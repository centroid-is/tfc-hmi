/// What this gateway has witnessed happen to a write, and — just as
/// load-bearing — the window it is entitled to have an opinion about.
///
/// Split out of `value_handlers.dart` because of the lifetime, which is the
/// whole of 04-REVIEW CR-02. The handlers are built **per session**
/// (`relay_session.dart`, deliberately); the log must not be, because the only
/// path that ever runs `writeStatus` is a client re-querying after a link
/// death, and after a link death the session is always a new one. A log that
/// died with the socket was therefore always empty at exactly the moment it was
/// asked, and an empty log answered [WriteNotReceived] — *the* outcome that
/// tells an operator a re-send is safe — for precisely the commands whose fate
/// was unknown. The gateway told the panel a write it had received, forwarded,
/// and possibly applied had never arrived.
///
/// ## `not_received` needs positive evidence
///
/// Two clocks bound the claim, and both are the gateway's own:
///
///  * **[startedAtMs]** — when this log began. A command minted before that is
///    one this gateway was not present for. Absence from a log that did not
///    exist yet is not evidence of anything, so the answer is [WriteUnknown].
///  * **`now()`** — a command minted in the *future* is a panel whose clock
///    runs ahead. `ClientConfig.implausibleClockThreshold` defaults to five
///    minutes and 04-CONTEXT rules that skew warns and keeps going, so skew of
///    that size is anticipated elsewhere in the same phase. Unclamped, a panel
///    ahead by Δ bought itself a `not_received` window of `ttl + Δ`, and one
///    ahead by more than the elapsed time passed the check trivially, forever.
///
/// Inside both bounds and absent from the log, `not_received` is a positive
/// claim: this gateway was up, it was recording, and it never saw the command.
///
/// ## Who may read an entry (T-04-05)
///
/// The log was per session so that one client's `writeStatus` could not answer
/// about another's write. Server-wide, the scoping is the `cmd` itself: it is a
/// 26-character ULID with 80 bits of randomness minted at the operator's
/// keyboard, so a client can only ask about commands it minted or watched go
/// past. That is a capability argument, and it is weaker than an identity
/// check — Phase 6 introduces an authenticated client identity, and the entry
/// carries [ownerHint] so that the read can be narrowed to it without moving
/// the log back inside a socket's lifetime.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// The write a recorded outcome belongs to: the tag, the payload, and the
/// compare-and-set guard it was sent under.
///
/// A record rather than three loose fields on the entry, because the question
/// the gateway asks of it is one question — "is the frame in my hand the same
/// operator action as the one I already answered?" — and three fields are three
/// comparisons that can drift apart. A `matches` written half-way (key only, or
/// key and value) is the failure mode this shape exists to make awkward, and
/// [WriteOutcomeEntry.matches] is the single place it is answered.
///
/// **`expect` is in here deliberately** (05-03 D-P5-B). "Set 1450" and "set
/// 1450 only if it still reads 1200" are two different operator intents;
/// answering the unguarded one from the guarded one's log entry would report
/// that a check passed which was never made.
typedef WriteFingerprint = ({String key, Object? value, Object? expect});

/// One recorded write outcome, the instant it was recorded, who recorded it,
/// and the request it was recorded for.
final class WriteOutcomeEntry {
  const WriteOutcomeEntry(this.result, this.atMs, this.ownerHint,
      [this.fingerprint]);

  /// What became of the write. In-flight writes are recorded too, as
  /// [WriteUnknown]: a `writeStatus` crossing a write that is still upstream
  /// must not answer `not_received` about a command on its way to a machine.
  final WriteResult result;

  /// The gateway's clock when this was recorded.
  final int atMs;

  /// The session that issued the write, for the Phase 6 narrowing. Carried,
  /// never read as a filter today — a reconnect is by definition a different
  /// session, and filtering on it would rebuild the defect this log exists to
  /// fix.
  final String? ownerHint;

  /// The write this outcome is about, or null when the recorder had nothing to
  /// fingerprint.
  ///
  /// Nullable rather than required because an entry can be constructed without
  /// one — a handler's own default log and the unit tests do — and recording
  /// honestly that the request is unknown beats inventing one. Production has
  /// no such caller: both record sites in `value_handlers.dart` have the
  /// decoded [WriteParams] in scope.
  ///
  /// **A null fingerprint never matches** ([matches]). Absence of the request
  /// is not evidence that a replay is the same request, and the two directions
  /// cost very different things: a false "not the same" is an
  /// `INVALID_PARAMS` refusal, which on the write path means "definitively no
  /// effect" and is true for the second write as well; a false "the same"
  /// reports one write's outcome for another, and puts "applied" on a setpoint
  /// nobody applied.
  final WriteFingerprint? fingerprint;

  /// Whether [other] is the same write this outcome was recorded for.
  ///
  /// The key compares as a string; the value and the guard compare with
  /// `jsonEquals` (`json_equality.dart`), which is deep, insensitive to JSON
  /// object key order, and holds numbers to their runtime type so a DINT `1`
  /// and a REAL `1.0` stay two different writes. `DynamicValue.operator ==`
  /// would compare quality and sourceTime that a write payload does not have,
  /// and comparing encoded strings would make key order significant — both are
  /// argued out in `json_equality.dart`'s library doc.
  ///
  /// The caller is the idempotency window at `value_handlers.dart`'s
  /// duplicate-cmd decision, and it is the *only* caller: the payload it hands
  /// over has been through `sanitize` at ingress, which is what bounds the
  /// depth `jsonEquals` recurses to.
  bool matches(WriteFingerprint other) {
    final mine = fingerprint;
    if (mine == null) return false;
    return mine.key == other.key &&
        jsonEquals(mine.value, other.value) &&
        jsonEquals(mine.expect, other.expect);
  }
}

/// Every write outcome this gateway is still prepared to speak about.
///
/// One per server, handed to each session's handlers. Pruned on access rather
/// than by a timer: it is data with a clock passed in, not a scheduler, so a
/// test models a stale entry with arithmetic instead of a sleep.
final class WriteOutcomeLog {
  WriteOutcomeLog({required this.ttl, required this.now})
      : startedAtMs = now();

  /// How long an outcome is kept, and the width of the `not_received` window.
  final Duration ttl;

  /// Wall-clock epoch milliseconds, injected: every promise here is arithmetic
  /// about *when*.
  final int Function() now;

  /// The gateway's own clock at the moment this log began recording.
  ///
  /// The lower bound on every `not_received`. On a running server that is boot
  /// time, so the window opens once and stays open across every reconnect —
  /// which is the difference between "I was watching and it never came" and "I
  /// have only just started watching".
  final int startedAtMs;

  final _entries = <String, WriteOutcomeEntry>{};

  /// How many outcomes are being held. Read by the test that proves the log is
  /// bounded (T-04-06); nothing in production depends on it.
  int get recordedOutcomes => _entries.length;

  /// Records [result] for [cmd], replacing whatever was there.
  ///
  /// [fingerprint] is the write the outcome is about, carried so a later frame
  /// under the same id can be told from it — see [WriteOutcomeEntry.matches].
  /// Optional, because an entry with nothing to fingerprint records honestly
  /// and then matches nothing.
  void record(String cmd, WriteResult result,
      {String? ownerHint, WriteFingerprint? fingerprint}) {
    prune();
    _entries[cmd] = WriteOutcomeEntry(result, now(), ownerHint, fingerprint);
  }

  /// The entry held for [cmd] after pruning, or null.
  WriteOutcomeEntry? entryFor(String cmd) {
    prune();
    return _entries[cmd];
  }

  /// Whether [cmd] currently has an entry — used by the duplicate-cmd refusal
  /// (04-REVIEW CR-05), which must not prune-and-forget its way into allowing
  /// one id to cover two actuations inside the window.
  bool holds(String cmd) => entryFor(cmd) != null;

  /// Whether this log was recording when [mintedAtMs] was minted, and whether
  /// that instant is one the gateway's own clock can vouch for.
  ///
  /// False for a command from before [startedAtMs] and for one from the
  /// future. Both are the "forgetting is not evidence" case wearing different
  /// clothes, and both must answer unknown rather than never-received.
  bool witnessed(int mintedAtMs) =>
      mintedAtMs >= startedAtMs && mintedAtMs <= now();

  /// Whether [mintedAtMs] is inside the window this log still answers for.
  bool insideWindow(int mintedAtMs) =>
      now() - mintedAtMs <= ttl.inMilliseconds;

  /// Drops everything past the TTL.
  void prune() {
    final horizon = now() - ttl.inMilliseconds;
    _entries.removeWhere((_, entry) => entry.atMs < horizon);
  }
}
