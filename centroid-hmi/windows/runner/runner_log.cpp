#include "runner_log.h"

#include <windows.h>

#include <cstdio>
#include <iostream>
#include <mutex>
#include <vector>

namespace tfc {
namespace {

std::mutex& LogMutex() {
  static std::mutex mutex;
  return mutex;
}

HANDLE& LogHandle() {
  static HANDLE handle = INVALID_HANDLE_VALUE;
  return handle;
}

std::string& LogPathStorage() {
  static std::string path;
  return path;
}

std::wstring Utf16(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int len = ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (len <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(len) - 1, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &wide[0], len);
  return wide;
}

// "2026-08-31 19:47:02.318". Local time, because the person reading this is
// correlating it against an operator saying "the screen died just before eight".
std::string Timestamp() {
  SYSTEMTIME now;
  ::GetLocalTime(&now);
  char buffer[32];
  std::snprintf(buffer, sizeof(buffer), "%04u-%02u-%02u %02u:%02u:%02u.%03u",
                now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
                now.wSecond, now.wMilliseconds);
  return std::string(buffer);
}

// Appends to the durable half. Caller holds the lock.
void WriteToFileLocked(const std::string& text) {
  HANDLE handle = LogHandle();
  if (handle == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  // FILE_APPEND_DATA means every write lands at the end regardless of this
  // handle's offset, which is what lets the Dart logger own the same file.
  ::WriteFile(handle, text.data(), static_cast<DWORD>(text.size()), &written,
              nullptr);
  ::FlushFileBuffers(handle);
}

}  // namespace

namespace {

// Beyond this the sidecar is rolled to .prev. The runner writes a few hundred
// throttled lines a day, so this is months of history; the cap exists so that
// a pathological loop cannot fill a station's disk.
constexpr long long kMaxSidecarBytes = 8LL * 1024 * 1024;

// The runner's own file, beside whatever CENTROID_LOG_FILE names.
//
// NOT the log file itself, which was the first attempt and does not work. The
// Dart logger writes that same path through its own handle at its own offset,
// and measurement on a live run showed it overwriting these lines as fast as
// they were appended: 23 [gpu-watchdog] lines reached stderr, 6 survived in
// the file, and a line read once was gone on the next read. utils.cpp already
// documents the same hazard for open62541. One file, one writer.
std::string SidecarPathFor(const std::string& log_path) {
  const size_t slash = log_path.find_last_of("\\/");
  if (slash == std::string::npos) {
    return "hmi-runner.log";
  }
  return log_path.substr(0, slash + 1) + "hmi-runner.log";
}

}  // namespace

void InitRunnerLog(const std::string& log_path) {
  std::lock_guard<std::mutex> guard(LogMutex());
  if (LogHandle() != INVALID_HANDLE_VALUE || log_path.empty()) {
    return;
  }

  const std::string sidecar = SidecarPathFor(log_path);
  const std::wstring wide = Utf16(sidecar);
  if (wide.empty()) {
    return;
  }

  // Roll before opening, so a run always starts with room. MOVEFILE_REPLACE
  // keeps exactly one generation: the interesting history is the current file,
  // and the previous one only matters when a station restarted mid-incident.
  WIN32_FILE_ATTRIBUTE_DATA attributes = {};
  if (::GetFileAttributesExW(wide.c_str(), GetFileExInfoStandard,
                             &attributes)) {
    const long long size =
        (static_cast<long long>(attributes.nFileSizeHigh) << 32) |
        attributes.nFileSizeLow;
    if (size > kMaxSidecarBytes) {
      ::MoveFileExW(wide.c_str(), (wide + L".prev").c_str(),
                    MOVEFILE_REPLACE_EXISTING);
    }
  }

  // OPEN_ALWAYS and FILE_APPEND_DATA: this file deliberately survives across
  // runs. "It froze twice yesterday" is a question about yesterday, and a
  // sidecar truncated on every start cannot answer it.
  HANDLE handle = ::CreateFileW(wide.c_str(), FILE_APPEND_DATA | SYNCHRONIZE,
                                FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                                OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    return;
  }
  LogHandle() = handle;
  LogPathStorage() = sidecar;

  const std::string banner =
      "\n" + Timestamp() +
      " [startup] ---- runner started; this file is written ONLY by the "
      "runner, so nothing else can overwrite it ----\n";
  WriteToFileLocked(banner);
}

void RunnerLogLine(const char* tag, const std::string& message) {
  std::string line = Timestamp();
  line += " ";
  line += tag;
  line += " ";
  line += message;
  line += "\n";

  std::lock_guard<std::mutex> guard(LogMutex());
  // stderr first: if the process is about to end because of what this line
  // says, the console is the sink most likely to be watched live.
  std::cerr << line;
  std::cerr.flush();
  WriteToFileLocked(line);
}

void RunnerLogBlock(const std::string& block) {
  std::lock_guard<std::mutex> guard(LogMutex());
  std::cerr << block;
  std::cerr.flush();
  WriteToFileLocked(block);
}

bool RunnerLogHasFile() {
  std::lock_guard<std::mutex> guard(LogMutex());
  return LogHandle() != INVALID_HANDLE_VALUE;
}

const std::string& RunnerLogPath() {
  return LogPathStorage();
}

}  // namespace tfc
