import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/graph.dart';

void main() {
  group('extractSeriesMemberValue', () {
    // Rows collected with `sample_members` cross the database boundary
    // either as decoded maps (historical query) or as raw JSON text
    // (notification payload) — both must chart identically.
    const row = {'p_stat_Frequency': 25.5, 'p_stat_xOutput': true};
    const rowJson =
        '{"p_stat_Frequency": 25.5, "p_stat_xOutput": true, "s": "x"}';

    test('plucks a numeric member from a decoded map', () {
      expect(extractSeriesMemberValue(row, 'p_stat_Frequency'), 25.5);
    });

    test('plucks from raw JSON text (notification path)', () {
      expect(extractSeriesMemberValue(rowJson, 'p_stat_Frequency'), 25.5);
    });

    test('bools chart as 1/0 — including string-encoded bools', () {
      expect(extractSeriesMemberValue(row, 'p_stat_xOutput'), 1);
      expect(extractSeriesMemberValue({'m': false}, 'm'), 0);
      expect(extractSeriesMemberValue({'m': 'true'}, 'm'), 1);
      expect(extractSeriesMemberValue({'m': 'false'}, 'm'), 0);
    });

    test('numeric strings parse, garbage drops the point', () {
      expect(extractSeriesMemberValue({'m': '42.5'}, 'm'), 42.5);
      expect(extractSeriesMemberValue({'m': 'oops'}, 'm'), isNull);
    });

    test('missing member / non-row values yield null (point dropped)', () {
      expect(extractSeriesMemberValue(row, 'nope'), isNull);
      expect(extractSeriesMemberValue(3.14, 'm'), isNull);
      expect(extractSeriesMemberValue('not json', 'm'), isNull);
    });

    test('GraphSeriesConfig.member round-trips through JSON', () {
      final series = GraphSeriesConfig(
          key: '/k', label: 'freq', member: 'p_stat_Frequency');
      final restored = GraphSeriesConfig.fromJson(series.toJson());
      expect(restored.member, 'p_stat_Frequency');

      // Legacy series without the field keep charting the row as-is.
      final legacy = GraphSeriesConfig.fromJson({'key': '/k', 'label': ''});
      expect(legacy.member, isNull);
    });
  });
}
