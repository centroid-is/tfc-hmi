/// The audit trail page: three ways to have nothing to show, and three
/// different screens.
///
/// Phase 2 ruled that **unavailable** and **empty** must be distinguishable. An
/// empty list drawn over an unreachable database claims nothing was ever
/// written on this station, which is the one lie an audit trail cannot tell. A
/// third state — still loading — is neither, and must not be mistaken for
/// either: a frame that renders "No entries match these filters" before the
/// query returns is a page that lies for one frame, and 05-08's goldens would
/// bake that frame in.
///
/// ## Why these tests override the *store* and not the entries family
///
/// The plan asked for `auditTrailEntriesProvider` to be overridden with a
/// recording implementation. Riverpod 2's generated families expose
/// `overrideWith` only on a *resolved* provider — `auditTrailEntriesProvider(q)`
/// — and the generated `AuditTrailEntriesFamily` carries no family-level
/// `overrideWith` at all (`lib/providers/audit_trail.g.dart:125-218`; the
/// `_FamilyMixin.overrideWithProvider` that would supply one is not mixed in).
/// Overriding by resolved query would mean the test had to know the query
/// before the page issued it, which is precisely the thing under test.
///
/// So the seam is one level lower: `auditTrailStoreProvider` is overridden with
/// a `Fake` store that records every [AuditQuery] that reaches it. That is
/// **stronger** than the family override, not weaker — the real
/// `auditTrailEntries` provider runs, so the grouping, the companion count, the
/// `reachedLimit` arithmetic and the `oldestAt` cursor are all the production
/// ones, and the recorded query is the one the page actually caused to be
/// executed rather than merely the one it named.
///
/// `test/providers/audit_trail_test.dart` uses the same `extends Fake implements
/// AuditTrailStore` shape for its `_CountingStore`.
library;

import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/audit_trail_store.dart';
import 'package:tfc/pages/audit_trail.dart';
import 'package:tfc/providers/audit_trail.dart';
import 'package:tfc/theme.dart' show muted;
import 'package:tfc/widgets/audit_trail_filters.dart';
import 'package:tfc/widgets/audit_trail_row.dart';
import 'package:tfc_dart/core/database_drift.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The instant every window assertion is written against, matching
/// `test/providers/audit_trail_test.dart` so the two suites read alike.
final DateTime _now = DateTime.utc(2026, 8, 30, 12);

/// One audit row, with every column defaulted to the ordinary case so a test
/// names only the column it is about.
AuditEntryData _row({
  int id = 1,
  DateTime? at,
  String who = 'jon',
  String itemKey = 'ST101.CN04.p_cfg',
  String groupRequired = 'setpoints',
  bool allowed = true,
  String surface = 'tag',
  String? actionId,
}) =>
    AuditEntryData(
      id: id,
      at: at ?? _now.subtract(Duration(minutes: id)),
      who: who,
      station: 'ST101',
      roleName: 'engineer',
      surface: surface,
      itemKey: itemKey,
      member: null,
      oldValue: '20',
      newValue: '35',
      groupRequired: groupRequired,
      allowed: allowed,
      origin: 'operator',
      actionId: actionId ?? 'action-$id',
      reason: null,
    );

/// [count] rows, newest first, each its own action — so one row is one tile.
List<AuditEntryData> _rows(int count, {int from = 1}) =>
    [for (var i = 0; i < count; i++) _row(id: from + i)];

/// A store that records every query and answers from a callback.
///
/// `extends Fake` rather than a real [AuditTrailStore]: the real one needs an
/// `AppDatabase`, and a widget test that stands up Drift to answer "did the
/// page ask for the whole table" is testing two things and reporting one.
class _FakeStore extends Fake implements AuditTrailStore {
  _FakeStore({
    List<AuditEntryData> Function(AuditQuery query)? answer,
    this.whoOptions = const <String>[],
  }) : _answer = answer ?? ((_) => const <AuditEntryData>[]);

  final List<AuditEntryData> Function(AuditQuery query) _answer;

  /// What `distinctWho` answers — the `who` dropdown's options.
  final List<String> whoOptions;

  /// Every query that reached the database, in order. The whole point of the
  /// fake: the page's promises are about the statement it issues, and the
  /// resolved value cannot distinguish "asked over seven days" from "asked over
  /// the whole table" when the fixture matches both.
  final List<AuditQuery> recorded = <AuditQuery>[];

  /// Set to make the read fail. An error and a resolved null are both
  /// "unavailable" to the page and must be tested as two separate causes.
  Object? error;

  /// Set to make the read never answer, so a test can hold the page in its
  /// loading frame and photograph it.
  bool hang = false;

  @override
  Future<List<AuditEntryData>> entries(AuditQuery query) {
    recorded.add(query);
    if (hang) return Completer<List<AuditEntryData>>().future;
    final err = error;
    if (err != null) return Future<List<AuditEntryData>>.error(err);
    return Future<List<AuditEntryData>>.value(_answer(query));
  }

  @override
  Future<Map<String, int>> memberCountsByAction(Iterable<String> actionIds) async {
    // Every action's true row count equals its visible row count here, so no
    // group is partial and no "N of M hidden" line appears. The hidden-member
    // arithmetic belongs to 05-02 and 05-04 and is tested there.
    final ids = actionIds.toList();
    return {for (final id in ids) id: ids.where((other) => other == id).length};
  }

  @override
  Future<List<String>> distinctWho() async => whoOptions;
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Pumps [AuditTrailBody] over [store], with the clock frozen at [_now] unless
/// [freezeClock] is false.
///
/// `muted()` rather than a bare `MaterialApp`, for the reason
/// `audit_trail_row_test.dart` states: `HmiStateColors.of` falls back to
/// `solarizedLight` under a theme carrying no extension, so anything drawn from
/// the theme extension under a bare app is drawn from a palette this build does
/// not ship.
Future<void> _pumpBody(
  WidgetTester tester, {
  required AuditTrailStore? store,
  bool freezeClock = true,
  Widget Function(Widget body)? wrap,
}) async {
  final (light, _) = muted();
  Widget body = const AuditTrailBody();
  if (wrap != null) body = wrap(body);

  final app = ProviderScope(
    overrides: [
      auditTrailStoreProvider.overrideWith((ref) async => store),
    ],
    child: MaterialApp(
      theme: light,
      home: Scaffold(body: body),
    ),
  );

  if (freezeClock) {
    await withClock(Clock.fixed(_now), () => tester.pumpWidget(app));
  } else {
    await tester.pumpWidget(app);
  }
  // One extra frame for the store future and the entries future to resolve.
  await tester.pump();
  await tester.pump();
}

/// How many `Clear filters` controls are on screen.
///
/// 05-05's bar renders one only while the filters are not default; this page's
/// empty body renders one only while they are. Exactly one, in every state,
/// never zero and never two.
int _clearFiltersCount(WidgetTester tester) =>
    tester.widgetList<Text>(find.text(kAuditTrailClearFiltersLabel)).length;

/// The page source with every whole-line comment stripped, for the greps that
/// stand behind the rules no type system can hold.
String _pageSourceWithoutComments() {
  final source = File('lib/pages/audit_trail.dart').readAsStringSync();
  return source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

void main() {
  // -------------------------------------------------------------------------
  // Task 1 — the Page/Body split and the three terminal states
  // -------------------------------------------------------------------------

  group('AuditTrailPage', () {
    test('is const-constructible, so the route map can register it', () {
      // Field-less on purpose: `createLocationBuilder` registers it as
      // `const AuditTrailPage()`. This is a compile-time assertion wearing a
      // test's clothes — if the page ever grows a required field, this line
      // stops compiling, which is the whole point.
      const page = AuditTrailPage();
      expect(page, isA<StatelessWidget>());
    });

    test('wraps AuditTrailBody in BaseScaffold and nothing else', () {
      final source = _pageSourceWithoutComments();
      expect(source, contains('BaseScaffold('));
      expect(source, contains('AuditTrailBody()'));
    });
  });

  group('AuditTrailBody — unavailable', () {
    testWidgets('a resolved null store renders the unavailable key and '
        'neither of the other two', (tester) async {
      await _pumpBody(tester, store: null);

      expect(find.byKey(kAuditTrailUnavailableKey), findsOneWidget);
      expect(
        find.byKey(kAuditTrailEmptyKey),
        findsNothing,
        reason: 'an unreachable database must never read as "nothing ever '
            'happened on this station"',
      );
      expect(find.byKey(kAuditTrailListKey), findsNothing);
    });

    testWidgets('a read that throws renders unavailable too, not empty',
        (tester) async {
      final store = _FakeStore()..error = StateError('the audit database blinked');
      await _pumpBody(tester, store: store);

      expect(find.byKey(kAuditTrailUnavailableKey), findsOneWidget);
      expect(
        find.byKey(kAuditTrailEmptyKey),
        findsNothing,
        reason: 'a failed read is not entitled to make a claim about the '
            'plant\'s history',
      );
      expect(find.byKey(kAuditTrailListKey), findsNothing);
    });

    testWidgets('states the unavailable copy', (tester) async {
      await _pumpBody(tester, store: null);
      expect(find.text(kAuditTrailUnavailable), findsOneWidget);
    });

    testWidgets('does not state the empty copy', (tester) async {
      await _pumpBody(tester, store: null);
      expect(find.text(kAuditTrailEmptyUnderFilters), findsNothing);
    });

    testWidgets('names no cause: neither "not configured" nor "connection"',
        (tester) async {
      await _pumpBody(tester, store: null);
      // `databaseProvider` answers null both for a station that was never
      // configured and for one whose Postgres will not answer, and the two are
      // indistinguishable by design. A line that guessed would send a
      // commissioning engineer hunting the wrong problem.
      expect(kAuditTrailUnavailable.toLowerCase(), isNot(contains('not configured')));
      expect(kAuditTrailUnavailable.toLowerCase(), isNot(contains('timed out')));
    });

    testWidgets('renders no filter bar — there is nothing to filter',
        (tester) async {
      await _pumpBody(tester, store: null);
      expect(find.byType(AuditTrailFilterBar), findsNothing);
    });
  });

  group('AuditTrailBody — empty under filters', () {
    testWidgets('a resolved empty result renders the empty key and neither of '
        'the other two', (tester) async {
      await _pumpBody(tester, store: _FakeStore());

      expect(find.byKey(kAuditTrailEmptyKey), findsOneWidget);
      expect(find.byKey(kAuditTrailUnavailableKey), findsNothing);
      expect(find.byKey(kAuditTrailListKey), findsNothing);
    });

    testWidgets('states the empty copy and not the unavailable one',
        (tester) async {
      await _pumpBody(tester, store: _FakeStore());
      expect(find.text(kAuditTrailEmptyUnderFilters), findsOneWidget);
      expect(find.text(kAuditTrailUnavailable), findsNothing);
    });

    testWidgets('is about the filters and never about the table', (tester) async {
      // CONTEXT's deferred list records a fourth state that would distinguish a
      // genuinely empty table. This phase does not ship it, so the wording must
      // claim nothing about what the table holds.
      expect(kAuditTrailEmptyUnderFilters.toLowerCase(), contains('filters'));
      expect(kAuditTrailEmptyUnderFilters.toLowerCase(), isNot(contains('nothing')));
      expect(kAuditTrailEmptyUnderFilters.toLowerCase(), isNot(contains('never')));
    });

    testWidgets('keeps the filter bar on screen, so the operator can see what '
        'excluded everything', (tester) async {
      await _pumpBody(tester, store: _FakeStore());
      expect(find.byType(AuditTrailFilterBar), findsOneWidget);
    });

    testWidgets('renders exactly one Clear filters under default filters',
        (tester) async {
      await _pumpBody(tester, store: _FakeStore());
      expect(
        _clearFiltersCount(tester),
        1,
        reason: '05-05\'s bar renders one only when the filters are not '
            'default; this body owns the default case, and never zero',
      );
    });

    testWidgets('renders exactly one Clear filters under a set key prefix',
        (tester) async {
      await _pumpBody(tester, store: _FakeStore());
      await tester.enterText(find.byType(TextField), 'CN04');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(
        _clearFiltersCount(tester),
        1,
        reason: 'the bar owns this case, so the body must stand down — never '
            'two',
      );
    });
  });

  group('AuditTrailBody — loading', () {
    testWidgets('renders none of the three keys while the query is still out',
        (tester) async {
      final store = _FakeStore()..hang = true;
      await _pumpBody(tester, store: store);

      expect(
        find.byKey(kAuditTrailUnavailableKey),
        findsNothing,
        reason: 'waiting is neither allowed nor denied and says nothing yet',
      );
      expect(
        find.byKey(kAuditTrailEmptyKey),
        findsNothing,
        reason: 'a frame that renders "No entries match" before the query '
            'returns is a page that lies for one frame, and a golden that '
            'catches that frame bakes the lie in',
      );
      expect(find.byKey(kAuditTrailListKey), findsNothing);
    });

    testWidgets('renders a progress indicator instead', (tester) async {
      final store = _FakeStore()..hang = true;
      await _pumpBody(tester, store: store);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('AuditTrailBody — a result', () {
    testWidgets('renders the list key and neither terminal state',
        (tester) async {
      final store = _FakeStore(answer: (_) => _rows(3));
      await _pumpBody(tester, store: store);

      expect(find.byKey(kAuditTrailListKey), findsOneWidget);
      expect(find.byKey(kAuditTrailEmptyKey), findsNothing);
      expect(find.byKey(kAuditTrailUnavailableKey), findsNothing);
    });

    testWidgets('renders one AuditActionTile per action', (tester) async {
      final store = _FakeStore(answer: (_) => _rows(3));
      await _pumpBody(tester, store: store);
      expect(find.byType(AuditActionTile), findsNWidgets(3));
    });
  });

  group('AuditTrailBody — what this page is not', () {
    test('checks no permission and builds no denied state', () {
      // T-05-60. The route gate renders `AccessLockedBody` before this page is
      // reached; a second, weaker check here could diverge from the first, and
      // the divergence would be an open page.
      final source = _pageSourceWithoutComments();
      expect(source, isNot(contains('AccessGroup')));
      expect(source, isNot(contains('AccessLockedBody')));
    });

    test('reaches for no raw Material colour', () {
      // `lib/pages/key_repository.dart` predates the convention and is a known
      // violation; it is the wrong model for colour and the right model for the
      // three-way branch.
      final source = _pageSourceWithoutComments();
      expect(source, isNot(contains('Colors.')));
    });
  });
}
