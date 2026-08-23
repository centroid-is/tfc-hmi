/// A clock the test moves by hand.
///
/// Anything measured as the difference between two clock reads -- uptime, a
/// rolling throughput window -- can then be asserted exactly instead of being
/// slept for and compared with a tolerance. That matters on Windows, where the
/// system clock advances in ~15.6ms steps: two reads inside the same tick are
/// equal, so "assert some time has passed" is a coin flip unless the test
/// sleeps long enough to be slow.
class TestClock {
  DateTime _now = DateTime.utc(2026, 1, 1);

  /// The current time. Pass as `now: clock.now`.
  DateTime now() => _now;

  /// Move the clock forward.
  void advance(Duration d) => _now = _now.add(d);
}
