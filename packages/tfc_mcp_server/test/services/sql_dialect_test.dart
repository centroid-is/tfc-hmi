import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/services/sql_dialect.dart';

void main() {
  group('adaptSql', () {
    test('returns query unchanged for SQLite (isPostgres=false)', () {
      final result = adaptSql(
        'SELECT * FROM alarm WHERE uid = ? AND active = ?',
        isPostgres: false,
      );
      expect(result, equals('SELECT * FROM alarm WHERE uid = ? AND active = ?'));
    });

    test('replaces ? placeholders with \$N for PostgreSQL', () {
      final result = adaptSql(
        'SELECT * FROM alarm WHERE uid = ? AND active = ?',
        isPostgres: true,
      );
      expect(result, equals(r'SELECT * FROM alarm WHERE uid = $1 AND active = $2'));
    });

    test('handles single placeholder', () {
      final result = adaptSql(
        'SELECT value FROM flutter_preferences WHERE key = ?',
        isPostgres: true,
      );
      expect(result, equals(r'SELECT value FROM flutter_preferences WHERE key = $1'));
    });

    test('handles LIMIT placeholder', () {
      final result = adaptSql(
        'SELECT uid, title FROM alarm LIMIT ?',
        isPostgres: true,
      );
      expect(result, equals(r'SELECT uid, title FROM alarm LIMIT $1'));
    });

    test('handles mixed WHERE and LIMIT placeholders', () {
      final result = adaptSql(
        'SELECT * FROM alarm_history WHERE active = ? '
        'AND deactivated_at IS NULL ORDER BY created_at DESC LIMIT ?',
        isPostgres: true,
      );
      expect(
        result,
        equals(
          r'SELECT * FROM alarm_history WHERE active = $1 '
          r'AND deactivated_at IS NULL ORDER BY created_at DESC LIMIT $2',
        ),
      );
    });

    test('handles query with no placeholders', () {
      final result = adaptSql(
        'SELECT COUNT(*) FROM alarm',
        isPostgres: true,
      );
      expect(result, equals('SELECT COUNT(*) FROM alarm'));
    });

    test('handles multiple sequential placeholders', () {
      final result = adaptSql(
        'WHERE created_at >= ? AND created_at <= ? AND alarm_uid = ? LIMIT ?',
        isPostgres: true,
      );
      expect(
        result,
        equals(
          r'WHERE created_at >= $1 AND created_at <= $2 AND alarm_uid = $3 LIMIT $4',
        ),
      );
    });

    test('handles dynamic WHERE with empty conditions', () {
      // Simulates queryHistory with no filter params
      final conditions = <String>[];
      final whereClause =
          conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
      final sql =
          'SELECT * FROM alarm_history $whereClause ORDER BY created_at DESC LIMIT ?';

      final result = adaptSql(sql, isPostgres: true);
      expect(
        result,
        equals(
          r'SELECT * FROM alarm_history  ORDER BY created_at DESC LIMIT $1',
        ),
      );
    });

    test('handles dynamic WHERE with all conditions', () {
      // Simulates queryHistory with all filter params
      final conditions = [
        'created_at >= ?',
        'created_at <= ?',
        'alarm_uid = ?',
      ];
      final whereClause = 'WHERE ${conditions.join(' AND ')}';
      final sql =
          'SELECT * FROM alarm_history $whereClause ORDER BY created_at DESC LIMIT ?';

      final result = adaptSql(sql, isPostgres: true);
      expect(
        result,
        equals(
          r'SELECT * FROM alarm_history WHERE created_at >= $1 AND created_at <= $2 AND alarm_uid = $3 ORDER BY created_at DESC LIMIT $4',
        ),
      );
    });
  });

  group('isPostgresDb', () {
    test('returns false for in-memory SQLite database', () async {
      final db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      expect(isPostgresDb(db), isFalse);

      await db.close();
    });
  });
}
