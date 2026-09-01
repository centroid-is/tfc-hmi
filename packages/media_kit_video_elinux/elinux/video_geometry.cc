// Copyright (c) Centroid. Part of CentroidX.

#include "video_geometry.h"

#include <algorithm>
#include <charconv>
#include <cmath>

namespace media_kit_video_elinux {

bool operator==(const Size& a, const Size& b) {
  return a.width == b.width && a.height == b.height;
}

bool operator!=(const Size& a, const Size& b) {
  return !(a == b);
}

std::optional<int64_t> ParseNullableInt(const std::string& value) {
  int64_t parsed = 0;
  const char* begin = value.data();
  const char* end = begin + value.size();
  const auto result = std::from_chars(begin, end, parsed);
  // Anything left over ("12abc", "12.0") is not a dimension either.
  if (result.ec != std::errc() || result.ptr != end || parsed <= 0) {
    return std::nullopt;
  }
  return parsed;
}

Size FitWithinRenderBudget(Size size) {
  if (size.IsEmpty()) {
    return Size{};
  }
  const double scale =
      std::min(static_cast<double>(kMaxRenderWidth) / size.width,
               static_cast<double>(kMaxRenderHeight) / size.height);
  if (scale >= 1.0) {
    return size;
  }
  // Rounding can land a hair over the budget; the clamp is what the budget
  // actually promises, the rounding only decides which side of a pixel we
  // land on. A dimension never scales away to nothing.
  const int64_t width = std::llround(static_cast<double>(size.width) * scale);
  const int64_t height = std::llround(static_cast<double>(size.height) * scale);
  return Size{std::clamp<int64_t>(width, 1, kMaxRenderWidth),
              std::clamp<int64_t>(height, 1, kMaxRenderHeight)};
}

Size ResolveRenderSize(const Size& requested, const Size& video) {
  return FitWithinRenderBudget(requested.IsEmpty() ? video : requested);
}

Size NotifiableSize(const Size& size) {
  return size.IsEmpty() ? Size{1, 1} : size;
}

int32_t StrideBytes(const Size& size) {
  return static_cast<int32_t>(size.IsEmpty() ? 0 : size.width * 4);
}

size_t PixelBufferBytes(const Size& size) {
  if (size.IsEmpty()) {
    return 0;
  }
  return static_cast<size_t>(size.width) * static_cast<size_t>(size.height) * 4;
}

}  // namespace media_kit_video_elinux
