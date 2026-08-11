#include "crash_handler.h"

#include <windows.h>
// dbghelp.h must follow windows.h.
#include <dbghelp.h>
// _CrtSetReportMode / _CrtSetReportFile, used in the debug block below.
#include <crtdbg.h>

#include <csignal>   // signal, SIGABRT
#include <cstdint>   // uintptr_t, in the invalid-parameter handler signature
#include <cstdio>    // fputs, fflush, _snprintf_s
#include <cstdlib>   // _set_abort_behavior, _set_purecall_handler
#include <exception> // set_terminate, current_exception, rethrow_exception
#include <typeinfo>  // typeid, to name the exception that killed us

namespace tfc {
namespace {

// Where minidumps go. Captured at install time because the handlers cannot
// take arguments and must not allocate.
char g_dump_dir[MAX_PATH] = {0};

// A crash inside a crash handler must not recurse forever. InterlockedExchange
// rather than a plain bool: two threads can fault simultaneously.
LONG g_handling = 0;

bool EnterHandler() {
  return ::InterlockedExchange(&g_handling, 1) == 0;
}

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

void FormatTimestamp(char* out, size_t out_len) {
  SYSTEMTIME st;
  ::GetSystemTime(&st);
  _snprintf_s(out, out_len, _TRUNCATE, "%04u%02u%02u-%02u%02u%02u", st.wYear,
              st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
}

// Writes a minidump and reports where it went. |pointers| may be null, which
// still yields usable thread stacks.
void WriteMinidump(EXCEPTION_POINTERS* pointers, const char* timestamp) {
  if (g_dump_dir[0] == '\0') {
    WriteRecord("[crash] no dump directory configured — minidump skipped");
    return;
  }

  char path[MAX_PATH];
  _snprintf_s(path, sizeof(path), _TRUNCATE, "%s\\hmi-crash-%s-%lu.dmp",
              g_dump_dir, timestamp, ::GetCurrentProcessId());

  HANDLE file = ::CreateFileA(path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    char line[MAX_PATH + 64];
    _snprintf_s(line, sizeof(line), _TRUNCATE,
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
    _snprintf_s(line, sizeof(line), _TRUNCATE, "[crash] minidump written: %s",
                path);
  } else {
    _snprintf_s(line, sizeof(line), _TRUNCATE,
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
  if (EnterHandler()) {
    char timestamp[32];
    FormatTimestamp(timestamp, sizeof(timestamp));

    char line[1024];
    _snprintf_s(line, sizeof(line), _TRUNCATE,
                "[crash] %s  thread=%lu  time=%s  detail=%s", kind,
                ::GetCurrentThreadId(), timestamp,
                detail != nullptr ? detail : "(none)");
    WriteRecord(line);

    WriteMinidump(pointers, timestamp);
  }
  ::TerminateProcess(::GetCurrentProcess(), exit_code);
  // TerminateProcess does not return, but the compiler wants an end here.
  ::ExitProcess(exit_code);
}

LONG WINAPI SehFilter(EXCEPTION_POINTERS* pointers) {
  char detail[128] = "(no record)";
  if (pointers != nullptr && pointers->ExceptionRecord != nullptr) {
    _snprintf_s(detail, sizeof(detail), _TRUNCATE,
                "code=0x%08lX address=0x%p",
                pointers->ExceptionRecord->ExceptionCode,
                pointers->ExceptionRecord->ExceptionAddress);
  }
  ReportAndDie("structured exception", detail, pointers, 1);
}

void TerminateHandler() {
  // Recovering what() is the whole point: this is the path an exception
  // escaping a noexcept function takes, and without this the log says nothing
  // beyond "abort() has been called".
  const char* detail = "no active exception (explicit terminate, or an "
                       "exception escaping a noexcept function)";
  char buffer[512];

  if (std::exception_ptr active = std::current_exception()) {
    try {
      std::rethrow_exception(active);
    } catch (const std::exception& e) {
      _snprintf_s(buffer, sizeof(buffer), _TRUNCATE, "uncaught %s: %s",
                  typeid(e).name(), e.what());
      detail = buffer;
    } catch (...) {
      detail = "uncaught exception not derived from std::exception";
    }
  }

  ReportAndDie("std::terminate", detail, nullptr, 3);
}

void SignalHandler(int signal_number) {
  const char* kind = signal_number == SIGABRT ? "abort()" : "signal";
  char detail[64];
  _snprintf_s(detail, sizeof(detail), _TRUNCATE, "signal=%d", signal_number);
  ReportAndDie(kind, detail, nullptr, 3);
}

void InvalidParameterHandler(const wchar_t* expression, const wchar_t* function,
                             const wchar_t* file, unsigned int line,
                             uintptr_t /*reserved*/) {
  // The CRT's default for this is to call abort() with no explanation at all.
  char detail[768];
  _snprintf_s(detail, sizeof(detail), _TRUNCATE,
              "expression=%ls function=%ls file=%ls line=%u",
              expression != nullptr ? expression : L"(null)",
              function != nullptr ? function : L"(null)",
              file != nullptr ? file : L"(null)", line);
  ReportAndDie("CRT invalid parameter", detail, nullptr, 3);
}

void PureCallHandler() {
  ReportAndDie("pure virtual call", nullptr, nullptr, 3);
}

}  // namespace

void InstallCrashHandlers(const std::string& dump_dir) {
  _snprintf_s(g_dump_dir, sizeof(g_dump_dir), _TRUNCATE, "%s",
              dump_dir.c_str());

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
