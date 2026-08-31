#include "crash_record.h"

#include <csignal>    // SIGABRT
#include <cstdint>    // uintptr_t
#include <cstdio>     // snprintf
#include <cstring>    // strlen, memcpy, in CleanTypeName
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

const char* CleanTypeName(char* out, size_t out_len, const char* raw) {
  if (raw == nullptr || out == nullptr || out_len == 0) {
    return raw;
  }
  // ".?AV" for a class, ".?AU" for a struct. Anything else is a shape we do
  // not claim to understand.
  if (raw[0] != '.' || raw[1] != '?' || raw[2] != 'A' ||
      (raw[3] != 'V' && raw[3] != 'U')) {
    return raw;
  }
  const char* body = raw + 4;
  const size_t body_len = std::strlen(body);
  // Every name the compiler emits for a plain class ends "@@"; without it this
  // is something else (a template's fragments, most often) and is left alone.
  if (body_len < 2 || body[body_len - 2] != '@' || body[body_len - 1] != '@') {
    return raw;
  }

  // Scopes are stored innermost-first: "bad_alloc@std" is std::bad_alloc. Walk
  // them backwards, joining with "::". A '?' anywhere means a template or a
  // special name whose grammar this does not implement -- bail to the raw form
  // rather than emit a plausible-looking wrong answer.
  const size_t scopes_len = body_len - 2;
  for (size_t i = 0; i < scopes_len; ++i) {
    if (body[i] == '?') {
      return raw;
    }
  }

  size_t used = 0;
  out[0] = '\0';
  size_t end = scopes_len;
  while (end > 0) {
    size_t start = end;
    while (start > 0 && body[start - 1] != '@') {
      --start;
    }
    const size_t part_len = end - start;
    // An empty scope ("a@@b") is not a shape the compiler emits; refuse it
    // rather than produce "a::::b".
    if (part_len == 0) {
      return raw;
    }
    const bool needs_sep = used > 0;
    if (used + (needs_sep ? 2 : 0) + part_len + 1 > out_len) {
      return raw;  // Would truncate: a shortened type name is a misleading one.
    }
    if (needs_sep) {
      out[used++] = ':';
      out[used++] = ':';
    }
    std::memcpy(out + used, body + start, part_len);
    used += part_len;
    out[used] = '\0';
    end = start > 0 ? start - 1 : 0;
  }
  return used > 0 ? out : raw;
}

void FormatCppExceptionDetail(char* out, size_t out_len, const char* type_name,
                              const void* address) {
  std::snprintf(out, out_len, "code=0xE06D7363 (C++ throw) type=%s address=0x%llx",
                type_name != nullptr ? type_name : "(not recoverable)",
                static_cast<unsigned long long>(
                    reinterpret_cast<uintptr_t>(address)));
}

void FormatFrameLine(char* out, size_t out_len, unsigned index,
                     const char* module, unsigned long long offset,
                     const void* address) {
  const unsigned long long addr =
      static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(address));
  if (module == nullptr) {
    // No module owns this address. Worth printing loudly: that is what a
    // return into freed or corrupted memory looks like.
    std::snprintf(out, out_len, "[crash]   #%02u <no module> (0x%llx)", index,
                  addr);
    return;
  }
  std::snprintf(out, out_len, "[crash]   #%02u %s+0x%llx (0x%llx)", index,
                module, offset, addr);
}

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
