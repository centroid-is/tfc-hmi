#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

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

  // Cached copy of the window handle for watchdog teardown. Win32Window clears
  // window_handle_ *before* dispatching WM_DESTROY to OnDestroy, so GetHandle()
  // is already null by the time we need to KillTimer and unregister.
  HWND watchdog_hwnd_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
