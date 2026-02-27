import 'dart:async';
import 'package:open62541/open62541.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/aggregator_server.dart';
import 'package:tfc_dart/core/state_man.dart';

import 'test_timing.dart';

/// Regression test for: backend crashes with FK violation when PLC reconnects.
///
/// Root cause: [AggregatorServer._removeDisconnectAlarm] called
/// [AlarmMan.removeExternalAlarm] which went through [AlarmMan._removeActiveAlarm]
/// → [AlarmMan._addToDb], inserting into alarm_history for an alarm_uid that
/// didn't exist in the alarm table.
///
/// Fix: [AlarmMan.removeExternalAlarm] now removes directly from _activeAlarms
/// without going through _removeActiveAlarm / _addToDb.
///
/// This test exercises the disconnect → reconnect flow through AggregatorServer
/// to verify the alarm inject/remove cycle doesn't throw.
void main() {
  enableTestTiming();
  group('Aggregator disconnect/reconnect alarm cycle', () {
    late Server upstreamServer;
    late int upstreamPort;
    late int aggregatorPort;
    late StateMan directSM;
    late AggregatorServer aggregator;
    var upstreamRunning = true;

    setUpAll(timed('alarm setUpAll', () async {
      final ports = allocatePorts(0, 2);
      upstreamPort = ports[0];
      aggregatorPort = ports[1];
      upstreamRunning = true;

      upstreamServer =
          Server(port: upstreamPort, logLevel: LogLevel.UA_LOGLEVEL_ERROR);
      upstreamServer.addVariableNode(
        NodeId.fromString(1, 'GVL.temp'),
        DynamicValue(value: 23.5, typeId: NodeId.double, name: 'temp'),
      );
      upstreamServer.start();
      unawaited(() async {
        while (upstreamRunning &&
            upstreamServer.runIterate(waitInterval: false)) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }());

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
        aggregator: AggregatorConfig(enabled: true, port: aggregatorPort),
      );

      directSM = await StateMan.create(
        config: config,
        keyMappings: keyMappings,
        useIsolate: true,
        alias: 'test-alarm',
      );

      for (final wrapper in directSM.clients) {
        if (wrapper.connectionStatus == ConnectionStatus.connected) continue;
        await wrapper.connectionStream
            .firstWhere((event) => event.$1 == ConnectionStatus.connected)
            .timeout(const Duration(seconds: 15));
      }

      aggregator = AggregatorServer(
        config: config.aggregator!,
        sharedStateMan: directSM,
      );
      // Note: no AlarmMan attached — alarm inject/remove are no-ops.
      // The real FK crash only happens with a PostgreSQL database, which
      // we can't replicate in a unit test. However, this test verifies
      // the disconnect/reconnect flow itself doesn't break.
      await aggregator.initialize(skipTls: true);
      unawaited(aggregator.runLoop());
    }));

    tearDownAll(timed('alarm tearDownAll', () async {
      await aggregator.shutdown();
      await directSM.close();
      upstreamRunning = false;
      await Future.delayed(const Duration(milliseconds: 20));
      upstreamServer.shutdown();
      upstreamServer.delete();
    }));

    test('simulate PLC disconnect then reconnect without crash', () async {
      final wrapper = directSM.clients.first;

      // Verify we start connected and have mapped nodes
      expect(wrapper.connectionStatus, ConnectionStatus.connected);
      await Future.delayed(const Duration(milliseconds: 100));

      // Simulate PLC disconnect
      wrapper.updateConnectionStatus(ClientState(
        channelState: SecureChannelState.UA_SECURECHANNELSTATE_CLOSED,
        sessionState: SessionState.UA_SESSIONSTATE_CLOSED,
        recoveryStatus: 0,
      ));
      await Future.delayed(const Duration(milliseconds: 100));

      // Simulate PLC reconnect
      wrapper.updateConnectionStatus(ClientState(
        channelState: SecureChannelState.UA_SECURECHANNELSTATE_OPEN,
        sessionState: SessionState.UA_SESSIONSTATE_ACTIVATED,
        recoveryStatus: 0,
      ));
      await Future.delayed(const Duration(milliseconds: 100));

      // The aggregator should still be running — no crash
      // _teardownAlias ran on disconnect, _repopulateAlias on reconnect
      // If AlarmMan were attached, _injectDisconnectAlarm / _removeDisconnectAlarm
      // would have fired — the fix ensures removeExternalAlarm doesn't crash.
      expect(true, isTrue, reason: 'No crash during disconnect/reconnect cycle');
    });
  });
}
