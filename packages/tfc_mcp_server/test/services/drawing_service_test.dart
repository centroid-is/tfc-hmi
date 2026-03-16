import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/interfaces/drawing_index.dart';
import 'package:tfc_mcp_server/src/services/drawing_service.dart';
import '../helpers/mock_drawing_index.dart';

void main() {
  group('DrawingService', () {
    late MockDrawingIndex mockIndex;
    late DrawingService service;

    setUp(() {
      mockIndex = MockDrawingIndex();
      service = DrawingService(mockIndex);

      // Populate test data
      mockIndex.addResult(const DrawingSearchResult(
        drawingName: 'Panel-A Main Wiring',
        pageNumber: 5,
        assetKey: 'panel-A',
        componentName: 'relay K3',
      ));
      mockIndex.addResult(const DrawingSearchResult(
        drawingName: 'Panel-B Motor Control',
        pageNumber: 2,
        assetKey: 'panel-B',
        componentName: 'motor M1',
      ));
      mockIndex.addResult(const DrawingSearchResult(
        drawingName: 'Panel-A Aux Wiring',
        pageNumber: 8,
        assetKey: 'panel-A',
        componentName: 'relay K7',
      ));
      mockIndex.addResult(const DrawingSearchResult(
        drawingName: 'Panel-C Power Distribution',
        pageNumber: 3,
        assetKey: 'panel-C',
        componentName: 'contactor Q1',
      ));
    });

    test('searchDrawings with component name returns matching results',
        () async {
      final results = await service.searchDrawings(query: 'relay K3');
      expect(results, hasLength(1));
      expect(results.first['componentName'], equals('relay K3'));
      expect(results.first['drawingName'], equals('Panel-A Main Wiring'));
      expect(results.first['pageNumber'], equals(5));
      expect(results.first['assetKey'], equals('panel-A'));
    });

    test('searchDrawings with partial name returns all matching components',
        () async {
      final results = await service.searchDrawings(query: 'motor');
      expect(results, hasLength(1));
      expect(results.first['componentName'], equals('motor M1'));
    });

    test('searchDrawings with relay returns multiple relay results', () async {
      final results = await service.searchDrawings(query: 'relay');
      expect(results, hasLength(2));
      expect(
        results.map((r) => r['componentName']),
        containsAll(['relay K3', 'relay K7']),
      );
    });

    test('searchDrawings with nonexistent query returns empty list', () async {
      final results = await service.searchDrawings(query: 'nonexistent');
      expect(results, isEmpty);
    });

    test('searchDrawings with assetFilter returns only that asset', () async {
      final results = await service.searchDrawings(
        query: 'relay',
        assetFilter: 'panel-A',
      );
      expect(results, hasLength(2));
      for (final r in results) {
        expect(r['assetKey'], equals('panel-A'));
      }
    });

    test('searchDrawings with limit returns at most limit results', () async {
      // Add more results to exceed limit
      mockIndex.addResult(const DrawingSearchResult(
        drawingName: 'Panel-D Relay Bank',
        pageNumber: 1,
        assetKey: 'panel-D',
        componentName: 'relay K10',
      ));
      final results = await service.searchDrawings(query: 'relay', limit: 2);
      expect(results, hasLength(2));
    });

    test('searchDrawings with empty index returns empty list', () async {
      mockIndex.clear();
      final results = await service.searchDrawings(query: 'relay');
      expect(results, isEmpty);
    });

    test('results contain metadata only -- no PDF bytes', () async {
      final results = await service.searchDrawings(query: 'relay K3');
      expect(results, hasLength(1));
      final result = results.first;
      // Should only have these four metadata keys
      expect(
          result.keys.toSet(),
          equals({
            'drawingName',
            'pageNumber',
            'assetKey',
            'componentName',
          }));
    });

    test('hasDrawings returns false for empty index', () async {
      mockIndex.clear();
      expect(await service.hasDrawings, isFalse);
    });

    test('hasDrawings returns true for non-empty index', () async {
      expect(await service.hasDrawings, isTrue);
    });
  });
}
