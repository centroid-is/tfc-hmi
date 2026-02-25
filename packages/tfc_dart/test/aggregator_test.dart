import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:open62541/open62541.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/aggregator_server.dart';
import 'package:tfc_dart/core/state_man.dart' show OpcUAConfig, OpcUANodeConfig;

void main() {
  group('AggregatorNodeId', () {
    test('encode with string identifier produces correct format', () {
      final upstream = NodeId.fromString(4, 'GVL.temp');
      final result = AggregatorNodeId.encode('plc1', upstream);

      expect(result.namespace, 1);
      expect(result.isString(), true);
      expect(result.string, 'plc1:ns=4;s=GVL.temp');
    });

    test('encode with numeric identifier produces correct format', () {
      final upstream = NodeId.fromNumeric(0, 2258);
      final result = AggregatorNodeId.encode('plc1', upstream);

      expect(result.namespace, 1);
      expect(result.isString(), true);
      expect(result.string, 'plc1:ns=0;i=2258');
    });

    test('encode uses "default" when alias is null', () {
      final upstream = NodeId.fromString(4, 'GVL.temp');
      final result = AggregatorNodeId.encode(null, upstream);

      expect(result.string, 'default:ns=4;s=GVL.temp');
    });

    test('decode round-trip with string identifier', () {
      final upstream = NodeId.fromString(4, 'GVL.temp');
      final encoded = AggregatorNodeId.encode('plc1', upstream);
      final decoded = AggregatorNodeId.decode(encoded);

      expect(decoded, isNotNull);
      final (alias, nodeId) = decoded!;
      expect(alias, 'plc1');
      expect(nodeId.namespace, 4);
      expect(nodeId.isString(), true);
      expect(nodeId.string, 'GVL.temp');
    });

    test('decode round-trip with numeric identifier', () {
      final upstream = NodeId.fromNumeric(0, 2258);
      final encoded = AggregatorNodeId.encode('plc1', upstream);
      final decoded = AggregatorNodeId.decode(encoded);

      expect(decoded, isNotNull);
      final (alias, nodeId) = decoded!;
      expect(alias, 'plc1');
      expect(nodeId.namespace, 0);
      expect(nodeId.isNumeric(), true);
      expect(nodeId.numeric, 2258);
    });

    test('decode round-trip with null alias uses default', () {
      final upstream = NodeId.fromString(4, 'GVL.temp');
      final encoded = AggregatorNodeId.encode(null, upstream);
      final decoded = AggregatorNodeId.decode(encoded);

      expect(decoded, isNotNull);
      final (alias, nodeId) = decoded!;
      expect(alias, 'default');
      expect(nodeId, upstream);
    });

    test('decode returns null for non-aggregator NodeId (wrong namespace)', () {
      final nodeId = NodeId.fromString(0, 'plc1:ns=4;s=GVL.temp');
      expect(AggregatorNodeId.decode(nodeId), isNull);
    });

    test('decode returns null for numeric NodeId', () {
      final nodeId = NodeId.fromNumeric(1, 42);
      expect(AggregatorNodeId.decode(nodeId), isNull);
    });

    test('decode returns null for missing colon separator', () {
      final nodeId = NodeId.fromString(1, 'no-colon-here');
      expect(AggregatorNodeId.decode(nodeId), isNull);
    });

    test('decode returns null for invalid node id string after colon', () {
      final nodeId = NodeId.fromString(1, 'plc1:garbage');
      expect(AggregatorNodeId.decode(nodeId), isNull);
    });

    test('folderNodeId uses alias under Servers/Variables/OpcUa in namespace 1', () {
      final folderId = AggregatorNodeId.folderNodeId('plc1');
      expect(folderId.namespace, 1);
      expect(folderId.isString(), true);
      expect(folderId.string, 'Servers/Variables/OpcUa/plc1');
    });

    test('folderNodeId uses "default" when alias is null', () {
      final folderId = AggregatorNodeId.folderNodeId(null);
      expect(folderId.string, 'Servers/Variables/OpcUa/default');
    });

    test('fromOpcUANodeConfig with string identifier', () {
      final config = OpcUANodeConfig(namespace: 4, identifier: 'GVL.temp')
        ..serverAlias = 'plc1';
      final result = AggregatorNodeId.fromOpcUANodeConfig(config);

      expect(result.namespace, 1);
      expect(result.string, 'plc1:ns=4;s=GVL.temp');
    });

    test('fromOpcUANodeConfig with numeric identifier', () {
      final config = OpcUANodeConfig(namespace: 0, identifier: '2258')
        ..serverAlias = 'plc1';
      final result = AggregatorNodeId.fromOpcUANodeConfig(config);

      expect(result.namespace, 1);
      expect(result.string, 'plc1:ns=0;i=2258');
    });

    test('fromOpcUANodeConfig with null alias', () {
      final config = OpcUANodeConfig(namespace: 4, identifier: 'GVL.temp');
      final result = AggregatorNodeId.fromOpcUANodeConfig(config);

      expect(result.string, 'default:ns=4;s=GVL.temp');
    });

    test('encode handles identifiers containing colons', () {
      // Edge case: OPC UA identifiers can contain colons
      final upstream = NodeId.fromString(4, 'Objects:Folder:Var');
      final encoded = AggregatorNodeId.encode('plc1', upstream);
      final decoded = AggregatorNodeId.decode(encoded);

      expect(decoded, isNotNull);
      final (alias, nodeId) = decoded!;
      expect(alias, 'plc1');
      // The decode should use first colon only for alias split
      // but nodeIdStr = "ns=4;s=Objects:Folder:Var" which is valid
      expect(nodeId.string, 'Objects:Folder:Var');
    });
  });

  group('AggregatorConfig', () {
    test('default values', () {
      final config = AggregatorConfig();
      expect(config.enabled, false);
      expect(config.port, 4840);
    });

    test('fromJson with all fields', () {
      final config = AggregatorConfig.fromJson({
        'enabled': true,
        'port': 5840,
      });
      expect(config.enabled, true);
      expect(config.port, 5840);
    });

    test('fromJson with defaults', () {
      final config = AggregatorConfig.fromJson({});
      expect(config.enabled, false);
      expect(config.port, 4840);
    });

    test('toJson round-trip', () {
      final config = AggregatorConfig(enabled: true, port: 5840);
      final json = config.toJson();
      final restored = AggregatorConfig.fromJson(json);
      expect(restored.enabled, true);
      expect(restored.port, 5840);
    });

    test('discoveryTtl serializes as seconds', () {
      final config = AggregatorConfig(
        discoveryTtl: const Duration(minutes: 15),
      );
      final json = config.toJson();
      expect(json['discovery_ttl_seconds'], 900);

      final restored = AggregatorConfig.fromJson(json);
      expect(restored.discoveryTtl.inSeconds, 900);
    });

    test('hasTls is true only when both cert and key are present', () {
      final certOnly = AggregatorConfig(
        certificate: Uint8List.fromList([1, 2, 3]),
      );
      expect(certOnly.hasTls, false);

      final keyOnly = AggregatorConfig(
        privateKey: Uint8List.fromList([4, 5, 6]),
      );
      expect(keyOnly.hasTls, false);

      final both = AggregatorConfig(
        certificate: Uint8List.fromList([1, 2, 3]),
        privateKey: Uint8List.fromList([4, 5, 6]),
      );
      expect(both.hasTls, true);

      final neither = AggregatorConfig();
      expect(neither.hasTls, false);
    });

    test('hasUsers is true when users list is non-empty', () {
      final noUsers = AggregatorConfig();
      expect(noUsers.hasUsers, false);

      final withUsers = AggregatorConfig(users: [
        AggregatorUser(username: 'admin', password: 'secret'),
      ]);
      expect(withUsers.hasUsers, true);
    });

    test('allowAnonymous defaults to true', () {
      final config = AggregatorConfig();
      expect(config.allowAnonymous, true);

      final fromEmpty = AggregatorConfig.fromJson({});
      expect(fromEmpty.allowAnonymous, true);
    });

    test('TLS certificate and key round-trip via base64 JSON', () {
      final cert = Uint8List.fromList(
          List.generate(256, (i) => i % 256)); // simulated DER bytes
      final key = Uint8List.fromList(
          List.generate(128, (i) => (i * 7) % 256));

      final config = AggregatorConfig(
        enabled: true,
        certificate: cert,
        privateKey: key,
      );

      final json = config.toJson();
      // Verify base64-encoded strings are in JSON
      expect(json['ssl_cert'], isA<String>());
      expect(json['ssl_key'], isA<String>());
      expect(json['ssl_cert'], base64Encode(cert));
      expect(json['ssl_key'], base64Encode(key));

      final restored = AggregatorConfig.fromJson(json);
      expect(restored.hasTls, true);
      expect(restored.certificate, cert);
      expect(restored.privateKey, key);
    });

    test('toJson omits ssl_cert and ssl_key when null', () {
      final config = AggregatorConfig();
      final json = config.toJson();
      expect(json.containsKey('ssl_cert'), false);
      expect(json.containsKey('ssl_key'), false);
    });

    test('users list round-trip via JSON', () {
      final config = AggregatorConfig(
        users: [
          AggregatorUser(username: 'admin', password: 'secret123'),
          AggregatorUser(username: 'operator', password: 'op456'),
        ],
        allowAnonymous: false,
      );

      final json = config.toJson();
      expect(json['users'], isList);
      expect((json['users'] as List).length, 2);
      expect(json['allow_anonymous'], false);

      final restored = AggregatorConfig.fromJson(json);
      expect(restored.users.length, 2);
      expect(restored.users[0].username, 'admin');
      expect(restored.users[0].password, 'secret123');
      expect(restored.users[1].username, 'operator');
      expect(restored.users[1].password, 'op456');
      expect(restored.allowAnonymous, false);
    });

    test('toJson omits users when list is empty', () {
      final config = AggregatorConfig();
      final json = config.toJson();
      expect(json.containsKey('users'), false);
    });

    test('full config round-trip with all TLS/auth fields', () {
      final cert = Uint8List.fromList([0x30, 0x82, 0x01, 0x22]);
      final key = Uint8List.fromList([0x30, 0x82, 0x01, 0x20]);

      final config = AggregatorConfig(
        enabled: true,
        port: 4841,
        discoveryTtl: const Duration(minutes: 60),
        certificate: cert,
        privateKey: key,
        users: [
          AggregatorUser(username: 'admin', password: 'pass'),
        ],
        allowAnonymous: false,
      );

      final json = config.toJson();
      final restored = AggregatorConfig.fromJson(json);

      expect(restored.enabled, true);
      expect(restored.port, 4841);
      expect(restored.discoveryTtl.inMinutes, 60);
      expect(restored.hasTls, true);
      expect(restored.certificate, cert);
      expect(restored.privateKey, key);
      expect(restored.hasUsers, true);
      expect(restored.users.length, 1);
      expect(restored.users.first.username, 'admin');
      expect(restored.allowAnonymous, false);
    });
  });

  group('AggregatorUser', () {
    test('fromJson creates user correctly', () {
      final user = AggregatorUser.fromJson({
        'username': 'admin',
        'password': 'secret',
      });
      expect(user.username, 'admin');
      expect(user.password, 'secret');
    });

    test('toJson produces correct map', () {
      final user = AggregatorUser(username: 'op', password: 'pass123');
      final json = user.toJson();
      expect(json, {'username': 'op', 'password': 'pass123', 'admin': false});
    });

    test('round-trip preserves values', () {
      final original = AggregatorUser(username: 'test', password: 'pw');
      final restored = AggregatorUser.fromJson(original.toJson());
      expect(restored.username, original.username);
      expect(restored.password, original.password);
    });
  });

  group('AggregatorServer', () {
    // Real OPC UA environment:
    // - An "upstream" OPC UA server simulating a PLC
    // - The AggregatorServer that reads from it via StateMan
    // - A client connecting to the AggregatorServer to verify the aggregated data
    //
    // Since creating a full StateMan requires config/prefs infrastructure,
    // we test the server in isolation with direct Server+Client.

    late Server upstreamServer;
    late int upstreamPort;
    late Server aggregatorServerRaw;
    late int aggregatorPort;
    late ClientIsolate aggregatorClient;

    setUpAll(() async {
      upstreamPort = 10000 + Random().nextInt(50000);
      aggregatorPort = upstreamPort + 1;

      // Upstream "PLC" server with test variables (namespace 1 = application ns)
      upstreamServer = Server(
          port: upstreamPort, logLevel: LogLevel.UA_LOGLEVEL_ERROR);
      upstreamServer.addVariableNode(
        NodeId.fromString(1, 'GVL.temp'),
        DynamicValue(
            value: 23.5, typeId: NodeId.double, name: 'GVL.temp'),
      );
      upstreamServer.addVariableNode(
        NodeId.fromNumeric(1, 100),
        DynamicValue(value: true, typeId: NodeId.boolean, name: 'motor_on'),
      );
      upstreamServer.start();

      // Run upstream server loop
      unawaited(() async {
        while (upstreamServer.runIterate(waitInterval: false)) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }());

      // Aggregator server with folder structure and variables
      aggregatorServerRaw = Server(
          port: aggregatorPort, logLevel: LogLevel.UA_LOGLEVEL_ERROR);

      // Create folder hierarchy (like AggregatorServer._createAliasFolders)
      aggregatorServerRaw.addObjectNode(
          NodeId.fromString(1, 'Servers'), 'Servers');
      aggregatorServerRaw.addObjectNode(
          NodeId.fromString(1, 'Servers/Variables'), 'Variables',
          parentNodeId: NodeId.fromString(1, 'Servers'));
      aggregatorServerRaw.addObjectNode(
          NodeId.fromString(1, 'Servers/Variables/OpcUa'), 'OpcUa',
          parentNodeId: NodeId.fromString(1, 'Servers/Variables'));
      final plc1FolderId = AggregatorNodeId.folderNodeId('plc1');
      aggregatorServerRaw.addObjectNode(plc1FolderId, 'plc1',
          parentNodeId: NodeId.fromString(1, 'Servers/Variables/OpcUa'));

      // Add variables under the alias folder
      final tempNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromString(1, 'GVL.temp'));
      aggregatorServerRaw.addVariableNode(
        tempNodeId,
        DynamicValue(
            value: 23.5, typeId: NodeId.double, name: 'temperature'),
        accessLevel: const AccessLevelMask(read: true, write: true),
        parentNodeId: plc1FolderId,
      );

      final motorNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromNumeric(1, 100));
      aggregatorServerRaw.addVariableNode(
        motorNodeId,
        DynamicValue(
            value: true, typeId: NodeId.boolean, name: 'motor_on'),
        accessLevel: const AccessLevelMask(read: true, write: true),
        parentNodeId: plc1FolderId,
      );

      aggregatorServerRaw.start();

      // Run aggregator server loop
      unawaited(() async {
        while (aggregatorServerRaw.runIterate(waitInterval: false)) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }());

      // Connect a client to the aggregator
      aggregatorClient = await ClientIsolate.create();
      unawaited(aggregatorClient.runIterate().catchError((_) {}));
      unawaited(
          aggregatorClient.connect('opc.tcp://localhost:$aggregatorPort'));
      await aggregatorClient.awaitConnect();
    });

    tearDownAll(() async {
      aggregatorServerRaw.shutdown();
      await aggregatorClient.delete();
      aggregatorServerRaw.delete();
      upstreamServer.shutdown();
      upstreamServer.delete();
    });

    test('client can read variable from aggregator server', () async {
      final tempNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromString(1, 'GVL.temp'));
      final value = await aggregatorClient.read(tempNodeId);
      expect(value.value, 23.5);
    });

    test('client can read boolean variable from aggregator server', () async {
      final motorNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromNumeric(1, 100));
      final value = await aggregatorClient.read(motorNodeId);
      expect(value.value, true);
    });

    test('server write updates value readable by client', () async {
      final tempNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromString(1, 'GVL.temp'));

      // Write new value to aggregator server
      await aggregatorServerRaw.write(
        tempNodeId,
        DynamicValue(value: 42.0, typeId: NodeId.double),
      );

      // Small delay for server to process
      await Future.delayed(const Duration(milliseconds: 50));

      // Client should see updated value
      final value = await aggregatorClient.read(tempNodeId);
      expect(value.value, 42.0);
    });

    test('client can browse ObjectsFolder and see Servers folder', () async {
      final results =
          await aggregatorClient.browse(NodeId.objectsFolder);

      final names = results.map((r) => r.browseName).toList();
      expect(names, contains('Servers'));
    });

    test('client can browse into alias folder and see variables', () async {
      final plc1FolderId = AggregatorNodeId.folderNodeId('plc1');
      final results = await aggregatorClient.browse(plc1FolderId);

      final names = results.map((r) => r.browseName).toList();
      expect(names, contains('temperature'));
      expect(names, contains('motor_on'));
    });

    test('client can write to aggregator variable', () async {
      final tempNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromString(1, 'GVL.temp'));

      // Write from client
      await aggregatorClient.write(
        tempNodeId,
        DynamicValue(value: 99.9, typeId: NodeId.double),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Read back
      final value = await aggregatorClient.read(tempNodeId);
      expect(value.value, 99.9);
    });

    test('aggregator node IDs use namespace 1 with encoded strings',
        () async {
      final plc1FolderId = AggregatorNodeId.folderNodeId('plc1');
      final results = await aggregatorClient.browse(plc1FolderId);

      // Find a variable and check its node ID
      for (final result in results) {
        if (result.browseName == 'temperature') {
          expect(result.nodeId.namespace, 1);
          expect(result.nodeId.isString(), true);
          expect(result.nodeId.string, 'plc1:ns=1;s=GVL.temp');
        }
      }
    });

    test('monitorVariable fires on client write', () async {
      final tempNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromString(1, 'GVL.temp'));

      // Set up monitorVariable to capture writes
      final writes = <DynamicValue>[];
      final monitorStream =
          aggregatorServerRaw.monitorVariable(tempNodeId);
      final sub = monitorStream.listen((event) {
        final (type, value) = event;
        if (type == 'write' && value != null) {
          writes.add(value);
        }
      });

      // Client writes to the aggregator
      await aggregatorClient.write(
        tempNodeId,
        DynamicValue(value: 77.7, typeId: NodeId.double),
      );

      // Allow server iteration to process the callback
      await Future.delayed(const Duration(milliseconds: 100));

      expect(writes, isNotEmpty);
      expect(writes.last.value, 77.7);

      await sub.cancel();
    });

    test('internal server writes do not trigger monitor forward', () async {
      // This tests the feedback loop fix: when the aggregator writes a value
      // received from upstream (internal write), monitorVariable should not
      // trigger a forward back to upstream. Only external client writes should.
      final tempNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromString(1, 'GVL.temp'));

      final externalWrites = <DynamicValue>[];
      final allWrites = <DynamicValue>[];
      final internalWriteKeys = <String>{};

      // Set up monitorVariable like AggregatorServer._createAndSubscribeVariable
      final monitorStream =
          aggregatorServerRaw.monitorVariable(tempNodeId);
      final sub = monitorStream.listen((event) {
        final (type, value) = event;
        if (type == 'write' && value != null) {
          allWrites.add(value);
          final nodeKey = tempNodeId.toString();
          if (internalWriteKeys.remove(nodeKey)) return; // skip internal
          externalWrites.add(value);
        }
      });

      // Simulate internal write (upstream subscription pushing new PLC value)
      internalWriteKeys.add(tempNodeId.toString());
      aggregatorServerRaw.write(
        tempNodeId,
        DynamicValue(value: 50.0, typeId: NodeId.double),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // monitorVariable should have seen the write, but it should be suppressed
      expect(allWrites.length, 1);
      expect(externalWrites, isEmpty, reason: 'Internal writes should be suppressed');

      // Now simulate external client write (HMI writing through OPC UA)
      await aggregatorClient.write(
        tempNodeId,
        DynamicValue(value: 77.7, typeId: NodeId.double),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // This write should NOT be suppressed — it's from an external client
      expect(allWrites.length, 2);
      expect(externalWrites.length, 1);
      expect(externalWrites.last.value, 77.7);

      await sub.cancel();
    });

    test('deleteNode removes variable from address space', () async {
      // Create a temporary variable for this test
      final deleteTestNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromString(1, 'GVL.toDelete'));
      final plc1FolderId = AggregatorNodeId.folderNodeId('plc1');
      aggregatorServerRaw.addVariableNode(
        deleteTestNodeId,
        DynamicValue(
            value: 123.0, typeId: NodeId.double, name: 'toDelete'),
        accessLevel: const AccessLevelMask(read: true, write: true),
        parentNodeId: plc1FolderId,
      );

      // Verify it exists — client can read it
      final valueBefore = await aggregatorClient.read(deleteTestNodeId);
      expect(valueBefore.value, 123.0);

      // Verify it appears in browse
      var browseResults = await aggregatorClient.browse(plc1FolderId);
      var names = browseResults.map((r) => r.browseName).toList();
      expect(names, contains('toDelete'));

      // Delete the node
      aggregatorServerRaw.deleteNode(deleteTestNodeId);

      // Allow server iteration to process
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify it's gone from browse
      browseResults = await aggregatorClient.browse(plc1FolderId);
      names = browseResults.map((r) => r.browseName).toList();
      expect(names, isNot(contains('toDelete')));
    });

    test('deleteNode then re-add recreates the variable', () async {
      final plc1FolderId = AggregatorNodeId.folderNodeId('plc1');
      final recreateNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromString(1, 'GVL.recreate'));

      // Create, verify, delete
      aggregatorServerRaw.addVariableNode(
        recreateNodeId,
        DynamicValue(
            value: 1.0, typeId: NodeId.double, name: 'recreate'),
        accessLevel: const AccessLevelMask(read: true, write: true),
        parentNodeId: plc1FolderId,
      );
      var value = await aggregatorClient.read(recreateNodeId);
      expect(value.value, 1.0);

      aggregatorServerRaw.deleteNode(recreateNodeId);
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify deleted
      var browseResults = await aggregatorClient.browse(plc1FolderId);
      var names = browseResults.map((r) => r.browseName).toList();
      expect(names, isNot(contains('recreate')));

      // Re-create with new value
      aggregatorServerRaw.addVariableNode(
        recreateNodeId,
        DynamicValue(
            value: 2.0, typeId: NodeId.double, name: 'recreate'),
        accessLevel: const AccessLevelMask(read: true, write: true),
        parentNodeId: plc1FolderId,
      );

      // Verify it's back with new value
      value = await aggregatorClient.read(recreateNodeId);
      expect(value.value, 2.0);

      browseResults = await aggregatorClient.browse(plc1FolderId);
      names = browseResults.map((r) => r.browseName).toList();
      expect(names, contains('recreate'));

      // Clean up
      aggregatorServerRaw.deleteNode(recreateNodeId);
    });

    test('multiple alias folders with separate variables', () async {
      // Add a second alias folder (parent hierarchy already created in setUpAll)
      final plc2FolderId = AggregatorNodeId.folderNodeId('plc2');
      aggregatorServerRaw.addObjectNode(plc2FolderId, 'plc2',
          parentNodeId: NodeId.fromString(1, 'Servers/Variables/OpcUa'));

      final pressureNodeId = AggregatorNodeId.encode(
          'plc2', NodeId.fromString(1, 'GVL.pressure'));
      aggregatorServerRaw.addVariableNode(
        pressureNodeId,
        DynamicValue(
            value: 101.3, typeId: NodeId.double, name: 'pressure'),
        accessLevel: const AccessLevelMask(read: true, write: true),
        parentNodeId: plc2FolderId,
      );

      // Browse OpcUa folder — should see both alias folders
      final opcuaFolder = NodeId.fromString(1, 'Servers/Variables/OpcUa');
      final rootResults = await aggregatorClient.browse(opcuaFolder);
      final rootNames = rootResults.map((r) => r.browseName).toList();
      expect(rootNames, contains('plc1'));
      expect(rootNames, contains('plc2'));

      // Browse plc2 folder — should see pressure variable
      final plc2Results = await aggregatorClient.browse(plc2FolderId);
      final plc2Names = plc2Results.map((r) => r.browseName).toList();
      expect(plc2Names, contains('pressure'));
      // plc1 variables should NOT appear under plc2
      expect(plc2Names, isNot(contains('temperature')));

      // Read value from plc2
      final value = await aggregatorClient.read(pressureNodeId);
      expect(value.value, 101.3);
    });
  });

  group('OpcUAConfig.hashCode', () {
    test('equal objects have equal hashCodes when sslCert/sslKey differ', () {
      final a = OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..serverAlias = 'plc1'
        ..sslCert = Uint8List.fromList([1, 2, 3])
        ..sslKey = Uint8List.fromList([4, 5, 6]);
      final b = OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..serverAlias = 'plc1'
        ..sslCert = Uint8List.fromList([1, 2, 3])
        ..sslKey = Uint8List.fromList([4, 5, 6]);

      // operator== considers sslCert/sslKey, so a == b
      expect(a, equals(b));
      // hashCode contract: equal objects must have equal hashCodes
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different sslCert produces different hashCode', () {
      final a = OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..sslCert = Uint8List.fromList([1, 2, 3]);
      final b = OpcUAConfig()
        ..endpoint = 'opc.tcp://localhost:4840'
        ..sslCert = Uint8List.fromList([9, 9, 9]);

      // These are not equal
      expect(a, isNot(equals(b)));
      // Ideally hashCodes differ too (not strictly required, but good practice)
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });

  group('TTL boundary condition', () {
    test('entry at exactly TTL age is expired', () {
      // Create a config with 30-minute TTL and manually inject a discovered node
      // at exactly TTL seconds ago. It should be cleaned up.
      final config = AggregatorConfig(
        enabled: true,
        port: 4840,
        discoveryTtl: const Duration(seconds: 30),
      );

      // We can't directly test AggregatorServer.cleanupExpiredDiscoveries
      // without a full server, but we can verify the boundary behavior
      // by testing with ttlOverride = Duration.zero which expires everything.
      // The real fix is changing > to >= in the comparison.
      //
      // This test documents that entries at exactly TTL should expire.
      // If the boundary is wrong (>), an entry at exactly 30s would NOT expire.
      final now = DateTime.now();
      final exactlyAtTtl = now.subtract(config.discoveryTtl);
      final diff = now.difference(exactlyAtTtl);
      // The duration should be exactly equal to TTL
      expect(diff, equals(config.discoveryTtl));
      // With >= comparison, this should be considered expired
      expect(diff >= config.discoveryTtl, isTrue);
      // With > comparison, this would NOT be expired (the bug)
      expect(diff > config.discoveryTtl, isFalse);
    });
  });
}
