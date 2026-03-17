import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart'
    if (dart.library.js_interop) '../core/pdfrx_stub.dart';

import 'section_detector.dart' show SizedFragment;
import 'tech_doc_upload_service.dart' show PdfPageFragments, PdfTextExtractor;

/// Production [PdfTextExtractor] using pdfrx to extract text fragments
/// with bounding-box heights from each page of a PDF.
///
/// pdfrx 2.x returns per-character bounding rects via [PdfPageRawText].
/// This extractor groups characters into lines by detecting Y-coordinate
/// breaks, then emits one [SizedFragment] per line with the median
/// character height as the fragment height.
class PdfrxTextExtractor implements PdfTextExtractor {
  @override
  Future<int> getPageCount(Uint8List pdfBytes) async {
    final document = await PdfDocument.openData(pdfBytes);
    try {
      return document.pages.length;
    } finally {
      document.dispose();
    }
  }

  @override
  Future<List<PdfPageFragments>> extractFragments(Uint8List pdfBytes) async {
    final document = await PdfDocument.openData(pdfBytes);
    try {
      final result = <PdfPageFragments>[];

      for (int i = 0; i < document.pages.length; i++) {
        final page = document.pages[i];
        final rawText = await page.loadText();
        if (rawText == null || rawText.fullText.isEmpty) {
          result.add(PdfPageFragments(pageNumber: i + 1, fragments: []));
          continue;
        }

        final fragments = _extractLineFragments(rawText, i + 1);
        result.add(PdfPageFragments(pageNumber: i + 1, fragments: fragments));
      }

      return result;
    } finally {
      document.dispose();
    }
  }

  /// Groups characters into lines and returns one [SizedFragment] per line.
  List<SizedFragment> _extractLineFragments(
      PdfPageRawText rawText, int pageNumber) {
    final text = rawText.fullText;
    final rects = rawText.charRects;
    final fragments = <SizedFragment>[];

    if (text.isEmpty) return fragments;

    // Walk through text splitting on newlines.
    // For each line, compute the median character height from charRects.
    var lineStart = 0;
    for (var j = 0; j <= text.length; j++) {
      final isEnd = j == text.length;
      final isNewline = !isEnd && text[j] == '\n';

      if (isEnd || isNewline) {
        if (j > lineStart) {
          final lineText = text.substring(lineStart, j).trim();
          if (lineText.isNotEmpty) {
            // Compute median character height for this line.
            final heights = <double>[];
            for (var k = lineStart; k < j && k < rects.length; k++) {
              final h = rects[k].height.abs();
              if (h > 0) heights.add(h);
            }

            final height = heights.isNotEmpty ? _median(heights) : 10.0;
            fragments.add(SizedFragment(
              text: lineText,
              height: height,
              pageNumber: pageNumber,
            ));
          }
        }
        lineStart = j + 1;
      }
    }

    return fragments;
  }

  double _median(List<double> values) {
    values.sort();
    final mid = values.length ~/ 2;
    if (values.length.isOdd) return values[mid];
    return (values[mid - 1] + values[mid]) / 2.0;
  }
}
