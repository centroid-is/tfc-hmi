/// Non-finite sanitization — the F28 / forum-survey rule.
///
/// Dart's jsonEncode THROWS on NaN and ±Infinity (it does not emit null the
/// way JavaScript does), so one open-circuit 4–20 mA input or a
/// divide-by-zero in a weigher rate calculation would fail the entire batch
/// for every client. And `1e999` silently *decodes* to Infinity, so poison
/// values can enter from outside too. Every value crosses [sanitize] before
/// it is placed in a frame.
library;

/// Result of sanitizing one value tree.
typedef SanitizeResult = ({Object? value, bool hadNonFinite});

/// Returns [value] with every non-finite double replaced by `null`,
/// reporting whether any replacement happened (so the caller can attach
/// [Quality.badNonFinite]). Finite values pass through untouched; lists and
/// maps are rebuilt only if they contain an offender.
SanitizeResult sanitize(Object? value) {
  var hadNonFinite = false;

  Object? walk(Object? v) {
    if (v is double && !v.isFinite) {
      hadNonFinite = true;
      return null;
    }
    if (v is List) {
      List<Object?>? copy;
      for (var i = 0; i < v.length; i++) {
        final w = walk(v[i]);
        if (!identical(w, v[i])) {
          copy ??= List<Object?>.of(v);
        }
        if (copy != null) copy[i] = w;
      }
      return copy ?? v;
    }
    if (v is Map) {
      Map<String, Object?>? copy;
      for (final entry in v.entries) {
        final w = walk(entry.value);
        if (!identical(w, entry.value)) {
          copy ??= Map<String, Object?>.of(v.cast<String, Object?>());
        }
        if (copy != null) copy[entry.key as String] = w;
      }
      return copy ?? v;
    }
    return v;
  }

  final sanitized = walk(value);
  return (value: sanitized, hadNonFinite: hadNonFinite);
}
