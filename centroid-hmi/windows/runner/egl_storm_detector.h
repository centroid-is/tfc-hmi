#ifndef RUNNER_EGL_STORM_DETECTOR_H_
#define RUNNER_EGL_STORM_DETECTOR_H_

#include <cstddef>
#include <string>

// Recognises an EGL context-loss storm in the engine's own error output.
//
// This exists because every polite way of asking about the renderer's health
// answers wrongly for this class of loss, and each was disproven by a real
// freeze on 2026-09-01 (see flutter_window.h, RebuildForSessionChange):
//
//   * the D3D11 sentinel watches the adapter, and the adapter stays healthy;
//   * the frame probe watches SetNextFrameCallback, which the engine answers
//     from the UI thread whether or not rasterisation succeeded;
//   * ANGLE's own device is unreachable from the runner -- the engine
//     statically links its own ANGLE with no exported EGL entry points
//     (measured 2026-08-31; see the note in gpu_diagnosis.h).
//
// What the incident DID produce was the engine writing
//
//   EGL Error: Context Lost (12302) ...
//   Could not make the context current to acquire the frame.
//
// to stderr 283,525 times over 89 minutes at 53 lines per second, while every
// other signal reported healthy. That stream is the one honest witness, so
// the runner reads it (see StderrInterposer) and this class decides when the
// lines amount to a storm rather than a one-off blip a recovered context can
// leave behind.
//
// Pure logic, no I/O and no Windows headers, so the thresholds are testable
// the same way GpuWatchdog's are.

namespace tfc {

class EglStormDetector {
 public:
  struct Config {
    // Lines that must match within one window before the storm is declared.
    // A real storm arrives at tens per second; a transient loss the engine
    // recovers from on its own produces a handful. Ten within five seconds
    // is far above the second and far below the first.
    unsigned int min_matches = 10;
    unsigned long long window_ms = 5000;
    // After firing, stay quiet this long. The watchdog's own reported_loss_
    // latch deduplicates reports, but there is no point waking the platform
    // thread 53 times a second while the loss is already being handled.
    unsigned long long refire_cooldown_ms = 10000;
  };

  EglStormDetector() : EglStormDetector(Config()) {}
  explicit EglStormDetector(Config config) : config_(config) {}

  // Whether one line of engine output is part of a context-loss storm.
  static bool LineMatches(const char* line, std::size_t length);

  // Feed one complete line. Returns true exactly when the threshold is
  // crossed; then goes quiet for refire_cooldown_ms.
  bool OnLine(const char* line, std::size_t length, unsigned long long now_ms);

  // Feed raw bytes as they come off the pipe; lines are split internally and
  // a partial trailing line is carried into the next call. Returns true if
  // any completed line crossed the threshold.
  bool OnBytes(const char* data, std::size_t length, unsigned long long now_ms);

  unsigned int matches_in_window() const { return matches_; }

 private:
  Config config_;
  unsigned int matches_ = 0;
  unsigned long long window_start_ms_ = 0;
  unsigned long long quiet_until_ms_ = 0;
  // Bytes after the last newline, waiting for the rest of their line. Bounded:
  // a pathological line with no newline is fed as-is once the cap is reached,
  // so a storm that somehow never flushes newlines still counts.
  std::string carry_;
};

}  // namespace tfc

#endif  // RUNNER_EGL_STORM_DETECTOR_H_
