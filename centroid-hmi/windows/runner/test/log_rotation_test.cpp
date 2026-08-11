// Tests for log file rotation planning.
//
// Rotation is where post-mortem logs get silently destroyed: rename in the
// wrong order and each generation overwrites the next, leaving one file. Since
// the whole point of this code is to still have the log after a crash, the plan
// is computed as pure data here and merely executed by the platform layer.

#include "../log_rotation.h"

#include "test_harness.h"

#include <string>

namespace {

using tfc::LogRotationPlan;

std::string Renames(const LogRotationPlan& plan) {
  std::string out;
  for (const auto& rename : plan.renames) {
    if (!out.empty()) out += " ; ";
    out += rename.first + " -> " + rename.second;
  }
  return out;
}

std::string Deletes(const LogRotationPlan& plan) {
  std::string out;
  for (const auto& path : plan.deletes) {
    if (!out.empty()) out += " ; ";
    out += path;
  }
  return out;
}

}  // namespace

// --- Generation paths -------------------------------------------------------

TEST(generation_zero_is_the_live_file) {
  CHECK_EQ(tfc::GenerationPath("C:\\logs\\hmi.log", 0),
           std::string("C:\\logs\\hmi.log"));
}

TEST(generation_number_goes_before_the_extension) {
  // Keeps the .log extension so file associations and log viewers still work.
  CHECK_EQ(tfc::GenerationPath("C:\\logs\\hmi.log", 1),
           std::string("C:\\logs\\hmi.1.log"));
  CHECK_EQ(tfc::GenerationPath("C:\\logs\\hmi.log", 12),
           std::string("C:\\logs\\hmi.12.log"));
}

TEST(generation_path_handles_a_base_with_no_extension) {
  CHECK_EQ(tfc::GenerationPath("hmi", 3), std::string("hmi.3"));
}

TEST(generation_path_ignores_dots_in_the_directory) {
  // The naive "last dot in the string" search picks the directory's dot and
  // produces C:\a.1.b\hmi.log — a path in a directory that does not exist.
  CHECK_EQ(tfc::GenerationPath("C:\\a.b\\hmi.log", 1),
           std::string("C:\\a.b\\hmi.1.log"));
  CHECK_EQ(tfc::GenerationPath("C:\\a.b\\hmi", 1), std::string("C:\\a.b\\hmi.1"));
}

TEST(generation_path_accepts_forward_slashes) {
  CHECK_EQ(tfc::GenerationPath("/var/log/hmi.log", 2),
           std::string("/var/log/hmi.2.log"));
}

// --- Rotation plan ----------------------------------------------------------

TEST(rotation_renames_oldest_first_so_nothing_is_clobbered) {
  LogRotationPlan plan = tfc::PlanRotation("hmi.log", 3);

  // Descending order is the whole point: renaming hmi.1 -> hmi.2 before
  // hmi.2 -> hmi.3 would destroy generation 2.
  CHECK_EQ(Renames(plan),
           std::string("hmi.2.log -> hmi.3.log ; "
                       "hmi.1.log -> hmi.2.log ; "
                       "hmi.log -> hmi.1.log"));
}

TEST(rotation_drops_the_generation_that_falls_off_the_end) {
  LogRotationPlan plan = tfc::PlanRotation("hmi.log", 3);

  CHECK_EQ(Deletes(plan), std::string("hmi.3.log"));
}

TEST(keeping_one_archive_still_preserves_the_previous_run) {
  LogRotationPlan plan = tfc::PlanRotation("hmi.log", 1);

  CHECK_EQ(Deletes(plan), std::string("hmi.1.log"));
  CHECK_EQ(Renames(plan), std::string("hmi.log -> hmi.1.log"));
}

TEST(keeping_no_archives_deletes_the_live_file_and_renames_nothing) {
  LogRotationPlan plan = tfc::PlanRotation("hmi.log", 0);

  CHECK_EQ(Deletes(plan), std::string("hmi.log"));
  CHECK_EQ(Renames(plan), std::string(""));
}

TEST(a_negative_archive_count_is_treated_as_zero) {
  LogRotationPlan plan = tfc::PlanRotation("hmi.log", -5);

  CHECK_EQ(Deletes(plan), std::string("hmi.log"));
  CHECK_EQ(Renames(plan), std::string(""));
}

TEST(every_renamed_generation_is_within_the_archive_limit) {
  const int kMaxArchives = 4;
  LogRotationPlan plan = tfc::PlanRotation("hmi.log", kMaxArchives);

  // Nothing may be renamed to a generation above the limit, or rotation grows
  // without bound and the disk fills — the exact failure this replaces.
  for (const auto& rename : plan.renames) {
    CHECK(rename.second != tfc::GenerationPath("hmi.log", kMaxArchives + 1));
  }
  CHECK_EQ(static_cast<int>(plan.renames.size()), kMaxArchives);
}

int main() {
  std::printf("log_rotation_test\n");
  return tfc_test::RunAll();
}
