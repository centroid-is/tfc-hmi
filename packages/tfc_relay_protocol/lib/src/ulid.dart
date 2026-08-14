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
///    hostile client re-query another operator's write outcome, so every
///    random digit — the 80-bit draw at the start of each millisecond and the
///    delta between two ids inside one — comes from [Random.secure], never the
///    default generator, which is seeded predictably and is not intended for
///    anything an attacker can see.
///
///    Standard ULID monotonicity increments the previous suffix by one, which
///    keeps the ordering but makes the neighbours of a known id enumerable.
///    Here the increment is itself a secure random positive delta: the suffix
///    still sorts strictly after the previous one, and knowing one id says
///    nothing about the next. It costs a bounded slice of the 80-bit space per
///    id within a millisecond, which is not a budget any client can spend.
///
///    None of this makes an id an authorisation token. `writeStatus`
///    authorisation is a session property (WRT-02, Phase 5); id opacity is
///    defence in depth behind it, not instead of it.
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

/// Upper bound on the random step between two ids minted in one millisecond.
/// Large enough that neighbours are not enumerable, small enough that the
/// 80-bit suffix cannot be walked off the end by any real client.
const int _maxBump = 1 << 16;

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

/// Base-32 addition from the least significant digit, so the encoded suffix
/// sorts strictly after the previous one within the same millisecond.
///
/// The delta is a secure random number in `[1, _maxBump]` rather than 1: both
/// keep the ordering, but +1 hands anyone holding one id every neighbouring id
/// from the same millisecond. At most 2^16 of the 80-bit space per id, so
/// exhausting a millisecond still needs ~2^64 writes from one client inside
/// it; if it ever happened, redrawing keeps ids unique — the property that
/// protects the dedup log — at the cost of ordering within that millisecond
/// alone.
void _bumpEntropy() {
  var carry = 1 + _entropy.nextInt(_maxBump);
  for (var i = _randomChars - 1; i >= 0 && carry > 0; i--) {
    final sum = _lastRandom[i] + carry;
    _lastRandom[i] = sum & 0x1f;
    carry = sum >> 5;
  }
  // Carry left over means the 80 bits wrapped, and a wrapped suffix would
  // sort before its predecessor.
  if (carry > 0) _drawEntropy();
}
