// ---------------------------------------------------------------------------
// Diagnostic service: composite data gatherer for single-call asset diagnostics.
//
// Replaces 6 sequential tool calls (get_tag_value, query_alarm_history,
// search_drawings, search_plc_code, search_tech_docs, query_trend_data)
// with one parallel call that assembles a structured text report.
//
// Follows the AlarmContextService composite pattern: inject services,
// query them in parallel via Future.wait, format into structured text.
// ---------------------------------------------------------------------------

import 'package:logger/logger.dart';

import 'alarm_service.dart';
import 'config_service.dart';
import 'drawing_service.dart';
import 'plc_code_service.dart';
import 'tag_service.dart';
import 'tech_doc_service.dart';
import 'trend_service.dart';

/// Service that gathers all diagnostic data for an asset in parallel.
///
/// Combines live tag values, alarm history, electrical drawings, PLC code,
/// technical documentation, and trend data into a single structured text
/// report optimized for LLM consumption.
///
/// Optional services ([plcCodeService], [techDocService], [drawingService])
/// are nullable -- sections are omitted gracefully when unavailable.
/// Each parallel query is wrapped in try/catch so one failure does not
/// block the others.
class DiagnosticService {
  /// Creates a [DiagnosticService] with all required and optional services.
  ///
  /// [trendService] is optional — pass null when the Trend History toggle is
  /// disabled so trend sections are omitted from the diagnostic report.
  DiagnosticService({
    required this.tagService,
    required this.alarmService,
    this.configService,
    this.trendService,
    this.drawingService,
    this.plcCodeService,
    this.techDocService,
  });

  static final _log = Logger();

  /// Service for real-time tag value queries.
  final TagService tagService;

  /// Service for alarm config and history queries.
  final AlarmService alarmService;

  /// Service for system configuration (pages, key mappings, alarm defs).
  ///
  /// Optional — when null (configEnabled = false), key mapping lookups are
  /// skipped and the Key Mappings section is omitted from the diagnostic report.
  final ConfigService? configService;

  /// Service for time-bucketed trend data (optional).
  ///
  /// Null when the Trend History toggle is disabled — trend sections are
  /// omitted from diagnostic reports when this is null.
  final TrendService? trendService;

  /// Service for electrical drawing searches (optional).
  final DrawingService? drawingService;

  /// Service for PLC code searches (optional).
  final PlcCodeService? plcCodeService;

  /// Service for technical documentation searches (optional).
  final TechDocService? techDocService;

  /// Gathers all diagnostic data for an asset in parallel.
  ///
  /// Returns a structured text report combining all data sources.
  /// Each section is independently fetched; failures in one section
  /// do not prevent other sections from returning data.
  ///
  /// [assetKey] is the logical key identifying the asset (e.g., "pump3").
  /// [hoursHistory] controls how far back alarm history and trend data
  /// are queried (default 4 hours).
  Future<String> diagnoseAsset({
    required String assetKey,
    int hoursHistory = 4,
  }) async {
    final now = DateTime.now().toUtc();
    final historyStart = now.subtract(Duration(hours: hoursHistory));

    // Step 1: Look up key mappings for associated tag paths.
    // Skipped when configService is null (configEnabled = false).
    List<Map<String, dynamic>> keyMappings;
    if (configService == null) {
      keyMappings = [];
    } else {
      try {
        keyMappings = await configService!.listKeyMappings(
          filter: assetKey,
          limit: 50,
        );
      } on Exception {
        keyMappings = [];
      }
    }

    // Extract mapped tag keys for targeted queries.
    final mappedKeys = keyMappings
        .map((m) => m['key'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    // Step 2: Query all data sources in parallel.
    // Each query is wrapped in a helper that catches exceptions and returns
    // a safe default so Future.wait never fails. Each is also timed so slow
    // queries (>3s) are logged for diagnostics.
    final overallSw = Stopwatch()..start();
    final results = await Future.wait([
      _timed('liveTagValues', _fetchLiveTagValues(assetKey, mappedKeys)), // [0]
      _timed('alarmHistory', _fetchAlarmHistory(assetKey, historyStart)), // [1]
      _timed('activeAlarms', _fetchActiveAlarms(assetKey)), // [2]
      _timed('drawings', _fetchDrawings(assetKey)), // [3]
      _timed('plcCode', _fetchPlcCode(assetKey)), // [4]
      _timed('techDocs', _fetchTechDocs(assetKey)), // [5]
      _timed('trendData', _fetchTrendData(mappedKeys, historyStart, now)), // [6]
      _timed('keyMappings', _fetchKeyMappingsSection(keyMappings)), // [7]
    ]);
    overallSw.stop();
    if (overallSw.elapsedMilliseconds > 3000) {
      _log.w('diagnoseAsset("$assetKey") total: ${overallSw.elapsedMilliseconds}ms');
    }

    final liveTagSection = results[0] as String;
    final alarmHistorySection = results[1] as String;
    final activeAlarmsSection = results[2] as String;
    final drawingsSection = results[3] as String;
    final plcCodeSection = results[4] as String;
    final techDocsSection = results[5] as String;
    final trendSection = results[6] as String;
    final keyMappingsSection = results[7] as String;

    // Step 3: Assemble the structured text report.
    final buffer = StringBuffer();
    buffer.writeln('=== ASSET DIAGNOSTIC: $assetKey ===');
    buffer.writeln();
    buffer.writeln(liveTagSection);
    buffer.writeln();
    buffer.writeln(activeAlarmsSection);
    buffer.writeln();
    buffer.writeln(alarmHistorySection);
    buffer.writeln();
    buffer.writeln(keyMappingsSection);
    buffer.writeln();
    buffer.writeln(drawingsSection);
    buffer.writeln();
    buffer.writeln(plcCodeSection);
    buffer.writeln();
    buffer.writeln(techDocsSection);
    buffer.writeln();
    buffer.writeln(trendSection);
    buffer.writeln();
    buffer.writeln('=== END DIAGNOSTIC ===');

    return buffer.toString().trimRight();
  }

  // ── Timing helper ────────────────────────────────────────────────────

  /// Wraps a [future] with a [Stopwatch], logging a warning when the query
  /// takes longer than 3 seconds. The [label] identifies the query in logs.
  Future<T> _timed<T>(String label, Future<T> future) async {
    final sw = Stopwatch()..start();
    try {
      return await future;
    } finally {
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      if (ms > 3000) {
        _log.w('Slow diagnostic query "$label": ${ms}ms');
      }
    }
  }

  // ── Private data fetchers ─────────────────────────────────────────────

  /// Fetch live tag values matching the asset key or its mapped keys.
  Future<String> _fetchLiveTagValues(
    String assetKey,
    List<String> mappedKeys,
  ) async {
    try {
      // Get tags by asset key prefix (fuzzy match).
      final tags = tagService.listTags(filter: assetKey, limit: 50);

      // Also get specific mapped keys that might not fuzzy-match.
      final tagMap = <String, dynamic>{};
      for (final tag in tags) {
        tagMap[tag['key'] as String] = tag['value'];
      }
      for (final key in mappedKeys) {
        if (!tagMap.containsKey(key)) {
          final tagValue = tagService.getTagValue(key);
          if (tagValue != null) {
            tagMap[tagValue['key'] as String] = tagValue['value'];
          }
        }
      }

      if (tagMap.isEmpty) {
        return '## Live Tag Values\nNo tags found matching "$assetKey".';
      }

      final buffer = StringBuffer('## Live Tag Values');
      for (final entry in tagMap.entries) {
        buffer.writeln();
        buffer.write('${entry.key}: ${entry.value}');
      }
      return buffer.toString();
    } on Exception catch (e) {
      return '## Live Tag Values\nError fetching tag values: $e';
    }
  }

  /// Fetch recent alarm history for the asset.
  Future<String> _fetchAlarmHistory(
    String assetKey,
    DateTime after,
  ) async {
    try {
      final history = await alarmService.queryHistory(
        after: after,
        limit: 50,
      );

      // Filter by asset key prefix in the alarm title or description.
      final assetLower = assetKey.toLowerCase();
      final filtered = history
          .where((a) =>
              (a['alarmTitle'] as String? ?? '')
                  .toLowerCase()
                  .contains(assetLower) ||
              (a['alarmDescription'] as String? ?? '')
                  .toLowerCase()
                  .contains(assetLower))
          .toList();

      if (filtered.isEmpty) {
        return '## Recent Alarm History\n'
            'No alarm history in the specified period.';
      }

      final buffer = StringBuffer('## Recent Alarm History');
      for (final record in filtered) {
        final status = record['active'] == true ? 'ACTIVE' : 'RESOLVED';
        buffer.writeln();
        buffer.write(
            '[$status] [${record['alarmLevel']}] ${record['alarmTitle']}');
        buffer.writeln();
        buffer.write('  ${record['alarmDescription']}');
        buffer.writeln();
        buffer.write('  Activated: ${record['createdAt']}');
        if (record['deactivatedAt'] != null) {
          buffer.writeln();
          buffer.write('  Resolved: ${record['deactivatedAt']}');
        }
        if (record['expression'] != null) {
          buffer.writeln();
          buffer.write('  Expression: ${record['expression']}');
        }
      }
      return buffer.toString();
    } on Exception catch (e) {
      return '## Recent Alarm History\nError fetching alarm history: $e';
    }
  }

  /// Fetch currently active alarms for the asset.
  Future<String> _fetchActiveAlarms(String assetKey) async {
    try {
      final active = await alarmService.listActiveAlarms(limit: 50);

      final assetLower = assetKey.toLowerCase();
      final filtered = active
          .where((a) =>
              (a['alarmTitle'] as String? ?? '')
                  .toLowerCase()
                  .contains(assetLower) ||
              (a['alarmDescription'] as String? ?? '')
                  .toLowerCase()
                  .contains(assetLower))
          .toList();

      if (filtered.isEmpty) {
        return '## Active Alarms\nNo active alarms for this asset.';
      }

      final buffer = StringBuffer('## Active Alarms');
      for (final alarm in filtered) {
        buffer.writeln();
        buffer.write('[${alarm['alarmLevel']}] ${alarm['alarmTitle']}');
        buffer.writeln();
        buffer.write('  ${alarm['alarmDescription']}');
        buffer.writeln();
        buffer.write('  Since: ${alarm['createdAt']}');
      }
      return buffer.toString();
    } on Exception catch (e) {
      return '## Active Alarms\nError fetching active alarms: $e';
    }
  }

  /// Fetch electrical drawings matching the asset key.
  Future<String> _fetchDrawings(String assetKey) async {
    if (drawingService == null) {
      return '## Electrical Drawings\nDrawing index not available.';
    }

    try {
      if (!(await drawingService!.hasDrawings)) {
        return '## Electrical Drawings\nNo electrical drawings indexed.';
      }

      final results = await drawingService!.searchDrawings(
        query: assetKey,
        limit: 10,
      );

      if (results.isEmpty) {
        return '## Electrical Drawings\n'
            'No drawings match "$assetKey".';
      }

      final buffer = StringBuffer(
          '## Electrical Drawings\nFound ${results.length} relevant drawing(s):');
      for (final r in results) {
        buffer.writeln();
        buffer.write('- ${r['componentName']} on ${r['drawingName']}, '
            'page ${r['pageNumber']} (asset: ${r['assetKey']})');
      }
      return buffer.toString();
    } on Exception catch (e) {
      return '## Electrical Drawings\nError searching drawings: $e';
    }
  }

  /// Fetch PLC code blocks matching the asset key.
  Future<String> _fetchPlcCode(String assetKey) async {
    if (plcCodeService == null) {
      return '## PLC Code\nPLC code index not available.';
    }

    try {
      // Let search() run — it calls _ensureInitialized() which properly
      // queries the DB. No synchronous hasCode gate needed.

      // Try key-based search first (correlates via OPC UA identifiers).
      var results = await plcCodeService!.searchByKey(assetKey, limit: 10);

      // Fall back to text search if key search yields nothing.
      if (results.isEmpty) {
        results = await plcCodeService!.search(
          assetKey,
          mode: 'text',
          limit: 10,
        );
      }

      if (results.isEmpty) {
        return '## PLC Code\nNo PLC code matches "$assetKey".';
      }

      final buffer = StringBuffer(
          '## PLC Code\nFound ${results.length} relevant code block(s):');
      for (final r in results) {
        buffer.writeln();
        buffer.write('- ${r.blockName} (${r.blockType})');
        if (r.variableName != null) {
          buffer.write(' — ${r.variableName}: ${r.variableType}');
        }
        buffer.write(' [asset: ${r.assetKey}]');
        if (r.declarationLine != null) {
          buffer.writeln();
          buffer.write('    > ${r.declarationLine}');
        }
      }
      return buffer.toString();
    } on Exception catch (e) {
      return '## PLC Code\nError searching PLC code: $e';
    }
  }

  /// Fetch technical documentation matching the asset key.
  Future<String> _fetchTechDocs(String assetKey) async {
    if (techDocService == null) {
      return '## Technical Documentation\n'
          'Technical documentation index not available.';
    }

    try {
      if (await techDocService!.isEmpty) {
        return '## Technical Documentation\n'
            'No technical documents uploaded.';
      }

      final results = await techDocService!.searchDocs(assetKey, limit: 10);

      if (results.isEmpty) {
        return '## Technical Documentation\n'
            'No documentation matches "$assetKey".';
      }

      final buffer = StringBuffer('## Technical Documentation\n'
          'Found ${results.length} relevant section(s):');
      for (final r in results) {
        buffer.writeln();
        buffer.write('- ${r['docName']} > ${r['sectionTitle']} '
            '(pages ${r['pageStart']}-${r['pageEnd']}) '
            '[section_id: ${r['sectionId']}]');
      }
      return buffer.toString();
    } on Exception catch (e) {
      return '## Technical Documentation\nError searching tech docs: $e';
    }
  }

  /// Fetch trend data for the mapped tag keys.
  Future<String> _fetchTrendData(
    List<String> tagKeys,
    DateTime from,
    DateTime to,
  ) async {
    if (trendService == null) {
      return '## Trend Data\nTrend history is disabled.';
    }
    if (tagKeys.isEmpty) {
      return '## Trend Data\nNo mapped tags to query trend data for.';
    }

    // Limit to first 5 keys to avoid excessive DB load.
    final keysToQuery = tagKeys.take(5).toList();
    final trendLines = <String>[];

    // Outer try-catch guards against connection-level failures.
    try {
      for (final key in keysToQuery) {
        try {
          final result = await trendService!.queryTrend(
            key: key,
            from: from,
            to: to,
          );
          if (result.error != null) {
            trendLines.add('$key: No trend data available');
          } else if (result.buckets.isEmpty) {
            trendLines.add('$key: No data in the requested period');
          } else {
            // Summarize: compute overall min/avg/max across all buckets.
            double overallMin = double.infinity;
            double overallMax = double.negativeInfinity;
            double sumAvg = 0;
            int bucketCount = 0;
            for (final b in result.buckets) {
              if (b.minVal < overallMin) overallMin = b.minVal;
              if (b.maxVal > overallMax) overallMax = b.maxVal;
              sumAvg += b.avgVal;
              bucketCount++;
            }
            final overallAvg = bucketCount > 0 ? sumAvg / bucketCount : 0.0;
            trendLines.add(
              '$key: avg=${overallAvg.toStringAsFixed(2)}, '
              'min=${overallMin.toStringAsFixed(2)}, '
              'max=${overallMax.toStringAsFixed(2)} '
              '(${bucketCount} buckets)',
            );
          }
        } on Exception {
          trendLines.add('$key: No trend data available');
        }
      }
    } on Object {
      trendLines.add('Trend queries aborted: database connection error');
    }

    if (trendLines.isEmpty) {
      return '## Trend Data\nNo trend data available.';
    }

    final buffer = StringBuffer('## Trend Data');
    for (final line in trendLines) {
      buffer.writeln();
      buffer.write(line);
    }
    return buffer.toString();
  }

  /// Format key mappings section from the already-fetched mappings.
  Future<String> _fetchKeyMappingsSection(
    List<Map<String, dynamic>> keyMappings,
  ) async {
    if (configService == null) {
      return '## Key Mappings\nSystem config is disabled.';
    }
    if (keyMappings.isEmpty) {
      return '## Key Mappings\nNo key mappings found for this asset.';
    }

    final buffer =
        StringBuffer('## Key Mappings\n${keyMappings.length} mapping(s):');
    for (final m in keyMappings) {
      final protocol = m['protocol'] as String? ?? 'unknown';
      buffer.writeln();
      switch (protocol) {
        case 'opcua':
          buffer.write(
              '- ${m['key']} -> opcua ${m['namespace']}:${m['identifier']}');
        case 'modbus':
          buffer.write(
              '- ${m['key']} -> modbus ${m['register_type']}@${m['address']} '
              '(${m['data_type']}, group: ${m['poll_group']})');
        case 'm2400':
          final field = m['field'] != null ? ', field: ${m['field']}' : '';
          buffer.write('- ${m['key']} -> m2400 ${m['record_type']}$field');
        default:
          buffer.write('- ${m['key']} -> $protocol');
      }
    }
    return buffer.toString();
  }
}
