import 'dart:typed_data';

import 'package:archive/archive.dart';

/// File types recognized from a TwinCAT project zip.
enum TwinCatFileType {
  /// .TcPOU -- Program Organization Unit (Function Block, Program, Function).
  tcPou,

  /// .TcGVL -- Global Variable List.
  tcGvl,

  /// .st -- Raw structured text file (not XML-wrapped).
  st,
}

/// A file extracted from a TwinCAT project zip.
class ExtractedFile {
  const ExtractedFile({
    required this.path,
    required this.content,
    required this.type,
  });

  /// Original path within the zip archive.
  final String path;

  /// File content as a string.
  final String content;

  /// Detected TwinCAT file type.
  final TwinCatFileType type;
}

/// Extract TwinCAT source files (.TcPOU, .TcGVL, .st) from a zip archive.
///
/// Ignores all other file types (.tsproj, .TcDUT, .TcIO, etc.).
/// Throws [ArgumentError] if [zipBytes] exceeds [maxSizeBytes] (default 50 MB).
List<ExtractedFile> extractTwinCatFiles(
  Uint8List zipBytes, {
  int maxSizeBytes = 50 * 1024 * 1024,
}) {
  if (zipBytes.length > maxSizeBytes) {
    final sizeMb = (zipBytes.length / (1024 * 1024)).toStringAsFixed(1);
    final limitMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(0);
    throw ArgumentError(
      'Zip file size ($sizeMb MB) exceeds the $limitMb MB limit',
    );
  }

  final archive = ZipDecoder().decodeBytes(zipBytes);
  final results = <ExtractedFile>[];

  for (final entry in archive) {
    if (!entry.isFile) continue;

    final nameLower = entry.name.toLowerCase();
    TwinCatFileType? type;

    if (nameLower.endsWith('.tcpou')) {
      type = TwinCatFileType.tcPou;
    } else if (nameLower.endsWith('.tcgvl')) {
      type = TwinCatFileType.tcGvl;
    } else if (nameLower.endsWith('.st')) {
      type = TwinCatFileType.st;
    }

    if (type != null) {
      final content = String.fromCharCodes(entry.content as List<int>);
      results.add(ExtractedFile(
        path: entry.name,
        content: content,
        type: type,
      ));
    }
  }

  return results;
}
