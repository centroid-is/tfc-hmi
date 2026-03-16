import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';

import 'package:tfc/mcp/mcp_bridge_notifier.dart';

/// Tests the in-memory proposal callback chain:
///
///   ProposalService.wrapProposal()
///     -> onProposal callback
///     -> McpBridgeNotifier._proposalController
///     -> proposalStream
///
/// This is the path that fires when the SSE HTTP server executes a write
/// tool (create_alarm, create_page, etc.) on behalf of an external client
/// (e.g., the Python proxy / Claude Agent SDK).
void main() {
  group('ProposalService callback', () {
    test('onProposal callback fires with wrapped proposal', () async {
      final callbackFired = Completer<Map<String, dynamic>>();
      final service = ProposalService(
        onProposal: (wrapped) => callbackFired.complete(wrapped),
      );

      final result = service.wrapProposal('alarm', {
        'title': 'Test Alarm',
        'key': 'test.key',
      });

      expect(result['_proposal_type'], 'alarm');
      expect(result['title'], 'Test Alarm');

      final callbackResult =
          await callbackFired.future.timeout(const Duration(seconds: 1));
      expect(callbackResult['_proposal_type'], 'alarm');
      expect(callbackResult['title'], 'Test Alarm');
    });

    test('fires callback for each proposal type', () {
      final received = <Map<String, dynamic>>[];
      final service = ProposalService(onProposal: received.add);

      service.wrapProposal('alarm', {'title': 'Alarm'});
      service.wrapProposal('page', {'title': 'Page'});
      service.wrapProposal('asset', {'title': 'Asset'});
      service.wrapProposal('key_mapping', {'key': 'k'});

      expect(received, hasLength(4));
      expect(received[0]['_proposal_type'], 'alarm');
      expect(received[1]['_proposal_type'], 'page');
      expect(received[2]['_proposal_type'], 'asset');
      expect(received[3]['_proposal_type'], 'key_mapping');
    });

    test('null callback does not throw', () {
      final service = ProposalService();
      final result = service.wrapProposal('alarm', {'title': 'Test'});
      expect(result['_proposal_type'], 'alarm');
    });
  });

  group('McpBridgeNotifier.proposalStream', () {
    test('testFireProposal delivers event to proposalStream', () async {
      final bridge = McpBridgeNotifier();
      addTearDown(() => bridge.dispose());

      final received = <String>[];
      final completer = Completer<void>();
      final sub = bridge.proposalStream.listen((json) {
        received.add(json);
        if (!completer.isCompleted) completer.complete();
      });
      addTearDown(sub.cancel);

      // Fire a proposal through the bridge's internal callback
      bridge.testFireProposal({
        '_proposal_type': 'alarm',
        'title': 'Test Alarm',
      });

      await completer.future.timeout(const Duration(seconds: 2));

      expect(received, hasLength(1));
      final decoded = jsonDecode(received.first) as Map<String, dynamic>;
      expect(decoded['_proposal_type'], 'alarm');
      expect(decoded['title'], 'Test Alarm');
    });

    test('multiple proposals arrive in order', () async {
      final bridge = McpBridgeNotifier();
      addTearDown(() => bridge.dispose());

      final received = <String>[];
      final sub = bridge.proposalStream.listen(received.add);
      addTearDown(sub.cancel);

      bridge.testFireProposal({
        '_proposal_type': 'alarm',
        'title': 'Alarm 1',
      });
      bridge.testFireProposal({
        '_proposal_type': 'page',
        'title': 'Page 1',
      });
      bridge.testFireProposal({
        '_proposal_type': 'asset',
        'title': 'Asset 1',
      });

      // Let events propagate through the broadcast stream
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received, hasLength(3));
      expect(jsonDecode(received[0])['_proposal_type'], 'alarm');
      expect(jsonDecode(received[1])['_proposal_type'], 'page');
      expect(jsonDecode(received[2])['_proposal_type'], 'asset');
    });

    test('disposed bridge does not deliver events', () async {
      final bridge = McpBridgeNotifier();

      final received = <String>[];
      final sub = bridge.proposalStream.listen(received.add);

      await bridge.dispose();

      // This should NOT add to the stream because _disposed is true
      bridge.testFireProposal({
        '_proposal_type': 'alarm',
        'title': 'Should Not Arrive',
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received, isEmpty);
      sub.cancel();
    });

    test('late subscriber misses events (broadcast stream behavior)', () async {
      final bridge = McpBridgeNotifier();
      addTearDown(() => bridge.dispose());

      // Fire event BEFORE subscribing
      bridge.testFireProposal({
        '_proposal_type': 'alarm',
        'title': 'Early Event',
      });

      // Give event time to propagate
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Now subscribe
      final received = <String>[];
      final sub = bridge.proposalStream.listen(received.add);
      addTearDown(sub.cancel);

      // Fire another event AFTER subscribing
      bridge.testFireProposal({
        '_proposal_type': 'page',
        'title': 'Late Event',
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Only the late event should arrive (broadcast streams don't replay)
      expect(received, hasLength(1));
      expect(jsonDecode(received.first)['_proposal_type'], 'page');
    });
  });

  group('end-to-end: ProposalService -> bridge -> proposalStream', () {
    test('wrapProposal fires through bridge proposalStream', () async {
      final bridge = McpBridgeNotifier();
      addTearDown(() => bridge.dispose());

      final received = <String>[];
      final completer = Completer<void>();
      final sub = bridge.proposalStream.listen((json) {
        received.add(json);
        if (!completer.isCompleted) completer.complete();
      });
      addTearDown(sub.cancel);

      // Create a ProposalService wired to the bridge's callback
      // (this is how McpSseServer.start() wires it in production)
      final service = ProposalService(
        onProposal: bridge.testFireProposal,
      );

      service.wrapProposal('alarm', {
        'uid': 'abc-123',
        'title': 'Pump Overcurrent',
        'key': 'pump3.overcurrent',
      });

      await completer.future.timeout(const Duration(seconds: 2));

      expect(received, hasLength(1));
      final decoded = jsonDecode(received.first) as Map<String, dynamic>;
      expect(decoded['_proposal_type'], 'alarm');
      expect(decoded['title'], 'Pump Overcurrent');
      expect(decoded['uid'], 'abc-123');
    });
  });
}
