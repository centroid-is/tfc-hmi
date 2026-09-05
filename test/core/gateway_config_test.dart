import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/gateway_config.dart';
import 'package:tfc_dart/core/preferences.dart';

void main() {
  group('GatewayConfig persistence', () {
    test('a station that has never been configured runs direct', () async {
      final prefs = InMemoryPreferences();
      expect(await readGatewayConfig(prefs), GatewayConfig.defaults);
      expect(GatewayConfig.defaults.mode, TransportMode.direct);
      expect(GatewayConfig.defaults.isGateway, isFalse);
    });

    test('round-trips every field through preferences', () async {
      final prefs = InMemoryPreferences();
      const written = GatewayConfig(
        mode: TransportMode.gateway,
        url: 'wss://10.50.10.11:9443',
        caCertPath: '/home/centroid/relay_config/pki/ca.pem',
        tokenPath: '/etc/centroid/station.token',
      );
      await writeGatewayConfig(prefs, written);
      expect(await readGatewayConfig(prefs), written);
    });

    // A hand-edited or half-written row must not stop a panel booting, and
    // direct mode is the configuration the plant already runs.
    test('a corrupt row reads as direct mode rather than throwing', () async {
      final prefs = InMemoryPreferences();
      await prefs.setString(GatewayConfig.prefsKey, 'not json at all');
      expect(await readGatewayConfig(prefs), GatewayConfig.defaults);
    });

    // Parsing is by string, so renaming the enum constant cannot silently
    // re-point a plant full of gateway stations back to direct.
    test('an unknown mode string reads as direct', () async {
      final prefs = InMemoryPreferences();
      await prefs.setString(
          GatewayConfig.prefsKey, jsonEncode({'mode': 'carrier-pigeon'}));
      expect((await readGatewayConfig(prefs)).mode, TransportMode.direct);
    });

    test('blank paths are stored as absent, not as empty strings', () async {
      final prefs = InMemoryPreferences();
      await prefs.setString(
          GatewayConfig.prefsKey,
          jsonEncode({
            'mode': 'gateway',
            'url': 'ws://localhost:9443',
            'ca_cert_path': '   ',
            'token_path': '',
          }));
      final read = await readGatewayConfig(prefs);
      expect(read.caCertPath, isNull);
      expect(read.tokenPath, isNull);
    });
  });

  group('GatewayConfig.validationError', () {
    // The whole point of the refusal living here: the operator reads it with
    // the keyboard still in their hands, not as a dark screen at next boot.
    test('direct mode never refuses, whatever else is filled in', () {
      const config = GatewayConfig(mode: TransportMode.direct, url: 'nonsense');
      expect(config.validationError, isNull);
    });

    test('an empty address is refused with the shape to type', () {
      const config = GatewayConfig(mode: TransportMode.gateway);
      expect(config.validationError, contains('wss://'));
    });

    test('a non-URL is refused', () {
      const config =
          GatewayConfig(mode: TransportMode.gateway, url: 'just some words');
      expect(config.validationError, contains('Not a URL'));
    });

    test('http is refused: this is a WebSocket', () {
      const config = GatewayConfig(
          mode: TransportMode.gateway, url: 'https://10.50.10.11:9443');
      expect(config.validationError, contains('wss'));
    });

    // Mirrors ClientConfig.checkDialable. Without the root every handshake
    // fails with the message a genuine impostor produces, so the panel reports
    // an attack rather than a missing file.
    test('wss without a pinned root is refused', () {
      const config = GatewayConfig(
          mode: TransportMode.gateway, url: 'wss://10.50.10.11:9443');
      expect(config.validationError, contains('CA root'));
    });

    test('wss with a pinned root is accepted', () {
      const config = GatewayConfig(
        mode: TransportMode.gateway,
        url: 'wss://10.50.10.11:9443',
        caCertPath: '/pki/ca.pem',
      );
      expect(config.validationError, isNull);
      expect(config.uri.scheme, 'wss');
    });

    // The mirror refusal: a config that reads as encrypted while the traffic
    // is not is the kind of thing found by a packet capture months later.
    test('a pinned root on a plaintext dial is refused', () {
      const config = GatewayConfig(
        mode: TransportMode.gateway,
        url: 'ws://10.50.10.11:9443',
        caCertPath: '/pki/ca.pem',
      );
      expect(config.validationError, contains('never consulted'));
    });

    test('a credential on a plaintext dial is refused', () {
      const config = GatewayConfig(
        mode: TransportMode.gateway,
        url: 'ws://10.50.10.11:9443',
        tokenPath: '/etc/station.token',
      );
      expect(config.validationError, contains('in the clear'));
    });

    test('a bare ws bench gateway is accepted', () {
      const config =
          GatewayConfig(mode: TransportMode.gateway, url: 'ws://localhost:9443');
      expect(config.validationError, isNull);
    });
  });

  group('GatewayConfig.toClientConfig', () {
    test('no credential file means no token on the wire', () async {
      const config = GatewayConfig(
        mode: TransportMode.gateway,
        url: 'wss://10.50.10.11:9443',
        caCertPath: '/pki/ca.pem',
      );
      final client = await config.toClientConfig();
      expect(client.token, isNull);
      expect(client.tls?.rootCertPath, '/pki/ca.pem');
    });

    // Read off disk at connect time and never written back: the secret must
    // not end up in a preferences row, a database backup or a support bundle.
    test('the credential is read from the file, trimmed', () async {
      final dir = await Directory.systemTemp.createTemp('gateway_token');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/station.token');
      await file.writeAsString('  s3cret-station-token\n');

      final config = GatewayConfig(
        mode: TransportMode.gateway,
        url: 'wss://10.50.10.11:9443',
        caCertPath: '/pki/ca.pem',
        tokenPath: file.path,
      );
      expect((await config.toClientConfig()).token, 's3cret-station-token');
    });

    // A panel that quietly drops its credential connects as an unknown station
    // and is refused with a message about authentication, which sends the
    // engineer to the wrong end of the wire.
    test('a missing credential file throws rather than dialling anonymously',
        () async {
      const config = GatewayConfig(
        mode: TransportMode.gateway,
        url: 'wss://10.50.10.11:9443',
        caCertPath: '/pki/ca.pem',
        tokenPath: '/no/such/station.token',
      );
      expect(config.toClientConfig(), throwsA(isA<FileSystemException>()));
    });
  });
}
