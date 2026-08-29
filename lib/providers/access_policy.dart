/// The write-path plumbing: the one [AccessPolicy] both guards consult, the
/// stream every denial lands on, and the counted set of writes the app makes on
/// its own behalf.
///
/// **Why this is not in `lib/providers/access.dart`.** That file is identity
/// and session: who is signed in, when the session expires, where the audit
/// rows go. The app bar watches it on every frame. This file is the write path:
/// it is read by exactly two providers and one listener, and it must never
/// reach back toward the session — a `watch` in that direction rebuilds
/// `stateManProvider` on every sign-in and drops every OPC UA connection on the
/// panel. Keeping the two files apart is what makes that a visible import
/// rather than one more line in a long file; `guard_wiring_test.dart` asserts
/// this source names none of `databaseProvider`, `preferencesProvider` or
/// `accessSessionProvider`.
library;

import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tfc_access/tfc_access.dart';

import '../access_routes.dart';

part 'access_policy.g.dart';

/// The single answer to "what does writing *this* require?".
///
/// `keepAlive` and a pure value: it holds no connection, reads no preference
/// and asks nothing of the database, so nothing can invalidate it and there is
/// no path by which rebuilding it cascades into the plant connection.
///
/// [kRaisedRoutes] is passed in rather than imported by `tfc_access`, which is
/// pure Dart and must not reach into the Flutter app for a route table. That
/// leaves two sources for one truth — this map and the [RouteRegistry] the
/// navigation menu reads — and `guard_wiring_test.dart` compares the two
/// answers for every raised route rather than restating an expected value.
///
/// No [TagBindingLookup] is supplied, so `groupForTag` answers null for every
/// key and no tag write is denied in this phase. That is spec §7b's fail-open
/// half, and Phase 4's access templates are what turn it on.
@Riverpod(keepAlive: true)
AccessPolicy accessPolicy(Ref ref) => const AccessPolicy(routes: kRaisedRoutes);

/// Holds the denial controller.
///
/// Private so that [reportAccessDenial] is the only way an event enters the
/// stream. A provider handing the controller out would make every `add` call
/// site a place the trail could be forged from.
final _accessDenialSinkProvider =
    Provider<StreamController<AccessDenied>>((ref) {
  // Broadcast for two reasons, both of them the point of the stream. Plan
  // 03-07's listener attaches and detaches with the app's navigation, which a
  // single-subscription stream forbids; and a broadcast controller **drops**
  // events while nobody is listening rather than buffering them, so a denial
  // from four screens ago is not replayed at whoever mounts the prompt next.
  // The purpose of a denial event is to show a refusal *now*.
  final controller = StreamController<AccessDenied>.broadcast();
  // A StreamController in shared plumbing has the same failure mode as an
  // always-on timer if it is never closed (spec §10).
  ref.onDispose(controller.close);
  return controller;
});

/// Every refusal both guards produce, as a stream a widget can listen to.
///
/// Read it, do not `watch` it for the value: it is a plain [Provider] holding a
/// broadcast [Stream], not a `StreamProvider`. A `StreamProvider` would cache
/// the last event as `AsyncData` and hand it to the next widget that mounts,
/// which is the replay this stream exists to avoid.
final accessDenialsProvider = Provider<Stream<AccessDenied>>(
  (ref) => ref.watch(_accessDenialSinkProvider).stream,
);

/// Publish [denial] to [accessDenialsProvider]. The only entry point.
///
/// Typed to [Ref] because every production caller is a provider's `onDenied`
/// closure. Publishing into a torn-down container is a **no-op rather than a
/// throw**, in both the ways it can happen: the controller already closed, or
/// the container itself disposed so the read throws. A guard's `onDenied` can
/// fire from a write already in flight while the app is shutting down, and an
/// exception there would turn an orderly shutdown into a crash — for an event
/// that by definition has no listener left to show it.
void reportAccessDenial(Ref ref, AccessDenied denial) {
  final StreamController<AccessDenied> controller;
  try {
    controller = ref.read(_accessDenialSinkProvider);
  } on Object {
    return;
  }
  if (controller.isClosed) return;
  controller.add(denial);
}
