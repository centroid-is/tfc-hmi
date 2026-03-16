import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/alarm_service.dart';
import '../services/config_service.dart';
import '../services/drawing_service.dart';
import '../services/plc_code_service.dart';
import '../services/tag_service.dart';
import '../services/tech_doc_service.dart';
import '../services/trend_service.dart';

/// Registers the `diagnose_equipment` MCP prompt on [mcpServer].
///
/// This prompt assembles multi-source diagnostic context for a specific asset:
/// live tag values, alarm history, trend data, alarm definitions, and optional
/// electrical drawing and PLC code references. It instructs the LLM to guide
/// the operator through structured troubleshooting steps with data evidence.
///
/// **Data assembly:** The callback queries 6+ services to build comprehensive
/// asset context. Trend queries are limited to the first 3 correlated tag keys
/// to reduce database load (the first few give enough diagnostic context).
/// [trendService] is optional — pass null when the Trend History toggle is
/// disabled so the prompt omits the Trend Data section.
/// [configService] is optional — pass null when the System Config toggle is
/// disabled so the prompt omits asset configuration and alarm definitions.
void registerDiagnoseEquipmentPrompt(
  McpServer mcpServer,
  AlarmService alarmService,
  TagService tagService,
  TrendService? trendService,
  ConfigService? configService,
  DrawingService? drawingService,
  PlcCodeService? plcCodeService,
  TechDocService? techDocService,
) {
  final encoder = const JsonEncoder.withIndent('  ');

  mcpServer.registerPrompt(
    'diagnose_equipment',
    description:
        'Guided troubleshooting for a specific asset using live data, '
        'alarm history, trends, and optional electrical drawings',
    argsSchema: {
      'asset_key': PromptArgumentDefinition(
        description: 'The asset key to diagnose (e.g., pump3)',
        required: true,
      ),
    },
    callback: (Map<String, dynamic>? args,
        [RequestHandlerExtra? extra]) async {
      // Validate asset_key argument
      final assetKey = args?['asset_key'] as String?;
      if (assetKey == null || assetKey.isEmpty) {
        return GetPromptResult(
          description: 'Error: asset_key is required',
          messages: [
            PromptMessage(
              role: PromptMessageRole.user,
              content: TextContent(
                text: 'Error: asset_key argument is required. '
                    'Please provide the asset key to diagnose.',
              ),
            ),
          ],
        );
      }

      // Wrap the entire data assembly in try-catch so a DB connection failure
      // returns a degraded prompt instead of crashing the MCP call.
      try {
        return await _assembleDiagnosticPrompt(
          assetKey: assetKey,
          encoder: encoder,
          alarmService: alarmService,
          tagService: tagService,
          trendService: trendService,
          configService: configService,
          drawingService: drawingService,
          plcCodeService: plcCodeService,
          techDocService: techDocService,
        );
      } on Exception catch (e) {
        // Degraded response: return what we can (the asset key) and explain
        // that data sources are temporarily unavailable.
        return GetPromptResult(
          description: 'Diagnose equipment: $assetKey (degraded)',
          messages: [
            PromptMessage(
              role: PromptMessageRole.user,
              content: TextContent(
                text: 'You are an industrial SCADA operator assistant.\n\n'
                    'The operator requested diagnostics for asset "$assetKey" '
                    'but data sources are temporarily unavailable:\n'
                    '${e.toString()}\n\n'
                    'Ask the operator to retry in a moment, or help with '
                    'general troubleshooting advice for this asset type.',
              ),
            ),
          ],
        );
      }
    },
  );
}

/// Assembles the full diagnostic prompt by querying all data sources.
///
/// Extracted from the callback to allow a top-level try-catch that returns
/// a degraded prompt on DB connection failure instead of crashing.
Future<GetPromptResult> _assembleDiagnosticPrompt({
  required String assetKey,
  required JsonEncoder encoder,
  required AlarmService alarmService,
  required TagService tagService,
  required TrendService? trendService,
  required ConfigService? configService,
  required DrawingService? drawingService,
  required PlcCodeService? plcCodeService,
  required TechDocService? techDocService,
}) async {
  // Look up asset configuration (skipped when configService is null).
  Map<String, dynamic>? assetDetail;
  if (configService != null) {
    assetDetail = await configService.getAssetDetail(assetKey);
    if (assetDetail == null) {
      return GetPromptResult(
        description: 'Error: asset not found',
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(
              text: 'Error: Asset with key "$assetKey" was not found. '
                  'Please verify the asset key and try again.',
            ),
          ),
        ],
      );
    }
  }

  // Get correlated tags by asset key prefix
  final correlatedTags = tagService.listTags(
    filter: assetKey,
    limit: 30,
  );

  // Get alarm history for this asset (last 24 hours)
  final now = DateTime.now().toUtc();
  final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));
  final allHistory = await alarmService.queryHistory(
    after: twentyFourHoursAgo,
    limit: 100,
  );
  // Filter alarm history by prefix match on alarm title
  final filteredHistory = allHistory
      .where((a) =>
          (a['alarmTitle'] as String? ?? '')
              .toLowerCase()
              .contains(assetKey.toLowerCase()))
      .toList();

  // Get active alarms and filter by prefix
  final allActive = await alarmService.listActiveAlarms(limit: 50);
  final filteredActive = allActive
      .where((a) =>
          (a['alarmTitle'] as String? ?? '')
              .toLowerCase()
              .contains(assetKey.toLowerCase()))
      .toList();

  // Query trend data for correlated tag keys (last 2 hours, max 3 keys).
  // Reduced from 5 to 3: the first few tags provide sufficient diagnostic
  // context while halving the number of DB round-trips.
  // Skipped entirely when trendService is null (Trend History toggle off).
  final trendLines = <String>[];
  if (trendService != null) {
    final twoHoursAgo = now.subtract(const Duration(hours: 2));
    final trendKeys =
        correlatedTags.take(3).map((t) => t['key'] as String).toList();

    for (final tagKey in trendKeys) {
      try {
        final result = await trendService.queryTrend(
          key: tagKey,
          from: twoHoursAgo,
          to: now,
        );
        if (result.error != null) {
          trendLines.add('$tagKey: No trend data available');
        } else if (result.buckets.isEmpty) {
          trendLines.add('$tagKey: No data in the last 2 hours');
        } else {
          trendLines.add(result.toText());
        }
      } on Exception {
        // Trend query may fail if table doesn't exist or DB dialect mismatch
        trendLines.add('$tagKey: No trend data available');
      }
    }
  }

  final trendSection = trendService == null
      ? 'Trend history is disabled.'
      : trendLines.isEmpty
          ? 'No trend data available for this asset.'
          : trendLines.join('\n');

  // Get alarm definitions for asset (skipped when configService is null).
  final alarmDefinitions = configService == null
      ? <Map<String, dynamic>>[]
      : await configService.listAlarmDefinitions(
          filter: assetKey,
          limit: 20,
        );

  // Search drawings for asset (optional section, skipped when disabled)
  String? drawingsSection;
  if (drawingService != null) {
    final drawingResults = await drawingService.searchDrawings(
      query: assetKey,
      assetFilter: assetKey,
      limit: 5,
    );
    if (drawingResults.isNotEmpty) {
      drawingsSection = '''
## Electrical Drawings
${encoder.convert(drawingResults)}

Reference these drawings for physical inspection of wiring and connections.''';
    }
  }

  // Search PLC code for asset (optional section)
  String? plcCodeSection;
  if (plcCodeService != null) {
    final plcResults =
        await plcCodeService.searchByKey(assetKey, limit: 5);
    if (plcResults.isNotEmpty) {
      final plcSummaries = plcResults
          .map((r) =>
              '${r.blockName} (${r.blockType})'
              '${r.variableName != null ? ' - ${r.variableName}' : ''}')
          .toList();
      plcCodeSection = '''
## PLC Code References
${encoder.convert(plcSummaries)}

These PLC code blocks contain the control logic for this asset.''';
    }
  }

  // Search tech docs for asset (optional section)
  String? techDocSection;
  if (techDocService != null) {
    final techDocResults =
        await techDocService.searchDocs(assetKey, limit: 10);
    if (techDocResults.isNotEmpty) {
      techDocSection = '''
## Knowledge Base
${encoder.convert(techDocResults)}

Use get_tech_doc_section to retrieve full content of relevant sections (e.g., wiring specifications, troubleshooting procedures, fault code descriptions).''';
    }
  }

  // Assemble structured prompt text
  final buffer = StringBuffer();
  buffer.writeln(
      'You are an industrial SCADA operator assistant performing equipment diagnostics.');
  buffer.writeln(
      'Guide the operator through structured troubleshooting for the specified asset.');
  buffer.writeln();
  buffer.writeln('RULES:');
  buffer.writeln(
      '1. Label your response as "AI-generated equipment diagnostic" at the top');
  buffer.writeln(
      '2. Always cite specific data values from the sections below');
  buffer.writeln(
      '3. Structure your response as numbered troubleshooting steps');
  buffer.writeln(
      '4. For each step: state what to check, show the data evidence, explain what it means');
  buffer.writeln(
      '5. If data is insufficient, explicitly state what additional information would help');
  buffer.writeln(
      '6. Include a "Summary" section with: status assessment, priority actions, and recommended next steps');
  buffer.writeln(
      '7. If electrical drawings are available, reference specific drawing pages for physical inspection');
  buffer.writeln(
      '8. If technical documentation is available, reference relevant manufacturer specs and troubleshooting procedures');
  buffer.writeln();
  if (assetDetail != null) {
    buffer.writeln('## Asset Configuration');
    buffer.writeln(encoder.convert(assetDetail));
    buffer.writeln();
  }
  buffer.writeln('## Current Tag Values');
  buffer.writeln(encoder.convert(correlatedTags));
  buffer.writeln();
  buffer.writeln('## Active Alarms for this Asset');
  buffer.writeln(encoder.convert(filteredActive));
  buffer.writeln();
  buffer.writeln('## Alarm History (Last 24 Hours)');
  buffer.writeln(encoder.convert(filteredHistory));
  buffer.writeln();
  buffer.writeln('## Trend Data (Last 2 Hours)');
  buffer.writeln(trendSection);
  buffer.writeln();
  buffer.writeln('## Alarm Definitions');
  buffer.writeln(encoder.convert(alarmDefinitions));

  if (drawingsSection != null) {
    buffer.writeln();
    buffer.writeln(drawingsSection);
  }

  if (plcCodeSection != null) {
    buffer.writeln();
    buffer.writeln(plcCodeSection);
  }

  if (techDocSection != null) {
    buffer.writeln();
    buffer.writeln(techDocSection);
  }

  buffer.writeln();
  buffer.writeln(
      'Diagnose the current state of this asset and guide the operator through troubleshooting.');

  return GetPromptResult(
    description: 'Diagnose equipment: $assetKey',
    messages: [
      PromptMessage(
        role: PromptMessageRole.user,
        content: TextContent(text: buffer.toString().trimRight()),
      ),
    ],
  );
}
