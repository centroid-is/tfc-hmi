/// The route gate: the decision table, the locked page, and the three renders.
///
/// The decision half is a pure function, so most of this file needs no
/// `WidgetTester` at all. That is deliberate — the repository-unavailable rule
/// is the part of this phase that took three review rounds to get right, and a
/// truth table is the only way to keep it honest as the phase grows.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/access_gate.dart';
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
}
