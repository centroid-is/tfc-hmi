/// The fifteen `PreferencesApi` members over `tfc_dart`'s shared
/// `flutter_preferences` table.
///
/// Skeleton only — 10-09 task 1's GREEN fills it in. Every member refuses with
/// an [UnsupportedError] rather than an `UnimplementedError` on purpose:
/// `freeze_test.dart`'s ledger counts `UnimplementedError(` throw sites under
/// `lib/src`, and an interim skeleton is not a member somebody owes.
library;

import 'package:tfc_dart/core/secure_storage/interface.dart'
    show MySecureStorage;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart' show PreferencesApi;

import 'timescale_reader.dart' show DatabaseSupplier;

/// A secure store that refuses, installed by the gateway's composition root.
///
/// Skeleton only — 10-09 task 1's GREEN documents it.
final class NoSecretStorage implements MySecureStorage {
  const NoSecretStorage();

  @override
  Future<String?> read({required String key}) async => throw StateError('no');

  @override
  Future<void> write({required String key, required String value}) async =>
      throw StateError('no');

  @override
  Future<void> delete({required String key}) async => throw StateError('no');
}

/// `PreferencesApi` over the shared preferences table.
final class PreferenceStore implements PreferencesApi {
  PreferenceStore({required this.database, this.log});

  /// The shared instance, borrowed per call. See `history_view_store.dart`'s
  /// library doc for why this is a supplier and not an instance.
  final DatabaseSupplier database;

  /// Where a swallowed failure goes.
  final void Function(String message)? log;

  Never _todo() => throw UnsupportedError('10-09 task 1 has not written this');

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async => _todo();

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async =>
      _todo();

  @override
  Future<bool?> getBool(String key) async => _todo();

  @override
  Future<int?> getInt(String key) async => _todo();

  @override
  Future<double?> getDouble(String key) async => _todo();

  @override
  Future<String?> getString(String key) async => _todo();

  @override
  Future<List<String>?> getStringList(String key) async => _todo();

  @override
  Future<bool> containsKey(String key) async => _todo();

  @override
  Future<void> setBool(String key, bool value) async => _todo();

  @override
  Future<void> setInt(String key, int value) async => _todo();

  @override
  Future<void> setDouble(String key, double value) async => _todo();

  @override
  Future<void> setString(String key, String value) async => _todo();

  @override
  Future<void> setStringList(String key, List<String> value) async => _todo();

  @override
  Future<void> remove(String key) async => _todo();

  @override
  Future<void> clear({Set<String>? allowList}) async => _todo();

  @override
  Stream<String> get onPreferencesChanged => _todo();

  /// Releases everything this store holds open.
  Future<void> close() async {}
}
