#include "log_rotation.h"

namespace tfc {
namespace {

// Offset of the extension dot in |path|, or npos if the filename has none.
// Only dots after the last path separator count — directories may contain dots
// and inserting the generation there yields a path that does not exist.
std::string::size_type ExtensionDot(const std::string& path) {
  std::string::size_type slash = path.find_last_of("/\\");
  std::string::size_type dot = path.find_last_of('.');
  if (dot == std::string::npos) {
    return std::string::npos;
  }
  if (slash != std::string::npos && dot < slash) {
    return std::string::npos;
  }
  return dot;
}

}  // namespace

std::string GenerationPath(const std::string& base, int generation) {
  if (generation <= 0) {
    return base;
  }
  const std::string suffix = "." + std::to_string(generation);
  std::string::size_type dot = ExtensionDot(base);
  if (dot == std::string::npos) {
    return base + suffix;
  }
  return base.substr(0, dot) + suffix + base.substr(dot);
}

LogRotationPlan PlanRotation(const std::string& base, int max_archives) {
  LogRotationPlan plan;

  if (max_archives <= 0) {
    plan.deletes.push_back(base);
    return plan;
  }

  // The oldest generation has nowhere left to go.
  plan.deletes.push_back(GenerationPath(base, max_archives));

  // Walk downwards so each destination is free before it is written to.
  for (int generation = max_archives - 1; generation >= 0; generation--) {
    plan.renames.emplace_back(GenerationPath(base, generation),
                              GenerationPath(base, generation + 1));
  }

  return plan;
}

}  // namespace tfc
