import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:tfc/widgets/searchable_pdf_viewer.dart';

void main() {
  const testSize = Size(1024, 900);

  group('SearchablePdfViewer initial page', () {
    testWidgets('passes targetPage as initialPageNumber to PdfViewer.data',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchablePdfViewer(
              pdfBytes: Uint8List.fromList(List.filled(16, 0)),
              targetPage: 10,
            ),
          ),
        ),
      );
      await tester.pump();

      // Find the PdfViewer in the widget tree and verify initialPageNumber.
      final pdfViewerFinder = find.byType(PdfViewer);
      expect(pdfViewerFinder, findsOneWidget);

      final pdfViewer = tester.widget<PdfViewer>(pdfViewerFinder);
      expect(pdfViewer.initialPageNumber, 10);
    });

    testWidgets('defaults initialPageNumber to 1 when targetPage is null',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchablePdfViewer(
              pdfBytes: Uint8List.fromList(List.filled(16, 0)),
            ),
          ),
        ),
      );
      await tester.pump();

      final pdfViewerFinder = find.byType(PdfViewer);
      expect(pdfViewerFinder, findsOneWidget);

      final pdfViewer = tester.widget<PdfViewer>(pdfViewerFinder);
      expect(pdfViewer.initialPageNumber, 1);
    });

    testWidgets('passes targetPage as initialPageNumber to PdfViewer.file',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchablePdfViewer(
              filePath: '/nonexistent/test.pdf',
              targetPage: 5,
            ),
          ),
        ),
      );
      await tester.pump();

      final pdfViewerFinder = find.byType(PdfViewer);
      expect(pdfViewerFinder, findsOneWidget);

      final pdfViewer = tester.widget<PdfViewer>(pdfViewerFinder);
      expect(pdfViewer.initialPageNumber, 5);
    });

    testWidgets(
        'updates initialPageNumber when rebuilt with different targetPage',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bytes = Uint8List.fromList(List.filled(16, 0));

      // First build with targetPage=3
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchablePdfViewer(
              pdfBytes: bytes,
              targetPage: 3,
            ),
          ),
        ),
      );
      await tester.pump();

      var pdfViewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(pdfViewer.initialPageNumber, 3);

      // Rebuild with targetPage=7
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchablePdfViewer(
              pdfBytes: bytes,
              targetPage: 7,
            ),
          ),
        ),
      );
      await tester.pump();

      pdfViewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(pdfViewer.initialPageNumber, 7);
    });
  });
}
