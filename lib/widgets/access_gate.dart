/// The route gate: one decision, taken in one place, in front of a page.
///
/// This is the phase's only enforcement point. Putting it at the route rather
/// than inside each page means a menu tap, a deep link and a stored startup
/// path all meet the same gate, and a page that forgets to ask is not a hole.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_access/tfc_access.dart';
import 'package:tfc_dart/core/access/access_repository.dart';

/// What the gate does with a route: show it, lock it, or show neither yet.
enum AccessGateState {
  /// Build the child. Nothing is added around it.
  allowed,

  /// Show the locked page — which explains what is missing and offers a
  /// sign-in. Never an error.
  denied,

  /// Neither the page nor the lock: something the decision depends on has not
  /// resolved yet.
  waiting,
}

/// Whether [group] may be opened, given what the two access providers currently
/// say.
///
/// Pure on purpose: no `BuildContext`, no `ref`, no widgets. The
/// repository-unavailable half of this rule is the part of the phase that is
/// easiest to get subtly wrong, and a pure function is the only version of it a
/// truth table can pin exhaustively.
///
/// The checks run in one order and the order is load-bearing: [AccessGroup
/// .operate] first, then the repository, then the session. Checking the session
/// first would let an unavailable-repository station resolve on a session that
/// has no authority behind it — a stale in-memory session claiming `configure`
/// after the database it was resolved against went away.
///
/// **No repository, one door opens.** With no repository, `signIn` can only
/// answer `AccessSignInResult.unavailable` (`lib/providers/access.dart`), so a
/// locked Server Config would be a sign-in prompt that cannot be passed,
/// guarding the page where the database is configured. That is true whether the
/// station was never configured or somebody mistyped the Postgres IP and saved
/// — and the second is the case that matters, because without this a typo turns
/// into an on-site recovery. `PROJECT.md` is explicit that the realistic failure
/// here is accident and shift confusion, not a malicious insider. So
/// [allowWhenRepositoryUnavailable] is passed true for exactly one route
/// (`kServerConfigRoute`) and false everywhere else.
///
/// **No repository, the other five stay shut.** The argument above is entirely
/// about reaching the database configuration page. It says nothing about Page
/// Editor, Alarm Editor, Key Repository, IP Settings or Preferences —
/// `centroid-hmi/lib/navigation.dart:48-50` already calls those surfaces that
/// store secrets — and an outage is a state a commissioned station enters
/// mid-shift, inducible from a Save button. Opening them would hand every gated
/// route to whoever is standing at the panel for the length of it.
///
/// **Loading is neither.** `AsyncLoading` is [AccessGateState.waiting], so a
/// slow connection is never mistaken for a missing one.
///
/// **The cost, accepted deliberately:** an unreachable database leaves Server
/// Config reachable by anyone at the panel, so someone could repoint the station
/// at a Postgres they control holding a known Engineering account and sign in.
/// That takes physical access to the panel plus a prepared server, and physical
/// access already defeats this milestone by design — spec §8, anyone with
/// UaExpert or `psql` walks around every guard. Bricking a plant's station over
/// a typo is the likelier and worse failure.
///
/// The parameter is named for the condition it enforces. It is deliberately not
/// `allowWhenUnconfigured`: it fires on *any* unavailable repository,
/// unconfigured or unreachable alike, and a name claiming the narrower condition
/// would be the same defect class as a mitigation sentence that describes its
/// own hole. There is likewise no provider anywhere in this phase that
/// distinguishes the two causes — under this ruling it would discriminate
/// nothing.
AccessGateState resolveAccessGate({
  required AccessGroup group,
  required AsyncValue<AccessRepository?> repository,
  required AsyncValue<AccessSession> session,
  required bool allowWhenRepositoryUnavailable,
}) {
  // Anonymous holds `operate`, so an unraised route must cost neither a frame
  // nor a lock — not even while the providers behind the other branches are
  // still resolving.
  if (group == AccessGroup.operate) return AccessGateState.allowed;

  // Nothing resolved yet — neither a value nor an error. Merely slow is not
  // missing.
  if (!repository.hasValue && !repository.hasError) {
    return AccessGateState.waiting;
  }

  // An error means the repository could not even be constructed, which is the
  // same fact as a resolved null: this station cannot authenticate anybody.
  // Both are gated identically for every route.
  final repository0 = repository.hasError ? null : repository.requireValue;
  if (repository0 == null) {
    return allowWhenRepositoryUnavailable
        ? AccessGateState.allowed
        : AccessGateState.denied;
  }

  // A repository exists, so a sign-in can succeed and the session is the
  // authority — including for Server Config, whose exemption is inert from
  // here on.
  if (session.hasError) return AccessGateState.denied;
  if (!session.hasValue) return AccessGateState.waiting;
  return session.requireValue.can(group)
      ? AccessGateState.allowed
      : AccessGateState.denied;
}
