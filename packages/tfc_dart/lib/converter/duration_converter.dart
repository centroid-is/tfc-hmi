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
/// Ten years. No retention window, chart window or ratio window is set in
/// centuries, while the smallest microsecond value in the field -- a 30 minute
/// ratio window, 1_800_000_000 -- is over three hundred times this. The two
/// populations are separated by six orders of magnitude, so the test is not a
/// close call. It exists so configs written before the converter was fixed
/// keep their meaning; once those are rewritten it can go.
const int kLegacyMicrosecondCutoffMinutes = 10 * 365 * 24 * 60;

Duration durationFromMinutesTolerant(int value) => value.abs() > kLegacyMicrosecondCutoffMinutes
    ? Duration(microseconds: value)
    : Duration(minutes: value);
