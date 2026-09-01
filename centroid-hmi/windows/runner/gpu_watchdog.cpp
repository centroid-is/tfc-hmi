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

GpuWatchdog::Action GpuWatchdog::OnStarted(unsigned long long now_ms) {
  (void)now_ms;
  Action action;
  if (disabled_) {
    return action;
  }
  probe_outstanding_ = true;
  action.start_probe = true;
  action.set_timer_ms = config_.probe_interval_ms;
  return action;
}

GpuWatchdog::Action GpuWatchdog::OnTick(unsigned long long now_ms) {
  Action action;
  if (disabled_) {
    return action;
  }

  if (probe_outstanding_) {
    missed_probes_++;
    if (missed_probes_ >= config_.missed_probes_before_recovery) {
      return DeclareLoss(LossCause::kNoFramesPresented, now_ms);
    }
  }

  // Either nothing was outstanding, or we are still under the failure
  // threshold -- keep asking, the renderer may come back on its own.
  probe_outstanding_ = true;
  action.start_probe = true;
  return action;
}

GpuWatchdog::Action GpuWatchdog::OnRendererLost(LossCause cause,
                                                unsigned long long now_ms) {
  Action action;
  if (disabled_) {
    return action;
  }
  // No probe accounting on this route on purpose. The caller did not fail to
  // observe a frame; it observed the device saying it is gone. Making that
  // wait out two probe intervals to agree with the slower test would be
  // deferring to the weaker evidence.
  //
  // It does still have to be idempotent: the host asks the device on every
  // tick, so a loss that is not acted on immediately (kLogOnly) arrives here
  // again and again. DeclareLoss's reported_loss_ latch is what keeps that to
  // one report per episode.
  return DeclareLoss(cause, now_ms);
}

GpuWatchdog::Action GpuWatchdog::DeclareLoss(LossCause cause,
                                             unsigned long long now_ms) {
  Action action;
  action.cause = cause;

  // The renderer is dead. Say why, once per episode: repeating the report
  // every tick would recreate the very flood of noise it exists to replace.
  // reported_loss_ clears when a frame is presented again.
  const bool new_episode = !reported_loss_;
  if (new_episode) {
    reported_loss_ = true;
    action.report_loss = true;

    // Count the episode against the loop guard. Only new episodes count: a
    // kLogOnly run re-enters here on every tick of the same freeze, and one
    // freeze must not look like a thousand.
    if (!window_open_ ||
        (config_.loss_window_ms != 0 &&
         now_ms - loss_window_start_ms_ > config_.loss_window_ms)) {
      window_open_ = true;
      loss_window_start_ms_ = now_ms;
      losses_in_window_ = 1;
    } else {
      losses_in_window_++;
    }
  }

  // --- Escalation -------------------------------------------------------
  //
  // Both guards turn "recover in place" into "exit". Checked before the
  // configured action so that a station left on the default policy still ends
  // up somewhere a supervisor can act, rather than thrashing until someone
  // walks over to it.
  const bool thrashing = config_.max_losses_in_window > 0 &&
                         losses_in_window_ > config_.max_losses_in_window;
  const bool recovery_exhausted =
      config_.max_recovery_attempts > 0 &&
      recovery_attempts_ >= config_.max_recovery_attempts;

  if (config_.on_loss == LossAction::kRestartEngine &&
      (thrashing || recovery_exhausted)) {
    action.escalation = thrashing ? LossEscalation::kRepeatedLosses
                                  : LossEscalation::kRecoveryExhausted;
    // Disabling first means a tick that races the shutdown cannot ask for a
    // second exit.
    disabled_ = true;
    action.exit_process = true;
    return action;
  }

  if (config_.on_loss == LossAction::kExitProcess) {
    // Nothing further to decide: the host writes the report and ends the
    // process.
    disabled_ = true;
    action.exit_process = true;
    return action;
  }

  if (config_.on_loss == LossAction::kLogOnly) {
    // Keep watching so the report's "frames resumed" counterpart can still
    // fire, but do not touch the engine. missed_probes_ is left alone
    // deliberately -- it is the stall length the report quotes.
    probe_outstanding_ = true;
    action.start_probe = true;
    return action;
  }

  recovery_attempts_++;
  missed_probes_ = 0;
  // Recreating the controller issues its own ForceRedraw and arms the
  // next-frame callback, so the restart *is* the next probe. Leaving the flag
  // set means the following ticks judge the new engine.
  probe_outstanding_ = true;
  action.restart_engine = true;
  action.set_timer_ms = BackoffMs();
  return action;
}

GpuWatchdog::Action GpuWatchdog::OnFramePresented(unsigned long long now_ms) {
  (void)now_ms;
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

GpuWatchdog::Action GpuWatchdog::OnDeviceLossHint(unsigned long long now_ms) {
  (void)now_ms;
  Action action;
  if (disabled_) {
    return action;
  }
  // Deliberately does not touch missed_probes_: a flood of session-change
  // messages must not be able to hold the failure count at zero while frames
  // are actually missing.
  //
  // It also deliberately does NOT re-arm the timer any more. SetTimer on an
  // existing id restarts its countdown, so the old "bring the next probe
  // forward" was in fact "push the next tick out by a full interval, once per
  // message" -- and an RDP reconnect delivers these in bursts. The probe still
  // happens immediately; the judging tick now keeps its own cadence.
  probe_outstanding_ = true;
  action.start_probe = true;
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
