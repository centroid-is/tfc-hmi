/// The method names this harness speaks — and why they are not the wire's.
///
/// There are two method tables in this repository and there have to be.
/// `packages/tfc_relay_protocol/lib/src/methods.dart` is the real one: the
/// names on it are, by construction, things any connected client may invoke,
/// which is why `test/api_surface_test.dart` writes the surface down as
/// literals and fails when it grows. This table is the other one, and every
/// name below that is not reused from the real table exists only so a test can
/// make a value arrive.
///
/// That distinction is the whole reason for the file. Half the names here —
/// [setValue], [dropKey], [disconnectUpstream] — are levers that stand in for
/// the plant. `lib/src/harness.dart:39-44` already makes the argument from the
/// other side: those levers are kept off `StateManApi` because "a method that
/// exists is a thing any connected client may invoke, so adding one is an
/// access-control decision, not a convenience". A harness that declared them in
/// `Methods` would hand that decision to whoever next copies a constant, and a
/// gateway registering the harness table by accident would let a connected
/// client tell the plant what the plant is reading. So they live here, in a
/// `publish_to: none` test-kit package that no server imports, under a
/// [prefix] that makes the boundary greppable.
///
/// Three names *are* reused from the real table, because the real table already
/// names the concept and inventing a second spelling would make the harness
/// prove a property against a name that does not ship: `Methods.write` and
/// `Methods.update` are used verbatim.
///
/// `Methods.subscribe` is deliberately **not** reused, and its absence is a
/// decision rather than an oversight. This harness carries the served source's
/// whole store: there is one session, it opens with a snapshot and every later
/// change is pushed. Per-key subscription accounting — handles, unsubscribe,
/// which client asked for what — is Phase 3's session layer, and borrowing the
/// wire's name for something that does not do that would make a later reader
/// believe subscription semantics had already been proven over this channel.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// Every method name the channel harness registers or sends.
abstract final class HarnessMethods {
  /// What marks a name as belonging to the harness rather than to the wire.
  ///
  /// A grep for this string finds every test-only method in one pass, and a
  /// name carrying it can never collide with a real one: nothing in
  /// [Methods] contains a dot.
  static const prefix = 'harness.';

  // --------------------------------------------------------- the value path

  /// A forced round trip for one key — `StateManApi.readFresh`.
  static const readFresh = '${prefix}readFresh';

  /// One round trip for many keys — `StateManApi.readMany`.
  ///
  /// Distinct from N [readFresh] calls on purpose: the served source counts one
  /// round trip per answer, so a client that fanned this out into N requests
  /// would be visible as N in `StateManHarness.roundTrips` even though the
  /// counter lives on the far side of the channel.
  static const readMany = '${prefix}readMany';

  /// The keys the served source can serve — `StateManApi.keys`.
  ///
  /// The client answers `keys` from its own store and never sends this in the
  /// ordinary path; it is registered so a test can ask the *source* what it
  /// holds and compare, and so a round trip exists that changes nothing (the
  /// barrier the batch-count case uses).
  static const keys = '${prefix}keys';

  /// A write — the real wire's name, because this is the real concept.
  static const write = Methods.write;

  /// A batch of changed values, pushed source → client. The real wire's name,
  /// one character long, for the same reason it is one character there.
  static const update = Methods.update;

  // ----------------------------------------------------------------- levers

  /// `StateManHarness.setValue`.
  static const setValue = '${prefix}setValue';

  /// `StateManHarness.setValues` — one batch, which is the unit the
  /// notification-count promise is made about.
  static const setValues = '${prefix}setValues';

  /// `StateManHarness.setQuality`.
  static const setQuality = '${prefix}setQuality';

  /// `StateManHarness.dropKey`.
  static const dropKey = '${prefix}dropKey';

  /// `StateManHarness.disconnectUpstream`.
  static const disconnectUpstream = '${prefix}disconnectUpstream';

  /// `StateManHarness.reconnectUpstream`.
  static const reconnectUpstream = '${prefix}reconnectUpstream';

  // ----------------------------------------------------- the write levers

  /// `StateManWriteHarness.failNextWrite`.
  static const failNextWrite = '${prefix}failNextWrite';

  /// `StateManWriteHarness.clampNextWrite`.
  static const clampNextWrite = '${prefix}clampNextWrite';

  /// `StateManWriteHarness.stallWrites` — Phase 2's `blackhole`, aimed at the
  /// write path.
  static const stallWrites = '${prefix}stallWrites';

  /// `StateManWriteHarness.releaseWrites`.
  static const releaseWrites = '${prefix}releaseWrites';

  /// `StateManWriteHarness.setReadOnly`.
  static const setReadOnly = '${prefix}setReadOnly';

  // There is deliberately no name here for `upstreamWriteAttempts` or
  // `mintedCmds`. Both are synchronous on the interface, so neither could be
  // answered by a round trip without changing the interface — the same
  // argument `channel_state_man.dart` makes for `roundTrips`. It is worth
  // stating once more here because of what the attempt counter is *for*: it is
  // the only observable that makes "a write is never auto-retried" testable,
  // and it works precisely because it lives where the attempts happen. A
  // mirrored copy on the client would count the client's sends, which is the
  // one place a retry would not be.

  /// The names that must never appear on a wire a connected client can reach.
  ///
  /// As data rather than as eleven references, so a Phase 10 test asserting the
  /// real method table is closed can iterate it instead of restating it.
  static const levers = <String>{
    setValue,
    setValues,
    setQuality,
    dropKey,
    disconnectUpstream,
    reconnectUpstream,
    failNextWrite,
    clampNextWrite,
    stallWrites,
    releaseWrites,
    setReadOnly,
  };

  /// Every name this harness registers on the served side.
  static const served = <String>{
    readFresh,
    readMany,
    keys,
    write,
    ...levers,
  };
}
