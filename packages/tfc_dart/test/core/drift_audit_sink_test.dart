// The append-only audit writer.
//
// Every assertion here is about a row landing, intact, exactly once — and
// about the sink never being the reason a caller falls over. Both halves
// matter: an audit row that is silently absent is the one defect nobody ever
// notices, and an audit write that throws into a login flow turns a database
// hiccup into an operator who cannot sign in.

import 'dart:io';

import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/drift_audit_sink.dart';
import 'package:tfc_dart/core/database_drift.dart' show AppDatabase;

/// Captures what a [Logger] emitted, with its level, instead of printing it.
class _CapturingOutput extends LogOutput {
  final List<OutputEvent> events = [];

  @override
  void output(OutputEvent event) => events.add(event);

  /// Every line emitted at [level], ANSI stripped and joined.
  String at(Level level) => events
      .where((e) => e.level == level)
      .expand((e) => e.lines)
      .join('\n')
      .replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
}

/// A logger that records instead of printing.
///
/// [ProductionFilter] rather than the default: the default filter is
/// debug-mode-gated, and a suite whose assertions depend on whether asserts
/// happen to be enabled is a suite that passes for the wrong reason.
Logger _capturing(_CapturingOutput out) =>
    Logger(output: out, filter: ProductionFilter(), level: Level.trace);

/// The sink's own source, with comments removed.
///
/// The comment removal is what makes the "no delete/update" assertion honest:
/// otherwise the comment explaining why there is no delete would itself fail
/// the test that enforces it.
String sinkSourceWithoutComments() {
  final file = File('lib/core/access/drift_audit_sink.dart');
  expect(file.existsSync(), isTrue,
      reason: 'Run this suite from packages/tfc_dart. Without the file these '
          'source assertions would pass vacuously.');
  final withoutBlockComments =
      file.readAsStringSync().replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlockComments
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx == -1 ? line : line.substring(0, idx);
      })
      .join('\n');
}

/// Method names declared directly in a class body of [source].
///
/// Matches `<return type> <name>(` at two-space indentation, which is what a
/// method looks like and what a constructor (no return type) and a field (no
/// parenthesis) do not.
List<String> declaredMethodNames(String source) {
  final decl =
      RegExp(r'^  (?:@override\s+)?([A-Za-z_][\w<>?, ]*?)\s+([a-zA-Z_]\w*)\s*\(');
  return source
      .split('\n')
      .map(decl.firstMatch)
      .where((m) => m != null)
      .map((m) => m!.group(2)!)
      .toList();
}

/// A fully populated record — every nullable column carries a value, so the
/// round-trip test asserts on all fourteen columns rather than on the ten
/// that are hard to get wrong.
AuditRecord _full({
  String actionId = 'act-1',
  bool allowed = true,
}) =>
    AuditRecord(
      at: DateTime.utc(2026, 8, 28, 14, 3, 17),
      who: 'gudrun',
      station: 'SVN-NES-OT-CL02',
      roleName: 'Engineering',
      surface: 'tag',
      itemKey: 'CN04.MOT01.HMI',
      member: 'p_cfg.Freq',
      oldValue: '25.0',
      newValue: '42.5',
      groupRequired: 'configure',
      allowed: allowed,
      origin: 'operator',
      actionId: actionId,
      reason: 'ramping the belt for the trial run',
    );

void main() {
  late AppDatabase db;
  late _CapturingOutput out;
  late DriftAuditSink sink;

  setUp(() {
    db = AppDatabase.inMemoryForTest();
    out = _CapturingOutput();
    sink = DriftAuditSink(db, logger: _capturing(out));
    addTearDown(() => db.close());
  });

  group('record() inserts', () {
    test('one record on an empty database is exactly one row', () async {
      await sink.record(_full());

      final rows = await db.select(db.auditEntry).get();
      expect(rows, hasLength(1));
    });

    test('every one of the fourteen columns round-trips', () async {
      final entry = _full();
      await sink.record(entry);

      final row = (await db.select(db.auditEntry).get()).single;
      expect(row.at.isAtSameMomentAs(entry.at), isTrue,
          reason: 'drift stores DateTime as unix seconds; the instant must '
              'survive even though the UTC flag does not.');
      expect(row.who, 'gudrun');
      expect(row.station, 'SVN-NES-OT-CL02');
      expect(row.roleName, 'Engineering');
      expect(row.surface, 'tag');
      expect(row.itemKey, 'CN04.MOT01.HMI');
      expect(row.member, 'p_cfg.Freq');
      expect(row.oldValue, '25.0');
      expect(row.newValue, '42.5');
      expect(row.groupRequired, 'configure');
      expect(row.allowed, isTrue);
      expect(row.origin, 'operator');
      expect(row.actionId, 'act-1');
      expect(row.reason, 'ramping the belt for the trial run');
    });

    test('null member, newValue and reason stay null', () async {
      // A logout row: nothing was written, so there is no member and no new
      // value, and no reason was prompted for.
      await sink.record(AuditRecord.logout(
        who: 'gudrun',
        station: 'SVN-NES-OT-CL02',
        roleName: 'Engineering',
        actionId: 'act-logout',
        at: DateTime.utc(2026, 8, 28, 15, 0, 0),
      ));

      final row = (await db.select(db.auditEntry).get()).single;
      expect(row.member, null);
      expect(row.newValue, null);
      expect(row.reason, null);
      expect(row.oldValue, 'Engineering',
          reason: 'logout repeats the role it left, so the trail reads as a '
              'transition without a join.');
    });

    test('a denial is stored as a row with allowed = false', () async {
      // The `allowed` column exists precisely so a refused action leaves a
      // row. A sink that dropped denials would make the trail lie by omission.
      await sink.record(_full(actionId: 'act-denied', allowed: false));

      final row = (await db.select(db.auditEntry).get()).single;
      expect(row.allowed, isFalse);
      expect(row.actionId, 'act-denied');
    });

    test('a failed login is stored, not dropped', () async {
      await sink.record(AuditRecord.loginFailed(
        who: 'gudrun',
        station: 'SVN-NES-OT-CL02',
        actionId: 'act-fail',
        at: DateTime.utc(2026, 8, 28, 15, 1, 0),
        reason: 'wrong password',
      ));

      final row = (await db.select(db.auditEntry).get()).single;
      expect(row.allowed, isFalse);
      expect(row.itemKey, 'login.failed');
      expect(row.roleName, kOperatorRoleName);
    });

    test('two records sharing an actionId produce two rows with that id',
        () async {
      // One recipe apply is one action with N member rows beneath it.
      await sink.record(_full(actionId: 'act-recipe'));
      await sink.record(_full(actionId: 'act-recipe'));

      final rows = await db.select(db.auditEntry).get();
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.actionId), everyElement('act-recipe'));
      expect(rows.map((r) => r.id).toSet(), hasLength(2),
          reason: 'Correlated rows are still distinct rows.');
    });

    test('origin defaults to operator when the record does not set it',
        () async {
      await sink.record(AuditRecord(
        at: DateTime.utc(2026, 8, 28, 16, 0, 0),
        who: 'gudrun',
        station: 'SVN-NES-OT-CL02',
        roleName: 'Engineering',
        surface: 'pref',
        itemKey: 'ui.theme',
        groupRequired: 'configure',
        allowed: true,
        actionId: 'act-pref',
      ));

      final row = (await db.select(db.auditEntry).get()).single;
      expect(row.origin, 'operator');
    });
  });

  group('record() cannot take the caller down', () {
    // How the database is broken here: it is closed before the call.
    //
    // `AppDatabase.forTest(config, executor)` exists for injecting a failing
    // executor, but a QueryExecutor stub has a wide surface and every member
    // of it would be a lie except the one that throws. A closed database is a
    // real drift failure mode produced by real drift code, and it is what the
    // sink meets when the app is shutting down while a logout is still being
    // written — exactly the moment an audit row matters most and is most
    // likely to be lost.
    Future<(DriftAuditSink, _CapturingOutput)> brokenSink() async {
      final broken = AppDatabase.inMemoryForTest();
      final brokenOut = _CapturingOutput();
      final s = DriftAuditSink(broken, logger: _capturing(brokenOut));
      await broken.close();
      return (s, brokenOut);
    }

    test('a broken database does not propagate an exception out of record()',
        () async {
      final (brokenSinkInstance, _) = await brokenSink();

      await expectLater(brokenSinkInstance.record(_full()), completes);
    });

    test(
        'the lost row is logged at error level, naming actionId, who and '
        'itemKey', () async {
      final (brokenSinkInstance, brokenOut) = await brokenSink();

      await brokenSinkInstance.record(_full(actionId: 'act-lost'));

      final logged = brokenOut.at(Level.error);
      expect(logged, isNotEmpty,
          reason: 'Swallowing without logging would make the sink the thing '
              'that hides its own failure.');
      expect(logged, contains('act-lost'));
      expect(logged, contains('gudrun'));
      expect(logged, contains('CN04.MOT01.HMI'));
      expect(logged.toLowerCase(), contains('lost'),
          reason: 'The line has to say a row was lost, in those words, or it '
              'reads as a retryable warning.');
    });

    test('nothing is logged at error level on the happy path', () async {
      await sink.record(_full());

      expect(out.at(Level.error), isEmpty,
          reason: 'A successful insert that logged an error would train '
              'everyone to ignore the line that matters.');
    });

    test('a later record still lands after an earlier one failed', () async {
      // The failure is per-call, not a latch: the sink does not disable itself
      // after one bad write.
      final (brokenSinkInstance, _) = await brokenSink();
      await brokenSinkInstance.record(_full());

      await sink.record(_full(actionId: 'act-after'));

      final rows = await db.select(db.auditEntry).get();
      expect(rows, hasLength(1));
      expect(rows.single.actionId, 'act-after');
    });
  });

  group('the sink is append-only by construction', () {
    // Asserted against the source text rather than by reflection: `dart:mirrors`
    // is not available to the test runner used here or to Flutter at all, and
    // an enumeration of members would in any case not stop somebody adding a
    // delete a week later — it would only report it. Reading the file is the
    // assertion that actually bites, because a sink with a delete method is
    // one refactor away from a swept trail.
    late String source;

    setUpAll(() {
      source = sinkSourceWithoutComments();
    });

    test('declares exactly one method: record', () {
      expect(declaredMethodNames(source), ['record'],
          reason: 'The public surface is one verb. Anything else here is a '
              'new way for the trail to be edited.');
    });

    test('contains no delete, update, prune, purge, truncate or clear', () {
      final offender = RegExp(
              r'\b(delete|update|prune|purge|truncate|clear)\w*',
              caseSensitive: false)
          .firstMatch(source);
      expect(offender?.group(0), null,
          reason: 'Append-only means those verbs are absent from the file, '
              'not merely uncalled today.');
    });

    test('writes through into(db.auditEntry).insert', () {
      expect(source, contains('auditEntry'));
      expect(source, contains('.insert('));
    });

    test('does not batch', () {
      // Batching is right for time-series, where a lost sample is a gap in a
      // chart. An audit row is the record that somebody did something, and a
      // flush timer that a crash discards is exactly the failure the trail
      // exists to survive.
      expect(source, isNot(contains('database_batch_insert')));
      expect(source, isNot(contains('tableInsertBatch')));
    });
  });

  group('NullAuditSink', () {
    test('completes and writes nothing', () async {
      await expectLater(NullAuditSink().record(_full()), completes);

      final rows = await db.select(db.auditEntry).get();
      expect(rows, isEmpty);
    });
  });
}
