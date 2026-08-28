/// The Drift-backed [AuditSink]: one [AuditRecord] in, one `audit_entry` row
/// out, and nothing else.
///
/// This is the only writer of the audit trail. It appends. It has no method
/// that edits or removes a row and it must not grow one — see the class doc
/// for why that is a design constraint and not merely a fact about today.
library;

import 'package:drift/drift.dart';
import 'package:logger/logger.dart';
import 'package:tfc_access/tfc_access.dart';

import '../database_drift.dart';

/// Writes an [AuditRecord] straight into the `audit_entry` table.
///
/// ## Why it takes [AppDatabase] and not the `Database` wrapper
///
/// `Database` is the collector's plumbing — the retry queue, the timeseries
/// table creation, the retention machinery. None of it applies here. The sink
/// wants the Drift handle and the generated companion, so that is what it
/// asks for, and taking the narrower thing keeps the audit path out of the
/// code that exists to bound and sweep tables.
///
/// ## Why it does not batch
///
/// `database_batch_insert.dart` exists and is the right answer for
/// time-series, where a lost sample is a gap in a chart that nobody will ever
/// look at closely. An audit row is not a sample — it is the record that
/// somebody did something, and a flush timer whose buffer a crash discards is
/// exactly the failure the trail exists to survive. So the insert happens on
/// the call, synchronously with the caller's `await`.
///
/// If a later performance pass finds this expensive, the answer is a queue
/// that survives a crash, not a timer that does not.
///
/// ## Why there is one method
///
/// Append-only is a property of the code that can write, not a policy written
/// down somewhere. A sink that also exposed a way to remove a row would be
/// one refactor away from a swept trail, and the person doing that refactor
/// would have no reason to think they were doing anything unusual. There is
/// no such method, `drift_audit_sink_test.dart` asserts on the source text
/// that none has appeared, and the retention machinery refuses this table by
/// name (`kRetentionExemptTables` in `database.dart`).
///
/// What this does *not* protect against is anybody with `psql`. That is a
/// deployment concern and it is addressed, as far as it can be, by the
/// INSERT-only Postgres role in `docs/access-control-deployment.md`.
class DriftAuditSink implements AuditSink {
  DriftAuditSink(this._db, {Logger? logger}) : _logger = logger ?? Logger();

  final AppDatabase _db;

  final Logger _logger;

  /// Appends [entry] to the trail.
  ///
  /// ## Why a failure is swallowed
  ///
  /// Swallowing is normally wrong, and it is right here for a narrow reason:
  /// the callers are auth and write paths, and refusing to sign somebody in —
  /// or refusing a setpoint change — because the audit database blinked is a
  /// worse outcome than a gap in the trail. The audit trail is an operational
  /// guardrail, not a security boundary, and a guardrail that stops the plant
  /// when it breaks has stopped being a guardrail.
  ///
  /// The price of that choice is that an absent audit row is the one defect
  /// nobody ever notices. So the error line names the record it lost —
  /// `actionId`, `who`, `itemKey` — and says in those words that a row was
  /// lost, so the log is a partial trail rather than a shrug.
  @override
  Future<void> record(AuditRecord entry) async {
    try {
      await _db.into(_db.auditEntry).insert(AuditEntryCompanion.insert(
            at: entry.at,
            who: entry.who,
            station: entry.station,
            roleName: entry.roleName,
            surface: entry.surface,
            itemKey: entry.itemKey,
            member: Value(entry.member),
            oldValue: Value(entry.oldValue),
            newValue: Value(entry.newValue),
            groupRequired: entry.groupRequired,
            allowed: entry.allowed,
            origin: Value(entry.origin),
            actionId: entry.actionId,
            reason: Value(entry.reason),
          ));
    } catch (e, stackTrace) {
      _logger.e(
        'AUDIT ROW LOST: this action happened and the trail does not have it. '
        'actionId=${entry.actionId} who=${entry.who} '
        'itemKey=${entry.itemKey} surface=${entry.surface} '
        'station=${entry.station} allowed=${entry.allowed}. '
        'The write itself was not affected — only its record. '
        'If these lines are frequent the database is the fault to chase, '
        'because the trail is incomplete for as long as they continue.',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
