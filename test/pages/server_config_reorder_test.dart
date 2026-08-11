/// Reordering servers on the server config page.
///
/// Covers all three sections (OPC-UA, JBTM M2400, Modbus TCP), the index
/// arithmetic behind the drag, and the thing that makes reordering a stateful
/// list subtle: each card owns TextEditingControllers seeded once in
/// initState, so a card that stays bound to the wrong server after a drag
/// would happily write the previous occupant's text back into the config.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/pages/server_config.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';
import 'package:tfc_dart/core/state_man.dart';

import '../helpers/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

StateManConfig _threeOpcuaServers() => StateManConfig(opcua: [
      OpcUAConfig()
        ..endpoint = 'opc.tcp://10.104.29.11:4840'
        ..serverAlias = 'st101',
      OpcUAConfig()
        ..endpoint = 'opc.tcp://10.104.29.12:4840'
        ..serverAlias = 'st201',
      OpcUAConfig()
        ..endpoint = 'opc.tcp://10.104.29.13:4840'
        ..serverAlias = 'st301',
    ]);

StateManConfig _threeJbtmServers() => StateManConfig(opcua: [], jbtm: [
      M2400Config(host: '10.104.29.71', port: 52211)..serverAlias = 'weigher_1',
      M2400Config(host: '10.104.29.72', port: 52211)..serverAlias = 'weigher_2',
      M2400Config(host: '10.104.29.73', port: 52211)..serverAlias = 'weigher_3',
    ]);

StateManConfig _threeModbusServers() => StateManConfig(opcua: [], modbus: [
      _modbus('10.104.29.31', 'plc_1'),
      _modbus('10.104.29.32', 'plc_2'),
      _modbus('10.104.29.33', 'plc_3'),
    ]);

ModbusConfig _modbus(String host, String alias) => ModbusConfig(
      host: host,
      port: 502,
      unitId: 1,
      pollGroups: [ModbusPollGroupConfig(name: 'default', intervalMs: 1000)],
    )..serverAlias = alias;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Rendered card titles, top to bottom, of the server list at [list] (0 is
/// OPC-UA, then JBTM, then Modbus — a section with no servers renders a
/// placeholder instead of a list and so does not take a slot).
///
/// A card's title is the first [Text] under its [ExpansionTile] — the bold
/// alias. Scoping to the list keeps the page's other tiles (the database
/// config card) out, and collapsed tile children are offstage, so nested
/// tiles (Modbus poll groups) do not show up either.
List<String> titleOrder(WidgetTester tester, {int list = 0}) {
  final titles = <String>[];
  final tiles = find.descendant(
    of: find.byType(ReorderableListView).at(list),
    matching: find.byType(ExpansionTile),
  );
  for (var i = 0; i < tiles.evaluate().length; i++) {
    final text = tester.widget<Text>(
      find.descendant(of: tiles.at(i), matching: find.byType(Text)).first,
    );
    titles.add(text.data ?? '');
  }
  return titles;
}

/// Invokes the page's single reorderable list the way a completed drag would.
///
/// [newIndex] follows the [ReorderableListView] contract: the slot the card
/// was dropped into *before* it is lifted out, so moving to the very end
/// means `newIndex == length`.
Future<void> reorder(WidgetTester tester, int oldIndex, int newIndex) async {
  final list =
      tester.widget<ReorderableListView>(find.byType(ReorderableListView));
  list.onReorder(oldIndex, newIndex);
  await settle(tester);
}

/// Scrolls the page until [finder] is on screen.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200,
      scrollable: find.byType(Scrollable).first);
  await settle(tester);
}

/// Reads the config back out of preferences, as saved.
Future<StateManConfig> persistedConfig(WidgetTester tester) async {
  final container =
      ProviderScope.containerOf(tester.element(find.byType(ServerConfigBody)));
  final prefs = await container.read(preferencesProvider.future);
  return StateManConfig.fromPrefs(prefs);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SecureStorage.setInstance(FakeSecureStorage());
  });

  // ==================== moveInList ====================
  //
  // The index arithmetic every section shares. Worth testing directly: the
  // off-by-one on downward moves is the classic ReorderableListView bug, and
  // it is invisible in a widget test that only ever drags upwards.
  group('moveInList', () {
    test('moves an item down, accounting for the removed slot', () {
      final list = ['a', 'b', 'c', 'd'];
      expect(moveInList(list, 0, 3), isTrue);
      // Dropped between c and d, not after d.
      expect(list, ['b', 'c', 'a', 'd']);
    });

    test('moves an item to the very end', () {
      final list = ['a', 'b', 'c'];
      expect(moveInList(list, 0, 3), isTrue);
      expect(list, ['b', 'c', 'a']);
    });

    test('moves an item up', () {
      final list = ['a', 'b', 'c'];
      expect(moveInList(list, 2, 0), isTrue);
      expect(list, ['c', 'a', 'b']);
    });

    test('dropping an item back where it started changes nothing', () {
      final list = ['a', 'b', 'c'];
      expect(moveInList(list, 1, 1), isFalse);
      expect(moveInList(list, 1, 2), isFalse);
      expect(list, ['a', 'b', 'c']);
    });

    test('out-of-range indices are clamped, never thrown', () {
      final list = ['a', 'b', 'c'];
      expect(moveInList(list, 5, 0), isFalse);
      expect(moveInList(list, -1, 0), isFalse);
      expect(list, ['a', 'b', 'c']);

      expect(moveInList(list, 0, 99), isTrue);
      expect(list, ['b', 'c', 'a']);
    });

    test('a single-item list has nothing to move', () {
      final list = ['a'];
      expect(moveInList(list, 0, 1), isFalse);
      expect(list, ['a']);
    });
  });

  // ==================== OPC-UA ====================
  group('OPC-UA server reorder', () {
    testWidgets('renders a reorderable list with a handle per card',
        (tester) async {
      await pumpAndLoad(tester,
          buildTestableServerConfig(stateManConfig: _threeOpcuaServers()));

      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));
      expect(titleOrder(tester), ['st101', 'st201', 'st301']);
    });

    testWidgets('dragging the last card to the top reorders the list',
        (tester) async {
      await pumpAndLoad(tester,
          buildTestableServerConfig(stateManConfig: _threeOpcuaServers()));

      await reorder(tester, 2, 0);

      expect(titleOrder(tester), ['st301', 'st101', 'st201']);
    });

    testWidgets('the new order survives a save', (tester) async {
      await pumpAndLoad(tester,
          buildTestableServerConfig(stateManConfig: _threeOpcuaServers()));

      await reorder(tester, 0, 3);
      expect(titleOrder(tester), ['st201', 'st301', 'st101']);

      await reveal(tester, find.text('Save Configuration'));
      await tester.tap(find.text('Save Configuration').first);
      await settle(tester);

      final saved = await persistedConfig(tester);
      expect(saved.opcua.map((s) => s.serverAlias),
          ['st201', 'st301', 'st101']);
    });

    testWidgets('a reorder counts as an unsaved change', (tester) async {
      await pumpAndLoad(tester,
          buildTestableServerConfig(stateManConfig: _threeOpcuaServers()));

      expect(find.textContaining('Unsaved'), findsNothing);

      await reorder(tester, 2, 0);

      expect(find.textContaining('Unsaved'), findsAtLeastNWidgets(1));
    });

    testWidgets('card state follows its server across a reorder',
        (tester) async {
      // The regression this guards: card fields are seeded once in initState.
      // Keyed on position rather than identity, the card left sitting in slot
      // 0 would still show st101's endpoint while editing st301's config.
      await pumpAndLoad(tester,
          buildTestableServerConfig(stateManConfig: _threeOpcuaServers()));

      await reorder(tester, 2, 0);

      // Expand the card now on top — it must be st301, endpoint and all.
      await tester.tap(find.text('st301'));
      await settle(tester);

      final endpoint = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Endpoint URL').first);
      expect(endpoint.controller!.text, 'opc.tcp://10.104.29.13:4840');
    });

    testWidgets('a lone server gets no drag handle', (tester) async {
      await pumpAndLoad(
          tester,
          buildTestableServerConfig(
              stateManConfig: StateManConfig(opcua: [
            OpcUAConfig()
              ..endpoint = 'opc.tcp://10.104.29.11:4840'
              ..serverAlias = 'st101',
          ])));

      expect(find.text('st101'), findsOneWidget);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
    });

    testWidgets('handles appear once a second server is added',
        (tester) async {
      await pumpAndLoad(
          tester,
          buildTestableServerConfig(
              stateManConfig: StateManConfig(opcua: [
            OpcUAConfig()
              ..endpoint = 'opc.tcp://10.104.29.11:4840'
              ..serverAlias = 'st101',
          ])));

      expect(find.byIcon(Icons.drag_indicator), findsNothing);

      await tester.tap(find.text('Add Server').first);
      await settle(tester);

      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));
    });

    testWidgets('removing a card keeps the remaining cards on their servers',
        (tester) async {
      await pumpAndLoad(tester,
          buildTestableServerConfig(stateManConfig: _threeOpcuaServers()));

      // Remove the middle server.
      await tester.tap(find.byType(IconButton).at(1));
      await settle(tester);
      await tester.tap(find.text('Remove'));
      await settle(tester);

      expect(titleOrder(tester), ['st101', 'st301']);

      await tester.tap(find.text('st301'));
      await settle(tester);
      final endpoint = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Endpoint URL').first);
      expect(endpoint.controller!.text, 'opc.tcp://10.104.29.13:4840');
    });
  });

  // ==================== JBTM ====================
  group('JBTM server reorder', () {
    testWidgets('reorders and persists', (tester) async {
      await pumpAndLoad(tester,
          buildTestableServerConfig(stateManConfig: _threeJbtmServers()));
      await reveal(tester, find.text('weigher_1'));

      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));

      await reorder(tester, 0, 3);
      expect(titleOrder(tester), ['weigher_2', 'weigher_3', 'weigher_1']);

      await reveal(tester, find.text('Save Configuration'));
      await tester.tap(find.text('Save Configuration').first);
      await settle(tester);

      final saved = await persistedConfig(tester);
      expect(saved.jbtm.map((s) => s.serverAlias),
          ['weigher_2', 'weigher_3', 'weigher_1']);
    });
  });

  // ==================== Modbus ====================
  group('Modbus server reorder', () {
    testWidgets('reorders and persists', (tester) async {
      await pumpAndLoad(tester,
          buildTestableServerConfig(stateManConfig: _threeModbusServers()));
      await reveal(tester, find.text('plc_1'));

      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));

      await reorder(tester, 2, 0);
      expect(titleOrder(tester), ['plc_3', 'plc_1', 'plc_2']);

      await reveal(tester, find.text('Save Configuration'));
      await tester.tap(find.text('Save Configuration').first);
      await settle(tester);

      final saved = await persistedConfig(tester);
      expect(saved.modbus.map((s) => s.serverAlias), ['plc_3', 'plc_1', 'plc_2']);
    });

    testWidgets('poll groups travel with their server', (tester) async {
      // Modbus cards carry per-poll-group controllers too — the deepest bit of
      // per-card state on the page.
      await pumpAndLoad(
          tester,
          buildTestableServerConfig(
              stateManConfig: StateManConfig(opcua: [], modbus: [
            _modbus('10.104.29.31', 'plc_1'),
            ModbusConfig(
              host: '10.104.29.32',
              port: 502,
              unitId: 1,
              pollGroups: [
                ModbusPollGroupConfig(name: 'fast', intervalMs: 50),
              ],
            )..serverAlias = 'plc_2',
          ])));
      await reveal(tester, find.text('plc_1'));

      await reorder(tester, 1, 0);
      expect(titleOrder(tester), ['plc_2', 'plc_1']);

      await tester.tap(find.text('plc_2'));
      await settle(tester);
      await reveal(tester, find.text('Poll Groups (1)'));
      await tester.tap(find.text('Poll Groups (1)'));
      await settle(tester);

      final name =
          tester.widget<TextField>(find.widgetWithText(TextField, 'Name').first);
      expect(name.controller!.text, 'fast');
    });
  });

  // ==================== Sections are independent ====================
  group('All sections', () {
    testWidgets('each section reorders only its own servers', (tester) async {
      final config = StateManConfig(
        opcua: _threeOpcuaServers().opcua,
        jbtm: _threeJbtmServers().jbtm,
        modbus: _threeModbusServers().modbus,
      );
      await pumpAndLoad(
          tester, buildTestableServerConfig(stateManConfig: config));

      expect(find.byType(ReorderableListView), findsNWidgets(3));

      // Reorder the OPC-UA list (the first of the three).
      final opcuaList = tester
          .widget<ReorderableListView>(find.byType(ReorderableListView).at(0));
      opcuaList.onReorder(2, 0);
      await settle(tester);

      await reveal(tester, find.text('Save Configuration'));
      await tester.tap(find.text('Save Configuration').first);
      await settle(tester);

      final saved = await persistedConfig(tester);
      expect(saved.opcua.map((s) => s.serverAlias), ['st301', 'st101', 'st201']);
      // Untouched.
      expect(saved.jbtm.map((s) => s.serverAlias),
          ['weigher_1', 'weigher_2', 'weigher_3']);
      expect(saved.modbus.map((s) => s.serverAlias),
          ['plc_1', 'plc_2', 'plc_3']);
    });
  });
}
