@TestOn('vm')
@Tags(['ws'])

/// SEC-01's second half: no key material is reachable from the gateway's
/// configuration.
///
/// The requirement is "a test asserts no key material can be read from config
/// **or preferences**", and it has two halves in two places on purpose:
///
///  * **Preferences — already green, cited rather than copied.**
///    `packages/tfc_stateman_contract/test/api_surface_test.dart:229-243`
///    reflects over the five wire interfaces and asserts no member declares a
///    parameter named `secret`. The concrete `Preferences` class has exactly
///    such a parameter, routing the read to secure storage, and mirroring it
///    onto the wire would turn one client-supplied boolean into remote access
///    to the secure store. Re-implementing that here would mean two places to
///    update and one of them going stale; this plan adds no interface member,
///    and that file's count of 49 is the proof.
///  * **Config — here.** Two *structural* pins on the field types plus a
///    content sweep over everything a config can be rendered into.
///
/// The structural pins are the half that survives a future edit. The content
/// sweep asks "does the key leak today"; the pins ask "can it ever" — a
/// `TlsConfig` whose fields are all `String` cannot hold PEM bytes, and a
/// `ServerConfig` that declares no `SecurityContext` cannot hand one to a
/// logger. Both start green, which is why the evidence for them is the
/// sabotage arms recorded in the SUMMARY and not a manufactured red: leaking a
/// key from production code to watch a test fail is not a red worth having.
///
/// `dart:mirrors` reflects the real type rather than its source text, and it
/// is available under `dart test` but never under `flutter test` — one more
/// reason this package is pure Dart.
///
/// Without this file, a private key in a config dump is a private key in a
/// support ticket, and nothing stops the edit that puts it there.
library;

import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/relay_server.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_relay_server/src/tls/tls_config.dart';
import 'package:tfc_relay_server/src/ws_channel.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';
import 'package:web_socket_channel/io.dart';

import 'support/certs.dart';

const _dialBudget = Duration(seconds: 10);
const _requestBudget = Duration(seconds: 5);

/// The non-static instance fields [type] declares, by name.
Map<String, VariableMirror> _fieldsOf(Type type) {
  final mirror = reflectClass(type);
  return {
    for (final declaration in mirror.declarations.values)
      if (declaration is VariableMirror && !declaration.isStatic)
        MirrorSystem.getName(declaration.simpleName): declaration,
  };
}

/// The name of [field]'s declared type, as mirrors reports it.
String _typeName(VariableMirror field) =>
    MirrorSystem.getName(field.type.simpleName);

/// Everything an object's fields render to, plus the object itself.
///
/// Walked rather than listed: a field added tomorrow is swept the day it is
/// added, which is the only way a sweep like this stays true.
List<String> _renderings(Object instance) {
  final mirror = reflect(instance);
  return [
    instance.toString(),
    for (final name in _fieldsOf(instance.runtimeType).keys)
      '${mirror.getField(Symbol(name)).reflectee}',
  ];
}

void main() {
  late TestCa ca;
  late CertFixture mounted;
  late String keyPem;

  /// Forty characters out of the middle of the key's base64 body.
  ///
  /// Long enough that a collision is not a thing that happens, and taken from
  /// the *middle* because a leak that stripped the PEM armour would still
  /// carry this.
  late String keyFingerprint;

  setUp(() {
    ca = mintCa();
    mounted = writeCertFixture(
      chainPem: mintLeaf(ca: ca),
      keyPem: leafKeyPem(),
      rootPem: ca.certPem,
    );
    keyPem = File(mounted.keyPath).readAsStringSync();

    final body = keyPem
        .split('\n')
        .where((line) => !line.startsWith('-----') && line.trim().isNotEmpty)
        .join();
    keyFingerprint = body.substring(body.length ~/ 2, body.length ~/ 2 + 40);
    expect(keyFingerprint, hasLength(40),
        reason: 'the whole content sweep is this needle; a short one would '
            'make every sweep below pass for the wrong reason');
  });

  group('a config cannot be rendered into key material', () {
    late RelayServer server;
    late FakeStateMan served;
    late ServerConfig config;
    late TlsConfig tls;

    setUp(() async {
      tls = TlsConfig(chainPath: mounted.chainPath, keyPath: mounted.keyPath);
      config = ServerConfig(tick: ServerConfig.minTick, tls: tls);
      served = FakeStateMan()..setValue('MOTOR01.speed', 12.5);
      server = RelayServer(api: served, config: config, onError: (_, __, ___) {});
      addTearDown(() async {
        await server.close();
        await served.dispose();
      });
      await server.start();
    });

    /// Fails the case if [where] carries the key in either form.
    void assertNoKeyIn(String what, Iterable<String> where) {
      for (final rendering in where) {
        expect(rendering, isNot(contains('BEGIN')),
            reason: 'SEC-01: $what carries PEM armour. A private key in a '
                'config dump is a private key in a support ticket, and the '
                'gateway is the only holder of the identity every panel on '
                'the plant trusts');
        expect(rendering, isNot(contains(keyFingerprint)),
            reason: 'SEC-01: $what carries the key\'s base64 body. Stripping '
                'the armour does not make key material safe to render');
      }
    }

    test('the config and its fields render no key material', () {
      assertNoKeyIn('ServerConfig', _renderings(config));
      assertNoKeyIn('TlsConfig', _renderings(tls));
    });

    test('the paths are rendered, which is what makes the sweep meaningful',
        () {
      // Anti-vacuity. If the config rendered nothing at all about TLS, every
      // assertion above would pass while proving nothing.
      expect(_renderings(tls).join('\n'), contains(mounted.keyPath),
          reason: 'the config is supposed to carry the *path* — a sweep over '
              'an object that says nothing is not a sweep');
    });

    test('the hello capabilities carry no key material', () async {
      final client = HttpClient(
          context: SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificatesBytes(ca.certPem.codeUnits));
      addTearDown(() => client.close(force: true));

      final ws = IOWebSocketChannel.connect(
        Uri.parse('wss://localhost:${server.port}'),
        customClient: client,
        connectTimeout: _dialBudget,
      );
      addTearDown(() => ws.sink.close().catchError((Object _) {}));
      await ws.ready.timeout(_dialBudget);

      final peer = rpc.Client(wsChannel(ws));
      addTearDown(() => peer.close().catchError((Object _) {}));
      unawaited(peer.listen().catchError((Object _) => null));

      final raw = await peer
          .sendRequest(
              Methods.hello,
              HelloParams(
                protocol: protocolVersion,
                supported: const [protocolVersion],
                client: const PeerInfo('panel-under-test', '0.1.0'),
              ).toJson())
          .timeout(_requestBudget);
      final hello = HelloResult.fromJson((raw as Map).cast<String, Object?>());

      expect(hello.capabilities, isNotEmpty,
          reason: 'an empty capabilities map would make the sweep below pass '
              'without looking at anything');
      assertNoKeyIn('the hello capabilities', ['${hello.capabilities}']);
    });

    test('nothing reachable through keys and read carries key material', () {
      expect(served.keys, isNotEmpty,
          reason: 'a source serving no keys cannot leak one through them; the '
              'sweep needs something to walk');
      assertNoKeyIn('a served key or its value', [
        served.keys.join('\n'),
        for (final key in served.keys) '${served.read(key)}',
      ]);
    });
  });

  group('a config that cannot hold key material cannot leak it', () {
    test('every TlsConfig field is a String', () {
      final fields = _fieldsOf(TlsConfig);

      expect(fields.keys, {'chainPath', 'keyPath', 'keyPassword'},
          reason: 'the sweep below is only as good as what it walks; a field '
              'added without a line here is a field nobody decided about');

      for (final entry in fields.entries) {
        expect(_typeName(entry.value), 'String',
            reason: 'SEC-01: TlsConfig.${entry.key} is declared '
                '${_typeName(entry.value)}. Paths, never bytes — a List<int>, '
                'a Uint8List or a SecurityContext here puts the gateway\'s '
                'private key inside the config object, where the next '
                'toString, log line or crash dump carries it out. A config '
                'that cannot hold bytes cannot leak them.');
      }
    });

    test('ServerConfig declares no SecurityContext', () {
      for (final entry in _fieldsOf(ServerConfig).entries) {
        expect(_typeName(entry.value), isNot('SecurityContext'),
            reason: 'SEC-01: ServerConfig.${entry.key} holds a loaded '
                'SecurityContext, which is the private key in memory behind a '
                'type that renders as an opaque handle today and need not '
                'tomorrow. The context is built inside RelayServer.start() '
                'and belongs to nothing else.');
      }
    });

    test('ServerConfig holds the TLS paths only through TlsConfig', () {
      final tls = _fieldsOf(ServerConfig)['tls'];

      expect(tls, isNotNull);
      expect(_typeName(tls!), 'TlsConfig',
          reason: 'the structural pin above guards TlsConfig; routing the '
              'paths around it — three loose String fields, or a Map — would '
              'leave nothing guarded');
    });
  });
}
