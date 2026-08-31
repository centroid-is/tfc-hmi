// Tests for what a crash says and where its minidump goes.
//
// A crash handler is the one piece of the runner that is never exercised on a
// developer machine and never exercised in CI, because running it ends the
// process. What can be checked is everything it decides before it does that:
// the record it writes, the dump path it builds, and the latch that stops two
// simultaneous faults from writing over each other. Those are the parts that
// have been wrong before — a truncated path, an unnamed exception, a second
// thread re-entering — and none of them need Win32.

#include "../crash_record.h"

#include "test_harness.h"

#include <csignal>
#include <cstring>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {

using tfc::CrashLatch;
using tfc::CrashTime;
using tfc::DescribeActiveException;
using tfc::CleanTypeName;
using tfc::FormatCppExceptionDetail;
using tfc::FormatCrashRecord;
using tfc::FormatFrameLine;
using tfc::FormatInvalidParameterDetail;
using tfc::FormatMinidumpPath;
using tfc::FormatSehDetail;
using tfc::FormatTimestamp;
using tfc::SignalKind;

CrashTime SomeTime() {
  CrashTime time;
  time.year = 2026;
  time.month = 8;
  time.day = 23;
  time.hour = 6;
  time.minute = 7;
  time.second = 9;
  return time;
}

bool Contains(const std::string& haystack, const std::string& needle) {
  return haystack.find(needle) != std::string::npos;
}

}  // namespace

TEST(a_type_descriptor_becomes_a_readable_scoped_name) {
  char out[64];
  CHECK_EQ(std::string(CleanTypeName(out, sizeof(out), ".?AVbad_alloc@std@@")),
           std::string("std::bad_alloc"));
  CHECK_EQ(std::string(CleanTypeName(out, sizeof(out), ".?AUmy_struct@@")),
           std::string("my_struct"));
  CHECK_EQ(std::string(CleanTypeName(out, sizeof(out), ".?AVerror@io@fs@@")),
           std::string("fs::io::error"));
}

// A name we cannot parse is still evidence. Handing back the mangled form beats
// emitting a tidy-looking guess, which is how a wrong type ends up in a report.
TEST(an_unparsable_type_descriptor_is_returned_verbatim) {
  char out[64];
  const char* templated = ".?AV?$vector@H@std@@";
  CHECK_EQ(std::string(CleanTypeName(out, sizeof(out), templated)),
           std::string(templated));
  const char* not_a_type = "bad_alloc";
  CHECK_EQ(std::string(CleanTypeName(out, sizeof(out), not_a_type)),
           std::string(not_a_type));
  const char* empty_scope = ".?AVa@@b@@";
  CHECK_EQ(std::string(CleanTypeName(out, sizeof(out), empty_scope)),
           std::string(empty_scope));
}

// Truncating a type name would silently rename the exception, so a buffer that
// cannot hold it yields the raw form instead of a prefix of the answer.
TEST(a_type_name_that_does_not_fit_is_not_truncated) {
  char out[8];
  const char* raw = ".?AVbad_alloc@std@@";
  CHECK_EQ(std::string(CleanTypeName(out, sizeof(out), raw)), std::string(raw));
}

TEST(a_cpp_exception_detail_names_the_type_when_it_is_known) {
  char out[128];
  FormatCppExceptionDetail(out, sizeof(out), "std::bad_alloc",
                           reinterpret_cast<const void*>(0x7ffb1234abcdULL));
  CHECK_EQ(std::string(out),
           std::string("code=0xE06D7363 (C++ throw) type=std::bad_alloc "
                       "address=0x7ffb1234abcd"));
}

TEST(a_cpp_exception_detail_admits_when_the_type_is_unknown) {
  char out[128];
  FormatCppExceptionDetail(out, sizeof(out), nullptr, nullptr);
  CHECK_EQ(std::string(out),
           std::string("code=0xE06D7363 (C++ throw) type=(not recoverable) "
                       "address=0x0"));
}

TEST(a_frame_line_reads_as_module_plus_offset) {
  char out[128];
  FormatFrameLine(out, sizeof(out), 3, "open62541.dll", 0x1a2b,
                  reinterpret_cast<const void*>(0x7ffb00001a2bULL));
  CHECK_EQ(std::string(out),
           std::string("[crash]   #03 open62541.dll+0x1a2b (0x7ffb00001a2b)"));
}

// An address belonging to no module is the interesting case, not one to hide:
// it is what a return through a corrupted pointer looks like.
TEST(a_frame_line_says_so_when_no_module_owns_the_address) {
  char out[128];
  FormatFrameLine(out, sizeof(out), 0, nullptr, 0,
                  reinterpret_cast<const void*>(0xdeadbeefULL));
  CHECK_EQ(std::string(out),
           std::string("[crash]   #00 <no module> (0xdeadbeef)"));
}

TEST(a_timestamp_is_fixed_width_and_sorts_as_a_filename) {
  char out[32];
  FormatTimestamp(out, sizeof(out), SomeTime());

  // Zero-padded throughout: these end up in dump filenames next to each other
  // in a directory listing, and "2026823-679" would sort wrongly and read
  // ambiguously.
  CHECK_EQ(std::string(out), std::string("20260823-060709"));
}

TEST(a_timestamp_never_runs_past_its_buffer) {
  char out[8] = {'\0'};
  FormatTimestamp(out, sizeof(out), SomeTime());

  CHECK_EQ(std::strlen(out), size_t{7});
  CHECK_EQ(std::string(out), std::string("2026082"));
}

TEST(a_crash_record_names_the_kind_thread_time_and_detail) {
  char out[256];
  FormatCrashRecord(out, sizeof(out), "std::terminate", 4321, "20260823-060709",
                    "uncaught std::runtime_error: boom");

  CHECK_EQ(std::string(out),
           std::string("[crash] std::terminate  thread=4321  "
                       "time=20260823-060709  detail=uncaught "
                       "std::runtime_error: boom"));
}

TEST(a_crash_record_with_no_detail_still_records_every_other_field) {
  char out[256];
  FormatCrashRecord(out, sizeof(out), "pure virtual call", 7, "20260823-060709",
                    nullptr);

  // The pure-call handler has nothing to say beyond its own name. Formatting
  // a null pointer through %s would be undefined; dropping the field would
  // make the line unparseable.
  CHECK(Contains(out, "detail=(none)"));
  CHECK(Contains(out, "thread=7"));
}

TEST(a_minidump_path_is_built_under_the_configured_directory) {
  char out[260];
  CHECK(FormatMinidumpPath(out, sizeof(out), "C:\\logs", "20260823-060709",
                           1234));
  CHECK_EQ(std::string(out),
           std::string("C:\\logs\\hmi-crash-20260823-060709-1234.dmp"));
}

TEST(no_dump_directory_means_no_dump) {
  char out[260];
  // main.cpp passes DirectoryOf(log_path), which is empty when the log path
  // has no directory part — and when DefaultLogPath() failed outright.
  CHECK(!FormatMinidumpPath(out, sizeof(out), "", "20260823-060709", 1234));
  CHECK_EQ(std::string(out), std::string());

  CHECK(!FormatMinidumpPath(out, sizeof(out), nullptr, "20260823-060709", 1234));
  CHECK_EQ(std::string(out), std::string());
}

TEST(a_dump_path_that_does_not_fit_is_refused_not_truncated) {
  // The real buffer is MAX_PATH, and the directory alone may be MAX_PATH-1, so
  // the sum overflows for any deep log location. A truncated path is still a
  // legal filename: writing to it would drop the dump somewhere nobody looks,
  // or chop off ".dmp" so nothing opens it.
  const std::string deep(200, 'd');
  char out[64];
  CHECK(!FormatMinidumpPath(out, sizeof(out), deep.c_str(), "20260823-060709",
                            1234));
  CHECK_EQ(std::string(out), std::string());

  // One byte of headroom is enough, and is not refused.
  char roomy[128];
  CHECK(FormatMinidumpPath(roomy, sizeof(roomy), "C:\\logs", "20260823-060709",
                           1234));
}

TEST(a_structured_exception_records_its_code_and_address) {
  char out[128];
  FormatSehDetail(out, sizeof(out), true, 0xC0000005UL,
                  reinterpret_cast<const void*>(0x7ff6abcd1234ULL));

  // 0xC0000005 is the access violation this handler exists for; the code is
  // zero-padded to eight digits so it can be pasted into a search.
  CHECK(Contains(out, "code=0xC0000005"));
  CHECK(Contains(out, "address=0x7ff6abcd1234"));
}

TEST(a_structured_exception_code_is_padded_to_eight_digits) {
  char out[128];
  FormatSehDetail(out, sizeof(out), true, 0x0000008DUL, nullptr);
  CHECK(Contains(out, "code=0x0000008D"));
}

TEST(a_structured_exception_with_no_record_still_produces_a_detail) {
  char out[128];
  FormatSehDetail(out, sizeof(out), false, 0, nullptr);

  // SetUnhandledExceptionFilter can be entered with no EXCEPTION_RECORD.
  // Reading through the null was the original hazard here.
  CHECK_EQ(std::string(out), std::string("(no record)"));
}

TEST(an_invalid_parameter_records_the_expression_that_failed) {
  char out[256];
  FormatInvalidParameterDetail(out, sizeof(out), L"index < size", L"at",
                               L"vector.h", 1421);

  CHECK(Contains(out, "expression=index < size"));
  CHECK(Contains(out, "function=at"));
  CHECK(Contains(out, "file=vector.h"));
  CHECK(Contains(out, "line=1421"));
}

TEST(an_invalid_parameter_with_no_strings_is_the_release_build_case) {
  char out[256];
  // A release CRT passes nothing at all. Formatting those nulls through %ls is
  // undefined, so they have to be substituted before they reach snprintf.
  FormatInvalidParameterDetail(out, sizeof(out), nullptr, nullptr, nullptr, 0);

  CHECK(Contains(out, "expression=(null)"));
  CHECK(Contains(out, "function=(null)"));
  CHECK(Contains(out, "file=(null)"));
  CHECK(Contains(out, "line=0"));
}

TEST(sigabrt_is_named_for_what_it_is) {
  // "signal 22" in a log tells an operator nothing; abort() tells them a
  // check inside the app failed.
  CHECK_EQ(std::string(SignalKind(SIGABRT)), std::string("abort()"));
  CHECK_EQ(std::string(SignalKind(SIGSEGV)), std::string("signal"));
}

TEST(the_latch_lets_exactly_one_crash_through) {
  CrashLatch latch;
  CHECK(latch.Enter());

  // A fault inside the handler re-enters here. Without the latch that is an
  // unbounded recursion instead of a process exit.
  CHECK(!latch.Enter());
  CHECK(!latch.Enter());
}

TEST(the_latch_admits_one_winner_when_threads_fault_together) {
  CrashLatch latch;
  std::atomic<int> winners{0};
  std::vector<std::thread> racers;
  for (int i = 0; i < 8; i++) {
    racers.emplace_back([&latch, &winners]() {
      for (int attempt = 0; attempt < 200; attempt++) {
        if (latch.Enter()) winners++;
      }
    });
  }
  for (std::thread& racer : racers) racer.join();

  // 1600 attempts, one winner: the UI thread and the OPC UA thread can fault
  // on the same bad pointer, and two threads writing one minidump is how you
  // get no readable minidump.
  CHECK_EQ(winners.load(), 1);
}

TEST(an_uncaught_std_exception_is_named_and_quoted) {
  char buffer[512];
  const char* detail = nullptr;
  try {
    throw std::runtime_error("modbus poll timed out");
  } catch (...) {
    detail = DescribeActiveException(buffer, sizeof(buffer));
  }

  // The whole reason this handler exists: without what(), the log says
  // "abort() has been called" and nothing else.
  CHECK(Contains(detail, "modbus poll timed out"));
  CHECK(Contains(detail, "uncaught "));
}

TEST(an_uncaught_non_std_exception_still_says_so) {
  char buffer[512];
  const char* detail = nullptr;
  try {
    throw 42;
  } catch (...) {
    detail = DescribeActiveException(buffer, sizeof(buffer));
  }

  CHECK_EQ(std::string(detail),
           std::string("uncaught exception not derived from std::exception"));
}

TEST(an_explicit_terminate_says_there_was_no_exception) {
  char buffer[512];
  // std::terminate reached with nothing in flight — an exception escaping a
  // noexcept function, or a direct call. Reporting a stale exception here
  // would send whoever reads the log after the wrong thing entirely.
  const char* detail = DescribeActiveException(buffer, sizeof(buffer));

  CHECK(Contains(detail, "no active exception"));
}

int main() {
  std::printf("crash_record_test\n");
  return tfc_test::RunAll();
}
