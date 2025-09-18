// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collector.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(collector)
const collectorProvider = CollectorProvider._();

final class CollectorProvider extends $FunctionalProvider<
        AsyncValue<Collector?>, Collector?, FutureOr<Collector?>>
    with $FutureModifier<Collector?>, $FutureProvider<Collector?> {
  const CollectorProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'collectorProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$collectorHash();

  @$internal
  @override
  $FutureProviderElement<Collector?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Collector?> create(Ref ref) {
    return collector(ref);
  }
}

String _$collectorHash() => r'51cb957194d03fdb11500d8e409e66df0cad4dad';
