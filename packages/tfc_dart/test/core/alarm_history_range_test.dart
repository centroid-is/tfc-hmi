import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/alarm.dart' show alarmHistoryOverlaps;
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

/// Against real sqlite rather than by inspecting the built expression: the
/// thing that can go wrong here is SQL — operator precedence between the AND
/// and the OR, and whether `IS NULL` survives being combined with a
/// comparison. Only the database can answer either.
class _Db extends AppDatabase {
  _Db() : super.forTest(DatabaseConfig(), NativeDatabase.memory());
}

/// A executor that only claims to be Postgres, so a statement can be built
/// for that dialect without a server to send it to.
class _PostgresDialect extends QueryExecutor {
  final statements = <String>[];

  @override
  SqlDialect get dialect => SqlDialect.postgres;

  @override
  Future<List<Map<String, Object?>>> runSelect(
      String statement, List<Object?> args) async {
    statements.add(statement);
    return const [];
  }

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;
  @override
  Future<void> close() async {}
  @override
  TransactionExecutor beginTransaction() => throw UnimplementedError();
  @override
  QueryExecutor beginExclusive() => throw UnimplementedError();
  @override
  Future<void> runBatched(BatchedStatements statements) async {}
  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async {}
  @override
  Future<int> runDelete(String statement, List<Object?> args) async => 0;
  @override
  Future<int> runInsert(String statement, List<Object?> args) async => 0;
  @override
  Future<int> runUpdate(String statement, List<Object?> args) async => 0;
}

final day = DateTime.utc(2026, 8, 29);
DateTime at(int hour, [int minute = 0]) =>
    day.add(Duration(hours: hour, minutes: minute));

void main() {
  late _Db db;

  setUp(() => db = _Db());
  tearDown(() => db.close());

  Future<void> activation(String uid, DateTime start, DateTime? end) {
    return db.into(db.alarmHistory).insert(AlarmHistoryCompanion.insert(
          alarmUid: uid,
          alarmTitle: uid,
          alarmDescription: uid,
          alarmLevel: 'error',
          expression: const Value('a'),
          active: false,
          pendingAck: false,
          createdAt: start,
          deactivatedAt: Value(end),
        ));
  }

  Future<List<String>> inWindow({DateTime? from, DateTime? to}) async {
    final query = db.select(db.alarmHistory)
      ..where((t) => alarmHistoryOverlaps(t, from: from, to: to));
    final rows = await query.get();
    return rows.map((r) => r.alarmUid).toList()..sort();
  }

  setUp(() async {
    // A shift window of 08:00–16:00 is the one every case is judged against.
    await activation('before', at(2), at(4)); // entirely before
    await activation('straddles-start', at(6), at(9)); // in over the left edge
    await activation('inside', at(10), at(11));
    await activation('straddles-end', at(15), at(18)); // out over the right
    await activation('after', at(20), at(22)); // entirely after
    await activation('spans-whole', at(1), at(23)); // longer than the window
    await activation('standing', at(7), null); // never cleared
    await activation('standing-later', at(19), null); // started after the end
  });

  test('an unbounded query still returns everything', () async {
    expect(await inWindow(), hasLength(8));
  });

  test('a window keeps every activation that overlaps it', () async {
    expect(
      await inWindow(from: at(8), to: at(16)),
      ['inside', 'spans-whole', 'standing', 'straddles-end', 'straddles-start'],
    );
  });

  test('activations wholly outside the window are dropped', () async {
    final kept = await inWindow(from: at(8), to: at(16));
    expect(kept, isNot(contains('before')));
    expect(kept, isNot(contains('after')));
    // Standing now, but it only went off after the window closed: it says
    // nothing about that shift.
    expect(kept, isNot(contains('standing-later')));
  });

  test('a standing alarm is never filtered out by the window end', () async {
    // The `IS NULL` branch must survive being ANDed with the created_at bound;
    // lose the parentheses and this query returns every standing alarm ever.
    expect(await inWindow(from: at(8), to: at(9)),
        ['spans-whole', 'standing', 'straddles-start']);
  });

  test('an open-ended window bounds only the side it names', () async {
    // Only `created_at` is bounded, so 06:00's activation is out even though
    // it was still standing at 05:00 — nothing had happened yet by then.
    expect(await inWindow(to: at(5)), ['before', 'spans-whole']);
    // Symmetrically, only `deactivated_at` is bounded here, so the one that
    // cleared at 18:00 is out.
    expect(
      await inWindow(from: at(19)),
      ['after', 'spans-whole', 'standing', 'standing-later'],
    );
  });

  /// The statement, not its results: drift rewrites datetime comparisons into
  /// `JULIANDAY(a) <op> JULIANDAY(b)` whenever datetimes are stored as text,
  /// and Postgres has no `julianday()`. The Downtime tab is the only caller
  /// that bounds the window, so it was the only screen that broke — with
  /// `42883: function julianday(text) does not exist` where the timeline
  /// should have been.
  ///
  /// test/integration/database_integration_test.dart runs the same query
  /// against a real server; this one fails without needing one.
  group('on the postgres dialect', () {
    Future<String> statementFor({DateTime? from, DateTime? to}) async {
      final executor = _PostgresDialect();
      final pg = AppDatabase.forTest(DatabaseConfig(), executor);
      await (pg.select(pg.alarmHistory)
            ..where((t) => alarmHistoryOverlaps(t, from: from, to: to)))
          .get();
      await pg.close();
      return executor.statements.single;
    }

    test('no bound is written as a julianday call', () async {
      expect(await statementFor(from: at(8), to: at(16)),
          isNot(contains('JULIANDAY')));
    });

    test('both sides of a bound are cast to timestamp', () async {
      // Neither side is one otherwise: drift declares these columns `text` on
      // Postgres, and binds a mapped datetime variable as `text` too, so
      // dropping either cast leaves a lexicographic string comparison.
      expect(
        await statementFor(from: at(8), to: at(16)),
        allOf(
          contains('"created_at"::timestamp <= \$1::timestamp'),
          contains('"deactivated_at"::timestamp >= \$2::timestamp'),
        ),
      );
    });

    test('a standing alarm still gets its IS NULL branch', () async {
      expect(await statementFor(from: at(8), to: at(16)),
          contains('"deactivated_at" IS NULL OR'));
    });
  });
}
