// Encoding of Schneider PLC exports on the way into the index.
//
// This is an Icelandic plant. Block names, variable names and comments in a
// real export contain þ, æ, ö and ð, and the exports come out of Windows
// tooling, so a UTF-8 byte-order mark is the normal case and not an edge one.
//
// One decode was wrong, in the zip half of _processSchneiderUpload:
//
//     final content = String.fromCharCodes(entry.content as List<int>);
//
// That is a Latin-1 read of UTF-8 bytes, so Færiband was indexed as
// FÃ¦riband -- and that is what the MCP tools then serve to the AI. The same
// file uploaded unzipped took utf8.decode and came out right, so the two
// entry points disagreed with each other about the same bytes.
//
// The BOM is a symptom of that one decode, not a second bug. utf8.decode
// strips a leading U+FEFF (strict and allowMalformed alike), so the unzipped
// path was never affected. String.fromCharCodes keeps all three BOM bytes as
// separate characters, XmlDocument.parse throws on them, and the throw was
// swallowed into skippedFiles++ -- an upload that reported success having
// indexed nothing. Fixing the decode fixes the BOM with it; the BOM tests
// below are regression guards, not a separate repair.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';
import 'package:tfc_mcp_server/src/services/plc_code_service.dart';

import '../helpers/mock_plc_code_index.dart';

/// Stub key-mapping lookup; these tests care only about parsing.
class _NoMappings implements KeyMappingLookup {
  @override
  Future<List<Map<String, dynamic>>> listKeyMappings({
    String? filter,
    int limit = 50,
  }) async =>
      const [];
}

/// A Control Expert function block whose identifiers and comments are the
/// kind of thing this plant actually ships.
const String _icelandicFb = '''<?xml version="1.0" encoding="utf-8"?>
<FBSource nameOfFBType="DFB" version="0.04">
  <objectName>FB_Færiband</objectName>
  <variables>
    <variable name="bÞvottur" typeName="BOOL" class="INPUT"/>
    <variable name="rHraði" typeName="REAL" class="INPUT"/>
    <variable name="bKeyrir" typeName="BOOL" class="OUTPUT"/>
  </variables>
  <sourceCode>FUNCTION_BLOCK FB_Færiband
VAR_INPUT
    bÞvottur : BOOL; (* þvottakerfi virkt *)
    rHraði : REAL;
END_VAR
VAR_OUTPUT
    bKeyrir : BOOL;
END_VAR

IF bÞvottur THEN
    bKeyrir := TRUE;
END_IF
END_FUNCTION_BLOCK</sourceCode>
</FBSource>
''';

/// UTF-8 byte-order mark. Windows PLC tooling writes it by default.
const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];

/// Zips one entry, writing [content] as raw UTF-8 with no re-encoding.
Uint8List _zipOne(String path, List<int> bytes) {
  final archive = Archive()..addFile(ArchiveFile.bytes(path, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  late MockPlcCodeIndex index;
  late PlcCodeService service;

  setUp(() {
    index = MockPlcCodeIndex();
    service = PlcCodeService(index, _NoMappings());
  });

  Future<List<PlcCodeBlock>> upload(Uint8List bytes) async {
    await service.processUpload(
      'asset-is',
      bytes,
      vendor: PlcVendor.schneiderControlExpert,
    );
    return index.getBlocksForAsset('asset-is');
  }

  group('Icelandic identifiers', () {
    // The bug. String.fromCharCodes reads each UTF-8 byte as a code point, so
    // the two bytes of æ (0xC3 0xA6) become "Ã¦".
    test('survive a zipped export', () async {
      final blocks =
          await upload(_zipOne('FB.xml', utf8.encode(_icelandicFb)));

      expect(blocks, isNotEmpty, reason: 'the block should be indexed at all');
      expect(blocks.first.blockName, equals('FB_Færiband'));
      expect(blocks.first.blockName, isNot(contains('Ã')),
          reason: 'Ã is the signature of UTF-8 read as Latin-1');
    });

    test('survive a zipped export in the variable names too', () async {
      await upload(_zipOne('FB.xml', utf8.encode(_icelandicFb)));
      final blocks = await index.getBlocksForAsset('asset-is');

      expect(blocks.first.fullSource, contains('bÞvottur'));
      expect(blocks.first.fullSource, contains('þvottakerfi virkt'));
      expect(blocks.first.fullSource, isNot(contains('Ã')));
    });

    // The contrast, and the reason this is a bug rather than a limitation:
    // the unzipped path was always right, so the same file gave two different
    // answers depending on whether it arrived in a zip. Green before the fix;
    // here to stop anyone "fixing" the zip path by breaking this one.
    test('survive an unzipped export, as they always did', () async {
      final blocks = await upload(Uint8List.fromList(utf8.encode(_icelandicFb)));

      expect(blocks.first.blockName, equals('FB_Færiband'));
    });

    // A genuinely Latin-1-encoded export is malformed UTF-8, and a hard
    // utf8.decode would turn a readable import into a skipped one. Falling
    // back to Latin-1 rather than to allowMalformed is worth the extra line:
    // every Icelandic letter lives inside Latin-1, so the fallback is exact,
    // where allowMalformed would replace each one with U+FFFD.
    test('a Latin-1 export imports with its characters intact', () async {
      final latin1Bytes = latin1.encode(_icelandicFb);

      final blocks = await upload(_zipOne('FB.xml', latin1Bytes));

      expect(blocks, isNotEmpty,
          reason: 'a mis-encoded file should decode, not be skipped');
      expect(blocks.first.blockName, equals('FB_Færiband'));
      expect(blocks.first.blockName, isNot(contains('�')),
          reason: 'U+FFFD would mean allowMalformed instead of a real decode');
    });
  });

  group('byte-order marks', () {
    // Reported success, indexed nothing. XmlDocument.parse throws on the
    // leading U+FEFF and the throw was swallowed into skippedFiles++.
    test('an unzipped export with a BOM still indexes its blocks', () async {
      final bytes = <int>[..._utf8Bom, ...utf8.encode(_icelandicFb)];

      final blocks = await upload(Uint8List.fromList(bytes));

      expect(blocks, isNotEmpty,
          reason: 'a BOM is the normal case for a Windows-authored export');
      expect(blocks.first.blockName, equals('FB_Færiband'));
    });

    test('a zipped export with a BOM still indexes its blocks', () async {
      final bytes = <int>[..._utf8Bom, ...utf8.encode(_icelandicFb)];

      final blocks = await upload(_zipOne('FB.xml', bytes));

      expect(blocks, isNotEmpty);
      expect(blocks.first.blockName, equals('FB_Færiband'));
    });

    // The failure was unfalsifiable from the UI: skippedFiles was the only
    // signal and nothing surfaced it. Pin that a BOM no longer counts as a
    // skip, so a future regression shows up as a number and not just silence.
    test('a BOM is not counted as a skipped file', () async {
      final bytes = <int>[..._utf8Bom, ...utf8.encode(_icelandicFb)];

      final result = await service.processUpload(
        'asset-bom',
        Uint8List.fromList(bytes),
        vendor: PlcVendor.schneiderControlExpert,
      );

      expect(result.skippedFiles, isZero);
      expect(result.totalBlocks, greaterThanOrEqualTo(1));
    });
  });
}
