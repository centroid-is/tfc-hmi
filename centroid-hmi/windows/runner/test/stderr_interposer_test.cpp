// End-to-end test of the stderr interposition, through a real pipe and a real
// reader thread, because every line of the interposer is an fd operation and a
// mock would test the mock.
//
// Windows-only, like the code under test. The detector's logic has its own
// platform-free suite in egl_storm_detector_test.cpp.
//
// Order matters inside this file: Install() is process-lifetime by design, so
// everything here shares one interposed stderr. The test redirects fd 2 to a
// temp file FIRST, so "the original target" is something whose bytes can be
// read back and checked.

#include "../stderr_interposer.h"

#include <fcntl.h>
#include <io.h>
#include <sys/stat.h>
#include <windows.h>

#include <atomic>
#include <cstdio>
#include <cstring>
#include <string>

#include "test_harness.h"

namespace {

constexpr const char* kStormLine =
    "[ERROR:flutter/shell/platform/windows/egl/egl.cc(57)] EGL Error: "
    "Context Lost (12302) in surface.cc:52\n";

std::atomic<int> g_storms{0};
std::atomic<unsigned int> g_last_matches{0};

std::string TempFilePath() {
  char dir[MAX_PATH];
  ::GetTempPathA(MAX_PATH, dir);
  char path[MAX_PATH];
  ::GetTempFileNameA(dir, "sit", 0, path);
  return path;
}

TEST(storm_on_real_stderr_reaches_the_callback_and_the_original_target) {
  // Point stderr at a file we can read back, BEFORE interposing: that file
  // then plays the role of "wherever stderr pointed before".
  const std::string capture_path = TempFilePath();
  const int capture_fd =
      _open(capture_path.c_str(), _O_CREAT | _O_TRUNC | _O_RDWR | _O_BINARY,
            _S_IREAD | _S_IWRITE);
  CHECK(capture_fd != -1);
  CHECK_EQ(_dup2(capture_fd, 2), 0);

  tfc::StderrInterposer interposer;
  tfc::EglStormDetector::Config config;
  config.min_matches = 10;
  config.window_ms = 5000;
  config.refire_cooldown_ms = 10000;
  CHECK(interposer.Install(config, [](unsigned int matches) {
    g_last_matches.store(matches);
    g_storms.fetch_add(1);
  }));
  CHECK(interposer.installed());

  // Below threshold: nine lines, plus noise that must pass through unharmed.
  const char* noise = "flutter: perfectly ordinary output\n";
  for (int i = 0; i < 9; i++) {
    _write(2, kStormLine, static_cast<unsigned int>(std::strlen(kStormLine)));
  }
  _write(2, noise, static_cast<unsigned int>(std::strlen(noise)));
  ::Sleep(300);
  CHECK_EQ(g_storms.load(), 0);

  // The tenth crosses it.
  _write(2, kStormLine, static_cast<unsigned int>(std::strlen(kStormLine)));
  for (int waited = 0; waited < 2000 && g_storms.load() == 0; waited += 50) {
    ::Sleep(50);
  }
  CHECK_EQ(g_storms.load(), 1);

  // Every byte -- storm and noise alike -- must have reached the original
  // target. Give the reader a beat to finish forwarding.
  ::Sleep(300);
  FILE* readback = std::fopen(capture_path.c_str(), "rb");
  CHECK(readback != nullptr);
  std::string contents;
  char buffer[512];
  size_t n;
  while ((n = std::fread(buffer, 1, sizeof(buffer), readback)) > 0) {
    contents.append(buffer, n);
  }
  std::fclose(readback);

  int forwarded_storm_lines = 0;
  size_t at = 0;
  while ((at = contents.find("EGL Error: Context Lost", at)) !=
         std::string::npos) {
    forwarded_storm_lines++;
    at += 1;
  }
  CHECK_EQ(forwarded_storm_lines, 10);
  CHECK(contents.find("perfectly ordinary output") != std::string::npos);
}

}  // namespace

int main() { return tfc_test::RunAll(); }
