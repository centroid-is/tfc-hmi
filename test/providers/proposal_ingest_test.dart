import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart' show McpConfig;

import 'package:tfc/providers/mcp_bridge.dart'
    show
        mcpBridgeProvider,
        mcpConfigProvider,
        mcpEnabledProvider,
        mcpServerLifecycleProvider;
import 'package:tfc/providers/proposal_state.dart';

/// The inbound half of the proposal path: a write tool (`create_alarm`,
/// `propose_asset`, ...) hands a proposal to the bridge and returns, and the
/// operator has to see a banner for it.
///
/// As with `proposal_feedback_relay_test.dart`, the important thing here is
/// what is NOT mounted. `chatLifecycleProvider` used to be the only listener
/// on the bridge's proposal stream, and it only runs when the in-app chat is
/// compiled in -- which shipped builds are not (`CENTROIDX_CHAT=false`). Staging
/// has to happen off `mcpServerLifecycleProvider`, the one `main.dart` mounts
/// unconditionally, or a proposal made by an external client is dropped while
/// the tool still reports success.
///
/// [kChatEnabled] is a compile-time const, so these tests cannot flip it.
/// They assert the property that survives either setting: with the server
/// lifecycle mounted and nothing chat-shaped in the container, a proposal on
/// the stream reaches [proposalStateProvider].
void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        // The lifecycle provider itself is the real one; only its preference
        // inputs are stubbed, so the test needs neither a database nor the
        // shared-preferences plugin. Server disabled: this is about the
        // proposal path, not about binding a port.
        mcpEnabledProvider.overrideWith((ref) async => false),
        mcpConfigProvider.overrideWith((ref) async => McpConfig.defaults),
      ],
    );
    addTearDown(container.dispose);
    // Exactly what main.dart mounts. No chat lifecycle, no chat provider.
    container.read(mcpServerLifecycleProvider);
    return container;
  }

  List<PendingProposal> staged(ProviderContainer container) =>
      container.read(proposalStateProvider).proposals;

  test('a write tool proposal reaches the banner with no chat mounted',
      () async {
    final container = makeContainer();

    container.read(mcpBridgeProvider).testFireProposal({
      '_proposal_type': 'alarm',
      '_op': 'create',
      'title': 'Pump Overcurrent',
      'key': 'pump3.overcurrent',
    });

    // The bridge's proposal stream is a broadcast controller: asynchronous.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(staged(container), hasLength(1));
    final proposal = staged(container).single;
    expect(proposal.proposalType, 'alarm');
    expect(proposal.title, 'Pump Overcurrent');
    expect(proposal.action, ProposalOp.create);
    expect(container.read(proposalStateProvider).hasPending, isTrue);
  });

  test('a key-mapping proposal is titled by its key', () async {
    final container = makeContainer();

    container.read(mcpBridgeProvider).testFireProposal({
      '_proposal_type': 'key_mapping',
      '_op': 'delete',
      'key': 'CVS02.CN01.PX01.Fault',
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(staged(container).single.title, 'CVS02.CN01.PX01.Fault');
    expect(staged(container).single.action, ProposalOp.delete);
  });

  test('the chat path staging the same proposal does not double it up',
      () async {
    // Development builds run with the chat on, so both listeners are live on
    // the one broadcast stream. Each mints its own local id, so the only
    // thing standing between the operator and two identical banners is
    // addProposal deduplicating on the proposal JSON.
    final container = makeContainer();
    final bridge = container.read(mcpBridgeProvider);

    // Capture what the chat lifecycle would have been handed, verbatim.
    final wire = Completer<String>();
    final sub = bridge.proposalStream.listen((json) {
      if (!wire.isCompleted) wire.complete(json);
    });
    addTearDown(sub.cancel);

    bridge.testFireProposal({
      '_proposal_type': 'asset_update',
      '_op': 'update',
      'title': 'CVS02.CN01.PX01.Fault: server_alias -> st201',
    });
    final proposalJson = await wire.future.timeout(const Duration(seconds: 2));

    // What ChatNotifier.injectProposal does with it.
    final fromChat = PendingProposal.tryParse(proposalJson)!;
    container.read(proposalStateProvider.notifier).addProposal(fromChat);

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(staged(container), hasLength(1));
    // Different ids, identical JSON -- the JSON is what did the work.
    expect(staged(container).single.id, isNot(fromChat.id));
  });

  test('a tool result that is not a proposal stages nothing', () async {
    final container = makeContainer();

    container.read(mcpBridgeProvider).testFireProposal({'ok': true, 'rows': 3});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(staged(container), isEmpty);
  });
}
