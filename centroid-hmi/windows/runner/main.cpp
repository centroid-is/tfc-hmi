#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdlib>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Debug logging for MSIX/release builds:
  //   CENTROID_STDOUT=1          → opens a console window with all output
  //   CENTROID_LOG_FILE=<path>   → writes all output to a file
  char* debug_env = nullptr;
  size_t debug_env_len = 0;
  _dupenv_s(&debug_env, &debug_env_len, "CENTROID_STDOUT");

  char* log_file_env = nullptr;
  size_t log_file_env_len = 0;
  _dupenv_s(&log_file_env, &log_file_env_len, "CENTROID_LOG_FILE");

  bool debug_mode = debug_env != nullptr &&
                    (strcmp(debug_env, "1") == 0 || strcmp(debug_env, "true") == 0);

  if (log_file_env != nullptr && log_file_env[0] != '\0') {
    RedirectIOToFile(log_file_env);
  } else if (debug_mode) {
    if (!::AttachConsole(ATTACH_PARENT_PROCESS)) {
      CreateAndAttachConsole();
    } else {
      RedirectIOToConsole();
    }
  } else {
    // Normal mode: console only from terminal or under debugger
    if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
      CreateAndAttachConsole();
    }
  }

  free(debug_env);
  free(log_file_env);

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
