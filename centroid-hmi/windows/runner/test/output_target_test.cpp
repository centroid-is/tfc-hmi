// Tests for deciding where the runner sends stdout/stderr.
//
// The runner is a WIN32-subsystem app, so "is there a console?" is the obvious
// question and the wrong one. `flutter run` — and therefore the VS Code
// debugger — launches it with stdout and stderr wired to pipes and no console
// at all. Redirecting to a log file in that situation silently empties the
// Debug Console, which is exactly when a developer is watching it.

#include "../output_target.h"

#include "test_harness.h"

namespace {

using tfc::ChooseOutputTarget;
using tfc::OutputTarget;
using tfc::OutputTargetInputs;

// Nothing set, nothing listening: an MSIX or Explorer launch.
OutputTargetInputs WindowedLaunch() {
  OutputTargetInputs inputs;
  inputs.explicit_log_file = false;
  inputs.console_requested = false;
  inputs.stdout_connected = false;
  return inputs;
}

}  // namespace

TEST(a_windowed_launch_has_nowhere_to_write_so_it_gets_the_file) {
  CHECK(ChooseOutputTarget(WindowedLaunch()) == OutputTarget::kFile);
}

TEST(a_connected_stdout_is_left_alone) {
  OutputTargetInputs inputs = WindowedLaunch();
  inputs.stdout_connected = true;

  // This is `flutter run` and the VS Code debugger: no console, but stdout is
  // a pipe the tool is reading. Redirecting it to a file is what makes the
  // Debug Console go silent.
  CHECK(ChooseOutputTarget(inputs) == OutputTarget::kInherited);
}

TEST(requesting_a_console_keeps_output_on_it) {
  OutputTargetInputs inputs = WindowedLaunch();
  inputs.console_requested = true;

  // CENTROID_STDOUT=1 allocates a console; sending output to a file instead
  // would make the flag do the opposite of what it says.
  CHECK(ChooseOutputTarget(inputs) == OutputTarget::kInherited);
}

TEST(an_explicit_log_file_does_not_take_over_a_connected_stdout) {
  OutputTargetInputs inputs = WindowedLaunch();
  inputs.stdout_connected = true;
  inputs.explicit_log_file = true;

  // This is run-hmi.ps1: CENTROID_LOG_FILE named, `flutter run` reading
  // stdout. Naming a file says where the log goes, not that stdout should
  // stop reaching its reader. The Dart side writes that file from inside the
  // process, so redirecting here would give one file two writers -- and it
  // is the redirect, not the in-process writer, that has to be right about
  // handles for anything to be recorded at all.
  CHECK(ChooseOutputTarget(inputs) == OutputTarget::kInherited);
}

TEST(an_explicit_log_file_does_not_cancel_a_requested_console) {
  OutputTargetInputs inputs = WindowedLaunch();
  inputs.console_requested = true;
  inputs.explicit_log_file = true;

  // Same reasoning: the console was asked for and still gets the output; the
  // file is written by the Dart side.
  CHECK(ChooseOutputTarget(inputs) == OutputTarget::kInherited);
}

TEST(everything_at_once_leaves_the_streams_alone) {
  OutputTargetInputs inputs;
  inputs.explicit_log_file = true;
  inputs.console_requested = true;
  inputs.stdout_connected = true;

  CHECK(ChooseOutputTarget(inputs) == OutputTarget::kInherited);
}

TEST(a_named_file_is_used_when_nothing_is_listening) {
  OutputTargetInputs inputs = WindowedLaunch();
  inputs.explicit_log_file = true;

  // Windowed launch with a path named by hand: the runner is the only
  // possible writer, so it takes the file and tells the Dart side to stand
  // down via CENTROID_LOG_REDIRECTED.
  CHECK(ChooseOutputTarget(inputs) == OutputTarget::kFile);
}

int main() {
  std::printf("output_target_test\n");
  return tfc_test::RunAll();
}
