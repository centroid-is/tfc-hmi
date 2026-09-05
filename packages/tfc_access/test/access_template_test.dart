import 'package:tfc_access/tfc_access.dart';
import 'package:test/test.dart';

/// The `conveyor` template from spec §7b, trimmed to the two members that
/// carry the phase's acceptance criterion: a key that locks `p_cfg_ManualFreq`
/// while leaving `p_cmd_JogFwd` usable by an anonymous session.
AccessTemplate _conveyor({AccessGroup? wholeKey}) => AccessTemplate(
      name: 'conveyor',
      rules: <String, AccessGroup>{
        'p_cmd_JogFwd': AccessGroup.operate,
        'p_cfg_ManualFreq': AccessGroup.setpoints,
        if (wholeKey != null) kWholeKeyMember: wholeKey,
      },
    );

void main() {
  group('kWholeKeyMember', () {
    test('is the asterisk', () {
      expect(kWholeKeyMember, '*');
    });

    test('cannot collide with a PLC member name', () {
      // T-04-04. `*` is not a legal IEC 61131-3 identifier — those are letters,
      // digits and underscores, starting with a letter or underscore — so no
      // struct member read off a PLC can ever equal the reserved row.
      final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
      expect(identifier.hasMatch(kWholeKeyMember), isFalse);
      for (final member in [
        'p_cmd_JogFwd',
        'p_cfg_ManualFreq',
        'p_stat_Frequency',
        '_reserved',
      ]) {
        expect(identifier.hasMatch(member), isTrue);
        expect(member, isNot(kWholeKeyMember));
      }
    });
  });

  group('AccessTemplate.groupFor — the conveyor table from spec section 7b', () {
    test('p_cmd_JogFwd answers operate', () {
      expect(_conveyor().groupFor('p_cmd_JogFwd'), AccessGroup.operate);
    });

    test('p_cfg_ManualFreq answers setpoints', () {
      expect(_conveyor().groupFor('p_cfg_ManualFreq'), AccessGroup.setpoints);
    });

    test('p_stat_Frequency — a member the template does not mention — answers null', () {
      expect(_conveyor().groupFor('p_stat_Frequency'), isNull);
    });

    test('a null member answers null when there is no whole-key row', () {
      expect(_conveyor().groupFor(null), isNull);
    });
  });

  group('AccessTemplate.groupFor — the whole-key row', () {
    test('without a whole-key row an unmentioned member is unrestricted', () {
      // Direction one of the §7d reading. Both directions are pinned because
      // the spec's phrase "a special row for scalar keys" leaves open whether
      // the row also covers struct members nobody wrote a rule for.
      expect(_conveyor().groupFor('p_stat_Frequency'), isNull);
      expect(_conveyor().groupFor('anything_at_all'), isNull);
    });

    test('with a whole-key row an unmentioned member takes the key-level group', () {
      // Direction two. This is the reading this file adopts: the whole-key row
      // is the key-level default, not a scalar-only answer.
      final template = _conveyor(wholeKey: AccessGroup.device);
      expect(template.groupFor('p_stat_Frequency'), AccessGroup.device);
      expect(template.groupFor('anything_at_all'), AccessGroup.device);
    });

    test('the whole-key row answers a scalar write, where the member is null', () {
      expect(_conveyor(wholeKey: AccessGroup.device).groupFor(null),
          AccessGroup.device);
    });

    test('an explicit member rule still wins over the whole-key row', () {
      // "this whole conveyor needs device except jogging" — the shape the
      // rejected reading could not express.
      final template = _conveyor(wholeKey: AccessGroup.device);
      expect(template.groupFor('p_cmd_JogFwd'), AccessGroup.operate);
      expect(template.groupFor('p_cfg_ManualFreq'), AccessGroup.setpoints);
    });

    test('the whole-key row is reachable by its own name as well', () {
      expect(_conveyor(wholeKey: AccessGroup.device).groupFor(kWholeKeyMember),
          AccessGroup.device);
    });
  });

  group('AccessTemplate.rules', () {
    test('is unmodifiable', () {
      final template = _conveyor();
      expect(() => template.rules['p_new'] = AccessGroup.force,
          throwsUnsupportedError);
      expect(() => template.rules.remove('p_cmd_JogFwd'), throwsUnsupportedError);
    });

    test('the constructor copies, so mutating the caller changes no answer', () {
      final source = <String, AccessGroup>{'p_cmd_JogFwd': AccessGroup.operate};
      final template = AccessTemplate(name: 'conveyor', rules: source);
      source['p_cfg_ManualFreq'] = AccessGroup.setpoints;
      source['p_cmd_JogFwd'] = AccessGroup.administer;
      expect(template.groupFor('p_cmd_JogFwd'), AccessGroup.operate);
      expect(template.groupFor('p_cfg_ManualFreq'), isNull);
    });
  });

  group('AccessTemplate.encodeRules / decodeRules', () {
    test('round-trips a rule set', () {
      final rules = _conveyor(wholeKey: AccessGroup.device).rules;
      expect(AccessTemplate.decodeRules(AccessTemplate.encodeRules(rules)),
          rules);
    });

    test('output is sorted by member name', () {
      // Byte-identical encodings for two equal templates, and a readable diff
      // of the stored blob.
      final encoded = AccessTemplate.encodeRules(<String, AccessGroup>{
        'p_stat_Frequency': AccessGroup.device,
        'p_cmd_JogFwd': AccessGroup.operate,
        kWholeKeyMember: AccessGroup.configure,
        'p_cfg_ManualFreq': AccessGroup.setpoints,
      });
      expect(
        encoded,
        '{"*":"configure","p_cfg_ManualFreq":"setpoints",'
        '"p_cmd_JogFwd":"operate","p_stat_Frequency":"device"}',
      );
    });

    test('two equal rule sets built in different orders encode identically', () {
      final a = AccessTemplate.encodeRules(<String, AccessGroup>{
        'p_cmd_JogFwd': AccessGroup.operate,
        'p_cfg_ManualFreq': AccessGroup.setpoints,
      });
      final b = AccessTemplate.encodeRules(<String, AccessGroup>{
        'p_cfg_ManualFreq': AccessGroup.setpoints,
        'p_cmd_JogFwd': AccessGroup.operate,
      });
      expect(a, b);
    });

    test('a group name this build does not know loses that rule and keeps the rest', () {
      // T-04-01. A newer station writes a rules blob naming an eighth group;
      // this build must lose that one rule, never the plant's controls.
      final decoded = AccessTemplate.decodeRules(
          '{"p_cmd_JogFwd":"operate","p_x":"notagroup"}');
      expect(decoded, hasLength(1));
      expect(decoded['p_cmd_JogFwd'], AccessGroup.operate);
      expect(decoded.containsKey('p_x'), isFalse);
    });

    test('a template built from such a blob leaves the dropped member open', () {
      final template = AccessTemplate(
        name: 'conveyor',
        rules: AccessTemplate.decodeRules(
            '{"p_cmd_JogFwd":"operate","p_x":"notagroup"}'),
      );
      expect(template.groupFor('p_cmd_JogFwd'), AccessGroup.operate);
      expect(template.groupFor('p_x'), isNull);
    });

    test('a malformed blob yields an empty rule set rather than throwing', () {
      for (final blob in ['', 'not json at all', '[]', '[1,2,3]', 'null', '7']) {
        expect(AccessTemplate.decodeRules(blob), isEmpty,
            reason: 'decoding "$blob" must not throw and must not lock a key');
      }
    });

    test('non-string values inside a well-formed object are dropped', () {
      final decoded = AccessTemplate.decodeRules(
          '{"p_cmd_JogFwd":"operate","p_a":7,"p_b":null,"p_c":["operate"]}');
      expect(decoded, hasLength(1));
      expect(decoded['p_cmd_JogFwd'], AccessGroup.operate);
    });

    test('an empty rule set round-trips', () {
      expect(AccessTemplate.encodeRules(const <String, AccessGroup>{}), '{}');
      expect(AccessTemplate.decodeRules('{}'), isEmpty);
    });
  });

  group('AccessTemplate equality', () {
    test('two templates with the same name and rules are equal', () {
      expect(_conveyor(), _conveyor());
      expect(_conveyor().hashCode, _conveyor().hashCode);
    });

    test('a different name is a different template', () {
      expect(_conveyor(), isNot(AccessTemplate(name: 'schneider', rules: _conveyor().rules)));
    });

    test('a different rule set is a different template', () {
      expect(_conveyor(), isNot(_conveyor(wholeKey: AccessGroup.device)));
    });
  });

  group('AccessTemplate.isValidTemplateName', () {
    test('accepts an ordinary name', () {
      expect(AccessTemplate.isValidTemplateName('conveyor'), isTrue);
      expect(AccessTemplate.isValidTemplateName('Schneider ATV320'), isTrue);
    });

    test('rejects empty and whitespace-only names', () {
      expect(AccessTemplate.isValidTemplateName(''), isFalse);
      expect(AccessTemplate.isValidTemplateName('   '), isFalse);
      expect(AccessTemplate.isValidTemplateName('\t\n'), isFalse);
    });

    test('rejects an untrimmed name', () {
      expect(AccessTemplate.isValidTemplateName(' conveyor'), isFalse);
      expect(AccessTemplate.isValidTemplateName('conveyor '), isFalse);
    });

    test('rejects a name longer than 64 characters, accepts one of exactly 64', () {
      expect(AccessTemplate.isValidTemplateName('c' * 64), isTrue);
      expect(AccessTemplate.isValidTemplateName('c' * 65), isFalse);
    });

    test('is a predicate — the constructor does not throw on an invalid name', () {
      expect(AccessTemplate(name: '', rules: const <String, AccessGroup>{}).name,
          '');
    });
  });

  _resolverTests();
}

// ---------------------------------------------------------------------------
// TagBindingResolver — the mutable snapshot the policy holds forever.
// ---------------------------------------------------------------------------

/// The bound conveyor key from the phase's acceptance criterion.
const String _cn04 = 'CN04.conveyor';

TagBindingResolver _loadedResolver({String templateName = 'conveyor'}) {
  final resolver = TagBindingResolver();
  resolver.setSnapshot(
    keyToTemplate: <String, String>{_cn04: templateName},
    templates: <String, AccessTemplate>{'conveyor': _conveyor()},
  );
  return resolver;
}

void _resolverTests() {
  group('TagBindingResolver snapshot state', () {
    test('a fresh resolver is neverLoaded and answers the operate floor', () {
      // 2026-09-02 ruling: every tag write requires at least `operate`. A
      // resolver that has never loaded reads exactly like a station with
      // nothing bound — the floor, not unrestricted. The anonymous session
      // maps to the Operator role, which holds `operate`, so a booting panel
      // stays usable; an account deliberately stripped of `operate` does not
      // get a free window while templates load.
      final resolver = TagBindingResolver();
      expect(resolver.state, TagBindingSnapshotState.neverLoaded);
      expect(resolver.groupFor(_cn04, 'p_cfg_ManualFreq'), AccessGroup.operate);
      expect(resolver.groupFor(_cn04, null), AccessGroup.operate);
      expect(resolver.groupFor('anything', 'anything'), AccessGroup.operate);
      expect(resolver.boundKeyCount, 0);
      expect(resolver.templateCount, 0);
    });

    test(
        'neverLoaded and loaded-but-empty both answer null and are told apart '
        'by state and by nothing else', () {
      // The property 04-05 and 04-08 depend on. `neverLoaded` is deliberately
      // permissive — a resolver does not know which keys exist, so "strict
      // until loaded" would refuse every write on a booting panel and for ever
      // on a station with no database. What must not be lost is that the two
      // cases are different *values*, so nothing can report "nobody has told me
      // yet" and "nothing is bound" the same way.
      final never = TagBindingResolver();
      final empty = TagBindingResolver()
        ..setSnapshot(
          keyToTemplate: const <String, String>{},
          templates: const <String, AccessTemplate>{},
        );

      expect(never.state, TagBindingSnapshotState.neverLoaded);
      expect(empty.state, TagBindingSnapshotState.loaded);
      expect(never.state, isNot(empty.state));

      for (final member in <String?>[null, 'p_cfg_ManualFreq', 'p_cmd_JogFwd']) {
        expect(never.groupFor(_cn04, member), AccessGroup.operate);
        expect(empty.groupFor(_cn04, member), AccessGroup.operate);
      }
      expect(never.boundKeyCount, empty.boundKeyCount);
      expect(never.templateCount, empty.templateCount);
      expect(never.unboundKeys(const [_cn04]), empty.unboundKeys(const [_cn04]));
    });

    test('setSnapshot moves neverLoaded to loaded and changes the answers', () {
      final resolver = TagBindingResolver();
      expect(resolver.groupFor(_cn04, 'p_cmd_JogFwd'), AccessGroup.operate);
      resolver.setSnapshot(
        keyToTemplate: <String, String>{_cn04: 'conveyor'},
        templates: <String, AccessTemplate>{'conveyor': _conveyor()},
      );
      expect(resolver.state, TagBindingSnapshotState.loaded);
      expect(resolver.groupFor(_cn04, 'p_cmd_JogFwd'), AccessGroup.operate);
    });

    test('replacing the snapshot does not change the object identity', () {
      // T-04-05. `accessPolicyProvider` is keepAlive and pure, and
      // `stateManProvider` reads it once and holds the resulting
      // GuardedStateMan for the life of the panel. If a template edit rebuilt
      // the policy it would rebuild `stateManProvider` and drop every OPC UA
      // connection on the station. So the policy captures one callback on one
      // long-lived object, and a template edit replaces that object's snapshot.
      final resolver = TagBindingResolver();
      final before = resolver;
      resolver.setSnapshot(
        keyToTemplate: <String, String>{_cn04: 'conveyor'},
        templates: <String, AccessTemplate>{'conveyor': _conveyor()},
      );
      resolver.setSnapshot(
        keyToTemplate: <String, String>{_cn04: 'schneider'},
        templates: <String, AccessTemplate>{
          'schneider': AccessTemplate(
            name: 'schneider',
            rules: <String, AccessGroup>{'p_cmd_JogFwd': AccessGroup.device},
          ),
        },
      );
      expect(
        identical(before, resolver),
        isTrue,
        reason: 'the resolver must be re-pointed in place. Making it '
            'immutable and rebuilding AccessPolicy on every template edit '
            'would rebuild stateManProvider and drop every OPC UA connection '
            'on the panel.',
      );
      // And the answers did move, so the identity is not being preserved by
      // the snapshot having failed to land.
      expect(resolver.groupFor(_cn04, 'p_cmd_JogFwd'), AccessGroup.device);
      expect(resolver.groupFor(_cn04, 'p_cfg_ManualFreq'), AccessGroup.operate);
    });

    test('markStale changes no answer', () {
      // 04-05's T-04-26: a load that failed against a snapshot already in
      // memory keeps answering from it. If markStale changed an answer, the
      // keep-the-previous-snapshot rule would be cosmetic.
      final resolver = _loadedResolver();
      final before = <String?, AccessGroup?>{
        null: resolver.groupFor(_cn04, null),
        'p_cmd_JogFwd': resolver.groupFor(_cn04, 'p_cmd_JogFwd'),
        'p_cfg_ManualFreq': resolver.groupFor(_cn04, 'p_cfg_ManualFreq'),
        'p_stat_Frequency': resolver.groupFor(_cn04, 'p_stat_Frequency'),
      };
      resolver.markStale();
      expect(resolver.state, TagBindingSnapshotState.stale);
      before.forEach((member, group) {
        expect(resolver.groupFor(_cn04, member), group,
            reason: 'markStale must change no answer');
      });
      expect(resolver.boundKeyCount, 1);
      expect(resolver.templateCount, 1);
      expect(resolver.templateForKey(_cn04), isNotNull);
    });

    test('markStale is a no-op on a resolver that has never been loaded', () {
      final resolver = TagBindingResolver();
      resolver.markStale();
      expect(resolver.state, TagBindingSnapshotState.neverLoaded,
          reason: 'there is nothing to be stale about');
      expect(resolver.groupFor(_cn04, 'p_cmd_JogFwd'), AccessGroup.operate);
    });

    test('a successful load after markStale returns the state to loaded', () {
      final resolver = _loadedResolver()..markStale();
      expect(resolver.state, TagBindingSnapshotState.stale);
      resolver.setSnapshot(
        keyToTemplate: <String, String>{_cn04: 'conveyor'},
        templates: <String, AccessTemplate>{'conveyor': _conveyor()},
      );
      expect(resolver.state, TagBindingSnapshotState.loaded);
    });
  });

  group('TagBindingResolver.groupFor', () {
    test('is assignable to TagBindingLookup with no adapter', () {
      // The assignability is exercised, not asserted in a comment — and the
      // typedef is synchronous, so this assignment is what stops anybody
      // making the binding read awaited on the write path.
      final resolver = _loadedResolver();
      final TagBindingLookup lookup = resolver.groupFor;
      expect(lookup(_cn04, 'p_cmd_JogFwd'), AccessGroup.operate);
      final policy = AccessPolicy(tagBindings: lookup);
      expect(policy.groupForTag(_cn04, member: 'p_cmd_JogFwd'),
          AccessGroup.operate);
    });

    test('answers the operate floor for a key nobody bound, on every member',
        () {
      // 2026-09-02 ruling: an unbound key is not unrestricted — every tag
      // write requires at least `operate`.
      final resolver = _loadedResolver();
      for (final member in <String?>[null, 'p_cmd_JogFwd', 'p_cfg_ManualFreq']) {
        expect(resolver.groupFor('CN05.conveyor', member), AccessGroup.operate);
      }
    });

    test('a dangling binding answers the operate floor, not a harder lock',
        () {
      // T-04-03, updated for the 2026-09-02 operate-floor ruling. A key
      // naming a template somebody removed in psql is indistinguishable,
      // from here, from a key nobody bound: both answer `operate`. The row
      // removed by hand still cannot freeze a conveyor — the Operator role
      // holds `operate` — and it no longer opens the key wider than any
      // other unbound key either.
      final resolver = _loadedResolver(templateName: 'deleted_template');
      expect(resolver.groupFor(_cn04, 'p_cmd_JogFwd'), AccessGroup.operate);
      expect(resolver.groupFor(_cn04, null), AccessGroup.operate);
      expect(resolver.templateForKey(_cn04), isNull);
    });

    test('the whole-key row of a bound template answers a scalar write', () {
      final resolver = TagBindingResolver()
        ..setSnapshot(
          keyToTemplate: <String, String>{_cn04: 'conveyor'},
          templates: <String, AccessTemplate>{
            'conveyor': _conveyor(wholeKey: AccessGroup.device),
          },
        );
      expect(resolver.groupFor(_cn04, null), AccessGroup.device);
      expect(resolver.groupFor(_cn04, 'p_stat_Frequency'), AccessGroup.device);
      expect(resolver.groupFor(_cn04, 'p_cmd_JogFwd'), AccessGroup.operate);
    });
  });

  group('TagBindingResolver through AccessPolicy — the phase acceptance criterion',
      () {
    test('a conveyor key locks p_cfg_ManualFreq while leaving p_cmd_JogFwd open',
        () {
      final resolver = _loadedResolver();
      final policy = AccessPolicy(tagBindings: resolver.groupFor);
      expect(policy.groupForTag(_cn04, member: 'p_cmd_JogFwd'),
          AccessGroup.operate);
      expect(policy.groupForTag(_cn04, member: 'p_cfg_ManualFreq'),
          AccessGroup.setpoints);
      // And the same answers arrive through the wire-surface entry point the
      // decorators actually call.
      expect(policy.groupForWireSurface('tag', _cn04, member: 'p_cmd_JogFwd'),
          AccessGroup.operate);
      expect(
          policy.groupForWireSurface('tag', _cn04, member: 'p_cfg_ManualFreq'),
          AccessGroup.setpoints);
    });

    test('an unmentioned member of a bound key answers the operate floor', () {
      final policy = AccessPolicy(tagBindings: _loadedResolver().groupFor);
      expect(policy.groupForTag(_cn04, member: 'p_stat_Frequency'),
          AccessGroup.operate);
      expect(policy.groupForTag(_cn04), AccessGroup.operate);
    });
  });

  group('TagBindingResolver snapshot copying', () {
    test('mutating the caller maps after setSnapshot changes no answer', () {
      final keyToTemplate = <String, String>{_cn04: 'conveyor'};
      final templates = <String, AccessTemplate>{'conveyor': _conveyor()};
      final resolver = TagBindingResolver()
        ..setSnapshot(keyToTemplate: keyToTemplate, templates: templates);

      keyToTemplate['CN05.conveyor'] = 'conveyor';
      keyToTemplate[_cn04] = 'schneider';
      templates.remove('conveyor');
      templates['schneider'] = AccessTemplate(
          name: 'schneider',
          rules: <String, AccessGroup>{'p_cmd_JogFwd': AccessGroup.administer});

      expect(resolver.groupFor(_cn04, 'p_cmd_JogFwd'), AccessGroup.operate);
      expect(resolver.groupFor('CN05.conveyor', 'p_cmd_JogFwd'),
          AccessGroup.operate);
      expect(resolver.boundKeyCount, 1);
      expect(resolver.templateCount, 1);
    });
  });

  group('TagBindingResolver reporting', () {
    TagBindingResolver plant() {
      final resolver = TagBindingResolver();
      resolver.setSnapshot(
        keyToTemplate: <String, String>{
          'CN04.conveyor': 'conveyor',
          'CN02.conveyor': 'conveyor',
          'CN21.conveyor': 'deleted_template',
          'ST101.drive': 'schneider',
        },
        templates: <String, AccessTemplate>{
          'conveyor': _conveyor(),
          'schneider': AccessTemplate(
              name: 'schneider',
              rules: <String, AccessGroup>{
                'p_cfg_AutoFreq': AccessGroup.device
              }),
        },
      );
      return resolver;
    }

    test('templateForKey returns the bound template, or null', () {
      expect(plant().templateForKey('CN04.conveyor')?.name, 'conveyor');
      expect(plant().templateForKey('ST101.drive')?.name, 'schneider');
      expect(plant().templateForKey('CN99.nothing'), isNull);
    });

    test('keysBoundTo returns every key naming the template, sorted', () {
      expect(plant().keysBoundTo('conveyor').toList(),
          <String>['CN02.conveyor', 'CN04.conveyor']);
      expect(plant().keysBoundTo('schneider').toList(), <String>['ST101.drive']);
      expect(plant().keysBoundTo('nobody_uses_this'), isEmpty);
    });

    test('keysBoundTo reports a dangling binding by the name it carries', () {
      expect(plant().keysBoundTo('deleted_template').toList(),
          <String>['CN21.conveyor']);
    });

    test('unboundKeys reports both an unbound key and a dangling binding', () {
      final keys = <String>[
        'CN04.conveyor', // bound, template exists
        'CN21.conveyor', // dangling — the template was removed
        'CN05.conveyor', // nobody bound it
        'ST101.drive', // bound, template exists
      ];
      expect(plant().unboundKeys(keys).toList(),
          <String>['CN21.conveyor', 'CN05.conveyor']);
    });

    test('unboundKeys preserves the order it was given', () {
      final keys = <String>['zz.key', 'aa.key', 'CN04.conveyor', 'mm.key'];
      expect(plant().unboundKeys(keys).toList(),
          <String>['zz.key', 'aa.key', 'mm.key']);
    });

    test('a never-loaded resolver reports every key as unbound', () {
      final keys = <String>['CN04.conveyor', 'ST101.drive'];
      expect(TagBindingResolver().unboundKeys(keys).toList(), keys);
    });

    test('boundKeyCount and templateCount are the summary line', () {
      expect(plant().boundKeyCount, 4);
      expect(plant().templateCount, 2);
    });

    test('boundKeyCount counts binding rows, dangling ones included', () {
      // The count is of what the table says, not of what resolves — a summary
      // that quietly excluded the dangling rows would hide the gap the
      // repository exists to surface.
      expect(plant().keysBoundTo('deleted_template'), hasLength(1));
      expect(plant().boundKeyCount, 4);
    });
  });
}
