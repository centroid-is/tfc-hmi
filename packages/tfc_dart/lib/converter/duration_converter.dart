import 'package:json_annotation/json_annotation.dart';

class DurationMicrosecondsConverter implements JsonConverter<Duration?, int?> {
  const DurationMicrosecondsConverter();

  @override
  Duration? fromJson(int? json) {
    if (json == null) return null;
    return Duration(microseconds: json);
  }

  @override
  int? toJson(Duration? duration) {
    if (duration == null) return null;
    return duration.inMicroseconds;
  }
}

class DurationMinutesConverter implements JsonConverter<Duration?, int?> {
  const DurationMinutesConverter();

  @override
  Duration? fromJson(int? json) {
    if (json == null) return null;
    return Duration(minutes: json);
  }

  @override
  int? toJson(Duration? duration) {
    if (duration == null) return null;
    return duration.inMinutes;
  }
}

/// Minutes, for a **non-nullable** [Duration].
///
/// json_serializable only applies a converter whose types match the field
/// exactly. [DurationMinutesConverter] is a `JsonConverter<Duration?, int?>`,
/// so on a non-nullable `Duration` field it is silently ignored and the
/// generator falls back to its own Duration handling -- which is
/// *microseconds*. That is how `drop_after_min`, `since_minutes` and
/// `time_window_minutes` all came to hold microseconds despite their names,
/// and how a one-year retention written as 525600 was read back as 525600
/// microseconds: half a second, which drops every closed chunk on the next
/// run of the policy.
///
/// [toJson] always writes minutes. [fromJson] also accepts the microsecond
/// values written while the converter was inert -- see [kLegacyMicrosecondCutoffMinutes].
class DurationMinutesConverterNonNull implements JsonConverter<Duration, int> {
  const DurationMinutesConverterNonNull();

  @override
  Duration fromJson(int json) => durationFromMinutesTolerant(json);

  @override
  int toJson(Duration duration) => duration.inMinutes;
}

/// Above this, a "minutes" value is read as microseconds instead.
///
/// Fifty years. The cutoff has to sit in the *gap* between two populations, and
/// it used to sit at the top of the lower one instead:
///
///   * Legitimate minutes. The largest is a retention policy, which the UI now
///     clamps to ten years = 5_256_000 minutes. Chart and ratio windows are far
///     smaller.
///   * Legacy microseconds, written while the converter was inert. Every field
///     using this converter is *measured in minutes*, and `toJson` wrote
///     `inMinutes`, so the smallest value that era could produce is one minute
///     = 60_000_000 microseconds.
///
/// The gap is therefore (5_256_000, 60_000_000), and this constant sits inside
/// it with roughly five times headroom below and better than two above.
///
/// The old value was ten years exactly — 5_256_000 — which is the *first*
/// number of the lower population rather than a point past it. A retention of
/// 3651 days is 5_257_440 minutes: one day over ten years, one minute-count
/// over the cutoff, and it was read back as 5.25744 seconds. Timescale was then
/// told to drop every chunk older than five seconds, and did. The cliff was
/// inside the range the operator could type, which is the whole defect; moving
/// it into the gap is what fixes it, and the clamp in the UI plus
/// [RetentionPolicy] keeps anything from approaching it again.
///
/// It exists so configs written before the converter was fixed keep their
/// meaning; once those are rewritten it can go.
const int kLegacyMicrosecondCutoffMinutes = 50 * 365 * 24 * 60;

Duration durationFromMinutesTolerant(int value) => value.abs() > kLegacyMicrosecondCutoffMinutes
    ? Duration(microseconds: value)
    : Duration(minutes: value);
