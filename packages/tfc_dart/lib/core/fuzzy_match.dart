/// Fuzzy match: each character of [query] must appear in [text] in order,
/// but not necessarily consecutively. e.g. "tmp" matches "temperature".
bool fuzzyMatch(String text, String query) {
  int ti = 0;
  for (int qi = 0; qi < query.length; qi++) {
    final c = query.codeUnitAt(qi);
    while (ti < text.length && text.codeUnitAt(ti) != c) {
      ti++;
    }
    if (ti >= text.length) return false;
    ti++;
  }
  return true;
}

/// Relevance of [query] against [text]; higher is better, null means no match.
///
/// The query is split on whitespace and every word must match [text]
/// (so "up arrow" finds "arrow upward"). The score is the sum of the
/// per-word scores from [fuzzyScoreFields]'s tier ladder.
///
/// Both [text] and [query] are compared as-is — lowercase them first for
/// case-insensitive search (as [fuzzyFilter] does).
int? fuzzyScore(String text, String query) => fuzzyScoreFields([text], query);

/// Like [fuzzyScore], but each query word may match any of [fields]
/// (so "plc1 temp" finds an item whose alias matches "plc1" and whose
/// key matches "temp"). Null if any word matches no field.
///
/// Per-word scoring is tiered so that better kinds of match always beat
/// worse ones regardless of penalties: exact > prefix > word-boundary
/// substring > substring > in-order subsequence. Within a tier, earlier
/// and tighter matches in shorter fields score higher.
int? fuzzyScoreFields(List<String> fields, String query) {
  var total = 0;
  var start = 0;
  while (start < query.length) {
    while (start < query.length && query.codeUnitAt(start) == 0x20) {
      start++;
    }
    if (start >= query.length) break;
    var end = start;
    while (end < query.length && query.codeUnitAt(end) != 0x20) {
      end++;
    }
    final word = query.substring(start, end);
    start = end;
    int? best;
    for (final field in fields) {
      final s = _wordScore(field, word);
      if (s != null && (best == null || s > best)) best = s;
    }
    if (best == null) return null;
    total += best;
  }
  return total;
}

int? _wordScore(String text, String word) {
  if (word.isEmpty) return 0;
  if (word.length > text.length) return null;
  if (text == word) return 100000;
  // Ties within a tier: prefer matches nearer the start of shorter fields.
  final lenPenalty = _clamp(text.length - word.length, 1000);
  final idx = text.indexOf(word);
  if (idx >= 0) {
    final int base;
    if (idx == 0) {
      base = 90000; // prefix
    } else if (!_isWordChar(text.codeUnitAt(idx - 1))) {
      base = 80000; // substring starting at a word boundary
    } else {
      base = 70000; // substring anywhere
    }
    return base - _clamp(idx, 100) * 10 - lenPenalty;
  }
  // In-order subsequence; penalize by how spread out the matched
  // characters are and how far in they start.
  int ti = 0, first = -1, last = -1;
  for (int wi = 0; wi < word.length; wi++) {
    final c = word.codeUnitAt(wi);
    while (ti < text.length && text.codeUnitAt(ti) != c) {
      ti++;
    }
    if (ti >= text.length) return null;
    if (first < 0) first = ti;
    last = ti;
    ti++;
  }
  final gaps = (last - first + 1) - word.length;
  return 50000 - _clamp(gaps, 90) * 100 - _clamp(first, 100) * 10 - lenPenalty;
}

int _clamp(int v, int max) => v < 0 ? 0 : (v > max ? max : v);

bool _isWordChar(int c) =>
    (c >= 0x61 && c <= 0x7a) || // a-z
    (c >= 0x41 && c <= 0x5a) || // A-Z
    (c >= 0x30 && c <= 0x39); // 0-9

/// Filter a list by fuzzy-matching [query] against fields extracted by
/// [getFields], best matches first (ties keep the input order).
/// Returns all items in their original order if [query] is empty.
List<T> fuzzyFilter<T>(
    List<T> items, String query, List<String Function(T)> getFields) {
  if (query.isEmpty) return items;
  final q = query.toLowerCase();
  final scored = <(int, T)>[];
  for (final item in items) {
    final score = fuzzyScoreFields(
        [for (final f in getFields) f(item).toLowerCase()], q);
    if (score != null) scored.add((score, item));
  }
  return rankedItems(scored);
}

/// Stable sort of pre-scored `(score, item)` pairs, best first; returns
/// the items. For callers that compute scores themselves (e.g. over
/// pre-lowercased fields) but want the same ordering as [fuzzyFilter].
List<T> rankedItems<T>(List<(int, T)> scored) {
  final indexed = List.generate(scored.length, (i) => i);
  indexed.sort((a, b) {
    final byScore = scored[b].$1.compareTo(scored[a].$1);
    return byScore != 0 ? byScore : a.compareTo(b);
  });
  return [for (final i in indexed) scored[i].$2];
}
