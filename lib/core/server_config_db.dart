import 'dart:convert';

import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_dart/core/preferences.dart';

/// A password-encrypted server configuration stored in the shared database.
///
/// The envelope itself is the [SecureEnvelope] JSON (PBKDF2 + AES-256-GCM),
/// so the database only ever sees ciphertext — the OPC-UA credentials inside
/// stay protected by the password the operator chose when storing it. The
/// metadata is deliberately plaintext: it lets the import dialog tell the
/// operator what they are about to overwrite their config with *before*
/// asking for the password.
class StoredServerConfig {
  final DateTime? savedAt;

  /// Hostname of the machine that stored the config.
  final String? savedBy;
  final Map<String, dynamic> envelope;

  StoredServerConfig({this.savedAt, this.savedBy, required this.envelope});

  factory StoredServerConfig.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'];
    return StoredServerConfig(
      savedAt: meta is Map && meta['saved_at'] is String
          ? DateTime.tryParse(meta['saved_at'] as String)
          : null,
      savedBy: meta is Map ? meta['saved_by'] as String? : null,
      envelope: (json['envelope'] as Map).cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'meta': {
          if (savedAt != null) 'saved_at': savedAt!.toIso8601String(),
          if (savedBy != null) 'saved_by': savedBy,
        },
        'envelope': envelope,
      };
}

/// Reads and writes the shared server-config envelope in the database.
///
/// The envelope lives as a row in the existing `flutter_preferences` table
/// rather than a table of its own: that table is already replicated to every
/// client, needs no schema migration, and an operator can find (and delete)
/// the row through the same tooling as any other preference. Reads always go
/// to the database, never through [Preferences]' in-memory cache — that cache
/// is a startup snapshot, and the whole point of importing is picking up a
/// config another client stored *after* this one started.
///
/// ## Why the writes go through [PreferencesApi] and the read does not
///
/// The asymmetry is deliberate, and it is not an oversight waiting to be
/// tidied up. [publish] and [remove] replace the whole server configuration —
/// which Postgres this station talks to, which OPC UA servers it trusts — so
/// they must be gated on `administer` and land in the audit trail, and the
/// guarded [PreferencesApi] is the one path that does both. [fetch] must not
/// see a stale snapshot, for the reason in the paragraph above. Those are two
/// different requirements and they point at two different paths; making the
/// class symmetric would break whichever half it was made to match.
///
/// One consequence to know before reading [fetch] and worrying: [publish] now
/// populates the very caches [fetch] refuses to consult, because
/// `Preferences.setString` writes the memory cache and the device-local cache
/// on its way to the row. That does not make [fetch]'s direct select
/// redundant — those caches only ever hold what *this* client wrote, and the
/// config worth importing is the one *another* client wrote. The row remains
/// the only shared copy, and it remains the one [fetch] reads.
class ServerConfigDb {
  ServerConfigDb._();

  static const String prefsKey = 'server_config_envelope';

  /// Stores [config] as the shared server config.
  ///
  /// [prefs] is the guarded store the caller already holds, so this write is
  /// checked and recorded like any other configuration write.
  static Future<void> publish(PreferencesApi prefs, StoredServerConfig config) {
    return prefs.setString(prefsKey, jsonEncode(config.toJson()));
  }

  /// Returns the stored config, or null when none has been stored yet.
  /// Throws [FormatException] when the row exists but does not parse — the
  /// caller should surface that, not treat it as "nothing stored".
  static Future<StoredServerConfig?> fetch(AppDatabase db) async {
    final row = await (db.select(db.flutterPreferences)
          ..where((t) => t.key.equals(prefsKey)))
        .getSingleOrNull();
    final raw = row?.value;
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['envelope'] is! Map) {
      throw const FormatException(
          'Stored server config is not a valid envelope');
    }
    return StoredServerConfig.fromJson(decoded);
  }

  /// Removes the shared server config. Gated and recorded like [publish].
  static Future<void> remove(PreferencesApi prefs) {
    return prefs.remove(prefsKey);
  }
}
