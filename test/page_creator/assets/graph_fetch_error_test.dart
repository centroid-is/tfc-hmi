import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/graph.dart';

void main() {
  group('describeTrendFetchError', () {
    test('a missing table reads as "not collected", in operator words', () {
      final text = describeTrendFetchError(
        'weigher4h.weight',
        Exception(
            'Severity.error 42P01: relation "weigher4h.weight" does not exist'),
      );
      expect(text, contains('No history for weigher4h.weight'));
      expect(text, contains('not being collected'));
      expect(text, isNot(contains('42P01')),
          reason: 'the SQLSTATE is for us, not the operator');
    });

    test('anything else keeps the cause', () {
      final text = describeTrendFetchError(
          'CVS01.CN01.Speed', Exception('connection refused'));
      expect(text, contains('Could not load history for CVS01.CN01.Speed'));
      expect(text, contains('connection refused'));
    });
  });
}
