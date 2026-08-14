/// A real gateway, a real socket, optionally a fault proxy and optionally a
/// lens on the frames — one call, torn down in the right order.
///
/// The wiring is `remote_state_man_test.dart:85-128`'s, lifted into `support/`
/// because three fault legs now need it and a fourth copy of it would be a
/// fourth place for the teardown order to be got wrong. Its argument is
/// unchanged and worth repeating: the server package's own `relayFixture` is
/// not reachable from here, because another package's `test/` directory is not
/// addressable by any `package:` URI, so the wiring is copied rather than
/// imported.
///
/// **What this is not.** `client_harness.dart`'s `relayFixture` is the
/// *contract-leg* fixture: it builds the whole 314-key page, wears the
/// contract's control surfaces, and is handed to `runStateManContract`. This
/// one is for a case that drives the client by hand — it takes the keys the
/// case names, hands back the plant and the proxy directly, and adds the one
/// thing the contract fixture has no business owning: a [FrameSeam] on the
/// dial.
///
/// **Teardown order, and why it is not `addTearDown` in declaration order.**
/// `addTearDown` runs last-registered-first, so the registrations below read
/// backwards from the order they execute in: plant, then proxy, then server,
/// then client — executing as client, server, proxy, plant. That is
/// `ws_harness.dart:359-384`'s order read from the inside out. The client goes
/// first because it owns the socket and both its timers and because it is the
/// only participant that *reconnects*: a server closed under a live client
/// leaves the client dialling a dead port for the rest of the run, and the
/// reconnect attempts land as noise on whichever case is unlucky enough to be
/// running then.
library;

import 'package:test/test.dart';
import 'package:tfc_relay_client/src/client_config.dart';
import 'package:tfc_relay_client/src/remote_state_man.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart';
import 'package:tfc_stateman_contract/channel_harness.dart';
import 'package:tfc_stateman_contract/faults.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';

import 'frame_seam.dart';

/// The client's timing knobs for a fault leg, with the deadline floor lowered
/// deliberately.
///
/// Lowering it is explicit and greppable for the reason `client_config.dart`
/// gives — nobody lowers it in production by accident. Here it buys deadlines
/// short enough that a link which stops answering fails a case inside that
/// case's own budget instead of stalling it, which is the whole mechanism the
/// truncated-write flip depends on.
ClientConfig faultClientConfig({
  Duration? write,
  Duration? control,
  Duration? freshness,
}) =>
    ClientConfig(
      controlDeadline: control ?? const Duration(milliseconds: 600),
      writeDeadline: write ?? const Duration(milliseconds: 600),
      freshnessDeadline: freshness ?? const Duration(seconds: 3),
      backoffBase: const Duration(milliseconds: 40),
      backoffCap: const Duration(seconds: 2),
      deadlineFloor: const Duration(milliseconds: 50),
    );

/// Everything one fault case drives, and the two things it reaches past the
/// client to pull.
final class FaultFixture {
  FaultFixture._(this.served, this.server, this._proxy, this.seam, this.client);

  /// The plant behind the gateway. Levers go straight here, never over the
  /// wire: `rpc_names.dart` keeps them off any method table a connected client
  /// can reach, and putting them on it would be an access-control change
  /// wearing a testing convenience (T-04-30).
  final FakeStateMan served;

  /// The gateway under test's peer. A real one — nothing here is scripted.
  final RelayServer server;

  final FaultProxy? _proxy;

  /// The lens on the inbound frames, and the injector F18 needs.
  final FrameSeam seam;

  /// The implementation under test.
  final RemoteStateMan client;

  /// The proxy in front of the gateway, when one was asked for.
  ///
  /// Throws rather than answering null, the way `ws_harness.dart:284-291` does:
  /// a case that forgot `withProxy: true` should be told that, not shown a
  /// null-check failure on a line that looks like a lever.
  FaultProxy get proxy {
    final proxy = _proxy;
    if (proxy == null) {
      throw StateError('this fixture was built without a proxy; pass '
          '`withProxy: true` to faultFixture before pulling a lever');
    }
    return proxy;
  }
}

/// Stands up plant, gateway, optional proxy and client, and wires the teardown.
///
/// [seed] runs against the plant **before** the gateway starts, which is not a
/// convenience: the gateway classifies every key on a subscribe against
/// `api.keys` (`session_handlers.dart:154-164`) and `FakeStateMan.keys` does
/// not name a tag until a value has been set on it, so a key seeded after the
/// client subscribed is rejected as a typo and is invisible for the rest of the
/// case no matter what the plant does with it. That is the trap
/// `client_harness.dart`'s `_PlantAddressSpace` documents from the other side.
Future<FaultFixture> faultFixture({
  Set<String> keys = const <String>{},
  ClientConfig? config,
  MessageCorruption? corrupt,
  bool withProxy = false,
  void Function(FakeStateMan plant)? seed,
}) async {
  final served = FakeStateMan();
  addTearDown(served.dispose);
  seed?.call(served);

  final server = RelayServer(
    api: served,
    config: ServerConfig(tick: ServerConfig.minTick),
    // Discards rather than `reportToStderr`: every case here provokes an error
    // on purpose, and a suite that printed a stack per provoked error would
    // train everyone to scroll past them (`ws_harness.dart:231-235`).
    onError: (_, __, ___) {},
  );
  await server.start();
  addTearDown(server.close);

  FaultProxy? proxy;
  if (withProxy) {
    proxy = FaultProxy(targetPort: server.port);
    await proxy.start();
    addTearDown(proxy.shutdown);
  }

  final seam = FrameSeam(corrupt: corrupt);
  final port = proxy?.port ?? server.port;
  final client = RemoteStateMan(
    uri: Uri.parse('ws://127.0.0.1:$port'),
    config: config ?? faultClientConfig(),
    keys: keys,
    dial: seam.dial,
  );
  addTearDown(client.dispose);

  return FaultFixture._(served, server, proxy, seam, client);
}

/// Polls [done] until it holds or [budget] runs out, and fails naming [what].
///
/// A poll rather than a stream wait because these cases assert a *state* the
/// client reached, and the transition that got it there is the supervisor's
/// business, tested in `reconnect_test.dart`. Copied from
/// `remote_state_man_test.dart:135-144` with its reason, because a second
/// almost-identical waiter is how two files start disagreeing about what
/// "recovered" means.
Future<void> until(
  String what,
  bool Function() done, {
  Duration budget = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(budget);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after ${budget.inMilliseconds} ms waiting for: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
