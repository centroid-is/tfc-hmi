#include "utils.h"

#include "log_rotation.h"

#include <flutter_windows.h>
#include <fcntl.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <cstdlib>  // free, _wdupenv_s
#include <iostream>
#include <string>
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

  // Point the *engine's* stdout/stderr at the new streams as well. Without
  // this, everything the Dart side writes through print() — which is every
  // logger package line, via ConsoleOutput — keeps going to the streams the
  // engine captured at startup, i.e. nowhere in a windowed app. The two
  // console paths above have always called this; the file path never did,
  // which is why file logging captured the C++ side only.
  FlutterDesktopResyncOutputStreams();
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

namespace {

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int len = ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (len <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(len) - 1, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &wide[0], len);
  return wide;
}

std::string Utf8FromUtf16Str(const std::wstring& utf16) {
  if (utf16.empty()) return std::string();
  int len = ::WideCharToMultiByte(CP_UTF8, 0, utf16.c_str(), -1, nullptr, 0,
                                  nullptr, nullptr);
  if (len <= 0) return std::string();
  std::string utf8(static_cast<size_t>(len) - 1, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, utf16.c_str(), -1, &utf8[0], len, nullptr,
                        nullptr);
  return utf8;
}

}  // namespace

std::string DirectoryOf(const std::string& path) {
  std::string::size_type slash = path.find_last_of("/\\");
  if (slash == std::string::npos) return std::string();
  return path.substr(0, slash);
}

std::string DefaultLogPath() {
  wchar_t* local_app_data = nullptr;
  size_t len = 0;
  if (_wdupenv_s(&local_app_data, &len, L"LOCALAPPDATA") != 0 ||
      local_app_data == nullptr) {
    return std::string();
  }
  std::wstring dir(local_app_data);
  free(local_app_data);

  // CreateDirectoryW does not create intermediate levels, so build the two
  // levels we need in order. Both may already exist; that is not an error.
  dir += L"\\centroid-hmi";
  ::CreateDirectoryW(dir.c_str(), nullptr);
  dir += L"\\logs";
  ::CreateDirectoryW(dir.c_str(), nullptr);

  DWORD attributes = ::GetFileAttributesW(dir.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      !(attributes & FILE_ATTRIBUTE_DIRECTORY)) {
    return std::string();
  }

  return Utf8FromUtf16Str(dir + L"\\hmi.log");
}

void RotateLogs(const std::string& path, int max_archives) {
  if (path.empty()) return;

  tfc::LogRotationPlan plan = tfc::PlanRotation(path, max_archives);

  for (const std::string& doomed : plan.deletes) {
    ::DeleteFileW(Utf16FromUtf8(doomed).c_str());
  }
  for (const auto& rename : plan.renames) {
    // MOVEFILE_REPLACE_EXISTING for safety: a leftover destination from an
    // interrupted rotation must not stop the chain.
    ::MoveFileExW(Utf16FromUtf8(rename.first).c_str(),
                  Utf16FromUtf8(rename.second).c_str(),
                  MOVEFILE_REPLACE_EXISTING);
  }
}
