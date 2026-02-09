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

/// Filter a list by fuzzy-matching [query] against fields extracted by [getFields].
/// Returns all items if [query] is empty.
List<T> fuzzyFilter<T>(
    List<T> items, String query, List<String Function(T)> getFields) {
  if (query.isEmpty) return items;
  final q = query.toLowerCase();
  return items
      .where((item) => getFields.any((f) => fuzzyMatch(f(item).toLowerCase(), q)))
      .toList();
}
