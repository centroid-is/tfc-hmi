#ifndef RUNNER_LOG_ROTATION_H_
#define RUNNER_LOG_ROTATION_H_

// Log file rotation planning.
//
// The runner writes its log to a fixed path so it can be found without knowing
// where the app was launched from. That path has to be reused across runs,
// which means the previous run's log — the interesting one, after a crash —
// must be moved aside rather than truncated.
//
// The plan is computed here as pure data, with no filesystem access, so the
// rename ordering can be unit tested. Getting that order wrong silently
// collapses every generation into one file, which is invisible until the day
// you actually need the history.

#include <string>
#include <utility>
#include <vector>

namespace tfc {

struct LogRotationPlan {
  // Files to remove, before any renames.
  std::vector<std::string> deletes;

  // Renames to perform, in the given order.
  std::vector<std::pair<std::string, std::string>> renames;
};

// Path of archive generation |generation| of |base|. Generation 0 is |base|
// itself. The number is inserted before the extension ("hmi.log" -> "hmi.1.log")
// so archives keep the .log extension.
std::string GenerationPath(const std::string& base, int generation);

// Plan a rotation of |base| keeping |max_archives| previous generations.
// max_archives <= 0 means keep nothing: the live file is simply deleted.
LogRotationPlan PlanRotation(const std::string& base, int max_archives);

}  // namespace tfc

#endif  // RUNNER_LOG_ROTATION_H_
