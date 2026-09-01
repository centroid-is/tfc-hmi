#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <atomic>
#include <memory>

#include "gpu_device_probe.h"
#include "gpu_diagnosis.h"
#include "gpu_watchdog.h"
#include "log_throttle.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // --- Flutter engine lifecycle -------------------------------------------
  //
  // Split out of OnCreate so the GPU watchdog can rebuild the engine without
  // tearing down the top-level window.

  // Builds a FlutterViewController and attaches its view as this window's
  // child content. Returns false if the engine failed to start.
  bool CreateController();

  // Tears the FlutterViewController down. This runs egl::Manager's destructor
  // inside the engine, which calls eglTerminate() and releases the D3D device.
  void DestroyController();

  // --- GPU watchdog adapter -----------------------------------------------
  //
  // All the decisions live in tfc::GpuWatchdog (unit tested); this class only
  // translates window messages and engine callbacks into watchdog events, and
  // carries out whatever the watchdog asks for.

  // The events the watchdog understands, so every one of them reaches it
  // through the single guarded path in Dispatch.
  enum class WatchdogEvent {
    kStarted,
    kTick,
    kFramePresented,
    kDeviceLossHint,
    kRendererLost,
  };

  // The only place the watchdog is driven from. Swallows exceptions and
  // disables the watchdog rather than letting anything escape: this runs
  // inside a noexcept window procedure and inside the engine's frame
  // callback, where an escaping exception is std::terminate.
  //
  // |cause| is used only by kRendererLost.
  void Dispatch(WatchdogEvent event,
                tfc::LossCause cause = tfc::LossCause::kNoFramesPresented);

  // Stop watching and cancel the tick timer.
  void DisableWatchdog(const std::string& why);

  void ApplyAction(const tfc::GpuWatchdog::Action& action);

  // --- The tick, and why it is not a WM_TIMER ------------------------------
  //
  // It used to be. WM_TIMER is the lowest-priority message in Windows:
  // GetMessage synthesises one only when nothing else is waiting in the
  // thread's queue. A lost EGL context makes the engine fail a frame in
  // microseconds and immediately schedule another, and each of those posts
  // work to the platform thread -- so the queue never drains and the timer
  // never fires. The watchdog was silenced by the exact condition it existed
  // to catch, which is how a station sat frozen for thirty-six minutes on an
  // exit-on-loss policy without exiting.
  //
  // The tick now comes from a timer-queue thread, which nothing in the message
  // queue can starve. It does not touch the engine or the watchdog: it sends
  // (not posts) kWatchdogTickMessage to the window and lets the platform
  // thread do the work, because FlutterViewController is not thread safe.
  // SENT messages are delivered ahead of the posted queue -- measured on the
  // frozen station, a WM_NULL round trip took 10 ms while the queue was
  // saturated -- so this reaches the platform thread when a posted message
  // would not.
  //
  // Runs on a thread-pool thread.
  static void CALLBACK WatchdogTimerThunk(void* context, BOOLEAN fired);
  void OnWatchdogTimerThread();

  bool StartWatchdogTimer(unsigned int period_ms);
  void SetWatchdogPeriod(unsigned int period_ms);
  void StopWatchdogTimer();

  // Ask the render device whether it is still alive, rather than inferring it
  // from missing frames. Returns true when it positively reports itself
  // removed. Runs on the platform thread.
  bool RenderDeviceIsLost();

  // Gathers everything known about the loss and writes the report block. This
  // is the diagnosis the log has been missing -- see gpu_diagnosis.h.
  void ReportDeviceLoss(tfc::LossCause cause, tfc::LossEscalation escalation);

  // Writes the report's last line, flushes the log, and ends the process
  // cleanly through the message loop so the report is the final thing in the
  // file rather than something a killed process left half-written.
  void ExitAfterDeviceLoss();

  // Remembers a window message that commonly precedes device loss, so the
  // report can say what came just before it. |session_code| is the WTS_* code
  // for a session change and ignored otherwise.
  void NoteLossHint(tfc::LossHint hint, unsigned long session_code);

  // Asks the engine for a frame and re-arms the next-frame callback.
  void StartProbe();

  // Invoked on the platform thread when the engine presents a frame.
  void OnFramePresented();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Watchdog state. Touched only on the platform thread.
  tfc::GpuWatchdog watchdog_;
  bool watchdog_enabled_ = true;
  bool first_frame_shown_ = false;
  bool session_notifications_registered_ = false;
  // Whether a next-frame callback is registered and still unanswered.
  //
  // The engine accepts a new registration every time it is asked, but the
  // client wrapper holds a single std::function behind them: its trampoline
  // calls that function and then nulls it, unguarded. A second pending
  // callback therefore invokes an empty std::function and throws
  // std::bad_function_call, ending the process. Probing while the renderer is
  // down is precisely how several come to be pending at once, so exactly one
  // is kept outstanding. See StartProbe.
  bool probe_armed_ = false;

  // A D3D11 device of our own, never rendered with, kept alive only so that
  // GetDeviceRemovedReason() can be asked why the renderer died.
  //
  // It is now a TRIGGER as well as evidence: the tick asks it every time, so
  // an adapter-wide loss (TDR, driver restart, adapter removed, VM GPU reset)
  // is declared the moment it happens rather than after two probe intervals of
  // no frames. It stays blind to a loss confined to ANGLE's own device -- see
  // the note in gpu_diagnosis.h on why that device cannot be reached -- and
  // for that class the frame probe remains the only detector.
  tfc::GpuDeviceProbe device_probe_;
  // Latches so the transition is logged once rather than every tick.
  bool sentinel_loss_logged_ = false;

  // --- Instrumentation ------------------------------------------------------
  //
  // "We need to have logs everywhere where it could be possible that the error
  // is." Every one of these is rate limited, because the incident that
  // prompted them put 9.7 MB into a log by repeating two lines, and
  // instrumentation that reproduces the fault it documents is not an
  // improvement. See log_throttle.h.
  tfc::LogThrottle tick_log_;
  tfc::LogThrottle frame_log_;
  tfc::LogThrottle hint_log_;
  tfc::LogThrottle send_failure_log_;
  tfc::LogThrottle timer_thread_log_;

  // What preceded the loss, for the report. GetTickCount64 values; 0 means
  // "never happened".
  tfc::LossHint last_hint_ = tfc::LossHint::kNone;
  unsigned long long last_hint_tick_ = 0;
  unsigned long session_change_code_ = 0;
  unsigned long long start_tick_ = 0;
  unsigned long long last_frame_tick_ = 0;

  // --- Cross-thread state ---------------------------------------------------
  //
  // Read by the timer-queue thread, written by the platform thread.

  // Cached copy of the window handle for watchdog teardown. Win32Window clears
  // window_handle_ *before* dispatching WM_DESTROY to OnDestroy, so GetHandle()
  // is already null by the time we need to unregister.
  std::atomic<HWND> watchdog_hwnd_{nullptr};

  // Set before the timer is deleted so a callback that is about to run bows
  // out instead of sending to a window that is going away.
  std::atomic<bool> watchdog_stopping_{false};

  // Consecutive sends that the platform thread did not answer. A platform
  // thread that will not take a SENT message is not merely busy, and after
  // enough of them the timer thread stops waiting for it.
  std::atomic<int> unanswered_sends_{0};

  HANDLE watchdog_timer_queue_ = nullptr;
  HANDLE watchdog_timer_ = nullptr;
  unsigned int watchdog_period_ms_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
