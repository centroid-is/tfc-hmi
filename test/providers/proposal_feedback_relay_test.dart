import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/providers/mcp_bridge.dart'
    show mcpBridgeProvider, proposalFeedbackRelayProvider;
import 'package:tfc/providers/proposal_state.dart';

/// The relay is what closes the gap this feature exists for: an external MCP
/// client proposes over HTTP, the operator accepts in the banner, and the
/// client learns about it.
///
/// The important thing about every test here is what is NOT mounted.
/// `chatLifecycleProvider` -- which relays the same decisions into the in-app
/// conversation -- only runs when the chat bubble is enabled. The external
/// client has to be nudged with the bubble off, so the relay lives on its own
/// and consumes the same broadcast controller independently.
void main() {
  PendingProposal proposal({
    int id = -1,
    String type = 'asset_update',
    String title = 'CVS02.CN01.PX01.Fault: server_alias -> st201',
  }) =>
      PendingProposal(
        id: id,
        proposalType: type,
        title: title,
        // Unique per proposal: ProposalStateNotifier.addProposal deduplicates
        // on the JSON as well as the id, so two staged proposals with
        // byte-identical JSON would collapse into one.
        proposalJson: '{"_op":"update","n":$id}',
        operatorId: 'op1',
        createdAt: DateTime.now(),
      );

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Mount only the relay. No chat lifecycle, no chat provider.
    container.read(proposalFeedbackRelayProvider);
    return container;
  }

  test('an accept reaches the bus with the chat lifecycle not mounted',
      () async {
    final container = makeContainer();
    final bus = container.read(mcpBridgeProvider).feedbackBus;

    await container
        .read(proposalStateProvider.notifier)
        .acceptProposal(_add(container, proposal()));

    // The broadcast controller delivers asynchronously.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final page = bus.since(null);
    expect(page.decisions, hasLength(1));
    final decision = page.decisions.single;
    expect(decision['action'], 'accepted');
    expect(decision['seq'], 1);
    expect(decision['count'], 1);
  });

  test('the payload carries the readable banner text, not just ids',
      () async {
    final container = makeContainer();
    final bus = container.read(mcpBridgeProvider).feedbackBus;
    final notifier = container.read(proposalStateProvider.notifier);

    _add(container, proposal());
    _add(
      container,
      proposal(
        id: -2,
        title: 'Line 1: keys -> SPB01.Recipe, SPB02.Recipe, SPB03.Recipe',
      ),
    );

    await notifier.acceptAllOfType('asset_update');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final decision = bus.since(null).decisions.single;

    // The sentence the operator's click produced, word for word the same one
    // the in-app assistant is given.
    expect(
      decision['summary'],
      'Accepted 2 asset update proposals: '
          '"CVS02.CN01.PX01.Fault: server_alias -> st201", '
          '"Line 1: keys -> SPB01.Recipe, SPB02.Recipe, SPB03.Recipe".',
    );

    final proposals = decision['proposals'] as List<dynamic>;
    expect(proposals, hasLength(2));
    expect((proposals.first as Map)['title'],
        'CVS02.CN01.PX01.Fault: server_alias -> st201');
    expect((proposals.first as Map)['type'], 'asset_update');
    expect((proposals.first as Map)['op'], 'update');
  });

  test('rejects, dismisses and views all come through', () async {
    final container = makeContainer();
    final bus = container.read(mcpBridgeProvider).feedbackBus;
    final notifier = container.read(proposalStateProvider.notifier);

    final a = _add(container, proposal(id: -1, title: 'A'));
    final b = _add(container, proposal(id: -2, title: 'B'));
    final c = _add(container, proposal(id: -3, title: 'C'));

    await notifier.viewProposal(c);
    await notifier.rejectProposal(a);
    await notifier.dismissProposal(b);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final actions =
        bus.since(null).decisions.map((d) => d['action']).toList();
    expect(actions, ['viewed', 'rejected', 'dismissed']);
  });

  test('decisions survive until a client comes to collect them', () async {
    // Nobody is listening on the bus stream at all here -- the whole point of
    // the ring buffer. A bare broadcast stream would have dropped these.
    final container = makeContainer();
    final bus = container.read(mcpBridgeProvider).feedbackBus;
    final notifier = container.read(proposalStateProvider.notifier);

    for (var i = 1; i <= 3; i++) {
      await notifier.acceptProposal(
          _add(container, proposal(id: -i, title: 'Proposal $i')));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // A client that connects only now still sees every decision.
    expect(bus.since(null).decisions, hasLength(3));
    expect(bus.lastSeq, 3);
    // And one that has already seen the first two picks up only the third.
    expect(bus.since(2).decisions.single['summary'], contains('Proposal 3'));
  });
}

/// Stages a proposal and returns its id.
int _add(ProviderContainer container, PendingProposal p) {
  container.read(proposalStateProvider.notifier).addProposal(p);
  return p.id;
}
