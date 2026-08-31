/// Which tags a station may see, and which it may actuate.
///
/// **Source: 06-CONTEXT decision 2**, which records the user's framing as the
/// reason this file exists at all: *"What if it should be hidden. Let's think
/// about the future even though we don't implement all at once."* So the seam
/// ships now and the policy data does not. This phase's shipped rule is
/// [AllVisibleOperatorWrites] — everything visible, `operate` may write — and
/// per-key hiding later becomes patterns in the token file rather than new
/// plumbing, because every enforcement point already exists and is tested.
///
/// ## What breaks in the plant without this file
///
/// A wall display in the canteen can start a conveyor. `view` and `operate`
/// are two words in a token file with nothing behind them until something
/// compares them, and this interface is that comparison's only home
/// (T-06-35).
///
/// The quieter half is [canSee]. A gateway that answers *forbidden* for a tag
/// a station may not see has told that station the tag exists; ask about a
/// thousand names, keep the ones answered *forbidden* instead of *unknown*,
/// and the plant's address space has been enumerated by a peer that may not
/// read a byte of it (T-06-36). CONTEXT locks the answer as architecture: a
/// hidden key is **indistinguishable from a key that does not exist**. That is
/// why [canSee] is a visibility question and not a permission question — there
/// is no "you may not see this" answer on the wire, only "this source does not
/// serve that tag".
///
/// ## Both members are synchronous, and that is a decision
///
/// `session_handlers.dart:255-264` catches a `SubscriptionLimitExceeded` for a
/// race that is unreachable today — there is no `await` between the
/// `atCapacity` check and the `put` — and its comment names *this phase* as
/// "the obvious thing to introduce the await that opens the race". An
/// asynchronous policy is exactly that `await`. The cost of opening it is not
/// theoretical: a subscription that slipped past a full ceiling surfaces as
/// `-32011 handlerFailed`, whose documented meaning is "possibly transient:
/// retrying is legitimate", so a panel would retry a limit it can never get
/// under.
///
/// There is nothing here to await. The shipped policy is a constant and a role
/// comparison, and the token file the role came from is already in memory
/// (`file_token_validator.dart`). A future policy that genuinely needs a
/// directory lookup should cache into memory on reload — the way the token set
/// does — rather than make this interface asynchronous. `policy_test.dart`
/// pins the return types by mirrors so the change cannot be made absent-
/// mindedly.
///
/// ## The open case: a key hidden *after* subscribe
///
/// 06-RESEARCH §E.5, recorded here because this is where whoever opens it will
/// be standing. CONTEXT asks what happens to the `u` and resync frames of a
/// live subscription whose key becomes hidden. **In Phase 6 that state is
/// unreachable**, and it is unreachable structurally rather than by luck:
/// policy is static per session (the [Identity] is minted once, in `_hello`,
/// and `relay_session.dart` assigns it with `??=` so it cannot be replaced),
/// and the only thing that changes a live session's authorization is
/// revocation — which does not re-evaluate anything, it closes the session
/// with `CloseCodes.authExpired`. There is no live re-evaluation path, and the
/// push machinery has no arm for one: `TickEngine` fans out from
/// `SubscriptionState.watch` listeners attached at subscribe time and never
/// re-consults a key list.
///
/// So whoever adds dynamic policy — a policy that can change under a live
/// session — is opening that case, and owes it three things this phase does
/// not have: a way to drop a live subscription's handle mid-stream, a decision
/// about whether the client is told (it must not be, or the drop leaks the
/// existence the hiding rule conceals), and a resync that does not walk the
/// panel's cache backwards.
library;

import '../auth/identity.dart';

/// The one question every key-touching surface asks about a station.
///
/// Injected at [RelayServer] construction in the style `TokenValidator` is
/// (`relay_server.dart:141`), so a deployment supplies its own and a test
/// supplies one that hides a tag. It is consulted through
/// `PolicyStateMan` — one decorator per session, between the handlers and
/// the shared source — rather than at each call site, which is the property
/// that keeps a handler added in Phase 10 from being able to forget it
/// (T-06-38).
///
/// Deliberately **not** a member of `StateManApi` or any of its four
/// sub-interfaces (06-CONTEXT amendment 3). `api_surface_test.dart:213-226`
/// calls that 49-member set "the access-control policy" — capability there is
/// defined by surface — so an access-control *query* on it would be the thing
/// it guards asking itself for permission. The seam is server-side, and this
/// package is downstream of the protocol package, so the mistake is not
/// expressible.
abstract interface class KeyPolicy {
  /// Whether [identity] may know that [key] exists.
  ///
  /// A false answer means the key is **absent**, not refused: it is filtered
  /// out of `keys`, which is the one getter `read`, `readFresh`, `readMany`,
  /// `subscribe` and `write` all already gate on, so a hidden tag takes the
  /// nonexistent-tag path on every one of them without any of them being
  /// edited (06-RESEARCH §E.2). Answering "forbidden" instead is the
  /// information disclosure the hiding rule exists to prevent.
  bool canSee(String key, Identity identity);

  /// Whether [identity] may actuate [key].
  ///
  /// Only ever asked about a key [canSee] has already allowed — the existence
  /// check runs first on the write path, so a hidden key is refused as
  /// nonexistent and never reaches this question. That ordering is what keeps
  /// the two refusals from leaking into each other, and `value_handlers.dart`
  /// carries it as a comment beside the gate.
  ///
  /// **This one answer gates both `write` and `holdToRun`** (orchestrator
  /// ruling OQ5). A hold-to-run engage is reached only through
  /// `write(hold: true)` (`value_handlers.dart:541-556`) — there is no second
  /// wire method — so one check covers both today. The obvious future split is
  /// a third member, `canHold`, for a deployment that lets a station change a
  /// setpoint but not jog a machine by hand; it is deliberately not built,
  /// because a member with no policy data behind it is a name pretending to be
  /// a rule.
  bool canWrite(String key, Identity identity);
}

/// Everything is visible; an `operate` station may write. **The shipped
/// policy.**
///
/// Named for what it does rather than for what it lacks, which is
/// `PermissiveTokenValidator`'s argument (`token_validator.dart:70-73`) and
/// holds for the same reason: a deployment still running this in Phase 12 must
/// be legible in a config diff. `NoPolicy` or `DefaultPolicy` would read as
/// something somebody chose.
///
/// Both answers are honest rather than generous. Everything *is* visible —
/// there is no policy data in this phase to hide anything with, and a seam
/// that hid a tag nobody configured would be policy invented by the plumbing.
/// And `operate` really is the write rule: it is the whole of CONTEXT decision
/// 2's shipped clause, and it is also what keeps every fixture in this
/// workspace writing, because `PermissiveTokenValidator` grants `operate` for
/// exactly that reason (`token_validator.dart:85-94`).
final class AllVisibleOperatorWrites implements KeyPolicy {
  const AllVisibleOperatorWrites();

  @override
  bool canSee(String key, Identity identity) => true;

  @override
  bool canWrite(String key, Identity identity) =>
      identity.role == Role.operate;
}
