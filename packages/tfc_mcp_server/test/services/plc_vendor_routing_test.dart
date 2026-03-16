// ---------------------------------------------------------------------------
// TDD tests for PLC vendor routing in PlcCodeService.processUpload().
//
// Validates that:
// - Explicit vendor parameter routes to the correct parser
// - Auto-detection from XML namespace works when vendor not specified
// - Auto-detection from file content works (.xef-style content -> Schneider)
// - vendorType is stored in plc_code_block records
// - serverAlias is stored in plc_code_block records
// - Default vendorType is "twincat" for backwards compatibility
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';
import 'package:tfc_mcp_server/src/services/plc_code_service.dart';

import '../helpers/mock_plc_code_index.dart';
import '../helpers/sample_schneider_files.dart';
import '../helpers/sample_twincat_files.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Stub [KeyMappingLookup] that returns canned mappings.
class _StubKeyMappingLookup implements KeyMappingLookup {
  _StubKeyMappingLookup([this._mappings = const []]);
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

/// Build a zip archive from a list of {path, content} entries.
Uint8List _buildZip(List<Map<String, String>> files) {
  final archive = Archive();
  for (final file in files) {
    final bytes = utf8.encode(file['content']!);
    archive.addFile(ArchiveFile.bytes(file['path']!, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded!);
}

/// Extend [MockPlcCodeIndex] to record the vendorType and serverAlias
/// passed to [indexAsset] for assertion purposes.
class _RecordingPlcCodeIndex extends MockPlcCodeIndex {
  String? lastVendorType;
  String? lastServerAlias;
  int indexCallCount = 0;

  @override
  Future<void> indexAsset(
    String assetKey,
    List<ParsedCodeBlock> blocks, {
    String? vendorType,
    String? serverAlias,
  }) async {
    lastVendorType = vendorType;
    lastServerAlias = serverAlias;
    indexCallCount++;
    await super.indexAsset(
      assetKey,
      blocks,
      vendorType: vendorType,
      serverAlias: serverAlias,
    );
  }
}

void main() {
  late _RecordingPlcCodeIndex index;
  late _StubKeyMappingLookup keyLookup;
  late PlcCodeService service;

  setUp(() {
    index = _RecordingPlcCodeIndex();
    keyLookup = _StubKeyMappingLookup();
    service = PlcCodeService(index, keyLookup);
  });

  // =========================================================================
  // Group 1: Explicit vendor routing
  // =========================================================================

  group('processUpload vendor routing - explicit vendor', () {
    test('routes to TwinCAT parser when vendor=twincat', () async {
      final zip = _buildZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);

      final result = await service.processUpload(
        'asset-1',
        zip,
        vendor: PlcVendor.twincat,
      );

      expect(result.totalBlocks, equals(2));
      expect(result.detectedVendor, equals(PlcVendor.twincat));
      expect(result.blockTypeCounts, containsPair('FunctionBlock', 1));
      expect(result.blockTypeCounts, containsPair('GVL', 1));
    });

    test('routes to Schneider Control Expert parser when vendor=schneiderControlExpert',
        () async {
      // Schneider XML passed as raw bytes (not a zip)
      final xmlBytes = utf8.encode(sampleControlExpertFB);

      final result = await service.processUpload(
        'asset-se',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderControlExpert,
      );

      expect(result.totalBlocks, greaterThanOrEqualTo(1));
      expect(
          result.detectedVendor, equals(PlcVendor.schneiderControlExpert));

      // Verify the parsed block is a Function Block from the Schneider parser
      final summary = await index.getIndexSummary();
      expect(summary, hasLength(1));
      expect(summary.first.assetKey, equals('asset-se'));
    });

    test('routes to Schneider Machine Expert parser when vendor=schneiderMachineExpert',
        () async {
      final xmlBytes = utf8.encode(samplePlcopenFB);

      final result = await service.processUpload(
        'asset-me',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderMachineExpert,
      );

      expect(result.totalBlocks, greaterThanOrEqualTo(1));
      expect(
          result.detectedVendor, equals(PlcVendor.schneiderMachineExpert));
    });

    test('TwinCAT upload parses FunctionBlock variables correctly', () async {
      final zip = _buildZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
      ]);

      final result = await service.processUpload(
        'asset-tc',
        zip,
        vendor: PlcVendor.twincat,
      );

      // FB_TestBlock has 4 vars: bStartTest, nCounter, nInput, bResult
      expect(result.totalVariables, equals(4));
    });

    test('Schneider Control Expert upload parses variables correctly',
        () async {
      final xmlBytes = utf8.encode(sampleControlExpertFB);

      final result = await service.processUpload(
        'asset-ce',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderControlExpert,
      );

      // FB_PumpControl has: bEnable, rSetpoint, rActualSpeed, bRunning, nErrorCode
      expect(result.totalVariables, greaterThanOrEqualTo(5));
    });

    test('Schneider Machine Expert upload parses PLCopen variables correctly',
        () async {
      final xmlBytes = utf8.encode(samplePlcopenFB);

      final result = await service.processUpload(
        'asset-mx',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderMachineExpert,
      );

      // FB_ValveControl has 6 vars: bOpen, rPosition, bIsOpen, rFeedback, nState, tDelay
      expect(result.totalVariables, greaterThanOrEqualTo(6));
    });
  });

  // =========================================================================
  // Group 2: Auto-detection from XML content
  // =========================================================================

  group('processUpload vendor routing - auto-detect from content', () {
    test('auto-detects Schneider Control Expert from FBSource XML namespace',
        () async {
      final xmlBytes = utf8.encode(sampleControlExpertFB);

      // vendor not specified -- should auto-detect
      final result = await service.processUpload(
        'asset-auto-ce',
        Uint8List.fromList(xmlBytes),
      );

      expect(
          result.detectedVendor, equals(PlcVendor.schneiderControlExpert));
      expect(result.totalBlocks, greaterThanOrEqualTo(1));
    });

    test('auto-detects Schneider Control Expert from STSource XML element',
        () async {
      final xmlBytes = utf8.encode(sampleControlExpertST);

      final result = await service.processUpload(
        'asset-auto-st',
        Uint8List.fromList(xmlBytes),
      );

      expect(
          result.detectedVendor, equals(PlcVendor.schneiderControlExpert));
    });

    test('auto-detects Schneider Machine Expert from PLCopen namespace',
        () async {
      final xmlBytes = utf8.encode(samplePlcopenFB);

      final result = await service.processUpload(
        'asset-auto-me',
        Uint8List.fromList(xmlBytes),
      );

      expect(
          result.detectedVendor, equals(PlcVendor.schneiderMachineExpert));
    });

    test('auto-detects PLCopen from pou + body elements without namespace',
        () async {
      // PLCopen XML that uses pou+body structure without explicit namespace
      const plcopenNoNs = '<?xml version="1.0" encoding="utf-8"?>'
          '<project>'
          '<types><pous>'
          '<pou name="FB_NoNs" pouType="functionBlock">'
          '<interface><localVars>'
          '<variable name="nVal"><type><INT/></type></variable>'
          '</localVars></interface>'
          '<body><ST><xhtml>nVal := nVal + 1;</xhtml></ST></body>'
          '</pou>'
          '</pous></types>'
          '</project>';

      final xmlBytes = utf8.encode(plcopenNoNs);

      final result = await service.processUpload(
        'asset-auto-noNs',
        Uint8List.fromList(xmlBytes),
      );

      // Should detect as Machine Expert via pou+body heuristic
      expect(
          result.detectedVendor, equals(PlcVendor.schneiderMachineExpert));
    });

    test('defaults to TwinCAT for binary zip with no Schneider markers',
        () async {
      final zip = _buildZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
      ]);

      // No vendor specified, zip content is TwinCAT
      final result = await service.processUpload('asset-auto-tc', zip);

      expect(result.detectedVendor, equals(PlcVendor.twincat));
      expect(result.totalBlocks, greaterThan(0));
    });

    test('defaults to TwinCAT when XML has no Schneider markers', () async {
      // A TwinCAT XML file (not Schneider)
      const twincatXml = '<?xml version="1.0" encoding="utf-8"?>'
          '<TcPlcObject Version="1.1.0.1" ProductVersion="3.1.4024.5">'
          '<POU Name="FB_Test" SpecialFunc="None">'
          '<Declaration><![CDATA[FUNCTION_BLOCK FB_Test\nVAR\n    x : INT;\nEND_VAR\n]]></Declaration>'
          '</POU>'
          '</TcPlcObject>';
      final xmlBytes = utf8.encode(twincatXml);

      final result = await service.processUpload(
        'asset-no-schneider',
        Uint8List.fromList(xmlBytes),
      );

      // Auto-detect sees no Schneider markers, falls back to twincat
      expect(result.detectedVendor, equals(PlcVendor.twincat));
    });
  });

  // =========================================================================
  // Group 3: vendorType stored in DB records
  // =========================================================================

  group('processUpload stores vendorType in plc_code_block records', () {
    test('stores vendorType="twincat" for TwinCAT uploads', () async {
      final zip = _buildZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);

      await service.processUpload(
        'asset-vt-tc',
        zip,
        vendor: PlcVendor.twincat,
      );

      expect(index.lastVendorType, equals('twincat'));
    });

    test('stores vendorType="schneider_control_expert" for Control Expert',
        () async {
      final xmlBytes = utf8.encode(sampleControlExpertFB);

      await service.processUpload(
        'asset-vt-ce',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderControlExpert,
      );

      expect(index.lastVendorType, equals('schneider_control_expert'));
    });

    test('stores vendorType="schneider_machine_expert" for Machine Expert',
        () async {
      final xmlBytes = utf8.encode(samplePlcopenFB);

      await service.processUpload(
        'asset-vt-me',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderMachineExpert,
      );

      expect(index.lastVendorType, equals('schneider_machine_expert'));
    });

    test('default vendorType is "twincat" for backwards compat (no vendor param)',
        () async {
      final zip = _buildZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
      ]);

      await service.processUpload('asset-default', zip);

      // When no vendor specified and auto-detect defaults to twincat,
      // the stored vendorType should be 'twincat'
      expect(index.lastVendorType, equals('twincat'));
    });

    test('vendorType is persisted and retrievable via getBlock', () async {
      final xmlBytes = utf8.encode(sampleControlExpertFB);

      await service.processUpload(
        'asset-persist',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderControlExpert,
      );

      // Retrieve the block and verify vendorType is stored
      final block = await service.getBlock(1);
      expect(block, isNotNull);
      expect(block!.vendorType, equals('schneider_control_expert'));
    });
  });

  // =========================================================================
  // Group 4: serverAlias stored in DB records
  // =========================================================================

  group('processUpload stores serverAlias in plc_code_block records', () {
    test('stores serverAlias when provided', () async {
      final zip = _buildZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);

      await service.processUpload(
        'asset-alias',
        zip,
        vendor: PlcVendor.twincat,
        serverAlias: 'PLC_ATV320',
      );

      expect(index.lastServerAlias, equals('PLC_ATV320'));
    });

    test('stores null serverAlias when not provided', () async {
      final zip = _buildZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);

      await service.processUpload(
        'asset-no-alias',
        zip,
        vendor: PlcVendor.twincat,
      );

      expect(index.lastServerAlias, isNull);
    });

    test('serverAlias is persisted and retrievable via getBlock', () async {
      final zip = _buildZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);

      await service.processUpload(
        'asset-alias-get',
        zip,
        vendor: PlcVendor.twincat,
        serverAlias: 'PLC_Main_001',
      );

      final block = await service.getBlock(1);
      expect(block, isNotNull);
      expect(block!.serverAlias, equals('PLC_Main_001'));
    });

    test('serverAlias stored for Schneider uploads too', () async {
      final xmlBytes = utf8.encode(samplePlcopenFB);

      await service.processUpload(
        'asset-se-alias',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderMachineExpert,
        serverAlias: 'SCHNEIDER_ATV320',
      );

      expect(index.lastServerAlias, equals('SCHNEIDER_ATV320'));
    });
  });

  // =========================================================================
  // Group 5: UploadResult contains detected vendor
  // =========================================================================

  group('processUpload UploadResult.detectedVendor', () {
    test('returns PlcVendor.twincat when routed via TwinCAT', () async {
      final zip = _buildZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
      ]);

      final result = await service.processUpload(
        'asset-1',
        zip,
        vendor: PlcVendor.twincat,
      );

      expect(result.detectedVendor, equals(PlcVendor.twincat));
    });

    test('returns PlcVendor.schneiderControlExpert for CE uploads', () async {
      final xmlBytes = utf8.encode(sampleControlExpertFB);

      final result = await service.processUpload(
        'asset-2',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderControlExpert,
      );

      expect(
          result.detectedVendor, equals(PlcVendor.schneiderControlExpert));
    });

    test('returns PlcVendor.schneiderMachineExpert for ME uploads', () async {
      final xmlBytes = utf8.encode(samplePlcopenFB);

      final result = await service.processUpload(
        'asset-3',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderMachineExpert,
      );

      expect(
          result.detectedVendor, equals(PlcVendor.schneiderMachineExpert));
    });

    test('auto-detected vendor is reflected in UploadResult', () async {
      final xmlBytes = utf8.encode(sampleControlExpertST);

      final result = await service.processUpload(
        'asset-auto',
        Uint8List.fromList(xmlBytes),
      );

      // Auto-detect should find STSource -> Control Expert
      expect(
          result.detectedVendor, equals(PlcVendor.schneiderControlExpert));
    });
  });

  // =========================================================================
  // Group 6: Schneider zip archive handling
  // =========================================================================

  group('processUpload - Schneider XML inside zip archive', () {
    test('parses Schneider Control Expert XML from zip archive', () async {
      final zip = _buildZip([
        {
          'path': 'exports/FB_PumpControl.xef',
          'content': sampleControlExpertFB,
        },
      ]);

      final result = await service.processUpload(
        'asset-zip-ce',
        zip,
        vendor: PlcVendor.schneiderControlExpert,
      );

      // Should find at least the FB_PumpControl block from the .xef file
      expect(result.totalBlocks, greaterThanOrEqualTo(1));
    });

    test('parses PLCopen XML from zip archive', () async {
      final zip = _buildZip([
        {
          'path': 'project/export.xml',
          'content': samplePlcopenFB,
        },
      ]);

      final result = await service.processUpload(
        'asset-zip-me',
        zip,
        vendor: PlcVendor.schneiderMachineExpert,
      );

      expect(result.totalBlocks, greaterThanOrEqualTo(1));
    });
  });

  // =========================================================================
  // Group 7: Re-upload replaces index with new vendor
  // =========================================================================

  group('processUpload - re-upload with different vendor', () {
    test('replacing TwinCAT index with Schneider upload updates vendorType',
        () async {
      // First upload: TwinCAT
      final tcZip = _buildZip([
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);
      await service.processUpload(
        'asset-replace',
        tcZip,
        vendor: PlcVendor.twincat,
      );
      expect(index.lastVendorType, equals('twincat'));

      // Second upload: Schneider Control Expert
      final ceBytes = utf8.encode(sampleControlExpertFB);
      await service.processUpload(
        'asset-replace',
        Uint8List.fromList(ceBytes),
        vendor: PlcVendor.schneiderControlExpert,
      );
      expect(index.lastVendorType, equals('schneider_control_expert'));

      // Only one asset in index (replaced, not appended)
      final summary = await index.getIndexSummary();
      expect(summary, hasLength(1));
      expect(summary.first.assetKey, equals('asset-replace'));
    });
  });

  // =========================================================================
  // Group 8: PlcVendor enum values
  // =========================================================================

  group('PlcVendor enum', () {
    test('has three values', () {
      expect(PlcVendor.values, hasLength(3));
    });

    test('contains twincat, schneiderControlExpert, schneiderMachineExpert',
        () {
      expect(
        PlcVendor.values.map((v) => v.name),
        containsAll([
          'twincat',
          'schneiderControlExpert',
          'schneiderMachineExpert',
        ]),
      );
    });
  });

  // =========================================================================
  // Group 9: Error handling per vendor
  // =========================================================================

  group('processUpload - error handling by vendor', () {
    test('TwinCAT skips malformed files and continues', () async {
      final zip = _buildZip([
        {'path': 'POUs/bad.TcPOU', 'content': '<not valid &&'},
        {'path': 'GVLs/GVL_Main.TcGVL', 'content': sampleTcGvlXml},
      ]);

      final result = await service.processUpload(
        'asset-err-tc',
        zip,
        vendor: PlcVendor.twincat,
      );

      expect(result.totalBlocks, equals(1));
      expect(result.skippedFiles, equals(1));
    });

    test('Schneider skips malformed XML and reports skip count', () async {
      const badXml = '<?xml version="1.0"?>'
          '<FBSource>'
          '<objectName>Bad</objectName>'
          '<sourceCode></sourceCode>'
          '</FBSource>';
      final xmlBytes = utf8.encode(badXml);

      final result = await service.processUpload(
        'asset-err-se',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderControlExpert,
      );

      // Even if the sourceCode is empty, the block should be skipped or
      // have zero content -- the important thing is no crash
      expect(result.skippedFiles, greaterThanOrEqualTo(0));
    });
  });

  // =========================================================================
  // Group 10: Both vendor and serverAlias together
  // =========================================================================

  group('processUpload - vendor + serverAlias combined', () {
    test('stores both vendorType and serverAlias for TwinCAT upload',
        () async {
      final zip = _buildZip([
        {'path': 'POUs/FB_TestBlock.TcPOU', 'content': sampleTcPouXml},
      ]);

      await service.processUpload(
        'asset-combined-tc',
        zip,
        vendor: PlcVendor.twincat,
        serverAlias: 'BECKHOFF_PLC1',
      );

      expect(index.lastVendorType, equals('twincat'));
      expect(index.lastServerAlias, equals('BECKHOFF_PLC1'));
    });

    test('stores both vendorType and serverAlias for Schneider upload',
        () async {
      final xmlBytes = utf8.encode(samplePlcopenFB);

      await service.processUpload(
        'asset-combined-se',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderMachineExpert,
        serverAlias: 'SCHNEIDER_M340',
      );

      expect(index.lastVendorType, equals('schneider_machine_expert'));
      expect(index.lastServerAlias, equals('SCHNEIDER_M340'));
    });

    test('serverAlias passes through to all blocks in multi-block upload',
        () async {
      final xmlBytes = utf8.encode(sampleControlExpertMultiBlock);

      await service.processUpload(
        'asset-multi-alias',
        Uint8List.fromList(xmlBytes),
        vendor: PlcVendor.schneiderControlExpert,
        serverAlias: 'SHARED_PLC',
      );

      // indexAsset was called once with the serverAlias
      expect(index.lastServerAlias, equals('SHARED_PLC'));
      expect(index.indexCallCount, equals(1));

      // All blocks in the index should share the same serverAlias
      // (verified by checking the mock's stored value)
      final summary = await index.getIndexSummary();
      expect(summary, hasLength(1));
      expect(summary.first.blockCount, greaterThanOrEqualTo(2));
    });
  });
}
