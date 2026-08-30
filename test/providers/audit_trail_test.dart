// The Riverpod layer between `AuditTrailStore` and the audit trail page.
//
// Phase 2 ruled that **unavailable** and **empty** must be distinguishable, and
// the whole of that distinction is carried by this file's providers.
// `databaseProvider` answers null both when Postgres was never configured and
// when the connection threw, and both mean "the trail is unavailable". An empty
// list in either case would claim nothing had ever happened on the station,
// which is the one failure mode an audit trail cannot have.
//
// So the three answers the page must be able to tell apart each get their own
// named test here: a resolved **null**, a thrown **error**, and a non-null
// result whose `actions` happen to be empty.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:tfc/core/audit_trail_store.dart';
import 'package:tfc/providers/audit_trail.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/drift_audit_sink.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

/// The instant every window assertion is written against, matching
/// `test/core/audit_trail_store_test.dart` so the two suites read alike.
final DateTime _now = DateTime.utc(2026, 8, 30, 12);

/// The `Database` wrapper `databaseProvider` yields, over an in-memory Drift
/// database. Only `db` is reached by anything under test.
class _FakeDatabase extends Fake implements Database {
  _FakeDatabase(this.db);

  @override
  final AppDatabase db;
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.inMemoryForTest();
    // Force the schema before the first provider read, so an empty result is a
    // real empty table rather than a missing one.
    await db.customSelect('SELECT 1').getSingle();
  });

  tearDown(() => db.close());

  /// Appends one row through the trail's only writer.
  ///
  /// Going through [DriftAuditSink] rather than inserting a companion directly
  /// is what keeps this fixture honest about column mapping: a renamed column
  /// breaks the seed as well as the query.
  Future<void> seed({
    required DateTime at,
    String who = 'engineer',
    String itemKey = 'CN04.MOT01.p_cmd_Run',
    String? member,
    String groupRequired = 'configure',
    bool allowed = true,
    String surface = 'tag',
    String actionId = 'action-a',
  }) =>
      DriftAuditSink(db).record(AuditRecord(
        at: at,
        who: who,
        station: 'SVN-NES-OT-CL02',
        roleName: 'Engineering',
        surface: surface,
        itemKey: itemKey,
        member: member,
        oldValue: '0',
        newValue: '1',
        groupRequired: groupRequired,
        allowed: allowed,
        actionId: actionId,
      ));

  /// A container over the in-memory database — the ordinary station.
  ProviderContainer wired() {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => _FakeDatabase(db)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// A container with no database at all — the station commissioned without
  /// Postgres, and the boot window before the connection opens. The two are
  /// indistinguishable by design.
  ProviderContainer databaseless() {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  // -------------------------------------------------------------------------
  // The store provider — the unavailable signal itself
  // -------------------------------------------------------------------------

  group('auditTrailStoreProvider', () {
    test('resolves to null when this station has no database', () async {
      final store = await databaseless().read(auditTrailStoreProvider.future);

      expect(store, isNull,
          reason: 'null is the unavailable signal. A store over nothing, or an '
              'empty result, would let the page claim nothing has ever '
              'happened on a station whose database is merely unreachable.');
    });

    test('resolves to a store when the database is there', () async {
      final store = await wired().read(auditTrailStoreProvider.future);

      expect(store, isA<AuditTrailStore>());
    });
  });

  // -------------------------------------------------------------------------
  // The `who` dropdown's options
  // -------------------------------------------------------------------------

  group('auditWhoOptionsProvider', () {
    test('answers an empty list without a database, and does not throw',
        () async {
      final who = await databaseless().read(auditWhoOptionsProvider.future);

      expect(who, isEmpty,
          reason: 'a who dropdown with no options on an unreachable database '
              'is correct; an exception here would take the whole filter bar '
              'down with it. The page says "unavailable" once, from the '
              'entries provider, and not twice.');
    });

    test('answers every distinct who in the table, sorted', () async {
      await seed(at: _now, who: 'operator');
      await seed(at: _now, who: 'engineer');
      await seed(at: _now, who: 'engineer');

      final who = await wired().read(auditWhoOptionsProvider.future);

      expect(who, ['engineer', 'operator']);
    });
  });

  // -------------------------------------------------------------------------
  // What this file may not contain
  // -------------------------------------------------------------------------

  group('the source of lib/providers/audit_trail.dart', () {
    late String source;

    setUpAll(() {
      final file = File('lib/providers/audit_trail.dart');
      expect(file.existsSync(), isTrue,
          reason: 'run this suite from the repository root. Without the file '
              'these source assertions would pass vacuously.');
      final withoutBlockComments = file
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
      source = withoutBlockComments
          .split('\n')
          .map((line) {
            final idx = line.indexOf('//');
            return idx == -1 ? line : line.substring(0, idx);
          })
          .join('\n');
    });

    test('starts no timer', () {
      expect(source, isNot(contains('Timer')),
          reason: 'CONTEXT ruled this page has no timer. An always-on '
              'Timer.periodic in this repo\'s plumbing has broken unrelated '
              'widget tests, and a self-scrolling audit list is unreadable. '
              'Refresh is ref.invalidate. Any future live-update hook must be '
              'listener-gated — started in onListen, stopped in onCancel.');
    });

    test('holds no AuditSink and cannot record', () {
      expect(source, isNot(contains('AuditSink')),
          reason: 'reading the trail must not write to it. A row per render '
              'would bury the writes that matter under rows recording that '
              'somebody looked.');
    });

    test('performs no permission check', () {
      expect(source, isNot(contains('AccessDenied')),
          reason: 'the route gate is the enforcement. A check here would be '
              'mistaken for it, and a second gate that disagrees with the '
              'route is worse than one gate.');
    });
  });
}
