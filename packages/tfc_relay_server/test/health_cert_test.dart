@TestOn('vm')
@Tags(['ws'])

/// SEC-04: how many days are left on the gateway's certificate, as an ordinary
/// subscribable key.
///
/// **Health is a key, not a method**, and that is a recorded ruling in three
/// places (`state_man_api.dart:45-49`, `tfc_stateman_contract.dart:52-57`,
/// `api_surface_test.dart:48-51`): "There is no health method. `PIPE.*` keys
/// are subscribable like any plant tag … `listen('PIPE.connected')` is the
/// health API." So the thing under test here is a *producer*, not an endpoint,
/// and every case asks the gateway the way a mimic would.
///
/// ## What breaks in the plant without this file
///
/// The gateway's leaf is a one-year certificate (06-CONTEXT decision 3). On
/// the morning it lapses, every panel in the plant stops connecting at once —
/// `tls_test.dart`'s expired arm is what that looks like from the panel's
/// side, and it is deliberately loud. Loud on the day of the expiry is a
/// Saturday outage; loud thirty days earlier is a Tuesday ticket. This file is
/// what makes the second one possible. The threshold is AlarmMan's rather than
/// ours: the gateway ships the number.
///
/// ## Three answers, and two of them are not numbers
///
///  * A **good** certificate reads whole days, `notAfter - now`, truncated.
///  * An **expired** one reads a negative number, which is meaningful.
///  * An **unreadable** one reads [Quality.errorConfig] and **never 0** — a 0
///    reads as "expires today" and would send somebody to re-issue a
///    certificate that is fine, because a path was misspelled.
///
/// Certificates are minted at test time through `test/support/certs.dart` and
/// never committed: a committed leaf rots on a schedule nobody watches, and
/// the near-expiry one this file needs is a `notAfter:` argument against the
/// cached keypair (~15 ms), not a second keygen.
library;

import 'dart:async';
import 'dart:io';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/health/cert_health_state_man.dart';
import 'package:tfc_relay_server/src/relay_server.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_relay_server/src/tls/tls_config.dart';
import 'package:tfc_relay_server/src/ws_channel.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart' show within;
import 'package:web_socket_channel/io.dart';

import 'support/certs.dart';

/// The ceiling on any dial (trap 17: an unreachable address takes 75 s to fail
/// on macOS, and one such case on its own blows the three-minute lane budget
/// `handler_table_test.dart` owns).
const _dialBudget = Duration(seconds: 10);

/// A plant tag, so "the certificate key" can be told apart from "every key".
const _speedKey = 'ST101.CN01.MOT01.speed';

void main() {
  late TestCa ca;

  setUp(() {
    // Deliberately not a `setUpAll` in `support/certs.dart` (06-01 note 1):
    // `certKeyPairs()` is a lazy top-level cache, so the RSA is paid once for
    // the process and every `mintCa` after it is ~18 ms.
    ca = mintCa();
  });

  /// A gateway serving [plant], torn down whatever happens to it.
  ///
  /// `close()` is registered at acquisition rather than after a successful
  /// `start()` — 06-03's discipline, and what lets a case fail an assertion
  /// without leaking a listener or a socket.
  RelayServer buildServer({
    required FakeStateMan plant,
    TlsConfig? tls,
    int Function()? now,
  }) {
    final server = RelayServer(
      api: plant,
      config: ServerConfig(tick: ServerConfig.minTick, tls: tls),
      now: now,
      // Several cases here provoke refusals on purpose, and a suite that
      // printed a stack trace per provoked refusal trains everyone to scroll
      // past them (`ws_harness.dart:231-235`).
      onError: (_, __, ___) {},
    );
    addTearDown(() async {
      await server.close();
      await plant.dispose();
    });
    return server;
  }

  /// A gateway holding a leaf that expires [days] from now.
  ///
  /// Negative [days] mints an already-lapsed leaf; `notBefore` is moved back
  /// with it, because a `notBefore` later than `notAfter` is not a
  /// certificate.
  ({RelayServer server, FakeStateMan plant, CertFixture mounted}) gatewayFor(
      {int days = 365, int Function()? now}) {
    final plant = FakeStateMan();
    final at = DateTime.now().toUtc();
    final mounted = writeCertFixture(
      chainPem: mintLeaf(
        ca: ca,
        notBefore: at.subtract(const Duration(days: 400)),
        notAfter: at.add(Duration(days: days)),
      ),
      keyPem: leafKeyPem(),
      rootPem: ca.certPem,
    );
    final server = buildServer(
      plant: plant,
      tls: TlsConfig(chainPath: mounted.chainPath, keyPath: mounted.keyPath),
      now: now,
    );
    return (server: server, plant: plant, mounted: mounted);
  }

  /// A client pinning [rootPem] and nothing else — the panel's posture.
  HttpClient pinnedClient(String rootPem) {
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(rootPem.codeUnits);
    final client = HttpClient(context: context);
    addTearDown(() => client.close(force: true));
    return client;
  }

  /// A connected station on [server], past the handshake.
  ///
  /// [root] pins the gateway's CA and selects `wss`; omitted, the dial is
  /// plaintext `ws`, which is what the plaintext arm wants.
  Future<_Station> station(RelayServer server, {String? root}) async {
    final opened = server.sessions.opened.first;
    final ws = IOWebSocketChannel.connect(
      Uri.parse('${root == null ? 'ws' : 'wss'}://localhost:${server.port}'),
      customClient: root == null ? null : pinnedClient(root),
      connectTimeout: _dialBudget,
    );
    await ws.ready.timeout(_dialBudget);
    final base = wsChannel(ws);
    final peer = rpc.Client(StreamChannel<String>(base.stream, base.sink));
    final connected = _Station._(peer);
    unawaited(peer.listen().catchError((Object _) => null));
    addTearDown(() async {
      await peer.close().catchError((Object _) {});
      await ws.sink.close().catchError((Object _) {});
    });
    // Awaited before the hello so a case reading `sessions` cannot race the
    // accept — `ws_harness.dart:315` makes the same argument.
    await opened.timeout(const Duration(seconds: 5));
    await connected.hello();
    return connected;
  }

  group('the gateway\'s own certificate is a key', () {
    test('a TLS gateway serves its certificate\'s days to expiry as a key',
        () async {
      final gateway = gatewayFor();
      gateway.plant.setValue(_speedKey, 1450);
      await gateway.server.start();
      final panel = await station(gateway.server, root: ca.certPem);

      // The chain, read off the live session rather than rebuilt beside it:
      // **policy over health over source**. The policy decorator is per
      // session because identity is; the certificate belongs to the *server*,
      // so its overlay sits underneath and is shared — which is also what
      // lets Phase 8 delete this overlay without touching the policy.
      final session = gateway.server.sessions.sessions.single;
      expect(session.api.source, isA<CertHealthStateMan>(),
          reason: 'the health overlay has to sit under the per-session policy '
              'decorator. Chained the other way, `canSee` would filter a key '
              'list that does not yet contain the health key, and a future '
              'hiding policy could never reach it');
      expect((session.api.source as CertHealthStateMan).source,
          same(gateway.plant),
          reason: 'one overlay over the one shared source — a second source '
              'here would be a second place plant state lives');

      expect(session.api.keys, contains(certDaysToExpiryKey),
          reason: 'AlarmMan alarms on keys. A number the gateway knows and '
              'does not publish is a number nobody can alarm on, and the '
              'yearly re-issue goes back to being a Saturday outage');
      expect(session.api.keys, contains(_speedKey),
          reason: 'the key list is a union, not a replacement: a gateway that '
              'served its own health key *instead of* the plant would be a '
              'blank screen with a healthy badge on it');

      final answer = _asMap(
          await panel.request(Methods.read, {'key': certDaysToExpiryKey}));
      final wire = WireValue.fromJson(_asMap(answer['value']));
      expect(wire.q, Quality.good);
      expect(wire.v, isA<int>(),
          reason: 'whole days, so an alarm threshold is an integer comparison '
              'and not a duration somebody has to parse on the way in');
    });

    test('a plaintext gateway carries no certificate key', () async {
      // The property that keeps this plan safe against every existing suite:
      // ten bind/dial fixture sites construct a config with no TLS, and not
      // one of them may grow a sixth health key.
      final plant = FakeStateMan();
      plant.setValue(_speedKey, 1450);
      final server = buildServer(plant: plant);
      await server.start();
      final panel = await station(server);

      final session = server.sessions.sessions.single;
      expect(session.api.source, same(plant),
          reason: 'a plaintext gateway has no certificate, so there is '
              'nothing for an overlay to report on — and an overlay installed '
              'anyway is a new key on every fixture in the package');
      expect(session.api.keys, isNot(contains(certDaysToExpiryKey)),
          reason: 'a health key reading errorConfig forever on a gateway that '
              'was never given a certificate is a permanent false alarm, '
              'which is how an operator learns to ignore the indicator');
      expect(server.certHealth, isNull,
          reason: '`tls == null` is the whole condition: no overlay, no '
              'store, no file read, nothing to release');

      // And it is absent over the wire too, answered as a tag this gateway
      // does not serve rather than as an empty reading.
      final answer = _asMap(
          await panel.request(Methods.read, {'key': certDaysToExpiryKey}));
      expect(answer['rejected'], isNotNull,
          reason: 'absent means absent: a key present in the list but empty '
              'is a badge that renders and says nothing');
    });

    test('the certificate value is there before anything subscribes',
        () async {
      // The same argument `fake_state_man.dart:93-107` makes for the other
      // five health keys: seeded at construction "so a client can read them
      // before anything has happened — a health indicator that reads unknown
      // until the first fault is no indicator at all".
      final gateway = gatewayFor();
      await gateway.server.start();

      expect(gateway.server.sessions.sessionCount, 0,
          reason: 'the whole point of this case is that nothing has connected '
              'yet');
      final overlay = gateway.server.certHealth;
      expect(overlay, isNotNull);
      final value = overlay!.read(certDaysToExpiryKey);
      expect(value, isNotNull,
          reason: 'the first panel to subscribe must find a number in its '
              'snapshot, not a hole that fills in an hour');
      expect(value!.quality, Quality.good);
    });
  });

  group('the contract kit did not grow a key', () {
    test('the reference implementation still declares five health keys', () {
      // Deliberately *not* a sixth entry in `FakeStateMan.healthKeys`:
      // `freshness_contract.dart:60-64` reads the reserved prefix from there
      // and three drivers run the resulting checks, including legs that have
      // no certificate at all. The gateway is this key's producer; the
      // contract kit does not move.
      expect(FakeStateMan.healthKeys, hasLength(5),
          reason: 'a sixth entry would put $certDaysToExpiryKey on every '
              'contract leg in the repository, including the in-memory ones '
              'where there is no certificate to report on');
      expect(FakeStateMan.healthKeys, isNot(contains(certDaysToExpiryKey)));
    });

    test('the key lives in the reserved PIPE namespace', () {
      // Phase 8's HLTH-03 will reject a plant keymapping claiming a name
      // inside `PIPE.` (`freshness_contract.dart:60-64`), so this key has to
      // be on that reserved list from the start — and the name is what puts
      // it there.
      expect(certDaysToExpiryKey, startsWith(FakeStateMan.healthPrefix),
          reason: 'a health key outside the reserved namespace is a name a '
              'plant keymapping may legally claim, and the collision would '
              'surface as an alarm reading a conveyor speed in days');
    });
  });
}

/// One connected client, past the handshake.
final class _Station {
  _Station._(this._peer);

  final rpc.Client _peer;

  Future<void> hello() => request(
      Methods.hello,
      HelloParams(
        protocol: protocolVersion,
        supported: const [protocolVersion],
        client: const PeerInfo('panel-under-test', '0.1.0'),
      ).toJson());

  Future<Object?> request(String method, Object? params,
          {Duration budget = const Duration(seconds: 5)}) =>
      within(_peer.sendRequest(method, params),
          'a $method response over a real socket',
          budget: budget);
}

/// One decoded JSON object, cast where the wire hands back `Object?`.
Map<String, Object?> _asMap(Object? raw) =>
    (raw! as Map).cast<String, Object?>();
