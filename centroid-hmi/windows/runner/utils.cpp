#include "utils.h"

#include <flutter_windows.h>
#include <fcntl.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>
#include <vector>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

void RedirectIOToConsole() {
  FILE *fp;
  freopen_s(&fp, "CONOUT$", "w", stdout);
  freopen_s(&fp, "CONOUT$", "w", stderr);
  freopen_s(&fp, "CONIN$", "r", stdin);
  setvbuf(stdout, nullptr, _IONBF, 0);
  setvbuf(stderr, nullptr, _IONBF, 0);
  std::ios::sync_with_stdio();
  FlutterDesktopResyncOutputStreams();
}

void RedirectIOToFile(const char* path) {
  // Open with FILE_SHARE_READ | FILE_SHARE_WRITE so Dart can also write to this file.
  // freopen_s does NOT expose sharing flags and defaults to exclusive access,
  // which blocks Dart's File.openSync() from appending to the same log file.
  int wlen = ::MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
  if (wlen <= 0) return;
  std::vector<wchar_t> wpath(wlen);
  ::MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath.data(), wlen);

  HANDLE hFile = ::CreateFileW(
      wpath.data(),
      GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr,
      CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (hFile == INVALID_HANDLE_VALUE) return;

  // Associate the Win32 handle with a CRT file descriptor, then with stdout.
  int fd = _open_osfhandle(reinterpret_cast<intptr_t>(hFile), _O_WRONLY | _O_TEXT);
  if (fd == -1) { ::CloseHandle(hFile); return; }

  FILE *fp = _fdopen(fd, "w");
  if (!fp) { _close(fd); return; }
  setvbuf(fp, nullptr, _IONBF, 0);

  // Replace CRT stdout with our file stream.
  *stdout = *fp;
  // Wire fd 1 and fd 2 to the same file so Dart (which uses fd 1) can reach it.
  _dup2(fd, 1);
  _dup2(fd, 2);

  // Sync Win32 standard handles (Dart uses GetStdHandle -> WriteFile).
  ::SetStdHandle(STD_OUTPUT_HANDLE, hFile);
  ::SetStdHandle(STD_ERROR_HANDLE, hFile);

  // Force std::cout/cerr to re-associate with the redirected CRT streams.
  std::ios::sync_with_stdio(false);
  std::ios::sync_with_stdio(true);
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
