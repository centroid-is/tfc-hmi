// Tests for the GPU device-loss watchdog state machine.
//
// The watchdog decides *whether* the renderer is dead and *what* to do about
// it. It deliberately knows nothing about Win32 or Flutter so that the whole
// decision can be exercised here, on any platform, without a GPU — the failure
// it guards against (a VM resuming from host sleep, an RDP session swapping the
// display adapter) is not something a test can stage for real.

#include "../gpu_watchdog.h"

#include "test_harness.h"

namespace {

using tfc::GpuWatchdog;

GpuWatchdog::Config TestConfig() {
  GpuWatchdog::Config config;
  config.probe_interval_ms = 5000;
  config.missed_probes_before_recovery = 2;
  config.max_probe_interval_ms = 60000;
  return config;
}

}  // namespace

// --- Steady state -----------------------------------------------------------

TEST(started_arms_the_timer_and_probes_immediately) {
  GpuWatchdog watchdog(TestConfig());

  GpuWatchdog::Action action = watchdog.OnStarted();

  CHECK(action.start_probe);
  CHECK(!action.restart_engine);
  CHECK_EQ(action.set_timer_ms, 5000u);
}

TEST(tick_starts_a_probe_when_none_is_outstanding) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();
  watchdog.OnFramePresented();

  GpuWatchdog::Action action = watchdog.OnTick();

  CHECK(action.start_probe);
  CHECK(!action.restart_engine);
}

TEST(a_presented_frame_clears_the_outstanding_probe) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();
  CHECK(watchdog.probe_outstanding());

  watchdog.OnFramePresented();

  // A presented frame is the only positive proof that the renderer is alive.
  // If it does not clear the flag, every subsequent tick counts a phantom
  // miss and a perfectly healthy app drifts towards a restart.
  CHECK(!watchdog.probe_outstanding());
}

TEST(an_answered_probe_never_counts_as_missed) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();
  watchdog.OnFramePresented();

  for (int i = 0; i < 100; i++) {
    GpuWatchdog::Action action = watchdog.OnTick();
    CHECK(!action.restart_engine);
    // Checked every iteration, not just at the end: a miss that is counted on
    // the tick and cleared by the following frame would be invisible from
    // outside the loop, but it is exactly the bookkeeping bug that would make
    // the watchdog restart a healthy engine under a slower frame cadence.
    CHECK_EQ(watchdog.missed_probes(), 0);
    watchdog.OnFramePresented();
  }

  CHECK_EQ(watchdog.missed_probes(), 0);
  CHECK_EQ(watchdog.recovery_attempts(), 0);
}

// --- Detecting a dead renderer ---------------------------------------------

TEST(one_unanswered_probe_is_not_enough_to_restart) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();  // probe outstanding, no frame answers it

  GpuWatchdog::Action action = watchdog.OnTick();

  CHECK_EQ(watchdog.missed_probes(), 1);
  CHECK(!action.restart_engine);
  // Keep asking — the renderer may still come back on its own.
  CHECK(action.start_probe);
}

TEST(restarts_the_engine_after_the_configured_number_of_missed_probes) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();

  CHECK(!watchdog.OnTick().restart_engine);      // missed 1
  GpuWatchdog::Action action = watchdog.OnTick();  // missed 2 -> recover

  CHECK(action.restart_engine);
  CHECK_EQ(watchdog.recovery_attempts(), 1);
}

TEST(a_frame_arriving_late_cancels_the_pending_recovery) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();

  watchdog.OnTick();          // missed 1
  watchdog.OnFramePresented();  // renderer recovered on its own

  CHECK_EQ(watchdog.missed_probes(), 0);
  CHECK(!watchdog.OnTick().restart_engine);
  CHECK_EQ(watchdog.recovery_attempts(), 0);
}

TEST(restart_treats_the_new_engine_as_probed_and_re_arms_the_count) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();
  watchdog.OnTick();
  CHECK(watchdog.OnTick().restart_engine);

  // Recreating the controller issues its own ForceRedraw, so the restart
  // itself counts as the next probe rather than needing a separate one.
  CHECK(watchdog.probe_outstanding());
  CHECK_EQ(watchdog.missed_probes(), 0);

  // A second restart must take another full round of missed probes.
  CHECK(!watchdog.OnTick().restart_engine);
  CHECK(watchdog.OnTick().restart_engine);
  CHECK_EQ(watchdog.recovery_attempts(), 2);
}

// --- Backoff ----------------------------------------------------------------

TEST(recovery_backs_off_geometrically_and_caps) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();

  const unsigned int expected[] = {5000, 10000, 20000, 40000, 60000, 60000};
  for (unsigned int want : expected) {
    GpuWatchdog::Action action;
    do {
      action = watchdog.OnTick();
    } while (!action.restart_engine);
    CHECK_EQ(action.set_timer_ms, want);
  }
}

TEST(a_healthy_frame_after_recovery_restores_the_base_interval) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();
  watchdog.OnTick();
  CHECK(watchdog.OnTick().restart_engine);
  CHECK_EQ(watchdog.recovery_attempts(), 1);

  GpuWatchdog::Action action = watchdog.OnFramePresented();

  CHECK_EQ(watchdog.recovery_attempts(), 0);
  CHECK_EQ(action.set_timer_ms, 5000u);
}

TEST(a_healthy_frame_in_steady_state_does_not_touch_the_timer) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();

  GpuWatchdog::Action action = watchdog.OnFramePresented();

  // 0 means "leave the timer alone" — re-arming it on every presented frame
  // would push the next tick out indefinitely on an animating page and the
  // watchdog would never probe.
  CHECK_EQ(action.set_timer_ms, 0u);
}

// --- Device-loss hints from window messages --------------------------------

TEST(a_hint_probes_immediately_and_restarts_the_interval) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();
  watchdog.OnFramePresented();

  GpuWatchdog::Action action = watchdog.OnDeviceLossHint();

  CHECK(action.start_probe);
  CHECK(!action.restart_engine);
  CHECK_EQ(action.set_timer_ms, 5000u);
}

TEST(a_hint_alone_never_restarts_the_engine) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();
  watchdog.OnFramePresented();

  // WM_DISPLAYCHANGE fires for benign things like a resolution change. The
  // probe, not the message, decides whether anything actually broke.
  for (int i = 0; i < 50; i++) {
    CHECK(!watchdog.OnDeviceLossHint().restart_engine);
    watchdog.OnFramePresented();
  }
  CHECK_EQ(watchdog.recovery_attempts(), 0);
}

TEST(a_hint_does_not_reset_an_in_progress_failure_count) {
  GpuWatchdog watchdog(TestConfig());
  watchdog.OnStarted();
  watchdog.OnTick();  // missed 1

  watchdog.OnDeviceLossHint();

  // A hint arriving while frames are already missing must not let a flood of
  // session-change messages hold the failure count at zero forever.
  CHECK_EQ(watchdog.missed_probes(), 1);
  CHECK(watchdog.OnTick().restart_engine);
}

// --- Config parsing ---------------------------------------------------------

TEST(watchdog_is_enabled_unless_explicitly_switched_off) {
  CHECK(tfc::ParseWatchdogEnabled(nullptr, true));
  CHECK(tfc::ParseWatchdogEnabled("1", true));
  CHECK(tfc::ParseWatchdogEnabled("yes", true));
  CHECK(!tfc::ParseWatchdogEnabled("0", true));
  CHECK(!tfc::ParseWatchdogEnabled("false", true));
}

TEST(probe_interval_falls_back_when_absent_or_nonsensical) {
  CHECK_EQ(tfc::ParseProbeIntervalMs(nullptr, 5000), 5000u);
  CHECK_EQ(tfc::ParseProbeIntervalMs("", 5000), 5000u);
  CHECK_EQ(tfc::ParseProbeIntervalMs("banana", 5000), 5000u);
  CHECK_EQ(tfc::ParseProbeIntervalMs("-1", 5000), 5000u);
  // Below a second the probe just competes with real frames for no benefit.
  CHECK_EQ(tfc::ParseProbeIntervalMs("250", 5000), 5000u);
  CHECK_EQ(tfc::ParseProbeIntervalMs("1000", 5000), 1000u);
  CHECK_EQ(tfc::ParseProbeIntervalMs("30000", 5000), 30000u);
}

int main() {
  std::printf("gpu_watchdog_test\n");
  return tfc_test::RunAll();
}
