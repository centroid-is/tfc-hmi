// Tests for the two decisions utils.cpp makes that are not Win32 calls.
//
// DirectoryOf is what the crash handler is handed as its dump directory, so
// getting it wrong means a release that logs but never dumps. Utf8LengthWithoutNul
// is the sizing step of the command-line conversion, where an unsigned
// subtraction used to turn a failed conversion into a four-gigabyte resize().

#include "../path_utils.h"

#include "test_harness.h"

#include <limits>
#include <string>

namespace {

using tfc::DirectoryOf;
using tfc::Utf8LengthWithoutNul;

}  // namespace

TEST(a_windows_path_keeps_everything_before_the_last_backslash) {
  CHECK_EQ(DirectoryOf("C:\\Users\\op\\AppData\\Local\\centroid-hmi\\logs\\hmi.log"),
           std::string("C:\\Users\\op\\AppData\\Local\\centroid-hmi\\logs"));
}

TEST(a_forward_slash_path_is_accepted_too) {
  // CENTROID_LOG_FILE is typed by a person, and PowerShell and the Flutter
  // tool both hand out forward slashes.
  CHECK_EQ(DirectoryOf("C:/logs/hmi.log"), std::string("C:/logs"));
}

TEST(a_mixed_separator_path_splits_at_the_last_one_of_either_kind) {
  CHECK_EQ(DirectoryOf("C:/logs\\run3/hmi.log"), std::string("C:/logs\\run3"));
  CHECK_EQ(DirectoryOf("C:\\logs/run3\\hmi.log"), std::string("C:\\logs/run3"));
}

TEST(a_bare_filename_has_no_directory) {
  // Not malformed — `CENTROID_LOG_FILE=hmi.log` is a working relative path.
  // The empty result is what tells the crash handler it has nowhere to write
  // a minidump, which is why it must be empty rather than "." or the input.
  CHECK_EQ(DirectoryOf("hmi.log"), std::string());
  CHECK_EQ(DirectoryOf(""), std::string());
}

TEST(a_dot_in_a_directory_name_does_not_split_the_path) {
  CHECK_EQ(DirectoryOf("C:\\centroid.hmi\\logs\\hmi.log"),
           std::string("C:\\centroid.hmi\\logs"));
}

TEST(a_path_ending_in_a_separator_is_all_directory) {
  CHECK_EQ(DirectoryOf("C:\\logs\\"), std::string("C:\\logs"));
}

TEST(a_root_relative_path_yields_the_root) {
  // find_last_of at index 0 must not be mistaken for npos.
  CHECK_EQ(DirectoryOf("\\hmi.log"), std::string());
  CHECK_EQ(DirectoryOf("/hmi.log"), std::string());
}

TEST(a_successful_sizing_call_loses_only_the_terminator) {
  // WideCharToMultiByte(..., -1, nullptr, 0, ...) counts the NUL.
  CHECK_EQ(Utf8LengthWithoutNul(6), size_t{5});
  CHECK_EQ(Utf8LengthWithoutNul(2), size_t{1});
}

TEST(a_failed_sizing_call_asks_for_nothing) {
  // WideCharToMultiByte returns 0 on failure, and WC_ERR_INVALID_CHARS makes
  // that reachable: a lone surrogate anywhere in the command line is enough.
  // The `- 1` this replaced produced 4294967295 in an unsigned int, which is
  // below std::string::max_size() on 64-bit, so the guard let it through and
  // the resize() threw bad_alloc out of wWinMain.
  CHECK_EQ(Utf8LengthWithoutNul(0), size_t{0});
}

TEST(an_empty_conversion_asks_for_nothing) {
  // A result of 1 is a string consisting only of the terminator.
  CHECK_EQ(Utf8LengthWithoutNul(1), size_t{0});
}

TEST(a_negative_sizing_result_asks_for_nothing) {
  // Not a documented return, but it must not become SIZE_MAX if it ever is.
  CHECK_EQ(Utf8LengthWithoutNul(-1), size_t{0});
  CHECK_EQ(Utf8LengthWithoutNul(std::numeric_limits<int>::min()), size_t{0});
}

int main() {
  std::printf("path_utils_test\n");
  return tfc_test::RunAll();
}
