/// Golden images of operator-decision notes in the chat, for design review
/// and PR descriptions.
///
/// Decisions on AI proposals (accepted / viewed / rejected) are injected into
/// the conversation as user-role messages prefixed with
/// [kOperatorDecisionPrefix]. They must read as system notes -- centered,
/// muted chips -- clearly distinct from an operator speech bubble, in both
/// light and dark themes.
///
/// To update: flutter test test/chat/operator_decision_note_golden_test.dart --update-goldens --run-skipped
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/chat/message_bubble.dart';
import 'package:tfc/llm/llm_models.dart';
import 'package:tfc/providers/proposal_state.dart';

const Size _viewport = Size(480, 560);

final _messages = [
  ChatMessage.assistant(
      'I have proposed three alarms for the freezer line and a dashboard '
      'page. Please review them.'),
  ChatMessage.user('Looks good, checking them now.'),
  ChatMessage.user('$kOperatorDecisionPrefix Viewed the alarm proposal '
      '"Freezer high temp" (#12). No decision yet.'),
  ChatMessage.user('$kOperatorDecisionPrefix Accepted 3 alarm proposals: '
      '"Freezer high temp", "Door open", "Compressor fault".'),
  ChatMessage.user('$kOperatorDecisionPrefix Rejected the page proposal '
      '"New dashboard" (#15).'),
];

Future<void> _pumpChat(WidgetTester tester, {required Brightness brightness}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        proposalStateProvider
            .overrideWith((ref) => ProposalStateNotifier(null)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: ListView(
              children: [for (final m in _messages) MessageBubble(message: m)],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _expectGolden(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name'));

// ---------------------------------------------------------------------------
// Fonts — same best-effort loading as key_repository_add_key_golden_test.dart;
// without this every label is an Ahem block and every icon a tofu box.
// ---------------------------------------------------------------------------

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer))))
        .load();
  }

  await load('Roboto', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    await load('MaterialIcons',
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  }
}

void main() {
  setUpAll(_loadFonts);

  Future<void> pump(WidgetTester tester, Brightness brightness) async {
    await tester.binding.setSurfaceSize(_viewport);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpChat(tester, brightness: brightness);
    await tester.pumpAndSettle();
  }

  testWidgets('decision notes render as centered system chips (light)',
      (tester) async {
    await pump(tester, Brightness.light);
    await _expectGolden(tester, 'operator_decision_notes_light.png');
  });

  testWidgets('decision notes render as centered system chips (dark)',
      (tester) async {
    await pump(tester, Brightness.dark);
    await _expectGolden(tester, 'operator_decision_notes_dark.png');
  });
}
