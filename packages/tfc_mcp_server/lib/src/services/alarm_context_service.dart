import 'alarm_service.dart';
import 'config_service.dart';
import 'tag_service.dart';
import 'trend_service.dart';

/// A single event in the causal chain leading to or surrounding an alarm.
///
/// Events are collected from alarm history (activations/deactivations) and
/// sibling alarms (same asset prefix), then sorted chronologically to form
/// the causal chain.
class CausalEvent {
  /// Creates a [CausalEvent].
  CausalEvent({
    required this.timestamp,
    required this.eventType,
    required this.description,
    this.evidence,
  });

  /// When the event occurred.
  final DateTime timestamp;

  /// Type of event: 'alarm_activated', 'alarm_deactivated', or 'sibling_alarm'.
  final String eventType;

  /// Human-readable description of the event.
  final String description;

  /// Supporting evidence (e.g., the expression that triggered, tag value).
  final String? evidence;
}

/// Structured context about an alarm including causal chain, correlated data,
/// and trend information.
///
/// Built by [AlarmContextService.buildContext] from multiple data sources.
class AlarmContext {
  /// Creates an [AlarmContext].
  AlarmContext({
    required this.alarmDetail,
    required this.causalEvents,
    required this.correlatedTags,
    required this.trendSummary,
    required this.alarmDefinitions,
  });

  /// The alarm configuration (uid, key, title, description, rules).
  final Map<String, dynamic> alarmDetail;

  /// Chronologically-ordered events forming the causal chain.
  final List<CausalEvent> causalEvents;

  /// Sibling tag values sharing the same prefix as the alarm key.
  final List<Map<String, dynamic>> correlatedTags;

  /// Summary of trend data preceding the alarm event.
  final String trendSummary;

  /// Alarm definitions matching the alarm (from ConfigService).
  final List<Map<String, dynamic>> alarmDefinitions;

  /// Format the alarm context as structured human-readable text.
  ///
  /// Produces sections: Alarm Detail, Causal Chain, Correlated Tag Values,
  /// Trend Context, and Alarm Definitions.
  String toText() {
    final buffer = StringBuffer();

    // Section 1: Alarm Detail
    buffer.writeln('## Alarm Detail');
    final title = alarmDetail['title'] ?? 'Unknown';
    final key = alarmDetail['key'] ?? 'Unknown';
    final description = alarmDetail['description'] ?? '';
    final rules = alarmDetail['rules'] ?? [];
    buffer.writeln('Title: $title');
    buffer.writeln('Key: $key');
    buffer.writeln('Description: $description');
    buffer.writeln('Rules: $rules');
    buffer.writeln();

    // Section 2: Causal Chain
    buffer.writeln('## Causal Chain (chronological)');
    if (causalEvents.isEmpty) {
      buffer.writeln('No events found.');
    } else {
      for (final event in causalEvents) {
        buffer.writeln(
          '${event.timestamp.toUtc().toIso8601String()} | '
          '${event.eventType} | ${event.description}',
        );
        if (event.evidence != null) {
          buffer.writeln('  Evidence: ${event.evidence}');
        }
      }
    }
    buffer.writeln();

    // Section 3: Correlated Tag Values
    buffer.writeln('## Correlated Tag Values');
    if (correlatedTags.isEmpty) {
      buffer.writeln('No correlated tags found.');
    } else {
      for (final tag in correlatedTags) {
        buffer.writeln('${tag['key']}: ${tag['value']}');
      }
    }
    buffer.writeln();

    // Section 4: Trend Context
    buffer.writeln('## Trend Context (preceding the alarm)');
    buffer.writeln(trendSummary);
    buffer.writeln();

    // Section 5: Alarm Definitions
    buffer.writeln('## Alarm Definitions');
    if (alarmDefinitions.isEmpty) {
      buffer.writeln('No alarm definitions found.');
    } else {
      for (final def in alarmDefinitions) {
        buffer.writeln(
          '${def['uid']}: ${def['title']} - ${def['description']}',
        );
      }
    }

    return buffer.toString().trimRight();
  }
}

/// Service that constructs causal chains explaining WHY an alarm fired.
///
/// Correlates alarm history, sibling tag values, trend data, and related
/// alarms to produce a structured [AlarmContext] that enables the AI to
/// give precise, data-backed explanations.
class AlarmContextService {
  /// Creates an [AlarmContextService] with the required dependencies.
  AlarmContextService({
    required this.alarmService,
    required this.tagService,
    required this.trendService,
    this.configService,
  });

  /// Service for alarm config and history queries.
  final AlarmService alarmService;

  /// Service for real-time tag value queries.
  final TagService tagService;

  /// Service for time-bucketed trend data.
  final TrendService trendService;

  /// Service for alarm definitions and config.
  ///
  /// Optional — when null (configEnabled = false), the alarm definitions
  /// section of the context is omitted.
  final ConfigService? configService;

  /// Build a structured alarm context for the given [alarmUid].
  ///
  /// Returns `null` if the alarm UID is not found in the alarm config.
  ///
  /// The context includes:
  /// - Alarm configuration detail
  /// - Chronologically-ordered causal chain from alarm history and siblings
  /// - Correlated tag values by prefix
  /// - Trend data summary preceding the alarm event
  /// - Alarm definitions matching the alarm
  Future<AlarmContext?> buildContext(String alarmUid) async {
    // Step A: Look up alarm config -- return null if not found
    final alarmDetail = alarmService.getAlarmDetail(alarmUid);
    if (alarmDetail == null) return null;

    // Step B: Extract prefix from alarm key using lastIndexOf('.') pattern
    final alarmKey = alarmDetail['key'] as String? ?? '';
    final dotIndex = alarmKey.lastIndexOf('.');
    final prefix = dotIndex > 0 ? alarmKey.substring(0, dotIndex) : alarmKey;

    // Step C+D: Query alarm history ONCE (last 24 hours, unfiltered) and
    // partition results into "this alarm" vs "sibling alarms". This avoids
    // the previous double-query pattern that made two separate DB round-trips
    // (one filtered by UID, one unfiltered).
    final twentyFourHoursAgo =
        DateTime.now().toUtc().subtract(const Duration(hours: 24));

    // Build a UID-to-config map from all alarm configs to avoid per-row
    // getAlarmDetail() calls (was N+1 queries when backed by DB, and O(N*M)
    // linear scans even for in-memory readers).
    final allConfigs = alarmService.getAllAlarmConfigs();
    final configByUid = <String, Map<String, dynamic>>{};
    for (final cfg in allConfigs) {
      final uid = cfg['uid'] as String?;
      if (uid != null) configByUid[uid] = cfg;
    }

    // Single DB query for all recent alarm history
    final allRecentHistory = await alarmService.queryHistory(
      after: twentyFourHoursAgo,
      limit: 100,
    );

    final causalEvents = <CausalEvent>[];

    for (final row in allRecentHistory) {
      final rowUid = row['alarmUid'] as String?;
      final createdAt = DateTime.parse(row['createdAt'] as String);
      final expression = row['expression'] as String?;

      if (rowUid == alarmUid) {
        // This alarm's own history -> alarm_activated / alarm_deactivated
        final isActive = row['active'] as bool? ?? false;
        final eventType =
            isActive ? 'alarm_activated' : 'alarm_deactivated';

        causalEvents.add(CausalEvent(
          timestamp: createdAt,
          eventType: eventType,
          description:
              '${row['alarmTitle']} (${row['alarmLevel']})',
          evidence: expression,
        ));
      } else {
        // Check if this is a sibling alarm (same prefix, different UID)
        final siblingDetail = configByUid[rowUid ?? ''];
        if (siblingDetail == null) continue;

        final siblingKey = siblingDetail['key'] as String? ?? '';
        final siblingDotIndex = siblingKey.lastIndexOf('.');
        final siblingPrefix = siblingDotIndex > 0
            ? siblingKey.substring(0, siblingDotIndex)
            : siblingKey;

        if (siblingPrefix != prefix) continue; // Different prefix, skip

        final rowTitle = row['alarmTitle'] as String? ?? '';
        causalEvents.add(CausalEvent(
          timestamp: createdAt,
          eventType: 'sibling_alarm',
          description: '$rowTitle (${row['alarmLevel']})',
          evidence: expression,
        ));
      }
    }

    // Step E: Get correlated tag values by prefix
    // Limit to 5 tags for trend queries — most diagnostic context comes from
    // the first few related tags, and each tag generates 1-2 DB queries.
    final correlatedTags = tagService.listTags(
      filter: prefix,
      limit: 5,
    );

    // Step F: Query trend data for correlated tag keys
    final trendLines = <String>[];
    // Determine the alarm time from the most recent history event for this UID.
    // allRecentHistory is ordered by createdAt DESC, so the first match is most recent.
    DateTime? alarmTime;
    final ownHistory = allRecentHistory
        .where((r) => r['alarmUid'] == alarmUid)
        .toList();
    if (ownHistory.isNotEmpty) {
      alarmTime = DateTime.parse(ownHistory.first['createdAt'] as String);
    }
    alarmTime ??= DateTime.now().toUtc();

    final trendFrom = alarmTime.subtract(const Duration(hours: 1));
    // Outer try-catch guards against connection-level failures (e.g.,
    // SocketException: Connection reset by peer) that would abort all
    // remaining trend queries.
    try {
      for (final tag in correlatedTags) {
        final tagKey = tag['key'] as String;
        try {
          final result = await trendService.queryTrend(
            key: tagKey,
            from: trendFrom,
            to: alarmTime,
          );
          if (result.error != null) {
            trendLines.add('$tagKey: No trend data available');
          } else if (result.buckets.isEmpty) {
            trendLines.add('$tagKey: No data in the preceding hour');
          } else {
            trendLines.add(result.toText());
          }
        } on Exception {
          // Trend query may fail if table doesn't exist or DB dialect mismatch
          trendLines.add('$tagKey: No trend data available');
        }
      }
    } on Object {
      // Connection-level failure — abandon remaining trend queries gracefully
      trendLines.add('Trend queries aborted: database connection error');
    }

    final trendSummary = trendLines.isEmpty
        ? 'No trend data available'
        : trendLines.join('\n');

    // Step G: Get alarm definitions using the alarm title for fuzzy matching.
    // Skipped when configService is null (configEnabled = false).
    // (listAlarmDefinitions filters on title/description, not uid)
    final alarmTitle = alarmDetail['title'] as String? ?? '';
    final alarmDefinitions = configService == null
        ? <Map<String, dynamic>>[]
        : await configService!.listAlarmDefinitions(
            filter: alarmTitle.isNotEmpty ? alarmTitle : null,
            limit: 5,
          );

    // Step H: Sort all causal events by timestamp ascending
    causalEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Step I: Build and return AlarmContext
    return AlarmContext(
      alarmDetail: alarmDetail,
      causalEvents: causalEvents,
      correlatedTags: correlatedTags,
      trendSummary: trendSummary,
      alarmDefinitions: alarmDefinitions,
    );
  }
}
