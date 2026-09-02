#include "egl_storm_detector.h"

namespace tfc {
namespace {

// The two lines the engine emits while its EGL context is gone. Exact
// prefixes from flutter/shell/platform/windows/egl/egl.cc and
// flutter/shell/gpu/gpu_surface_gl_skia.cc, matched as substrings because the
// engine prepends its [ERROR:...] location tag.
constexpr const char* kNeedles[] = {
    "EGL Error: Context Lost",
    "Could not make the context current",
};

// A bounded substring search: |haystack| is not NUL-terminated.
bool Contains(const char* haystack, std::size_t length, const char* needle) {
  std::size_t needle_length = 0;
  while (needle[needle_length] != '\0') {
    needle_length++;
  }
  if (needle_length == 0 || length < needle_length) {
    return false;
  }
  for (std::size_t i = 0; i + needle_length <= length; i++) {
    std::size_t j = 0;
    while (j < needle_length && haystack[i + j] == needle[j]) {
      j++;
    }
    if (j == needle_length) {
      return true;
    }
  }
  return false;
}

// Past this, a "line" with no newline is fed to the detector as-is rather
// than being buffered forever. Both needles fit in the first 120 bytes of
// their real lines, so nothing is lost by cutting here.
constexpr std::size_t kMaxCarryBytes = 4096;

}  // namespace

bool EglStormDetector::LineMatches(const char* line, std::size_t length) {
  for (const char* needle : kNeedles) {
    if (Contains(line, length, needle)) {
      return true;
    }
  }
  return false;
}

bool EglStormDetector::OnLine(const char* line, std::size_t length,
                              unsigned long long now_ms) {
  if (now_ms < quiet_until_ms_) {
    return false;
  }
  if (!LineMatches(line, length)) {
    return false;
  }
  if (matches_ == 0 || now_ms - window_start_ms_ > config_.window_ms) {
    window_start_ms_ = now_ms;
    matches_ = 0;
  }
  matches_++;
  if (matches_ >= config_.min_matches) {
    matches_ = 0;
    window_start_ms_ = 0;
    quiet_until_ms_ = now_ms + config_.refire_cooldown_ms;
    return true;
  }
  return false;
}

bool EglStormDetector::OnBytes(const char* data, std::size_t length,
                               unsigned long long now_ms) {
  bool fired = false;
  std::size_t start = 0;
  for (std::size_t i = 0; i < length; i++) {
    if (data[i] != '\n') {
      continue;
    }
    if (carry_.empty()) {
      fired |= OnLine(data + start, i - start, now_ms);
    } else {
      carry_.append(data + start, i - start);
      fired |= OnLine(carry_.data(), carry_.size(), now_ms);
      carry_.clear();
    }
    start = i + 1;
  }
  if (start < length) {
    carry_.append(data + start, length - start);
    if (carry_.size() > kMaxCarryBytes) {
      fired |= OnLine(carry_.data(), carry_.size(), now_ms);
      carry_.clear();
    }
  }
  return fired;
}

}  // namespace tfc
