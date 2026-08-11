#ifndef RUNNER_OUTPUT_TARGET_H_
#define RUNNER_OUTPUT_TARGET_H_

// Deciding where the runner sends stdout and stderr.
//
// The runner is built WIN32-subsystem, so the instinctive question is "is a
// console attached?" — and that is the wrong one. `flutter run`, and therefore
// the VS Code debugger, launches the app with stdout and stderr wired to pipes
// and no console at all. What matters is whether *anything* is already
// listening, console or pipe.
//
// Get this wrong towards the file and a developer's Debug Console goes silent.
// Get it wrong towards the stream and a packaged app writes its diagnostics to
// a handle nobody holds, which is how a crash ends up with no log.

namespace tfc {

enum class OutputTarget {
  // Something is already reading stdout — a console, or the pipe `flutter run`
  // set up. Leave the streams alone.
  kInherited,

  // Nothing is listening. Redirect to the log file, or the output is lost.
  kFile,
};

struct OutputTargetInputs {
  // CENTROID_LOG_FILE names a file explicitly.
  bool explicit_log_file = false;

  // CENTROID_STDOUT asks for a console.
  bool console_requested = false;

  // stdout is already a valid handle: a console, or a pipe from a parent
  // process such as the flutter tool.
  bool stdout_connected = false;
};

OutputTarget ChooseOutputTarget(const OutputTargetInputs& inputs);

}  // namespace tfc

#endif  // RUNNER_OUTPUT_TARGET_H_
