import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/parser/twincat_zip_extractor.dart';

import '../helpers/sample_twincat_files.dart';

Uint8List _createZip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  _encodingTests();

  group('extractTwinCatFiles', () {
    test('extracts .TcPOU, .TcGVL, and .st files from zip', () {
      final zipBytes = _createZip({
        'POUs/Main.TcPOU': sampleTcPouXml,
        'GVLs/GVL_Main.TcGVL': sampleTcGvlXml,
        'POUs/Helper.st': sampleStFile,
        'Project.tsproj': '<TcSmProject></TcSmProject>',
      });

      final results = extractTwinCatFiles(zipBytes);

      expect(results, hasLength(3));
      expect(
        results.map((f) => f.type).toSet(),
        equals({TwinCatFileType.tcPou, TwinCatFileType.tcGvl, TwinCatFileType.st}),
      );
    });

    test('returns empty list for zip with only non-code files', () {
      final zipBytes = _createZip({
        'Project.tsproj': '<TcSmProject></TcSmProject>',
        'Types/DUT_MyType.TcDUT': '<TcPlcObject></TcPlcObject>',
      });

      final results = extractTwinCatFiles(zipBytes);
      expect(results, isEmpty);
    });

    test('throws ArgumentError for zip over 50 MB', () {
      // Create a small zip and test with a low maxSizeBytes
      final zipBytes = _createZip({
        'POUs/Main.TcPOU': sampleTcPouXml,
      });

      expect(
        () => extractTwinCatFiles(zipBytes, maxSizeBytes: 10),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('file type detection is case-insensitive', () {
      final zipBytes = _createZip({
        'POUs/Main.TCPOU': sampleTcPouXml,
        'GVLs/GVL.tcgvl': sampleTcGvlXml,
        'helper.ST': sampleStFile,
      });

      final results = extractTwinCatFiles(zipBytes);
      expect(results, hasLength(3));
      expect(results[0].type, equals(TwinCatFileType.tcPou));
      expect(results[1].type, equals(TwinCatFileType.tcGvl));
      expect(results[2].type, equals(TwinCatFileType.st));
    });

    test('preserves nested directory paths', () {
      final zipBytes = _createZip({
        'Project/POUs/SubFolder/Deep/Main.TcPOU': sampleTcPouXml,
      });

      final results = extractTwinCatFiles(zipBytes);
      expect(results, hasLength(1));
      expect(results.first.path, equals('Project/POUs/SubFolder/Deep/Main.TcPOU'));
    });
  });
}

// ---------------------------------------------------------------------------
// Encoding
//
// Same defect as the Schneider path in plc_code_service: entry bytes were read
// with String.fromCharCodes, which is Latin-1. A Beckhoff project exported
// from a Windows machine with Icelandic identifiers came out as mojibake, and
// the BOM that the same tooling writes was kept as three stray characters at
// the head of the XML.
// ---------------------------------------------------------------------------

/// Builds a zip writing raw bytes, so the test controls the encoding rather
/// than ArchiveFile.string re-encoding for it.
Uint8List _zipRaw(String path, List<int> bytes) {
  final archive = Archive()..addFile(ArchiveFile.bytes(path, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const String _icelandicPou = '''<?xml version="1.0" encoding="utf-8"?>
<TcPlcObject Version="1.1.0.1">
  <POU Name="FB_Færiband" Id="{00000000-0000-0000-0000-000000000001}">
    <Declaration><![CDATA[FUNCTION_BLOCK FB_Færiband
VAR
    bÞvottur : BOOL; (* þvottakerfi *)
END_VAR]]></Declaration>
    <Implementation><ST><![CDATA[bÞvottur := TRUE;]]></ST></Implementation>
  </POU>
</TcPlcObject>
''';

void _encodingTests() {
  group('extractTwinCatFiles encoding', () {
    test('reads UTF-8 identifiers without mangling them', () {
      final files = extractTwinCatFiles(
          _zipRaw('POUs/FB.TcPOU', utf8.encode(_icelandicPou)));

      expect(files, hasLength(1));
      expect(files.first.content, contains('FB_Færiband'));
      expect(files.first.content, contains('þvottakerfi'));
      expect(files.first.content, isNot(contains('Ã')),
          reason: 'Ã is the signature of UTF-8 read as Latin-1');
    });

    test('strips the byte-order mark Windows tooling writes', () {
      final withBom = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(_icelandicPou)];

      final files = extractTwinCatFiles(_zipRaw('POUs/FB.TcPOU', withBom));

      expect(files.first.content.startsWith('<?xml'), isTrue,
          reason: 'a kept BOM makes XmlDocument.parse throw downstream');
    });

    test('falls back to Latin-1 exactly, not to replacement characters', () {
      final files = extractTwinCatFiles(
          _zipRaw('POUs/FB.TcPOU', latin1.encode(_icelandicPou)));

      expect(files.first.content, contains('FB_Færiband'));
      expect(files.first.content, isNot(contains('�')));
    });
  });
}
