// Copyright (c) Centroid. Part of CentroidX.
//
// Pure geometry helpers for the eLinux media_kit video output. Nothing in
// here touches Flutter, mpv or the process — it is the part of the plugin
// that can be unit tested on any host (see test/video_geometry_test.cc).

#ifndef MEDIA_KIT_VIDEO_ELINUX_VIDEO_GEOMETRY_H_
#define MEDIA_KIT_VIDEO_ELINUX_VIDEO_GEOMETRY_H_

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>

namespace media_kit_video_elinux {

// Upper bound on a software-rendered frame. Every frame is scaled by the CPU
// and then uploaded as a whole texture, so an unbounded size is a way to make
// a station unresponsive rather than a way to show more detail. Same budget
// upstream's GNU/Linux S/W path uses.
inline constexpr int64_t kMaxRenderWidth = 1920;
inline constexpr int64_t kMaxRenderHeight = 1080;

struct Size {
  int64_t width = 0;
  int64_t height = 0;

  bool IsEmpty() const { return width <= 0 || height <= 0; }
};

bool operator==(const Size& a, const Size& b);
bool operator!=(const Size& a, const Size& b);

// package:media_kit_video sends every dimension as a string, using the
// literal "null" for "no opinion". Returns nullopt for "null", for anything
// that is not a whole positive number, and for trailing garbage — a bogus
// dimension must degrade to "no opinion", never to a negative allocation.
std::optional<int64_t> ParseNullableInt(const std::string& value);

// Scales `size` down to fit inside the render budget, preserving aspect
// ratio. Sizes already inside the budget are returned unchanged; an empty
// size stays empty. Never returns a zero dimension for a non-empty input.
Size FitWithinRenderBudget(Size size);

// The size to actually render at: an explicitly requested size wins over the
// video's own dimensions, and the winner is fitted to the budget. A partially
// specified request (only a width, say) is not a size and falls back to the
// video's.
Size ResolveRenderSize(const Size& requested, const Size& video);

// The size to report to Dart. A zero size is reported as 1x1 so that the
// `Texture` widget actually mounts: Flutter never asks for a frame of a
// texture it has not laid out, and a texture that is never asked for never
// produces the frame that would give it a real size.
Size NotifiableSize(const Size& size);

// Bytes per row and total bytes for a 4-bytes-per-pixel frame.
int32_t StrideBytes(const Size& size);
size_t PixelBufferBytes(const Size& size);

}  // namespace media_kit_video_elinux

#endif  // MEDIA_KIT_VIDEO_ELINUX_VIDEO_GEOMETRY_H_
