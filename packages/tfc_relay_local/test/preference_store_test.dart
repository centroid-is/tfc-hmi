/// Properties of the preference store that are true without a server.
///
/// The database-backed behaviour lives in `preferences_read_test.dart` and
/// `preference_change_feed_test.dart`, both `db`-tagged. What is here is
/// everything a `db` tag would only make harder to run: the absent `secret`
/// parameter, which is a property of the SOURCE; and the de-duplication
/// window's arithmetic, which is a property of a clock nobody has to
/// provision. 10-07 and 10-08 both split their suites this way and for this
/// reason — gating a property behind Docker is gating a property nobody runs.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('SEC-01: the secret parameter never appears', () {
    final source =
        File('lib/src/data/preference_store.dart').readAsStringSync();

    test('the store does not spell "secret" anywhere at all', () {
      expect(source.contains('secret:'), isFalse,
          reason: 'the concrete Preferences class carries a '
              '{bool secret = false} at twelve sites, and passing it would '
              'turn one client-supplied flag into remote retrieval of the '
              'secure store (T-10-35). The interface being mirrored omits it; '
              'this file must never re-introduce it at a call site');
    });

    test('no call site in the file passes a named argument to a setter', () {
      // The concrete class also carries `saveToDb:`, and a call that passed
      // `saveToDb: false` would put a value in the memory cache and nowhere
      // else — a preference that vanishes on the next reconnect.
      expect(source.contains('saveToDb: false'), isFalse,
          reason: 'a write that skips Postgres is a write that undoes itself '
              'the next time the cache is refilled from the table');
    });
  });
}
