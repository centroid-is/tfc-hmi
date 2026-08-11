#include "output_target.h"

namespace tfc {

OutputTarget ChooseOutputTarget(const OutputTargetInputs& inputs) {
  // Naming a file is unambiguous and wins over everything: it is how you
  // capture a session that is also being watched in a terminal.
  if (inputs.explicit_log_file) {
    return OutputTarget::kFile;
  }

  // A console was asked for and will be allocated; sending output to a file
  // instead would make the flag do the opposite of what it says.
  if (inputs.console_requested) {
    return OutputTarget::kInherited;
  }

  // Someone is already reading stdout — `flutter run`, a terminal, a shell
  // redirect. Taking it away from them is never what was wanted.
  if (inputs.stdout_connected) {
    return OutputTarget::kInherited;
  }

  // Windowed launch with nothing attached: the file is the only destination
  // that survives.
  return OutputTarget::kFile;
}

}  // namespace tfc
