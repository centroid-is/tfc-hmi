/// The refusal a query too big to answer raises.
///
/// ## Refuse, never truncate
///
/// A month of one-second samples is millions of points and a chart has
/// hundreds of pixels. The tempting answer is to send the first N and stop,
/// and it is the wrong one: returning the first `maxPoints` samples respects
/// the count and truncates the chart to the first minute of the window, which
/// "draws a line that stops in mid-air", and the newest sample in particular
/// "is the one an operator reads as *now*"
/// (`data_services_contract.dart:196-199`). A truncated series is not a
/// smaller answer to the same question; it is a confident answer to a
/// different one, and the operator cannot tell.
///
/// ## And a refusal must never become a disconnect
///
/// The other tempting failure is to let the over-large answer through and have
/// the conflating send buffer evict the session with `4004`
/// (`CloseCodes.backpressureOverrun`). That reports "your query was too large"
/// as "you disconnected" — a query-too-large misread as backpressure, which is
/// the class of failure this project exists to prevent (10-CONTEXT amendment
/// 3). So this is an [Exception], not an `Error`: the handler catches it and
/// answers a named JSON-RPC refusal that names the limit, what was measured
/// and what to call instead.
///
/// ## Where it is raised and where it is mapped
///
/// Raised by 10-07's timeseries reader and 10-09's preference store, where the
/// size is known. Mapped to a wire error by 10-03's and 10-05's handlers,
/// where the wire is — the error *code* is chosen there and deliberately not
/// here, because this package holds no wire codes and a refusal that carried
/// one would have to know which method it was refusing.
library;

/// What was counted when a result was found too large.
///
/// Two ceilings, and a reader tracing a refusal has to know which one bit:
/// 2 678 400 bytes is nothing and 2 678 400 rows is a month of one-second
/// samples.
enum ResultSizeUnit {
  /// Rows the database would return — the pagination ceiling.
  rows,

  /// Bytes the encoded frame would occupy — the conflating send buffer's
  /// ceiling, the one a `4004` would otherwise be blamed for.
  bytes,
}

/// A result the gateway will not send, because sending it would be worse than
/// refusing.
///
/// Carries the limit, what was measured, which of the two [ResultSizeUnit]
/// ceilings that was, and the method that would answer the same question
/// within the limit — so the refusal is something an engineer acts on rather
/// than a dead end reported as a broken chart.
final class ResultTooLarge implements Exception {
  const ResultTooLarge._(
      this.limit, this.measured, this.unit, this.suggestion);

  /// The ceiling, in [unit].
  final int limit;

  /// What the answer would actually have been, in [unit]. Always above
  /// [limit] — the point of carrying it is that "how far over" is what tells
  /// an operator whether to narrow the window a little or a lot.
  final int measured;

  /// Which ceiling [limit] and [measured] are counted against.
  final ResultSizeUnit unit;

  /// The wire name of the method that would answer within the limit — a
  /// [DataServiceMethods] constant, e.g.
  /// `timeseries.queryTimeseriesDataDownsampled` for a window that is simply
  /// too long.
  final String suggestion;

  /// Too many rows.
  const ResultTooLarge.rows({
    required int limit,
    required int measured,
    required String suggestion,
  }) : this._(limit, measured, ResultSizeUnit.rows, suggestion);

  /// Too many bytes on the wire.
  const ResultTooLarge.bytes({
    required int limit,
    required int measured,
    required String suggestion,
  }) : this._(limit, measured, ResultSizeUnit.bytes, suggestion);

  /// The sentence the refusal travels as: what the limit is, what was asked
  /// for, and what to call instead.
  String get message =>
      'this query would answer $measured ${unit.name}, over the $limit '
      '${unit.name} limit. Narrow the window or call $suggestion — the answer '
      'is refused rather than truncated, because a series cut short reads as '
      'a series that stopped';

  @override
  String toString() => 'ResultTooLarge: $message';
}
