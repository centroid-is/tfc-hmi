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

/// One recorded write outcome, the instant it was recorded, and who recorded
/// it.
final class WriteOutcomeEntry {
  const WriteOutcomeEntry(this.result, this.atMs, this.ownerHint);

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
  void record(String cmd, WriteResult result, {String? ownerHint}) {
    prune();
    _entries[cmd] = WriteOutcomeEntry(result, now(), ownerHint);
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
