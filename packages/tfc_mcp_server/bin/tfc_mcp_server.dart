import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'package:tfc_mcp_server/tfc_mcp_server.dart';

const _version = '0.1.0';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage help')
    ..addFlag('version',
        abbr: 'v', negatable: false, help: 'Show version number')
    ..addOption('db-host',
        help: 'PostgreSQL host (or CENTROID_PGHOST env var)',
        defaultsTo: 'localhost')
    ..addOption('db-port',
        help: 'PostgreSQL port (or CENTROID_PGPORT env var)',
        defaultsTo: '5432')
    ..addOption('db-name',
        help: 'PostgreSQL database (or CENTROID_PGDATABASE env var)',
        defaultsTo: 'hmi')
    ..addOption('db-user',
        help: 'PostgreSQL user (or CENTROID_PGUSER env var)',
        defaultsTo: 'postgres')
    ..addOption('db-password',
        help: 'PostgreSQL password (or CENTROID_PGPASSWORD env var)',
        defaultsTo: '');

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('Usage: tfc_mcp_server [options]');
    stderr.writeln(parser.usage);
    exit(64); // EX_USAGE
  }

  if (results.flag('help')) {
    stderr.writeln('TFC MCP Server - AI copilot for TFC HMI');
    stderr.writeln('');
    stderr.writeln('Usage: tfc_mcp_server [options]');
    stderr.writeln('');
    stderr.writeln(parser.usage);
    exit(0);
  }

  if (results.flag('version')) {
    stderr.writeln('tfc_mcp_server $_version');
    exit(0);
  }

  final logger = createServerLogger();
  logger.i('Starting TFC MCP Server v$_version');

  // Create operator identity from TFC_USER environment variable
  final identity = EnvOperatorIdentity();

  // Build database config from env vars + CLI arg fallbacks.
  // Env vars (CENTROID_PG*) take precedence over CLI args, which take
  // precedence over hard-coded defaults.
  final dbConfig = ServerDatabaseConfig.fromEnvironment(
    cliArgs: {
      'db-host': results['db-host'] as String,
      'db-port': results['db-port'] as String,
      'db-name': results['db-name'] as String,
      'db-user': results['db-user'] as String,
      'db-password': results['db-password'] as String,
    },
  );

  // Create database -- use in-memory SQLite for development/testing
  // when no PostgreSQL connection is available. In production, connect
  // to the same PostgreSQL instance as the HMI app.
  ServerDatabase db;
  try {
    db = ServerDatabase.fromConfig(dbConfig);
    logger.i('Connected to PostgreSQL at ${dbConfig.endpoint.host}:'
        '${dbConfig.endpoint.port}/${dbConfig.endpoint.database}');
  } on Exception catch (e) {
    logger.w('PostgreSQL connection failed ($e), using in-memory SQLite');
    db = ServerDatabase.inMemory();
  }

  // In standalone mode (Claude Desktop), no live StateMan/AlarmMan is
  // available. Create empty readers as placeholders. Real data comes from
  // database queries (alarm history, config). In production (Flutter-spawned),
  // these will be populated via IPC (Phase 5).
  final stateReader = EmptyStateReader();
  final alarmReader = EmptyAlarmReader();

  // Read tool toggle state from flutter_preferences table.
  // First tries consolidated McpConfig key, falls back to legacy keys.
  final toggles = await _readTogglesFromDb(db);
  logger.i('Tool toggles: tags=${toggles.tagsEnabled}, '
      'alarms=${toggles.alarmsEnabled}, config=${toggles.configEnabled}, '
      'drawings=${toggles.drawingsEnabled}, trends=${toggles.trendsEnabled}, '
      'plcCode=${toggles.plcCodeEnabled}, proposals=${toggles.proposalsEnabled}');

  final server = TfcMcpServer(
    identity: identity,
    database: db,
    stateReader: stateReader,
    alarmReader: alarmReader,
    plcCodeIndex: DriftPlcCodeIndex(db),
    toggles: toggles,
    logger: logger,
  );
  final transport = StdioServerTransport();

  // Handle SIGTERM/SIGINT for clean shutdown.
  // This binary expects SIGTERM for clean shutdown from the Flutter-side
  // McpBridgeNotifier (Phase 5). It closes DB connections and flushes logs.
  final shutdownCompleter = Completer<void>();

  void handleShutdown(ProcessSignal signal) {
    logger.i('Received ${signal.toString()}, shutting down...');
    server.close().then((_) {
      shutdownCompleter.complete();
      exit(0);
    });
  }

  ProcessSignal.sigterm.watch().listen(handleShutdown);
  // SIGINT for Ctrl+C during development
  ProcessSignal.sigint.watch().listen(handleShutdown);

  await server.connect(transport);

  logger.i('TFC MCP Server is running on stdio transport.');
}

/// Read tool toggle state from the `flutter_preferences` table.
///
/// First tries the consolidated [McpConfig.kPrefKey] JSON blob. If not
/// found, falls back to reading legacy individual `mcp_tools_*_enabled`
/// keys. Missing keys default to `true` (enabled) so that a fresh
/// database with no toggle preferences has all tools available.
Future<McpToolToggles> _readTogglesFromDb(ServerDatabase db) async {
  // Try consolidated config first.
  final configRows = await (db.select(db.serverFlutterPreferences)
        ..where((t) => t.key.equals(McpConfig.kPrefKey)))
      .get();

  if (configRows.isNotEmpty &&
      configRows.first.type == 'String' &&
      configRows.first.value != null) {
    try {
      final json =
          jsonDecode(configRows.first.value!) as Map<String, dynamic>;
      return McpConfig.fromJson(json).toggles;
    } catch (_) {
      // Corrupted JSON -- fall through to legacy keys.
    }
  }

  // Fall back to legacy individual keys.
  final rows = await (db.select(db.serverFlutterPreferences)
        ..where((t) => t.key.isIn(McpToolToggles.legacyKeys)))
      .get();

  final toggleMap = <String, bool>{};
  for (final row in rows) {
    if (row.type == 'bool') {
      toggleMap[row.key] = row.value == 'true';
    }
  }

  return McpToolToggles.fromLegacyMap(toggleMap);
}
