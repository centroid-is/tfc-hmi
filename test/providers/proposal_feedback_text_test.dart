import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/providers/chat.dart';
import 'package:tfc/providers/proposal_state.dart';

void main() {
  PendingProposal proposal({
    int id = 1,
    String type = 'alarm',
    String title = 'High Temp',
  }) =>
      PendingProposal(
        id: id,
        proposalType: type,
        title: title,
        proposalJson: '{"uid":"$id"}',
        operatorId: 'op1',
        createdAt: DateTime.now(),
      );

  group('describeProposalFeedback', () {
    test('single proposal names the type, title, and id', () {
      final text = describeProposalFeedback(
          'accepted', [proposal(id: 12, title: 'High Temp')]);
      expect(text, 'Accepted the alarm proposal "High Temp" (#12).');
    });

    test('viewed carries a no-decision-yet suffix', () {
      final text = describeProposalFeedback('viewed', [proposal(id: 3)]);
      expect(text, endsWith('No decision yet.'));
      expect(text, startsWith('Viewed'));
    });

    test('synthetic negative ids are not shown', () {
      final text = describeProposalFeedback('rejected', [proposal(id: -42)]);
      expect(text, isNot(contains('#')));
    });

    test('bulk decision of one type counts and lists titles', () {
      final text = describeProposalFeedback('accepted', [
        proposal(id: 1, type: 'page', title: 'A'),
        proposal(id: 2, type: 'page', title: 'B'),
      ]);
      expect(text, 'Accepted 2 page proposals: "A", "B".');
    });

    test('bulk decision over five titles is truncated', () {
      final text = describeProposalFeedback('rejected', [
        for (var i = 1; i <= 7; i++)
          proposal(id: i, title: 'T$i'),
      ]);
      expect(text, contains('7 alarm proposals'));
      expect(text, contains('and 2 more'));
      expect(text, isNot(contains('"T6"')));
    });

    test('mixed types fall back to plain "proposals"', () {
      final text = describeProposalFeedback('rejected', [
        proposal(id: 1, type: 'alarm'),
        proposal(id: 2, type: 'page'),
      ]);
      expect(text, contains('2 proposals'));
    });

    test('key_mapping and asset_update get readable labels', () {
      expect(
        describeProposalFeedback(
            'accepted', [proposal(id: 1, type: 'key_mapping', title: 'K')]),
        contains('key mapping proposal'),
      );
      expect(
        describeProposalFeedback(
            'accepted', [proposal(id: 1, type: 'asset_update', title: 'U')]),
        contains('asset update proposal'),
      );
    });
  });
}
