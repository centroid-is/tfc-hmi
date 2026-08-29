import 'package:tfc_access/tfc_access.dart';
import 'package:test/test.dart';

void main() {
  group('AccessSurface', () {
    test('has exactly three values', () {
      // Exact, not `greaterThan`. A fourth write surface is a decision: every
      // surface this enum names has to have an answer in `groupForPref` or
      // `groupForTag`, and a value added without one would ride the unmapped
      // branch forever without anybody noticing.
      expect(AccessSurface.values, hasLength(3));
    });

    test('values are tag, pref, route in that order', () {
      expect(AccessSurface.values, [
        AccessSurface.tag,
        AccessSurface.pref,
        AccessSurface.route,
      ]);
    });

    test('wire names match spec section 2 surface column vocabulary', () {
      expect(AccessSurface.values.map((s) => s.wireName), [
        'tag',
        'pref',
        'route',
      ]);
    });

    test('byWireName resolves each of the three wire names', () {
      expect(AccessSurface.byWireName('tag'), AccessSurface.tag);
      expect(AccessSurface.byWireName('pref'), AccessSurface.pref);
      expect(AccessSurface.byWireName('route'), AccessSurface.route);
    });

    test('byWireName returns null for anything outside the vocabulary', () {
      // 'auth' is a real value in spec section 2's surface column and is
      // deliberately not a write surface, so the enum and the column are not
      // the same set.
      expect(AccessSurface.byWireName('auth'), isNull);
      expect(AccessSurface.byWireName(''), isNull);
      expect(AccessSurface.byWireName('Tag'), isNull);
      expect(AccessSurface.byWireName('preferences'), isNull);
    });
  });

  group('AccessPolicy construction', () {
    test('is const-constructible with no arguments', () {
      const policy = AccessPolicy();
      expect(policy, isA<AccessPolicy>());
    });

    test('two instances built the same way answer identically', () {
      const a = AccessPolicy();
      const b = AccessPolicy();
      for (final key in ['page_editor_data', 'nonsense', '', 'BATCH.recipes']) {
        expect(a.groupForPref(key), b.groupForPref(key));
        expect(a.groupForTag(key), b.groupForTag(key));
      }
      expect(a.groupForRoute('/advanced/page-editor'),
          b.groupForRoute('/advanced/page-editor'));
    });
  });

  group('the asymmetry: tags fail OPEN', () {
    test('an unbound tag key is unrestricted — groupForTag answers null', () {
      // This is the fail-open half, and the return type carries it: null means
      // "no group required". Phase 4 has not shipped access templates, so a
      // strict default here would lock every control on the plant on the day
      // this merges.
      const policy = AccessPolicy();
      expect(policy.groupForTag('CN01.MOT01'), isNull);
      expect(policy.groupForTag(''), isNull);
      expect(policy.groupForTag('anything_at_all'), isNull);
      expect(policy.groupForTag('server_config_envelope'), isNull);
    });

    test('groupForTag consults the injected binding lookup', () {
      final policy = AccessPolicy(
        tagBindings: (key, member) {
          if (key == 'CN01.MOT01' && member == 'p_cfg_ManualFreq') {
            return AccessGroup.setpoints;
          }
          if (key == 'CN01.MOT01' && member == 'p_cmd_JogFwd') {
            return AccessGroup.operate;
          }
          return null;
        },
      );
      expect(policy.groupForTag('CN01.MOT01', member: 'p_cfg_ManualFreq'),
          AccessGroup.setpoints);
      expect(policy.groupForTag('CN01.MOT01', member: 'p_cmd_JogFwd'),
          AccessGroup.operate);
    });

    test('groupForTag returns null when the binding lookup answers null', () {
      // A member no bound template mentions is unrestricted, same as an
      // unbound key (spec section 7b).
      final policy = AccessPolicy(tagBindings: (key, member) => null);
      expect(policy.groupForTag('CN01.MOT01', member: 'p_stat_RunMode'), isNull);
    });

    test('a binding lookup that throws is treated as no binding', () {
      // The fail-open half must not become fail-closed because a template
      // table is unreadable. A guard that threw on the read path would take
      // down jogging.
      final policy = AccessPolicy(
        tagBindings: (key, member) => throw StateError('template table is gone'),
      );
      expect(policy.groupForTag('CN01.MOT01', member: 'p_cmd_JogFwd'), isNull);
      expect(policy.groupForTag('CN01.MOT01'), isNull);
      expect(
        policy.groupForWireSurface('tag', 'CN01.MOT01', member: 'p_cmd_JogFwd'),
        isNull,
      );
    });
  });

  group('the asymmetry: config keys fail CLOSED', () {
    test('an unrecognised preference key requires administer', () {
      // The mirror of the tag direction, and the return type carries this half
      // too: non-nullable, so there is no "unrestricted" answer to reopen.
      const policy = AccessPolicy();
      expect(policy.groupForPref('nobody_classified_this'),
          AccessGroup.administer);
      expect(policy.groupForPref('some.new.subsystem.key'),
          AccessGroup.administer);
    });

    test('groupForPref never answers null, including for the empty string', () {
      const policy = AccessPolicy();
      for (final key in ['', ' ', 'x', 'page_editor_data', 'chat.history']) {
        expect(policy.groupForPref(key), isA<AccessGroup>());
      }
    });
  });

  group('groupForRoute', () {
    test('an unknown path defaults to operate', () {
      const policy = AccessPolicy();
      expect(policy.groupForRoute('/trends'), AccessGroup.operate);
    });

    test('a null path defaults to operate', () {
      const policy = AccessPolicy();
      expect(policy.groupForRoute(null), AccessGroup.operate);
    });

    test('a raised route passed in by the app answers its group', () {
      // Plan 03-06 passes kRaisedRoutes in; this package must not import the
      // app's route table.
      const policy = AccessPolicy(routes: {
        '/advanced/page-editor': AccessGroup.configure,
        '/advanced/server-config': AccessGroup.administer,
      });
      expect(policy.groupForRoute('/advanced/page-editor'),
          AccessGroup.configure);
      expect(policy.groupForRoute('/advanced/server-config'),
          AccessGroup.administer);
      expect(policy.groupForRoute('/advanced/unlisted'), AccessGroup.operate);
    });
  });

  group('groupForWireSurface', () {
    test("the 'tag' wire name delegates to groupForTag and may answer null",
        () {
      const policy = AccessPolicy();
      expect(policy.groupForWireSurface('tag', 'CN01.MOT01'), isNull);

      final bound = AccessPolicy(
        tagBindings: (key, member) =>
            member == 'p_cfg_ManualFreq' ? AccessGroup.setpoints : null,
      );
      expect(
        bound.groupForWireSurface('tag', 'CN01.MOT01',
            member: 'p_cfg_ManualFreq'),
        AccessGroup.setpoints,
      );
    });

    test("the 'pref' wire name delegates to groupForPref and never answers null",
        () {
      const policy = AccessPolicy();
      expect(policy.groupForWireSurface('pref', 'page_editor_data'),
          AccessGroup.configure);
      expect(policy.groupForWireSurface('pref', 'never_seen_before'),
          AccessGroup.administer);
      expect(policy.groupForWireSurface('pref', ''), AccessGroup.administer);
    });

    test("the 'route' wire name delegates to groupForRoute", () {
      const policy = AccessPolicy(routes: {
        '/advanced/page-editor': AccessGroup.configure,
      });
      expect(policy.groupForWireSurface('route', '/advanced/page-editor'),
          AccessGroup.configure);
      expect(policy.groupForWireSurface('route', '/trends'),
          AccessGroup.operate);
    });

    test('an unmapped surface answers administer rather than passing', () {
      // T-03-02. A surface string this file does not know is either a new
      // write surface nobody classified or a typo, and both land on the
      // strictest answer. Never null, never operate, never a throw — the
      // guards call this on the write path and an ArgumentError there would be
      // an outage rather than a denial.
      const policy = AccessPolicy();
      for (final surface in [
        'auth', // a real value in spec section 2, deliberately not a write surface
        '',
        'Tag',
        'preferences',
        'tags',
        'pref ',
      ]) {
        expect(
          policy.groupForWireSurface(surface, 'page_editor_data'),
          AccessGroup.administer,
          reason: 'unmapped surface "$surface" must fail closed',
        );
      }
    });

    test('an unmapped surface does not throw even with a bound lookup', () {
      final policy = AccessPolicy(
        tagBindings: (key, member) => AccessGroup.operate,
      );
      expect(policy.groupForWireSurface('nonsense', 'anything'),
          AccessGroup.administer);
    });
  });
}
