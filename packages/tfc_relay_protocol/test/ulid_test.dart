import 'package:test/test.dart';
import 'package:tfc_relay_protocol/src/ulid.dart';

/// One property per test. A `cmd` id that is short, non-unique, non-sortable
/// or guessable each breaks a different part of the write path, so each is
/// asserted on its own.
void main() {
  const crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  test('a ULID is 26 characters long', () {
    expect(newUlid(), hasLength(26));
    expect(newUlid(nowMs: 0), hasLength(26));
    expect(newUlid(nowMs: (1 << 48) - 1), hasLength(26),
        reason: 'the timestamp field never overflows into the random field');
  });

  test('a ULID uses only the Crockford base32 alphabet', () {
    for (var i = 0; i < 200; i++) {
      final id = newUlid();
      for (final unit in id.split('')) {
        expect(crockford.contains(unit), isTrue,
            reason: '"$unit" in $id is outside Crockford base32 — I, L, O and '
                'U are excluded so an operator reading an id off a screen '
                'cannot transcribe it wrong');
      }
    }
  });

  test('the timestamp is the leading 10 characters, zero at epoch', () {
    expect(newUlid(nowMs: 0).substring(0, 10), '0000000000');
    expect(newUlid(nowMs: (1 << 48) - 1).substring(0, 10), '7ZZZZZZZZZ',
        reason: '48 bits of milliseconds is the whole timestamp field');
  });

  test('ULIDs minted in different milliseconds sort in time order', () {
    final earlier = newUlid(nowMs: 1786000000000);
    final later = newUlid(nowMs: 1786000000001);
    final muchLater = newUlid(nowMs: 1786000060000);

    expect(earlier.compareTo(later), lessThan(0));
    expect(later.compareTo(muchLater), lessThan(0),
        reason: 'a dedup log sorted by cmd is sorted by when the operator '
            'acted');
  });

  test('ULIDs minted within one millisecond are distinct and ordered', () {
    final ids = [for (var i = 0; i < 500; i++) newUlid(nowMs: 1786000000000)];

    expect(ids.toSet(), hasLength(ids.length),
        reason: 'two operator actions in the same millisecond must never '
            'collide into one dedup entry');
    final sorted = [...ids]..sort();
    expect(sorted, ids,
        reason: 'the within-millisecond counter keeps later actions sorting '
            'after earlier ones');
  });

  test('an id within one millisecond is not its predecessor plus one', () {
    // WR-03. Standard ULID monotonicity increments the suffix by 1, which
    // keeps the ordering and hands anyone holding one id every neighbouring
    // id from the same millisecond — and writeStatus is queried by id.
    var adjacent = 0;
    String? previous;
    for (var i = 0; i < 500; i++) {
      final id = newUlid(nowMs: 1786000000000);
      if (previous != null && _isSuccessorOf(id, previous)) adjacent++;
      previous = id;
    }
    // A random step of exactly 1 is legitimate (~1/65536 per pair, so ~0.76%
    // of 499-pair runs see one) — the property WR-03 guards is that steps are
    // not PREDICTABLY +1. Standard-ULID monotonicity would make all 499
    // adjacent; a handful by chance is expected noise.
    expect(adjacent, lessThan(10),
        reason: 'the step between two ids in one millisecond is a secure '
            'random delta, so the next id cannot be computed from this one — '
            'all-adjacent (499) is the standard-ULID regression this forbids');
  });

  test('10,000 ULIDs from a tight loop are all distinct', () {
    final ids = <String>{};
    for (var i = 0; i < 10000; i++) {
      ids.add(newUlid());
    }
    expect(ids, hasLength(10000));
  });

  test('the random component differs across milliseconds', () {
    final suffixes = <String>{
      for (var ms = 1786000000000; ms < 1786000000100; ms++)
        newUlid(nowMs: ms).substring(10),
    };

    expect(suffixes, hasLength(100),
        reason: 'a hostile client that guesses a cmd can re-query another '
            "operator's write outcome, so the entropy is Random.secure()");
  });

  test('the random component is 16 characters and varies within a run', () {
    final a = newUlid(nowMs: 5).substring(10);
    final b = newUlid(nowMs: 6).substring(10);

    expect(a, hasLength(16));
    expect(b, hasLength(16));
    expect(a, isNot(b));
  });
}

/// True when [id] is exactly the base-32 successor of [previous] — what a
/// plain `+1` monotonicity counter produces.
bool _isSuccessorOf(String id, String previous) {
  const crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  final digits = [for (final c in previous.split('')) crockford.indexOf(c)];
  for (var i = digits.length - 1; i >= 10; i--) {
    if (digits[i] < 31) {
      digits[i]++;
      break;
    }
    digits[i] = 0;
  }
  return id == [for (final d in digits) crockford[d]].join();
}
