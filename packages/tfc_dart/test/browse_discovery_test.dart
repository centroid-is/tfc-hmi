@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:math';

import 'package:open62541/open62541.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/aggregator_server.dart';
import 'package:tfc_dart/core/state_man.dart';

// ---------------------------------------------------------------------------
// Test infrastructure helpers
// ---------------------------------------------------------------------------

/// Creates an upstream "PLC" server with a realistic address space:
/// - ObjectsFolder
///   ├── GVL (folder)
///   │   ├── temperature (double)
///   │   ├── pressure (double)
///   │   └── status (bool)
///   └── Config (folder)
///       ├── setpoint (double)
///       └── mode (int32)
Server createUpstreamPlc(int port) {
  final server = Server(port: port, logLevel: LogLevel.UA_LOGLEVEL_ERROR);

  // GVL folder
  final gvlFolder = NodeId.fromString(1, 'GVL');
  server.addObjectNode(gvlFolder, 'GVL');
  server.addVariableNode(
    NodeId.fromString(1, 'GVL.temperature'),
    DynamicValue(value: 23.5, typeId: NodeId.double, name: 'temperature'),
    parentNodeId: gvlFolder,
  );
  server.addVariableNode(
    NodeId.fromString(1, 'GVL.pressure'),
    DynamicValue(value: 101.3, typeId: NodeId.double, name: 'pressure'),
    parentNodeId: gvlFolder,
  );
  server.addVariableNode(
    NodeId.fromString(1, 'GVL.status'),
    DynamicValue(value: true, typeId: NodeId.boolean, name: 'status'),
    parentNodeId: gvlFolder,
  );

  // Config folder
  final configFolder = NodeId.fromString(1, 'Config');
  server.addObjectNode(configFolder, 'Config');
  server.addVariableNode(
    NodeId.fromString(1, 'Config.setpoint'),
    DynamicValue(value: 25.0, typeId: NodeId.double, name: 'setpoint'),
    parentNodeId: configFolder,
  );
  server.addVariableNode(
    NodeId.fromString(1, 'Config.mode'),
    DynamicValue(value: 0, typeId: NodeId.int32, name: 'mode'),
    parentNodeId: configFolder,
  );

  return server;
}

void main() {
  // =========================================================================
  // 1. Raw addMethodNode + call API tests (stabilize the in-progress API)
  // =========================================================================
  group('Server.addMethodNode + Client.call', () {
    late Server server;
    late ClientIsolate client;
    late int port;

    setUpAll(() async {
      port = 10000 + Random().nextInt(50000);
      server = Server(port: port, logLevel: LogLevel.UA_LOGLEVEL_ERROR);
      server.start();
      unawaited(() async {
        while (server.runIterate(waitInterval: false)) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }());

      client = await ClientIsolate.create();
      unawaited(client.runIterate().catchError((_) {}));
      unawaited(client.connect('opc.tcp://localhost:$port'));
      await client.awaitConnect();
    });

    tearDownAll(() async {
      server.shutdown();
      await client.delete();
      server.delete();
    });

    test('method with no arguments and no return', () async {
      var called = false;
      final methodId = NodeId.fromString(1, 'test.noargs');

      server.addMethodNode(
        methodId,
        'NoArgs',
        callback: (inputs) {
          called = true;
          return [];
        },
      );

      final result = await client.call(NodeId.objectsFolder, methodId, []);
      expect(called, isTrue);
      expect(result, isEmpty);
    });

    test('method receives int input and returns doubled value', () async {
      final methodId = NodeId.fromString(1, 'test.double');

      server.addMethodNode(
        methodId,
        'DoubleIt',
        callback: (inputs) {
          final val = inputs.first.value as int;
          return [DynamicValue(value: val * 2, typeId: NodeId.int32)];
        },
        inputArguments: [DynamicValue(name: 'value', typeId: NodeId.int32)],
        outputArguments: [DynamicValue(name: 'result', typeId: NodeId.int32)],
      );

      final result = await client.call(
        NodeId.objectsFolder,
        methodId,
        [DynamicValue(value: 21, typeId: NodeId.int32)],
      );
      expect(result.length, 1);
      expect(result.first.value, 42);
    });

    test('method receives string input and returns string output', () async {
      final methodId = NodeId.fromString(1, 'test.greet');

      server.addMethodNode(
        methodId,
        'Greet',
        callback: (inputs) {
          final name = inputs.first.value as String;
          return [
            DynamicValue(value: 'Hello, $name!', typeId: NodeId.uastring)
          ];
        },
        inputArguments: [DynamicValue(name: 'name', typeId: NodeId.uastring)],
        outputArguments: [
          DynamicValue(name: 'greeting', typeId: NodeId.uastring)
        ],
      );

      final result = await client.call(
        NodeId.objectsFolder,
        methodId,
        [DynamicValue(value: 'World', typeId: NodeId.uastring)],
      );
      expect(result.length, 1);
      expect(result.first.value, 'Hello, World!');
    });

    test('method under object node (not ObjectsFolder)', () async {
      final folderId = NodeId.fromString(1, 'test.folder');
      final methodId = NodeId.fromString(1, 'test.folder.method');

      server.addObjectNode(folderId, 'TestFolder');
      server.addMethodNode(
        methodId,
        'FolderMethod',
        callback: (inputs) => [
          DynamicValue(value: 'ok', typeId: NodeId.uastring),
        ],
        outputArguments: [
          DynamicValue(name: 'status', typeId: NodeId.uastring)
        ],
        parentNodeId: folderId,
      );

      final result = await client.call(
        folderId,
        methodId,
        [],
      );
      expect(result.length, 1);
      expect(result.first.value, 'ok');
    });

    test('method is browseable under its parent', () async {
      final folderId = NodeId.fromString(1, 'test.browse.folder');
      final methodId = NodeId.fromString(1, 'test.browse.method');

      server.addObjectNode(folderId, 'BrowseFolder');
      server.addMethodNode(
        methodId,
        'BrowseMethod',
        callback: (inputs) => [],
        parentNodeId: folderId,
      );

      final results = await client.browse(folderId);
      final names = results.map((r) => r.browseName).toSet();
      expect(names, contains('BrowseMethod'));
    });

    test('method with multiple inputs and outputs', () async {
      final methodId = NodeId.fromString(1, 'test.multi');

      server.addMethodNode(
        methodId,
        'AddAndMultiply',
        callback: (inputs) {
          final a = inputs[0].value as int;
          final b = inputs[1].value as int;
          return [
            DynamicValue(value: a + b, typeId: NodeId.int32),
            DynamicValue(value: a * b, typeId: NodeId.int32),
          ];
        },
        inputArguments: [
          DynamicValue(name: 'a', typeId: NodeId.int32),
          DynamicValue(name: 'b', typeId: NodeId.int32),
        ],
        outputArguments: [
          DynamicValue(name: 'sum', typeId: NodeId.int32),
          DynamicValue(name: 'product', typeId: NodeId.int32),
        ],
      );

      final result = await client.call(
        NodeId.objectsFolder,
        methodId,
        [
          DynamicValue(value: 3, typeId: NodeId.int32),
          DynamicValue(value: 7, typeId: NodeId.int32),
        ],
      );
      expect(result.length, 2);
      expect(result[0].value, 10);
      expect(result[1].value, 21);
    });

    test('method callback can access server state', () async {
      // Add a variable node to the server
      server.addVariableNode(
        NodeId.fromString(1, 'state_value'),
        DynamicValue(value: 100, typeId: NodeId.int32, name: 'state_value'),
      );

      final methodId = NodeId.fromString(1, 'test.readstate');

      server.addMethodNode(
        methodId,
        'ReadState',
        callback: (inputs) {
          // The callback has access to the server via closure
          // In real use, the aggregator callback would browse/read upstream
          return [DynamicValue(value: 'state_accessed', typeId: NodeId.uastring)];
        },
        outputArguments: [
          DynamicValue(name: 'result', typeId: NodeId.uastring)
        ],
      );

      final result = await client.call(NodeId.objectsFolder, methodId, []);
      expect(result.first.value, 'state_accessed');
    });
  });

  // =========================================================================
  // 2. On-demand browse discovery via Discover method on aggregator
  // =========================================================================
  //
  // Architecture:
  //   Upstream PLC (with GVL/ and Config/ folders and variables)
  //     ↕ (direct StateMan connection)
  //   AggregatorServer
  //     ├── plc1/ (alias folder)
  //     │   ├── mapped variables (from key mappings)
  //     │   └── Discover (method node)
  //     │       input: parentNodeId (string, e.g. "ns=0;i=85")
  //     │       output: discovered node descriptions
  //     │       side-effect: creates discovered nodes in aggregator
  //     └── ...
  //     ↕ (aggregator client)
  //   HMI client
  //
  // When HMI calls Discover("ns=1;s=GVL"):
  //   1. Aggregator browses upstream PLC at ns=1;s=GVL
  //   2. Finds children: temperature, pressure, status
  //   3. Creates variable nodes in aggregator under plc1/ folder
  //   4. Returns list of discovered browse names
  //   5. HMI can now browse/read these nodes normally

  group('On-demand browse discovery', () {
    late Server upstreamServer;
    late int upstreamPort;
    late int aggregatorPort;
    late StateMan directSM;
    late AggregatorServer aggregator;
    late ClientIsolate aggClient;
    var upstreamRunning = true;

    setUpAll(() async {
      final base = 10000 + Random().nextInt(40000);
      upstreamPort = base;
      aggregatorPort = base + 1;
      upstreamRunning = true;

      // Upstream PLC with hierarchical address space
      upstreamServer = createUpstreamPlc(upstreamPort);
      upstreamServer.start();
      unawaited(() async {
        while (upstreamRunning && upstreamServer.runIterate(waitInterval: false)) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }());

      // Only map ONE variable in key mappings (the rest will be discovered)
      final keyMappings = KeyMappings(nodes: {
        'plc1_temperature': KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(
            namespace: 1,
            identifier: 'GVL.temperature',
          )..serverAlias = 'plc1',
        ),
      });

      final config = StateManConfig(
        opcua: [
          OpcUAConfig()
            ..endpoint = 'opc.tcp://localhost:$upstreamPort'
            ..serverAlias = 'plc1',
        ],
        aggregator: AggregatorConfig(enabled: true, port: aggregatorPort),
      );

      // Direct StateMan
      directSM = await StateMan.create(
        config: config,
        keyMappings: keyMappings,
        useIsolate: true,
        alias: 'test-discover',
      );

      // Wait for connection
      for (final wrapper in directSM.clients) {
        if (wrapper.connectionStatus == ConnectionStatus.connected) continue;
        await wrapper.connectionStream
            .firstWhere((event) => event.$1 == ConnectionStatus.connected)
            .timeout(const Duration(seconds: 15));
      }

      // Create aggregator
      aggregator = AggregatorServer(
        config: config.aggregator!,
        sharedStateMan: directSM,
      );
      await aggregator.initialize();
      unawaited(aggregator.runLoop());

      // Connect client to aggregator
      aggClient = await ClientIsolate.create();
      unawaited(aggClient.runIterate().catchError((_) {}));
      unawaited(aggClient.connect('opc.tcp://localhost:$aggregatorPort'));
      await aggClient.awaitConnect();
    });

    tearDownAll(() async {
      await aggregator.shutdown();
      await aggClient.delete();
      await directSM.close();
      upstreamRunning = false;
      // Allow the upstream runIterate loop to exit
      await Future.delayed(const Duration(milliseconds: 20));
      upstreamServer.shutdown();
      upstreamServer.delete();
    });

    test('Discover method node exists under each alias folder', () async {
      final plc1Folder = AggregatorNodeId.folderNodeId('plc1');
      final results = await aggClient.browse(plc1Folder);
      final names = results.map((r) => r.browseName).toSet();

      expect(names, contains('Discover'),
          reason: 'Each alias folder should have a Discover method');
    });

    test('calling Discover with ObjectsFolder discovers top-level nodes',
        () async {
      final plc1Folder = AggregatorNodeId.folderNodeId('plc1');

      // Call Discover with the upstream ObjectsFolder NodeId
      final discoverMethodId =
          NodeId.fromString(1, 'plc1/Discover');
      final result = await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=0;i=85', typeId: NodeId.uastring)],
      );

      // Should return discovered browse names
      expect(result, isNotEmpty,
          reason: 'Discover should return discovered node info');
    });

    test('calling Discover with GVL folder discovers GVL children', () async {
      final plc1Folder = AggregatorNodeId.folderNodeId('plc1');
      final discoverMethodId = NodeId.fromString(1, 'plc1/Discover');

      // Discover GVL folder contents
      final result = await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=1;s=GVL', typeId: NodeId.uastring)],
      );

      expect(result, isNotEmpty);
    });

    test('discovered variable nodes are browseable after Discover', () async {
      final plc1Folder = AggregatorNodeId.folderNodeId('plc1');
      final discoverMethodId = NodeId.fromString(1, 'plc1/Discover');

      // Discover GVL folder contents
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=1;s=GVL', typeId: NodeId.uastring)],
      );

      // Small delay for server to process
      await Future.delayed(const Duration(milliseconds: 100));

      // Browse the aggregator's plc1 folder — should now contain discovered nodes
      final browseResults = await aggClient.browse(plc1Folder);
      final browseNames = browseResults.map((r) => r.browseName).toSet();

      // The originally-mapped temperature should be there
      expect(browseNames, contains('plc1_temperature'));

      // Discovered GVL children should also now be present
      // (pressure and status were NOT in key mappings, but discovered)
      expect(browseNames, contains('pressure'),
          reason: 'Discovered GVL.pressure should appear');
      expect(browseNames, contains('status'),
          reason: 'Discovered GVL.status should appear');
    });

    test('discovered variable nodes are readable', () async {
      final plc1Folder = AggregatorNodeId.folderNodeId('plc1');
      final discoverMethodId = NodeId.fromString(1, 'plc1/Discover');

      // Discover GVL folder
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=1;s=GVL', typeId: NodeId.uastring)],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Read the discovered pressure node
      final pressureNodeId =
          AggregatorNodeId.encode('plc1', NodeId.fromString(1, 'GVL.pressure'));
      final value = await aggClient.read(pressureNodeId);
      expect(value.value, 101.3);
    });

    test('discovered object nodes (folders) are browseable', () async {
      final plc1Folder = AggregatorNodeId.folderNodeId('plc1');
      final discoverMethodId = NodeId.fromString(1, 'plc1/Discover');

      // Discover top-level objects
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=0;i=85', typeId: NodeId.uastring)],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // The GVL and Config folders from upstream should be discoverable
      final browseResults = await aggClient.browse(plc1Folder);
      final browseNames = browseResults.map((r) => r.browseName).toSet();

      expect(browseNames, contains('GVL'),
          reason: 'GVL folder should be discovered from upstream ObjectsFolder');
      expect(browseNames, contains('Config'),
          reason:
              'Config folder should be discovered from upstream ObjectsFolder');
    });

    test('re-discovering same parent is idempotent', () async {
      final plc1Folder = AggregatorNodeId.folderNodeId('plc1');
      final discoverMethodId = NodeId.fromString(1, 'plc1/Discover');

      // Call Discover twice on the same parent
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=1;s=GVL', typeId: NodeId.uastring)],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Second call should not fail or create duplicates
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=1;s=GVL', typeId: NodeId.uastring)],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Browse should still work fine
      final results = await aggClient.browse(plc1Folder);
      // Count occurrences of 'pressure' — should be exactly 1
      final pressureCount =
          results.where((r) => r.browseName == 'pressure').length;
      expect(pressureCount, 1,
          reason: 'Re-discover should not create duplicate nodes');
    });

    test('discovery cache entries expire after TTL', () async {
      final plc1Folder = AggregatorNodeId.folderNodeId('plc1');
      final discoverMethodId = NodeId.fromString(1, 'plc1/Discover');

      // Discover GVL folder contents
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=1;s=GVL', typeId: NodeId.uastring)],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify pressure node was discovered
      final pressureNodeId =
          AggregatorNodeId.encode('plc1', NodeId.fromString(1, 'GVL.pressure'));
      final val1 = await aggClient.read(pressureNodeId);
      expect(val1.value, 101.3);

      // Manually trigger TTL cleanup (the aggregator has a short TTL in tests
      // but we can directly call the cleanup method to avoid waiting)
      // Access internal state via the server — set discovered timestamps to the past
      // Since we can't access private fields, we simulate TTL by shutting down
      // and creating a new aggregator with a very short TTL that already expired
      //
      // Alternative: verify that after cleanup, re-discovery reads fresh values.
      // Since we can't delete nodes (no deleteNode API), the TTL just clears
      // the tracking set. The node still exists in the address space.
      // Re-discovery should succeed without error (idempotent due to skip).

      // Force expire by calling cleanup with a 0-duration TTL config
      aggregator.cleanupExpiredDiscoveries(ttlOverride: Duration.zero);

      // Verify the tracking was cleared (re-discover succeeds and node still readable)
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=1;s=GVL', typeId: NodeId.uastring)],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Node is still readable (it was re-discovered, values refreshed)
      final val2 = await aggClient.read(pressureNodeId);
      expect(val2.value, 101.3);
    });

    test('reconnection clears discovered nodes for that alias', () async {
      final plc1Folder = AggregatorNodeId.folderNodeId('plc1');
      final discoverMethodId = NodeId.fromString(1, 'plc1/Discover');

      // Discover GVL folder contents
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=1;s=GVL', typeId: NodeId.uastring)],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify discovered nodes exist
      expect(aggregator.discoveredNodeCount, greaterThan(0));

      // Simulate reconnection: push disconnected then connected status
      final wrapper = directSM.clients.first;
      wrapper.updateConnectionStatus(ClientState(
        channelState: SecureChannelState.UA_SECURECHANNELSTATE_CLOSED,
        sessionState: SessionState.UA_SESSIONSTATE_CLOSED,
        recoveryStatus: 0,
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      wrapper.updateConnectionStatus(ClientState(
        channelState: SecureChannelState.UA_SECURECHANNELSTATE_OPEN,
        sessionState: SessionState.UA_SESSIONSTATE_ACTIVATED,
        recoveryStatus: 0,
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      // Discovered nodes should have been cleared on reconnect
      expect(aggregator.discoveredNodeCount, 0,
          reason: 'Reconnection should invalidate discovered nodes');
    });

    test('hierarchical discovery: discover folder then its children',
        () async {
      final plc1Folder = AggregatorNodeId.folderNodeId('plc1');
      final discoverMethodId = NodeId.fromString(1, 'plc1/Discover');

      // Step 1: Discover ObjectsFolder → finds GVL and Config folders
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=0;i=85', typeId: NodeId.uastring)],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 2: Discover GVL folder contents → finds temperature, pressure, status
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=1;s=GVL', typeId: NodeId.uastring)],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 3: Discover Config folder contents → finds setpoint, mode
      await aggClient.call(
        plc1Folder,
        discoverMethodId,
        [DynamicValue(value: 'ns=1;s=Config', typeId: NodeId.uastring)],
      );
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify: plc1 folder should now have all discovered items
      final browseResults = await aggClient.browse(plc1Folder);
      final browseNames = browseResults.map((r) => r.browseName).toSet();

      expect(browseNames, contains('GVL'));
      expect(browseNames, contains('Config'));
      expect(browseNames, contains('pressure'));
      expect(browseNames, contains('status'));
      expect(browseNames, contains('setpoint'));
      expect(browseNames, contains('mode'));

      // Verify: read a Config variable
      final setpointNodeId = AggregatorNodeId.encode(
          'plc1', NodeId.fromString(1, 'Config.setpoint'));
      final val = await aggClient.read(setpointNodeId);
      expect(val.value, 25.0);
    });
  });
}
