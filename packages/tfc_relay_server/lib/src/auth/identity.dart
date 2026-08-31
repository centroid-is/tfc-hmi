/// Who a session is, once its credential has been accepted — a **station**,
/// never a person.
///
/// CONTEXT's scope fence for this phase is explicit: "no people-identity, no
/// expiry clockwork, no external auth dependencies". What the plant has is
/// panels bolted to walls, each with a token mounted beside it, and the
/// question every surface downstream asks is "which station is this, and may
/// it actuate?" — not "who is standing in front of it". A field for a person
/// would be a field nobody could fill honestly and a field a policy would
/// eventually read.
///
/// **This type cannot hold a credential**, and that is structural rather than
/// a convention: it has two fields, and neither is the token. An identity is
/// what a token is exchanged *for*, so it is safe to log, safe to put in a
/// close reason, and safe to name in an error — which is exactly what the
/// revocation sweep does. `TlsConfig` carries the same discipline for key
/// material (paths, never bytes) and for the same reason: a type that cannot
/// hold the secret cannot leak it.
///
/// Without this file the gateway can only answer "the credential was good",
/// which is enough to let a panel in and not enough to close one station's
/// session when its token is pulled — the whole of SEC-03's revocation clause.
library;

/// What a station is allowed to do.
///
/// Two values, and deliberately only two. Phase 6's shipped policy is trivial
/// — `canSee` is always true and `canWrite` is `role == operate` (CONTEXT
/// decision 2) — and a third role invented before there is policy data to
/// distinguish it would be a name with no behaviour behind it.
enum Role {
  /// May read the plant. A wall display, a shift screen, a laptop in an
  /// office.
  view,

  /// May read the plant and actuate it. A panel next to a machine.
  operate,
}

/// One station, and what it may do.
///
/// A const-constructible value type with value equality, because it is
/// compared rather than mutated: the revocation sweep asks the token file
/// whether the identity a live session is carrying is still the identity that
/// file describes, and an identity type with reference equality would answer
/// "no" for every session on every reload and close the whole plant.
final class Identity {
  const Identity({required this.stationId, required this.role});

  /// The station this session speaks for — `ST101`, `PACK-02`. Stable across
  /// reconnects, which is what makes it the thing a future `writeStatus`
  /// narrowing can be keyed on (see `write_outcome_log.dart`) where the
  /// session id cannot.
  final String stationId;

  /// What this station may do, as of the moment its `hello` was accepted. It
  /// does not track later edits to the token file on its own: the sweep in
  /// `RelayServer.reloadTokens` is what makes a demotion take effect, by
  /// closing the session that is still carrying the old one.
  final Role role;

  @override
  bool operator ==(Object other) =>
      other is Identity && other.stationId == stationId && other.role == role;

  @override
  int get hashCode => Object.hash(stationId, role);

  /// Safe to print anywhere, by construction — see this library's doc.
  @override
  String toString() => 'Identity($stationId, ${role.name})';
}
