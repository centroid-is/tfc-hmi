// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state_man.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(stateMan)
const stateManProvider = StateManProvider._();

final class StateManProvider extends $FunctionalProvider<AsyncValue<StateMan>,
        StateMan, FutureOr<StateMan>>
    with $FutureModifier<StateMan>, $FutureProvider<StateMan> {
  const StateManProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'stateManProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$stateManHash();

  @$internal
  @override
  $FutureProviderElement<StateMan> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<StateMan> create(Ref ref) {
    return stateMan(ref);
  }
}

String _$stateManHash() => r'dcf2ef006afa9f8bc3e4db4869d2abd5cb738352';
