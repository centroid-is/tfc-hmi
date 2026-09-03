/// The fifteen `PreferencesApi` members over `tfc_dart`'s shared
/// `flutter_preferences` table.
///
/// ## TRAP 8: a `Preferences` built by hand answers "no keys"
///
/// `getKeys` and `getAll` read an **in-memory cache**
/// (`preferences.dart:267-274`), not the table. The only thing that fills that
/// cache is `Preferences.create`, which awaits `loadFromPostgres()` (`:233`).
/// A gateway that constructed `Preferences(database: db, …)` directly — the
/// public constructor, which compiles and looks right — would answer an empty
/// set to a store that at SVN today holds **four rows and 675,890 bytes**,
/// `key_mappings` alone being 530,287 of them (`svn-prefs-live-20260811.csv`,
/// measured). Nothing throws. The first symptom is a settings page that looks
/// like a fresh install, which is not a thing anybody reports as a fault, and
/// the second is somebody re-entering configuration that was never lost.
///
/// So this store never uses the constructor. [_load] goes through
/// `Preferences.create`, and there is a case asserting a freshly built store
/// answers a seeded database's keys.
///
/// ## The cache is rebuilt, never patched
///
/// The cache is a process-local copy of a table **other processes write** — an
/// HMI station at SVN saves its settings straight into it. When
/// `preference_change_feed.dart` hears that happen it calls [invalidate], and
/// the next call rebuilds through `Preferences.create` rather than refreshing
/// the one key that changed.
///
/// A per-key refresh was considered and rejected, for a reason worth writing
/// down: upstream offers no way to **evict** a key from the cache that does not
/// also delete its row. `Preferences.remove` clears the entry *and* issues a
/// `DELETE` (`preferences.dart:421-436`), so reflecting somebody else's delete
/// with it would mean this gateway issuing a delete of its own — against a row
/// that a racing writer may have just re-created. `loadFromPostgres` on the
/// live instance has the mirror-image flaw: it overwrites and adds, and never
/// removes, so a deleted key would live in the cache forever. Rebuilding is
/// the only operation that is total, and its cost is one full read — 660 KiB
/// at SVN's present size, on a change nobody makes twice a minute.
///
/// ## The seam stays at two files
///
/// This file does not import `core/database.dart`. It takes 10-07's
/// [DatabaseSupplier] from next door and hands what it returns to
/// `Preferences.create`, whose `db` parameter has exactly that type — so the
/// call is statically checked and `freeze_test.dart`'s
/// `declaredSeamImportFiles` does not move. `history_view_store.dart`'s
/// library doc carries the full argument.
///
/// `Preferences.create` accepts a **null** database and quietly degrades to a
/// memory-only store when given one. That is Trap 8 wearing a second hat, so
/// [_load] refuses instead: null means the historian is not up, and
/// [PreferenceStoreUnavailable] is retryable and says so.
///
/// ## SEC-01: `secret:` is not spelled in this file
///
/// The concrete `Preferences` carries a `{bool secret = false}` on twelve
/// members, which routes the call to the OS keychain instead of the table. The
/// interface this store implements omits it, every call below uses the
/// non-secret overload, and `preference_store_test.dart` greps this source for
/// the word — because the obvious future edit is to add it back "for
/// symmetry", and that one client-supplied boolean would be remote retrieval
/// of the secure store (T-10-35).
library;

import 'dart:async';

import 'package:tfc_dart/core/preferences.dart' show Preferences;
import 'package:tfc_dart/core/secure_storage/interface.dart'
    show MySecureStorage;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart' show PreferencesApi;

import 'timescale_reader.dart' show DatabaseSupplier;

/// The preference store cannot be reached right now.
///
/// A separate type from `HistorianUnavailable` even though the absent thing is
/// the same `Database`: a client that asked for a setting and was told "the
/// historian is not connected" would go and look at charts. Not a member of
/// the sealed `TimeseriesReadRefusal` family for the same reason — the switch
/// that family exists for is about *reads of recorded samples*.
final class PreferenceStoreUnavailable implements Exception {
  const PreferenceStoreUnavailable();

  /// Whether retrying the identical request could ever succeed.
  bool get retryable => true;

  @override
  String toString() =>
      'the preference store is not connected; this is worth retrying';
}

/// A secure store that refuses every request.
///
/// Installed by the gateway's composition root. The gateway must never read or
/// write secret material — SEC-01 says keys are mounted files, not preference
/// rows — and this makes that true by construction rather than by convention.
///
/// It also removes a dependency this process should not have. `Preferences`
/// asks `SecureStorage.getInstance()` **unconditionally**, outside the `try`
/// that guards the rest of `create` (`preferences.dart:219-220`), and the
/// default on Linux and macOS builds an `AwsSecureStorage` over the OS
/// keychain. A headless gateway has no session keyring to talk to, and a
/// failure there would take down a call that never wanted a secret in the
/// first place.
final class NoSecretStorage implements MySecureStorage {
  const NoSecretStorage();

  static Never _refuse(String op) => throw StateError(
      'this gateway does not handle secret material: $op was asked of the '
      'refusing secure store. SEC-01 — keys are mounted files, not '
      'preference rows, and nothing reachable from the pipe may request one');

  @override
  Future<String?> read({required String key}) async => _refuse('read');

  @override
  Future<void> write({required String key, required String value}) async =>
      _refuse('write');

  @override
  Future<void> delete({required String key}) async => _refuse('delete');
}

/// `PreferencesApi` over the shared `flutter_preferences` table.
final class PreferenceStore implements PreferencesApi {
  PreferenceStore({required this.database, this.log});

  /// The shared instance, borrowed per call. See the library doc.
  final DatabaseSupplier database;

  /// Where a swallowed failure goes. Optional and injected, following
  /// `HistoryViewStore`'s shape: a store built in a test asserts what it was
  /// told, and one built by `bin/relay_gateway.dart` writes to the gateway's
  /// logger.
  final void Function(String message)? log;

  /// Writes made **through this gateway**, forwarded from whichever
  /// `Preferences` instance is current.
  ///
  /// Broadcast and forwarded rather than handed out directly, because the
  /// instance is rebuilt whenever the cache is invalidated or the database
  /// is swapped, and a subscriber holding the old instance's stream would go
  /// quiet without anything closing.
  final StreamController<String> _local = StreamController<String>.broadcast();

  /// The `Preferences` currently loaded, or null when it must be rebuilt.
  Future<Preferences>? _loaded;

  /// The database instance [_loaded] was built over, for the swap check.
  ///
  /// Deliberately `Object?`: only [identical] is asked of it, and naming the
  /// real type here would mean importing the seam.
  Object? _loadedOver;

  StreamSubscription<String>? _localSource;

  bool _closed = false;

  /// The loaded `Preferences`, built if it is absent or built over a
  /// database instance the supplier has since replaced.
  ///
  /// The *future* is cached rather than the value, so two concurrent first
  /// calls share one `loadFromPostgres` instead of racing two.
  Future<Preferences> _load() async {
    if (_closed) throw StateError('this preference store has been closed');
    final db = database();
    if (db == null) throw const PreferenceStoreUnavailable();
    final loaded = _loaded;
    if (loaded != null && identical(_loadedOver, db)) return loaded;

    // `create` and not the constructor. See TRAP 8 in the library doc.
    final building = Preferences.create(db: db);
    _loaded = building;
    _loadedOver = db;
    final Preferences prefs;
    try {
      prefs = await building;
    } catch (_) {
      // A failed build must not be cached as the answer: the next caller has
      // to try again rather than inherit a broken instance forever.
      if (identical(_loaded, building)) {
        _loaded = null;
        _loadedOver = null;
      }
      rethrow;
    }
    await _localSource?.cancel();
    _localSource = prefs.onPreferencesChanged.listen(
      (key) {
        if (!_local.isClosed) _local.add(key);
      },
      onError: (Object e) {
        log?.call('preference change stream error: $e');
      },
    );
    return prefs;
  }

  // ------------------------------------------------------------------- reads

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async =>
      (await _load()).getKeys(allowList: allowList);

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async =>
      (await _load()).getAll(allowList: allowList);

  @override
  Future<bool?> getBool(String key) async => (await _load()).getBool(key);

  @override
  Future<int?> getInt(String key) async => (await _load()).getInt(key);

  @override
  Future<double?> getDouble(String key) async => (await _load()).getDouble(key);

  @override
  Future<String?> getString(String key) async => (await _load()).getString(key);

  @override
  Future<List<String>?> getStringList(String key) async =>
      (await _load()).getStringList(key);

  @override
  Future<bool> containsKey(String key) async =>
      (await _load()).containsKey(key);

  // ------------------------------------------------------------------ writes

  @override
  Future<void> setBool(String key, bool value) async =>
      (await _load()).setBool(key, value);

  @override
  Future<void> setInt(String key, int value) async =>
      (await _load()).setInt(key, value);

  @override
  Future<void> setDouble(String key, double value) async =>
      (await _load()).setDouble(key, value);

  @override
  Future<void> setString(String key, String value) async =>
      (await _load()).setString(key, value);

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      (await _load()).setStringList(key, value);

  @override
  Future<void> remove(String key) async => (await _load()).remove(key);

  /// Removes every stored preference, or every one named by [allowList].
  ///
  /// **Not a delegation, and this is the one member that could not be.**
  /// `Preferences.clear` empties the memory cache and the local cache and
  /// **never touches Postgres** (`preferences.dart:439-442`). Through this
  /// gateway that would be a clear that undoes itself: the cache is refilled
  /// from the table on the next rebuild, so every key would come back, and
  /// nothing anywhere would have said the call did not do what it said. It
  /// also fires no change event, so no connected panel would hear about it
  /// either.
  ///
  /// So it is a remove per key. That also gives the wire the right shape:
  /// each `remove` announces its key, and `data_handlers.dart` coalesces the
  /// burst into **one** `preferences.changed` frame carrying the whole set
  /// (10-05), rather than one frame per key.
  ///
  /// **The blast radius is real and is not this file's to narrow.** With no
  /// allow-list this deletes `key_mappings` — the gateway's own routing
  /// configuration — from the shared table, and the interface's own doc says
  /// as much ("It is highly recommended that an allowList be provided"). The
  /// gate on the call is 10-05's `operate` role, which is the same role that
  /// writes a motor setpoint; narrowing it further is a policy decision, and
  /// policy lives in `policy_state_man.dart`, not here. Recorded as a threat
  /// flag rather than quietly refused, because a store that silently declined
  /// an unrestricted clear would be a fourth behaviour nobody could predict
  /// from the interface.
  @override
  Future<void> clear({Set<String>? allowList}) async {
    final prefs = await _load();
    for (final key in await prefs.getKeys(allowList: allowList)) {
      await prefs.remove(key);
    }
  }

  // ------------------------------------------------------------------ events

  /// Every key whose value changed **through this gateway**.
  ///
  /// Half the answer, and 10-09 task 2 supplies the other half. This stream
  /// carries writes made through this process's `Preferences`
  /// (`preferences.dart:154-155`), which is every write a connected client
  /// makes, because the gateway is the single writer for all of them. It does
  /// **not** carry a write an HMI station makes straight at the table, and at
  /// SVN that happens today — `preference_change_feed.dart` merges the
  /// LISTEN/NOTIFY half in and this getter becomes the merged feed.
  @override
  Stream<String> get onPreferencesChanged => _local.stream;

  /// Releases the forwarded stream and everything it holds.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _localSource?.cancel();
    _localSource = null;
    await _local.close();
    _loaded = null;
    _loadedOver = null;
  }
}
