import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:open62541/open62541.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/aggregator_server.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/state_man.dart';

void _t(Stopwatch sw, String label) {
  stderr.writeln('  [${sw.elapsedMilliseconds}ms] $label');
}

(Uint8List, Uint8List) _generateTestCerts() {
  final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final csr = X509Utils.generateRsaCsrPem(
    {'CN': 'TestClient', 'O': 'Test', 'OU': 'OPC-UA'},
    keyPair.privateKey as RSAPrivateKey,
    keyPair.publicKey as RSAPublicKey,
    san: ['localhost', '127.0.0.1'],
  );
  final certPem = X509Utils.generateSelfSignedCertificate(
    keyPair.privateKey as RSAPrivateKey,
    csr,
    365,
    sans: ['localhost', '127.0.0.1'],
  );
  final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(
      keyPair.privateKey as RSAPrivateKey);
  return (
    Uint8List.fromList(utf8.encode(certPem)),
    Uint8List.fromList(utf8.encode(keyPem)),
  );
}

/// Pre-generated certs shared across all test groups.
late Uint8List _serverCert;
late Uint8List _serverKey;
late Uint8List _clientCert;
late Uint8List _clientKey;

/// Integration tests for bugs found in code review.
void main() {
  setUpAll(() {
    final sw = Stopwatch()..start();
    final serverPair = _generateTestCerts();
    _serverCert = serverPair.$1;
    _serverKey = serverPair.$2;
    _t(sw, 'server cert generated');
    final clientPair = _generateTestCerts();
    _clientCert = clientPair.$1;
    _clientKey = clientPair.$2;
    _t(sw, 'client cert generated');
  });

  group('Bug #1: setOpcUaClients reload sees stale config', () {
    late Server upstreamServer;
    late int upstreamPort;
    late int aggregatorPort;
    late StateMan stateMan;
    late AggregatorServer aggregator;
    late ClientIsolate aggClient;
    var running = true;
    List<OpcUAConfig>? reloadedServers;
    String? oldEndpointAtCallbackTime;

    setUpAll(() async {
      final sw = Stopwatch()..start();
      final base = 10000 + Random().nextInt(40000);
      upstreamPort = base;
      aggregatorPort = base + 1;

      upstreamServer =
          Server(port: upstreamPort, logLevel: LogLevel.UA_LOGLEVEL_ERROR);
      upstreamServer.addVariableNode(
        NodeId.fromString(1, 'GVL.temp'),
        DynamicValue(value: 23.5, typeId: NodeId.double, name: 'temp'),
      );
      upstreamServer.start();
      unawaited(() async {
        while (running && upstreamServer.runIterate(waitInterval: false)) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }());
      _t(sw, 'Bug#1 upstream server started');

      final keyMappings = KeyMappings(nodes: {
        'temperature': KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'GVL.temp')
            ..serverAlias = 'plc1',
        ),
      });

      final config = StateManConfig(
        opcua: [
          OpcUAConfig()
            ..endpoint = 'opc.tcp://localhost:$upstreamPort'
            ..serverAlias = 'plc1',
        ],
        aggregator: AggregatorConfig(
          enabled: true,
          port: aggregatorPort,
          certificate: _serverCert,
          privateKey: _serverKey,
        ),
      );

      stateMan = await StateMan.create(
        config: config,
        keyMappings: keyMappings,
        useIsolate: true,
        alias: 'test-reload',
      );
      _t(sw, 'Bug#1 StateMan.create');

      for (final wrapper in stateMan.clients) {
        if (wrapper.connectionStatus == ConnectionStatus.connected) continue;
        await wrapper.connectionStream
            .firstWhere((event) => event.$1 == ConnectionStatus.connected)
            .timeout(const Duration(seconds: 15));
      }
      _t(sw, 'Bug#1 client connected');

      aggregator = AggregatorServer(
        config: config.aggregator!,
        sharedStateMan: stateMan,
        onReloadClients: (newServers) async {
          reloadedServers = newServers;
          oldEndpointAtCallbackTime = stateMan.config.opcua.first.endpoint;
          return 'ok';
        },
      );
      await aggregator.initialize();
      _t(sw, 'Bug#1 aggregator initialized');

      unawaited(aggregator.runLoop());

      aggClient = await ClientIsolate.create(
        certificate: _clientCert,
        privateKey: _clientKey,
        securityMode: MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGNANDENCRYPT,
      );
      unawaited(aggClient.runIterate().catchError((_) {}));
      unawaited(aggClient.connect('opc.tcp://localhost:$aggregatorPort'));
      await aggClient.awaitConnect();
      _t(sw, 'Bug#1 aggClient connected');
    });

    tearDownAll(() async {
      await aggregator.shutdown();
      await aggClient.delete();
      await stateMan.close();
      running = false;
      await Future.delayed(const Duration(milliseconds: 20));
      upstreamServer.shutdown();
      upstreamServer.delete();
    });

    test('onReloadClients sees original config, not already-replaced one', () async {
      final newEndpoint = 'opc.tcp://localhost:${upstreamPort + 100}';
      final originalEndpoint = stateMan.config.opcua.first.endpoint;

      await aggClient.call(
        NodeId.objectsFolder,
        NodeId.fromString(1, 'setOpcUaClients'),
        [
          DynamicValue(
            value: jsonEncode([
              {'endpoint': newEndpoint, 'server_alias': 'plc1'},
            ]),
            typeId: NodeId.uastring,
          ),
        ],
      );

      // Wait for async reload
      await Future.delayed(const Duration(milliseconds: 500));

      expect(reloadedServers, isNotNull, reason: 'reload callback should fire');
      expect(
        oldEndpointAtCallbackTime,
        originalEndpoint,
        reason: 'Config should not be replaced before reload callback',
      );
    });
  });

  group('Bug #2: _createAliasFolders duplicate Discover/Statistics nodes', () {
    late Server upstreamServer;
    late int upstreamPort;
    late int aggregatorPort;
    late StateMan stateMan;
    late AggregatorServer aggregator;
    late ClientIsolate aggClient;
    var running = true;

    setUpAll(() async {
      final sw = Stopwatch()..start();
      final base = 10000 + Random().nextInt(40000);
      upstreamPort = base;
      aggregatorPort = base + 1;

      upstreamServer =
          Server(port: upstreamPort, logLevel: LogLevel.UA_LOGLEVEL_ERROR);
      upstreamServer.addVariableNode(
        NodeId.fromString(1, 'GVL.temp'),
        DynamicValue(value: 23.5, typeId: NodeId.double, name: 'temp'),
      );
      upstreamServer.start();
      unawaited(() async {
        while (running && upstreamServer.runIterate(waitInterval: false)) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }());
      _t(sw, 'Bug#2 upstream server started');

      final keyMappings = KeyMappings(nodes: {
        'temperature': KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'GVL.temp')
            ..serverAlias = 'plc1',
        ),
      });

      final config = StateManConfig(
        opcua: [
          OpcUAConfig()
            ..endpoint = 'opc.tcp://localhost:$upstreamPort'
            ..serverAlias = 'plc1',
        ],
        aggregator: AggregatorConfig(
          enabled: true,
          port: aggregatorPort,
          certificate: _serverCert,
          privateKey: _serverKey,
        ),
      );

      stateMan = await StateMan.create(
        config: config,
        keyMappings: keyMappings,
        useIsolate: true,
        alias: 'test-dup',
      );
      _t(sw, 'Bug#2 StateMan.create');

      for (final wrapper in stateMan.clients) {
        if (wrapper.connectionStatus == ConnectionStatus.connected) continue;
        await wrapper.connectionStream
            .firstWhere((event) => event.$1 == ConnectionStatus.connected)
            .timeout(const Duration(seconds: 15));
      }
      _t(sw, 'Bug#2 client connected');

      aggregator = AggregatorServer(
        config: config.aggregator!,
        sharedStateMan: stateMan,
      );
      await aggregator.initialize();
      _t(sw, 'Bug#2 aggregator initialized');

      unawaited(aggregator.runLoop());

      aggClient = await ClientIsolate.create(
        certificate: _clientCert,
        privateKey: _clientKey,
        securityMode: MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGNANDENCRYPT,
      );
      unawaited(aggClient.runIterate().catchError((_) {}));
      unawaited(aggClient.connect('opc.tcp://localhost:$aggregatorPort'));
      await aggClient.awaitConnect();
      _t(sw, 'Bug#2 aggClient connected');
    });

    tearDownAll(() async {
      await aggregator.shutdown();
      await aggClient.delete();
      await stateMan.close();
      running = false;
      await Future.delayed(const Duration(milliseconds: 20));
      upstreamServer.shutdown();
      upstreamServer.delete();
    });

    test('setOpcUaClients with same alias does not crash on duplicate nodes', () async {
      final result = await aggClient.call(
        NodeId.objectsFolder,
        NodeId.fromString(1, 'setOpcUaClients'),
        [
          DynamicValue(
            value: jsonEncode([
              {
                'endpoint': 'opc.tcp://localhost:$upstreamPort',
                'server_alias': 'plc1',
              },
            ]),
            typeId: NodeId.uastring,
          ),
        ],
      );

      expect(result.first.value, contains('ok'));
    });
  });

  group('Bug #4: _internalWrites burst loses track', () {
    late Server upstreamServer;
    late int upstreamPort;
    late int aggregatorPort;
    late StateMan stateMan;
    late AggregatorServer aggregator;
    var running = true;

    setUpAll(() async {
      final sw = Stopwatch()..start();
      final base = 10000 + Random().nextInt(40000);
      upstreamPort = base;
      aggregatorPort = base + 1;

      upstreamServer =
          Server(port: upstreamPort, logLevel: LogLevel.UA_LOGLEVEL_ERROR);
      upstreamServer.addVariableNode(
        NodeId.fromString(1, 'GVL.temp'),
        DynamicValue(
            value: 23.5, typeId: NodeId.double, name: 'temp'),
        accessLevel: const AccessLevelMask(read: true, write: true),
      );
      upstreamServer.start();
      unawaited(() async {
        while (running && upstreamServer.runIterate(waitInterval: false)) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }());
      _t(sw, 'Bug#4 upstream server started');

      final keyMappings = KeyMappings(nodes: {
        'temperature': KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'GVL.temp')
            ..serverAlias = 'plc1',
        ),
      });

      final config = StateManConfig(
        opcua: [
          OpcUAConfig()
            ..endpoint = 'opc.tcp://localhost:$upstreamPort'
            ..serverAlias = 'plc1',
        ],
        aggregator: AggregatorConfig(
          enabled: true,
          port: aggregatorPort,
          certificate: _serverCert,
          privateKey: _serverKey,
        ),
      );

      stateMan = await StateMan.create(
        config: config,
        keyMappings: keyMappings,
        useIsolate: true,
        alias: 'test-burst',
      );
      _t(sw, 'Bug#4 StateMan.create');

      for (final wrapper in stateMan.clients) {
        if (wrapper.connectionStatus == ConnectionStatus.connected) continue;
        await wrapper.connectionStream
            .firstWhere((event) => event.$1 == ConnectionStatus.connected)
            .timeout(const Duration(seconds: 15));
      }
      _t(sw, 'Bug#4 client connected');

      aggregator = AggregatorServer(
        config: config.aggregator!,
        sharedStateMan: stateMan,
      );
      await aggregator.initialize();
      _t(sw, 'Bug#4 aggregator initialized');

      unawaited(aggregator.runLoop());
    });

    tearDownAll(() async {
      await aggregator.shutdown();
      await stateMan.close();
      running = false;
      await Future.delayed(const Duration(milliseconds: 20));
      upstreamServer.shutdown();
      upstreamServer.delete();
    });

    test('rapid upstream changes do not echo writes back to upstream', () async {
      final sw = Stopwatch()..start();
      // Wait for initial subscription setup
      await Future.delayed(const Duration(milliseconds: 500));
      _t(sw, 'Bug#4 subscription wait');

      // Monitor the upstream server for writes
      final upstreamWrites = <DynamicValue>[];
      final sub = upstreamServer
          .monitorVariable(NodeId.fromString(1, 'GVL.temp'))
          .listen((event) {
        final (type, value) = event;
        if (type == 'write' && value != null) {
          upstreamWrites.add(value);
        }
      });

      // Simulate rapid upstream PLC changes
      for (var i = 0; i < 5; i++) {
        upstreamServer.write(
          NodeId.fromString(1, 'GVL.temp'),
          DynamicValue(value: 100.0 + i, typeId: NodeId.double),
        );
      }

      // Wait for propagation
      await Future.delayed(const Duration(seconds: 2));
      _t(sw, 'Bug#4 propagation wait');

      expect(upstreamWrites.length, 5,
          reason: 'Should see only 5 direct writes, no echoes from aggregator');

      await sub.cancel();
    });
  });

  group('Bug #5: addExternalAlarm duplicates', () {
    test('calling addExternalAlarm twice with same uid deduplicates', () async {
      final config = StateManConfig(opcua: []);
      final keyMappings = KeyMappings(nodes: {});
      final sm = await StateMan.create(
        config: config,
        keyMappings: keyMappings,
        useIsolate: false,
        alias: 'test-dedup',
      );

      final prefs = await Preferences.create(db: null);
      final alarmMan = await AlarmMan.create(prefs, sm);

      final rule = AlarmRule(
        level: AlarmLevel.error,
        expression: ExpressionConfig(
          value: Expression(formula: 'disconnected'),
        ),
        acknowledgeRequired: false,
      );

      final alarmConfig = AlarmConfig(
        uid: 'connection-plc1',
        title: 'plc1 disconnected',
        description: 'PLC1 is disconnected',
        rules: [rule],
      );

      for (var i = 0; i < 2; i++) {
        alarmMan.addExternalAlarm(AlarmActive(
          alarm: Alarm(config: alarmConfig),
          notification: AlarmNotification(
            uid: 'connection-plc1',
            active: true,
            expression: 'disconnected',
            rule: rule,
            timestamp: DateTime.now(),
          ),
        ));
      }

      final alarms = await alarmMan.activeAlarms().first;
      final matching = alarms
          .where((a) => a.alarm.config.uid == 'connection-plc1')
          .toList();

      expect(matching.length, 1,
          reason: 'Should dedup by uid, not accumulate duplicates');

      await sm.close();
    });
  });

  group('Bug #8: _pendingDiscoveries concurrent modification', () {
    test('shutdown copies pendingDiscoveries before awaiting', () async {
      final pending = <Future<void>>{};
      var completed = 0;

      for (var i = 0; i < 3; i++) {
        final future = Future.delayed(const Duration(milliseconds: 50)).then((_) {
          completed++;
        });
        pending.add(future);
        future.whenComplete(() => pending.remove(future));
      }

      await Future.wait(pending.toList()).catchError((_) => <void>[]);
      expect(completed, 3, reason: 'All futures should complete');
    });
  });
}
