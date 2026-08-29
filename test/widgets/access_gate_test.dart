/// The route gate: the decision table, the locked page, and the three renders.
///
/// The decision half is a pure function, so most of this file needs no
/// `WidgetTester` at all. That is deliberate — the repository-unavailable rule
/// is the part of this phase that took three review rounds to get right, and a
/// truth table is the only way to keep it honest as the phase grows.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/access.dart';
import 'package:tfc/widgets/access_gate.dart';
import 'package:tfc/widgets/access_sign_in_dialog.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';

/// A repository that answers nothing. `resolveAccessGate` only ever asks
/// whether one exists, so a stand-in with no behaviour is the whole surface
/// the decision depends on.
class _StubRepository extends Fake implements AccessRepository {}

/// The five routes that stay locked when the repository is unavailable, in
/// group terms: page editor / alarm editor / key repository are `configure`,
/// IP settings and preferences are `administer`.
const List<AccessGroup> _lockedRouteGroups = [
  AccessGroup.configure,
  AccessGroup.administer,
];

/// Every group except `operate`, which short-circuits before any of this.
const List<AccessGroup> _raisableGroups = [
  AccessGroup.setpoints,
  AccessGroup.device,
  AccessGroup.force,
  AccessGroup.configure,
  AccessGroup.administer,
  AccessGroup.users,
];

AsyncValue<AccessRepository?> _repoPresent() =>
    AsyncValue.data(_StubRepository());
AsyncValue<AccessRepository?> _repoNull() =>
    const AsyncValue<AccessRepository?>.data(null);
AsyncValue<AccessRepository?> _repoLoading() =>
    const AsyncValue<AccessRepository?>.loading();
AsyncValue<AccessRepository?> _repoError() => AsyncValue<AccessRepository?>.error(
      StateError('postgres will not answer'),
      StackTrace.empty,
    );

/// The two ways a station ends up with no usable repository. The whole point
/// of the ruling is that these two are indistinguishable to the gate, so every
/// unavailable-repository test runs over both.
Map<String, AsyncValue<AccessRepository?>> get _unavailableRepositories => {
      'resolved null (never configured, or configured and unreachable)':
          _repoNull(),
      'AsyncError (the repository could not even be constructed)': _repoError(),
    };

AsyncValue<AccessSession> _anonymous() =>
    AsyncValue.data(AccessSession.anonymous(const {AccessGroup.operate}));

AsyncValue<AccessSession> _elevated(Set<AccessGroup> groups) =>
    AsyncValue.data(AccessSession(
      user: const AuthenticatedUser(
        username: 'jon',
        roleName: 'Engineering',
        displayName: 'Jon B',
      ),
      groups: groups,
      expiresAt: DateTime.utc(2026, 8, 29, 12),
    ));

AsyncValue<AccessSession> _sessionLoading() =>
    const AsyncValue<AccessSession>.loading();

AsyncValue<AccessSession> _sessionError() => AsyncValue<AccessSession>.error(
      StateError('session could not be resolved'),
      StackTrace.empty,
    );

void main() {
  group('resolveAccessGate — operate', () {
    test('operate is allowed even while every provider is loading', () {
      expect(
        resolveAccessGate(
          group: AccessGroup.operate,
          repository: _repoLoading(),
          session: _sessionLoading(),
          allowWhenRepositoryUnavailable: false,
        ),
        AccessGateState.allowed,
      );
    });

    test('operate is allowed with no repository and no session', () {
      for (final repository in _unavailableRepositories.values) {
        expect(
          resolveAccessGate(
            group: AccessGroup.operate,
            repository: repository,
            session: _sessionError(),
            allowWhenRepositoryUnavailable: false,
          ),
          AccessGateState.allowed,
        );
      }
    });
  });

  group('resolveAccessGate — the repository, before the session', () {
    test('repository loading is waiting, never allowed', () {
      for (final flag in [true, false]) {
        for (final group in _raisableGroups) {
          expect(
            resolveAccessGate(
              group: group,
              repository: _repoLoading(),
              session: _anonymous(),
              allowWhenRepositoryUnavailable: flag,
            ),
            AccessGateState.waiting,
            reason: 'a slow connection must not be read as a missing one '
                '($group, flag $flag)',
          );
        }
      }
    });

    test('repository loading is waiting even for a session holding the group',
        () {
      expect(
        resolveAccessGate(
          group: AccessGroup.configure,
          repository: _repoLoading(),
          session: _elevated(const {AccessGroup.operate, AccessGroup.configure}),
          allowWhenRepositoryUnavailable: false,
        ),
        AccessGateState.waiting,
      );
    });

    test(
        'repository unavailable with allowWhenRepositoryUnavailable: true is '
        'allowed, in both causes, for every group', () {
      _unavailableRepositories.forEach((cause, repository) {
        for (final group in _raisableGroups) {
          expect(
            resolveAccessGate(
              group: group,
              repository: repository,
              session: _anonymous(),
              allowWhenRepositoryUnavailable: true,
            ),
            AccessGateState.allowed,
            reason: '$group, $cause',
          );
        }
      });
    });

    test(
        'repository unavailable with allowWhenRepositoryUnavailable: false is '
        'denied, in both causes, for every group including administer', () {
      _unavailableRepositories.forEach((cause, repository) {
        for (final group in _raisableGroups) {
          expect(
            resolveAccessGate(
              group: group,
              repository: repository,
              session: _anonymous(),
              allowWhenRepositoryUnavailable: false,
            ),
            AccessGateState.denied,
            reason: '$group, $cause',
          );
        }
      });
    });

    test(
        'an unavailable repository denies even a session that claims the group',
        () {
      // A stale in-memory session must not carry authority the database is no
      // longer there to back. The repository check runs first for exactly this.
      _unavailableRepositories.forEach((cause, repository) {
        expect(
          resolveAccessGate(
            group: AccessGroup.configure,
            repository: repository,
            session:
                _elevated(const {AccessGroup.operate, AccessGroup.configure}),
            allowWhenRepositoryUnavailable: false,
          ),
          AccessGateState.denied,
          reason: cause,
        );
      });
    });

    test('AsyncError behaves exactly as resolved null, for both flag values',
        () {
      for (final flag in [true, false]) {
        for (final group in _raisableGroups) {
          expect(
            resolveAccessGate(
              group: group,
              repository: _repoError(),
              session: _anonymous(),
              allowWhenRepositoryUnavailable: flag,
            ),
            resolveAccessGate(
              group: group,
              repository: _repoNull(),
              session: _anonymous(),
              allowWhenRepositoryUnavailable: flag,
            ),
            reason: 'the rule does not care why the repository is '
                'unavailable ($group, flag $flag)',
          );
        }
      }
    });

    test(
        'the amendment: Server Config opens in BOTH unavailable states and the '
        'other five stay locked in both', () {
      _unavailableRepositories.forEach((cause, repository) {
        // Server Config is the one route that passes the exemption true.
        expect(
          resolveAccessGate(
            group: AccessGroup.administer,
            repository: repository,
            session: _anonymous(),
            allowWhenRepositoryUnavailable: true,
          ),
          AccessGateState.allowed,
          reason: 'server config must open — $cause',
        );

        // Page editor, alarm editor, key repository (configure) and IP
        // settings, preferences (administer) pass it false.
        for (final group in _lockedRouteGroups) {
          expect(
            resolveAccessGate(
              group: group,
              repository: repository,
              session: _anonymous(),
              allowWhenRepositoryUnavailable: false,
            ),
            AccessGateState.denied,
            reason: 'the other five must stay locked — $group, $cause',
          );
        }
      });
    });
  });

  group('resolveAccessGate — the session, once a repository exists', () {
    test('repository present and session loading is waiting', () {
      expect(
        resolveAccessGate(
          group: AccessGroup.configure,
          repository: _repoPresent(),
          session: _sessionLoading(),
          allowWhenRepositoryUnavailable: false,
        ),
        AccessGateState.waiting,
      );
    });

    test('repository present and session in error is denied', () {
      expect(
        resolveAccessGate(
          group: AccessGroup.configure,
          repository: _repoPresent(),
          session: _sessionError(),
          allowWhenRepositoryUnavailable: false,
        ),
        AccessGateState.denied,
      );
    });

    test('repository present and session holding the group is allowed', () {
      expect(
        resolveAccessGate(
          group: AccessGroup.configure,
          repository: _repoPresent(),
          session:
              _elevated(const {AccessGroup.operate, AccessGroup.configure}),
          allowWhenRepositoryUnavailable: false,
        ),
        AccessGateState.allowed,
      );
    });

    test('repository present and session lacking the group is denied', () {
      expect(
        resolveAccessGate(
          group: AccessGroup.administer,
          repository: _repoPresent(),
          session:
              _elevated(const {AccessGroup.operate, AccessGroup.configure}),
          allowWhenRepositoryUnavailable: false,
        ),
        AccessGateState.denied,
      );
    });

    test(
        'the exemption goes inert the moment a repository exists: '
        'allowWhenRepositoryUnavailable: true with an anonymous session is '
        'denied', () {
      for (final group in _raisableGroups) {
        expect(
          resolveAccessGate(
            group: group,
            repository: _repoPresent(),
            session: _anonymous(),
            allowWhenRepositoryUnavailable: true,
          ),
          AccessGateState.denied,
          reason: 'server config is gated like everything else once the '
              'database answers ($group)',
        );
      }
    });

    test('an elevated session lacking the group is denied like an anonymous one',
        () {
      final elevated = resolveAccessGate(
        group: AccessGroup.administer,
        repository: _repoPresent(),
        session: _elevated(const {AccessGroup.operate}),
        allowWhenRepositoryUnavailable: false,
      );
      final anonymous = resolveAccessGate(
        group: AccessGroup.administer,
        repository: _repoPresent(),
        session: _anonymous(),
        allowWhenRepositoryUnavailable: false,
      );
      expect(elevated, AccessGateState.denied);
      expect(elevated, anonymous,
          reason: 'being signed in is not the question; holding the group is');
    });
  });

  group('AccessLockedBody', () {
    testWidgets('names the missing group by its AccessGroup name',
        (tester) async {
      await tester.pumpWidget(_lockedBodyHost(group: AccessGroup.administer));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessLockedBodyKey), findsOneWidget);
      expect(find.text(kAccessLockedGroupNote(AccessGroup.administer)),
          findsOneWidget);
      expect(kAccessLockedGroupNote(AccessGroup.administer),
          contains(AccessGroup.administer.name));
    });

    testWidgets('anonymous: says a sign-in is needed and offers one',
        (tester) async {
      await tester.pumpWidget(_lockedBodyHost(group: AccessGroup.configure));
      await tester.pumpAndSettle();

      expect(find.text(kAccessLockedHeadline), findsOneWidget);
      expect(find.byKey(kAccessLockedSignInKey), findsOneWidget);
      // Nobody is signed in, so there is no role to talk about.
      expect(find.textContaining('You are signed in as'), findsNothing);
    });

    testWidgets(
        'elevated but insufficient: names who and their role, and still '
        'offers a sign-in', (tester) async {
      await tester.pumpWidget(_lockedBodyHost(
        group: AccessGroup.administer,
        session: _elevatedSession(const {AccessGroup.operate}),
      ));
      await tester.pumpAndSettle();

      final note = kAccessLockedRoleNote(
          'Jon B', 'Engineering', AccessGroup.administer);
      expect(find.text(note), findsOneWidget);
      expect(note, contains('Jon B'));
      expect(note, contains('Engineering'));
      expect(note, contains(AccessGroup.administer.name));

      // Signing in as somebody else is still on offer.
      expect(find.byKey(kAccessLockedSignInKey), findsOneWidget);
    });

    testWidgets('an unavailable repository adds the no-database line, in both '
        'causes', (tester) async {
      for (final repository in [_absentRepository, _throwingRepository]) {
        await tester.pumpWidget(_lockedBodyHost(
          group: AccessGroup.configure,
          repository: repository,
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(kAccessLockedNoDatabaseKey), findsOneWidget);
        expect(find.text(kAccessLockedNoDatabaseNote), findsOneWidget);
      }
    });

    testWidgets('the no-database line is absent when a repository is present',
        (tester) async {
      await tester.pumpWidget(_lockedBodyHost(group: AccessGroup.configure));
      await tester.pumpAndSettle();

      expect(find.byKey(kAccessLockedNoDatabaseKey), findsNothing);
      expect(find.text(kAccessLockedNoDatabaseNote), findsNothing);
    });

    testWidgets('the no-database line wraps rather than ellipsising',
        (tester) async {
      await tester.pumpWidget(_lockedBodyHost(
        group: AccessGroup.configure,
        repository: _absentRepository,
      ));
      await tester.pumpAndSettle();

      _expectWrapsLegibly(tester, kAccessLockedNoDatabaseKey,
          kAccessLockedNoDatabaseNote);
    });

    test('the no-database line states the consequence and the next step, '
        'never a cause', () {
      // Never configured and configured-but-down lead to the same next step
      // now that Server Config opens in both, and a line that guessed wrong
      // would send a commissioner and an operator hunting different wrong
      // problems — the mistake `lib/pages/first_user.dart:55-64` documents.
      expect(kAccessLockedNoDatabaseNote, isNot(contains('configured')));
      expect(kAccessLockedNoDatabaseNote, isNot(contains('unreachable')));
      expect(kAccessLockedNoDatabaseNote, contains('Server Config'));
    });

    testWidgets('carries the honesty line verbatim, wrapping rather than '
        'ellipsising', (tester) async {
      await tester.pumpWidget(_lockedBodyHost(group: AccessGroup.configure));
      await tester.pumpAndSettle();

      expect(find.text(kAccessSignInHonestyNote), findsOneWidget);
      _expectWrapsLegibly(
          tester, kAccessLockedHonestyKey, kAccessSignInHonestyNote);
    });

    testWidgets('the Sign in action calls the injected opener once per tap',
        (tester) async {
      final opener = _CountingOpener();
      await tester.pumpWidget(_lockedBodyHost(
        group: AccessGroup.configure,
        openSignIn: opener.call,
      ));
      await tester.pumpAndSettle();

      expect(opener.calls, 0, reason: 'a render must not open the dialog');
      await tester.tap(find.byKey(kAccessLockedSignInKey));
      await tester.pumpAndSettle();
      expect(opener.calls, 1);
      await tester.tap(find.byKey(kAccessLockedSignInKey));
      await tester.pumpAndSettle();
      expect(opener.calls, 2);
    });

    testWidgets('renders no error styling, in either repository state',
        (tester) async {
      for (final repository in [_presentRepository, _absentRepository]) {
        await tester.pumpWidget(_lockedBodyHost(
          group: AccessGroup.configure,
          repository: repository,
        ));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.error), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(find.byIcon(Icons.warning), findsNothing);
        expect(find.byIcon(Icons.warning_amber), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
        expect(find.textContaining('Error'), findsNothing);

        final scheme = Theme.of(
          tester.element(find.byKey(kAccessLockedBodyKey)),
        ).colorScheme;
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(text.style?.color, isNot(scheme.error),
              reason: 'a lock is not a fault: "${text.data}"');
        }
        for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
          expect(icon.color, isNot(scheme.error));
        }
      }
    });

    testWidgets('offers no go-back, retry or request-access affordance',
        (tester) async {
      await tester.pumpWidget(_lockedBodyHost(
        group: AccessGroup.configure,
        repository: _absentRepository,
      ));
      await tester.pumpAndSettle();

      // Leaving is the app bar's and the navigation bar's job, and there is
      // nobody in this build to request access from.
      expect(find.textContaining('Back'), findsNothing);
      expect(find.textContaining('Retry'), findsNothing);
      expect(find.textContaining('Try again'), findsNothing);
      expect(find.textContaining('Request'), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('nothing it renders is disabled, including with no repository',
        (tester) async {
      for (final repository in [
        _presentRepository,
        _absentRepository,
        _throwingRepository,
      ]) {
        await tester.pumpWidget(_lockedBodyHost(
          group: AccessGroup.configure,
          repository: repository,
        ));
        await tester.pumpAndSettle();

        final buttons = tester.widgetList<ButtonStyleButton>(
          find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        expect(buttons, isNotEmpty);
        for (final button in buttons) {
          expect(button.onPressed, isNotNull,
              reason: 'a greyed control is the one thing the UI rules forbid');
        }
        for (final button in tester.widgetList<IconButton>(
          find.byType(IconButton),
        )) {
          expect(button.onPressed, isNotNull);
        }
      }
    });
  });
}

/// A session that resolves immediately to whatever the test needs.
///
/// Overriding [build] is what keeps the frame chosen rather than raced: none of
/// the real leaf providers — database, preferences, audit sink, inactivity
/// monitor — is ever constructed, so there is no I/O to settle against and no
/// timer to leak. Copied from `test/widgets/access_golden_test.dart`.
class _FixedSession extends AccessSessionController {
  _FixedSession(this._session);

  final AccessSession _session;

  @override
  Future<AccessSession> build() async => _session;

  @override
  Future<AccessSignInResult> signIn(String username, String password) async =>
      AccessSignInResult.ok;

  @override
  Future<void> signOut() async {}

  @override
  void poke() {}
}

/// The three repository states a widget test can be in. The gate's own decision
/// is tested against `AsyncValue`s directly; these are for the widgets, which
/// read the provider themselves.
Future<AccessRepository?> _presentRepository() async => _StubRepository();
Future<AccessRepository?> _absentRepository() async => null;
Future<AccessRepository?> _throwingRepository() async =>
    throw StateError('postgres will not answer');

AccessSession _elevatedSession(Set<AccessGroup> groups) => AccessSession(
      user: const AuthenticatedUser(
        username: 'jon',
        roleName: 'Engineering',
        displayName: 'Jon B',
      ),
      groups: groups,
      expiresAt: DateTime.utc(2026, 8, 29, 12),
    );

/// Counts the taps without standing up a dialog route.
class _CountingOpener {
  int calls = 0;

  Future<void> call(BuildContext context, WidgetRef ref) async {
    calls++;
  }
}

/// [AccessLockedBody] under a bare `MaterialApp` — no Beamer, no router.
///
/// Both access providers are overridden, always: an unoverridden
/// `accessRepositoryProvider` reaches `databaseProvider` and the keychain, and
/// the test becomes a race.
Widget _lockedBodyHost({
  required AccessGroup group,
  AccessSession? session,
  Future<AccessRepository?> Function() repository = _presentRepository,
  AccessSignInOpener? openSignIn,
}) {
  return ProviderScope(
    overrides: [
      accessSessionProvider.overrideWith(() => _FixedSession(
          session ?? AccessSession.anonymous(const {AccessGroup.operate}))),
      accessRepositoryProvider.overrideWith((ref) => repository()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: AccessLockedBody(
          group: group,
          openSignIn: openSignIn ?? _CountingOpener().call,
        ),
      ),
    ),
  );
}

/// The Phase 1 lesson, copied deliberately: `find.text` passes on a string the
/// painter has clipped to "…not a security bo…", which is how an ellipsised
/// honesty line shipped past a green assertion. Pin the properties that decide
/// legibility, then check the paragraph really is taller than one line at the
/// width the page renders it at.
void _expectWrapsLegibly(WidgetTester tester, Key key, String expected) {
  final text = tester.widget<Text>(find.byKey(key));
  expect(text.data, expected);
  expect(text.maxLines, isNull);
  expect(text.overflow, isNot(TextOverflow.ellipsis));

  final rendered = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
  );
  expect(rendered.size.height, greaterThan(rendered.preferredLineHeight));
}
