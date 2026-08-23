#include "path_utils.h"

namespace tfc {

std::string DirectoryOf(const std::string& path) {
  std::string::size_type slash = path.find_last_of("/\\");
  if (slash == std::string::npos) return std::string();
  return path.substr(0, slash);
}

size_t Utf8LengthWithoutNul(int wide_to_utf8_result) {
  if (wide_to_utf8_result <= 1) {
    // 0 is the failure return; 1 is a string consisting only of the NUL. Both
    // mean there is nothing to convert.
    return 0;
  }
  return static_cast<size_t>(wide_to_utf8_result) - 1;
}

}  // namespace tfc
