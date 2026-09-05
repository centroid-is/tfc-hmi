import 'dynamic_value.dart';
import 'quality.dart';
import 'sanitize.dart';

/// A value on the wire: `{"v": …}` with optional `"q"` (quality, omitted
/// when good) and `"t"` (source timestamp, UTC epoch ms, omitted in slim
/// pushes where the batch timestamp applies).
///
/// Construction goes through [WireValue.of], which sanitizes non-finite
/// doubles — there is deliberately no way to build a WireValue that
/// jsonEncode would throw on.
final class WireValue {
  final Object? v;
  final Quality q;
  final int? t;

  const WireValue._(this.v, this.q, this.t);

  /// Sanitizing constructor: non-finite doubles anywhere in [value] become
  /// null and force quality to [Quality.badNonFinite] (worst-wins with
  /// [quality]).
  factory WireValue.of(Object? value,
      {Quality quality = Quality.good, int? t}) {
    final s = sanitize(value);
    final q = s.hadNonFinite
        ? Quality.worst([quality, Quality.badNonFinite])
        : quality;
    return WireValue._(s.value, q, t);
  }

  factory WireValue.fromJson(Map<String, Object?> json) {
    // Re-sanitize on decode: `1e999` in incoming JSON silently parses to
    // Infinity and would detonate on the next encode.
    final t = json['t'];
    return WireValue.of(
      json['v'],
      quality: Quality.fromWire(json['q']),
      // `isFinite` before `toInt()`: a `1e999` timestamp decodes to Infinity,
      // on which toInt() throws.
      t: t is num && t.isFinite ? t.toInt() : null,
    );
  }

  /// This value as the store type the rest of the client speaks.
  ///
  /// **The [t] half is the reason this exists.** Every decode site on the
  /// client used to build `DynamicValue(value: v, quality: q)` by hand and drop
  /// the timestamp on the floor, at three separate places — the subscribe
  /// snapshot, the update push and the `readFresh`/`readMany` answers. A value
  /// whose source time is gone cannot be aged by anything downstream: staleness
  /// stops being computable at the panel, `readFresh` cannot be shown to be
  /// newer than the cache it was called to bypass, and the freshness badge the
  /// operator reads becomes a property of when the frame arrived rather than of
  /// when the plant measured it.
  ///
  /// UTC on the way out, because [t] is epoch milliseconds and a local-time
  /// `DateTime` here would put the panel's timezone into a comparison against
  /// a timestamp the gateway stamped in UTC.
  DynamicValue toDynamicValue() => DynamicValue(
        value: v,
        quality: q,
        sourceTime:
            t == null ? null : DateTime.fromMillisecondsSinceEpoch(t!, isUtc: true),
      );

  Map<String, Object?> toJson() => {
        'v': v,
        if (q != Quality.good) 'q': q.code,
        if (t != null) 't': t,
      };

  @override
  bool operator ==(Object other) =>
      other is WireValue && other.v == v && other.q == q && other.t == t;

  @override
  int get hashCode => Object.hash(v, q, t);

  @override
  String toString() => 'WireValue(v: $v, q: ${q.code}${t == null ? '' : ', t: $t'})';
}
