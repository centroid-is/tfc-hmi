import 'dart:convert';

import 'package:tfc_access/tfc_access.dart';
import 'package:test/test.dart';

void main() {
  final elevatedUser = AuthenticatedUser(
    username: 'gudrun',
    roleName: 'Engineering',
    displayName: 'Guðrún',
  );

  group('anonymous', () {
    test('has no user, is not elevated, and never expires', () {
      final session = AccessSession.anonymous({AccessGroup.operate});
      expect(session.user, isNull);
      expect(session.isElevated, isFalse);
      expect(session.roleName, kOperatorRoleName);
      expect(session.roleName, 'Operator');
      expect(session.expiresAt, isNull);
    });

    test('can operate but cannot set points, configure or manage users', () {
      final session = AccessSession.anonymous({AccessGroup.operate});
      expect(session.can(AccessGroup.operate), isTrue);
      expect(session.can(AccessGroup.setpoints), isFalse);
      expect(session.can(AccessGroup.configure), isFalse);
      expect(session.can(AccessGroup.users), isFalse);
    });

    test(
        'uses the Operator role as it currently stands, without second-guessing'
        ' it', () {
      // Somebody ticked `setpoints` on the Operator role. That silently grants
      // it to every panel on the floor with nobody signed in — the one footgun
      // this simplification creates. The session's job is to report the role,
      // not to overrule it.
      final session = AccessSession.anonymous(
        {AccessGroup.operate, AccessGroup.setpoints},
      );
      expect(session.can(AccessGroup.setpoints), isTrue);
      expect(session.can(AccessGroup.device), isFalse);
    });

    test('is never expired, at any time', () {
      final session = AccessSession.anonymous({AccessGroup.operate});
      expect(session.isExpiredAt(DateTime(1970)), isFalse);
      expect(session.isExpiredAt(DateTime.now()), isFalse);
      expect(session.isExpiredAt(DateTime(2999)), isFalse);
    });
  });

  group('elevated', () {
    test('roleName is the user\'s role, not Operator', () {
      final session = AccessSession(
        user: elevatedUser,
        groups: AccessGroup.values.toSet(),
        expiresAt: DateTime.utc(2026, 8, 28, 12, 0),
      );
      expect(session.isElevated, isTrue);
      expect(session.roleName, 'Engineering');
      expect(session.roleName, isNot(kOperatorRoleName));
      expect(session.can(AccessGroup.administer), isTrue);
    });

    test('can() answers from the resolved groups', () {
      final session = AccessSession(
        user: AuthenticatedUser(username: 'siggi', roleName: 'Shift Leader'),
        groups: {AccessGroup.operate, AccessGroup.setpoints},
      );
      expect(session.can(AccessGroup.setpoints), isTrue);
      expect(session.can(AccessGroup.force), isFalse);
    });

    test('isExpiredAt is true strictly after expiresAt', () {
      final at = DateTime.utc(2026, 8, 28, 12, 0);
      final session = AccessSession(
        user: elevatedUser,
        groups: {AccessGroup.operate},
        expiresAt: at,
      );
      expect(session.isExpiredAt(at.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(session.isExpiredAt(at), isFalse,
          reason: 'equal is not yet expired');
      expect(session.isExpiredAt(at.add(const Duration(seconds: 1))), isTrue);
    });

    test('value equality covers user, groups and expiresAt', () {
      final at = DateTime.utc(2026, 8, 28, 12, 0);
      final a = AccessSession(
        user: elevatedUser,
        groups: {AccessGroup.operate, AccessGroup.setpoints},
        expiresAt: at,
      );
      final sameByValue = AccessSession(
        user: AuthenticatedUser(
          username: 'gudrun',
          roleName: 'Engineering',
          displayName: 'Guðrún',
        ),
        // Different insertion order, same set.
        groups: {AccessGroup.setpoints, AccessGroup.operate},
        expiresAt: DateTime.utc(2026, 8, 28, 12, 0),
      );
      expect(a, sameByValue);
      expect(a.hashCode, sameByValue.hashCode);

      expect(
        a,
        isNot(AccessSession(
          user: elevatedUser,
          groups: {AccessGroup.operate},
          expiresAt: at,
        )),
      );
      expect(a, isNot(AccessSession.anonymous({AccessGroup.operate})));
    });
  });

  group('serialization', () {
    final at = DateTime.utc(2026, 8, 28, 12, 34, 56);
    final session = AccessSession(
      user: elevatedUser,
      groups: {AccessGroup.operate, AccessGroup.configure},
      expiresAt: at,
    );

    test('toJson emits username, roleName, displayName and an ISO expiresAt',
        () {
      final json = session.toJson();
      expect(json['username'], 'gudrun');
      expect(json['roleName'], 'Engineering');
      expect(json['displayName'], 'Guðrún');
      expect(json['expiresAt'], at.toIso8601String());
    });

    test('toJson does not emit groups', () {
      // Groups are re-resolved from the role on restore, so a role edited on
      // another station takes effect here at the next restart rather than
      // staying stale until the next login.
      expect(session.toJson().containsKey('groups'), isFalse);
      expect(jsonEncode(session.toJson()), isNot(contains('operate')));
    });

    test('the payload carries no password, hash or salt', () {
      final encoded = jsonEncode(session.toJson()).toLowerCase();
      expect(encoded, isNot(contains('password')));
      expect(encoded, isNot(contains('hash')));
      expect(encoded, isNot(contains('salt')));
    });

    test('parse of a toJson payload round-trips into a PersistedSession', () {
      final restored = AccessSession.parse(jsonEncode(session.toJson()));
      expect(restored, isNotNull);
      expect(restored!.username, 'gudrun');
      expect(restored.roleName, 'Engineering');
      expect(restored.displayName, 'Guðrún');
      expect(restored.expiresAt, at);
    });

    test('parse tolerates a missing displayName', () {
      final restored = AccessSession.parse(jsonEncode({
        'username': 'siggi',
        'roleName': 'Shift Leader',
        'expiresAt': at.toIso8601String(),
      }));
      expect(restored, isNotNull);
      expect(restored!.displayName, isNull);
    });

    test('parse returns null on garbage rather than throwing', () {
      expect(AccessSession.parse('not json'), isNull);
    });

    test('parse returns null on an empty object', () {
      expect(AccessSession.parse('{}'), isNull);
    });

    test('parse returns null when expiresAt is missing', () {
      expect(
        AccessSession.parse(
            jsonEncode({'username': 'siggi', 'roleName': 'Shift Leader'})),
        isNull,
      );
    });

    test('parse returns null when expiresAt is unparseable', () {
      expect(
        AccessSession.parse(jsonEncode({
          'username': 'siggi',
          'roleName': 'Shift Leader',
          'expiresAt': 'whenever',
        })),
        isNull,
      );
    });

    test('parse returns null for an anonymous session payload', () {
      // There is nothing to restore: an anonymous session is what you get when
      // restore fails, so it never needs to survive a restart itself.
      final anonymous = AccessSession.anonymous({AccessGroup.operate});
      expect(AccessSession.parse(jsonEncode(anonymous.toJson())), isNull);
    });
  });

  group('PersistedSession', () {
    test(
        'an expiresAt in the past is expired — this is what makes a stored '
        'session restore as anonymous', () {
      final stored = PersistedSession(
        username: 'gudrun',
        roleName: 'Engineering',
        expiresAt: DateTime.utc(2020, 1, 1),
      );
      expect(stored.isExpiredAt(DateTime.utc(2026, 8, 28)), isTrue);
    });

    test('an expiresAt in the future is not expired', () {
      final stored = PersistedSession(
        username: 'gudrun',
        roleName: 'Engineering',
        expiresAt: DateTime.utc(2099, 1, 1),
      );
      expect(stored.isExpiredAt(DateTime.utc(2026, 8, 28)), isFalse);
    });

    test('equal is not yet expired', () {
      final at = DateTime.utc(2026, 8, 28, 12);
      final stored = PersistedSession(
        username: 'gudrun',
        roleName: 'Engineering',
        expiresAt: at,
      );
      expect(stored.isExpiredAt(at), isFalse);
    });

    test('value equality', () {
      final at = DateTime.utc(2026, 8, 28, 12);
      expect(
        PersistedSession(username: 'a', roleName: 'Operator', expiresAt: at),
        PersistedSession(username: 'a', roleName: 'Operator', expiresAt: at),
      );
      expect(
        PersistedSession(username: 'a', roleName: 'Operator', expiresAt: at),
        isNot(PersistedSession(
            username: 'b', roleName: 'Operator', expiresAt: at)),
      );
    });
  });
}
