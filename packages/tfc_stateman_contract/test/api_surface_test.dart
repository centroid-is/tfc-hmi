@TestOn('vm')
@Tags(['contract'])

/// The method table of the wire, written down.
///
/// This test exists to break the build on purpose. Every name below is a thing
/// a connected client may ask the gateway to do, so the set of names *is* the
/// access-control policy: capability is defined by surface. Adding a method to
/// `StateManApi` without editing this file fails; editing this file is the
/// deliberate act that says "yes, the wire may now do this too".
///
/// The expected sets are hand-written literals, never derived from the classes
/// they check. A set computed from the type would agree with any change and
/// assert nothing — the point is that a human reads a diff of these lines.
///
/// Two properties are enforced here:
///
///  * **Closure.** The five interfaces expose exactly these members. This is
///    where `query(String sql)` dies: a generic statement-taking method is a
///    name nobody wrote down, so it fails the set comparison before it can
///    ship, and no amount of gateway-side validation has to be trusted.
///  * **No secret retrieval.** No member of any of the five types declares a
///    parameter named `secret`. The concrete `Preferences` class
///    (`packages/tfc_dart/lib/core/preferences.dart:221+`) has exactly such a
///    parameter, routing reads to secure storage; mirroring it onto the wire
///    would make one client-supplied boolean into remote access to the secure
///    store (SEC-01).
///
/// `dart:mirrors` reflects the real type rather than its source text, and it
/// is available under `dart test` but not under `flutter test` — which is
/// another reason the interface package is pure Dart.
library;

import 'dart:mirrors';

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// The twelve members of the wire's primary interface.
///
/// Deliberately absent, each for a reason recorded in `state_man_api.dart`:
/// `writeStatus` (Phase 5 / WRT-02 must edit this line to add it),
/// `isKeyDisabled`, the four substitution members, and any health method —
/// `PIPE.*` keys are subscribed through `listen` like any plant tag.
const Set<String> expectedStateManApi = {
  'listen',
  'subscribe',
  'read',
  'readFresh',
  'readMany',
  'write',
  'keys',
  'browse',
  'timeseries',
  'historyViews',
  'preferences',
  'dispose',
};

/// Browse is three navigation calls plus path resolution — `resolvePath` is
/// required, not optional: without it the page editor opens the browse panel
/// on an already-bound value with nothing selected.
const Set<String> expectedBrowseApi = {
  'fetchRoots',
  'fetchChildren',
  'fetchDetail',
  'resolvePath',
};

/// Four named queries over a named series and a time range.
///
/// This set is the reason a client cannot make the database do arbitrary work:
/// every argument these four take is a value the gateway validates, and there
/// is no fifth method that takes a statement, an expression or a filter
/// string. A `query` method added here would be an unexpected name.
const Set<String> expectedTimeseriesApi = {
  'queryTimeseriesData',
  'queryTimeseriesDataMultiple',
  'queryTimeseriesDataDownsampled',
  'countTimeseriesDataMultiple',
};

/// The eleven history-view methods, names mirrored verbatim from the database
/// layer they will be served by.
const Set<String> expectedHistoryViewApi = {
  'createHistoryView',
  'updateHistoryView',
  'deleteHistoryView',
  'selectHistoryViews',
  'getHistoryViewKeys',
  'getHistoryViewGraphs',
  'getHistoryViewKeyNames',
  'addHistoryViewPeriod',
  'deleteHistoryViewPeriod',
  'listHistoryViewPeriods',
  'getGlobalRetentionHorizon',
};

/// The fifteen members of the preferences *interface*, plus the change
/// notification DB-03 needs. Nothing from the concrete class.
const Set<String> expectedPreferencesApi = {
  'getKeys',
  'getAll',
  'getBool',
  'getInt',
  'getDouble',
  'getString',
  'getStringList',
  'containsKey',
  'setBool',
  'setInt',
  'setDouble',
  'setString',
  'setStringList',
  'remove',
  'clear',
  'onPreferencesChanged',
};

/// Every type that is reachable from the wire, and its agreed table.
const Map<String, Set<String>> wireSurface = {
  'StateManApi': expectedStateManApi,
  'BrowseApi': expectedBrowseApi,
  'TimeseriesApi': expectedTimeseriesApi,
  'HistoryViewApi': expectedHistoryViewApi,
  'PreferencesApi': expectedPreferencesApi,
};

/// The types behind [wireSurface], in the same order.
const List<Type> wireTypes = [
  StateManApi,
  BrowseApi,
  TimeseriesApi,
  HistoryViewApi,
  PreferencesApi,
];

/// Every method, getter and setter reachable on [type], including inherited
/// ones.
///
/// Superinterfaces are walked, not just the class's own declarations. A member
/// arriving via `abstract interface class TimeseriesApi implements RawQueryApi`
/// is fully part of the wire surface and would otherwise be completely
/// invisible here — in a test whose entire job is to be the access-control
/// policy, which is exactly where `query(String sql)` would come in through
/// the side door.
///
/// Constructors and private members are excluded; a setter's trailing `=` is
/// stripped so `foo` and `foo=` do not read as two separate wire methods.
/// `Object`'s own members are not part of anybody's wire table, so the
/// superclass walk stops there.
Set<String> declaredMemberNames(Type type) =>
    _walkSurface(type, (m) => [MirrorSystem.getName(m.simpleName)])
        .map((name) =>
            name.endsWith('=') ? name.substring(0, name.length - 1) : name)
        .toSet();

/// Every parameter name declared anywhere on [type], inherited included — the
/// `secret:` check has the identical hole otherwise.
Iterable<String> declaredParameterNames(Type type) => _walkSurface(
    type, (m) => m.parameters.map((p) => MirrorSystem.getName(p.simpleName)));

/// Collects [read] over every public, non-constructor member of [type] and of
/// everything it inherits from.
Set<String> _walkSurface(
    Type type, Iterable<String> Function(MethodMirror) read) {
  final seen = <String>{};
  final visited = <ClassMirror>{};

  void walk(ClassMirror mirror) {
    if (!visited.add(mirror)) return;
    for (final member in mirror.declarations.values.whereType<MethodMirror>()) {
      if (member.isConstructor || member.isPrivate) continue;
      seen.addAll(read(member));
    }
    mirror.superinterfaces.forEach(walk);
    final parent = mirror.superclass;
    if (parent != null && parent.reflectedType != Object) walk(parent);
  }

  walk(reflectClass(type));
  return seen;
}

void main() {
  group('the wire surface is closed', () {
    for (var i = 0; i < wireTypes.length; i++) {
      final type = wireTypes[i];
      final name = wireSurface.keys.elementAt(i);
      final expected = wireSurface[name]!;

      test('$name exposes exactly the agreed method table', () {
        expect(declaredMemberNames(type), expected,
            reason: 'a new member on $name is a new thing every connected '
                'client may invoke, and a removed one silently breaks a '
                'deployed client that still calls it. Change this set only '
                'when that is the intent — this is also the reason '
                'query(sql) can never appear on the wire.');
      });
    }

    test('the whole surface is 47 members and nothing more', () {
      final actual = <String>{
        for (final type in wireTypes) ...declaredMemberNames(type),
      };
      final expected = <String>{
        for (final table in wireSurface.values) ...table,
      };
      expect(actual, expected,
          reason: 'the union is checked as well as the parts, so a member '
              'moved from one sub-interface to another still has to be a '
              'deliberate edit here');
      expect(actual, hasLength(47),
          reason: 'the count is written down so a same-size swap — one '
              'member removed, another added — cannot slip through as a '
              'coincidence');
    });
  });

  group('no secret material can be requested over the pipe', () {
    for (var i = 0; i < wireTypes.length; i++) {
      final type = wireTypes[i];
      final name = wireSurface.keys.elementAt(i);

      test('$name declares no parameter named secret', () {
        expect(declaredParameterNames(type), isNot(contains('secret')),
            reason: 'SEC-01: secrets are mounted files, never preference '
                'rows, and never anything a remote client can ask for. The '
                'concrete Preferences class takes {bool secret = false} and '
                'routes the read to secure storage; mirroring that parameter '
                'onto $name would turn one client-supplied boolean into '
                'remote retrieval of the secure store.');
      });
    }

    test('the walk itself sees members arriving via a superinterface', () {
      // WR-07. The reflection used to read `declarations` alone, which
      // returns only what a class declares itself — so the one shape this
      // file exists to forbid could arrive through a superinterface and be
      // completely invisible to every assertion above.
      expect(declaredMemberNames(_DerivedFixture), {'query', 'ownMember'},
          reason: 'a member inherited from a superinterface is fully part of '
              'the wire surface');
      expect(declaredParameterNames(_DerivedFixture), contains('secret'),
          reason: 'the secret check had the identical hole');
    });

    test('no member name suggests a statement-taking escape hatch', () {
      final suspicious = <String>[
        for (final type in wireTypes)
          for (final member in declaredMemberNames(type))
            if (member.toLowerCase().contains('sql') ||
                member.toLowerCase().contains('rawquery') ||
                member.toLowerCase().contains('execute'))
              member,
      ];
      expect(suspicious, isEmpty,
          reason: 'the four timeseries methods take a series name and a time '
              'range, all of which the gateway validates. A method that '
              'takes a statement hands the database to whoever holds a '
              'socket, and no gateway-side sanitizing makes that safe.');
    });
  });
}

/// Fixtures for the walk's own regression test: exactly the shape that used to
/// slip past — a statement-taking method and a `secret:` parameter, reachable
/// only through a superinterface. Nothing on the wire implements these.
abstract interface class _InheritedFixture {
  Future<void> query(String sql, {bool secret});
}

abstract interface class _DerivedFixture implements _InheritedFixture {
  void ownMember();
}
