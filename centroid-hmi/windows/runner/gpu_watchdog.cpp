#include "gpu_watchdog.h"

#include <cstdlib>

namespace tfc {
namespace {

// Below a second the probe stops measuring anything useful and just competes
// with real frames.
constexpr unsigned int kMinProbeIntervalMs = 1000;

bool EqualsIgnoreCase(const char* a, const char* b) {
  for (; *a != '\0' && *b != '\0'; a++, b++) {
    char lhs = (*a >= 'A' && *a <= 'Z') ? static_cast<char>(*a + 32) : *a;
    char rhs = (*b >= 'A' && *b <= 'Z') ? static_cast<char>(*b + 32) : *b;
    if (lhs != rhs) {
      return false;
    }
  }
  return *a == *b;
}

}  // namespace

GpuWatchdog::GpuWatchdog() : GpuWatchdog(Config()) {}

GpuWatchdog::GpuWatchdog(Config config) : config_(config) {}

GpuWatchdog::Action GpuWatchdog::OnStarted() {
  Action action;
  if (disabled_) {
    return action;
  }
  probe_outstanding_ = true;
  action.start_probe = true;
  action.set_timer_ms = config_.probe_interval_ms;
  return action;
}

GpuWatchdog::Action GpuWatchdog::OnTick() {
  Action action;
  if (disabled_) {
    return action;
  }

  if (probe_outstanding_) {
    missed_probes_++;
    if (missed_probes_ >= config_.missed_probes_before_recovery) {
      // The renderer is dead. Say why, once per episode: repeating the report
      // every tick would recreate the very flood of noise it exists to
      // replace. reported_loss_ clears when a frame is presented again.
      if (!reported_loss_) {
        reported_loss_ = true;
        action.report_loss = true;
      }

      if (config_.on_loss == LossAction::kExitProcess) {
        // Nothing further to decide: the host writes the report and ends the
        // process. Disabling first means a tick that races the shutdown
        // cannot ask for a second exit.
        disabled_ = true;
        action.exit_process = true;
        return action;
      }

      if (config_.on_loss == LossAction::kLogOnly) {
        // Keep watching so the report's "frames resumed" counterpart can
        // still fire, but do not touch the engine. missed_probes_ is left
        // alone deliberately -- it is the stall length the report quotes.
        probe_outstanding_ = true;
        action.start_probe = true;
        return action;
      }

      recovery_attempts_++;
      missed_probes_ = 0;
      if (config_.max_recovery_attempts > 0 &&
          recovery_attempts_ >= config_.max_recovery_attempts) {
        // Hand back this last restart, then stop: one more attempt is worth
        // more than a tidy state machine, but an endless loop is not.
        disabled_ = true;
        action.restart_engine = true;
        return action;
      }
      // Recreating the controller issues its own ForceRedraw and arms the
      // next-frame callback, so the restart *is* the next probe. Leaving the
      // flag set means the following ticks judge the new engine.
      probe_outstanding_ = true;
      action.restart_engine = true;
      action.set_timer_ms = BackoffMs();
      return action;
    }
  }

  // Either nothing was outstanding, or we are still under the failure
  // threshold — keep asking, the renderer may come back on its own.
  probe_outstanding_ = true;
  action.start_probe = true;
  return action;
}

GpuWatchdog::Action GpuWatchdog::OnFramePresented() {
  Action action;
  if (disabled_) {
    return action;
  }
  probe_outstanding_ = false;
  missed_probes_ = 0;
  // A presented frame ends the episode, so the next loss reports again.
  reported_loss_ = false;

  if (recovery_attempts_ > 0) {
    // The engine we restarted is drawing again: drop the backoff.
    recovery_attempts_ = 0;
    action.set_timer_ms = config_.probe_interval_ms;
  }
  // Otherwise leave the timer alone. Re-arming it on every presented frame
  // would push the next tick out indefinitely on an animating page, and the
  // watchdog would never probe.

  return action;
}

GpuWatchdog::Action GpuWatchdog::OnDeviceLossHint() {
  Action action;
  if (disabled_) {
    return action;
  }
  // Deliberately does not touch missed_probes_: a flood of session-change
  // messages must not be able to hold the failure count at zero while frames
  // are actually missing.
  probe_outstanding_ = true;
  action.start_probe = true;
  action.set_timer_ms = config_.probe_interval_ms;
  return action;
}

void GpuWatchdog::Disable() {
  disabled_ = true;
  probe_outstanding_ = false;
}

unsigned int GpuWatchdog::BackoffMs() const {
  unsigned int backoff = config_.probe_interval_ms;
  for (int i = 1; i < recovery_attempts_; i++) {
    if (backoff >= config_.max_probe_interval_ms) {
      break;
    }
    backoff *= 2;
  }
  return backoff > config_.max_probe_interval_ms ? config_.max_probe_interval_ms
                                                 : backoff;
}

bool ParseWatchdogEnabled(const char* raw, bool fallback) {
  if (raw == nullptr || *raw == '\0') {
    return fallback;
  }
  const char* falsy[] = {"0", "false", "no", "off"};
  for (const char* candidate : falsy) {
    if (EqualsIgnoreCase(raw, candidate)) {
      return false;
    }
  }
  const char* truthy[] = {"1", "true", "yes", "on"};
  for (const char* candidate : truthy) {
    if (EqualsIgnoreCase(raw, candidate)) {
      return true;
    }
  }
  return fallback;
}

unsigned int ParseProbeIntervalMs(const char* raw, unsigned int fallback) {
  if (raw == nullptr || *raw == '\0') {
    return fallback;
  }
  char* end = nullptr;
  long parsed = std::strtol(raw, &end, 10);
  // Reject trailing garbage ("5000ms") as well as outright nonsense.
  if (end == raw || *end != '\0') {
    return fallback;
  }
  if (parsed < static_cast<long>(kMinProbeIntervalMs)) {
    return fallback;
  }
  return static_cast<unsigned int>(parsed);
}

}  // namespace tfc
