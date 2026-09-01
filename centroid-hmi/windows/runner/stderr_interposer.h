#ifndef RUNNER_STDERR_INTERPOSER_H_
#define RUNNER_STDERR_INTERPOSER_H_

#include <functional>
#include <thread>

#include "egl_storm_detector.h"

// Puts a pipe in front of the process's stderr so the runner can READ what
// the engine writes there, forwarding every byte to wherever stderr pointed
// before, unchanged.
//
// Why this works: flutter_windows.dll and the runner share the dynamic CRT,
// so fd 2 is one table entry for the whole process. Measured 2026-09-01: when
// the runner reopened CONOUT$ on stderr, the ENGINE's EGL error lines
// followed it -- which is the same mechanism this class relies on, pointed
// the other way.
//
// Why it exists: during the 2026-09-01 freeze the engine's stderr was the
// only signal that said the truth (283,525 context-lost lines while every
// probe reported healthy), and the runner was the one observer in a position
// to read it and act.
//
// Installed once, never removed: the pipe, the duplicated original fd and the
// reader thread live for the process. Restoring stderr mid-flight while other
// threads write to it buys nothing and races everything.
//
// Deliberately tested through a real pipe (see stderr_interposer_test.cpp)
// rather than mocked: every line here is an fd operation, and the detector it
// feeds carries the logic worth unit testing on its own.

namespace tfc {

class StderrInterposer {
 public:
  // Called from the READER THREAD when the detector declares a storm. Keep it
  // to a PostMessage; the platform thread does the thinking.
  using StormCallback = std::function<void(unsigned int matches_in_window)>;

  // Interposes fd 2 and STD_ERROR_HANDLE and starts the reader thread.
  // Returns false -- leaving stderr exactly as it was -- if any step fails.
  bool Install(EglStormDetector::Config config, StormCallback on_storm);

  bool installed() const { return installed_; }

  StderrInterposer() = default;
  StderrInterposer(const StderrInterposer&) = delete;
  StderrInterposer& operator=(const StderrInterposer&) = delete;

 private:
  void ReaderLoop();

  EglStormDetector detector_;
  StormCallback on_storm_;
  int pipe_read_fd_ = -1;
  int original_stderr_fd_ = -1;
  bool installed_ = false;
  std::thread reader_;
};

}  // namespace tfc

#endif  // RUNNER_STDERR_INTERPOSER_H_
