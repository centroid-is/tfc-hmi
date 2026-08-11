#include "flutter_window.h"

#include <windows.h>
#include <wtsapi32.h>

#include <cstdlib>
#include <iostream>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

// The GPU device-loss problem this file guards against is described in
// gpu_watchdog.h. Everything below is adapter: window messages and engine
// callbacks in, tfc::GpuWatchdog decisions out.
//
// Tunables, read once at startup:
//   CENTROID_GPU_WATCHDOG=0               disable the watchdog entirely
//   CENTROID_GPU_WATCHDOG_INTERVAL_MS=n   probe interval, default 5000

namespace {

// Timer id for the watchdog's WM_TIMER. Scoped to our window, so any value
// that does not collide with another timer on the same HWND will do.
constexpr UINT_PTR kWatchdogTimerId = 1;

std::optional<std::string> GetEnvVar(const char* name) {
  char* value = nullptr;
  size_t len = 0;
  if (_dupenv_s(&value, &len, name) != 0 || value == nullptr) {
    return std::nullopt;
  }
  std::string result(value);
  free(value);
  return result;
}

const char* CStrOrNull(const std::optional<std::string>& value) {
  return value.has_value() ? value->c_str() : nullptr;
}

tfc::GpuWatchdog::Config WatchdogConfigFromEnvironment() {
  tfc::GpuWatchdog::Config config;
  config.probe_interval_ms = tfc::ParseProbeIntervalMs(
      CStrOrNull(GetEnvVar("CENTROID_GPU_WATCHDOG_INTERVAL_MS")),
      config.probe_interval_ms);
  return config;
}

bool WatchdogEnabledFromEnvironment() {
  return tfc::ParseWatchdogEnabled(
      CStrOrNull(GetEnvVar("CENTROID_GPU_WATCHDOG")), true);
}

void LogWatchdog(const std::string& message) {
  std::cerr << "[gpu-watchdog] " << message << std::endl;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project),
      watchdog_(WatchdogConfigFromEnvironment()),
      watchdog_enabled_(WatchdogEnabledFromEnvironment()) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::CreateController() {
  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    flutter_controller_ = nullptr;
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The engine posts this back to the platform thread, so it is safe to touch
  // watchdog state from it. It doubles as the stock runner template's "show the
  // window once the first frame is ready" hook.
  flutter_controller_->engine()->SetNextFrameCallback(
      [this]() { this->OnFramePresented(); });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::DestroyController() {
  // Destroying the controller shuts the engine down, which takes egl::Manager
  // with it: eglTerminate() releases the lost D3D device so the next
  // eglInitialize() can create a healthy one.
  flutter_controller_ = nullptr;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  if (!CreateController()) {
    return false;
  }

  if (!watchdog_enabled_) {
    LogWatchdog("disabled via CENTROID_GPU_WATCHDOG");
    return true;
  }

  watchdog_hwnd_ = GetHandle();

  // Device loss usually — but not always — comes with one of these messages.
  // They only bring the next probe forward; the probe still decides whether
  // anything actually broke.
  if (::WTSRegisterSessionNotification(watchdog_hwnd_,
                                       NOTIFY_FOR_THIS_SESSION)) {
    session_notifications_registered_ = true;
  } else {
    // Not fatal: the periodic probe still catches the loss, just later.
    LogWatchdog("WTSRegisterSessionNotification failed (error " +
                std::to_string(::GetLastError()) +
                "); relying on the periodic probe only");
  }

  ApplyAction(watchdog_.OnStarted());
  return true;
}

void FlutterWindow::OnDestroy() {
  if (watchdog_hwnd_ != nullptr) {
    ::KillTimer(watchdog_hwnd_, kWatchdogTimerId);
    if (session_notifications_registered_) {
      ::WTSUnRegisterSessionNotification(watchdog_hwnd_);
      session_notifications_registered_ = false;
    }
    // Also guards against OnDestroy running twice: Win32Window::Destroy calls
    // it directly, and again via the WM_DESTROY it triggers.
    watchdog_hwnd_ = nullptr;
  }
  DestroyController();

  Win32Window::OnDestroy();
}

void FlutterWindow::ApplyAction(const tfc::GpuWatchdog::Action& action) {
  if (action.restart_engine) {
    LogWatchdog("renderer is not presenting frames (EGL context lost?) — "
                "restarting the Flutter engine, attempt " +
                std::to_string(watchdog_.recovery_attempts()));
    DestroyController();
    // Deliberately does not touch first_frame_shown_. If the window was already
    // shown it stays shown, and re-running Show() would undo an operator's
    // maximise. If the GPU was dead before the very first frame, the flag is
    // still false and the window has never appeared — then we do want the next
    // successful frame to show it.
    if (!CreateController()) {
      LogWatchdog("engine restart FAILED — will retry");
    }
    // CreateController's own ForceRedraw is the next probe; the watchdog
    // already accounted for that.
  }

  if (action.start_probe) {
    StartProbe();
  }

  // A null handle means the window is going away — SetTimer would silently
  // create an unowned timer that never routes a WM_TIMER back to us.
  if (action.set_timer_ms != 0 && watchdog_hwnd_ != nullptr) {
    ::SetTimer(watchdog_hwnd_, kWatchdogTimerId, action.set_timer_ms, nullptr);
  }
}

void FlutterWindow::StartProbe() {
  if (!flutter_controller_ || !flutter_controller_->engine()) {
    return;
  }
  // Re-arm: the callback is one-shot and was consumed by the previous frame.
  flutter_controller_->engine()->SetNextFrameCallback(
      [this]() { this->OnFramePresented(); });
  flutter_controller_->ForceRedraw();
}

void FlutterWindow::OnFramePresented() {
  int attempts_before = watchdog_.recovery_attempts();
  ApplyAction(watchdog_.OnFramePresented());
  if (attempts_before > 0) {
    LogWatchdog("renderer healthy again after " +
                std::to_string(attempts_before) + " recovery attempt(s)");
  }

  if (!first_frame_shown_) {
    first_frame_shown_ = true;
    this->Show();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Handled before Flutter sees it — the timer is ours by id, and nothing in
  // the engine should claim it.
  if (message == WM_TIMER && wparam == kWatchdogTimerId) {
    ApplyAction(watchdog_.OnTick());
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      // Null while the engine is being restarted; the fresh engine picks up
      // the current fonts on its own.
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;

    case WM_POWERBROADCAST:
      // Resuming from sleep is the classic way a VM's virtual GPU comes back
      // as a reset (or different) device.
      if (wparam == PBT_APMRESUMEAUTOMATIC || wparam == PBT_APMRESUMESUSPEND) {
        if (watchdog_enabled_ && flutter_controller_) {
          LogWatchdog("probing after power resume");
          ApplyAction(watchdog_.OnDeviceLossHint());
        }
      }
      break;

    case WM_DISPLAYCHANGE:
      if (watchdog_enabled_ && flutter_controller_) {
        LogWatchdog("probing after display change");
        ApplyAction(watchdog_.OnDeviceLossHint());
      }
      break;

    case WM_WTSSESSION_CHANGE:
      // Connecting or disconnecting an RDP session swaps the session's display
      // adapter, tearing down the D3D device ANGLE was rendering with.
      switch (wparam) {
        case WTS_CONSOLE_CONNECT:
        case WTS_CONSOLE_DISCONNECT:
        case WTS_REMOTE_CONNECT:
        case WTS_REMOTE_DISCONNECT:
        case WTS_SESSION_UNLOCK:
          if (watchdog_enabled_ && flutter_controller_) {
            LogWatchdog("probing after session change");
            ApplyAction(watchdog_.OnDeviceLossHint());
          }
          break;
        default:
          break;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
