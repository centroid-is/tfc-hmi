// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dbus.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(dbus)
const dbusProvider = DbusProvider._();

final class DbusProvider
    extends $FunctionalProvider<DBusClient?, DBusClient?, DBusClient?>
    with $Provider<DBusClient?> {
  const DbusProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'dbusProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$dbusHash();

  @$internal
  @override
  $ProviderElement<DBusClient?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DBusClient? create(Ref ref) {
    return dbus(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DBusClient? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DBusClient?>(value),
    );
  }
}

String _$dbusHash() => r'9fd83bd41282c6a856cba2be04006df2ed73061a';
