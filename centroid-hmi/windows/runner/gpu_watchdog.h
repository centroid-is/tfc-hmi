#ifndef RUNNER_GPU_WATCHDOG_H_
#define RUNNER_GPU_WATCHDOG_H_

#include "gpu_diagnosis.h"

// GPU device-loss watchdog.
//
// The problem, as it appears in the logs:
//
//   [ERROR:...egl/egl.cc(57)] EGL Error: Context Lost (12302) in .../context.cc
//   [ERROR:...gpu_surface_gl_skia.cc(220)] Could not make the context current
//                                          to acquire the frame.
//
// repeating forever, with the process alive but the window frozen on its last
// frame. It means the D3D11 device ANGLE renders through was destroyed under
// it. In a VM that happens when the host sleeps and the virtual GPU resets,
// when an RDP session connects or disconnects and Windows swaps the session's
// display adapter, or when the graphics driver resets (TDR).
//
// Recovering requires rebuilding the EGL display, context and surface plus
// Skia's GrDirectContext. The Flutter Windows embedder does not do that — it
// retries eglMakeCurrent every frame and fails every frame. Those sources ship
// as a prebuilt flutter_windows.dll, so we cannot fix it there without forking
// the engine. What the runner *can* do is destroy and recreate
// FlutterViewController: that runs egl::Manager's destructor (eglTerminate,
// releasing the dead device) and then its constructor (eglInitialize, creating
// a fresh one). The Dart VM restarts with it, so the app reboots — which for a
// 24/7 HMI beats a permanently frozen screen.
//
// This class owns only the decision: is the renderer dead, and what should the
// host do about it. It is deliberately free of Win32 and Flutter types so the
// decision can be unit tested without a GPU — see test/gpu_watchdog_test.cpp.
// FlutterWindow is the adapter that feeds it events and executes its actions.
//
// Detection works by probing: ask the engine for a frame (ForceRedraw) and arm
// the next-frame callback, which only fires once a frame has actually been
// presented. Consecutive unanswered probes mean the renderer is gone.

namespace tfc {

class GpuWatchdog {
 public:
  struct Config {
    // How often to probe, and how long an unanswered probe is given.
    unsigned int probe_interval_ms = 5000;

    // Consecutive unanswered probes before the renderer is judged dead. At the
    // default interval that is ~10s of no presented frame: long enough not to
    // trip on one slow frame, short enough that an operator is not left
    // staring at a stale screen.
    int missed_probes_before_recovery = 2;

    // Ceiling for the post-recovery backoff, so a GPU that never comes back is
    // retried slowly instead of rebooting the engine every few seconds.
    unsigned int max_probe_interval_ms = 60000;

    // What to do once the renderer is judged dead. The diagnosis in
    // gpu_diagnosis.h is written either way; this is only about what happens
    // after it. See CENTROID_GPU_ON_LOSS in flutter_window.cpp.
    LossAction on_loss = LossAction::kExitProcess;

    // Consecutive failed recoveries before the watchdog gives up for good.
    // Restarting the engine restarts the Dart app with it, so a GPU that is
    // never coming back would otherwise wipe the operator's UI on every
    // backoff interval, forever. 0 means never give up.
    int max_recovery_attempts = 5;
  };

  // What the host should do in response to an event.
  struct Action {
    // Call ForceRedraw and re-arm the next-frame callback.
    bool start_probe = false;

    // Gather the evidence and write the device-loss report. Set once per
    // episode, not once per tick: the whole point is to replace a flood of
    // engine errors with one block that says why.
    bool report_loss = false;

    // End the process, after the report has been written and flushed.
    bool exit_process = false;

    // Destroy and recreate the FlutterViewController.
    bool restart_engine = false;

    // Re-arm the tick timer with this period. 0 means "leave it alone".
    unsigned int set_timer_ms = 0;
  };

  // Two overloads rather than a defaulted argument: `Config()` cannot be named
  // as a default argument inside the class that encloses Config.
  GpuWatchdog();
  explicit GpuWatchdog(Config config);

  // The engine is up; begin watching.
  Action OnStarted();

  // The tick timer fired: judge the outstanding probe, then start a new one.
  Action OnTick();

  // The engine presented a frame — the only positive proof of a live renderer.
  Action OnFramePresented();

  // A window message arrived that commonly accompanies device loss (power
  // resume, display change, session change). This only brings the next probe
  // forward; the probe still decides whether anything actually broke, so a
  // benign resolution change cannot reboot the engine on its own.
  Action OnDeviceLossHint();

  // Stop watching, permanently. The host calls this when carrying out an
  // action threw: the window procedure that drives the watchdog is noexcept,
  // so an exception escaping it aborts the process. Failing safe here costs
  // the recovery feature and leaves the app exactly as it behaved before the
  // watchdog existed.
  void Disable();

  // True once the watchdog has stopped acting, whether from Disable() or from
  // exhausting max_recovery_attempts.
  bool has_given_up() const { return disabled_; }

  // True once this loss episode has been reported, so kLogOnly does not write
  // the same block on every tick. Cleared when a frame is presented again.
  bool has_reported_loss() const { return reported_loss_; }

  // The resolved CENTROID_GPU_ON_LOSS, so the host can name it in the log
  // without re-reading the environment.
  LossAction on_loss() const { return config_.on_loss; }

  int missed_probes() const { return missed_probes_; }
  int recovery_attempts() const { return recovery_attempts_; }
  bool probe_outstanding() const { return probe_outstanding_; }

 private:
  // Period to wait before judging the engine we just restarted.
  unsigned int BackoffMs() const;

  Config config_;
  bool disabled_ = false;
  bool probe_outstanding_ = false;
  bool reported_loss_ = false;
  int missed_probes_ = 0;
  int recovery_attempts_ = 0;
};

// Parses CENTROID_GPU_WATCHDOG. Returns |fallback| when unset or unrecognised.
bool ParseWatchdogEnabled(const char* raw, bool fallback);

// Parses CENTROID_GPU_WATCHDOG_INTERVAL_MS. Returns |fallback| when unset,
// malformed, or below the one-second floor.
unsigned int ParseProbeIntervalMs(const char* raw, unsigned int fallback);

}  // namespace tfc

#endif  // RUNNER_GPU_WATCHDOG_H_
