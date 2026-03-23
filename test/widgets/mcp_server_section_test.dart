import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/mcp_bridge.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/widgets/preferences.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    if (dart.library.js_interop) 'package:tfc_mcp_server/tfc_mcp_server_web.dart'
    show McpToolToggles;

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
  group('McpServerSection', () {
    testWidgets('expansion tile stays open after toggling enable switch',
        (tester) async {
      await tester.pumpWidget(buildTestableMcpServerSection());
      await tester.pumpAndSettle();

      // Expand the tile
      await tester.tap(find.text('MCP Server'));
      await tester.pumpAndSettle();

      // Verify the enable switch is visible (tile is expanded)
      expect(find.text('Enable MCP Server'), findsOneWidget);

      // Toggle the enable switch
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // ExpansionTile must still be expanded — enable switch still visible
      expect(find.text('Enable MCP Server'), findsOneWidget,
          reason: 'ExpansionTile collapsed after toggling enable switch');

      // Tool Groups section should now be visible (server enabled)
      expect(find.text('Tool Groups'), findsOneWidget);
    });

    testWidgets('expansion tile stays open after toggling a tool group switch',
        (tester) async {
      await tester.pumpWidget(buildTestableMcpServerSection());
      await tester.pumpAndSettle();

      // Expand the tile
      await tester.tap(find.text('MCP Server'));
      await tester.pumpAndSettle();

      // Enable the server first so tool toggles appear
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Find and toggle the first tool group switch (Tag Tools)
      final firstToolGroupMeta = McpToolToggles.toolGroupMeta.first;
      expect(find.text(firstToolGroupMeta.title), findsOneWidget);

      // Switches: [0] enable, [1] chat bubble, [2+] tool groups
      final switches = find.byType(Switch);
      expect(switches, findsAtLeast(3));

      // Toggle the third switch (first tool group)
      await tester.tap(switches.at(2));
      await tester.pumpAndSettle();

      // ExpansionTile must still be expanded
      expect(find.text('Enable MCP Server'), findsOneWidget,
          reason: 'ExpansionTile collapsed after toggling a tool group');
      expect(find.text(firstToolGroupMeta.title), findsOneWidget,
          reason: 'Tool group no longer visible after toggle');
    });

    testWidgets('status updates reactively when bridge state changes',
        (tester) async {
      final bridge = McpBridgeNotifier();
      addTearDown(() async => await bridge.dispose());

      await tester.pumpWidget(buildTestableMcpServerSection(bridge: bridge));
      await tester.pumpAndSettle();

      // Expand the tile
      await tester.tap(find.text('MCP Server'));
      await tester.pumpAndSettle();

      // Initially shows "Server stopped"
      expect(find.text('Server stopped'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget); // subtitle

      // Simulate server starting by updating bridge state
      bridge.testSetState(McpBridgeState(
        connectionState: McpConnectionState.connected,
        port: 8765,
      ));
      await tester.pumpAndSettle();

      // Status should now show running
      expect(find.text('Server running on port 8765'), findsOneWidget);
      expect(find.text('Running on port 8765'), findsOneWidget); // subtitle

      // Simulate server stopping
      bridge.testSetState(McpBridgeState.initial());
      await tester.pumpAndSettle();

      // Status should revert to stopped
      expect(find.text('Server stopped'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget);
    });

    testWidgets('toggling enable off hides tool groups section',
        (tester) async {
      await tester.pumpWidget(buildTestableMcpServerSection());
      await tester.pumpAndSettle();

      // Expand and enable
      await tester.tap(find.text('MCP Server'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('Tool Groups'), findsOneWidget);

      // Toggle off
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // Tool groups should be hidden, but tile still expanded
      expect(find.text('Enable MCP Server'), findsOneWidget,
          reason: 'ExpansionTile collapsed after toggling enable off');
      expect(find.text('Tool Groups'), findsNothing);
    });
  });
}
