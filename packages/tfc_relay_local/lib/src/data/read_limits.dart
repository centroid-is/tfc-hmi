/// The outbound size ceilings — **RED skeleton**, filled by the GREEN commit.
///
/// Placeholders on purpose: every number below is zero so that each named case
/// in `read_limits_test.dart` fails on the property it is about rather than on
/// a missing symbol. The derivation, the arithmetic and the doc comments the
/// plan asks for arrive with the values.
library;

/// Ceilings on what one answer may be, before it is built.
final class ReadLimits {
  ReadLimits({
    this.maxTimeseriesRows = defaultMaxTimeseriesRows,
    this.maxPreferenceBytes = defaultMaxPreferenceBytes,
  });

  /// Placeholder.
  static const int defaultMaxTimeseriesRows = 0;

  /// Placeholder.
  static const int defaultMaxPreferenceBytes = 0;

  /// Placeholder.
  static const int measuredBytesPerSample = 0;

  /// Placeholder.
  final int maxTimeseriesRows;

  /// Placeholder.
  final int maxPreferenceBytes;
}
