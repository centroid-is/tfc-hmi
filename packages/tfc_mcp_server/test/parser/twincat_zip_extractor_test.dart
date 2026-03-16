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
