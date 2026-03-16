import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';
import 'package:tfc_mcp_server/src/services/plc_code_service.dart';

import '../helpers/mock_plc_code_index.dart';
import '../helpers/sample_twincat_files.dart';

// ---------------------------------------------------------------------------
// Stub ConfigService that returns canned key mappings.
// ---------------------------------------------------------------------------
class StubConfigService implements KeyMappingLookup {
  StubConfigService([this._mappings = const []]);

  final List<Map<String, dynamic>> _mappings;

  @override
  Future<List<Map<String, dynamic>>> listKeyMappings({
    String? filter,
    int limit = 50,
  }) async {
    if (filter == null || filter.isEmpty) {
      return _mappings.take(limit).toList();
    }
    final q = filter.toLowerCase();
    return _mappings
        .where((m) => (m['key'] as String).toLowerCase().contains(q))
        .take(limit)
        .toList();
  }
}

/// Build a zip archive containing the given files.
/// Each entry is {path: String, content: String}.
Uint8List buildTestZip(List<Map<String, String>> files) {
  final archive = Archive();
  for (final file in files) {
    final bytes = utf8.encode(file['content']!);
    archive.addFile(ArchiveFile.bytes(file['path']!, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded!);
}

void main() {
  late MockPlcCodeIndex index;
  late StubConfigService configService;
  late PlcCodeService service;

  setUp(() {
    index = MockPlcCodeIndex();
  });

  group('processUpload', () {
    test('stores parsed blocks from zip containing TcPOU and TcGVL', () async {
      configService = StubConfigService();
      service = PlcCodeService(index, configService);

      final zip = buildTestZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);

      final result = await service.processUpload('asset-1', zip);

      // Should have stored 2 blocks (1 POU + 1 GVL)
      expect(result.totalBlocks, equals(2));
      expect(index.isEmpty, isFalse);

      // Verify index has blocks via summary
      final summary = await index.getIndexSummary();
      expect(summary, hasLength(1));
      expect(summary.first.assetKey, equals('asset-1'));
    });

    test('returns UploadResult with block counts by type and variable count',
        () async {
      configService = StubConfigService();
      service = PlcCodeService(index, configService);

      final zip = buildTestZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);

      final result = await service.processUpload('asset-1', zip);

      expect(result.blockTypeCounts, containsPair('FunctionBlock', 1));
      expect(result.blockTypeCounts, containsPair('GVL', 1));
      // FB_TestBlock has 4 vars, GVL_Main has 3 vars = 7 total
      expect(result.totalVariables, equals(7));
    });

    test('replaces existing index on re-upload (calls deleteAssetIndex)',
        () async {
      configService = StubConfigService();
      service = PlcCodeService(index, configService);

      final zip1 = buildTestZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
      ]);
      final zip2 = buildTestZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);

      // Upload first time
      await service.processUpload('asset-1', zip1);
      final summary1 = await index.getIndexSummary();
      expect(summary1.first.blockCount, greaterThan(0));

      // Upload second time for same asset -- should replace
      final result2 = await service.processUpload('asset-1', zip2);
      expect(result2.totalBlocks, equals(1));
      expect(result2.blockTypeCounts, containsPair('GVL', 1));
      expect(result2.blockTypeCounts.containsKey('FunctionBlock'), isFalse);
    });

    test('skips files that fail to parse and continues with valid files',
        () async {
      configService = StubConfigService();
      service = PlcCodeService(index, configService);

      final zip = buildTestZip([
        {
          'path': 'POUs/broken.TcPOU',
          'content': '<not valid xml at all &&&',
        },
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);

      final result = await service.processUpload('asset-1', zip);
      expect(result.totalBlocks, equals(1));
      expect(result.skippedFiles, equals(1));
    });

    test('empty zip returns UploadResult with zero counts', () async {
      configService = StubConfigService();
      service = PlcCodeService(index, configService);

      // Zip with no TcPOU/TcGVL/st files
      final zip = buildTestZip([
        {'path': 'README.md', 'content': 'Hello'},
      ]);
      // This zip has no relevant files -- extractTwinCatFiles returns empty
      // but our service should handle that gracefully.
      // Actually extractTwinCatFiles just filters by extension, so README.md won't be included.
      // Let's use a completely empty zip.
      final emptyZip = Uint8List.fromList(ZipEncoder().encode(Archive())!);

      final result = await service.processUpload('asset-1', emptyZip);
      expect(result.totalBlocks, equals(0));
      expect(result.totalVariables, equals(0));
      expect(result.skippedFiles, equals(0));
    });
  });

  group('search', () {
    setUp(() async {
      configService = StubConfigService();
      service = PlcCodeService(index, configService);

      // Index some data for search tests
      final zip = buildTestZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);
      await service.processUpload('asset-1', zip);
    });

    test('delegates to PlcCodeIndex.search() with mode, assetFilter, and limit',
        () async {
      final results = await service.search(
        'pump3_speed',
        mode: 'variable',
        assetFilter: 'asset-1',
        limit: 5,
      );

      // Should find pump3_speed in GVL_Main
      expect(results, isNotEmpty);
      expect(results.first.variableName, equals('pump3_speed'));
    });

    test('mode=text searches code body and comments', () async {
      // Index block with comments
      final zip2 = buildTestZip([
        {
          'path': 'POUs/FB_WithComments.TcPOU',
          'content': sampleTcPouWithCommentsXml,
        },
      ]);
      await service.processUpload('asset-2', zip2);

      final results = await service.search('motor speed', mode: 'text');
      expect(results, isNotEmpty);
    });

    test('mode=variable searches variable names', () async {
      final results = await service.search('pump3', mode: 'variable');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.variableName == 'pump3_speed'),
        isTrue,
      );
    });

    test('mode=key with MAIN prefix matches qualifiedName without prefix',
        () async {
      // qualifiedName stored as "GVL_Main.pump3_speed" (2 segments)
      // query is "MAIN.GVL_Main.pump3_speed" (3 segments with program prefix)
      final results = await index.search(
        'MAIN.GVL_Main.pump3_speed',
        mode: 'key',
      );
      expect(results, isNotEmpty);
      expect(results.first.variableName, equals('pump3_speed'));
    });

    test('mode=key with exact qualifiedName still matches', () async {
      // query matches stored qualifiedName exactly
      final results = await index.search(
        'GVL_Main.pump3_speed',
        mode: 'key',
      );
      expect(results, isNotEmpty);
      expect(results.first.variableName, equals('pump3_speed'));
    });

    test('mode=key with unrelated prefix does not match', () async {
      // query has a prefix that doesn't end with the qualifiedName
      final results = await index.search(
        'OTHER.pump3_speed',
        mode: 'key',
      );
      // "OTHER.pump3_speed" does not end with "GVL_Main.pump3_speed"
      // and is not equal — should not match
      expect(results, isEmpty);
    });
  });

  group('searchByKey', () {
    test(
        'looks up key mapping, extracts PLC variable path from s= identifier, searches index',
        () async {
      // Index GVL_Main which has pump3_speed
      final zip = buildTestZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);
      configService = StubConfigService([
        {
          'key': 'pump3.speed',
          'namespace': 4,
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
        },
      ]);
      service = PlcCodeService(index, configService);
      await service.processUpload('asset-1', zip);

      final results = await service.searchByKey('pump3.speed');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.variableName == 'pump3_speed'),
        isTrue,
      );
    });

    test('numeric OPC UA identifier (i=) returns empty list', () async {
      configService = StubConfigService([
        {
          'key': 'numeric.tag',
          'namespace': 2,
          'identifier': 'ns=2;i=847',
        },
      ]);
      service = PlcCodeService(index, configService);

      final results = await service.searchByKey('numeric.tag');
      expect(results, isEmpty);
    });

    test('returns fuzzy matches when exact match not found', () async {
      final zip = buildTestZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);
      configService = StubConfigService([
        {
          'key': 'pump3.spd',
          'namespace': 4,
          'identifier': 'ns=4;s=GVL_Main.pump3_spd',
        },
      ]);
      service = PlcCodeService(index, configService);
      await service.processUpload('asset-1', zip);

      // pump3_spd doesn't exactly match but fuzzy should find pump3_speed
      final results = await service.searchByKey('pump3.spd');
      // The fuzzy search on variable mode should pick up pump3_speed
      expect(results, isNotEmpty);
    });

    test('key not in key mappings returns empty list', () async {
      configService = StubConfigService([]); // No mappings
      service = PlcCodeService(index, configService);

      final results = await service.searchByKey('nonexistent.key');
      expect(results, isEmpty);
    });

    test('plain identifier (no ns=/s= prefix) searches index correctly',
        () async {
      // Index GVL_Main which has pump3_speed
      final zip = buildTestZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);
      configService = StubConfigService([
        {
          'key': 'pump3.speed',
          'namespace': 4,
          'identifier': 'GVL_Main.pump3_speed', // plain, no prefix
        },
      ]);
      service = PlcCodeService(index, configService);
      await service.processUpload('asset-1', zip);

      final results = await service.searchByKey('pump3.speed');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.variableName == 'pump3_speed'),
        isTrue,
      );
    });

    test(
        'MAIN-prefixed OPC-UA path matches stored qualifiedName without MAIN prefix',
        () async {
      // Index GVL_Main which stores qualifiedName as "GVL_Main.pump3_speed"
      // (2 segments). OPC-UA identifier has 3 segments with MAIN. prefix.
      final zip = buildTestZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);
      configService = StubConfigService([
        {
          'key': 'pump3.speed',
          'namespace': 4,
          'identifier': 'ns=4;s=MAIN.GVL_Main.pump3_speed',
        },
      ]);
      service = PlcCodeService(index, configService);
      await service.processUpload('asset-1', zip);

      final results = await service.searchByKey('pump3.speed');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.variableName == 'pump3_speed'),
        isTrue,
      );
    });

    test(
        'variable fallback uses last segment when key mode finds no match',
        () async {
      // Index FB_TestBlock which has variable "nCounter"
      // OPC-UA path is "MAIN.FB_TestBlock.nCounter" -- key mode matches
      // qualifiedName "FB_TestBlock.nCounter" via suffix. But if the
      // qualifiedName were stored differently, the variable fallback
      // should still find "nCounter" by extracting the last segment.
      final zip = buildTestZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
      ]);
      configService = StubConfigService([
        {
          'key': 'test.counter',
          'namespace': 4,
          // identifier that won't match any qualifiedName in key mode
          'identifier': 'ns=4;s=SomeOther.Program.nCounter',
        },
      ]);
      service = PlcCodeService(index, configService);
      await service.processUpload('asset-1', zip);

      // Key mode won't match "SomeOther.Program.nCounter" against
      // qualifiedName "FB_TestBlock.nCounter". Variable fallback should
      // extract "nCounter" (last segment) and fuzzy-match it.
      final results = await service.searchByKey('test.counter');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.variableName == 'nCounter'),
        isTrue,
      );
    });
  });

  group('extractPlcVariablePath', () {
    test('extracts path from ns=N;s=... format', () {
      expect(
        PlcCodeService.extractPlcVariablePath('ns=4;s=GVL_Main.pump3_speed'),
        equals('GVL_Main.pump3_speed'),
      );
    });

    test('extracts path from s=... format (no namespace)', () {
      expect(
        PlcCodeService.extractPlcVariablePath('s=GVL_Main.pump3_speed'),
        equals('GVL_Main.pump3_speed'),
      );
    });

    test('returns null for numeric identifier i=', () {
      expect(
        PlcCodeService.extractPlcVariablePath('ns=2;i=847'),
        isNull,
      );
    });

    test('returns plain identifier as-is when no prefix present', () {
      expect(
        PlcCodeService.extractPlcVariablePath('GVL_Main.pump3_speed'),
        equals('GVL_Main.pump3_speed'),
      );
    });

    test('returns simple variable name when no prefix or dots', () {
      expect(
        PlcCodeService.extractPlcVariablePath('pump3_speed'),
        equals('pump3_speed'),
      );
    });
  });

  group('getCorrelatedKeys', () {
    test(
        'returns HMI keys whose OPC UA identifier contains the variable path',
        () async {
      configService = StubConfigService([
        {
          'key': 'pump3.speed',
          'namespace': 4,
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
        },
        {
          'key': 'pump3.running',
          'namespace': 4,
          'identifier': 'ns=4;s=GVL_Main.pump3_running',
        },
        {
          'key': 'tank.level',
          'namespace': 4,
          'identifier': 'ns=4;s=GVL_Main.tank_level',
        },
      ]);
      service = PlcCodeService(index, configService);

      final keys =
          await service.getCorrelatedKeys('GVL_Main.pump3_speed');
      expect(keys, hasLength(1));
      expect(keys.first['key'], equals('pump3.speed'));
    });

    test('variable with no HMI key returns empty list', () async {
      configService = StubConfigService([
        {
          'key': 'pump3.speed',
          'namespace': 4,
          'identifier': 'ns=4;s=GVL_Main.pump3_speed',
        },
      ]);
      service = PlcCodeService(index, configService);

      final keys = await service.getCorrelatedKeys('FB_Motor.someVar');
      expect(keys, isEmpty);
    });

    test('correlates keys with plain identifiers (no ns=/s= prefix)',
        () async {
      configService = StubConfigService([
        {
          'key': 'pump3.speed',
          'namespace': 4,
          'identifier': 'GVL_Main.pump3_speed', // plain, no prefix
        },
        {
          'key': 'tank.level',
          'namespace': 4,
          'identifier': 'GVL_Main.tank_level', // plain, no prefix
        },
      ]);
      service = PlcCodeService(index, configService);

      final keys =
          await service.getCorrelatedKeys('GVL_Main.pump3_speed');
      expect(keys, hasLength(1));
      expect(keys.first['key'], equals('pump3.speed'));
    });
  });

  group('getBlock', () {
    test('delegates to PlcCodeIndex.getBlock()', () async {
      configService = StubConfigService();
      service = PlcCodeService(index, configService);

      final zip = buildTestZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);
      await service.processUpload('asset-1', zip);

      // Block IDs are assigned incrementally, first block is 1
      final block = await service.getBlock(1);
      expect(block, isNotNull);
      expect(block!.blockName, equals('GVL_Main'));
    });
  });

  group('getIndexSummary', () {
    test('delegates to PlcCodeIndex.getIndexSummary()', () async {
      configService = StubConfigService();
      service = PlcCodeService(index, configService);

      final zip = buildTestZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);
      await service.processUpload('asset-1', zip);

      final summaries = await service.getIndexSummary();
      expect(summaries, hasLength(1));
      expect(summaries.first.assetKey, equals('asset-1'));
    });
  });

  group('hasCode', () {
    test('returns false when index is empty', () {
      configService = StubConfigService();
      service = PlcCodeService(index, configService);
      expect(service.hasCode, isFalse);
    });

    test('returns true when indexed', () async {
      configService = StubConfigService();
      service = PlcCodeService(index, configService);

      final zip = buildTestZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);
      await service.processUpload('asset-1', zip);
      expect(service.hasCode, isTrue);
    });
  });
}
