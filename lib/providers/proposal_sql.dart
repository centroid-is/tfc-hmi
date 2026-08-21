/// SQL for moving a proposal out of `pending`.
///
/// Drift hands custom SQL to the engine verbatim, so the placeholder style has
/// to match the backend: SQLite binds with `?`, Postgres with `$1`, `$2`. Both
/// writers used the `?` form unconditionally, which against Postgres is a
/// syntax error rather than a wrong answer — and both swallowed it. The
/// `mcp_proposal` table had accumulated 1018 rows without a single status
/// change, so every proposal ever made came back on the next load and looked
/// like the delivery being flaky.
library;

import 'package:drift/drift.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart' show adaptSql;

/// The statement that sets a proposal's status, bound for [isPostgres].
String proposalStatusUpdate({required bool isPostgres}) => adaptSql(
      'UPDATE mcp_proposal SET status = ? WHERE id = ?',
      isPostgres: isPostgres,
    );

/// The poll for proposals newer than the watermark, bound for [isPostgres].
///
/// Same defect as the status update: against Postgres this was a syntax error
/// inside a `catch (_) {}`, so the watcher could never read a proposal out of
/// the database and every delivery depended on the inline path from the tool
/// result.
String proposalPollQuery({required bool isPostgres}) => adaptSql(
      'SELECT id, proposal_type, title, proposal_json, operator_id, created_at '
      'FROM mcp_proposal WHERE id > ? AND status = ? ORDER BY id ASC',
      isPostgres: isPostgres,
    );

/// Whether [db] speaks Postgres, so the caller can pick the binding style.
bool proposalDbIsPostgres(GeneratedDatabase db) =>
    db.executor.dialect == SqlDialect.postgres;
