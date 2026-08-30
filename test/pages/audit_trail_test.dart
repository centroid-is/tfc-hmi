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


/// A host whose `setState` rebuilds [AuditTrailBody] without replacing its
/// `State`.
///
/// A bare `tester.pump()` does not rebuild a widget whose own state has not
/// changed, so a stability test written that way passes identically under the
/// correct and the defective design. This host makes the rebuild happen for
/// real.
class _RebuildHost extends StatefulWidget {
  const _RebuildHost();

  @override
  State<_RebuildHost> createState() => _RebuildHostState();
}

class _RebuildHostState extends State<_RebuildHost> {
  /// Forces one more `AuditTrailBody.build`.
  void bump() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // Deliberately not `const`, and deliberately unkeyed. Flutter short-circuits
    // a child's rebuild when the new widget is `identical` to the old one, so a
    // const instance would make this host inert; a *changing* key would go the
    // other way and replace the `State` outright, which would legitimately
    // issue a second query and hide the defect behind a false positive.
    // ignore: prefer_const_constructors
    return AuditTrailBody();
  }
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
  Widget child = const AuditTrailBody(),
}) async {
  final (light, _) = muted();

  final app = ProviderScope(
    overrides: [
      auditTrailStoreProvider.overrideWith((ref) async => store),
    ],
    child: MaterialApp(
      theme: light,
      home: Scaffold(body: child),
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

  // -------------------------------------------------------------------------
  // Task 2 — the list, the filter wiring, and the search that escapes the
  // window
  // -------------------------------------------------------------------------

  group('AuditTrailBody — the opening query', () {
    testWidgets('spans exactly seven days back from now and asks for 500 rows',
        (tester) async {
      final store = _FakeStore(answer: (_) => _rows(3));
      await _pumpBody(tester, store: store);

      expect(store.recorded, hasLength(1));
      final window = store.recorded.single.window;
      expect(window, isNotNull);
      expect(
        window!.end.difference(window.start),
        const Duration(days: 7),
        reason: 'the default is the last seven days, capped at 500 rows — '
            'whichever bound is reached first',
      );
      expect(window.end, _now);
      expect(store.recorded.single.limit, kAuditTrailRowLimit);
    });

    testWidgets('is issued on arrival, without waiting for a filter change',
        (tester) async {
      final store = _FakeStore(answer: (_) => _rows(1));
      await _pumpBody(tester, store: store);
      expect(store.recorded, isNotEmpty);
    });

    testWidgets('excludes operate and says so on screen', (tester) async {
      final store = _FakeStore(answer: (_) => _rows(1));
      await _pumpBody(tester, store: store);

      expect(store.recorded.single.groupNames, isNot(contains('operate')));
      expect(find.text(kAuditTrailOperateNote), findsOneWidget);
    });
  });

  group('AuditTrailBody — the search that reaches the whole table', () {
    testWidgets('a typed key prefix drops the time bound entirely',
        (tester) async {
      final store = _FakeStore(answer: (_) => _rows(2));
      await _pumpBody(tester, store: store);

      await tester.enterText(find.byType(TextField), 'CN04');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final issued = store.recorded.last;
      expect(issued.keyPrefix, 'CN04');
      expect(
        issued.window,
        isNull,
        reason: 'searching must answer "has anyone ever written this key", '
            'not "did anyone this week" — a search that silently covered only '
            'the default window would be a wrong answer that looks like a '
            'right one',
      );
      expect(
        issued.limit,
        kAuditTrailRowLimit,
        reason: 'the search escapes the time bound and never the row cap',
      );
    });

    testWidgets('a chosen who drops the time bound too', (tester) async {
      final store = _FakeStore(answer: (_) => _rows(2), whoOptions: ['jon']);
      await _pumpBody(tester, store: store);

      await tester.tap(find.byKey(kAuditTrailWhoDropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('jon').last);
      await tester.pumpAndSettle();

      final issued = store.recorded.last;
      expect(issued.who, 'jon');
      expect(issued.window, isNull);
      expect(issued.limit, kAuditTrailRowLimit);
    });
  });

  group('AuditTrailBody — query stability', () {
    testWidgets('two rebuilds that change no filter issue one query, not three',
        (tester) async {
      // T-05-67, which is T-05-21 at the page layer. `clock.now()` called
      // inside `build` moves `window.end` forward on every frame, so
      // `AuditQuery ==` goes false, the autoDispose family swaps instances and
      // the page hits the database on every frame it paints.
      //
      // **The clock has to be made to move, and simply omitting `withClock` is
      // not enough.** `testWidgets` runs its body inside `package:fake_async`,
      // and `FakeAsync` installs its own `clock` — so inside a widget test the
      // "live" clock is frozen exactly as hard as a `Clock.fixed` one, and it
      // advances only when a pump is given a duration. A version of this test
      // that bumped and then called a bare `tester.pump()` passes with
      // `clock.now()` sitting in the middle of `build`, which was verified by
      // putting it there. Every rebuild below therefore elapses real fake-time,
      // which is what gives the defective design a distinct `now` to be caught
      // with.
      final store = _FakeStore(answer: (_) => _rows(2));
      await _pumpBody(
        tester,
        store: store,
        freezeClock: false,
        child: const _RebuildHost(),
      );

      final host = tester.state<_RebuildHostState>(find.byType(_RebuildHost));
      host.bump();
      await tester.pump(const Duration(seconds: 1));
      host.bump();
      await tester.pump(const Duration(seconds: 1));

      final body =
          tester.state<AuditTrailBodyState>(find.byType(AuditTrailBody));
      expect(
        body.buildCount,
        greaterThanOrEqualTo(3),
        reason: 'a stability test that failed to trigger any rebuild would '
            'pass vacuously',
      );
      expect(
        store.recorded,
        hasLength(1),
        reason: 'the resolved AuditQuery lives in State; a rebuild that '
            'changes no filter must watch the identical value and cost no '
            'round trip (T-05-67)',
      );
    });

    testWidgets('the window it opened with does not drift as time passes',
        (tester) async {
      // The sibling of the test above, stated as the operator sees it: the
      // seven days on screen are the seven days the page opened with, and they
      // do not slide out from under a row while it is being read.
      final store = _FakeStore(answer: (_) => _rows(2));
      await _pumpBody(
        tester,
        store: store,
        freezeClock: false,
        child: const _RebuildHost(),
      );
      final opened = store.recorded.single.window!.end;

      final host = tester.state<_RebuildHostState>(find.byType(_RebuildHost));
      host.bump();
      await tester.pump(const Duration(minutes: 5));

      expect(store.recorded.single.window!.end, opened);
    });
  });

  group('AuditTrailBody — the list', () {
    testWidgets('virtualises: a 500-action result builds far fewer tiles',
        (tester) async {
      final store = _FakeStore(answer: (_) => _rows(kAuditTrailRowLimit));
      await _pumpBody(tester, store: store);

      final built = tester
          .widgetList<AuditActionTile>(
            find.byType(AuditActionTile, skipOffstage: false),
          )
          .length;
      expect(
        built,
        lessThan(50),
        reason: 'building 500 expandable tiles in one frame is T-05-64',
      );
      expect(built, greaterThan(0));
    });

    testWidgets('uses no itemExtent — the tiles expand', (tester) async {
      final store = _FakeStore(answer: (_) => _rows(3));
      await _pumpBody(tester, store: store);

      final list = tester.widget<ListView>(find.byKey(kAuditTrailListKey));
      expect(list.itemExtent, isNull);
      expect(list.prototypeItem, isNull);
    });
  });

  group('AuditTrailBody — the result line', () {
    testWidgets('states the row count and the window it counted over',
        (tester) async {
      final store = _FakeStore(answer: (_) => _rows(3));
      await _pumpBody(tester, store: store);

      expect(
        find.text(auditTrailResultSummary(
          count: 3,
          filters: const AuditTrailFilters(),
        )),
        findsOneWidget,
        reason: 'a count without the window that produced it is a number '
            'somebody will quote',
      );
    });

    testWidgets('says All time once the query escaped the seven-day bound',
        (tester) async {
      final store = _FakeStore(answer: (_) => _rows(2));
      await _pumpBody(tester, store: store);

      await tester.enterText(find.byType(TextField), 'CN04');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.textContaining(kAuditTrailWholeTableLabel), findsOneWidget);
    });
  });

  group('AuditTrailBody — the row cap', () {
    testWidgets('says it is showing the newest 500 when the cap was reached',
        (tester) async {
      final store = _FakeStore(answer: (_) => _rows(kAuditTrailRowLimit));
      await _pumpBody(tester, store: store);
      expect(find.byKey(kAuditTrailLimitNoteKey), findsOneWidget);
      expect(find.text(kAuditTrailLimitNote), findsOneWidget);
    });

    testWidgets('says nothing of the sort on a short result', (tester) async {
      final store = _FakeStore(answer: (_) => _rows(3));
      await _pumpBody(tester, store: store);
      expect(find.byKey(kAuditTrailLimitNoteKey), findsNothing);
    });
  });

  group('AuditTrailBody — nothing is filtered in memory', () {
    test('the page holds no client-side filter or sort', () {
      // Every filter is pushed into SQL and applied in `WHERE` before `LIMIT`.
      // Filtering the already-loaded rows would show three denials while the
      // table held three hundred.
      final source = _pageSourceWithoutComments();
      expect(source, isNot(contains('.where(')));
      expect(source, isNot(contains('.sort(')));
    });
  });
}
