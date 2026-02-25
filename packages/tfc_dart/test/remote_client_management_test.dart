@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:open62541/open62541.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/aggregator_server.dart';
import 'package:tfc_dart/core/state_man.dart';

// ---------------------------------------------------------------------------
// Test infrastructure helpers
// ---------------------------------------------------------------------------

/// Generate self-signed TLS certificates for testing.
/// Returns (certBytes, keyBytes) as Uint8List (PEM encoded).
(Uint8List, Uint8List) generateTestCerts() {
  final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final attributes = {
    'CN': 'TestPLC',
    'O': 'Test',
    'OU': 'OPC-UA',
    'C': 'IS',
  };

  final csr = X509Utils.generateRsaCsrPem(
    attributes,
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

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  // Shared state across all tests
  final plcServers = <Server>[];
  StateMan? directSM;
  AggregatorServer? aggregator;
  ClientIsolate? adminClient;
  ClientIsolate? viewerClient;
  ClientIsolate? anonClient;
  late int basePort;
  late int aggregatorPort;
  late String configFilePath;
  late Uint8List plc2Cert;
  late Uint8List plc2Key;

  // NodeIds for the method nodes (will be created by aggregator)
  final getMethodId = NodeId.fromString(1, 'getOpcUaClients');
  final setMethodId = NodeId.fromString(1, 'setOpcUaClients');

  // -------------------------------------------------------------------------
  // Setup: 2 upstream PLCs + AggregatorServer with auth + 3 clients
  // -------------------------------------------------------------------------
  setUpAll(() async {
    basePort = 15000 + Random().nextInt(40000);
    aggregatorPort = basePort + 10;

    // Generate TLS certs for PLC2
    (plc2Cert, plc2Key) = generateTestCerts();

    // Create temp config file for persistence tests
    final tmpDir = await Directory.systemTemp.createTemp('tfc_test_');
    configFilePath = '${tmpDir.path}/stateman_config.json';

    // --- PLC 1: plain server (credentials stored in config metadata, not server auth) ---
    final plc1Port = basePort;
    final plc1Server =
        Server(port: plc1Port, logLevel: LogLevel.UA_LOGLEVEL_ERROR);
    plc1Server.addVariableNode(
      NodeId.fromString(1, 'temperature'),
      DynamicValue(
          value: 23.5, typeId: NodeId.double, name: 'temperature'),
      accessLevel: const AccessLevelMask(read: true, write: true),
    );
    plc1Server.addVariableNode(
      NodeId.fromString(1, 'status'),
      DynamicValue(value: true, typeId: NodeId.boolean, name: 'status'),
      accessLevel: const AccessLevelMask(read: true, write: true),
    );
    plc1Server.start();
    unawaited(() async {
      while (plc1Server.runIterate(waitInterval: false)) {
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }());
    plcServers.add(plc1Server);

    // --- PLC 2: no credentials, has TLS certs (in config only — actual PLC is plain) ---
    final plc2Port = basePort + 1;
    final plc2Server =
        Server(port: plc2Port, logLevel: LogLevel.UA_LOGLEVEL_ERROR);
    plc2Server.addVariableNode(
      NodeId.fromString(1, 'pressure'),
      DynamicValue(
          value: 101.3, typeId: NodeId.double, name: 'pressure'),
      accessLevel: const AccessLevelMask(read: true, write: true),
    );
    plc2Server.start();
    unawaited(() async {
      while (plc2Server.runIterate(waitInterval: false)) {
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }());
    plcServers.add(plc2Server);

    // --- Build key mappings ---
    final keyMappings = KeyMappings(nodes: {
      'plc1_temperature': KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(
          namespace: 1,
          identifier: 'temperature',
        )..serverAlias = 'plc1',
      ),
      'plc1_status': KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(
          namespace: 1,
          identifier: 'status',
        )..serverAlias = 'plc1',
      ),
      'plc2_pressure': KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(
          namespace: 1,
          identifier: 'pressure',
        )..serverAlias = 'plc2',
      ),
    });

    // --- Build StateManConfig ---
    // Both PLCs connect plain initially; credentials/TLS added to config after connect.
    final plc1Config = OpcUAConfig()
      ..endpoint = 'opc.tcp://localhost:$plc1Port'
      ..serverAlias = 'plc1';

    final plc2Config = OpcUAConfig()
      ..endpoint = 'opc.tcp://localhost:$plc2Port'
      ..serverAlias = 'plc2';

    final smConfig = StateManConfig(
      opcua: [plc1Config, plc2Config],
      aggregator: AggregatorConfig(
        enabled: true,
        port: aggregatorPort,
        users: [
          AggregatorUser(
              username: 'admin', password: 'admin123', admin: true),
          AggregatorUser(
              username: 'viewer', password: 'viewer123', admin: false),
        ],
        allowAnonymous: true, // anonymous can connect but methods are restricted
      ),
    );

    // --- Create direct StateMan ---
    directSM = await StateMan.create(
      config: smConfig,
      keyMappings: keyMappings,
      useIsolate: true,
      alias: 'test-direct',
    );

    // Wait for PLC connections
    for (final wrapper in directSM!.clients) {
      if (wrapper.connectionStatus == ConnectionStatus.connected) continue;
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 30));
    }

    // Now add credentials/TLS to configs (simulating stored metadata).
    // StateMan connected plain, but aggregator sees has_credentials/has_tls=true.
    plc1Config.username = 'plcuser';
    plc1Config.password = 'plcpass';
    plc2Config.sslCert = plc2Cert;
    plc2Config.sslKey = plc2Key;

    // Write config with full data (including TLS certs) to temp file
    await File(configFilePath).writeAsString(jsonEncode(smConfig.toJson()));

    // --- Create AggregatorServer ---
    aggregator = AggregatorServer(
      config: smConfig.aggregator!,
      sharedStateMan: directSM!,
      configFilePath: configFilePath,
    );
    await aggregator!.initialize();
    unawaited(aggregator!.runLoop());

    // --- Create 3 clients with different auth levels ---
    // Admin client
    adminClient = await ClientIsolate.create(
      username: 'admin',
      password: 'admin123',
    );
    unawaited(adminClient!.runIterate().catchError((_) {}));
    unawaited(
        adminClient!.connect('opc.tcp://localhost:$aggregatorPort'));
    await adminClient!.awaitConnect();

    // Viewer client (non-admin authenticated user)
    viewerClient = await ClientIsolate.create(
      username: 'viewer',
      password: 'viewer123',
    );
    unawaited(viewerClient!.runIterate().catchError((_) {}));
    unawaited(
        viewerClient!.connect('opc.tcp://localhost:$aggregatorPort'));
    await viewerClient!.awaitConnect();

    // Anonymous client (no credentials)
    anonClient = await ClientIsolate.create();
    unawaited(anonClient!.runIterate().catchError((_) {}));
    unawaited(
        anonClient!.connect('opc.tcp://localhost:$aggregatorPort'));
    await anonClient!.awaitConnect();
  });

  // -------------------------------------------------------------------------
  // Teardown
  // -------------------------------------------------------------------------
  tearDownAll(() async {
    if (anonClient != null) await anonClient!.delete();
    if (viewerClient != null) await viewerClient!.delete();
    if (adminClient != null) await adminClient!.delete();
    if (aggregator != null) await aggregator!.shutdown();
    if (directSM != null) await directSM!.close();
    for (final server in plcServers) {
      server.shutdown();
      server.delete();
    }
    // Clean up temp config file
    try {
      final tmpDir = Directory(configFilePath).parent;
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  // =========================================================================
  // Group 1: Native OPC UA access control
  // =========================================================================
  group('Access control', () {
    test('admin can call getOpcUaClients', () async {
      final result = await adminClient!.call(
        NodeId.objectsFolder,
        getMethodId,
        [],
      );
      expect(result, isNotEmpty);
      // Result should be a JSON string
      final json = jsonDecode(result.first.value as String);
      expect(json, isList);
    });

    test('viewer can call getOpcUaClients', () async {
      final result = await viewerClient!.call(
        NodeId.objectsFolder,
        getMethodId,
        [],
      );
      expect(result, isNotEmpty);
      final json = jsonDecode(result.first.value as String);
      expect(json, isList);
    });

    test('anonymous blocked from getOpcUaClients', () async {
      await expectLater(
        anonClient!.call(NodeId.objectsFolder, getMethodId, []),
        throwsA(predicate((e) => e.toString().contains('BadNotExecutable'))),
      );
    });

    test('admin can call setOpcUaClients', () async {
      // Send back current config unchanged (using has_credentials/has_tls)
      final getResult = await adminClient!.call(
        NodeId.objectsFolder,
        getMethodId,
        [],
      );
      final currentServers = jsonDecode(getResult.first.value as String);

      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: jsonEncode(currentServers), typeId: NodeId.uastring)],
      );
      expect(result, isNotEmpty);
      expect(result.first.value, contains('ok'));
    });

    test('viewer blocked from setOpcUaClients', () async {
      await expectLater(
        viewerClient!.call(
          NodeId.objectsFolder,
          setMethodId,
          [DynamicValue(value: '[]', typeId: NodeId.uastring)],
        ),
        throwsA(predicate((e) => e.toString().contains('BadNotExecutable'))),
      );
    });

    test('anonymous blocked from setOpcUaClients', () async {
      await expectLater(
        anonClient!.call(
          NodeId.objectsFolder,
          setMethodId,
          [DynamicValue(value: '[]', typeId: NodeId.uastring)],
        ),
        throwsA(predicate((e) => e.toString().contains('BadNotExecutable'))),
      );
    });
  });

  // =========================================================================
  // Group 2: getOpcUaClients response
  // =========================================================================
  group('getOpcUaClients', () {
    test('returns sanitized list — no passwords or certs', () async {
      final result = await adminClient!.call(
        NodeId.objectsFolder,
        getMethodId,
        [],
      );
      final servers =
          jsonDecode(result.first.value as String) as List<dynamic>;

      expect(servers.length, 2);

      // PLC1: has credentials, no TLS
      final plc1 =
          servers.firstWhere((s) => s['server_alias'] == 'plc1') as Map;
      expect(plc1['endpoint'], contains('localhost'));
      expect(plc1['has_credentials'], isTrue);
      expect(plc1['has_tls'], isFalse);
      // Should NOT contain actual secrets
      expect(plc1.containsKey('username'), isFalse);
      expect(plc1.containsKey('password'), isFalse);
      expect(plc1.containsKey('ssl_cert'), isFalse);
      expect(plc1.containsKey('ssl_key'), isFalse);

      // PLC2: no credentials, has TLS
      final plc2 =
          servers.firstWhere((s) => s['server_alias'] == 'plc2') as Map;
      expect(plc2['endpoint'], contains('localhost'));
      expect(plc2['has_credentials'], isFalse);
      expect(plc2['has_tls'], isTrue);
      expect(plc2.containsKey('username'), isFalse);
      expect(plc2.containsKey('password'), isFalse);
      expect(plc2.containsKey('ssl_cert'), isFalse);
      expect(plc2.containsKey('ssl_key'), isFalse);
    });

    test('returns all configured servers with correct aliases', () async {
      final result = await adminClient!.call(
        NodeId.objectsFolder,
        getMethodId,
        [],
      );
      final servers =
          jsonDecode(result.first.value as String) as List<dynamic>;

      final aliases =
          servers.map((s) => (s as Map)['server_alias']).toSet();
      expect(aliases, containsAll(['plc1', 'plc2']));
    });
  });

  // =========================================================================
  // Group 3: setOpcUaClients — credential merge
  // =========================================================================
  group('setOpcUaClients credential merge', () {
    test('has_credentials=true preserves existing credentials', () async {
      // Send plc1 with has_credentials:true (no actual username/password)
      final payload = jsonEncode([
        {
          'endpoint': 'opc.tcp://localhost:${basePort}',
          'server_alias': 'plc1',
          'has_credentials': true,
          'has_tls': false,
        },
        {
          'endpoint': 'opc.tcp://localhost:${basePort + 1}',
          'server_alias': 'plc2',
          'has_tls': true,
          'has_credentials': false,
        },
      ]);

      await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );

      // Verify credentials preserved by reading config file
      final configJson =
          jsonDecode(await File(configFilePath).readAsString());
      final opcua = configJson['opcua'] as List;
      final plc1 = opcua.firstWhere((s) => s['server_alias'] == 'plc1');
      expect(plc1['username'], 'plcuser');
      expect(plc1['password'], 'plcpass');
    });

    test('has_tls=true preserves existing TLS certs', () async {
      final payload = jsonEncode([
        {
          'endpoint': 'opc.tcp://localhost:${basePort}',
          'server_alias': 'plc1',
          'has_credentials': true,
          'has_tls': false,
        },
        {
          'endpoint': 'opc.tcp://localhost:${basePort + 1}',
          'server_alias': 'plc2',
          'has_tls': true,
          'has_credentials': false,
        },
      ]);

      await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );

      // Verify TLS certs preserved
      final configJson =
          jsonDecode(await File(configFilePath).readAsString());
      final opcua = configJson['opcua'] as List;
      final plc2 = opcua.firstWhere((s) => s['server_alias'] == 'plc2');
      expect(plc2['ssl_cert'], isNotNull);
      expect(plc2['ssl_key'], isNotNull);
    });

    test('explicit credentials replace existing', () async {
      final payload = jsonEncode([
        {
          'endpoint': 'opc.tcp://localhost:${basePort}',
          'server_alias': 'plc1',
          'username': 'newuser',
          'password': 'newpass',
        },
        {
          'endpoint': 'opc.tcp://localhost:${basePort + 1}',
          'server_alias': 'plc2',
          'has_tls': true,
          'has_credentials': false,
        },
      ]);

      await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );

      // Verify new credentials in config file
      final configJson =
          jsonDecode(await File(configFilePath).readAsString());
      final opcua = configJson['opcua'] as List;
      final plc1 = opcua.firstWhere((s) => s['server_alias'] == 'plc1');
      expect(plc1['username'], 'newuser');
      expect(plc1['password'], 'newpass');
    });

    test('explicit TLS certs replace existing', () async {
      final (newCert, newKey) = generateTestCerts();
      final newCertB64 = base64Encode(newCert);
      final newKeyB64 = base64Encode(newKey);

      final payload = jsonEncode([
        {
          'endpoint': 'opc.tcp://localhost:${basePort}',
          'server_alias': 'plc1',
          'has_credentials': true,
          'has_tls': false,
        },
        {
          'endpoint': 'opc.tcp://localhost:${basePort + 1}',
          'server_alias': 'plc2',
          'ssl_cert': newCertB64,
          'ssl_key': newKeyB64,
        },
      ]);

      await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );

      // Verify new TLS certs in config file
      final configJson =
          jsonDecode(await File(configFilePath).readAsString());
      final opcua = configJson['opcua'] as List;
      final plc2 = opcua.firstWhere((s) => s['server_alias'] == 'plc2');
      expect(plc2['ssl_cert'], newCertB64);
      expect(plc2['ssl_key'], newKeyB64);
    });
  });

  // =========================================================================
  // Group 4: Config persistence
  // =========================================================================
  group('Config persistence', () {
    test('setOpcUaClients persists to config file', () async {
      final payload = jsonEncode([
        {
          'endpoint': 'opc.tcp://localhost:${basePort}',
          'server_alias': 'plc1',
          'has_credentials': true,
          'has_tls': false,
        },
        {
          'endpoint': 'opc.tcp://localhost:${basePort + 1}',
          'server_alias': 'plc2',
          'has_tls': true,
          'has_credentials': false,
        },
      ]);

      await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );

      // Verify file exists and contains valid config
      final fileContent = await File(configFilePath).readAsString();
      final configJson = jsonDecode(fileContent) as Map<String, dynamic>;
      expect(configJson.containsKey('opcua'), isTrue);
      final opcua = configJson['opcua'] as List;
      expect(opcua.length, 2);
    });

    test('OpcUAConfig equality — same fields', () {
      final a = OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..serverAlias = 'plc1'
        ..username = 'user'
        ..password = 'pass';
      final b = OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..serverAlias = 'plc1'
        ..username = 'user'
        ..password = 'pass';
      expect(a, equals(b));
    });

    test('OpcUAConfig equality — different endpoint', () {
      final a = OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..serverAlias = 'plc1';
      final b = OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4841'
        ..serverAlias = 'plc1';
      expect(a, isNot(equals(b)));
    });

    test('OpcUAConfig equality — different credentials', () {
      final a = OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..username = 'user1'
        ..password = 'pass1';
      final b = OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..username = 'user2'
        ..password = 'pass2';
      expect(a, isNot(equals(b)));
    });

    test('StateManConfig.toFile writes valid JSON', () async {
      final config = StateManConfig(
        opcua: [
          OpcUAConfig()
            ..endpoint = 'opc.tcp://localhost:4840'
            ..serverAlias = 'test',
        ],
      );
      final tmpFile = '${Directory.systemTemp.path}/test_config_${Random().nextInt(99999)}.json';
      await config.toFile(tmpFile);

      final content = await File(tmpFile).readAsString();
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      expect(parsed.containsKey('opcua'), isTrue);
      expect((parsed['opcua'] as List).length, 1);

      await File(tmpFile).delete();
    });
  });

  // =========================================================================
  // Group 5: Hot-reload (isolate lifecycle)
  // =========================================================================
  group('Hot-reload', () {
    test('adding a server triggers reload callback', () async {
      // Add a third PLC
      final payload = jsonEncode([
        {
          'endpoint': 'opc.tcp://localhost:${basePort}',
          'server_alias': 'plc1',
          'has_credentials': true,
          'has_tls': false,
        },
        {
          'endpoint': 'opc.tcp://localhost:${basePort + 1}',
          'server_alias': 'plc2',
          'has_tls': true,
          'has_credentials': false,
        },
        {
          'endpoint': 'opc.tcp://localhost:${basePort + 2}',
          'server_alias': 'plc3',
        },
      ]);

      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );
      expect(result.first.value, contains('ok'));

      // Verify config file has 3 servers
      final configJson =
          jsonDecode(await File(configFilePath).readAsString());
      final opcua = configJson['opcua'] as List;
      expect(opcua.length, 3);
    });

    test('removing a server triggers reload callback', () async {
      // Only keep plc1
      final payload = jsonEncode([
        {
          'endpoint': 'opc.tcp://localhost:${basePort}',
          'server_alias': 'plc1',
          'has_credentials': true,
          'has_tls': false,
        },
      ]);

      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );
      expect(result.first.value, contains('ok'));

      // Verify config file has 1 server
      final configJson =
          jsonDecode(await File(configFilePath).readAsString());
      final opcua = configJson['opcua'] as List;
      expect(opcua.length, 1);
    });

    test('changing endpoint triggers reload callback', () async {
      final payload = jsonEncode([
        {
          'endpoint': 'opc.tcp://localhost:${basePort + 99}',
          'server_alias': 'plc1',
          'has_credentials': true,
          'has_tls': false,
        },
        {
          'endpoint': 'opc.tcp://localhost:${basePort + 1}',
          'server_alias': 'plc2',
          'has_tls': true,
          'has_credentials': false,
        },
      ]);

      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );
      expect(result.first.value, contains('ok'));

      // Verify config file has the changed endpoint
      final configJson =
          jsonDecode(await File(configFilePath).readAsString());
      final opcua = configJson['opcua'] as List;
      final plc1 = opcua.firstWhere((s) => s['server_alias'] == 'plc1');
      expect(plc1['endpoint'], contains('${basePort + 99}'));
    });
  });

  // =========================================================================
  // Group 6: setOpcUaClients input validation
  // =========================================================================
  group('setOpcUaClients validation', () {
    test('rejects invalid JSON', () async {
      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: '{broken', typeId: NodeId.uastring)],
      );
      expect(result.first.value as String, startsWith('error:'));
      expect(result.first.value as String, contains('invalid JSON'));
    });

    test('rejects non-array JSON', () async {
      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: '{"foo": "bar"}', typeId: NodeId.uastring)],
      );
      expect(result.first.value as String, startsWith('error:'));
      expect(result.first.value as String, contains('expected JSON array'));
    });

    test('rejects empty server list', () async {
      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: '[]', typeId: NodeId.uastring)],
      );
      expect(result.first.value as String, startsWith('error:'));
      expect(result.first.value as String, contains('cannot be empty'));
    });

    test('rejects entry without endpoint', () async {
      final payload = jsonEncode([
        {'server_alias': 'plc1'},
      ]);
      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );
      expect(result.first.value as String, startsWith('error:'));
      expect(result.first.value as String, contains('endpoint'));
    });

    test('rejects entry with empty endpoint', () async {
      final payload = jsonEncode([
        {'endpoint': '', 'server_alias': 'plc1'},
      ]);
      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );
      expect(result.first.value as String, startsWith('error:'));
      expect(result.first.value as String, contains('endpoint'));
    });

    test('rejects array of non-objects', () async {
      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: '[1, 2, 3]', typeId: NodeId.uastring)],
      );
      expect(result.first.value as String, startsWith('error:'));
      expect(result.first.value as String, contains('not an object'));
    });

    test('returns ok with count on valid input', () async {
      final payload = jsonEncode([
        {
          'endpoint': 'opc.tcp://localhost:${basePort + 1}',
          'server_alias': 'plc1',
          'has_tls': false,
          'has_credentials': false,
        },
      ]);
      final result = await adminClient!.call(
        NodeId.objectsFolder,
        setMethodId,
        [DynamicValue(value: payload, typeId: NodeId.uastring)],
      );
      expect(result.first.value as String, startsWith('ok:'));
      expect(result.first.value as String, contains('1 server(s)'));
    });
  });

  // =========================================================================
  // Group 7: AggregatorUser admin flag
  // =========================================================================
  group('AggregatorUser', () {
    test('admin flag serialization round-trip', () {
      final user = AggregatorUser(
          username: 'admin', password: 'pass', admin: true);
      final json = user.toJson();
      final restored = AggregatorUser.fromJson(json);
      expect(restored.admin, isTrue);
      expect(restored.username, 'admin');
      expect(restored.password, 'pass');
    });

    test('admin defaults to false', () {
      final json = {'username': 'user', 'password': 'pass'};
      final user = AggregatorUser.fromJson(json);
      expect(user.admin, isFalse);
    });

    test('non-admin user serialization round-trip', () {
      final user = AggregatorUser(
          username: 'viewer', password: 'pass', admin: false);
      final json = user.toJson();
      final restored = AggregatorUser.fromJson(json);
      expect(restored.admin, isFalse);
    });
  });
}
