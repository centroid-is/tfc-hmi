// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'access_policy.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$accessPolicyHash() => r'64642d9b90de9a53ef5668517cc1bfccedc53c54';

/// The single answer to "what does writing *this* require?".
///
/// `keepAlive` and pure: it holds no connection, reads no preference and asks
/// nothing of the database. Since 04-05 it reads exactly one provider —
/// [tagBindingResolverProvider], which has no dependencies of its own and can
/// therefore never rebuild — so it is still true that nothing can invalidate
/// this provider and there is no path by which rebuilding it cascades into the
/// plant connection.
///
/// [kRaisedRoutes] is passed in rather than imported by `tfc_access`, which is
/// pure Dart and must not reach into the Flutter app for a route table. That
/// leaves two sources for one truth — this map and the [RouteRegistry] the
/// navigation menu reads — and `guard_wiring_test.dart` compares the two
/// answers for every raised route rather than restating an expected value.
///
/// The [TagBindingLookup] is `groupFor` on the one [TagBindingResolver] the
/// panel holds — a **callback on a mutable object**, deliberately, and never a
/// value read out of the database.
///
/// The distinction is the whole design of plan 04-05 and it is easy to undo by
/// accident. `tagBindingResolverProvider` has no dependencies and never
/// rebuilds; `accessTemplatesProvider` replaces the snapshot *inside* it when a
/// template or a binding changes. So an edit changes what this policy answers
/// on the very next write, while this policy — and everything downstream of
/// it — is never rebuilt.
///
/// Make the lookup a value instead (a `FutureProvider<AccessPolicy>` over the
/// templates, or a `ref.watch` of the loader here) and every template edit
/// invalidates this provider, rebuilds `stateManProvider`, and drops every OPC
/// UA connection and subscription on the panel. `guard_wiring_test.dart`'s
/// "signing in and out does not rebuild stateManProvider" is the assertion
/// that stops being true; T-04-25 is the threat. `ref.read`, not `ref.watch`,
/// for the same reason, and `access_templates_test.dart` asserts the shape of
/// this line from source.
///
/// Until the first load completes the resolver is empty and `groupForTag`
/// answers null for every key — spec §7b's fail-open half, now a bounded
/// window rather than the shipped state. `TagBindingSnapshotState.neverLoaded`
/// is what tells that window apart from a station with nothing bound.
///
/// Copied from [accessPolicy].
@ProviderFor(accessPolicy)
final accessPolicyProvider = Provider<AccessPolicy>.internal(
  accessPolicy,
  name: r'accessPolicyProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$accessPolicyHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AccessPolicyRef = ProviderRef<AccessPolicy>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
