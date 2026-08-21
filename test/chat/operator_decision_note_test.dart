import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/chat/message_bubble.dart';
import 'package:tfc/llm/llm_models.dart';
import 'package:tfc/providers/proposal_state.dart';

/// Operator-decision notes are feedback FOR THE AI -- injected into the
/// conversation history so the model learns what the operator clicked --
/// but they must not appear in the chat UI: the operator already saw the
/// button they pressed.
void main() {
  Widget wrap(ChatMessage message) => ProviderScope(
        overrides: [
          proposalStateProvider.overrideWith((ref) => ProposalStateNotifier()),
        ],
        child: MaterialApp(
          home: Scaffold(body: MessageBubble(message: message)),
        ),
      );

  testWidgets('operator-decision note renders nothing', (tester) async {
    await tester.pumpWidget(wrap(ChatMessage.user(
        '$kOperatorDecisionPrefix Accepted the alarm proposal "High Temp".')));

    expect(find.text('$kOperatorDecisionPrefix Accepted the alarm proposal '
        '"High Temp".'), findsNothing);
    expect(find.textContaining('Accepted'), findsNothing);
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('a normal user message still gets its bubble', (tester) async {
    await tester.pumpWidget(wrap(ChatMessage.user('Looks good, thanks.')));

    expect(find.text('Looks good, thanks.'), findsOneWidget);
  });
}
