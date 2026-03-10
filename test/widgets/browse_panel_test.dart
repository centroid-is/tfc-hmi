import 'dart:async';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:tfc/widgets/browse_panel.dart';

// ---------------------------------------------------------------------------
// Fake BrowseDataSource
// ---------------------------------------------------------------------------

class FakeBrowseDataSource implements BrowseDataSource {
  final Map<String, List<BrowseNode>> _children;
  final Map<String, BrowseNodeDetail> _details;
  int fetchRootsCallCount = 0;
  int fetchChildrenCallCount = 0;
  int fetchDetailCallCount = 0;

  /// When non-null, fetchRoots() will await this completer instead of
  /// returning immediately. Call [rootsCompleter]!.complete() from the test
  /// to unblock it.
  Completer<void>? rootsCompleter;

  FakeBrowseDataSource({
    required List<BrowseNode> roots,
    Map<String, List<BrowseNode>>? children,
    Map<String, BrowseNodeDetail>? details,
    this.rootsCompleter,
  })  : _children = {
          '__roots__': roots,
          ...?children,
        },
        _details = details ?? {};

  @override
  Future<List<BrowseNode>> fetchRoots() async {
    fetchRootsCallCount++;
    if (rootsCompleter != null) await rootsCompleter!.future;
    return _children['__roots__'] ?? [];
  }

  @override
  Future<List<BrowseNode>> fetchChildren(BrowseNode parent) async {
    fetchChildrenCallCount++;
    return _children[parent.id] ?? [];
  }

  @override
  Future<BrowseNodeDetail> fetchDetail(BrowseNode node) async {
    fetchDetailCallCount++;
    return _details[node.id] ?? const BrowseNodeDetail();
  }
}

class FailingBrowseDataSource implements BrowseDataSource {
  @override
  Future<List<BrowseNode>> fetchRoots() async {
    throw Exception('Connection refused');
  }

  @override
  Future<List<BrowseNode>> fetchChildren(BrowseNode parent) async {
    throw Exception('Connection refused');
  }

  @override
  Future<BrowseNodeDetail> fetchDetail(BrowseNode node) async {
    throw Exception('Connection refused');
  }
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _plcFolder = BrowseNode(
  id: 'plc',
  displayName: 'PLC',
  type: BrowseNodeType.folder,
);

const _systemFolder = BrowseNode(
  id: 'system',
  displayName: 'System',
  type: BrowseNodeType.folder,
);

const _tempVar = BrowseNode(
  id: 'plc.temp',
  displayName: 'Temperature',
  type: BrowseNodeType.variable,
  dataType: 'REAL',
);

const _pressVar = BrowseNode(
  id: 'plc.press',
  displayName: 'Pressure',
  type: BrowseNodeType.variable,
  dataType: 'INT',
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _showPanel(
  WidgetTester tester,
  BrowseDataSource dataSource, {
  String alias = 'TestServer',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showBrowseDialog(
                context: context,
                dataSource: dataSource,
                serverAlias: alias,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BrowsePanel', () {
    testWidgets('Test 1: shows loading spinner while fetchRoots is pending',
        (tester) async {
      final completer = Completer<void>();
      final ds = FakeBrowseDataSource(
        roots: [_plcFolder, _systemFolder],
        rootsCompleter: completer,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showBrowseDialog(
                    context: context,
                    dataSource: ds,
                    serverAlias: 'TestServer',
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump(); // Show dialog
      await tester.pump(); // Build the panel (roots still pending)

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Unblock and settle to avoid pending timers
      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Test 2: renders root nodes from fetchRoots', (tester) async {
      final ds = FakeBrowseDataSource(
        roots: [_plcFolder, _systemFolder],
      );

      await _showPanel(tester, ds);

      expect(find.text('PLC'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
    });

    testWidgets('Test 3: tapping a folder expands it and shows children',
        (tester) async {
      final ds = FakeBrowseDataSource(
        roots: [_plcFolder],
        children: {
          'plc': [_tempVar, _pressVar],
        },
      );

      await _showPanel(tester, ds);

      expect(find.text('PLC'), findsOneWidget);
      expect(find.text('Temperature'), findsNothing);

      await tester.tap(find.text('PLC'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('Pressure'), findsOneWidget);
    });

    testWidgets('Test 4: tapping an expanded folder collapses it',
        (tester) async {
      final ds = FakeBrowseDataSource(
        roots: [_plcFolder],
        children: {
          'plc': [_tempVar],
        },
      );

      await _showPanel(tester, ds);

      // Expand
      await tester.tap(find.text('PLC'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.text('Temperature'), findsOneWidget);

      // Collapse
      await tester.tap(find.text('PLC'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.text('Temperature'), findsNothing);
    });

    testWidgets('Test 5: tapping a variable selects it and shows detail strip',
        (tester) async {
      final ds = FakeBrowseDataSource(
        roots: [_tempVar],
        details: {
          'plc.temp': const BrowseNodeDetail(
            value: '23.5',
            dataType: 'Float',
          ),
        },
      );

      await _showPanel(tester, ds);

      expect(find.byType(VariableDetailStrip), findsNothing);

      await tester.tap(find.text('Temperature'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.byType(VariableDetailStrip), findsOneWidget);
      expect(find.text('23.5'), findsOneWidget);

      // Select button should be enabled
      final selectButton =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Select'));
      expect(selectButton.onPressed, isNotNull);
    });

    testWidgets(
        'Test 6: double-tapping a variable calls onSelected with the BrowseNode',
        (tester) async {
      final ds = FakeBrowseDataSource(
        roots: [_tempVar],
        details: {
          'plc.temp': const BrowseNodeDetail(value: '23.5'),
        },
      );

      await _showPanel(tester, ds);

      // First tap to select
      await tester.tap(find.text('Temperature'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.byType(BrowsePanel), findsOneWidget);

      // Second tap on already-selected variable triggers onSelected (dismiss).
      // BrowseNodeTile is the specific widget, avoids breadcrumb ambiguity.
      await tester.tap(find.byType(BrowseNodeTile));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.byType(BrowsePanel), findsNothing);
    });

    testWidgets('Test 7: Select button calls onSelected', (tester) async {
      final ds = FakeBrowseDataSource(
        roots: [_tempVar],
        details: {
          'plc.temp': const BrowseNodeDetail(value: '23.5'),
        },
      );

      await _showPanel(tester, ds);

      // Select the variable
      await tester.tap(find.text('Temperature'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      // Click the Select button
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.byType(BrowsePanel), findsNothing);
    });

    testWidgets('Test 8: breadcrumb shows path from root to selected node',
        (tester) async {
      final ds = FakeBrowseDataSource(
        roots: [_plcFolder],
        children: {
          'plc': [_tempVar],
        },
        details: {
          'plc.temp': const BrowseNodeDetail(value: '23.5'),
        },
      );

      await _showPanel(tester, ds);

      // Default breadcrumb
      expect(find.text('Root'), findsOneWidget);

      // Expand PLC
      await tester.tap(find.text('PLC'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      // Select Temperature
      await tester.tap(find.text('Temperature'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      // Breadcrumb should show: Root > PLC > Temperature
      expect(find.text('Root'), findsOneWidget);
      // PLC appears in both the tree and the breadcrumb
      expect(find.text('PLC'), findsAtLeast(1));
      // Temperature appears in both the tree and the breadcrumb
      expect(find.text('Temperature'), findsAtLeast(1));
    });

    testWidgets('Test 9: error from fetchRoots shows error message',
        (tester) async {
      final ds = FailingBrowseDataSource();

      await _showPanel(tester, ds);

      expect(find.textContaining('Connection refused'), findsOneWidget);
    });

    // Additional tests for completeness

    testWidgets('shows server alias in header', (tester) async {
      final ds = FakeBrowseDataSource(roots: []);

      await _showPanel(tester, ds, alias: 'opc.tcp://plc1:4840');

      expect(find.text('Browse: opc.tcp://plc1:4840'), findsOneWidget);
    });

    testWidgets('Cancel button dismisses dialog', (tester) async {
      final ds = FakeBrowseDataSource(roots: []);

      await _showPanel(tester, ds);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(BrowsePanel), findsNothing);
    });

    testWidgets('Select button is disabled when no variable selected',
        (tester) async {
      final ds = FakeBrowseDataSource(
        roots: [_plcFolder],
      );

      await _showPanel(tester, ds);

      final selectButton =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Select'));
      expect(selectButton.onPressed, isNull);
    });

    testWidgets('shows folder, variable, and method icons', (tester) async {
      const method = BrowseNode(
        id: 'mymethod',
        displayName: 'MyMethod',
        type: BrowseNodeType.method,
      );
      final ds = FakeBrowseDataSource(
        roots: [_plcFolder, _tempVar, method],
      );

      await _showPanel(tester, ds);

      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(
        find.byWidgetPredicate(
            (w) => w is FaIcon && w.icon == FontAwesomeIcons.tag),
        findsOneWidget,
      );
    });
  });

  group('BrowseNode', () {
    test('folder is expandable but not variable', () {
      expect(_plcFolder.isExpandable, true);
      expect(_plcFolder.isVariable, false);
      expect(_plcFolder.isFolder, true);
    });

    test('variable is expandable and is variable', () {
      expect(_tempVar.isExpandable, true);
      expect(_tempVar.isVariable, true);
      expect(_tempVar.isFolder, false);
    });

    test('method is neither expandable nor variable', () {
      const method = BrowseNode(
        id: 'meth',
        displayName: 'Meth',
        type: BrowseNodeType.method,
      );
      expect(method.isExpandable, false);
      expect(method.isVariable, false);
    });
  });
}
