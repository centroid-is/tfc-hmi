import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../helpers/test_helpers.dart';

void main() {
  // ==================== Group 1: Modbus Section Rendering ====================
  group('Modbus section rendering', () {
    testWidgets('renders "Modbus TCP Servers" section header', (tester) async {
      await tester.pumpWidget(buildTestableServerConfig());
      await tester.pumpAndSettle();

      // Scroll to find Modbus section (it's the 4th section on the page)
      await tester.scrollUntilVisible(
        find.text('Modbus TCP Servers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Modbus TCP Servers'), findsOneWidget);
    });

    testWidgets('renders networkWired icon in section header', (tester) async {
      await tester.pumpWidget(buildTestableServerConfig());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Modbus TCP Servers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Find the networkWired icon within the Modbus section
      final networkWiredIcons = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.networkWired);
      expect(networkWiredIcons, findsAtLeastNWidgets(1));
    });

    testWidgets('shows empty state when config.modbus is empty',
        (tester) async {
      await tester.pumpWidget(buildTestableServerConfig());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('No Modbus servers configured'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('No Modbus servers configured'), findsOneWidget);
      expect(find.text('Add your first Modbus TCP server to get started'),
          findsOneWidget);
    });
  });

  // ==================== Group 2: Add Modbus Server ====================
  group('Add Modbus server', () {
    testWidgets(
        'tapping "Add Server" creates a card with defaults (localhost, 502, unit ID 1)',
        (tester) async {
      await tester.pumpWidget(buildTestableServerConfig());
      await tester.pumpAndSettle();

      // Scroll to Modbus section and find its Add Server button.
      // There may be multiple "Add Server" buttons (OPC UA, JBTM, Modbus).
      // Scroll to the Modbus section first.
      await tester.scrollUntilVisible(
        find.text('No Modbus servers configured'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Find Add Server buttons -- the Modbus one is the last one
      final addButtons = find.text('Add Server');
      // Tap the last Add Server button (belongs to Modbus section)
      await tester.tap(addButtons.last);
      await tester.pumpAndSettle();

      // Empty state should be gone
      expect(find.text('No Modbus servers configured'), findsNothing);

      // Card should show default host:port:unitId in subtitle
      expect(find.text('localhost:502 (Unit 1)'), findsOneWidget);
    });
  });

  // ==================== Group 3: Edit Modbus Server ====================
  group('Edit Modbus server', () {
    testWidgets('editing host field updates the server config and shows unsaved badge',
        (tester) async {
      await tester.pumpWidget(buildTestableServerConfig(
        stateManConfig: sampleModbusStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Scroll to Modbus section
      await tester.scrollUntilVisible(
        find.text('Modbus TCP Servers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Find and expand the server card by tapping its title
      await tester.tap(find.text('plc_1'));
      await tester.pumpAndSettle();

      // Scroll to make the host field visible
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Host'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Change the host field
      final hostField = find.widgetWithText(TextField, 'Host');
      await tester.enterText(hostField, '10.0.0.1');
      await tester.pumpAndSettle();

      // Unsaved badge should appear
      // Scroll back up to see the badge
      await tester.scrollUntilVisible(
        find.text('Modbus TCP Servers'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Find "Unsaved" or "Unsaved Changes" text within the Modbus section
      expect(find.textContaining('Unsaved'), findsAtLeastNWidgets(1));
    });
  });

  // ==================== Group 4: Remove Modbus Server ====================
  group('Remove Modbus server', () {
    testWidgets('tapping delete button shows confirmation dialog',
        (tester) async {
      await tester.pumpWidget(buildTestableServerConfig(
        stateManConfig: sampleModbusStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Scroll to Modbus section
      await tester.scrollUntilVisible(
        find.text('Modbus TCP Servers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Find trash icon buttons in the Modbus section area.
      // Tap the last trash button (belongs to Modbus card).
      final trashButtons = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.trash);
      await tester.tap(trashButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('Remove Server'), findsOneWidget);
      expect(
          find.text('Are you sure you want to remove this Modbus server?'),
          findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('confirming removal removes the server card', (tester) async {
      await tester.pumpWidget(buildTestableServerConfig(
        stateManConfig: sampleModbusStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Scroll to Modbus section
      await tester.scrollUntilVisible(
        find.text('Modbus TCP Servers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Server card should be visible
      expect(find.text('plc_1'), findsOneWidget);

      // Tap delete (last trash button)
      final trashButtons = find.byWidgetPredicate(
          (w) => w is FaIcon && w.icon == FontAwesomeIcons.trash);
      await tester.tap(trashButtons.last);
      await tester.pumpAndSettle();

      // Confirm removal
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Server card should be gone, empty state should show
      expect(find.text('plc_1'), findsNothing);
      expect(find.text('No Modbus servers configured'), findsOneWidget);
    });
  });

  // ==================== Group 5: Connection Status ====================
  group('Connection status', () {
    testWidgets('shows grey dot with "Not active" when no StateMan',
        (tester) async {
      await tester.pumpWidget(buildTestableServerConfig(
        stateManConfig: sampleModbusStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Scroll to Modbus section
      await tester.scrollUntilVisible(
        find.text('Modbus TCP Servers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // The connection status chip should show "Not active" (grey)
      // since stateManProvider is not overridden with a real StateMan
      expect(find.text('Not active'), findsAtLeastNWidgets(1));
    });
  });

  // ==================== Group 6: Save Button ====================
  group('Save button', () {
    testWidgets('Save button disabled when no changes', (tester) async {
      await tester.pumpWidget(buildTestableServerConfig(
        stateManConfig: sampleModbusStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Scroll to Modbus save button area
      await tester.scrollUntilVisible(
        find.text('Modbus TCP Servers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Find "All Changes Saved" text (indicates save button is disabled)
      // Need to scroll further to find it
      await tester.scrollUntilVisible(
        find.text('All Changes Saved').last,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // The last "All Changes Saved" belongs to Modbus section
      expect(find.text('All Changes Saved'), findsAtLeastNWidgets(1));
    });

    testWidgets('Save button text changes to "Save Configuration" when unsaved',
        (tester) async {
      await tester.pumpWidget(buildTestableServerConfig(
        stateManConfig: sampleModbusStateManConfig(),
      ));
      await tester.pumpAndSettle();

      // Scroll to Modbus section
      await tester.scrollUntilVisible(
        find.text('Modbus TCP Servers'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Expand the server card
      await tester.tap(find.text('plc_1'));
      await tester.pumpAndSettle();

      // Edit host to create unsaved changes
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Host'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final hostField = find.widgetWithText(TextField, 'Host');
      await tester.enterText(hostField, '10.0.0.1');
      await tester.pumpAndSettle();

      // Scroll to Save button area
      await tester.scrollUntilVisible(
        find.text('Save Configuration'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Save Configuration'), findsAtLeastNWidgets(1));
    });
  });
}
