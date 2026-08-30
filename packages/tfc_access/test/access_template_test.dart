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
}
