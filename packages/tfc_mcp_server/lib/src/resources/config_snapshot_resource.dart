import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/config_service.dart';

/// Registers the `scada://config/snapshot` resource on [mcpServer].
///
/// This resource returns a curated JSON summary of the current system
/// configuration including pages, assets, key mappings, and alarm definitions.
/// Data is assembled from [configService] methods with generous limits to
/// capture the full configuration without dumping raw JSON blobs.
///
/// The snapshot follows the progressive discovery pattern: each section
/// contains summary fields (key, title, etc.) rather than full widget
/// configurations or editor data.
void registerConfigSnapshotResource(
  McpServer mcpServer,
  ConfigService configService,
) {
  mcpServer.registerResource(
    'System Configuration Snapshot',
    'scada://config/snapshot',
    (
      description:
          'Current system configuration including pages, assets, key mappings, '
          'and alarm definitions',
      mimeType: 'application/json',
    ),
    (Uri uri, RequestHandlerExtra extra) async {
      final pages = await configService.listPages(limit: 200);
      final assets = await configService.listAssets(limit: 200);
      final keyMappings = await configService.listKeyMappings(limit: 500);
      final alarmDefinitions =
          await configService.listAlarmDefinitions(limit: 500);

      final snapshot = {
        'pages': pages,
        'assets': assets,
        'key_mappings': keyMappings,
        'alarm_definitions': alarmDefinitions,
      };

      final encoder = const JsonEncoder.withIndent('  ');

      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: 'application/json',
            text: encoder.convert(snapshot),
          ),
        ],
      );
    },
  );
}
