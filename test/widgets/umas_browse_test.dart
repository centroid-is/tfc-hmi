import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:tfc_dart/core/state_man.dart' show ModbusConfig;
import 'package:tfc/widgets/umas_browse.dart';
import 'package:tfc/widgets/browse_panel.dart';

/// Fake UmasClient that returns canned tree data for testing.
class FakeUmasClient extends UmasClient {
  final List<UmasVariableTreeNode> _tree;

  FakeUmasClient(this._tree) : super(sendFn: (_) => throw UnimplementedError());

  @override
  Future<List<UmasVariableTreeNode>> browse() async => _tree;
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
