/// The gateway's configuration, and the two things it refuses.
///
/// This file is about a file on disk deciding what a panel reads. Two failures
/// live here and neither of them is a crash:
///
///  * **Two links sharing an alias** (T-08-50). The router offers a key to
///    every link in order and takes the first claim, so two links called
///    `ST101` mean a key is routed to whichever one was listed first — and
///    which one that is depends on the order somebody typed the JSON in. That
///    is not a fault anybody can diagnose from a screen; it is a motor speed
///    that reads the wrong motor. Refused at construction, with the alias in
///    the message.
///  * **A keymapping claiming a `PIPE.` name** (HLTH-03, T-08-51). Refused
///    *per key*, at boot, logged once, and the gateway starts. A gateway that
///    refuses to boot over one bad mapping entry is a plant that is down over
///    one bad mapping entry, and the operator's screen goes black for a typo.
///
/// No hardware, no sockets: every case here is allocation and arithmetic.
@TestOn('vm')
library;

import 'package:tfc_dart/core/state_man.dart' show KeyMappings, KeyMappingEntry;
import 'package:tfc_relay_local/tfc_relay_local.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:test/test.dart';

import 'support/free_port.dart';

/// A config with one OPC UA link, the smallest thing that is a gateway.
Map<String, dynamic> oneLinkJson({String alias = 'ST101'}) => <String, dynamic>{
      'server': <String, dynamic>{'port': 0},
      'key_mappings': 'svn-key-mappings.json',
      'links': <dynamic>[
        <String, dynamic>{
          'alias': alias,
          'protocol': 'opcua',
          'endpoint': 'opc.tcp://10.104.29.11:4840',
        },
      ],
    };

void main() {
  group('the config deserializes what the plant already has', () {
    test('a one-link config round-trips through JSON', () {
      final config = GatewayConfig.fromJson(oneLinkJson());

      final again = GatewayConfig.fromJson(config.toJson());

      expect(again.links, hasLength(1));
      expect(again.links.single.alias, 'ST101');
      expect(again.links.single.protocol, UpstreamProtocol.opcUa);
      expect(again.links.single.endpoint, 'opc.tcp://10.104.29.11:4840');
      expect(again.keyMappingsPath, 'svn-key-mappings.json');
    });

    test('every field the gateway needs survives the round trip', () async {
      // **Not a literal, and freeze 5 is why.** The round trip only needs *a*
      // number here, and a hard-coded one trips the port sweep — correctly: the
      // sweep is blunt on purpose, because the day somebody copies this line
      // into a case that actually binds is the day two worktrees collide and
      // the collision reads as a fault in the code under test. Drawing a real
      // free port costs one socket and keeps the allow-list empty.
      final chosen = await freePort();
      final json = oneLinkJson()
        ..['stale_after_ms'] = 7000
        ..['linger_ms'] = 250
        ..['server'] = <String, dynamic>{
          'port': chosen,
          'tick_ms': 60,
          'publisher_id': 'svn-gateway-1',
          'tls': <String, dynamic>{
            'chain_path': '/etc/relay/leaf.pem',
            'key_path': '/etc/relay/leaf.key',
          },
          'auth': <String, dynamic>{'token_file': '/etc/relay/tokens.json'},
        };
      (json['links'] as List).first
        ..['username'] = 'hmi'
        ..['password'] = 'secret'
        ..['string_encoding'] = 'latin1'
        ..['build_stamp_key'] = 'ST101.build'
        ..['use_isolate'] = false;

      final again = GatewayConfig.fromJson(GatewayConfig.fromJson(json).toJson());

      expect(again.staleAfter, const Duration(milliseconds: 7000));
      expect(again.linger, const Duration(milliseconds: 250));
      expect(again.server.port, chosen);
      expect(again.server.tick, const Duration(milliseconds: 60));
      expect(again.server.publisherId, 'svn-gateway-1');
      expect(again.server.tls?.chainPath, '/etc/relay/leaf.pem');
      expect(again.server.auth?.tokenFilePath, '/etc/relay/tokens.json');
      final link = again.links.single;
      expect(link.username, 'hmi');
      expect(link.password, 'secret');
      expect(link.stringEncoding, ServerStringEncoding.latin1);
      expect(link.buildStampKey, 'ST101.build');
      expect(link.useIsolate, isFalse);
    });

    test('the per-alias encoding table is built from the links', () {
      final json = oneLinkJson();
      (json['links'] as List)
        ..first['string_encoding'] = 'latin1'
        ..add(<String, dynamic>{
          'alias': 'ST201',
          'protocol': 'opcua',
          'endpoint': 'opc.tcp://10.104.29.12:4840',
        });

      final config = GatewayConfig.fromJson(json);

      expect(config.stringEncodings.encodingFor('ST101'),
          ServerStringEncoding.latin1);
      expect(config.stringEncodings.encodingFor('ST201'),
          ServerStringEncoding.utf8,
          reason: 'per SERVER: one Latin-1 device does not make the PLC beside '
              'it Latin-1');
    });
  });

  group('two links may not share an alias (T-08-50)', () {
    test('a duplicate alias is refused at construction, naming the alias', () {
      final json = oneLinkJson();
      (json['links'] as List).add(<String, dynamic>{
        'alias': 'ST101',
        'protocol': 'modbus',
        'endpoint': '10.104.29.31:502',
      });

      expect(
        () => GatewayConfig.fromJson(json),
        throwsA(isA<ArgumentError>().having(
            (e) => e.toString(), 'message', contains('ST101'))),
        reason: 'refused at construction and not at first use: at first use '
            'the symptom is a motor speed that reads the wrong motor, and '
            'nothing on any screen says which link answered',
      );
    });

    test('the duplicate check is exactly as strict as every other alias match',
        () {
      final json = oneLinkJson();
      (json['links'] as List).add(<String, dynamic>{
        'alias': 'st101',
        'protocol': 'opcua',
        'endpoint': 'opc.tcp://10.104.29.12:4840',
      });

      expect(GatewayConfig.fromJson(json).links, hasLength(2),
          reason: 'StateManConfig.normalizeAlias folds "" into null and '
              'nothing else — it is NOT case-insensitive, and the M2400 '
              'adapter\'s alias check (m2400_upstream_link.dart:86-89) and '
              'StringEncodingConfig.encodingFor both compare through it. So '
              '"st101" and "ST101" really are two different plants to every '
              'other layer, and a duplicate check that was stricter HERE '
              'would refuse a configuration the router would have served '
              'correctly. The rule is "exactly as strict as every other alias '
              'match", not "as strict as possible"');
    });

    test('an empty alias is refused before it can become the unnamed server',
        () {
      final json = oneLinkJson(alias: '');

      expect(() => GatewayConfig.fromJson(json), throwsArgumentError,
          reason: 'the unnamed server is a real shipped value in the live '
              'keymapping file — 430 entries carry server_alias: null — so an '
              'alias somebody left blank is indistinguishable from the plant '
              'that legitimately has none, and it would silently claim all of '
              'them');
    });

    test('an empty link list is a legitimate gateway', () {
      final json = oneLinkJson()..['links'] = <dynamic>[];

      expect(GatewayConfig.fromJson(json).links, isEmpty,
          reason: 'a gateway with no plant is what a bench and a first '
              'deployment both look like; it is not a misconfiguration');
    });
  });

  group('a PIPE. keymapping is refused per key, not per gateway (HLTH-03)', () {
    test('the reserved names are named, and the ordinary ones are not', () {
      final mappings = KeyMappings(nodes: <String, KeyMappingEntry>{
        'ST101.CN01.MOT01.speed': KeyMappingEntry(),
        PipeKeys.connected: KeyMappingEntry(),
        '${PipeKeys.prefix}upstream.ST101.connected': KeyMappingEntry(),
      });

      final refused = reservedKeyMappingNames(mappings);

      expect(refused, <String>{
        PipeKeys.connected,
        '${PipeKeys.prefix}upstream.ST101.connected',
      });
      expect(refused, isNot(contains('ST101.CN01.MOT01.speed')));
    });

    test('a clean keymapping refuses nothing', () {
      final mappings = KeyMappings(nodes: <String, KeyMappingEntry>{
        'ST101.CN01.MOT01.speed': KeyMappingEntry(),
      });

      expect(reservedKeyMappingNames(mappings), isEmpty);
    });
  });

  group('the usage text exists and names the one argument', () {
    test('usage names the config path', () {
      expect(gatewayUsage, contains('--config'));
      expect(gatewayUsage, contains('relay_gateway'));
    });
  });
}
