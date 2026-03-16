import 'package:drift/drift.dart';

/// Adapts a SQL query with `?` placeholders to use `$N` placeholders
/// when targeting PostgreSQL.
///
/// SQLite uses `?` for bind parameters. PostgreSQL uses `$1`, `$2`, etc.
/// Drift's `customSelect` does NOT translate placeholders automatically --
/// the SQL string is passed verbatim to the database engine.
///
/// When [isPostgres] is `true`, each `?` in [sql] is replaced with
/// `$1`, `$2`, `$3`, etc. in order of appearance.
///
/// When [isPostgres] is `false` (SQLite), the query is returned unchanged.
///
/// Example:
/// ```dart
/// adaptSql('SELECT * FROM t WHERE a = ? AND b = ? LIMIT ?', isPostgres: true)
/// // => 'SELECT * FROM t WHERE a = $1 AND b = $2 LIMIT $3'
/// ```
String adaptSql(String sql, {required bool isPostgres}) {
  if (!isPostgres) return sql;
  var index = 0;
  return sql.replaceAllMapped(RegExp(r'\?'), (_) => '\$${++index}');
}

/// Returns `true` if [db] uses a PostgreSQL backend.
///
/// Checks the executor's [SqlDialect] to determine the backend type.
/// This allows services to auto-detect the correct SQL placeholder style
/// without requiring an explicit `isPostgres` constructor parameter.
bool isPostgresDb(GeneratedDatabase db) {
  return db.executor.dialect == SqlDialect.postgres;
}
