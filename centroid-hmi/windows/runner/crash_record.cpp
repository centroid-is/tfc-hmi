#include "crash_record.h"

#include <csignal>    // SIGABRT
#include <cstdint>    // uintptr_t
#include <cstdio>     // snprintf
#include <exception>  // current_exception, rethrow_exception
#include <typeinfo>   // typeid, to name the exception that killed us

namespace tfc {
namespace {

// snprintf, not the CRT's _snprintf_s: both truncate and NUL-terminate, and
// only one of them exists off Windows. Nothing here formats anything wider
// than the buffer on purpose, so the return value is only interesting where
// truncation changes the answer (see FormatMinidumpPath).
//
// A negative return means an encoding failure, which for the %ls conversions
// below is possible in the "C" locale. Treated as "wrote nothing".
bool Fits(int written, size_t out_len) {
  return written >= 0 && static_cast<size_t>(written) < out_len;
}

}  // namespace

void FormatTimestamp(char* out, size_t out_len, const CrashTime& time) {
  std::snprintf(out, out_len, "%04u%02u%02u-%02u%02u%02u", time.year,
                time.month, time.day, time.hour, time.minute, time.second);
}

void FormatCrashRecord(char* out, size_t out_len, const char* kind,
                       unsigned long thread_id, const char* timestamp,
                       const char* detail) {
  std::snprintf(out, out_len, "[crash] %s  thread=%lu  time=%s  detail=%s",
                kind, thread_id, timestamp,
                detail != nullptr ? detail : "(none)");
}

bool FormatMinidumpPath(char* out, size_t out_len, const char* dump_dir,
                        const char* timestamp, unsigned long pid) {
  if (out_len == 0) {
    return false;
  }
  out[0] = '\0';
  if (dump_dir == nullptr || dump_dir[0] == '\0') {
    return false;
  }
  int written = std::snprintf(out, out_len, "%s\\hmi-crash-%s-%lu.dmp",
                              dump_dir, timestamp, pid);
  if (!Fits(written, out_len)) {
    out[0] = '\0';
    return false;
  }
  return true;
}

void FormatSehDetail(char* out, size_t out_len, bool has_record,
                     unsigned long code, const void* address) {
  if (!has_record) {
    std::snprintf(out, out_len, "(no record)");
    return;
  }
  // The address is printed through uintptr_t rather than %p: %p is formatted
  // differently by every CRT (MSVC pads to pointer width and omits the 0x,
  // glibc adds its own), and a crash log is read by people comparing it with
  // a map file.
  std::snprintf(out, out_len, "code=0x%08lX address=0x%llx", code,
                static_cast<unsigned long long>(
                    reinterpret_cast<uintptr_t>(address)));
}

void FormatInvalidParameterDetail(char* out, size_t out_len,
                                  const wchar_t* expression,
                                  const wchar_t* function, const wchar_t* file,
                                  unsigned int line) {
  // The CRT's default for this is to call abort() with no explanation at all.
  // In a release build it also passes nothing but nulls, so the substitution
  // below is the common case, not the edge case.
  int written = std::snprintf(
      out, out_len, "expression=%ls function=%ls file=%ls line=%u",
      expression != nullptr ? expression : L"(null)",
      function != nullptr ? function : L"(null)",
      file != nullptr ? file : L"(null)", line);
  if (written < 0 && out_len > 0) {
    // %ls failed to encode (a wide character with no representation in the
    // current locale). Losing the strings is survivable; losing the record is
    // not, so fall back to the one field that always formats.
    std::snprintf(out, out_len, "expression=(unprintable) line=%u", line);
  }
}

const char* SignalKind(int signal_number) {
  return signal_number == SIGABRT ? "abort()" : "signal";
}

const char* DescribeActiveException(char* buffer, size_t buffer_len) {
  // Recovering what() is the whole point: this is the path an exception
  // escaping a noexcept function takes, and without this the log says nothing
  // beyond "abort() has been called".
  if (std::exception_ptr active = std::current_exception()) {
    try {
      std::rethrow_exception(active);
    } catch (const std::exception& e) {
      std::snprintf(buffer, buffer_len, "uncaught %s: %s", typeid(e).name(),
                    e.what());
      return buffer;
    } catch (...) {
      return "uncaught exception not derived from std::exception";
    }
  }
  return "no active exception (explicit terminate, or an exception escaping a "
         "noexcept function)";
}

}  // namespace tfc
