// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'preferences.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(preferences)
const preferencesProvider = PreferencesProvider._();

final class PreferencesProvider extends $FunctionalProvider<
        AsyncValue<Preferences>, Preferences, FutureOr<Preferences>>
    with $FutureModifier<Preferences>, $FutureProvider<Preferences> {
  const PreferencesProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'preferencesProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$preferencesHash();

  @$internal
  @override
  $FutureProviderElement<Preferences> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Preferences> create(Ref ref) {
    return preferences(ref);
  }
}

String _$preferencesHash() => r'e1e51e4a0237621265a9a23b4b3441b6a8b63d13';
