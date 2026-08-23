#ifndef RUNNER_PATH_UTILS_H_
#define RUNNER_PATH_UTILS_H_

#include <cstddef>
#include <string>

// String and path arithmetic pulled out of utils.cpp, which cannot be compiled
// off Windows. Both functions here decide whether the runner logs and dumps at
// all, so they are worth testing on their own.

namespace tfc {

// Directory part of |path|, empty if it has none. Accepts either separator:
// the path can come from CENTROID_LOG_FILE, which a person typed.
//
// The result is what the crash handler is given as its dump directory, and an
// empty one means "no minidumps" — so "hmi.log" with no directory is a real
// input, not a malformed one.
std::string DirectoryOf(const std::string& path);

// Bytes to allocate for a UTF-8 conversion whose sizing call returned
// |wide_to_utf8_result| — the value WideCharToMultiByte hands back when asked
// for a length, which counts the terminating NUL. Zero means "do not convert".
//
// The subtraction is here rather than at the call site because
// WideCharToMultiByte returns 0 on failure (an unpaired surrogate in the
// command line is enough, with WC_ERR_INVALID_CHARS set), and 0 - 1 in an
// unsigned type is a four-billion-byte resize, not a zero-length string.
size_t Utf8LengthWithoutNul(int wide_to_utf8_result);

}  // namespace tfc

#endif  // RUNNER_PATH_UTILS_H_
