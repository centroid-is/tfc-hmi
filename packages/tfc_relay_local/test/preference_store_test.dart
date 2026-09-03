/// Properties of the preference store that are true without a server.
///
/// The database-backed behaviour lives in `preferences_read_test.dart` and
/// `preference_change_feed_test.dart`, both `db`-tagged. What is here is
/// everything a `db` tag would only make harder to run: the absent `secret`
/// parameter, which is a property of the SOURCE, and the de-duplication
/// window's arithmetic, which is a property of a clock nobody has to
/// provision. 10-07 and 10-08 both split their suites this way and for this
/// reason — gating a property behind Docker is gating a property nobody runs.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Lines of [source] that are not `//` or `///` comments.
///
/// **The plan's acceptance criterion is `grep -c "secret" … == 0`, and it
/// cannot be met as written.** The file explains, at length, which parameter
/// it omits and why — the whole SEC-01 argument is unwriteable if the word may
/// not appear. 10-07 and 10-08 each hit the same shape and answered it the
/// same way: a sweep that flagged prose would make the honest explanation
/// impossible to write down, so the sweep reads code and the paragraph stays.
/// The property being defended is "no call site passes it", and that is what
/// is asserted below.
List<String> codeLines(String source) => source
    .split('\n')
    .where((line) {
      final trimmed = line.trimLeft();
      return !trimmed.startsWith('//') && !trimmed.startsWith('///');
    })
    .toList();

void main() {
  group('SEC-01: the secret parameter is never passed', () {
    final source =
        File('lib/src/data/preference_store.dart').readAsStringSync();

    test('no line of code in the store spells the secret parameter', () {
      final offenders =
          codeLines(source).where((line) => line.contains('secret:')).toList();

      expect(offenders, isEmpty,
          reason: 'the concrete Preferences class carries a '
              '{bool secret = false} on twelve members, and it routes the '
              'call to the OS keychain instead of the table. Passing it would '
              'turn one client-supplied flag into remote retrieval of the '
              'secure store (T-10-35). The interface being mirrored omits it, '
              'and the obvious future edit is to add it back for symmetry');
    });

    test('the sweep can see an offender', () {
      // Non-vacuous on purpose: a sweep over a file that will never contain
      // the needle passes forever whether or not it works.
      const seeded = '/// A doc comment mentioning secret: which is fine.\n'
          'await prefs.getString(key, secret: true);\n';

      expect(codeLines(seeded).where((l) => l.contains('secret:')), hasLength(1),
          reason: 'the call site must be seen and the doc comment must not; a '
              'sweep that saw both would be the one that cannot be satisfied, '
              'and one that saw neither would be decoration');
    });

    test('no write in the store skips the database', () {
      // The concrete class also carries `saveToDb:`. A call passing
      // `saveToDb: false` would put a value in the memory cache and nowhere
      // else — a preference that vanishes the next time the cache is rebuilt
      // from the table, with nothing anywhere saying it was never stored.
      final offenders = codeLines(source)
          .where((line) => line.contains('saveToDb:'))
          .toList();

      expect(offenders, isEmpty,
          reason: 'a write that skips Postgres is a write that undoes itself');
    });
  });
}
