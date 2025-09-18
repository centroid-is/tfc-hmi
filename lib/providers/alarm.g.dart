// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alarm.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(alarmMan)
const alarmManProvider = AlarmManProvider._();

final class AlarmManProvider extends $FunctionalProvider<AsyncValue<AlarmMan>,
        AlarmMan, FutureOr<AlarmMan>>
    with $FutureModifier<AlarmMan>, $FutureProvider<AlarmMan> {
  const AlarmManProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'alarmManProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$alarmManHash();

  @$internal
  @override
  $FutureProviderElement<AlarmMan> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<AlarmMan> create(Ref ref) {
    return alarmMan(ref);
  }
}

String _$alarmManHash() => r'070a52de2aada5e37f7d2051c4ad9f39872116f4';
