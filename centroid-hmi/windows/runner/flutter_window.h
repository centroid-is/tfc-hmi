#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "gpu_device_probe.h"
#include "gpu_diagnosis.h"
#include "gpu_watchdog.h"
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
  };

  // The only place the watchdog is driven from. Swallows exceptions and
  // disables the watchdog rather than letting anything escape: this runs
  // inside a noexcept window procedure and inside the engine's frame
  // callback, where an escaping exception is std::terminate.
  void Dispatch(WatchdogEvent event);

  // Stop watching and cancel the tick timer.
  void DisableWatchdog();

  void ApplyAction(const tfc::GpuWatchdog::Action& action);

  // Gathers everything known about the loss and writes the report block. This
  // is the diagnosis the log has been missing -- see gpu_diagnosis.h.
  void ReportDeviceLoss();

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
  // GetDeviceRemovedReason() can be asked why the renderer died. ANGLE's own
  // device is unreachable inside flutter_windows.dll.
  tfc::GpuDeviceProbe device_probe_;

  // What preceded the loss, for the report. GetTickCount64 values; 0 means
  // "never happened".
  tfc::LossHint last_hint_ = tfc::LossHint::kNone;
  unsigned long long last_hint_tick_ = 0;
  unsigned long session_change_code_ = 0;
  unsigned long long start_tick_ = 0;
  unsigned long long last_frame_tick_ = 0;

  // Cached copy of the window handle for watchdog teardown. Win32Window clears
  // window_handle_ *before* dispatching WM_DESTROY to OnDestroy, so GetHandle()
  // is already null by the time we need to KillTimer and unregister.
  HWND watchdog_hwnd_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
