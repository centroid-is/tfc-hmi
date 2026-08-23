#ifndef RUNNER_CRASH_RECORD_H_
#define RUNNER_CRASH_RECORD_H_

#include <atomic>
#include <cstddef>

// The part of crash handling that is not Win32: deciding what a crash record
// says, where its minidump goes, and which thread is allowed to write either.
//
// It lives apart from crash_handler.cpp for the same reason log_rotation.cpp
// lives apart from utils.cpp — this is the half that can be wrong in a way no
// compiler catches, and the half that cannot be exercised on a developer
// machine unless it is separable. Everything here is allocation-free and
// re-entrancy-safe, because it runs after bad_alloc and stack corruption.

namespace tfc {

// The wall-clock fields a crash record stamps itself with. Mirrors the subset
// of Win32's SYSTEMTIME the runner reads, so formatting can be tested without
// a clock.
struct CrashTime {
  unsigned year = 0;
  unsigned month = 0;
  unsigned day = 0;
  unsigned hour = 0;
  unsigned minute = 0;
  unsigned second = 0;
};

// "YYYYMMDD-HHMMSS" into |out|. Always NUL-terminates; truncates rather than
// overflowing. |out_len| must be at least 1.
void FormatTimestamp(char* out, size_t out_len, const CrashTime& time);

// The one line every crash writes to stderr. |detail| may be null, which
// records "(none)" rather than dropping the field.
void FormatCrashRecord(char* out, size_t out_len, const char* kind,
                       unsigned long thread_id, const char* timestamp,
                       const char* detail);

// Where the minidump for this crash goes: |dump_dir|\hmi-crash-<ts>-<pid>.dmp.
//
// False means no dump should be attempted — either no directory was configured
// or the full path does not fit |out_len|. Truncation has to be a refusal, not
// a shrug: a path cut short is still a syntactically fine filename, so writing
// to it would either fail obscurely or drop the dump somewhere nobody looks.
bool FormatMinidumpPath(char* out, size_t out_len, const char* dump_dir,
                        const char* timestamp, unsigned long pid);

// Detail field for a structured exception. |has_record| is false when the OS
// handed the filter no EXCEPTION_RECORD, which is rare but must still produce
// a record rather than a formatted null.
void FormatSehDetail(char* out, size_t out_len, bool has_record,
                     unsigned long code, const void* address);

// Detail field for the CRT's invalid-parameter handler. Any of the three
// strings may be null; the CRT supplies nothing at all in a release build.
void FormatInvalidParameterDetail(char* out, size_t out_len,
                                  const wchar_t* expression,
                                  const wchar_t* function, const wchar_t* file,
                                  unsigned int line);

// How a signal is named in the record. SIGABRT is the one that actually
// happens, and calling it "signal 22" helps nobody.
const char* SignalKind(int signal_number);

// Lets exactly one crash through. Two threads can fault at the same instant,
// and a fault inside a crash handler must not recurse forever, so the loser
// skips straight to ending the process.
class CrashLatch {
 public:
  // True for the first caller only, for the lifetime of the process.
  bool Enter() { return entered_.exchange(1) == 0; }

  // Test-only: puts the latch back so a second scenario can be exercised.
  void ResetForTest() { entered_.store(0); }

 private:
  std::atomic<int> entered_{0};
};

// Detail field for the exception that reached std::terminate. Must be called
// from inside the terminate handler, where std::current_exception() still
// names it. Returns either a literal or |buffer|, so |buffer| has to outlive
// the returned pointer.
const char* DescribeActiveException(char* buffer, size_t buffer_len);

}  // namespace tfc

#endif  // RUNNER_CRASH_RECORD_H_
