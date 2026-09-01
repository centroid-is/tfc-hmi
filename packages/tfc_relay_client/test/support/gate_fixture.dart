/// N real panels on one gateway, a gateway that can be restarted underneath
/// them, and the counters that prove the numbers above are being measured
/// rather than assumed.
///
/// **Why this is a second fixture and not a parameter on the first.**
/// `fault_fixture.dart` builds exactly one client, and its teardown order is
/// load-bearing prose: plant, gateway, proxy and panel are released in an order
/// that is argued in that file's library doc and nowhere else. Adding an `n:`
/// to it would make that order an *inherited* property — a reader of a herd
/// case would have to open the other file to find out what is torn down when,
/// and a change to either lifetime would silently change the other's. The two
/// fixtures have genuinely different lifetimes (that one's gateway is built
/// once and never replaced; this one's is closed and rebound mid-case), so the
/// wiring is **copied with its reasons restated** rather than shared. That is
/// 07-RESEARCH trap 16's instruction, and the cost — two places that must not
/// drift — is the price of the order staying readable in one place.
///
/// **Teardown order, and why it is registered backwards.** `addTearDown` runs
/// last-registered-first, so the registrations below read backwards from the
/// order they execute in: plant, then proxies, then gateway, then every client
/// — executing as **all clients, then the gateway, then the proxies, then the
/// plant**. That is `ws_harness.dart:359-384`'s order, which
/// `client_harness.dart:330-340` restates: the client goes first because it
/// owns the socket and both its timers and because it is the only participant
/// that *reconnects* (a gateway closed under a live panel leaves that panel
/// dialling a dead port for the rest of the run, and the attempts land as
/// noise on whichever case is unlucky enough to be running then); the proxy
/// cannot go first because shutting it down destroys both halves of every pair
/// it carries; and the plant goes last because its freshness watchdog must
/// outlive anything still draining through it.
///
/// With N clients the rule is unchanged and the *whole* client group goes
/// first, which is why each client registers its own teardown in the loop that
/// builds it rather than one teardown closing the list — a single closure would
/// still be one registration, and one registration cannot be reordered against
/// the gateway's if a later reader adds something between them.
///
/// **The listen port is fixed from the first bind, not chosen by us.**
/// `FaultProxy.targetPort` is `final` (`fault_proxy.dart:149`), a Phase 2
/// artifact guarded by `proxy_core_test.dart` and `mode_integrity_test.dart`,
/// so a gateway that is restarted behind a proxy must come back on the port it
/// left. 07-RESEARCH §A.3 argues at length that making `targetPort` mutable is
/// the strictly worse route, and Phase 6 landed the field this needs:
/// `ServerConfig.port`, defaulting to `0`.
///
/// So the first gateway binds `port: 0` — the OS picks — and every replacement
/// binds `ServerConfig(port: <that number>)`. The port is fixed for the
/// fixture's whole life, which is all the proxy requires, and it is a port the
/// kernel has just confirmed is free rather than a number this file guessed
/// and another process might own. See [GateFixture.restartGateway] for the
/// rebind and its retry.
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_relay_client/src/client_config.dart';
import 'package:tfc_relay_client/src/remote_state_man.dart';
import 'package:tfc_relay_client/src/ws_transport.dart';
// `RelayErrorHandler` is not on the server package's public surface — the
// barrel exports the configuration types and not the reporter — so it is
// reached through `src/`, the way `error_reporter_test.dart:21` reaches it.
import 'package:tfc_relay_server/src/error_reporter.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart';
import 'package:tfc_stateman_contract/faults.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';

import 'fault_fixture.dart' show faultClientConfig, until;
import 'frame_seam.dart';

/// How many panels a herd holds unless a case says otherwise.
///
/// **Twenty, and deliberately not fifty.** 07-RESEARCH §C.2: twenty real
/// panels cost about eighty descriptors in this process — panel socket, the
/// proxy's accepted socket, the proxy's upstream socket, the gateway's accepted
/// socket, per client — against a 256+ default on macOS and 1024 on Linux, and
/// the gate lane runs at `concurrency: 1` so no neighbouring suite is competing
/// for them. Fifty buys no additional evidence about the property (the
/// mechanism that spreads a herd is per-client jitter, which twenty samples
/// measure as well as fifty) and costs two and a half times the descriptors and
/// the wall clock, which is where flakes come from.
///
/// [herdSize] reads `RELAY_HERD_N` so a larger arm can be run by hand without
/// the default moving. It is the `FAULT_LANE_BUDGET` shape 07-CONTEXT ruling 2
/// established: short in every CI run, long behind an environment flag.
const int defaultHerdSize = 20;

/// The environment variable that overrides [defaultHerdSize].
const String herdSizeEnvVar = 'RELAY_HERD_N';

/// How many panels this run's herd holds.
int get herdSize {
  final override = Platform.environment[herdSizeEnvVar];
  if (override == null || override.isEmpty) return defaultHerdSize;
  final parsed = int.tryParse(override);
  if (parsed == null || parsed <= 0) {
    throw ArgumentError('$herdSizeEnvVar is "$override", which is not a '
        'positive integer. A herd size that failed to parse would silently '
        'become the default and the run would report a number nobody asked '
        'for');
  }
  return parsed;
}

/// The close a *client* observed.
///
/// The naming rule is `ws_harness.dart:73-90`'s and `client_harness.dart`
/// copies it for the same reason: a client observation says `closeCode`, the
/// gateway's own record says `sentCloseCode`, and that one character's case is
/// what lets the phase's text sweep tell intention from observation. Both
/// fields are null while the socket is open, which is the ordinary reading for
/// a panel that was never evicted.
typedef ObservedClose = ({int? closeCode, String? closeReason});

/// A mutable holder for the gateway, so the teardown closure registered before
/// the fixture object exists still closes whichever gateway is current.
///
/// A restart replaces the `RelayServer`, and the teardown has to release the
/// replacement rather than the one it was registered against — otherwise every
/// case that restarts leaks a listener and its tick engine into the rest of the
/// run, which is the shape a leak counter would then report against the *next*
/// case.
final class _GatewaySlot {
  _GatewaySlot(this.server);

  RelayServer server;
}

/// One panel of the herd: its client, its lens, its proxy, and what it saw.
final class GateClient {
  GateClient._(this.index, this.client, this.seam, this.proxy);

  /// Its position in the herd, for the messages a herd case has to print.
  final int index;

  /// The implementation under test.
  final RemoteStateMan client;

  /// The lens on this panel's inbound frames.
  ///
  /// **One seam per client, and it cannot be otherwise.** A `FrameSeam` holds
  /// the dial's `_dials` counter and the `_toClient` controller for the socket
  /// it is currently serving (`frame_seam.dart:96-99`), so a seam shared by two
  /// panels would count both panels' dials as one number and would deliver an
  /// injection to whichever of them dialled last.
  final FrameSeam seam;

  /// The fault proxy this panel dials through.
  ///
  /// Shared with the rest of the herd unless the fixture was built
  /// `proxyPerClient: true`, which is what F12 needs — see [gateFixture].
  final FaultProxy proxy;

  /// The close this panel's socket has observed, both fields null while it is
  /// open.
  ///
  /// Read off the most recent attempt the dial produced, which is the only
  /// close worth asserting on for a close the gateway initiated
  /// (`web_socket_channel` #1698: `closeCode` is null after a self-initiated
  /// close on every platform).
  ObservedClose get observedClose =>
      (closeCode: _last?.closeCode, closeReason: _last?.closeReason);

  ConnectAttempt? _last;
}

/// Everything a herd case drives.
final class GateFixture {
  GateFixture._(
    this.served,
    this._slot,
    this.port,
    this.proxies,
    this.clients,
    this._keys,
  );

  /// The plant behind the gateway. Levers go straight here, never over the
  /// wire: `rpc_names.dart` keeps them off any method table a connected client
  /// can reach, and putting them on it would be an access-control change
  /// wearing a testing convenience (T-04-30).
  final FakeStateMan served;

  final _GatewaySlot _slot;

  /// The gateway under test's peer, right now.
  ///
  /// A getter and not a field: [restartGateway] replaces the object, and a case
  /// that captured the old one would be reading a closed gateway's registry
  /// and finding it reassuringly empty.
  RelayServer get server => _slot.server;

  /// The port the gateway binds, fixed for this fixture's whole life.
  ///
  /// Chosen by the kernel at the first bind and then pinned through
  /// `ServerConfig.port` on every replacement — see the library doc.
  final int port;

  /// The proxies in front of the gateway: one, or one per client.
  final List<FaultProxy> proxies;

  /// The panels, in the order they were built.
  final List<GateClient> clients;

  final Set<String> _keys;

  /// The one proxy the whole herd shares.
  ///
  /// Throws rather than answering the first of several, the way
  /// `fault_fixture.dart:164-171` throws for a fixture built without one: a
  /// case that pulled a lever on `proxies.first` believing it was pulling it on
  /// the link would be throttling one panel and asserting about all of them,
  /// which is the exact confusion F12's doc has to rule out.
  FaultProxy get proxy {
    if (proxies.length != 1) {
      throw StateError('this fixture was built with ${proxies.length} proxies '
          '(one per client), so there is no single link to pull a lever on. '
          'Reach for `clients[i].proxy` and say in the case which panel is '
          'being shaped');
    }
    return proxies.single;
  }

  /// How many panels the gateway is holding.
  int get sessionCount => server.sessions.sessionCount;

  /// How many sessions the gateway holds that have connected but **not** yet
  /// completed `hello`.
  ///
  /// A slot held between accept and handshake is a resource nobody has
  /// authenticated for (06-RESEARCH §H.4). `RelaySession.sessionId` is minted
  /// by the `hello` handler and is null until then
  /// (`relay_session.dart:430-431`), which is the same predicate
  /// `RelayServer.reloadTokens`' sweep uses to skip a pre-hello session, so
  /// this counts what the gateway itself calls unauthenticated.
  ///
  /// **Reported, never enforced.** 07-CONTEXT orchestrator ruling 4: Phase 7
  /// measures the emergent bound and `maxSessions` is a later decision.
  int get unauthenticatedSlots =>
      server.sessions.sessions.where((s) => s.sessionId == null).length;

  /// Every close the gateway *initiated*, as it recorded them.
  ///
  /// This is the eviction question, and it is asked of the gateway rather than
  /// of the panels on purpose. A panel whose socket the proxy reset observes
  /// 1002 or 1006 — a fault the case injected — while a panel the gateway threw
  /// off observes a 4000-4999 code the gateway chose (`CloseCodes`). Only the
  /// second is an eviction, and only the gateway's ledger can tell them apart.
  ///
  /// Read it **before** teardown: `RelayServer.close` drains every live session
  /// with `serverDraining` (4002), so a ledger read afterwards names every
  /// panel as evicted by a gateway that was merely shutting down.
  List<ConnectionClose> get evictions => [
        for (final close in server.closeLedger)
          if (close.serverCloseCode != null) close,
      ];

  /// Every panel's observed close, in herd order.
  List<ObservedClose> get observedCloses =>
      [for (final one in clients) one.observedClose];

  /// Closes the gateway and starts a replacement on the **same port**, behind
  /// the same proxies, and returns how many rebinds it took.
  ///
  /// **The retry is named, and it is named because the probe only covered one
  /// platform.** 07-RESEARCH §A.3 executed the same-port rebind with twenty
  /// connections in `TIME_WAIT` and measured **0 ms on macOS** — `shelf`'s
  /// `serve` sets `SO_REUSEADDR`, and a listening socket in `TIME_WAIT` does
  /// not hold the port against it. Linux behaves the same way. **Windows was
  /// not measured**, and Windows is the platform where `SO_REUSEADDR` means
  /// something else entirely, so the bind is retried with a short backoff and
  /// the failure message says how many times it tried and on which port —
  /// a fixture that failed here with a bare `SocketException` would send the
  /// next reader looking for a bug in the gateway.
  ///
  /// [downtime] is spent between the close and the first rebind. Zero is the
  /// fastest restart the process can do and it is what F10 wants; a herd wants
  /// a number, because a gateway that is back before anybody's first retry
  /// never asks the backoff to spread anything and the row would measure an
  /// empty mechanism.
  ///
  /// The returned count is expected to be **0** on macOS and Linux. A case that
  /// prints it is recording the platform's answer rather than trusting this
  /// paragraph.
  Future<int> restartGateway({
    Duration downtime = Duration.zero,
    int attempts = 5,
  }) async {
    await _slot.server.close();
    if (downtime > Duration.zero) await Future<void>.delayed(downtime);

    var retries = 0;
    while (true) {
      final replacement = _buildGateway(served, port);
      try {
        await replacement.start();
        _slot.server = replacement;
        return retries;
      } on SocketException catch (error) {
        // Nothing to close: `RelayServer.start` binds first and only builds the
        // tick engine afterwards (`relay_server.dart:396-408`), so a bind that
        // threw leaves no listener and no timer behind.
        retries++;
        if (retries >= attempts) {
          fail('the replacement gateway could not bind port $port after '
              '$retries retries with a backoff between them: $error. The '
              'rebind was measured at 0 retries on macOS with twenty '
              'connections in TIME_WAIT (07-RESEARCH §A.3) and Windows was '
              'never measured, so this is the platform difference that probe '
              'left open — not a fault in the gateway');
        }
        await Future<void>.delayed(Duration(milliseconds: 50 * retries));
      }
    }
  }

  /// Waits until every panel in the herd reads [expected] for [key].
  ///
  /// **One budget for the whole herd, not one per panel.** A per-panel wait
  /// would let a straggler be averaged away: nineteen panels back in 200 ms and
  /// one back in nine seconds is exactly the starvation F11 forbids, and a loop
  /// of per-panel `until()` calls reports it as twenty passes. One window over
  /// the whole list fails naming the panels that did not make it.
  ///
  /// Returns each panel's convergence instant, in milliseconds from the call,
  /// in herd order — which is the fairness measurement F11 bands.
  Future<List<int>> untilAllRead(
    String key,
    Object? expected, {
    Duration budget = const Duration(seconds: 20),
  }) async {
    final started = Stopwatch()..start();
    final at = List<int?>.filled(clients.length, null);
    await until(
      'all ${clients.length} panels to read $expected for $key',
      () {
        for (var i = 0; i < clients.length; i++) {
          if (at[i] != null) continue;
          if (clients[i].client.read(key)?.value == expected) {
            at[i] = started.elapsedMilliseconds;
          }
        }
        return at.every((instant) => instant != null);
      },
      budget: budget,
    );
    return [for (final instant in at) instant!];
  }

  /// The keys this fixture's panels subscribed to.
  Set<String> get keys => _keys;
}

/// Builds a gateway on [port] against [plant], with this package's fault-leg
/// settings.
///
/// One function so the first gateway and every replacement are built the same
/// way. A replacement that differed from the original in any respect would make
/// "the restarted gateway behaves like the original" a claim about this file.
RelayServer _buildGateway(
  FakeStateMan plant,
  int port, {
  RelayErrorHandler? onError,
}) =>
    RelayServer(
      api: plant,
      config: ServerConfig(tick: ServerConfig.minTick, port: port),
      // Discards rather than `reportToStderr`, for `fault_fixture.dart:259-263`'s
      // reason: every case in this directory provokes an error on purpose, and
      // a suite that printed a stack per provoked error would train everyone to
      // scroll past them.
      onError: onError ?? (_, __, ___) {},
    );

/// Stands up a plant, a gateway on a fixed port, one or N proxies, and N real
/// panels — and wires the teardown so the whole herd is released in the order
/// the library doc argues for.
///
/// [seed] runs against the plant **before** the gateway starts, which is not a
/// convenience: the gateway classifies every key on a subscribe against
/// `api.keys` (`session_handlers.dart:154-164`) and `FakeStateMan.keys` does
/// not name a tag until a value has been set on it, so a key seeded after a
/// panel subscribed is rejected as a typo and is invisible for the rest of the
/// case no matter what the plant does with it.
///
/// [proxyPerClient] gives every panel its own proxy in front of the one
/// gateway. **F12 cannot be expressed without it.** `throttleBytesPerSec` is a
/// property of the proxy and reaches every pair it carries
/// (`fault_proxy.dart:513-517`), so "throttle one of two panels sharing a
/// proxy" is not a thing this instrument can do — a case that thought it had
/// done that would be throttling both and then asserting that neither was
/// affected, which is a green that measures nothing. One proxy per panel is the
/// honest arrangement and it changes nothing else: all of them target the same
/// gateway port, so the panels are still on one gateway.
///
/// [waitForReady] leaves every panel subscribed and holding a value for every
/// key before this returns. Off is for a case that wants to watch the
/// establishment itself.
Future<GateFixture> gateFixture({
  int? clients,
  Set<String> keys = const <String>{},
  void Function(FakeStateMan plant)? seed,
  bool proxyPerClient = false,
  ClientConfig? config,
  bool waitForReady = true,
  Duration readyBudget = const Duration(seconds: 20),
}) async {
  final n = clients ?? herdSize;
  if (n <= 0) {
    throw ArgumentError('a herd of $n panels is not a herd; pass a positive '
        'count or leave it to default to $defaultHerdSize');
  }
  final clientConfig = config ?? faultClientConfig();

  final served = FakeStateMan();
  addTearDown(served.dispose);
  seed?.call(served);

  // Port 0: the kernel picks, and the number it picks is what every
  // replacement binds. See the library doc on why the port is fixed from the
  // first bind rather than chosen here.
  final first = _buildGateway(served, 0);
  await first.start();
  final slot = _GatewaySlot(first);
  final port = first.port;

  final proxies = <FaultProxy>[];
  for (var i = 0; i < (proxyPerClient ? n : 1); i++) {
    final proxy = FaultProxy(targetPort: port);
    await proxy.start();
    proxies.add(proxy);
  }
  addTearDown(() => slot.server.close());
  for (final proxy in proxies) {
    addTearDown(proxy.shutdown);
  }

  final herd = <GateClient>[];
  for (var i = 0; i < n; i++) {
    final proxy = proxyPerClient ? proxies[i] : proxies.single;
    final seam = FrameSeam(connectTimeout: clientConfig.connectTimeout);
    late final GateClient one;
    final client = RemoteStateMan(
      uri: Uri.parse('ws://127.0.0.1:${proxy.port}'),
      config: clientConfig,
      keys: keys,
      // The seam's dial, with the attempt kept so the panel can be asked what
      // close it observed. `FrameSeam` does not retain it — it has no reason
      // to, and giving it one would put a second lifetime in a file five other
      // waves already depend on.
      dial: (uri) async {
        final attempt = await seam.dial(uri);
        one._last = attempt;
        return attempt;
      },
    );
    one = GateClient._(i, client, seam, proxy);
    herd.add(one);
    addTearDown(client.dispose);
  }

  final fixture = GateFixture._(served, slot, port, proxies, herd, keys);

  if (waitForReady) {
    await until(
      'all $n panels to establish and hold a value for every one of '
      '${keys.length} keys',
      () => herd.every((one) =>
          one.client.isReady &&
          keys.every((key) => one.client.read(key) != null)),
      budget: readyBudget,
    );
  }
  return fixture;
}

/// Long enough for the kernel to have caught up with a close before a
/// descriptor count is believed.
///
/// `tfc_stateman_contract/test/faults/fd_count_test.dart:50-60`'s number and
/// its reason, restated because that file is not importable from here: there is
/// no event for "the fd table has settled" — the kernel does not announce it —
/// so a count taken immediately after a teardown reads a half-settled table and
/// blames the code under test.
const Duration fdSettle = Duration(milliseconds: 400);

/// Polls [openSocketCount] until it is back within [tolerance] of [baseline],
/// or [budget] runs out, and returns the last reading.
///
/// A window rather than one reading after a sleep, for the same reason every
/// other wall-clock property in this directory is a window: `destroy()` returns
/// before the descriptor closes, and how long "before" is depends on the
/// runner.
Future<int> untilSocketsSettle(
  int baseline, {
  int tolerance = 0,
  Duration budget = const Duration(seconds: 10),
}) async {
  await Future<void>.delayed(fdSettle);
  final deadline = DateTime.now().add(budget);
  var last = openSocketCount();
  while (last > baseline + tolerance && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    last = openSocketCount();
  }
  return last;
}
