// A templated key that has not been resolved must not be subscribed to.
//
// `resolveKey` substitutes `$name` from values published by OptionVariable
// assets, and returns the key UNCHANGED when it has nothing to substitute.
// The home page's throughput readouts use `Line1.$sb_line_stats_period`, and
// they subscribe before the OptionVariable that owns that variable has
// awaited its provider and published it -- 98 times per startup in the field
// log. Subscribing anyway asks the server for a node that cannot exist, and
// the caller gets `null`: the same answer a dead tag, a renamed node and a
// mapping with no server alias all give.

import 'package:tfc_dart/core/state_man.dart';
import 'package:test/test.dart';

void main() {
  group('unresolvedVariables', () {
    test('finds the variable in a templated key', () {
      expect(unresolvedVariables(r'Line1.$sb_line_stats_period'),
          {'sb_line_stats_period'});
    });

    test('finds several', () {
      expect(unresolvedVariables(r'$line.avg$period'), {'line', 'period'});
    });

    test('is empty for a plain key', () {
      expect(unresolvedVariables('Line1.avgBPM30Minute'), isEmpty);
      expect(unresolvedVariables('STM02.CN04.PX02.Output'), isEmpty);
    });

    test('is empty once substitution has happened', () {
      expect(unresolvedVariables('Line1.avgBPM5Minute'), isEmpty);
    });

    test('does not treat a bare dollar as a variable', () {
      expect(unresolvedVariables(r'weird$'), isEmpty);
      expect(unresolvedVariables(r'a$1b'), isEmpty);
    });
  });

  group('unresolvedKeyMessage', () {
    test('names the key and what it is waiting for', () {
      final m = unresolvedKeyMessage(r'Line1.$sb_line_stats_period');
      expect(m, contains('Line1.\$sb_line_stats_period'));
      expect(m, contains('\$sb_line_stats_period'));
      expect(m, contains('OptionVariable'));
    });

    test('does not read as a dead tag', () {
      // The whole point: distinguishable from BadNodeIdUnknown, a missing
      // server alias, or a key that simply has no value yet.
      final m = unresolvedKeyMessage(r'Line2.$period');
      expect(m.toLowerCase(), isNot(contains('not found')));
      expect(m.toLowerCase(), contains('waiting on'));
    });
  });
}
