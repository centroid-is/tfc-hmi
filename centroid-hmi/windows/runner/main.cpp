#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdlib>
#include <iostream>
#include <string>

#include "crash_handler.h"
#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Logging for MSIX/release builds:
  //   CENTROID_STDOUT=1          → also opens a console window
  //   CENTROID_LOG_FILE=<path>   → overrides the default log file location
  //   CENTROID_LOG_ARCHIVES=<n>  → previous runs to keep (default 5)
  //
  // A log file is written unconditionally. This is a windowed app: with no
  // console attached and no file, everything on stdout/stderr — including the
  // crash records installed below — is discarded, which is exactly how a
  // crash ends up with nothing to go on.
  char* debug_env = nullptr;
  size_t debug_env_len = 0;
  _dupenv_s(&debug_env, &debug_env_len, "CENTROID_STDOUT");

  char* log_file_env = nullptr;
  size_t log_file_env_len = 0;
  _dupenv_s(&log_file_env, &log_file_env_len, "CENTROID_LOG_FILE");

  char* archives_env = nullptr;
  size_t archives_env_len = 0;
  _dupenv_s(&archives_env, &archives_env_len, "CENTROID_LOG_ARCHIVES");

  bool debug_mode = debug_env != nullptr &&
                    (strcmp(debug_env, "1") == 0 || strcmp(debug_env, "true") == 0);

  int max_archives = 5;
  if (archives_env != nullptr && archives_env[0] != '\0') {
    int parsed = atoi(archives_env);
    if (parsed >= 0) {
      max_archives = parsed;
    }
  }

  std::string log_path = (log_file_env != nullptr && log_file_env[0] != '\0')
                             ? std::string(log_file_env)
                             : DefaultLogPath();

  // A console, when asked for or when launched from a terminal. Done first so
  // the file redirect below wins for stdout/stderr.
  if (debug_mode) {
    if (!::AttachConsole(ATTACH_PARENT_PROCESS)) {
      CreateAndAttachConsole();
    } else {
      RedirectIOToConsole();
    }
  } else if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (!log_path.empty()) {
    // Rotate before opening: RedirectIOToFile truncates, and the previous
    // run's log is the one worth keeping after a crash.
    RotateLogs(log_path, max_archives);
    RedirectIOToFile(log_path.c_str());

    // Only now can crash records actually be written somewhere.
    tfc::InstallCrashHandlers(DirectoryOf(log_path));
    std::cerr << "[startup] logging to " << log_path << " (keeping "
              << max_archives << " previous runs)" << std::endl;
  }

  free(debug_env);
  free(log_file_env);
  free(archives_env);

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1920, 1080);
  if (!window.Create(L"hmi", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
