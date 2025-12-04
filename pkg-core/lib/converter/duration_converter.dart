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
