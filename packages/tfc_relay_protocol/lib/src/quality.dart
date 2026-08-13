/// Four-band quality code carried with every value.
///
/// Band layout follows Ignition's proven model (good 0–255, uncertain
/// 256–511, bad 512–767, error 768–1023); the specific subcode numbers are
/// provisional until the open decision on mapping to OPC UA StatusCodes is
/// settled. The two states that must stay distinct:
/// [uncertainLastKnown] (holding the last known value — pipe may be fine)
/// vs [badStale] (past the freshness deadline — do not trust the number).
extension type const Quality(int code) {
  static const good = Quality(192);

  /// Write accepted, readback not yet observed (the in-flight window an
  /// operator must be able to see).
  static const goodWritePending = Quality(2);

  /// Current value unavailable; this is the last known value.
  static const uncertainLastKnown = Quality(257);

  /// Out-of-date past the requested freshness deadline.
  static const badStale = Quality(516);

  /// Upstream device link is down.
  static const badCommFault = Quality(522);

  /// Source produced NaN/±Infinity; the value field is null (JSON cannot
  /// carry it and Dart's jsonEncode throws — sanitized at the OPC UA
  /// boundary, see Sanitize).
  static const badNonFinite = Quality(524);

  /// Source bytes were not valid in the configured string encoding;
  /// replacement characters were substituted.
  static const uncertainEncoding = Quality(260);

  /// The key no longer exists upstream (tag deleted / renamed): a
  /// configuration error, not a transient — waiting will not fix it.
  static const errorConfig = Quality(770);

  bool get isGood => code >= 0 && code < 256;
  bool get isUncertain => code >= 256 && code < 512;
  bool get isBad => code >= 512 && code < 768;
  bool get isError => code >= 768;

  /// Band severity for worst-wins composition (higher is worse).
  int get band => code >> 8;

  /// Worst-quality-wins: a derived value can never look healthier than its
  /// worst input.
  static Quality worst(Iterable<Quality> qualities) {
    var result = good;
    for (final q in qualities) {
      if (q.band > result.band) result = q;
    }
    return result;
  }
}
