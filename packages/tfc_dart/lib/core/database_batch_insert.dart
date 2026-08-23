/// Building the SQL for a multi-row insert into a dynamic timeseries table.
///
/// Split out of [AppDatabase.tableInsertBatch] because the defect this code
/// exists to prevent is a defect of *construction*, not of execution, and a
/// test that needs a Postgres to catch it is a test that does not run in CI.
///
/// The defect: the column list, the placeholder list and the variable list are
/// three orderings that must agree. The original took them from three
/// independent sources — `dataList.first.keys`, each row's own `data.keys`,
/// and each row's own `data.values` — and rows are not guaranteed to have the
/// same keys. `sample_members` omits a member that did not resolve in that
/// sample, so one flush carries {time,a,b} next to {time,a}.
///
/// Same arity, different members, and Postgres accepts it and writes the
/// value under the wrong column. Different arity and it is
/// `42601: VALUES lists must all be the same length`, which
/// `Database._isPermanentDbError` re-raises, so the batch is queued, retried
/// every five seconds forever, and eventually dropped on overflow.
///
/// One source of truth for all three is the whole point: [BatchInsert.columns]
/// drives the names, the placeholders and the binding.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;

/// The SQL and bound variables for one multi-row insert.
class BatchInsert {
  const BatchInsert({
    required this.sql,
    required this.variables,
    required this.columns,
  });

  final String sql;
  final List<Variable> variables;

  /// The union of every row's keys, in first-seen order. Exposed so a test can
  /// assert the ordering rule directly rather than parsing it back out of SQL.
  final List<String> columns;
}

/// The union of every row's keys, in the order they are first seen.
///
/// First-seen rather than sorted so the common case — every row the same
/// shape — produces the natural column order of the sample, which is what
/// makes the generated SQL readable in a log.
List<String> unionColumns(List<Map<String, dynamic>> dataList) {
  final columns = <String>[];
  final seen = <String>{};
  for (final data in dataList) {
    for (final key in data.keys) {
      if (seen.add(key)) columns.add(key);
    }
  }
  return columns;
}

/// The `::type` cast a placeholder needs, or the empty string for none.
///
/// `time` is cast explicitly because it is bound as an ISO 8601 string.
/// Arrays are cast from the runtime type of their first element, which is the
/// only type information available at this point.
String placeholderCast(String column, dynamic value) {
  if (column == 'time') return '::timestamptz';
  if (value is! List) return '';
  if (value.isEmpty) return '::text[]';
  final first = value.first;
  if (first is int) return '::integer[]';
  if (first is double) return '::double precision[]';
  if (first is String) return '::text[]';
  if (first is bool) return '::boolean[]';
  return '::jsonb[]';
}

/// The bound value for [value], encoding lists as Postgres array literals.
Variable bindValue(dynamic value) {
  if (value is! List) return Variable(value);
  if (value.isEmpty) return const Variable('{}');
  final first = value.first;
  if (first is num || first is bool) return Variable('{${value.join(',')}}');
  if (first is String) {
    return Variable('{${value.map((e) => '"$e"').join(',')}}');
  }
  return Variable(jsonEncode(value));
}

String _quote(String ident) => '"${ident.replaceAll('"', '""')}"';

/// Builds the INSERT for [dataList] into [tableName].
///
/// Every row binds a value for every column — null where that row has none,
/// which is what a `sample_members` member that did not resolve actually
/// means. Returns null for an empty [dataList]; there is no statement to run.
BatchInsert? buildBatchInsert(
    String tableName, List<Map<String, dynamic>> dataList) {
  if (dataList.isEmpty) return null;

  final columns = unionColumns(dataList);
  final variables = <Variable>[];
  final valuesClauses = <String>[];
  var paramIndex = 1;

  for (final data in dataList) {
    final placeholders = <String>[];
    for (final column in columns) {
      final value = data[column];
      placeholders.add('\$${paramIndex++}${placeholderCast(column, value)}');
      variables.add(bindValue(value));
    }
    valuesClauses.add('(${placeholders.join(', ')})');
  }

  final keys = columns.map(_quote).join(', ');
  return BatchInsert(
    sql: 'INSERT INTO ${_quote(tableName)} ($keys) '
        'VALUES ${valuesClauses.join(', ')}',
    variables: variables,
    columns: columns,
  );
}
