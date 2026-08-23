import 'package:test/test.dart';
import 'package:tfc_dart/core/database_batch_insert.dart';

/// Covers the construction of a multi-row INSERT, which is pure string and
/// list work and needs no database. The equivalent Postgres test exists too
/// (`database_ragged_batch_test.dart`) and proves the SQL is actually
/// accepted; it is skip-gated on a server, so it does not run in CI. This one
/// does, on every platform, and it is what stops the column/placeholder/
/// variable orderings drifting apart again.

/// The value each column was bound to for row [row].
Map<String, Object?> boundRow(BatchInsert insert, int row) {
  final n = insert.columns.length;
  final slice = insert.variables.sublist(row * n, (row + 1) * n);
  return {
    for (var i = 0; i < n; i++) insert.columns[i]: slice[i].value,
  };
}

/// The `($1, $2, ...)` groups, one per row.
List<String> valuesGroups(String sql) =>
    RegExp(r'\(([^()]*)\)').allMatches(sql.split(' VALUES ').last)
        .map((m) => m.group(1)!)
        .toList();

void main() {
  group('column ordering', () {
    test('is the union of every row, not just the first', () {
      final insert = buildBatchInsert('t', [
        {'time': 'T0', 'a': 1.0},
        {'time': 'T1', 'b': 2.0},
        {'time': 'T2', 'a': 3.0, 'c': 4.0},
      ])!;
      expect(insert.columns, ['time', 'a', 'b', 'c']);
    });

    test('is first-seen across the batch, not sorted', () {
      final insert = buildBatchInsert('t', [
        {'time': 'T0', 'zebra': 1},
        {'time': 'T1', 'alpha': 2},
      ])!;
      expect(insert.columns, ['time', 'zebra', 'alpha'],
          reason: 'Sorting would reorder a struct away from its sample order.');
    });

    test('a repeated key is not repeated as a column', () {
      final insert = buildBatchInsert('t', [
        {'time': 'T0', 'a': 1},
        {'time': 'T1', 'a': 2},
      ])!;
      expect(insert.columns, ['time', 'a']);
    });
  });

  group('ragged rows', () {
    test('rows of DIFFERENT arity still produce equal-length VALUES lists', () {
      // The 42601 case: "VALUES lists must all be the same length".
      final insert = buildBatchInsert('t', [
        {'time': 'T0', 'a': 1.0, 'b': 2.0},
        {'time': 'T1', 'a': 3.0},
      ])!;
      final groups = valuesGroups(insert.sql);
      expect(groups, hasLength(2));
      final widths =
          groups.map((g) => g.split(',').length).toSet();
      expect(widths, {insert.columns.length},
          reason: 'Every row must bind one value per column.');
      expect(insert.variables,
          hasLength(insert.columns.length * 2));
    });

    test('rows of the SAME arity bind each value under its OWN column', () {
      // The silent-corruption case. Positional binding put 9.0 under `a`.
      final insert = buildBatchInsert('t', [
        {'time': 'T0', 'a': 1.0},
        {'time': 'T1', 'b': 9.0},
      ])!;
      expect(insert.columns, ['time', 'a', 'b']);
      expect(boundRow(insert, 0), {'time': 'T0', 'a': 1.0, 'b': null});
      expect(boundRow(insert, 1), {'time': 'T1', 'a': null, 'b': 9.0},
          reason: '9.0 belongs to b. Binding it under a is the corruption '
              'this whole split exists to make impossible.');
    });

    test('a row missing a column binds null for it', () {
      final insert = buildBatchInsert('t', [
        {'time': 'T0', 'a': 1.0, 'b': 2.0},
        {'time': 'T1', 'a': 3.0},
      ])!;
      expect(boundRow(insert, 1), {'time': 'T1', 'a': 3.0, 'b': null});
    });

    test('placeholders are numbered continuously across rows', () {
      final insert = buildBatchInsert('t', [
        {'time': 'T0', 'a': 1},
        {'time': 'T1', 'a': 2},
      ])!;
      expect(insert.sql, contains(r'($1::timestamptz, $2)'));
      expect(insert.sql, contains(r'($3::timestamptz, $4)'));
    });
  });

  group('casts and binding, unchanged from before the split', () {
    test('time is cast to timestamptz', () {
      final insert = buildBatchInsert('t', [
        {'time': 'T0', 'value': 1.0}
      ])!;
      expect(insert.sql, contains(r'$1::timestamptz'));
      expect(insert.sql, contains(r'$2)'));
    });

    test('array columns are cast from the first element type', () {
      expect(placeholderCast('value', <int>[1, 2]), '::integer[]');
      expect(placeholderCast('value', <double>[1.5]), '::double precision[]');
      expect(placeholderCast('value', <String>['a']), '::text[]');
      expect(placeholderCast('value', <bool>[true]), '::boolean[]');
      expect(placeholderCast('value', <dynamic>[]), '::text[]');
      expect(placeholderCast('value', <dynamic>[Object()]), '::jsonb[]');
      expect(placeholderCast('value', 1.0), '');
    });

    test('arrays bind as postgres array literals', () {
      expect(bindValue(<int>[1, 2, 3]).value, '{1,2,3}');
      expect(bindValue(<double>[1.5, 2.5]).value, '{1.5,2.5}');
      expect(bindValue(<bool>[true, false]).value, '{true,false}');
      expect(bindValue(<String>['a', 'b']).value, '{"a","b"}');
      expect(bindValue(<dynamic>[]).value, '{}');
      expect(bindValue(2.5).value, 2.5);
      expect(bindValue(null).value, isNull);
    });

    test('an array column keeps its cast and its literal together', () {
      final insert = buildBatchInsert('t', [
        {'time': 'T0', 'value': <int>[1, 2]}
      ])!;
      expect(insert.sql, contains(r'$2::integer[]'));
      expect(boundRow(insert, 0)['value'], '{1,2}');
    });
  });

  group('statement shape', () {
    test('an empty batch produces no statement', () {
      expect(buildBatchInsert('t', []), isNull);
    });

    test('identifiers are quoted, and embedded quotes escaped', () {
      final insert = buildBatchInsert('we"ird', [
        {'col"umn': 1}
      ])!;
      expect(insert.sql, startsWith('INSERT INTO "we""ird" ("col""umn")'));
    });

    test('a dotted table name survives quoting', () {
      // Timeseries tables are named after keys like `cooler.temp.1`.
      final insert = buildBatchInsert('cooler.temp.1', [
        {'time': 'T0', 'value': 1.0}
      ])!;
      expect(insert.sql, startsWith('INSERT INTO "cooler.temp.1" '));
    });
  });
}
