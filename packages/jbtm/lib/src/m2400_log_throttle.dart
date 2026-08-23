/// Count-and-report throttling for the M2400 parse log sites.
///
/// A malformed weigher record is never a one-off. The M2400s stream records
/// continuously -- eight scales, one record per weighment -- so a single field
/// the firmware emits in an unexpected shape turns into one log line per
/// record for as long as the line is running. Measured: `parseTypedRecord` on
/// a 17-field record with two unknown field ids costs 139,951ns, of which
/// 138,171ns is two `Logger.d` calls.
///
/// Worse, three of those sites are warnings, which survive every
/// `CENTROID_LOG_LEVEL` a station would realistically be set to. Turning the
/// level down does not fix them; counting does.
///
/// So: report the first occurrence of each distinct reason, then every
/// thousandth, carrying the running count -- the same shape as
/// `Collector`'s `_eventCount % 1000 == 1`. The first line still tells support
/// that the condition exists; the count tells them whether it is a hiccup or
/// the whole shift.
library;

final Map<String, int> _counts = <String, int>{};

/// How often a reason repeats before it is logged again.
const int m2400LogReportInterval = 1000;

/// Records one occurrence of [reason] and returns whether it should be logged.
///
/// True on the first occurrence and every [m2400LogReportInterval]th after
/// that.
///
/// [reason] must come from a bounded set -- a field id, a record type id, a
/// fixed string -- never raw device data, or the map grows without bound.
bool shouldReportM2400(String reason) {
  final n = (_counts[reason] ?? 0) + 1;
  _counts[reason] = n;
  return n == 1 || n % m2400LogReportInterval == 1;
}

/// The number of times [reason] has occurred, including suppressed ones.
int m2400LogCount(String reason) => _counts[reason] ?? 0;

/// Clears every counter. For tests, and for anything that wants a fresh
/// report after a reconnect.
void resetM2400LogCounts() => _counts.clear();
