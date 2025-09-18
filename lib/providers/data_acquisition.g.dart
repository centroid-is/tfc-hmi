// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'data_acquisition.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Supervisor: spawns N workers (one per server with collect-entries), and restarts whichever dies.

@ProviderFor(dataAcquisition)
const dataAcquisitionProvider = DataAcquisitionProvider._();

/// Supervisor: spawns N workers (one per server with collect-entries), and restarts whichever dies.

final class DataAcquisitionProvider extends $FunctionalProvider<
        AsyncValue<DataAcquisition>, DataAcquisition, FutureOr<DataAcquisition>>
    with $FutureModifier<DataAcquisition>, $FutureProvider<DataAcquisition> {
  /// Supervisor: spawns N workers (one per server with collect-entries), and restarts whichever dies.
  const DataAcquisitionProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'dataAcquisitionProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$dataAcquisitionHash();

  @$internal
  @override
  $FutureProviderElement<DataAcquisition> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<DataAcquisition> create(Ref ref) {
    return dataAcquisition(ref);
  }
}

String _$dataAcquisitionHash() => r'4b5a493d5e73fcf01ff74b7f9b2a4b50f19bdee7';
