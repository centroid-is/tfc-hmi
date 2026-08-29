// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'access_policy.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$accessPolicyHash() => r'4640e4da7358f7b37321a75838c4af8549e64ee2';

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
