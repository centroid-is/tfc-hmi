// Tests for the detector that reads the engine's own context-lost errors.
//
// Sized against the real incident of 2026-09-01: an RDP disconnect lost
// ANGLE's EGL context and the engine wrote 283,525 error lines at 53/second
// for 89 minutes while the D3D11 sentinel, the frame probe and a sent-message
// probe all reported healthy. The stderr stream was the only true witness, so
// its thresholds get the same treatment the watchdog's do.

#include "../egl_storm_detector.h"

#include <cstring>
#include <string>

#include "test_harness.h"

namespace {

using tfc::EglStormDetector;

// The two lines exactly as the engine writes them.
constexpr const char* kContextLostLine =
    "[ERROR:flutter/shell/platform/windows/egl/egl.cc(57)] EGL Error: "
    "Context Lost (12302) in ../../../flutter/shell/platform/windows/egl/"
    "context.cc:33";
constexpr const char* kMakeCurrentLine =
    "[ERROR:flutter/shell/gpu/gpu_surface_gl_skia.cc(220)] Could not make "
    "the context current to acquire the frame.";

EglStormDetector::Config Tight() {
  EglStormDetector::Config config;
  config.min_matches = 10;
  config.window_ms = 5000;
  config.refire_cooldown_ms = 10000;
  return config;
}

bool FeedLine(EglStormDetector& detector, const char* line,
              unsigned long long now_ms) {
  return detector.OnLine(line, std::strlen(line), now_ms);
}

TEST(matches_both_engine_error_lines) {
  CHECK(EglStormDetector::LineMatches(kContextLostLine,
                                      std::strlen(kContextLostLine)));
  CHECK(EglStormDetector::LineMatches(kMakeCurrentLine,
                                      std::strlen(kMakeCurrentLine)));
}

TEST(ignores_ordinary_output) {
  const char* ordinary[] = {
      "flutter: hello",
      "[2026-09-01 18:15:10.064 (UTC+0000)] info/channel TCP | ok",
      "2026-09-01 18:18:07.982 [gpu-watchdog] tick: missed 0/2",
      "",
  };
  for (const char* line : ordinary) {
    CHECK(!EglStormDetector::LineMatches(line, std::strlen(line)));
  }
}

TEST(nine_matches_stay_silent_the_tenth_fires) {
  EglStormDetector detector(Tight());
  for (int i = 0; i < 9; i++) {
    CHECK(!FeedLine(detector, kContextLostLine, 1000 + i));
  }
  CHECK(FeedLine(detector, kContextLostLine, 1009));
}

TEST(a_slow_trickle_never_fires) {
  // One matching line every six seconds is a context loss the engine keeps
  // recovering from -- or log replay -- not a storm. The window must expire
  // between them.
  EglStormDetector detector(Tight());
  unsigned long long now = 1000;
  for (int i = 0; i < 50; i++) {
    CHECK(!FeedLine(detector, kMakeCurrentLine, now));
    now += 6000;
  }
}

TEST(the_window_resets_rather_than_accumulating) {
  EglStormDetector detector(Tight());
  for (int i = 0; i < 5; i++) {
    CHECK(!FeedLine(detector, kContextLostLine, 1000 + i));
  }
  // Past the window: the five above no longer count.
  CHECK(!FeedLine(detector, kContextLostLine, 7001));
  for (int i = 0; i < 8; i++) {
    CHECK(!FeedLine(detector, kContextLostLine, 7002 + i));
  }
  // Tenth inside the fresh window.
  CHECK(FeedLine(detector, kContextLostLine, 7010));
}

TEST(cooldown_swallows_the_continuing_storm_then_rearms) {
  EglStormDetector detector(Tight());
  unsigned long long now = 1000;
  for (int i = 0; i < 9; i++) {
    FeedLine(detector, kContextLostLine, now++);
  }
  CHECK(FeedLine(detector, kContextLostLine, now++));

  // 53 lines per second for the whole cooldown: not one refire.
  for (int i = 0; i < 500; i++) {
    CHECK(!FeedLine(detector, kContextLostLine, now));
    now += 19;
  }

  // Cooldown over (10 s after the fire); the storm is still running, so the
  // detector must be able to say so again.
  now += 10000;
  bool refired = false;
  for (int i = 0; i < 10; i++) {
    refired = FeedLine(detector, kContextLostLine, now + i);
  }
  CHECK(refired);
}

TEST(bytes_are_split_into_lines_across_chunk_boundaries) {
  EglStormDetector detector(Tight());
  // One matching line delivered in three reads, cut inside the needle.
  std::string line = std::string(kContextLostLine) + "\n";
  const std::size_t first_cut = 30;   // inside "EGL Error: Cont|ext Lost"
  const std::size_t second_cut = 60;
  CHECK(!detector.OnBytes(line.data(), first_cut, 1000));
  CHECK(!detector.OnBytes(line.data() + first_cut, second_cut - first_cut,
                          1001));
  // Completing the line is the 1st match of 10 -- no fire, but it counted.
  CHECK(!detector.OnBytes(line.data() + second_cut, line.size() - second_cut,
                          1002));
  CHECK_EQ(static_cast<int>(detector.matches_in_window()), 1);
}

TEST(a_burst_in_one_read_fires) {
  EglStormDetector detector(Tight());
  std::string burst;
  for (int i = 0; i < 12; i++) {
    burst += kMakeCurrentLine;
    burst += "\n";
  }
  CHECK(detector.OnBytes(burst.data(), burst.size(), 1000));
}

TEST(crlf_line_endings_still_match) {
  EglStormDetector detector(Tight());
  std::string burst;
  for (int i = 0; i < 10; i++) {
    burst += kContextLostLine;
    burst += "\r\n";
  }
  CHECK(detector.OnBytes(burst.data(), burst.size(), 1000));
}

TEST(a_needle_in_an_endless_line_is_not_lost) {
  // A writer that never flushes a newline must not buffer forever; the carry
  // cap feeds what it has, and a needle inside it still counts.
  EglStormDetector detector(Tight());
  std::string endless(3000, 'x');
  endless += kContextLostLine;
  endless += std::string(3000, 'y');  // > 4096 total, no newline anywhere
  detector.OnBytes(endless.data(), endless.size(), 1000);
  CHECK_EQ(static_cast<int>(detector.matches_in_window()), 1);
}

}  // namespace

int main() { return tfc_test::RunAll(); }
