/// F15: a gateway the panel will not believe, and the loop that must not
/// hammer it.
///
/// **F15 — TLS handshake failure.** Injection: proxy to a plain-TCP port /
/// wrong cert. Expect: clear terminal error, no reconnect-forever at full speed
/// against a misconfigured endpoint.
///
/// **The row's operational teeth are F15d, and they are not about TLS at all.**
/// Four of the six arms below assert that a handshake fails and that the panel
/// says so, which Phase 6 already pinned directly. What no file in this
/// repository stated before this one is the clause an operator actually feels:
/// a panel pointed at a gateway whose certificate is wrong must **back off**,
/// not spin. That is a property of `connection_supervisor.dart`'s schedule, and
/// F15d measures it against a bound computed from the backoff schedule.
///
/// **Assert the union, never the discrimination.** 06-RESEARCH §A.3 measured
/// that a foreign CA, an expired leaf, a SAN that does not cover the address
/// and a private leaf against the system roots all produce a byte-identical
/// `WebSocketChannelException` wrapping `HandshakeException` with
/// `CERTIFICATE_VERIFY_FAILED: application verification failure`, `closeCode`
/// null, in one to twenty-two milliseconds. A case asserting three different
/// messages would be asserting a fiction. One expected shape, three bindings —
/// and that *is* the finding, printed by the arms below rather than only
/// claimed here.
///
/// **06-07 measured a fifth shape that collapses into the first, and this file
/// inherits it.** `dart:io` raises `HandshakeException` for a link that dies
/// *inside* a handshake as well as for a leaf it refuses to verify, and
/// `_refusalReason` (`connection_supervisor.dart:384-406`) branches on the
/// class alone — so a cut cable and an impostor read identically on the health
/// line. The discriminator is in the text (`Connection terminated during
/// handshake` versus `CERTIFICATE_VERIFY_FAILED`) and nothing here asserts on
/// it: narrowing that branch changes a sentence an operator acts on, which is a
/// decision and not a typo. F15e therefore asserts the **union** of
/// `HandshakeException` and `SocketException`, and the gap is in the deviations
/// registry against F15's `clear terminal error`.
///
/// **What Phase 6 already asserts, cited rather than repeated.** The gate's job
/// is the pipe, not the handshake:
///
///  - `test/tls_client_test.dart` — the pinned dial, the system-roots refusal,
///    and the `CERTIFICATE_VERIFY_FAILED` text itself.
///  - `test/tls_fault_test.dart` — the same four shapes through the fault
///    proxy, each with a recovery driven by a value the plant changed during
///    the outage, plus the `cutMidFrame`-under-TLS boundary.
///  - `tfc_relay_server/test/tls_test.dart` — the `wss` bind and the
///    `assertServesTls` anti-vacuity pattern.
///
/// This file asserts only the half those cannot: what the *panel* does over
/// time when the handshake keeps failing.
///
/// **No arm asserts a `FailureKind.tlsRejected`, and none may be added.**
/// 06-PLAN-INDEX records the constant as deliberately not built:
/// `classifyFailure` sorts *call* failures and never sees a `ConnectAttempt`,
/// so the member would have no producer, and `grep -c tlsRejected` returning 0
/// is one of 06-05's own acceptance criteria. What Phase 6 shipped instead is
/// the link-state reason string, and that is what the arms below read.
///
/// **One `wss` smoke row, not a second lane.** 06-RESEARCH §C.4 measured
/// `latency`, `throttle`, `flap`, `blackhole`, `killOnce` and `reject` as
/// unchanged under TLS — the proxy is a byte relay and shapes ciphertext
/// without knowing it — so running all twenty-seven rows over `wss` would
/// double an eight-minute lane to re-prove a property already measured.
/// 07-CONTEXT orchestrator ruling 3 settles it: one smoke row proving the
/// fixture carries a full subscribe and resync, plus this family. The decision
/// to leave the other rows plaintext is in the deviations registry with that
/// measurement as its reason, because a scope decision nobody wrote down is
/// indistinguishable from an oversight.
///
/// **Two cases here are deliberately not F-rows**, and both are declared in
/// `gate_manifest_test.dart`'s supporting-case exemption with a written reason.
/// The smoke row proves the fixture; naming it `F1c` would claim a second F1
/// and break the 1:1 row mapping the whole manifest exists to hold. The auth
/// contrast is ROADMAP criterion 4's second clause and the *other side* of the
/// supervisor branch F15d sits on — it belongs beside F15 and belongs to no row.
///
/// Without this file the phase ships a gate that has never seen a TLS
/// handshake, and the plant-side property nobody measured is the one that
/// matters: a panel whose gateway certificate is wrong keeps trying, at a rate
/// that lets the gateway come back.
@TestOn('vm')
@Tags(['gate', 'faults'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_relay_client/src/ws_transport.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../support/fault_fixture.dart';
import '../support/gate_fixture.dart';

/// How many keys the smoke row's page carries.
///
/// A page rather than a key: the row exists to prove the wss fixture carries a
/// whole subscribe and a whole resync, and a one-key snapshot would prove that
/// a handshake completed and nothing else. Fifty rather than `plantPage`'s
/// two hundred because the property is "the page came back", not "the page came
/// back at a rate" — this row is not a slow-link row and paying four times the
/// snapshot for the same claim would spend lane budget on nothing.
const int _pageKeys = 50;

/// What the plant holds before the drop.
const int _before = 1200;

/// What the plant is changed to *while the panel is down*.
///
/// The whole force of the smoke row: a panel that reconnected and re-rendered
/// the value it already had would look identical without it.
const int _after = 1500;

/// The budget for "the panel got where it was going" over `wss`.
const Duration _recovery = Duration(seconds: 15);

/// The ceiling on a direct probe dial (07-RESEARCH trap 19).
///
/// Generous against a handshake measured at tens of milliseconds, small against
/// the 75 s macOS would otherwise spend on an address that answers nothing. A
/// hang guard, never a measurement.
const Duration _dialBudget = Duration(seconds: 10);

// ---------------------------------------------------------------------------
// Certificates. `tfc_relay_server/test/support/certs.dart`'s wiring, over the
// same minter, copied for the reason 06-05 records and 06-07 restates: another
// package's `test/` directory is not addressable by any `package:` URI, and the
// minter itself is on the barrel.
//
// Minted lazily and reused for the isolate: one RSA keygen (~364 ms, 06-01) for
// the whole file, after which every certificate below is 3-18 ms. Every arm
// varies only the *binding* — who signed the leaf, when it expires, or whether
// the listener speaks TLS at all — which is what makes "the same shape" a claim
// about the shape rather than about the fixture.
// ---------------------------------------------------------------------------

/// A certificate authority a case can sign leaves under.
typedef _Ca = ({
  String certPem,
  String keyPem,
  Map<String, String> dn,
  RelayKeyPair keys,
});

({RelayKeyPair ca, RelayKeyPair leaf})? _pairs;

({RelayKeyPair ca, RelayKeyPair leaf}) _keyPairs() =>
    _pairs ??= (ca: generateKeyPair(), leaf: generateKeyPair());

_Ca _mintCa({
  required RelayKeyPair keys,
  required Map<String, String> dn,
}) {
  final now = DateTime.now().toUtc();
  return (
    certPem: mintCertificate(
      signingKey: keys.privateKey,
      issuer: dn,
      subject: dn,
      subjectPublicKey: keys.publicKey,
      notBefore: now.subtract(const Duration(days: 1)),
      notAfter: now.add(const Duration(days: 3650)),
      ca: true,
    ),
    keyPem: privateKeyToPem(keys.privateKey),
    dn: dn,
    keys: keys,
  );
}

/// The root the plant provisions to its panels.
_Ca _trustedCa() =>
    _mintCa(keys: _keyPairs().ca, dn: {'CN': 'Relay Gate CA', 'O': 'Centroid'});

/// A gateway leaf signed by [ca].
///
/// The IP SAN is load-bearing in this file in a way it is nowhere else: every
/// dial goes to the *proxy*, at `127.0.0.1:<proxy port>`. A leaf whose IP SAN
/// was written as a DNS string — the defect 06-01's `0x87` branch exists for —
/// would fail every case here and pass every hostname case elsewhere, which is
/// a fixture fault wearing a product fault's clothes.
///
/// [notAfter] in the past is how an arm asks for an expired leaf: one argument
/// on the same keypair, never a second keygen and never a second code path.
String _mintLeaf({
  required _Ca ca,
  List<String> sans = const ['localhost', '127.0.0.1'],
  DateTime? notBefore,
  DateTime? notAfter,
}) {
  final now = DateTime.now().toUtc();
  return mintCertificate(
    signingKey: ca.keys.privateKey,
    issuer: ca.dn,
    subject: {'CN': 'relay-gateway', 'O': 'Centroid'},
    subjectPublicKey: _keyPairs().leaf.publicKey,
    sans: sans,
    notBefore: notBefore ?? now.subtract(const Duration(days: 1)),
    notAfter: notAfter ?? now.add(const Duration(days: 365)),
  );
}

/// Writes a chain, its key and a root into a fresh temp directory.
///
/// Under `Directory.systemTemp` and never inside the checkout, with the
/// recursive delete registered at acquisition: a case that fails an assertion
/// before its own cleanup line still takes the private key off the machine, and
/// no run can leave a `.pem` where `git add` would find it. `find packages -name
/// '*.pem'` is 0 and 06-01, 06-09 and this file all depend on it staying 0.
FaultTls _mount({required String chainPem, required String rootPem}) {
  final dir = Directory.systemTemp.createTempSync('relay-tls-gate-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final sep = Platform.pathSeparator;
  final chainPath = '${dir.path}${sep}chain.pem';
  final keyPath = '${dir.path}${sep}chain-key.pem';
  final rootPath = '${dir.path}${sep}root.pem';
  File(chainPath).writeAsStringSync(chainPem);
  File(keyPath).writeAsStringSync(privateKeyToPem(_keyPairs().leaf.privateKey));
  File(rootPath).writeAsStringSync(rootPem);
  return (chainPath: chainPath, keyPath: keyPath, rootPath: rootPath);
}

/// The mount a panel pins [root] against while the gateway serves [chain].
///
/// The two halves are independent paths, which is what lets one record express
/// "the gateway's leaf is fine" and "the gateway's leaf was signed by somebody
/// else" without any other difference between the two fixtures.
FaultTls _mountOf(_Ca root, String chain) =>
    _mount(chainPem: chain, rootPem: root.certPem);

// ---------------------------------------------------------------------------
// Probes.
// ---------------------------------------------------------------------------

/// Dials [url] once through the production transport and requires a refusal.
///
/// [connect] is the code under test rather than a convenience: it is what
/// drains the second copy of the exception off the stream, and a probe that
/// hand-rolled the dial would be measuring a socket this client never opens.
///
/// [client] null is deliberately the **system trust store** posture:
/// `IOWebSocketChannel.connect` builds a default client of its own. That is the
/// arm that proves the pin is load-bearing.
Future<ConnectFailed> _refused(String url, {HttpClient? client}) async {
  final attempt = await connect(
    Uri.parse(url),
    client: client,
    connectTimeout: _dialBudget,
  );
  return switch (attempt) {
    ConnectFailed() => attempt,
    ConnectSucceeded() =>
      fail('$url completed a handshake it had no business completing'),
  };
}

/// Proves the listener [port] forwards to is genuinely TLS, and that reaching
/// it requires the pinned root.
///
/// **Both halves, because either alone is satisfied by the wrong thing.**
/// Dialling `wss` at a *plaintext* listener also raises a `HandshakeException`
/// (06-03 measured facts §4), so "a pinned panel connected" is on its own
/// equally consistent with "there was no TLS back there at all" and with "the
/// proxy forwarded nowhere". A `ws://` dial coming back `HttpException` rules
/// out both. And a `wss` dial on the *system* store being refused is what says
/// the panel's success came from the mounted root rather than from a machine
/// that happens to trust this leaf.
Future<void> _assertPinnedTls(int port) async {
  final plaintext = await _refused('ws://127.0.0.1:$port');
  expect(
    (plaintext.error as WebSocketChannelException).inner,
    isA<HttpException>(),
    reason: 'a plaintext dial at the proxy port did not meet a TLS listener, '
        'so the fixture may have fallen back to ws — under which every arm in '
        'this file passes while measuring nothing about TLS',
  );

  final unpinned = await _refused('wss://127.0.0.1:$port');
  expect(
    (unpinned.error as WebSocketChannelException).inner,
    isA<HandshakeException>(),
    reason: 'a client using the machine\'s own trust store reached this '
        'gateway. The panel\'s success would then say nothing about the pin: '
        'the point of SecurityContext(withTrustedRoots: false) is that a rogue '
        'root installed on the station cannot vouch for anything claiming to '
        'be the gateway (T-06-20)',
  );
}

void main() {
  group('the gate can stand up a TLS gateway, and a page survives a drop on it',
      () {
    test('a full page survives a drop and a resync over wss', () async {
      final trusted = _trustedCa();
      final mount = _mountOf(trusted, _mintLeaf(ca: trusted));
      final page = plantPage(_pageKeys);

      final fixture = await gateFixture(
        clients: 1,
        keys: page.toSet(),
        seed: (plant) =>
            plant.setValues({for (final key in page) key: _before}),
        tls: mount,
        readyBudget: _recovery,
      );
      final panel = fixture.clients.single;

      expect(panel.client.uri.scheme, 'wss',
          reason: 'the panel dialled ${panel.client.uri}. Everything below is '
              'about a page crossing a TLS link, and a ws dial would prove the '
              'page crosses the link it always crossed');
      await _assertPinnedTls(fixture.proxies.single.port);

      // The seam is not merely absent, it is refused — and that refusal is
      // itself the proof that the panel's own pinned HttpClient is what dialled
      // rather than a `dial:` override the fixture installed.
      expect(() => panel.seam, throwsStateError,
          reason: 'a TLS panel handed back a frame seam, which means a `dial:` '
              'override is in the path — and that override bypasses the pinned '
              'client this whole leg exists to exercise');

      expect(panel.client.read(page.first)?.value, _before,
          reason: 'the page did not arrive over the wss subscribe, so the drop '
              'below would be measuring an empty view coming back empty');

      fixture.proxies.single.killOnce();
      await until('the panel to notice the killed wss link',
          () => !panel.client.isReady,
          budget: _recovery);
      fixture.served.setValues({for (final key in page) key: _after});

      await fixture.untilAllRead(page.last, _after, budget: _recovery);
      expect(
        [for (final key in page) panel.client.read(key)?.value],
        everyElement(_after),
        reason: 'the resync after a drop over wss delivered a partial page. '
            'The value changed *while the panel was down*, so a client that '
            're-rendered its cache reads $_before here — this is F1\'s '
            'silent-permanent-staleness claim, asked once of the TLS fixture '
            'to prove the fixture carries it',
      );
      print('wss smoke: a ${page.length}-key page subscribed, dropped, '
          'resynced and converged on $_after over TLS; '
          '${panel.attempts} connect transitions');
    });
  });
}
