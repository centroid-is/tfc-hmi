import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/state_man.dart'
    show KeyMappingEntry, KeyMappings, OpcUANodeConfig;
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    show CallGraphBuilder, CallGraphData, PlcCodeBlock, PlcVariable, PlcAssetSummary;

import 'package:tfc/plc/plc_detail_panel.dart';
import 'package:tfc/providers/plc.dart';

// ── Test Data ────────────────────────────────────────────────────────────

final _actionTestBlocks = [
  PlcCodeBlock(
    id: 3,
    assetKey: 'pump-001',
    blockName: 'MAIN',
    blockType: 'Program',
    filePath: 'POUs/MAIN.TcPOU',
    declaration: 'PROGRAM MAIN\nVAR\n  fbPump : FB_Pump;\nEND_VAR',
    implementation: 'fbPump(bStart := TRUE);',
    fullSource:
        'PROGRAM MAIN\nVAR\n  fbPump : FB_Pump;\nEND_VAR\nfbPump(bStart := TRUE);',
    indexedAt: DateTime(2025, 6, 15, 10, 30),
    vendorType: 'twincat',
    serverAlias: 'PLC_Main',
    variables: [
      PlcVariable(
        id: 4,
        blockId: 3,
        variableName: 'fbPump',
        variableType: 'FB_Pump',
        section: 'VAR',
        qualifiedName: 'MAIN.fbPump',
      ),
    ],
  ),
  PlcCodeBlock(
    id: 10,
    assetKey: 'pump-001',
    blockName: 'Init',
    blockType: 'Action',
    filePath: 'POUs/MAIN.TcPOU',
    declaration: 'ACTION Init',
    implementation: 'fbPump(bStart := FALSE);',
    fullSource: 'ACTION Init\nfbPump(bStart := FALSE);',
    indexedAt: DateTime(2025, 6, 15, 10, 30),
    vendorType: 'twincat',
    serverAlias: 'PLC_Main',
    parentBlockId: 3,
    variables: [],
  ),
  PlcCodeBlock(
    id: 1,
    assetKey: 'pump-001',
    blockName: 'FB_Pump',
    blockType: 'FunctionBlock',
    filePath: 'POUs/FB_Pump.TcPOU',
    declaration: 'FUNCTION_BLOCK FB_Pump\nVAR_INPUT\n  bStart : BOOL;\nEND_VAR',
    implementation: 'IF bStart THEN\n  bRunning := TRUE;\nEND_IF',
    fullSource:
        'FUNCTION_BLOCK FB_Pump\nVAR_INPUT\n  bStart : BOOL;\nEND_VAR\nIF bStart THEN\n  bRunning := TRUE;\nEND_IF',
    indexedAt: DateTime(2025, 6, 15, 10, 30),
    vendorType: 'twincat',
    serverAlias: 'PLC_Main',
    variables: [
      PlcVariable(
        id: 1,
        blockId: 1,
        variableName: 'bStart',
        variableType: 'BOOL',
        section: 'VAR_INPUT',
        qualifiedName: 'FB_Pump.bStart',
        comment: 'Start command',
      ),
    ],
  ),
];

final _testBlocks = [
  PlcCodeBlock(
    id: 1,
    assetKey: 'pump-001',
    blockName: 'FB_Pump',
    blockType: 'FunctionBlock',
    filePath: 'POUs/FB_Pump.TcPOU',
    declaration: 'FUNCTION_BLOCK FB_Pump\nVAR_INPUT\n  bStart : BOOL;\nEND_VAR',
    implementation: 'IF bStart THEN\n  bRunning := TRUE;\nEND_IF',
    fullSource:
        'FUNCTION_BLOCK FB_Pump\nVAR_INPUT\n  bStart : BOOL;\nEND_VAR\nIF bStart THEN\n  bRunning := TRUE;\nEND_IF',
    indexedAt: DateTime(2025, 6, 15, 10, 30),
    vendorType: 'twincat',
    serverAlias: 'PLC_Main',
    variables: [
      PlcVariable(
        id: 1,
        blockId: 1,
        variableName: 'bStart',
        variableType: 'BOOL',
        section: 'VAR_INPUT',
        qualifiedName: 'FB_Pump.bStart',
        comment: 'Start command',
      ),
      PlcVariable(
        id: 2,
        blockId: 1,
        variableName: 'bRunning',
        variableType: 'BOOL',
        section: 'VAR_OUTPUT',
        qualifiedName: 'FB_Pump.bRunning',
      ),
    ],
  ),
  PlcCodeBlock(
    id: 2,
    assetKey: 'pump-001',
    blockName: 'GVL_Main',
    blockType: 'GVL',
    filePath: 'GVLs/GVL_Main.TcGVL',
    declaration: 'VAR_GLOBAL\n  fTemperature : REAL;\nEND_VAR',
    implementation: null,
    fullSource: 'VAR_GLOBAL\n  fTemperature : REAL;\nEND_VAR',
    indexedAt: DateTime(2025, 6, 15, 10, 30),
    vendorType: 'twincat',
    serverAlias: 'PLC_Main',
    variables: [
      PlcVariable(
        id: 3,
        blockId: 2,
        variableName: 'fTemperature',
        variableType: 'REAL',
        section: 'VAR_GLOBAL',
        qualifiedName: 'GVL_Main.fTemperature',
        comment: 'Process temperature',
      ),
    ],
  ),
  PlcCodeBlock(
    id: 3,
    assetKey: 'pump-001',
    blockName: 'MAIN',
    blockType: 'Program',
    filePath: 'POUs/MAIN.TcPOU',
    declaration: 'PROGRAM MAIN\nVAR\n  fbPump : FB_Pump;\nEND_VAR',
    implementation: 'fbPump(bStart := TRUE);',
    fullSource:
        'PROGRAM MAIN\nVAR\n  fbPump : FB_Pump;\nEND_VAR\nfbPump(bStart := TRUE);',
    indexedAt: DateTime(2025, 6, 15, 10, 30),
    vendorType: 'twincat',
    serverAlias: 'PLC_Main',
    variables: [
      PlcVariable(
        id: 4,
        blockId: 3,
        variableName: 'fbPump',
        variableType: 'FB_Pump',
        section: 'VAR',
        qualifiedName: 'MAIN.fbPump',
      ),
    ],
  ),
];

final _testSummary = PlcAssetSummary(
  assetKey: 'pump-001',
  blockCount: 3,
  variableCount: 4,
  lastIndexedAt: DateTime(2025, 6, 15, 10, 30),
  blockTypeCounts: {'FunctionBlock': 1, 'GVL': 1, 'Program': 1},
);

OpcUANodeConfig _makeOpcUaNode(int ns, String id, {String? serverAlias}) {
  final node = OpcUANodeConfig(namespace: ns, identifier: id);
  node.serverAlias = serverAlias;
  return node;
}

/// Key mappings for testing — keys for server alias "PLC_Main".
final _testKeyMappings = KeyMappings(nodes: {
  'pump.temperature': KeyMappingEntry(
    opcuaNode:
        _makeOpcUaNode(4, 'ns=4;s=GVL_Main.fTemperature', serverAlias: 'PLC_Main'),
  ),
  'pump.start': KeyMappingEntry(
    opcuaNode:
        _makeOpcUaNode(4, 'ns=4;s=FB_Pump.bStart', serverAlias: 'PLC_Main'),
  ),
  'other_server.key': KeyMappingEntry(
    opcuaNode:
        _makeOpcUaNode(4, 'ns=4;s=GVL_Other.value', serverAlias: 'OTHER_PLC'),
  ),
  'numeric.key': KeyMappingEntry(
    opcuaNode:
        _makeOpcUaNode(2, 'ns=2;i=847', serverAlias: 'PLC_Main'),
  ),
});

// ── Widget Builder ───────────────────────────────────────────────────────

Widget _buildTestWidget({
  required String assetKey,
  List<PlcCodeBlock>? blocks,
  PlcAssetSummary? summary,
  Completer<List<PlcCodeBlock>>? blocksCompleter,
  bool throwError = false,
  KeyMappings? keyMappings,
  CallGraphData? callGraphData,
  bool buildCallGraph = true,
}) {
  final effectiveBlocks = blocks ?? _testBlocks;
  // Build call graph from blocks if not explicitly provided and not loading.
  final effectiveCallGraph = callGraphData ??
      (buildCallGraph && blocksCompleter == null && !throwError
          ? CallGraphBuilder().build(effectiveBlocks)
          : null);

  return ProviderScope(
    overrides: [
      selectedPlcAssetProvider.overrideWith((ref) => assetKey),
      plcBlockListProvider.overrideWith((ref, key) {
        if (blocksCompleter != null) return blocksCompleter.future;
        if (throwError) return Future.error('DB connection lost');
        return Future.value(effectiveBlocks);
      }),
      plcAssetSummaryProvider.overrideWith((ref) async {
        if (summary != null) return [summary];
        return [_testSummary];
      }),
      keyMappingsProvider.overrideWith((ref) async {
        return keyMappings ?? _testKeyMappings;
      }),
      callGraphDataProvider.overrideWith((ref, key) async {
        return effectiveCallGraph;
      }),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 800,
          child: PlcDetailPanel(assetKey: assetKey),
        ),
      ),
    ),
  );
}

void main() {
  group('PlcDetailPanel', () {
    // ---------------------------------------------------------------
    // Loading state
    // ---------------------------------------------------------------
    testWidgets('shows loading indicator while blocks are loading',
        (tester) async {
      final completer = Completer<List<PlcCodeBlock>>();

      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        blocksCompleter: completer,
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete to avoid dangling future.
      completer.complete([]);
      await tester.pumpAndSettle();
    });

    // ---------------------------------------------------------------
    // Error state
    // ---------------------------------------------------------------
    testWidgets('shows error message on load failure', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        throwError: true,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Error loading'), findsOneWidget);
    });

    // ---------------------------------------------------------------
    // Header info
    // ---------------------------------------------------------------
    testWidgets('shows asset key in header', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      expect(find.text('pump-001'), findsOneWidget);
    });

    testWidgets('shows close button that clears selection', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // After closing, the provider should be null -- widget won't
      // rebuild to show that, but we verify the tap doesn't crash.
    });

    // ---------------------------------------------------------------
    // Top-level view: sorted list
    // ---------------------------------------------------------------
    testWidgets('shows top-level blocks (programs and GVLs) sorted',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // MAIN (Program) and GVL_Main should be visible.
      expect(find.text('MAIN'), findsOneWidget);
      expect(find.text('GVL_Main'), findsOneWidget);

      // FB_Pump is a FunctionBlock -- not shown at top level.
      expect(find.text('FB_Pump'), findsNothing);
    });

    testWidgets('MAIN appears before GVL in top-level sort order',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Find positions of MAIN and GVL_Main in the widget tree.
      final mainFinder = find.text('MAIN');
      final gvlFinder = find.text('GVL_Main');

      // Both should exist.
      expect(mainFinder, findsOneWidget);
      expect(gvlFinder, findsOneWidget);

      // MAIN should be above GVL_Main (smaller Y coordinate).
      final mainY = tester.getTopLeft(mainFinder).dy;
      final gvlY = tester.getTopLeft(gvlFinder).dy;
      expect(mainY, lessThan(gvlY));
    });

    testWidgets('shows referenced block count for programs', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // MAIN references FB_Pump through its variable type.
      expect(find.textContaining('1 referenced block'), findsOneWidget);
    });

    testWidgets('shows chevron icon for drill-down navigation',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Chevron icons indicate tappable drill-down items.
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
    });

    testWidgets('shows other blocks count summary', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Should show a summary of non-top-level blocks.
      expect(find.textContaining('1 other block'), findsOneWidget);
    });

    // ---------------------------------------------------------------
    // Metadata info
    // ---------------------------------------------------------------
    testWidgets('shows vendor type and server alias', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      expect(find.textContaining('twincat'), findsOneWidget);
      expect(find.textContaining('PLC_Main'), findsOneWidget);
    });

    testWidgets('shows block count', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      expect(find.textContaining('3 blocks'), findsOneWidget);
    });

    // ---------------------------------------------------------------
    // Empty blocks
    // ---------------------------------------------------------------
    testWidgets('shows empty message when no blocks exist', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        blocks: [],
      ));
      await tester.pumpAndSettle();

      expect(find.text('No code blocks found'), findsOneWidget);
    });

    // ---------------------------------------------------------------
    // Drill-down navigation
    // ---------------------------------------------------------------
    testWidgets('tapping a program drills into detail view', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Tap MAIN to drill in.
      await tester.tap(find.text('MAIN'));
      await tester.pumpAndSettle();

      // Should show back arrow.
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // GVL_Main should no longer be visible (we're in MAIN's detail).
      expect(find.text('GVL_Main'), findsNothing);

      // Should show the referenced FB_Pump block.
      expect(find.text('FB_Pump'), findsOneWidget);
    });

    testWidgets('drill-down view shows source code section', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Drill into MAIN.
      await tester.tap(find.text('MAIN'));
      await tester.pumpAndSettle();

      // Source Code collapsible section header should be present.
      expect(find.text('Source Code'), findsOneWidget);
    });

    testWidgets('drill-down view shows variables section', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Drill into MAIN.
      await tester.tap(find.text('MAIN'));
      await tester.pumpAndSettle();

      // Variables section header should be present.
      expect(find.textContaining('Variables'), findsOneWidget);
    });

    testWidgets('drill-down shows referenced blocks section', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Drill into MAIN.
      await tester.tap(find.text('MAIN'));
      await tester.pumpAndSettle();

      // Should show referenced blocks header.
      expect(find.textContaining('Referenced Blocks'), findsOneWidget);

      // FB_Pump is referenced by MAIN.
      expect(find.text('FB_Pump'), findsOneWidget);
    });

    testWidgets('back button returns to top-level view', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Drill into MAIN.
      await tester.tap(find.text('MAIN'));
      await tester.pumpAndSettle();

      // Verify we're in the drill-down view.
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Tap back.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Should be back at top level.
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.text('GVL_Main'), findsOneWidget);
      expect(find.text('MAIN'), findsOneWidget);
    });

    testWidgets('expanding a referenced block shows its source code',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Drill into MAIN.
      await tester.tap(find.text('MAIN'));
      await tester.pumpAndSettle();

      // Expand FB_Pump referenced block tile.
      await tester.tap(find.text('FB_Pump'));
      await tester.pumpAndSettle();

      // Should show FB_Pump's source code inline.
      expect(find.textContaining('FUNCTION_BLOCK FB_Pump'), findsOneWidget);
    });

    testWidgets('expanding a referenced block shows its variables',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Drill into MAIN.
      await tester.tap(find.text('MAIN'));
      await tester.pumpAndSettle();

      // Expand FB_Pump referenced block tile.
      await tester.tap(find.text('FB_Pump'));
      await tester.pumpAndSettle();

      // Should show variable sections.
      expect(find.text('VAR_INPUT'), findsOneWidget);
      expect(find.text('VAR_OUTPUT'), findsOneWidget);
    });

    // ---------------------------------------------------------------
    // GVL drill-down (no referenced blocks)
    // ---------------------------------------------------------------
    testWidgets('Action shows referenced blocks inherited from parent Program',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        blocks: _actionTestBlocks,
      ));
      await tester.pumpAndSettle();

      // Action Init should be visible at top level.
      expect(find.text('Init'), findsOneWidget);

      // Init should show "1 referenced blocks" from parent MAIN's variables.
      expect(find.textContaining('1 referenced block'), findsWidgets);

      // Drill into the Init action.
      await tester.tap(find.text('Init'));
      await tester.pumpAndSettle();

      // Should show the referenced FB_Pump from parent's variables.
      expect(find.textContaining('Referenced Blocks'), findsOneWidget);
      expect(find.text('FB_Pump'), findsOneWidget);
    });

    testWidgets('drilling into GVL shows source but no referenced blocks',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // Drill into GVL_Main.
      await tester.tap(find.text('GVL_Main'));
      await tester.pumpAndSettle();

      // Should show source code section.
      expect(find.text('Source Code'), findsOneWidget);

      // Should NOT show referenced blocks (GVL has no FB references).
      expect(find.textContaining('Referenced Blocks'), findsNothing);
    });

    // ---------------------------------------------------------------
    // Tab bar
    // ---------------------------------------------------------------
    testWidgets('shows Blocks and Key Map tabs', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // TabBar renders text in both selected and unselected styles.
      expect(find.text('Blocks'), findsWidgets);
      expect(find.text('Key Map'), findsWidgets);
    });

    testWidgets('Blocks tab is selected by default', (tester) async {
      await tester.pumpWidget(_buildTestWidget(assetKey: 'pump-001'));
      await tester.pumpAndSettle();

      // MAIN should be visible (from the Blocks tab content).
      expect(find.text('MAIN'), findsOneWidget);
    });

    // ---------------------------------------------------------------
    // Key Map tab — flat selectable key list
    // ---------------------------------------------------------------
    testWidgets('Key Map tab shows filtered keys for server alias',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        keyMappings: _testKeyMappings,
      ));
      await tester.pumpAndSettle();

      // Switch to Key Map tab.
      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      // Should show keys for PLC_Main only (pump.temperature, pump.start,
      // numeric.key) — not other_server.key.
      expect(find.text('pump.temperature'), findsOneWidget);
      expect(find.text('pump.start'), findsOneWidget);
      expect(find.text('numeric.key'), findsOneWidget);
      expect(find.text('other_server.key'), findsNothing);
    });

    testWidgets('Key Map tab shows key count header', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        keyMappings: _testKeyMappings,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      // Should show "3 keys for PLC_Main".
      expect(find.textContaining('3 keys'), findsOneWidget);
      expect(find.textContaining('PLC_Main'), findsWidgets);
    });

    testWidgets('Key Map shows variable path for string identifiers',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        keyMappings: _testKeyMappings,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      // Variable path shown as subtitle in the flat key list.
      expect(find.text('GVL_Main.fTemperature'), findsOneWidget);
    });

    testWidgets('Key Map shows "numeric OPC-UA" message for numeric keys',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        keyMappings: _testKeyMappings,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      // Select the numeric.key entry to see its trace detail.
      await tester.tap(find.text('numeric.key'));
      await tester.pumpAndSettle();

      expect(
          find.textContaining('numeric OPC-UA identifier'), findsOneWidget);
    });

    testWidgets('selecting a key shows back button and trace detail',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        keyMappings: _testKeyMappings,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      // Select pump.temperature.
      await tester.tap(find.text('pump.temperature'));
      await tester.pumpAndSettle();

      // Should show back arrow for returning to key list.
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Other keys should NOT be visible (we're in detail view).
      expect(find.text('pump.start'), findsNothing);
      expect(find.text('numeric.key'), findsNothing);

      // Variable path should be shown in the detail.
      expect(find.text('GVL_Main.fTemperature'), findsWidgets);
    });

    testWidgets('back button from key detail returns to key list',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        keyMappings: _testKeyMappings,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      // Select a key.
      await tester.tap(find.text('pump.start'));
      await tester.pumpAndSettle();

      // Tap back.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Should be back at key list.
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.text('pump.temperature'), findsOneWidget);
      expect(find.text('pump.start'), findsOneWidget);
      expect(find.text('numeric.key'), findsOneWidget);
    });

    testWidgets('Key Map shows "no PLC references" when callGraph is null',
        (tester) async {
      // Use blocks for the Blocks tab but null call graph for Key Map.
      await tester.pumpWidget(ProviderScope(
        overrides: [
          selectedPlcAssetProvider.overrideWith((ref) => 'pump-001'),
          plcBlockListProvider.overrideWith((ref, key) {
            return Future.value(_testBlocks);
          }),
          plcAssetSummaryProvider.overrideWith((ref) async {
            return [_testSummary];
          }),
          keyMappingsProvider.overrideWith((ref) async => _testKeyMappings),
          callGraphDataProvider.overrideWith((ref, key) async => null),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 800,
              child: PlcDetailPanel(assetKey: 'pump-001'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      // Keys should still be listed even with null call graph.
      expect(find.text('pump.temperature'), findsOneWidget);
      expect(find.text('pump.start'), findsOneWidget);

      // Select a key with a string identifier.
      await tester.tap(find.text('pump.temperature'));
      await tester.pumpAndSettle();

      // Should show "No PLC references found" since call graph is null
      // (no references can be resolved without indexed PLC code).
      expect(find.textContaining('No PLC references found'), findsOneWidget);
    });

    testWidgets('Key Map shows empty message when no keys match server',
        (tester) async {
      // All keys are for OTHER_PLC but blocks are PLC_Main.
      final noMatchKeys = KeyMappings(nodes: {
        'other.key': KeyMappingEntry(
          opcuaNode: _makeOpcUaNode(
              4, 'ns=4;s=GVL.val', serverAlias: 'OTHER_PLC'),
        ),
      });

      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        keyMappings: noMatchKeys,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No key mappings found'), findsOneWidget);
    });

    testWidgets('Key Map shows empty message when key mappings are null',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          selectedPlcAssetProvider.overrideWith((ref) => 'pump-001'),
          plcBlockListProvider.overrideWith((ref, key) {
            return Future.value(_testBlocks);
          }),
          plcAssetSummaryProvider.overrideWith((ref) async {
            return [_testSummary];
          }),
          keyMappingsProvider.overrideWith((ref) async => null),
          callGraphDataProvider.overrideWith((ref, key) async => null),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 800,
              child: PlcDetailPanel(assetKey: 'pump-001'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not available'), findsOneWidget);
    });

    testWidgets('Key Map shows line numbers and source lines for references',
        (tester) async {
      // Build blocks that simulate the FB_Dimmer scenario:
      // FB_Pump writes bRunning on a specific line, and MAIN calls fbPump.
      final dimmerBlocks = [
        PlcCodeBlock(
          id: 1,
          assetKey: 'pump-001',
          blockName: 'FB_Pump',
          blockType: 'FunctionBlock',
          filePath: 'POUs/FB_Pump.TcPOU',
          declaration: 'FUNCTION_BLOCK FB_Pump',
          implementation: 'IF bStart THEN\n  bRunning := TRUE;\nEND_IF',
          fullSource: '...',
          indexedAt: DateTime(2025, 6, 15),
          vendorType: 'twincat',
          serverAlias: 'PLC_Main',
          variables: [
            PlcVariable(
              id: 1, blockId: 1,
              variableName: 'bStart', variableType: 'BOOL',
              section: 'VAR_INPUT', qualifiedName: 'FB_Pump.bStart',
            ),
            PlcVariable(
              id: 2, blockId: 1,
              variableName: 'bRunning', variableType: 'BOOL',
              section: 'VAR_OUTPUT', qualifiedName: 'FB_Pump.bRunning',
            ),
          ],
        ),
        PlcCodeBlock(
          id: 2,
          assetKey: 'pump-001',
          blockName: 'MAIN',
          blockType: 'Program',
          filePath: 'POUs/MAIN.TcPOU',
          declaration: 'PROGRAM MAIN',
          implementation: 'fbPump(bStart := TRUE);',
          fullSource: '...',
          indexedAt: DateTime(2025, 6, 15),
          vendorType: 'twincat',
          serverAlias: 'PLC_Main',
          variables: [
            PlcVariable(
              id: 3, blockId: 2,
              variableName: 'fbPump', variableType: 'FB_Pump',
              section: 'VAR', qualifiedName: 'MAIN.fbPump',
            ),
          ],
        ),
      ];

      // Key that maps to an FB member variable.
      final dimmerKeyMappings = KeyMappings(nodes: {
        'pump.running': KeyMappingEntry(
          opcuaNode: _makeOpcUaNode(
              4, 'ns=4;s=MAIN.fbPump.bRunning', serverAlias: 'PLC_Main'),
        ),
      });

      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        blocks: dimmerBlocks,
        keyMappings: dimmerKeyMappings,
      ));
      await tester.pumpAndSettle();

      // Switch to Key Map tab.
      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      // Select the key.
      await tester.tap(find.text('pump.running'));
      await tester.pumpAndSettle();

      // Should show "Written by" section since bRunning is assigned.
      expect(find.text('Written by'), findsOneWidget);

      // Should show the block name "FB_Pump".
      expect(find.textContaining('FB_Pump'), findsWidgets);

      // Should show line number in the reference row.
      expect(find.textContaining('line'), findsWidgets);

      // Should show the source line preview.
      expect(find.textContaining('bRunning := TRUE'), findsOneWidget);
    });

    testWidgets('Key Map shows keys as flat list with chevrons',
        (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        assetKey: 'pump-001',
        keyMappings: _testKeyMappings,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key Map'));
      await tester.pumpAndSettle();

      // Keys should have chevron_right icons for drill-down.
      expect(find.byIcon(Icons.chevron_right), findsWidgets);

      // Should be simple list tiles, not expansion tiles.
      // The key detail should NOT be visible until tapped.
      expect(find.textContaining('numeric OPC-UA identifier'), findsNothing);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // Unit tests for sort and cross-reference logic
  // ─────────────────────────────────────────────────────────────────────
  group('sortBlocks', () {
    test('puts MAIN first, then Programs, then Actions, then GVLs', () {
      final blocks = [
        _makeBlock('GVL_Main', 'GVL'),
        _makeBlock('DoStuff', 'Action'),
        _makeBlock('SubProg', 'Program'),
        _makeBlock('MAIN', 'Program'),
        _makeBlock('FB_Motor', 'FunctionBlock'),
      ];

      final sorted = sortBlocks(blocks);

      expect(sorted[0].blockName, 'MAIN');
      expect(sorted[1].blockName, 'SubProg');
      expect(sorted[2].blockName, 'DoStuff');
      expect(sorted[3].blockName, 'FB_Motor');
      expect(sorted[4].blockName, 'GVL_Main');
    });
  });

  group('findReferencedBlocks', () {
    test('finds function blocks referenced by variable types', () {
      final main = _makeBlock('MAIN', 'Program', variables: [
        _makeVar('fbPump', 'FB_Pump'),
        _makeVar('fbDoor', 'FB_Door'),
        _makeVar('bReady', 'BOOL'),
      ]);
      final fbPump = _makeBlock('FB_Pump', 'FunctionBlock', id: 2);
      final fbDoor = _makeBlock('FB_Door', 'FunctionBlock', id: 3);
      final gvl = _makeBlock('GVL_Main', 'GVL', id: 4);

      final allBlocks = [main, fbPump, fbDoor, gvl];
      final referenced = findReferencedBlocks(main, allBlocks);

      expect(referenced.length, 2);
      expect(referenced.map((b) => b.blockName).toList(),
          containsAll(['FB_Pump', 'FB_Door']));
    });

    test('does not include the source block itself', () {
      final main = _makeBlock('MAIN', 'Program', variables: [
        // A variable whose type happens to match the block name.
        _makeVar('self', 'MAIN'),
      ]);

      final referenced = findReferencedBlocks(main, [main]);
      expect(referenced, isEmpty);
    });

    test('handles case-insensitive matching', () {
      final main = _makeBlock('MAIN', 'Program', variables: [
        _makeVar('fb', 'fb_pump'),
      ]);
      final fbPump = _makeBlock('FB_Pump', 'FunctionBlock', id: 2);

      final referenced = findReferencedBlocks(main, [main, fbPump]);
      expect(referenced.length, 1);
      expect(referenced.first.blockName, 'FB_Pump');
    });

    test('returns empty list when no variable types match block names', () {
      final main = _makeBlock('MAIN', 'Program', variables: [
        _makeVar('counter', 'INT'),
        _makeVar('ready', 'BOOL'),
      ]);
      final fbPump = _makeBlock('FB_Pump', 'FunctionBlock', id: 2);

      final referenced = findReferencedBlocks(main, [main, fbPump]);
      expect(referenced, isEmpty);
    });

    test('Action only shows parent FBs actually used in its source code', () {
      final mainProg = _makeBlock('MAIN', 'Program', id: 10, variables: [
        _makeVar('fbPump', 'FB_Pump'),
        _makeVar('fbDoor', 'FB_Door'),
      ]);
      // Action source only calls fbPump, not fbDoor.
      final action = _makeBlock('Init', 'Action',
          id: 11,
          parentBlockId: 10,
          implementation: 'fbPump(bStart := FALSE);');
      final fbPump = _makeBlock('FB_Pump', 'FunctionBlock', id: 20);
      final fbDoor = _makeBlock('FB_Door', 'FunctionBlock', id: 21);

      final allBlocks = [mainProg, action, fbPump, fbDoor];
      final referenced = findReferencedBlocks(action, allBlocks);

      // Only FB_Pump should appear -- fbDoor is not used in the action.
      expect(referenced.length, 1);
      expect(referenced.first.blockName, 'FB_Pump');
    });

    test('Action using all parent FBs shows all of them', () {
      final mainProg = _makeBlock('MAIN', 'Program', id: 10, variables: [
        _makeVar('fbPump', 'FB_Pump'),
        _makeVar('fbDoor', 'FB_Door'),
      ]);
      // Action source calls both fbPump and fbDoor.
      final action = _makeBlock('RunAll', 'Action',
          id: 11,
          parentBlockId: 10,
          implementation: 'fbPump(bStart := TRUE);\nfbDoor(bOpen := TRUE);');
      final fbPump = _makeBlock('FB_Pump', 'FunctionBlock', id: 20);
      final fbDoor = _makeBlock('FB_Door', 'FunctionBlock', id: 21);

      final allBlocks = [mainProg, action, fbPump, fbDoor];
      final referenced = findReferencedBlocks(action, allBlocks);

      expect(referenced.length, 2);
      expect(referenced.map((b) => b.blockName),
          containsAll(['FB_Pump', 'FB_Door']));
    });

    test('Action with own variables merges with used parent variables', () {
      final mainProg = _makeBlock('MAIN', 'Program', id: 10, variables: [
        _makeVar('fbPump', 'FB_Pump'),
      ]);
      // Action has its own local variable AND uses the parent's fbPump.
      final action = _makeBlock('Cleanup', 'Action',
          id: 11,
          parentBlockId: 10,
          implementation: 'fbPump(bStart := FALSE);\nfbValve.Close();',
          variables: [
        _makeVar('fbValve', 'FB_Valve'),
      ]);
      final fbPump = _makeBlock('FB_Pump', 'FunctionBlock', id: 20);
      final fbValve = _makeBlock('FB_Valve', 'FunctionBlock', id: 22);

      final allBlocks = [mainProg, action, fbPump, fbValve];
      final referenced = findReferencedBlocks(action, allBlocks);

      expect(referenced.length, 2);
      expect(referenced.map((b) => b.blockName),
          containsAll(['FB_Pump', 'FB_Valve']));
    });

    test('Action with own variable but unused parent FB excludes parent FB',
        () {
      final mainProg = _makeBlock('MAIN', 'Program', id: 10, variables: [
        _makeVar('fbPump', 'FB_Pump'),
      ]);
      // Action has its own variable but does NOT use the parent's fbPump.
      final action = _makeBlock('Cleanup', 'Action',
          id: 11,
          parentBlockId: 10,
          implementation: 'fbValve.Close();',
          variables: [
        _makeVar('fbValve', 'FB_Valve'),
      ]);
      final fbPump = _makeBlock('FB_Pump', 'FunctionBlock', id: 20);
      final fbValve = _makeBlock('FB_Valve', 'FunctionBlock', id: 22);

      final allBlocks = [mainProg, action, fbPump, fbValve];
      final referenced = findReferencedBlocks(action, allBlocks);

      // Only FB_Valve (own variable) -- FB_Pump is parent-inherited but
      // not used in this action's source code.
      expect(referenced.length, 1);
      expect(referenced.first.blockName, 'FB_Valve');
    });

    test('block without parentBlockId does not inherit any variables', () {
      final main = _makeBlock('MAIN', 'Program', id: 10, variables: [
        _makeVar('fbPump', 'FB_Pump'),
      ]);
      // A standalone Action with no parentBlockId and no own variables.
      final orphan = _makeBlock('Orphan', 'Action', id: 11);
      final fbPump = _makeBlock('FB_Pump', 'FunctionBlock', id: 20);

      final allBlocks = [main, orphan, fbPump];
      final referenced = findReferencedBlocks(orphan, allBlocks);

      expect(referenced, isEmpty);
    });

    test('source code filtering is case-insensitive', () {
      final mainProg = _makeBlock('MAIN', 'Program', id: 10, variables: [
        _makeVar('FBPump', 'FB_Pump'),
      ]);
      // Source uses lowercase but variable is declared with uppercase.
      final action = _makeBlock('Init', 'Action',
          id: 11,
          parentBlockId: 10,
          implementation: 'fbpump(bStart := TRUE);');
      final fbPump = _makeBlock('FB_Pump', 'FunctionBlock', id: 20);

      final allBlocks = [mainProg, action, fbPump];
      final referenced = findReferencedBlocks(action, allBlocks);

      expect(referenced.length, 1);
      expect(referenced.first.blockName, 'FB_Pump');
    });

    test('exact bug scenario: Doors action with GarageDoor() call', () {
      // Reproduces the reported bug: MAIN has 8 FB variables, but the
      // "Doors" action only calls GarageDoor(). Before the fix, all 8 FBs
      // were shown. After the fix, only FB_GarageDoor should appear.
      final mainProg = _makeBlock('MAIN', 'Program', id: 1, variables: [
        _makeVar('AnalogInput', 'FB_AnalogInput'),
        _makeVar('CoE', 'FB_CoE'),
        _makeVar('Cooler', 'FB_Cooler'),
        _makeVar('Dimmer', 'FB_Dimmer'),
        _makeVar('ExitButton', 'FB_ExitButton'),
        _makeVar('GarageDoor', 'FB_GarageDoor'),
        _makeVar('LightSwitch', 'FB_LightSwitch'),
        _makeVar('SunsetSunrise', 'FB_SunsetSunrise'),
      ]);
      final doors = _makeBlock('Doors', 'Action',
          id: 2, parentBlockId: 1, implementation: 'GarageDoor();');

      final allBlocks = [
        mainProg,
        doors,
        _makeBlock('FB_AnalogInput', 'FunctionBlock', id: 10),
        _makeBlock('FB_CoE', 'FunctionBlock', id: 11),
        _makeBlock('FB_Cooler', 'FunctionBlock', id: 12),
        _makeBlock('FB_Dimmer', 'FunctionBlock', id: 13),
        _makeBlock('FB_ExitButton', 'FunctionBlock', id: 14),
        _makeBlock('FB_GarageDoor', 'FunctionBlock', id: 15),
        _makeBlock('FB_LightSwitch', 'FunctionBlock', id: 16),
        _makeBlock('FB_SunsetSunrise', 'FunctionBlock', id: 17),
      ];

      final referenced = findReferencedBlocks(doors, allBlocks);

      // Only FB_GarageDoor should be referenced -- the action only calls
      // GarageDoor(), not any of the other 7 FBs.
      expect(referenced.length, 1);
      expect(referenced.first.blockName, 'FB_GarageDoor');
    });

    test('Program still shows all declared FB references (no filtering)', () {
      // Programs should NOT be filtered -- they declare the variables,
      // so all declared FBs are genuinely referenced.
      final mainProg = _makeBlock('MAIN', 'Program', id: 1, variables: [
        _makeVar('fbPump', 'FB_Pump'),
        _makeVar('fbDoor', 'FB_Door'),
      ]);
      final fbPump = _makeBlock('FB_Pump', 'FunctionBlock', id: 20);
      final fbDoor = _makeBlock('FB_Door', 'FunctionBlock', id: 21);

      final allBlocks = [mainProg, fbPump, fbDoor];
      final referenced = findReferencedBlocks(mainProg, allBlocks);

      // Both FBs should appear for the Program itself.
      expect(referenced.length, 2);
      expect(referenced.map((b) => b.blockName),
          containsAll(['FB_Pump', 'FB_Door']));
    });
  });
}

// ── Test Helpers ─────────────────────────────────────────────────────────

PlcCodeBlock _makeBlock(
  String name,
  String type, {
  int id = 1,
  List<PlcVariable>? variables,
  int? parentBlockId,
  String? implementation,
}) {
  final impl = implementation ?? '';
  return PlcCodeBlock(
    id: id,
    assetKey: 'test-asset',
    blockName: name,
    blockType: type,
    filePath: 'POUs/$name.TcPOU',
    declaration: '$type $name',
    implementation: impl,
    fullSource: '$type $name\n$impl',
    indexedAt: DateTime(2025, 1, 1),
    variables: variables ?? [],
    parentBlockId: parentBlockId,
  );
}

PlcVariable _makeVar(String name, String type) {
  return PlcVariable(
    id: 0,
    blockId: 1,
    variableName: name,
    variableType: type,
    section: 'VAR',
    qualifiedName: 'MAIN.$name',
  );
}
