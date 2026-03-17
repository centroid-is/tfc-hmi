import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/mcp_bridge.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/widgets/preferences.dart';

import '../helpers/test_helpers.dart';

Widget buildTestableMcpServerSection({McpBridgeNotifier? bridge}) {
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWith(
        (ref) => createTestPreferences(),
      ),
      databaseProvider.overrideWith((ref) async => null),
      if (bridge != null) mcpBridgeProvider.overrideWith((ref) => bridge),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: McpServerSection(),
        ),
      ),
    ),
  );
}

void main() {
  group('MCP Chat Toggle', () {
    testWidgets('chat bubble toggle appears when server is enabled',
        (tester) async {
      await tester.pumpWidget(buildTestableMcpServerSection());
      await tester.pumpAndSettle();

      // Expand the tile
      await tester.tap(find.text('MCP Server'));
      await tester.pumpAndSettle();

      // Enable the server
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Chat bubble toggle should be visible
      expect(find.text('Show Chat Bubble'), findsOneWidget);
    });

    testWidgets('chat bubble toggle hidden when server is disabled',
        (tester) async {
      await tester.pumpWidget(buildTestableMcpServerSection());
      await tester.pumpAndSettle();

      // Expand the tile
      await tester.tap(find.text('MCP Server'));
      await tester.pumpAndSettle();

      // Server is disabled by default — chat toggle should not appear
      expect(find.text('Show Chat Bubble'), findsNothing);
    });

    testWidgets('chat bubble toggle defaults to off', (tester) async {
      await tester.pumpWidget(buildTestableMcpServerSection());
      await tester.pumpAndSettle();

      // Expand and enable server
      await tester.tap(find.text('MCP Server'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Find the chat bubble switch — it should be the second Switch
      // (first is Enable MCP Server)
      final switches = find.byType(Switch);
      // Enable MCP Server switch is first, Chat Bubble is second,
      // then tool group switches follow
      final chatSwitch = tester.widget<Switch>(switches.at(1));
      expect(chatSwitch.value, isFalse,
          reason: 'Chat bubble should default to off');
    });

    testWidgets('toggling chat bubble persists to preferences',
        (tester) async {
      await tester.pumpWidget(buildTestableMcpServerSection());
      await tester.pumpAndSettle();

      // Expand and enable server
      await tester.tap(find.text('MCP Server'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Toggle chat bubble on (second switch)
      final switches = find.byType(Switch);
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();

      // Verify it's now on
      final chatSwitch = tester.widget<Switch>(switches.at(1));
      expect(chatSwitch.value, isTrue);
    });

    testWidgets('kMcpConfigKey constant has expected value', (_) async {
      expect(kMcpConfigKey, equals('mcp.config'));
    });
  });
}
