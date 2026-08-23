#include "crash_handler.h"

#include "crash_record.h"

#include <windows.h>
// dbghelp.h must follow windows.h.
#include <dbghelp.h>
// _CrtSetReportMode / _CrtSetReportFile, used in the debug block below.
#include <crtdbg.h>

#include <csignal>   // signal, SIGABRT
#include <cstdint>   // uintptr_t, in the invalid-parameter handler signature
#include <cstdio>    // fputs, fflush, snprintf
#include <cstdlib>   // _set_abort_behavior, _set_purecall_handler
#include <exception> // set_terminate

namespace tfc {
namespace {

// Where minidumps go. Captured at install time because the handlers cannot
// take arguments and must not allocate.
char g_dump_dir[MAX_PATH] = {0};

// A crash inside a crash handler must not recurse forever, and two threads can
// fault simultaneously. Constant-initialised, so it is armed before any static
// constructor could fault.
CrashLatch g_latch;

// Writes straight to stderr, which the runner has redirected to the log file.
// Deliberately avoids std::string and iostreams: this runs after things like
// bad_alloc and stack corruption, where allocation may be exactly what failed.
void WriteRecord(const char* line) {
  std::fputs(line, stderr);
  std::fputs("\n", stderr);
  std::fflush(stderr);
  // Also visible to a debugger or DebugView when no log file is configured.
  ::OutputDebugStringA(line);
  ::OutputDebugStringA("\n");
}

CrashTime NowUtc() {
  SYSTEMTIME st;
  ::GetSystemTime(&st);
  CrashTime time;
  time.year = st.wYear;
  time.month = st.wMonth;
  time.day = st.wDay;
  time.hour = st.wHour;
  time.minute = st.wMinute;
  time.second = st.wSecond;
  return time;
}

// Writes a minidump and reports where it went. |pointers| may be null, which
// still yields usable thread stacks.
void WriteMinidump(EXCEPTION_POINTERS* pointers, const char* timestamp) {
  char path[MAX_PATH];
  if (!FormatMinidumpPath(path, sizeof(path), g_dump_dir, timestamp,
                          ::GetCurrentProcessId())) {
    WriteRecord("[crash] no usable dump path — minidump skipped");
    return;
  }

  HANDLE file = ::CreateFileA(path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    char line[MAX_PATH + 64];
    std::snprintf(line, sizeof(line),
                  "[crash] could not create minidump %s (error %lu)", path,
                  ::GetLastError());
    WriteRecord(line);
    return;
  }

  MINIDUMP_EXCEPTION_INFORMATION info;
  info.ThreadId = ::GetCurrentThreadId();
  info.ExceptionPointers = pointers;
  info.ClientPointers = FALSE;

  // Normal + thread info + handles keeps the dump small enough to copy off a
  // rig while still giving every thread's stack.
  const MINIDUMP_TYPE type = static_cast<MINIDUMP_TYPE>(
      MiniDumpNormal | MiniDumpWithThreadInfo | MiniDumpWithHandleData);

  BOOL ok = ::MiniDumpWriteDump(::GetCurrentProcess(), ::GetCurrentProcessId(),
                                file, type, pointers ? &info : nullptr, nullptr,
                                nullptr);
  ::CloseHandle(file);

  char line[MAX_PATH + 64];
  if (ok) {
    std::snprintf(line, sizeof(line), "[crash] minidump written: %s", path);
  } else {
    std::snprintf(line, sizeof(line),
                  "[crash] MiniDumpWriteDump failed (error %lu)",
                  ::GetLastError());
  }
  WriteRecord(line);
}

// Common tail: record what happened, dump, and end the process. Does not
// return. Uses TerminateProcess rather than abort() so we cannot re-enter the
// SIGABRT handler, and so no second dialog appears.
[[noreturn]] void ReportAndDie(const char* kind, const char* detail,
                               EXCEPTION_POINTERS* pointers, UINT exit_code) {
  if (g_latch.Enter()) {
    char timestamp[32];
    FormatTimestamp(timestamp, sizeof(timestamp), NowUtc());

    char line[1024];
    FormatCrashRecord(line, sizeof(line), kind, ::GetCurrentThreadId(),
                      timestamp, detail);
    WriteRecord(line);

    WriteMinidump(pointers, timestamp);
  }
  ::TerminateProcess(::GetCurrentProcess(), exit_code);
  // TerminateProcess does not return, but the compiler wants an end here.
  ::ExitProcess(exit_code);
}

LONG WINAPI SehFilter(EXCEPTION_POINTERS* pointers) {
  const bool has_record =
      pointers != nullptr && pointers->ExceptionRecord != nullptr;
  char detail[128];
  FormatSehDetail(detail, sizeof(detail), has_record,
                  has_record ? pointers->ExceptionRecord->ExceptionCode : 0,
                  has_record ? pointers->ExceptionRecord->ExceptionAddress
                             : nullptr);
  ReportAndDie("structured exception", detail, pointers, 1);
}

void TerminateHandler() {
  char buffer[512];
  ReportAndDie("std::terminate", DescribeActiveException(buffer, sizeof(buffer)),
               nullptr, 3);
}

void SignalHandler(int signal_number) {
  char detail[64];
  std::snprintf(detail, sizeof(detail), "signal=%d", signal_number);
  ReportAndDie(SignalKind(signal_number), detail, nullptr, 3);
}

void InvalidParameterHandler(const wchar_t* expression, const wchar_t* function,
                             const wchar_t* file, unsigned int line,
                             uintptr_t /*reserved*/) {
  char detail[768];
  FormatInvalidParameterDetail(detail, sizeof(detail), expression, function,
                               file, line);
  ReportAndDie("CRT invalid parameter", detail, nullptr, 3);
}

void PureCallHandler() {
  ReportAndDie("pure virtual call", nullptr, nullptr, 3);
}

}  // namespace

void InstallCrashHandlers(const std::string& dump_dir) {
  std::snprintf(g_dump_dir, sizeof(g_dump_dir), "%s", dump_dir.c_str());

  ::SetUnhandledExceptionFilter(SehFilter);
  std::set_terminate(TerminateHandler);
  std::signal(SIGABRT, SignalHandler);
  _set_invalid_parameter_handler(InvalidParameterHandler);
  _set_purecall_handler(PureCallHandler);

  // Route SIGABRT to our handler rather than the CRT's message box. WER
  // reporting is dropped too: we write our own minidump, and a kiosk must not
  // sit on a modal dialog waiting for a click that will never come.
  _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);

#ifdef _DEBUG
  // Debug-CRT assertions default to a dialog; send them to stderr instead so
  // they reach the log like everything else.
  _CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE);
  _CrtSetReportFile(_CRT_ASSERT, _CRTDBG_FILE_STDERR);
  _CrtSetReportMode(_CRT_ERROR, _CRTDBG_MODE_FILE);
  _CrtSetReportFile(_CRT_ERROR, _CRTDBG_FILE_STDERR);
#endif
}

}  // namespace tfc
