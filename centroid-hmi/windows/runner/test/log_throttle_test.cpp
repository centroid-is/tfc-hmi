// Tests for the rate limiter that keeps the watchdog's instrumentation from
// becoming the next incident.
//
// The incident it is sized against: a lost EGL context made the engine log two
// ERROR lines per failed frame for thirty-six minutes, and the app log reached
// 9.7 MB saying the same thing over and over. The runner's own diagnostics now
// cover far more of the path than they did, so every one of them is bounded
// before it is written.

#include "../log_throttle.h"

#include "test_harness.h"

namespace {

using tfc::LogThrottle;

LogThrottle::Config Loud() {
  LogThrottle::Config config;
  config.burst = 3;
  config.every_nth = 10;
  // Off, so the burst-and-sample behaviour can be tested without a clock.
  config.summary_interval_ms = 0;
  return config;
}

int EmittedOver(LogThrottle& throttle, int occurrences,
                unsigned long long start_ms, unsigned long long step_ms) {
  int emitted = 0;
  unsigned long long now = start_ms;
  for (int i = 0; i < occurrences; i++) {
    if (throttle.Record(now).emit) {
      emitted++;
    }
    now += step_ms;
  }
  return emitted;
}

}  // namespace

TEST(the_beginning_of_an_episode_is_printed_in_full) {
  // The first few occurrences are the ones worth reading: they carry the
  // timestamp the loss actually began at.
  LogThrottle throttle(Loud());

  for (int i = 0; i < 3; i++) {
    CHECK(throttle.Record(0).emit);
  }
  CHECK(!throttle.Record(0).emit);
}

TEST(after_the_burst_only_every_nth_is_printed) {
  LogThrottle throttle(Loud());

  // 3 burst + one in every 10 of the remaining 100.
  const int emitted = EmittedOver(throttle, 103, 0, 1);

  CHECK_EQ(emitted, 13);
}

TEST(a_flood_stays_bounded_by_a_constant_fraction) {
  // The property that matters: whatever the volume, the log grows by a fixed
  // proportion of it and never by all of it.
  LogThrottle throttle(Loud());

  const int emitted = EmittedOver(throttle, 100000, 0, 1);

  CHECK(emitted <= 10010);
  // ...and it does not go silent either, which would be the opposite failure:
  // a reader must be able to see that it is STILL happening.
  CHECK(emitted > 1000);
}

TEST(the_interval_caps_a_flood_that_arrives_faster_than_every_nth_can_hold) {
  // every_nth alone is not enough when the underlying event fires thousands of
  // times a second, which is exactly what a failing frame loop does. The
  // interval is the second bound.
  LogThrottle::Config config = Loud();
  config.summary_interval_ms = 1000;
  LogThrottle throttle(config);

  // 100,000 occurrences crammed into one second of wall clock.
  const int emitted = EmittedOver(throttle, 100000, 0, 0);

  // The burst, plus the one sampled line the interval lets through.
  CHECK(emitted <= 4);
  CHECK(emitted >= 3);
}

TEST(a_throttled_line_says_how_many_it_stands_for) {
  // A sampled line that looks like the only line is worse than no line: it
  // understates the fault. Every emitted line after the first carries the
  // count it is standing in for.
  LogThrottle throttle(Loud());

  for (int i = 0; i < 3; i++) {
    throttle.Record(0);
  }
  LogThrottle::Decision decision;
  for (int i = 0; i < 10; i++) {
    decision = throttle.Record(0);
  }

  CHECK(decision.emit);
  CHECK_EQ(decision.suppressed, 9ULL);
  CHECK_EQ(decision.total, 13ULL);
  CHECK(!LogThrottle::DescribeSuppression(decision).empty());
}

TEST(the_first_lines_of_a_burst_claim_nothing_they_did_not_swallow) {
  LogThrottle throttle(Loud());

  LogThrottle::Decision first = throttle.Record(0);

  CHECK(first.emit);
  CHECK_EQ(first.suppressed, 0ULL);
  CHECK(LogThrottle::DescribeSuppression(first).empty());
}

TEST(a_second_episode_is_as_loud_as_the_first) {
  // Reset is called when the condition demonstrably stopped -- a frame was
  // presented, the engine was rebuilt. Without it the second loss of the day
  // would inherit the first one's silence and go almost unlogged, which is the
  // occurrence someone is most likely to be investigating.
  LogThrottle throttle(Loud());
  EmittedOver(throttle, 1000, 0, 1);

  throttle.Reset();

  CHECK_EQ(throttle.total(), 0ULL);
  for (int i = 0; i < 3; i++) {
    CHECK(throttle.Record(0).emit);
  }
}

TEST(a_nonsensical_every_nth_prints_more_rather_than_dividing_by_zero) {
  // A throttle asked for nonsense must fail towards noise. The alternative
  // here is a modulo by zero, which takes the process with it -- and this code
  // exists to keep a process alive.
  LogThrottle::Config config;
  config.burst = 0;
  config.every_nth = 0;
  config.summary_interval_ms = 0;
  LogThrottle throttle(config);

  CHECK_EQ(EmittedOver(throttle, 10, 0, 1), 10);
}

TEST(a_slow_repeating_condition_is_never_silenced_by_the_interval) {
  // Something that happens once a minute for an hour must produce sixty lines,
  // not five: it is inside the burst-and-sample budget and the interval is a
  // floor on frequency, not a quota.
  LogThrottle::Config config;
  config.burst = 3;
  config.every_nth = 1;
  config.summary_interval_ms = 60000;
  LogThrottle throttle(config);

  const int emitted = EmittedOver(throttle, 60, 0, 60000);

  CHECK_EQ(emitted, 60);
}

int main() {
  std::printf("log_throttle_test\n");
  return tfc_test::RunAll();
}
