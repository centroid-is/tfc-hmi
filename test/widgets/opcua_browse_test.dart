import 'dart:async';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:open62541/open62541.dart'
    show
        BrowseResultItem,
        BrowseTreeItem,
        ClientApi,
        ClientState,
        DynamicValue,
        NodeClass,
        NodeId;

import 'package:tfc/widgets/opcua_browse.dart';

// ---------------------------------------------------------------------------
// Fake ClientApi
// ---------------------------------------------------------------------------

class FakeClientApi implements ClientApi {
  final Map<NodeId, List<BrowseResultItem>> browseResults;
  final Map<NodeId, DynamicValue> readResults;
  int browseCallCount = 0;
  int readCallCount = 0;
  Duration browseDelay;

  FakeClientApi({
    this.browseResults = const {},
    this.readResults = const {},
    this.browseDelay = Duration.zero,
  });

  @override
  Future<List<BrowseResultItem>> browse(
    NodeId nodeId, {
    int direction = 0,
    NodeId? referenceTypeId,
    bool includeSubtypes = true,
    int nodeClassMask = 0,
    int resultMask = 63,
  }) async {
    browseCallCount++;
    if (browseDelay > Duration.zero) {
      await Future.delayed(browseDelay);
    }
    return browseResults[nodeId] ?? [];
  }

  @override
  Future<DynamicValue> read(NodeId nodeId) async {
    readCallCount++;
    return readResults[nodeId] ?? DynamicValue();
  }

  // -- Unused stubs --
  @override
  Future<void> awaitConnect() async {}
  @override
  Future<void> connect(String url) async {}
  @override
  Future<void> delete() async {}
  @override
  Future<void> write(NodeId nodeId, DynamicValue value) async {}
  @override
  Stream<ClientState> get stateStream => const Stream.empty();
  @override
  Future<int> subscriptionCreate({
    Duration requestedPublishingInterval = const Duration(milliseconds: 100),
    int requestedLifetimeCount = 10000,
    int requestedMaxKeepAliveCount = 10,
    int maxNotificationsPerPublish = 0,
    bool publishingEnabled = true,
    int priority = 0,
  }) async =>
      0;
  @override
  Stream<DynamicValue> monitor(
    NodeId nodeId,
    int subscriptionId, {
    dynamic monitoringMode,
    Duration samplingInterval = const Duration(milliseconds: 100),
    bool discardOldest = true,
    int queueSize = 1,
  }) =>
      const Stream.empty();
  @override
  Stream<BrowseTreeItem> browseTree(
    NodeId root, {
    int maxDepth = 100,
    NodeId? referenceTypeId,
    bool includeSubtypes = true,
    Set<NodeClass> recurseInto = const {
      NodeClass.UA_NODECLASS_OBJECT,
      NodeClass.UA_NODECLASS_VIEW,
    },
  }) =>
      const Stream.empty();
  @override
  Future<List<DynamicValue>> call(
          NodeId objectId, NodeId methodId, Iterable<DynamicValue> args) async =>
      [];
  @override
  Future<Map<NodeId, DynamicValue>> readAttribute(
          Map<NodeId, List<dynamic>> nodes) async =>
      {};
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

NodeId _nodeId(int ns, String s) => NodeId.fromString(ns, s);

BrowseResultItem _object(String name, {int ns = 2, String? id}) =>
    BrowseResultItem(
      referenceTypeId: NodeId.fromNumeric(0, 0),
      isForward: true,
      nodeId: _nodeId(ns, id ?? name),
      browseName: name,
      displayName: name,
      nodeClass: NodeClass.UA_NODECLASS_OBJECT,
    );

BrowseResultItem _variable(String name, {int ns = 2, String? id}) =>
    BrowseResultItem(
      referenceTypeId: NodeId.fromNumeric(0, 0),
      isForward: true,
      nodeId: _nodeId(ns, id ?? name),
      browseName: name,
      displayName: name,
      nodeClass: NodeClass.UA_NODECLASS_VARIABLE,
    );

BrowseResultItem _method(String name, {int ns = 2, String? id}) =>
    BrowseResultItem(
      referenceTypeId: NodeId.fromNumeric(0, 0),
      isForward: true,
      nodeId: _nodeId(ns, id ?? name),
      browseName: name,
      displayName: name,
      nodeClass: NodeClass.UA_NODECLASS_METHOD,
    );

/// Pumps an [OpcUaBrowsePanel] inside a dialog (using [showOpcUaBrowseDialog]).
/// Returns a future that completes when the dialog is closed with the result.
Future<void> _showPanel(
  WidgetTester tester,
  FakeClientApi client, {
  String alias = 'TestServer',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showOpcUaBrowseDialog(
                context: context,
                client: client,
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
  group('OpcUaBrowsePanel', () {
    testWidgets('shows loading indicator then root nodes', (tester) async {
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [
            _object('Server'),
            _object('MyDevice'),
          ],
        },
      );

      await _showPanel(tester, client);

      expect(find.text('Server'), findsOneWidget);
      expect(find.text('MyDevice'), findsOneWidget);
    });

    testWidgets('shows server alias in header', (tester) async {
      final client = FakeClientApi(
        browseResults: {NodeId.objectsFolder: []},
      );

      await _showPanel(tester, client, alias: 'opc.tcp://plc1:4840');

      expect(find.text('Browse: opc.tcp://plc1:4840'), findsOneWidget);
    });

    testWidgets('shows "No nodes found" for empty server', (tester) async {
      final client = FakeClientApi(
        browseResults: {NodeId.objectsFolder: []},
      );

      await _showPanel(tester, client);

      expect(find.text('No nodes found'), findsOneWidget);
    });

    testWidgets('shows error when browse fails', (tester) async {
      final client = _FailingBrowseClient();

      await _showPanel(tester, client);

      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('expanding an object node loads and shows children',
        (tester) async {
      final deviceId = _nodeId(2, 'MyDevice');
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [_object('MyDevice', id: 'MyDevice')],
          deviceId: [
            _variable('Temperature', id: 'Temp'),
            _variable('Pressure', id: 'Press'),
          ],
        },
      );

      await _showPanel(tester, client);

      expect(find.text('MyDevice'), findsOneWidget);
      expect(find.text('Temperature'), findsNothing);

      await tester.tap(find.text('MyDevice'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('Pressure'), findsOneWidget);
    });

    testWidgets('collapsing an expanded node hides children', (tester) async {
      final deviceId = _nodeId(2, 'MyDevice');
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [_object('MyDevice', id: 'MyDevice')],
          deviceId: [_variable('Temperature', id: 'Temp')],
        },
      );

      await _showPanel(tester, client);

      await tester.tap(find.text('MyDevice'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.text('Temperature'), findsOneWidget);

      await tester.tap(find.text('MyDevice'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.text('Temperature'), findsNothing);
    });

    testWidgets('tapping a variable node selects it', (tester) async {
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [_variable('SomeVar')],
        },
        readResults: {
          _nodeId(2, 'SomeVar'): DynamicValue()..value = 42,
        },
      );

      await _showPanel(tester, client);

      await tester.tap(find.text('SomeVar'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      final selectButton =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Select'));
      expect(selectButton.onPressed, isNotNull);
    });

    testWidgets('tapping Select with selected variable dismisses dialog',
        (tester) async {
      final varItem = _variable('MyVar');
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [varItem],
        },
        readResults: {
          varItem.nodeId: DynamicValue()..value = 99,
        },
      );

      await _showPanel(tester, client);

      await tester.tap(find.text('MyVar'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      expect(find.byType(OpcUaBrowsePanel), findsNothing);
    });

    testWidgets('double-tapping a variable dismisses dialog', (tester) async {
      final varItem = _variable('DblTapVar');
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [varItem],
        },
        readResults: {
          varItem.nodeId: DynamicValue()..value = 1,
        },
      );

      await _showPanel(tester, client);

      // First tap selects the variable
      await tester.tap(find.text('DblTapVar'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      // Second tap on the already-selected variable confirms (dismisses).
      // After selection, the breadcrumb also shows 'DblTapVar', so tap
      // the BrowseNodeTile directly to avoid ambiguity.
      await tester.tap(find.byType(BrowseNodeTile));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.byType(OpcUaBrowsePanel), findsNothing);
    });

    testWidgets('Cancel button dismisses dialog', (tester) async {
      final client = FakeClientApi(
        browseResults: {NodeId.objectsFolder: []},
      );

      await _showPanel(tester, client);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(OpcUaBrowsePanel), findsNothing);
    });

    testWidgets('Select button is disabled when no variable selected',
        (tester) async {
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [_object('Folder')],
        },
      );

      await _showPanel(tester, client);

      final selectButton =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Select'));
      expect(selectButton.onPressed, isNull);
    });

    testWidgets('detail strip shows when variable selected', (tester) async {
      final varItem = _variable('DetailVar');
      final dv = DynamicValue()..value = 3.14;
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [varItem],
        },
        readResults: {
          varItem.nodeId: dv,
        },
      );

      await _showPanel(tester, client);

      expect(find.byType(VariableDetailStrip), findsNothing);

      await tester.tap(find.text('DetailVar'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.byType(VariableDetailStrip), findsOneWidget);
      expect(find.text('3.14'), findsOneWidget);
    });

    testWidgets('detail strip shows error when read fails', (tester) async {
      final varItem = _variable('FailVar');
      final client = _FailingReadClient(
        browseResults: {
          NodeId.objectsFolder: [varItem],
        },
      );

      await _showPanel(tester, client);

      await tester.tap(find.text('FailVar'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('shows object, variable, and method icons', (tester) async {
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [
            _object('Folder1'),
            _variable('Var1'),
            _method('Method1'),
          ],
        },
      );

      await _showPanel(tester, client);

      // Standard Icon widgets
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      // FaIcon uses RichText, not Icon, so find.byIcon won't work
      expect(
        find.byWidgetPredicate(
            (w) => w is FaIcon && w.icon == FontAwesomeIcons.tag),
        findsOneWidget,
      );
    });

    testWidgets('breadcrumb shows Objects by default', (tester) async {
      final client = FakeClientApi(
        browseResults: {NodeId.objectsFolder: [_variable('X')]},
      );

      await _showPanel(tester, client);

      expect(find.text('Objects'), findsOneWidget);
    });

    testWidgets('tapping already-selected variable confirms selection',
        (tester) async {
      final varItem = _variable('ConfirmVar');
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [varItem],
        },
        readResults: {
          varItem.nodeId: DynamicValue()..value = 1,
        },
      );

      await _showPanel(tester, client);

      // First tap: select
      await tester.tap(find.text('ConfirmVar'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.byType(OpcUaBrowsePanel), findsOneWidget);

      // Second tap: confirm (dismiss). After selection, the breadcrumb also
      // shows 'ConfirmVar', so tap the BrowseNodeTile directly.
      await tester.tap(find.byType(BrowseNodeTile));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.byType(OpcUaBrowsePanel), findsNothing);
    });

    testWidgets('method nodes are not selectable', (tester) async {
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [_method('MyMethod')],
        },
      );

      await _showPanel(tester, client);

      await tester.tap(find.text('MyMethod'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      final selectButton =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Select'));
      expect(selectButton.onPressed, isNull);
    });

    testWidgets('nested expansion works multiple levels', (tester) async {
      final deviceId = _nodeId(2, 'Device');
      final sensorsId = _nodeId(2, 'Sensors');
      final client = FakeClientApi(
        browseResults: {
          NodeId.objectsFolder: [_object('Device', id: 'Device')],
          deviceId: [_object('Sensors', id: 'Sensors')],
          sensorsId: [_variable('TempSensor', id: 'TempSensor')],
        },
      );

      await _showPanel(tester, client);

      await tester.tap(find.text('Device'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.text('Sensors'), findsOneWidget);

      await tester.tap(find.text('Sensors'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.text('TempSensor'), findsOneWidget);
    });
  });

  group('BrowseTreeNode', () {
    test('isExpandable is true for objects', () {
      final node = BrowseTreeNode(
        item: _object('Obj'),
        depth: 0,
        parentNodeId: NodeId.objectsFolder,
      );
      expect(node.isExpandable, true);
      expect(node.isVariable, false);
    });

    test('isVariable is true for variables', () {
      final node = BrowseTreeNode(
        item: _variable('Var'),
        depth: 0,
        parentNodeId: NodeId.objectsFolder,
      );
      expect(node.isVariable, true);
      expect(node.isExpandable, false);
    });

    test('method nodes are neither expandable nor variable', () {
      final node = BrowseTreeNode(
        item: _method('Meth'),
        depth: 0,
        parentNodeId: NodeId.objectsFolder,
      );
      expect(node.isExpandable, false);
      expect(node.isVariable, false);
    });
  });

  group('formatDynamicValue', () {
    test('formats null value', () {
      expect(OpcUaBrowsePanelState.formatDynamicValue(DynamicValue()), 'null');
    });

    test('formats simple value', () {
      final dv = DynamicValue()..value = 42;
      expect(OpcUaBrowsePanelState.formatDynamicValue(dv), '42');
    });

    test('formats string value', () {
      final dv = DynamicValue()..value = 'hello';
      expect(OpcUaBrowsePanelState.formatDynamicValue(dv), 'hello');
    });

    test('truncates long string', () {
      final dv = DynamicValue()..value = 'x' * 200;
      final result = OpcUaBrowsePanelState.formatDynamicValue(dv);
      expect(result.length, 120);
      expect(result.endsWith('...'), true);
    });
  });
}

// ---------------------------------------------------------------------------
// Specialized fakes
// ---------------------------------------------------------------------------

class _FailingBrowseClient extends FakeClientApi {
  @override
  Future<List<BrowseResultItem>> browse(
    NodeId nodeId, {
    int direction = 0,
    NodeId? referenceTypeId,
    bool includeSubtypes = true,
    int nodeClassMask = 0,
    int resultMask = 63,
  }) async {
    throw Exception('Connection refused');
  }
}

class _FailingReadClient extends FakeClientApi {
  _FailingReadClient({super.browseResults});

  @override
  Future<DynamicValue> read(NodeId nodeId) async {
    throw Exception('buildSchema failed');
  }
}
