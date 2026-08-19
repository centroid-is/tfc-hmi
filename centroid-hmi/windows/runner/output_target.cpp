#include "output_target.h"

namespace tfc {

OutputTarget ChooseOutputTarget(const OutputTargetInputs& inputs) {
  // Someone is already reading stdout — `flutter run`, a terminal, a shell
  // redirect. Taking it away from them is never what was wanted, and naming a
  // log file is not a request to.
  //
  // CENTROID_LOG_FILE used to win here, on the reasoning that naming a file is
  // unambiguous. It is — about the file, not about stdout. The Dart side
  // writes that same file directly (see initLogConfig), so redirecting as well
  // gives one file two owners with independent offsets, and the runner
  // signals CENTROID_LOG_REDIRECTED to make the Dart writer stand down for
  // the one it cannot verify carries anything. Leaving the streams alone keeps
  // the in-process writer -- the one that needs no handle plumbing to be
  // correct -- as the single owner, and stdout still reaches whoever is
  // reading it.
  if (inputs.stdout_connected) {
    return OutputTarget::kInherited;
  }

  // A console was asked for and will be allocated; sending output to a file
  // instead would make the flag do the opposite of what it says.
  if (inputs.console_requested) {
    return OutputTarget::kInherited;
  }

  // Nothing is listening, but a file was named: it is the only destination
  // left, and now the runner really is the only writer.
  if (inputs.explicit_log_file) {
    return OutputTarget::kFile;
  }

  // Windowed launch with nothing attached: the file is the only destination
  // that survives.
  return OutputTarget::kFile;
}

}  // namespace tfc
