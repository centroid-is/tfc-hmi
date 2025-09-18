// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'data_acquisition.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$dataAcquisitionHash() => r'4b5a493d5e73fcf01ff74b7f9b2a4b50f19bdee7';

/// Supervisor: spawns N workers (one per server with collect-entries), and restarts whichever dies.
///
/// Copied from [dataAcquisition].
@ProviderFor(dataAcquisition)
final dataAcquisitionProvider = FutureProvider<DataAcquisition>.internal(
  dataAcquisition,
  name: r'dataAcquisitionProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$dataAcquisitionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DataAcquisitionRef = FutureProviderRef<DataAcquisition>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
