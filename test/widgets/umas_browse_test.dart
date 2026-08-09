import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_fb_browse_types.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:tfc_dart/core/state_man.dart' show ModbusConfig;
import 'package:tfc/widgets/umas_browse.dart';
import 'package:tfc/widgets/browse_panel.dart';

/// Fake UmasClient that returns canned tree data for testing.
///
/// Also records calls to [readVariables] so tests can assert the
/// single-batched-read invariant for FB instance fetchDetail.
class FakeUmasClient extends UmasClient {
  final List<UmasVariableTreeNode> _tree;

  /// Records the pair list passed to each [readVariables] invocation.
  /// One entry per call — length 1 means a single batched fan-out.
  final List<List<(UmasVariable, UmasDataTypeRef)>> readCalls = [];

  /// Canned values keyed by `variable.offset`. Order-independent — the
  /// fake looks up the canned value for whichever offsets are requested,
  /// in the order requested, so it preserves [readVariables]'s ordering
  /// contract without depending on the call site listing members in a
  /// particular order.
  final Map<int, TypedVariableValue> _cannedByOffset;

  FakeUmasClient(
    this._tree, {
    Map<int, TypedVariableValue>? cannedByOffset,
  })  : _cannedByOffset = cannedByOffset ?? const {},
        super(sendFn: (_) => throw UnimplementedError());

  @override
  Future<List<UmasVariableTreeNode>> browse({int maxDepth = 6}) async => _tree;

  @override
  Future<PlcStatusResult> readPlcStatus() async {
    // The scalar branch of fetchDetail calls readPlcStatus before
    // dispatching to readVariables. Stub it out so tests can drive
    // readVariables without a live PLC — we intercept readVariables
    // at the public method below, so the parent's internal _blockCrcs
    // gating never fires.
    return PlcStatusResult(
      statusByte: 0x00,
      numberOfBlocks: 0,
      blockCrcs: const [],
      additionalData: Uint8List(0),
    );
  }

  @override
  Future<List<TypedVariableValue>> readVariables(
      List<(UmasVariable, UmasDataTypeRef)> variables) async {
    readCalls.add(List.unmodifiable(variables));
    return [
      for (final (v, _) in variables)
        _cannedByOffset[v.offset] ??
            TypedVariableValue(
              value: 0,
              typeName: 'UNKNOWN',
              rawBytes: Uint8List(0),
            ),
    ];
  }
}

/// Builds a sample variable tree that contains a function-block instance
/// `M_F2_RC_01` with three readable members (input/output/publicVar via a
/// nested folder) and one unreadable VAR_IN_OUT member.
///
/// Shape:
///   App (folder)
///     +-- M_F2_RC_01 (folder, no variable — but children have variables)
///           +-- i_setpoint (REAL, block=178, offset=0, direction=input)
///           +-- q_actual   (REAL, block=178, offset=4, direction=output)
///           +-- iq_pointer (DINT, block=178, offset=8, direction=inOut,
///                           readable=false)
///           +-- Nested (folder)
///                 +-- p_count (UINT, block=178, offset=12, direction=publicVar)
List<UmasVariableTreeNode> sampleTreeWithFb() {
  return [
    UmasVariableTreeNode(
      name: 'App',
      path: 'App',
      children: [
        UmasVariableTreeNode(
          name: 'M_F2_RC_01',
          path: 'App.M_F2_RC_01',
          children: [
            UmasVariableTreeNode(
              name: 'i_setpoint',
              path: 'App.M_F2_RC_01.i_setpoint',
              variable: const UmasVariable(
                name: 'App.M_F2_RC_01.i_setpoint',
                blockNo: 178,
                offset: 0,
                dataTypeId: 8,
              ),
              dataType: const UmasDataTypeRef(id: 8, name: 'REAL', byteSize: 4),
              direction: UmasFbMemberDirection.input,
            ),
            UmasVariableTreeNode(
              name: 'q_actual',
              path: 'App.M_F2_RC_01.q_actual',
              variable: const UmasVariable(
                name: 'App.M_F2_RC_01.q_actual',
                blockNo: 178,
                offset: 4,
                dataTypeId: 8,
              ),
              dataType: const UmasDataTypeRef(id: 8, name: 'REAL', byteSize: 4),
              direction: UmasFbMemberDirection.output,
            ),
            UmasVariableTreeNode(
              name: 'iq_pointer',
              path: 'App.M_F2_RC_01.iq_pointer',
              variable: const UmasVariable(
                name: 'App.M_F2_RC_01.iq_pointer',
                blockNo: 178,
                offset: 8,
                dataTypeId: 6,
              ),
              dataType: const UmasDataTypeRef(id: 6, name: 'DINT', byteSize: 4),
              direction: UmasFbMemberDirection.inOut,
              readable: false,
              unreadableReason: 'VAR_IN_OUT (PLC returns 0x94)',
            ),
            UmasVariableTreeNode(
              name: 'Nested',
              path: 'App.M_F2_RC_01.Nested',
              children: [
                UmasVariableTreeNode(
                  name: 'p_count',
                  path: 'App.M_F2_RC_01.Nested.p_count',
                  variable: const UmasVariable(
                    name: 'App.M_F2_RC_01.Nested.p_count',
                    blockNo: 178,
                    offset: 12,
                    dataTypeId: 5,
                  ),
                  dataType:
                      const UmasDataTypeRef(id: 5, name: 'UINT', byteSize: 2),
                  direction: UmasFbMemberDirection.publicVar,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ];
}

/// Production-shape FB instance tree: the FB instance node itself
/// carries BOTH `variable` (with blockNo + dataTypeId — the FB lives at
/// a memory address) AND non-empty `children` (its members). This is
/// what the live M580 browse() actually returns for a node like
/// `M_F2_RC_01`. The earlier [sampleTreeWithFb] omits the
/// instance-level variable so the FB instance is dispatched through
/// `BrowseNodeType.folder`, hiding the branch-order regression this
/// fixture pins down. See `lib/widgets/umas_browse.dart::fetchDetail`.
List<UmasVariableTreeNode> sampleTreeWithProductionShapeFb() {
  return [
    UmasVariableTreeNode(
      name: 'App',
      path: 'App',
      children: [
        UmasVariableTreeNode(
          name: 'M_F2_RC_01',
          path: 'App.M_F2_RC_01',
          // Instance-level variable: the FB lives at block=178, offset=0.
          // dataTypeId points at the FB type, NOT a primitive.
          variable: const UmasVariable(
            name: 'App.M_F2_RC_01',
            blockNo: 178,
            offset: 0,
            dataTypeId: 0xb2,
          ),
          dataType: const UmasDataTypeRef(
              id: 0xb2, name: 'F2_RC_TYPE', byteSize: 16),
          children: [
            UmasVariableTreeNode(
              name: 'i_setpoint',
              path: 'App.M_F2_RC_01.i_setpoint',
              variable: const UmasVariable(
                name: 'App.M_F2_RC_01.i_setpoint',
                blockNo: 178,
                offset: 0,
                dataTypeId: 8,
              ),
              dataType: const UmasDataTypeRef(id: 8, name: 'REAL', byteSize: 4),
              direction: UmasFbMemberDirection.input,
            ),
            UmasVariableTreeNode(
              name: 'q_actual',
              path: 'App.M_F2_RC_01.q_actual',
              variable: const UmasVariable(
                name: 'App.M_F2_RC_01.q_actual',
                blockNo: 178,
                offset: 4,
                dataTypeId: 8,
              ),
              dataType: const UmasDataTypeRef(id: 8, name: 'REAL', byteSize: 4),
              direction: UmasFbMemberDirection.output,
            ),
          ],
        ),
      ],
    ),
  ];
}

/// Builds a pure-folder tree with no readable variable leaves anywhere —
/// guards the safety net in fetchDetail (do not call readVariables on an
/// empty leaf set).
List<UmasVariableTreeNode> sampleTreePureFolders() {
  return [
    UmasVariableTreeNode(
      name: 'App',
      path: 'App',
      children: [
        UmasVariableTreeNode(
          name: 'EmptyA',
          path: 'App.EmptyA',
          children: [
            UmasVariableTreeNode(
              name: 'EmptyB',
              path: 'App.EmptyA.EmptyB',
              children: [],
            ),
          ],
        ),
      ],
    ),
  ];
}

/// Builds a sample variable tree for testing:
/// App (folder)
///   +-- GVL (folder)
///   |    +-- temperature (variable: REAL, block=1, offset=0)
///   |    +-- pressure (variable: DINT, block=1, offset=4)
///   +-- Motor (folder)
///        +-- speed (variable: UINT, block=2, offset=0)
List<UmasVariableTreeNode> sampleTree() {
  return [
    UmasVariableTreeNode(
      name: 'App',
      path: 'App',
      children: [
        UmasVariableTreeNode(
          name: 'GVL',
          path: 'App.GVL',
          children: [
            UmasVariableTreeNode(
              name: 'temperature',
              path: 'App.GVL.temperature',
              variable: const UmasVariable(
                name: 'App.GVL.temperature',
                blockNo: 1,
                offset: 0,
                dataTypeId: 5,
              ),
              dataType: const UmasDataTypeRef(id: 5, name: 'REAL', byteSize: 4),
            ),
            UmasVariableTreeNode(
              name: 'pressure',
              path: 'App.GVL.pressure',
              variable: const UmasVariable(
                name: 'App.GVL.pressure',
                blockNo: 1,
                offset: 4,
                dataTypeId: 3,
              ),
              dataType: const UmasDataTypeRef(id: 3, name: 'DINT', byteSize: 4),
            ),
          ],
        ),
        UmasVariableTreeNode(
          name: 'Motor',
          path: 'App.Motor',
          children: [
            UmasVariableTreeNode(
              name: 'speed',
              path: 'App.Motor.speed',
              variable: const UmasVariable(
                name: 'App.Motor.speed',
                blockNo: 2,
                offset: 0,
                dataTypeId: 2,
              ),
              dataType: const UmasDataTypeRef(id: 2, name: 'UINT', byteSize: 2),
            ),
          ],
        ),
      ],
    ),
  ];
}

void main() {
  group('UmasBrowseDataSource', () {
    late FakeUmasClient fakeClient;
    late UmasBrowseDataSource dataSource;

    setUp(() {
      fakeClient = FakeUmasClient(sampleTree());
      dataSource = UmasBrowseDataSource(fakeClient);
    });

    test('fetchRoots returns root folder nodes from UmasClient.browse()', () async {
      final roots = await dataSource.fetchRoots();

      expect(roots, hasLength(1));
      expect(roots.first.displayName, 'App');
      expect(roots.first.id, 'App');
      expect(roots.first.type, BrowseNodeType.folder);
    });

    test('fetchChildren returns children of a folder node', () async {
      // First load roots to cache tree
      await dataSource.fetchRoots();

      final parent = BrowseNode(
        id: 'App',
        displayName: 'App',
        type: BrowseNodeType.folder,
      );
      final children = await dataSource.fetchChildren(parent);

      expect(children, hasLength(2));
      expect(children.map((c) => c.displayName).toSet(), {'GVL', 'Motor'});
      expect(children.every((c) => c.type == BrowseNodeType.folder), isTrue);
    });

    test('fetchChildren returns variable leaf nodes', () async {
      await dataSource.fetchRoots();

      final gvl = BrowseNode(
        id: 'App.GVL',
        displayName: 'GVL',
        type: BrowseNodeType.folder,
      );
      final children = await dataSource.fetchChildren(gvl);

      expect(children, hasLength(2));
      expect(children.map((c) => c.displayName).toSet(),
          {'temperature', 'pressure'});
      expect(children.every((c) => c.type == BrowseNodeType.variable), isTrue);
    });

    test('variable BrowseNode has blockNo and offset in metadata', () async {
      await dataSource.fetchRoots();

      final gvl = BrowseNode(
        id: 'App.GVL',
        displayName: 'GVL',
        type: BrowseNodeType.folder,
      );
      final children = await dataSource.fetchChildren(gvl);
      final temp = children.firstWhere((c) => c.displayName == 'temperature');

      expect(temp.metadata['blockNo'], '1');
      expect(temp.metadata['offset'], '0');
      expect(temp.metadata['dataTypeId'], '5');
      expect(temp.metadata['dataTypeName'], 'REAL');
      expect(temp.metadata['byteSize'], '4');
      expect(temp.metadata['path'], 'App.GVL.temperature');
    });

    test('variable BrowseNode has dataType set', () async {
      await dataSource.fetchRoots();

      final motor = BrowseNode(
        id: 'App.Motor',
        displayName: 'Motor',
        type: BrowseNodeType.folder,
      );
      final children = await dataSource.fetchChildren(motor);
      final speed = children.firstWhere((c) => c.displayName == 'speed');

      expect(speed.dataType, 'UINT');
    });

    test('fetchDetail returns path as description', () async {
      await dataSource.fetchRoots();

      final node = BrowseNode(
        id: 'App.GVL.temperature',
        displayName: 'temperature',
        type: BrowseNodeType.variable,
        dataType: 'REAL',
        metadata: {
          'path': 'App.GVL.temperature',
          'blockNo': '1',
          'offset': '0',
        },
      );
      final detail = await dataSource.fetchDetail(node);

      expect(detail.description, 'App.GVL.temperature');
      expect(detail.dataType, 'REAL');
    });

    test('fetchChildren returns empty list for unknown node', () async {
      await dataSource.fetchRoots();

      final unknown = BrowseNode(
        id: 'NonExistent.Path',
        displayName: 'unknown',
        type: BrowseNodeType.folder,
      );
      final children = await dataSource.fetchChildren(unknown);

      expect(children, isEmpty);
    });

    test('fetchRoots caches tree on second call', () async {
      final roots1 = await dataSource.fetchRoots();
      final roots2 = await dataSource.fetchRoots();

      // Same object -- tree was cached, not re-fetched
      expect(identical(roots1.first.id, roots2.first.id), isTrue);
    });

    // -----------------------------------------------------------------
    // FB instance fetchDetail — inspection-layer tests (260519-hgc).
    // Headline v1.1 promise: clicking an FB instance shows
    // {member: value, ...} not the empty `[]` placeholder.
    // -----------------------------------------------------------------

    test('fetchDetail on scalar leaf still does a single ref read '
        'and returns structChildren=null', () async {
      // Regression sentinel: the new FB branch must not capture the
      // scalar code path. Clicking App.GVL.temperature must still
      // produce exactly one readVariables call with one ref, and the
      // detail.structChildren must be null (NOT empty list).
      fakeClient = FakeUmasClient(
        sampleTree(),
        cannedByOffset: {
          0: TypedVariableValue(
            value: 21.5,
            typeName: 'REAL',
            rawBytes: Uint8List(0),
          ),
        },
      );
      dataSource = UmasBrowseDataSource(fakeClient);
      await dataSource.fetchRoots();

      final node = BrowseNode(
        id: 'App.GVL.temperature',
        displayName: 'temperature',
        type: BrowseNodeType.variable,
        dataType: 'REAL',
        metadata: const {
          'path': 'App.GVL.temperature',
          'blockNo': '1',
          'offset': '0',
          'dataTypeId': '5',
          'dataTypeName': 'REAL',
          'byteSize': '4',
        },
      );
      final detail = await dataSource.fetchDetail(node);

      expect(fakeClient.readCalls.length, 1,
          reason: 'scalar leaf should issue exactly one readVariables call');
      expect(fakeClient.readCalls.first.length, 1,
          reason: 'scalar batch carries exactly one ref');
      expect(fakeClient.readCalls.first.first.$1.offset, 0);
      expect(detail.structChildren, isNull,
          reason: 'scalar leaf must NOT synthesise structChildren');
      expect(detail.value, isNotNull);
    });

    test('fetchDetail on FB instance returns structChildren with one entry '
        'per member, including a placeholder for VAR_IN_OUT', () async {
      fakeClient = FakeUmasClient(
        sampleTreeWithFb(),
        cannedByOffset: {
          0: TypedVariableValue(
            value: 42.5,
            typeName: 'REAL',
            rawBytes: Uint8List(0),
          ),
          4: TypedVariableValue(
            value: 17.0,
            typeName: 'REAL',
            rawBytes: Uint8List(0),
          ),
          12: TypedVariableValue(
            value: 99,
            typeName: 'UINT',
            rawBytes: Uint8List(0),
          ),
        },
      );
      dataSource = UmasBrowseDataSource(fakeClient);
      await dataSource.fetchRoots();

      final fb = BrowseNode(
        id: 'App.M_F2_RC_01',
        displayName: 'M_F2_RC_01',
        type: BrowseNodeType.folder,
        metadata: const {'path': 'App.M_F2_RC_01'},
      );
      final detail = await dataSource.fetchDetail(fb);

      expect(detail.structChildren, isNotNull,
          reason: 'FB instance must synthesise structChildren');
      expect(detail.structChildren!.length, 4,
          reason: '3 readable + 1 unreadable (VAR_IN_OUT) = 4 entries');

      final byName = {
        for (final c in detail.structChildren!) c.displayName: c,
      };
      expect(byName.keys.toSet(),
          {'i_setpoint', 'q_actual', 'iq_pointer', 'p_count'});

      // Readable entries carry their value via metadata['value'].
      expect(byName['i_setpoint']!.metadata['value'], '42.5');
      expect(byName['q_actual']!.metadata['value'], '17.0');
      expect(byName['p_count']!.metadata['value'], '99');

      // VAR_IN_OUT placeholder: starts with '[not readable:' and
      // contains the reason text.
      final iqValue = byName['iq_pointer']!.metadata['value']!;
      expect(iqValue, startsWith('[not readable:'));
      expect(iqValue, contains('VAR_IN_OUT'));
      expect(
          UmasFbMember.readableFromMetadata(byName['iq_pointer']!.metadata),
          isFalse,
          reason: 'VAR_IN_OUT entry carries fbReadable=false in metadata');

      // Nested members are flattened — p_count came from
      // App.M_F2_RC_01.Nested.p_count.
      expect(byName['p_count']!.id, 'App.M_F2_RC_01.Nested.p_count');
    });

    test('fetchDetail on FB instance issues a single batched readVariables '
        'call covering only the readable members', () async {
      fakeClient = FakeUmasClient(
        sampleTreeWithFb(),
        cannedByOffset: {
          0: TypedVariableValue(
            value: 42.5,
            typeName: 'REAL',
            rawBytes: Uint8List(0),
          ),
          4: TypedVariableValue(
            value: 17.0,
            typeName: 'REAL',
            rawBytes: Uint8List(0),
          ),
          12: TypedVariableValue(
            value: 99,
            typeName: 'UINT',
            rawBytes: Uint8List(0),
          ),
        },
      );
      dataSource = UmasBrowseDataSource(fakeClient);
      await dataSource.fetchRoots();

      final fb = BrowseNode(
        id: 'App.M_F2_RC_01',
        displayName: 'M_F2_RC_01',
        type: BrowseNodeType.folder,
        metadata: const {'path': 'App.M_F2_RC_01'},
      );
      await dataSource.fetchDetail(fb);

      expect(fakeClient.readCalls.length, 1,
          reason: 'FB fan-out must collapse into ONE TCP round-trip');
      final batched = fakeClient.readCalls.single;
      expect(batched.length, 3,
          reason: 'exactly the 3 readable members (iq_pointer skipped)');
      final offsets = batched.map((p) => p.$1.offset).toSet();
      expect(offsets, {0, 4, 12},
          reason: 'no VAR_IN_OUT offset 8 in the read');
      expect(offsets.length, batched.length,
          reason: 'no member requested more than once');
    });

    test('fetchDetail on FB instance returns a truncated brace-wrapped '
        'value summary', () async {
      // Build a tree with 8 readable members to exercise the
      // truncation path (>6 readable → "... (N fields)").
      final manyMembers = <UmasVariableTreeNode>[];
      final canned = <int, TypedVariableValue>{};
      for (int i = 0; i < 8; i++) {
        final off = i * 4;
        manyMembers.add(UmasVariableTreeNode(
          name: 'm$i',
          path: 'App.WIDE_FB.m$i',
          variable: UmasVariable(
            name: 'App.WIDE_FB.m$i',
            blockNo: 200,
            offset: off,
            dataTypeId: 8,
          ),
          dataType: const UmasDataTypeRef(id: 8, name: 'REAL', byteSize: 4),
          direction: UmasFbMemberDirection.input,
        ));
        canned[off] = TypedVariableValue(
          value: i,
          typeName: 'REAL',
          rawBytes: Uint8List(0),
        );
      }
      final wideTree = [
        UmasVariableTreeNode(
          name: 'App',
          path: 'App',
          children: [
            UmasVariableTreeNode(
              name: 'WIDE_FB',
              path: 'App.WIDE_FB',
              children: manyMembers,
            ),
          ],
        ),
      ];
      fakeClient = FakeUmasClient(wideTree, cannedByOffset: canned);
      dataSource = UmasBrowseDataSource(fakeClient);
      await dataSource.fetchRoots();

      final fb = BrowseNode(
        id: 'App.WIDE_FB',
        displayName: 'WIDE_FB',
        type: BrowseNodeType.folder,
        metadata: const {'path': 'App.WIDE_FB'},
      );
      final detail = await dataSource.fetchDetail(fb);

      expect(detail.value, isNotNull,
          reason: 'FB summary value must be populated, not null');
      expect(detail.value, startsWith('{'),
          reason: 'value summary must be brace-wrapped');
      expect(detail.value, endsWith('}'));
      expect(detail.value, contains('8 fields'),
          reason: 'truncation marker must surface the total field count');

      // Also check the small-FB non-truncated branch via the regular
      // M_F2_RC_01 tree.
      fakeClient = FakeUmasClient(
        sampleTreeWithFb(),
        cannedByOffset: {
          0: TypedVariableValue(
            value: 42.5,
            typeName: 'REAL',
            rawBytes: Uint8List(0),
          ),
          4: TypedVariableValue(
            value: 17.0,
            typeName: 'REAL',
            rawBytes: Uint8List(0),
          ),
          12: TypedVariableValue(
            value: 99,
            typeName: 'UINT',
            rawBytes: Uint8List(0),
          ),
        },
      );
      dataSource = UmasBrowseDataSource(fakeClient);
      await dataSource.fetchRoots();
      final smallFb = BrowseNode(
        id: 'App.M_F2_RC_01',
        displayName: 'M_F2_RC_01',
        type: BrowseNodeType.folder,
        metadata: const {'path': 'App.M_F2_RC_01'},
      );
      final smallDetail = await dataSource.fetchDetail(smallFb);
      expect(smallDetail.value, contains('i_setpoint: 42.5'));
      expect(smallDetail.value, contains('q_actual: 17.0'));
      expect(smallDetail.value, contains('p_count: 99'));
      expect(smallDetail.value, contains('iq_pointer: [n/r]'),
          reason: 'unreadable member surfaces as [n/r] in the preview');
    });

    test('fetchDetail on FB instance with production tree shape '
        '(variable + dataType + non-empty children) routes through the FB '
        'branch, not the scalar branch', () async {
      // Regression for the val [] bug: the live M580 returns FB instances
      // with the instance-level `variable` populated (the FB lives at a
      // memory address) AND non-empty children. `_toBrowseNode` therefore
      // emits BrowseNodeType.variable with blockNo + dataTypeId metadata.
      // The pre-fix scalar branch matched first and read the FB as a
      // primitive, producing `val []` in the UI. The earlier FB tests
      // didn't catch it because their FB instance node had `variable ==
      // null`, so the BrowseNode came back as BrowseNodeType.folder.
      fakeClient = FakeUmasClient(
        sampleTreeWithProductionShapeFb(),
        cannedByOffset: {
          0: TypedVariableValue(
            value: 42.5,
            typeName: 'REAL',
            rawBytes: Uint8List(0),
          ),
          4: TypedVariableValue(
            value: 17.0,
            typeName: 'REAL',
            rawBytes: Uint8List(0),
          ),
        },
      );
      dataSource = UmasBrowseDataSource(fakeClient);
      await dataSource.fetchRoots();

      // BrowseNode shaped exactly as `_toBrowseNode` would emit for the
      // production-shape FB instance: variable type, with FB-level
      // blockNo + dataTypeId metadata.
      final fb = BrowseNode(
        id: 'App.M_F2_RC_01',
        displayName: 'M_F2_RC_01',
        type: BrowseNodeType.variable,
        dataType: 'F2_RC_TYPE',
        metadata: const {
          'path': 'App.M_F2_RC_01',
          'blockNo': '178',
          'offset': '0',
          'dataTypeId': '178',
          'dataTypeName': 'F2_RC_TYPE',
          'byteSize': '16',
        },
      );
      final detail = await dataSource.fetchDetail(fb);

      expect(detail.structChildren, isNotNull,
          reason:
              'FB instance with production shape must reach the FB branch '
              'and synthesise structChildren, not be read as a primitive');
      expect(detail.structChildren!.length, 2,
          reason: 'two readable members on this FB');
      expect(detail.value, isNotNull);
      expect(detail.value, startsWith('{'),
          reason: 'FB summary must be brace-wrapped, not a single scalar '
              'or "val []"');
      expect(detail.value, contains('i_setpoint: 42.5'));
      expect(detail.value, contains('q_actual: 17.0'));

      // The single batched FB read must cover exactly the members, not
      // the FB instance itself.
      expect(fakeClient.readCalls.length, 1);
      final offsets =
          fakeClient.readCalls.single.map((p) => p.$1.offset).toSet();
      expect(offsets, {0, 4},
          reason: 'reads must target the members, not the FB instance');
    });

    test('fetchDetail on pure-folder tree (no readable leaves anywhere) '
        'does NOT call readVariables and returns no structChildren',
        () async {
      fakeClient = FakeUmasClient(sampleTreePureFolders());
      dataSource = UmasBrowseDataSource(fakeClient);
      await dataSource.fetchRoots();

      final folder = BrowseNode(
        id: 'App.EmptyA',
        displayName: 'EmptyA',
        type: BrowseNodeType.folder,
        metadata: const {'path': 'App.EmptyA'},
      );
      final detail = await dataSource.fetchDetail(folder);

      expect(fakeClient.readCalls, isEmpty,
          reason: 'pure folder must not issue any read');
      expect(detail.structChildren, isNull,
          reason: 'pure folder has no synthesised children');
      expect(detail.value, isNull);
      expect(detail.description, 'App.EmptyA');
    });

    // -----------------------------------------------------------------
    // resolvePath — pre-selection support for opening Browse with the
    // current value already selected and tree expanded down to it.
    // -----------------------------------------------------------------

    test('resolvePath returns root→leaf chain for a known dotted path',
        () async {
      fakeClient = FakeUmasClient(sampleTree());
      dataSource = UmasBrowseDataSource(fakeClient);

      final chain = await dataSource.resolvePath('App.GVL.temperature');

      expect(chain, isNotNull);
      expect(chain!.map((n) => n.id).toList(),
          ['App', 'App.GVL', 'App.GVL.temperature'],
          reason: 'chain is ordered root→leaf with each prefix resolved');
      expect(chain.last.displayName, 'temperature');
      expect(chain.last.type, BrowseNodeType.variable);
    });

    test('resolvePath returns null for an unknown path (stale binding)',
        () async {
      fakeClient = FakeUmasClient(sampleTree());
      dataSource = UmasBrowseDataSource(fakeClient);

      final chain = await dataSource.resolvePath('App.Missing.var');

      expect(chain, isNull,
          reason: 'unknown leaf must not produce a chain — caller falls '
              'back to empty-selection state');
    });

    test('resolvePath returns null for empty input', () async {
      fakeClient = FakeUmasClient(sampleTree());
      dataSource = UmasBrowseDataSource(fakeClient);

      expect(await dataSource.resolvePath(''), isNull);
    });
  });

  group('ModbusConfig.umasEnabled serialization', () {
    test('round-trips through JSON with umasEnabled=true', () {
      // Import ModbusConfig from state_man for this test
      // We test via the toJson/fromJson methods
      final config = ModbusConfig(
        host: '10.0.0.1',
        port: 502,
        unitId: 1,
        umasEnabled: true,
      )..serverAlias = 'schneider';

      final json = config.toJson();
      expect(json['umas_enabled'], true);

      final restored = ModbusConfig.fromJson(json);
      expect(restored.umasEnabled, true);
      expect(restored.host, '10.0.0.1');
      expect(restored.serverAlias, 'schneider');
    });

    test('defaults to false when umas_enabled absent from JSON', () {
      final json = {
        'host': '10.0.0.1',
        'port': 502,
        'unit_id': 1,
        'server_alias': 'plc_1',
        'poll_groups': [],
      };

      final config = ModbusConfig.fromJson(json);
      expect(config.umasEnabled, false);
    });
  });
}
