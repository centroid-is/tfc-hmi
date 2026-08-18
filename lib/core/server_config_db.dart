import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tfc_dart/core/database_drift.dart';

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
class ServerConfigDb {
  ServerConfigDb._();

  static const String prefsKey = 'server_config_envelope';

  static Future<void> publish(AppDatabase db, StoredServerConfig config) {
    return db.into(db.flutterPreferences).insertOnConflictUpdate(
          FlutterPreferencesCompanion.insert(
            key: prefsKey,
            value: Value(jsonEncode(config.toJson())),
            type: 'String',
          ),
        );
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

  static Future<void> remove(AppDatabase db) {
    return (db.delete(db.flutterPreferences)
          ..where((t) => t.key.equals(prefsKey)))
        .go();
  }
}
