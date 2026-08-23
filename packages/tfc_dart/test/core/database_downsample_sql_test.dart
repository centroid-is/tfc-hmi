import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';

/// The min/max/last downsampling statement is the History View's whole cost
/// on a range query, and the "last" column is where that cost used to live:
/// `(array_agg(value ORDER BY time DESC))[1]` makes Postgres sort every row in
/// range before it can group them — `Sort Method: external merge  Disk:
/// 60288kB` over 1.8M rows on the plant database. TimescaleDB's
/// `last(value, time)` computes the same thing in one pass off the time index.
///
/// These are white-box assertions on the generated SQL on purpose: the two
/// spellings are *semantically identical* (see the doc comment on
/// [buildDownsampleSql], and the equivalence tests in
/// test/integration/database_integration_test.dart), so no black-box test can
/// tell them apart. What can regress is somebody "simplifying" the aggregate
/// back to portable SQL and quietly reinstating the sort.
void main() {
  group('buildDownsampleSql', () {
    test('scalar branch takes the per-bucket last off the time index', () {
      final sql = buildDownsampleSql(quotedTable: 'my_tag', isArray: false);

      expect(sql, contains('last(value, time)'));
      expect(sql, isNot(contains('array_agg(value ORDER BY time DESC)')));
      // The sort we are avoiding is specifically ORDER BY inside an
      // aggregate; the trailing ORDER BY 1 over ~1000 output rows is fine.
      expect(sql, isNot(contains('ORDER BY time DESC')));
    });

    test('array branch takes the per-element last off the time index', () {
      final sql = buildDownsampleSql(quotedTable: 'my_tag', isArray: true);

      expect(sql, contains('last(val, time)'));
      expect(sql, isNot(contains('array_agg(val ORDER BY time DESC)')));
      expect(sql, isNot(contains('ORDER BY time DESC')));
    });

    test('still emits min, max and last for every bucket', () {
      for (final isArray in [false, true]) {
        final sql = buildDownsampleSql(quotedTable: 'my_tag', isArray: isArray);
        final col = isArray ? 'val' : 'value';
        expect(sql, contains('min($col)'), reason: 'isArray=$isArray');
        expect(sql, contains('max($col)'), reason: 'isArray=$isArray');
        expect(sql, contains('time_bucket(\$1::interval, time)'),
            reason: 'isArray=$isArray');
      }
    });

    test('interpolates the table name inside quotes, as given', () {
      // The caller is responsible for doubling embedded quotes; this just
      // pins that the name lands inside the identifier quotes.
      final sql =
          buildDownsampleSql(quotedTable: 'weird""name', isArray: false);
      expect(sql, contains('"weird""name"'));
    });
  });
}
