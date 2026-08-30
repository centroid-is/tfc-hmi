// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_trail.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$auditTrailStoreHash() => r'dcb702afab835ae97102fe76cd489b29c637f072';

/// Reads of `audit_entry`, or null when this station has no database.
///
/// Null is a normal state, exactly as it is for `accessRepositoryProvider` and
/// for `accessTemplateStoreProvider` next door: no Postgres configured, and
/// again during the boot window before the connection opens. The two causes are
/// **indistinguishable by design** — `databaseProvider` returns null for both —
/// which is why the page's copy names no cause and says only that the trail is
/// unavailable.
///
/// `keepAlive`, unlike the query provider below: this holds the handle
/// `databaseProvider` already owns and rebuilding it on every page visit would
/// be churn for nothing. The query result is the thing worth releasing.
///
/// Copied from [auditTrailStore].
@ProviderFor(auditTrailStore)
final auditTrailStoreProvider = FutureProvider<AuditTrailStore?>.internal(
  auditTrailStore,
  name: r'auditTrailStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$auditTrailStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AuditTrailStoreRef = FutureProviderRef<AuditTrailStore?>;
String _$auditWhoOptionsHash() => r'314988cb41608661fc6d7e47b23dac945325b10e';

/// Every distinct `who` in the table, for the filter bar's dropdown.
///
/// Answers an **empty list** — not null and not an error — when the store is
/// null. A `who` dropdown with no options on an unreachable database is
/// correct; an exception here would take the whole filter bar down with it, and
/// the page already says "unavailable" once, from the query provider below.
/// Saying it twice, in two shapes, is not more honest.
///
/// Copied from [auditWhoOptions].
@ProviderFor(auditWhoOptions)
final auditWhoOptionsProvider =
    AutoDisposeFutureProvider<List<String>>.internal(
  auditWhoOptions,
  name: r'auditWhoOptionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$auditWhoOptionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AuditWhoOptionsRef = AutoDisposeFutureProviderRef<List<String>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
