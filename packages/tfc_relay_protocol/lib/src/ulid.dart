/// The idempotency id every write carries.
///
/// A `cmd` is minted **when the operator acted**, not at send time, and the
/// same id rides every re-send and every `writeStatus` re-query of that one
/// action (see `write_result.dart`). That is what lets the gateway answer
/// "applied / rejected / unknown / never received" about a specific button
/// press instead of about a specific packet.
///
/// Three properties, each load-bearing:
///
///  * **Unique.** Two operator actions that collide on one id merge into a
///    single entry in the gateway's dedup log, and one of the two writes
///    silently reports the other's outcome.
///  * **Roughly time-sortable.** The dedup log and the write-audit trail are
///    read in id order; a random-only id makes them unreadable.
///  * **Unguessable.** `writeStatus` is queried by id. A predictable id lets a
///    hostile client re-query another operator's write outcome, so the random
///    component comes from [Random.secure] — never the default generator,
///    which is seeded predictably and is not intended for anything an attacker
///    can see.
///
/// Hand-rolled rather than taken from `package:ulid`: this package is imported
/// by the Flutter app, and every dependency added here is a future
/// version-constraint conflict in an app that already pins Flutter (CLAUDE.md).
/// What the write path needs is uniqueness plus rough sortability, not
/// spec-perfect ULID monotonicity — that is ~40 lines, and `dart:math` ships
/// with the SDK.
library;

import 'dart:math';

/// Crockford base32: no I, L, O or U, so an id read off a panel and typed into
/// a support ticket cannot be transcribed wrong. Ordered by value, so
/// comparing the encoded strings compares the underlying numbers.
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// 10 characters × 5 bits, of which the low 48 are the millisecond timestamp.
const int _timeChars = 10;

/// 16 characters × 5 bits = 80 bits of randomness.
const int _randomChars = 16;

/// Milliseconds are a 48-bit field. Masking (rather than widening) is what
/// guarantees the timestamp can never spill into the random characters, even
/// if a caller passes a nonsense clock reading.
const int _msMask = (1 << 48) - 1;

final Random _entropy = Random.secure();

/// The last timestamp minted, and the random digits issued for it. Held so a
/// second call inside the same millisecond can increment rather than redraw:
/// two ids from one millisecond must still sort in the order the operator
/// pressed the buttons.
int _lastMs = -1;
final List<int> _lastRandom = List<int>.filled(_randomChars, 0);

/// Returns a new 26-character idempotency id.
///
/// [nowMs] overrides the clock — the tests mint at an exact millisecond, and
/// a caller that already read the clock should pass it rather than read it
/// again. Values outside 48 bits are masked into range.
String newUlid({int? nowMs}) {
  final ms = (nowMs ?? DateTime.now().millisecondsSinceEpoch) & _msMask;

  if (ms == _lastMs) {
    _bumpEntropy();
  } else {
    _lastMs = ms;
    _drawEntropy();
  }

  final out = List<String>.filled(_timeChars + _randomChars, '0');
  var remaining = ms;
  for (var i = _timeChars - 1; i >= 0; i--) {
    out[i] = _alphabet[remaining & 0x1f];
    remaining >>= 5;
  }
  for (var i = 0; i < _randomChars; i++) {
    out[_timeChars + i] = _alphabet[_lastRandom[i]];
  }
  return out.join();
}

void _drawEntropy() {
  for (var i = 0; i < _randomChars; i++) {
    _lastRandom[i] = _entropy.nextInt(32);
  }
}

/// Base-32 increment from the least significant digit, so the encoded suffix
/// sorts strictly after the previous one within the same millisecond.
///
/// Exhausting 80 bits inside one millisecond is unreachable — it needs 2^80
/// writes from one client in 1 ms — but if it ever happened, redrawing keeps
/// ids unique (the property that protects the dedup log) at the cost of
/// ordering within that millisecond alone.
void _bumpEntropy() {
  for (var i = _randomChars - 1; i >= 0; i--) {
    if (_lastRandom[i] < 31) {
      _lastRandom[i]++;
      return;
    }
    _lastRandom[i] = 0;
  }
  _drawEntropy();
}
