import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tfc_dart/tfc_dart_core.dart' show McpDatabase, fuzzyFilter;

import '../cache/ttl_cache.dart';
import 'plc_code_service.dart';
import 'sql_dialect.dart';

/// Service for reading system configuration from the database.
///
/// Provides methods to query pages, assets, key mappings, and alarm
/// definitions. Data is stored as JSON blobs in the flutter_preferences
/// table (page_editor_data, key_mappings) and as rows in the alarm table.
///
/// All list methods enforce a [limit] parameter to prevent context window
/// overflow when used by the AI copilot.
///
/// Implements [KeyMappingLookup] so it can be used by [PlcCodeService]
/// for OPC UA identifier correlation.
///
/// Accepts [McpDatabase] (not ServerDatabase) so it works with both
/// AppDatabase (Flutter in-process) and ServerDatabase (standalone binary).
/// Shared tables (flutter_preferences, alarm) are queried via raw SQL since
/// AppDatabase and ServerDatabase define different row classes for the same
/// physical tables.
///
/// SQL queries use [adaptSql] to translate `?` placeholders to `$N` when
/// running against PostgreSQL, since drift's `customSelect` passes raw SQL
/// verbatim to the database engine without placeholder translation.
class ConfigService implements KeyMappingLookup {
  /// Creates a [ConfigService] backed by the given [McpDatabase].
  ConfigService(this._db) : _isPostgres = isPostgresDb(_db);

  final McpDatabase _db;

  /// Whether the database uses PostgreSQL dialect.
  final bool _isPostgres;

  /// Cache for preference JSON blobs (keyed by preference key).
  final _prefCache = TtlCache<String, Map<String, dynamic>?>(
    defaultTtl: Duration(minutes: 5),
    maxEntries: 50,
  );

  /// Cache for alarm definition listings (keyed by filter:limit).
  final _alarmDefCache = TtlCache<String, List<Map<String, dynamic>>>(
    defaultTtl: Duration(minutes: 5),
    maxEntries: 100,
  );

  /// Cache for individual alarm configs (keyed by alarm UID).
  final _alarmConfigCache = TtlCache<String, Map<String, dynamic>?>(
    defaultTtl: Duration(minutes: 5),
    maxEntries: 100,
  );

  /// Invalidate all config caches.
  void invalidateCache() {
    _prefCache.clear();
    _alarmDefCache.clear();
    _alarmConfigCache.clear();
  }

  /// Adapts SQL with `?` placeholders to `$N` for PostgreSQL.
  String _sql(String query) => adaptSql(query, isPostgres: _isPostgres);

  /// Reads a JSON preference value from the flutter_preferences table.
  ///
  /// Results are cached with a 5-minute TTL to avoid repeated DB round-trips.
  /// ConfigService queries via raw SQL ([customSelect]), completely bypassing
  /// the Flutter InMemoryPreferences layer, so this cache is valuable in both
  /// in-process and subprocess modes.
  ///
  /// Returns the decoded JSON value, or `null` if the key does not exist
  /// or the value is null/empty.
  ///
  /// Uses raw SQL via [customSelect] because flutter_preferences is a shared
  /// table with different row classes in AppDatabase vs ServerDatabase.
  Future<Map<String, dynamic>?> _getPreferenceJson(String key) {
    return _prefCache.getOrCompute(key, () async {
      final rows = await _db.customSelect(
        _sql('SELECT value FROM flutter_preferences WHERE key = ?'),
        variables: [Variable.withString(key)],
      ).get();
      if (rows.isEmpty) return null;
      final value = rows.first.readNullable<String>('value');
      if (value == null || value.isEmpty) return null;
      return jsonDecode(value) as Map<String, dynamic>;
    });
  }

  /// Returns a summary list of pages from page_editor_data.
  ///
  /// Each entry contains `key` and `title` fields. Results are limited
  /// to [limit] entries (default 50).
  Future<List<Map<String, dynamic>>> listPages({int limit = 50}) async {
    final data = await _getPreferenceJson('page_editor_data');
    if (data == null) return [];

    final pages = <Map<String, dynamic>>[];
    for (final entry in data.entries) {
      final page = entry.value as Map<String, dynamic>;
      pages.add({
        'key': page['key'] ?? entry.key,
        'title': page['title'] ?? entry.key,
      });
    }

    return pages.take(limit).toList();
  }

  /// Returns a summary list of assets from page_editor_data.
  ///
  /// Each page is treated as an asset. Each entry contains `key` and
  /// `title` fields. Results are limited to [limit] entries (default 50).
  Future<List<Map<String, dynamic>>> listAssets({int limit = 50}) async {
    final data = await _getPreferenceJson('page_editor_data');
    if (data == null) return [];

    final assets = <Map<String, dynamic>>[];
    for (final entry in data.entries) {
      final page = entry.value as Map<String, dynamic>;
      assets.add({
        'key': page['key'] ?? entry.key,
        'title': page['title'] ?? entry.key,
      });
    }

    return assets.take(limit).toList();
  }

  /// Returns the full page configuration for the given [pageKey].
  ///
  /// Returns `null` if no page with the given key exists. This provides
  /// the detailed view in the progressive discovery pattern (Level 2).
  Future<Map<String, dynamic>?> getAssetDetail(String pageKey) async {
    final data = await _getPreferenceJson('page_editor_data');
    if (data == null) return null;

    if (data.containsKey(pageKey)) {
      return data[pageKey] as Map<String, dynamic>;
    }
    return null;
  }

  /// Returns key-to-protocol-node mappings from the key_mappings preference.
  ///
  /// Handles OPC UA (`opcua_node`), Modbus (`modbus_node`), and M2400
  /// (`m2400_node`) entries. Each result always contains a `key` field and
  /// a `protocol` field indicating the source protocol. OPC UA entries
  /// additionally include `namespace` and `identifier`; Modbus entries
  /// include `register_type`, `address`, `data_type`, and `poll_group`;
  /// M2400 entries include `record_type` and optionally `field` and
  /// `server_alias`.
  ///
  /// A single key may appear multiple times if it has mappings for more
  /// than one protocol.
  ///
  /// Supports optional fuzzy [filter] on key names. Results are limited
  /// to [limit] entries (default 50).
  @override
  Future<List<Map<String, dynamic>>> listKeyMappings({
    String? filter,
    int limit = 50,
  }) async {
    final data = await _getPreferenceJson('key_mappings');
    if (data == null) return [];

    final nodes = data['nodes'] as Map<String, dynamic>?;
    if (nodes == null) return [];

    var mappings = <Map<String, dynamic>>[];
    for (final entry in nodes.entries) {
      final config = entry.value as Map<String, dynamic>;
      var hasMapping = false;

      // Bit mask/shift (applies to any protocol)
      final bitMask = config['bit_mask'] as int?;
      final bitShift = config['bit_shift'] as int?;

      // OPC UA
      final opcuaNode = config['opcua_node'] as Map<String, dynamic>?;
      if (opcuaNode != null) {
        hasMapping = true;
        final m = <String, dynamic>{
          'key': entry.key,
          'protocol': 'opcua',
          'namespace': opcuaNode['namespace'] as int,
          'identifier': opcuaNode['identifier'] as String,
        };
        if (opcuaNode['server_alias'] != null) {
          m['server_alias'] = opcuaNode['server_alias'];
        }
        if (bitMask != null) m['bit_mask'] = bitMask;
        if (bitShift != null) m['bit_shift'] = bitShift;
        mappings.add(m);
      }

      // Modbus
      final modbusNode = config['modbus_node'] as Map<String, dynamic>?;
      if (modbusNode != null) {
        hasMapping = true;
        final m = <String, dynamic>{
          'key': entry.key,
          'protocol': 'modbus',
          'register_type': modbusNode['register_type'] as String?,
          'address': modbusNode['address'] as int?,
          'data_type': modbusNode['data_type'] as String?,
          'poll_group': modbusNode['poll_group'] as String?,
        };
        if (modbusNode['server_alias'] != null) {
          m['server_alias'] = modbusNode['server_alias'];
        }
        mappings.add(m);
      }

      // M2400
      final m2400Node = config['m2400_node'] as Map<String, dynamic>?;
      if (m2400Node != null) {
        hasMapping = true;
        final m = <String, dynamic>{
          'key': entry.key,
          'protocol': 'm2400',
          'record_type': m2400Node['record_type'] as String?,
        };
        if (m2400Node['field'] != null) {
          m['field'] = m2400Node['field'];
        }
        if (m2400Node['server_alias'] != null) {
          m['server_alias'] = m2400Node['server_alias'];
        }
        mappings.add(m);
      }

      // Skip entries with no recognized protocol mapping
      if (!hasMapping) continue;
    }

    if (filter != null && filter.isNotEmpty) {
      mappings = fuzzyFilter(
        mappings,
        filter,
        [(m) => m['key'] as String],
      );
    }

    return mappings.take(limit).toList();
  }

  /// Returns alarm definition summaries from the alarm table.
  ///
  /// Each entry contains `uid`, `title`, and `description` fields.
  /// Supports optional fuzzy [filter] on title and description.
  /// Results are limited to [limit] entries (default 50).
  ///
  /// Uses raw SQL via [customSelect] because the alarm table is shared
  /// with different row classes in AppDatabase vs ServerDatabase.
  Future<List<Map<String, dynamic>>> listAlarmDefinitions({
    String? filter,
    int limit = 50,
  }) {
    final cacheKey = '${filter ?? ''}:$limit';
    return _alarmDefCache.getOrCompute(cacheKey, () async {
      final rows = await _db.customSelect(
        _sql('SELECT uid, title, description FROM alarm LIMIT ?'),
        variables: [Variable.withInt(limit)],
      ).get();

      var alarms = rows
          .map((row) => {
                'uid': row.read<String>('uid'),
                'title': row.read<String>('title'),
                'description': row.read<String>('description'),
              })
          .toList();

      if (filter != null && filter.isNotEmpty) {
        alarms = fuzzyFilter(
          alarms,
          filter,
          [
            (a) => a['title'] as String,
            (a) => a['description'] as String,
          ],
        );
      }

      return alarms;
    });
  }

  /// Returns the full alarm configuration for the given [uid].
  ///
  /// Returns a map with `uid`, `key`, `title`, `description`, and `rules`
  /// (parsed from JSON string into a List). Returns `null` if no alarm
  /// with the given UID exists.
  ///
  /// Uses raw SQL via [customSelect] because the alarm table is shared
  /// with different row classes in AppDatabase vs ServerDatabase.
  Future<Map<String, dynamic>?> getAlarmConfig(String uid) {
    return _alarmConfigCache.getOrCompute(uid, () async {
      final rows = await _db.customSelect(
        _sql(
            'SELECT uid, key, title, description, rules FROM alarm WHERE uid = ?'),
        variables: [Variable.withString(uid)],
      ).get();
      if (rows.isEmpty) return null;

      final row = rows.first;
      return {
        'uid': row.read<String>('uid'),
        'key': row.readNullable<String>('key'),
        'title': row.read<String>('title'),
        'description': row.read<String>('description'),
        'rules': jsonDecode(row.read<String>('rules')) as List<dynamic>,
      };
    });
  }
}
