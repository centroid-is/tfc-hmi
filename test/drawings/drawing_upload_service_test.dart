import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart';

// Import the mock from the MCP server test helpers
import '../../packages/tfc_mcp_server/test/helpers/mock_drawing_index.dart';

// Import the service under test
import 'package:tfc/drawings/drawing_upload_service.dart';

void main() {
  group('DrawingUploadService', () {
    late MockDrawingIndex mockIndex;
    late DrawingUploadService service;

    setUp(() {
      mockIndex = MockDrawingIndex();
      service = DrawingUploadService(mockIndex);
    });

    test('uploadDrawingWithTexts calls storeDrawing with correct arguments',
        () async {
      final pageTexts = [
        const DrawingPageText(pageNumber: 1, fullText: 'relay K3\nmotor M1'),
        const DrawingPageText(pageNumber: 2, fullText: 'contactor Q1'),
      ];

      await service.uploadDrawingWithTexts(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Wiring',
        filePath: '/drawings/panel-a.pdf',
        pageTexts: pageTexts,
      );

      final summaries = await service.getDrawings();
      expect(summaries, hasLength(1));
      expect(summaries.first.drawingName, equals('Panel-A Wiring'));
      expect(summaries.first.assetKey, equals('panel-A'));
      expect(summaries.first.filePath, equals('/drawings/panel-a.pdf'));
      expect(summaries.first.pageCount, equals(2));
    });

    test('uploadDrawingWithTexts replaces existing drawing (re-upload)',
        () async {
      // Upload initial version
      await service.uploadDrawingWithTexts(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Wiring',
        filePath: '/drawings/panel-a-v1.pdf',
        pageTexts: [
          const DrawingPageText(pageNumber: 1, fullText: 'old content'),
        ],
      );

      // Re-upload with same name
      await service.uploadDrawingWithTexts(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Wiring',
        filePath: '/drawings/panel-a-v2.pdf',
        pageTexts: [
          const DrawingPageText(pageNumber: 1, fullText: 'new content'),
          const DrawingPageText(pageNumber: 2, fullText: 'extra page'),
        ],
      );

      final summaries = await service.getDrawings();
      expect(summaries, hasLength(1));
      expect(summaries.first.filePath, equals('/drawings/panel-a-v2.pdf'));
      expect(summaries.first.pageCount, equals(2));
    });

    test('getDrawings returns list of DrawingSummary from DrawingIndex',
        () async {
      // Store two drawings
      await service.uploadDrawingWithTexts(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Wiring',
        filePath: '/drawings/panel-a.pdf',
        pageTexts: [
          const DrawingPageText(pageNumber: 1, fullText: 'content A'),
        ],
      );
      await service.uploadDrawingWithTexts(
        assetKey: 'panel-B',
        drawingName: 'Panel-B Motors',
        filePath: '/drawings/panel-b.pdf',
        pageTexts: [
          const DrawingPageText(pageNumber: 1, fullText: 'content B1'),
          const DrawingPageText(pageNumber: 2, fullText: 'content B2'),
        ],
      );

      final summaries = await service.getDrawings();
      expect(summaries, hasLength(2));
      expect(
        summaries.map((s) => s.drawingName).toSet(),
        equals({'Panel-A Wiring', 'Panel-B Motors'}),
      );
    });

    test('deleteDrawing calls deleteDrawing on DrawingIndex', () async {
      // Store a drawing first
      await service.uploadDrawingWithTexts(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Wiring',
        filePath: '/drawings/panel-a.pdf',
        pageTexts: [
          const DrawingPageText(pageNumber: 1, fullText: 'content'),
        ],
      );

      expect(await service.getDrawings(), hasLength(1));

      await service.deleteDrawing('Panel-A Wiring');

      expect(await service.getDrawings(), isEmpty);
    });
  });
}
