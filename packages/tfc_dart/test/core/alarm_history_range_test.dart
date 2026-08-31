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
}
