import 'package:clock/clock.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:test/test.dart';

/// A password-shaped string. If this ever appears in an audit row, the trail
/// has become the thing it was meant to protect against.
const _password = 'hunter2-correct-horse-battery-staple';

void main() {
  group('newActionId', () {
    test('is 32 lowercase hex characters', () {
      expect(newActionId(), matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('two successive calls differ', () {
      expect(newActionId(), isNot(newActionId()));
    });

    test('a hundred calls produce a hundred distinct ids', () {
      // 128 bits from Random.secure(). Collisions here would mean one action's
      // rows could be confused with another's, which is the whole point of
      // having a correlation id.
      final ids = {for (var i = 0; i < 100; i++) newActionId()};
      expect(ids, hasLength(100));
    });
  });

  group('AuditRecord', () {
    test('carries one field per AuditEntry column', () {
      final at = DateTime.utc(2026, 8, 28, 9, 30);
      final record = AuditRecord(
        at: at,
        who: 'jon',
        station: 'svn-nes-ot-cl02',
        roleName: 'Engineering',
        surface: 'tag',
        itemKey: 'CN04.MOT01.p_cfg',
        member: 'Freq',
        oldValue: '50',
        newValue: '35',
        groupRequired: 'device',
        allowed: true,
        origin: 'operator',
        actionId: 'a' * 32,
        reason: 'commissioning',
      );

      expect(record.at, at);
      expect(record.who, 'jon');
      expect(record.station, 'svn-nes-ot-cl02');
      expect(record.roleName, 'Engineering');
      expect(record.surface, 'tag');
      expect(record.itemKey, 'CN04.MOT01.p_cfg');
      expect(record.member, 'Freq');
      expect(record.oldValue, '50');
      expect(record.newValue, '35');
      expect(record.groupRequired, 'device');
      expect(record.allowed, isTrue);
      expect(record.origin, 'operator');
      expect(record.actionId, 'a' * 32);
      expect(record.reason, 'commissioning');
    });

    test('origin defaults to operator', () {
      // Hand-made by default on purpose: an unmarked future machine caller
      // lands in the trail loudly rather than escaping it silently.
      final record = AuditRecord(
        at: DateTime.utc(2026),
        who: 'jon',
        station: 'st101',
        roleName: 'Engineering',
        surface: 'pref',
        itemKey: 'some.pref',
        groupRequired: 'configure',
        allowed: true,
        actionId: newActionId(),
      );
      expect(record.origin, 'operator');
    });

    test('nullable columns default to null', () {
      final record = AuditRecord(
        at: DateTime.utc(2026),
        who: 'jon',
        station: 'st101',
        roleName: 'Engineering',
        surface: 'route',
        itemKey: '/server-config',
        groupRequired: 'administer',
        allowed: false,
        actionId: newActionId(),
      );
      expect(record.member, isNull);
      expect(record.oldValue, isNull);
      expect(record.newValue, isNull);
      expect(record.reason, isNull);
    });

    test('has value equality', () {
      final at = DateTime.utc(2026);
      final a = AuditRecord(
        at: at,
        who: 'jon',
        station: 'st101',
        roleName: 'Engineering',
        surface: 'tag',
        itemKey: 'k',
        groupRequired: 'device',
        allowed: true,
        actionId: 'b' * 32,
      );
      final b = AuditRecord(
        at: at,
        who: 'jon',
        station: 'st101',
        roleName: 'Engineering',
        surface: 'tag',
        itemKey: 'k',
        groupRequired: 'device',
        allowed: true,
        actionId: 'b' * 32,
      );
      final c = AuditRecord(
        at: at,
        who: 'jon',
        station: 'st101',
        roleName: 'Engineering',
        surface: 'tag',
        itemKey: 'k',
        groupRequired: 'device',
        allowed: false,
        actionId: 'b' * 32,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('AuditRecord.login', () {
    AuditRecord build() => AuditRecord.login(
          who: 'jon',
          station: 'st101',
          roleName: 'Engineering',
          actionId: 'c' * 32,
        );

    test('fixes the auth vocabulary', () {
      final record = build();
      expect(record.surface, 'auth');
      expect(record.itemKey, 'login');
      expect(record.allowed, isTrue);
    });

    test('records the resolved role in newValue', () {
      final record = build();
      expect(record.roleName, 'Engineering');
      expect(record.newValue, 'Engineering');
    });

    test('groupRequired is empty — an auth event is not gated on a group', () {
      expect(build().groupRequired, isEmpty);
    });

    test('at defaults to the current clock', () {
      final fixed = DateTime.utc(2026, 8, 28, 12);
      final record = withClock(
        Clock.fixed(fixed),
        () => AuditRecord.login(
          who: 'jon',
          station: 'st101',
          roleName: 'Engineering',
          actionId: 'c' * 32,
        ),
      );
      expect(record.at, fixed);
    });
  });

  group('AuditRecord.loginFailed', () {
    AuditRecord build({String who = 'jon'}) => AuditRecord.loginFailed(
          who: who,
          station: 'st101',
          actionId: 'd' * 32,
        );

    test('fixes the auth vocabulary and records the denial', () {
      final record = build();
      expect(record.surface, 'auth');
      expect(record.itemKey, 'login.failed');
      expect(record.allowed, isFalse);
    });

    test('who is the attempted username', () {
      expect(build(who: 'not-a-user').who, 'not-a-user');
    });

    test('who is truncated to 64 characters', () {
      // The username field on a login form accepts a paste. A megabyte of it
      // must not become an audit row.
      final record = build(who: 'x' * 5000);
      expect(record.who, hasLength(64));
      expect(record.who, 'x' * 64);
    });

    test('a who of exactly 64 characters is left alone', () {
      expect(build(who: 'y' * 64).who, 'y' * 64);
    });

    test('the role is anonymous — nobody was signed in', () {
      expect(build().roleName, kOperatorRoleName);
    });

    test('groupRequired is empty', () {
      expect(build().groupRequired, isEmpty);
    });
  });

  group('AuditRecord.logout', () {
    AuditRecord build() => AuditRecord.logout(
          who: 'jon',
          station: 'st101',
          roleName: 'Engineering',
          actionId: 'e' * 32,
        );

    test('fixes the auth vocabulary', () {
      final record = build();
      expect(record.surface, 'auth');
      expect(record.itemKey, 'logout');
      expect(record.allowed, isTrue);
    });

    test('oldValue is the role being left', () {
      expect(build().oldValue, 'Engineering');
    });

    test('groupRequired is empty', () {
      expect(build().groupRequired, isEmpty);
    });
  });

  group('AuditRecord.sessionTimeout', () {
    AuditRecord build({String? reason}) => AuditRecord.sessionTimeout(
          who: 'jon',
          station: 'st101',
          roleName: 'Engineering',
          actionId: 'f' * 32,
          reason: reason,
        );

    test('fixes the auth vocabulary', () {
      final record = build();
      expect(record.surface, 'auth');
      expect(record.itemKey, 'session.timeout');
      expect(record.allowed, isTrue);
    });

    test('accepts a reason', () {
      expect(build(reason: '15 minutes idle').reason, '15 minutes idle');
    });

    test('oldValue is the role being left', () {
      expect(build().oldValue, 'Engineering');
    });

    test('groupRequired is empty', () {
      expect(build().groupRequired, isEmpty);
    });
  });

  group('no auth record can carry a password', () {
    // The structural half of this assertion is the constructor signatures: none
    // of the four auth factories takes a password, so a call passing one would
    // not compile and this file would not run at all. The tests below cover the
    // other half — that a password handed to the *login flow* has no field on
    // the record it could land in, and that toString() does not leak the value
    // columns for an auth row even if something later puts one there.

    test('a failed login built from a bad password mentions it nowhere', () {
      final record = AuditRecord.loginFailed(
        who: 'jon',
        station: 'st101',
        actionId: newActionId(),
      );
      expect(record.toString(), isNot(contains(_password)));
      expect(record.oldValue, isNull);
      expect(record.newValue, isNull);
      expect(record.member, isNull);
      expect(record.reason, isNull);
    });

    test('toString withholds the value columns for surface auth', () {
      final record = AuditRecord(
        at: DateTime.utc(2026),
        who: 'jon',
        station: 'st101',
        roleName: 'Engineering',
        surface: 'auth',
        itemKey: 'login',
        oldValue: _password,
        newValue: _password,
        groupRequired: '',
        allowed: true,
        actionId: newActionId(),
      );
      expect(record.toString(), isNot(contains(_password)));
      expect(record.toString(), contains('auth'));
      expect(record.toString(), contains('login'));
    });

    test('toString still shows the value columns for a tag write', () {
      // Withholding is scoped to auth rows. A tag write's old and new values
      // are the point of the trail.
      final record = AuditRecord(
        at: DateTime.utc(2026),
        who: 'jon',
        station: 'st101',
        roleName: 'Engineering',
        surface: 'tag',
        itemKey: 'CN04.MOT01.p_cfg',
        member: 'Freq',
        oldValue: '50',
        newValue: '35',
        groupRequired: 'device',
        allowed: true,
        actionId: newActionId(),
      );
      expect(record.toString(), contains('50'));
      expect(record.toString(), contains('35'));
    });
  });

  group('NullAuditSink', () {
    test('records nothing and completes', () async {
      final sink = NullAuditSink();
      await sink.record(
        AuditRecord.login(
          who: 'jon',
          station: 'st101',
          roleName: 'Engineering',
          actionId: newActionId(),
        ),
      );
    });

    test('is an AuditSink', () {
      expect(NullAuditSink(), isA<AuditSink>());
    });
  });
}
