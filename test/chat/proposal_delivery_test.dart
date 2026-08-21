import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:tfc_dart/core/preferences.dart';

import 'package:tfc/providers/chat.dart';
import 'package:tfc/providers/mcp_bridge.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/proposal_state.dart';
import '../helpers/test_helpers.dart';

/// `ChatNotifier.injectProposal` is the one door a proposal comes through.
///
/// The MCP server is hosted in this process; its write tools hand each
/// proposal to `ProposalService`'s callback, which the bridge turns into a
/// `proposalStream` event, which the chat lifecycle passes to
/// `injectProposal`. Nothing is stored on the way, and there is no poll to
/// fall back on, so if this seam drops a proposal the operator never sees it.
void main() {
  late ProviderContainer container;
  late McpBridgeNotifier bridge;
  late Preferences testPrefs;

  const alarmJson =
      '{"_proposal_type":"alarm","_op":"create","title":"Pump 3 Overcurrent",'
      '"key":"pump3.overcurrent"}';

  setUp(() async {
    testPrefs = await createTestPreferences();
    bridge = McpBridgeNotifier();
    container = ProviderContainer(
      overrides: [
        mcpBridgeProvider.overrideWith((ref) {
          ref.onDispose(() => bridge.dispose());
          return bridge;
        }),
        preferencesProvider.overrideWith((ref) async => testPrefs),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('an injected proposal reaches proposal state, routable', () {
    container.read(chatProvider.notifier).injectProposal(alarmJson);

    final state = container.read(proposalStateProvider);
    expect(state.pendingCount, 1);
    final pending = state.proposals.single;
    expect(pending.proposalType, 'alarm');
    expect(pending.title, 'Pump 3 Overcurrent');
    expect(pending.editorRoute, '/advanced/alarm-editor');
    expect(pending.id, isNegative, reason: 'ids are local handles');
  });

  test('the same proposal injected twice yields one pending proposal', () {
    final notifier = container.read(chatProvider.notifier);
    notifier.injectProposal(alarmJson);
    notifier.injectProposal(alarmJson);

    expect(container.read(proposalStateProvider).pendingCount, 1);
  });

  test('an in-app tool call surfacing the proposal first does not double it',
      () {
    // In-process tool calls reach the UI twice: the tool result goes through
    // ChatNotifier's own tool loop, and the server callback fires as well.
    // The two copies get different ids, so only the JSON comparison collapses
    // them -- the row id that used to do it is gone.
    container.read(proposalStateProvider.notifier).addProposal(PendingProposal(
          id: nextLocalProposalId(),
          proposalType: 'alarm',
          title: 'Pump 3 Overcurrent',
          proposalJson: alarmJson,
          operatorId: 'local',
          createdAt: DateTime.now(),
        ));

    container.read(chatProvider.notifier).injectProposal(alarmJson);

    expect(container.read(proposalStateProvider).pendingCount, 1);
  });

  test('two different proposals both arrive', () {
    final notifier = container.read(chatProvider.notifier);
    notifier.injectProposal(alarmJson);
    notifier.injectProposal(jsonEncode({
      '_proposal_type': 'key_mapping',
      '_op': 'create',
      'key': 'belt.speed',
    }));

    final state = container.read(proposalStateProvider);
    expect(state.pendingCount, 2);
    expect(state.ofType('alarm'), hasLength(1));
    expect(state.ofType('key_mapping'), hasLength(1));
    expect(state.ofType('key_mapping').single.editorRoute,
        '/advanced/key-repository');
  });

  test('a non-proposal message adds no pending proposal', () {
    container
        .read(chatProvider.notifier)
        .injectProposal('{"result":"no proposal here"}');

    expect(container.read(proposalStateProvider).pendingCount, 0);
  });
}
