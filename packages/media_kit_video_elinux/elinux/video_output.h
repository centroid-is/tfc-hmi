// Copyright (c) Centroid. Part of CentroidX.
//
// One software-rendered video output per libmpv handle: an mpv render context
// writing RGBA frames into a buffer that is handed to the eLinux embedder as
// a pixel-buffer texture.
//
// Hardware rendering is deliberately not offered. mpv's OpenGL render API
// needs the embedder's EGL context, and flutter-elinux exposes no way for a
// plugin to reach it; software rendering is what is actually available here.

#ifndef MEDIA_KIT_VIDEO_ELINUX_VIDEO_OUTPUT_H_
#define MEDIA_KIT_VIDEO_ELINUX_VIDEO_OUTPUT_H_

#include <flutter/texture_registrar.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "mpv_library.h"
#include "video_geometry.h"

namespace media_kit_video_elinux {

class VideoOutput {
 public:
  VideoOutput(mpv_handle* handle,
              const MpvApi* mpv,
              flutter::TextureRegistrar* texture_registrar);
  ~VideoOutput();

  VideoOutput(const VideoOutput&) = delete;
  VideoOutput& operator=(const VideoOutput&) = delete;

  // Creates the render context and registers the texture. On failure returns
  // false and describes why in `error`.
  bool Initialize(const Size& requested_size, std::string* error);

  // Stops rendering and unregisters the texture. `keep_alive` is released
  // once the render thread is known to be done with this output, so pass the
  // owning reference: the texture callback runs on another thread and must
  // not outlive the object it reads from.
  void Shutdown(std::shared_ptr<VideoOutput> keep_alive);

  int64_t texture_id() const { return texture_id_; }

  // The size media_kit asked for, "no opinion" being an empty size.
  void SetRequestedSize(const Size& size);

  // The size frames are currently rendered at.
  Size CurrentSize();

 private:
  // Invoked by the embedder's render thread when it wants a frame.
  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width, size_t height);

  // Invoked by mpv, from whichever thread it pleases, when a new frame is
  // ready. Only marks the texture dirty — the frame itself is rendered in
  // CopyPixelBuffer, on the thread that is going to upload it.
  void OnMpvRenderUpdate();

  Size CurrentSizeLocked();
  Size VideoSizeFromMpvLocked();

  mpv_handle* handle_ = nullptr;
  const MpvApi* mpv_ = nullptr;
  flutter::TextureRegistrar* texture_registrar_ = nullptr;
  mpv_render_context* render_context_ = nullptr;

  std::unique_ptr<flutter::TextureVariant> texture_;
  FlutterDesktopPixelBuffer buffer_descriptor_ = {};
  std::vector<uint8_t> pixels_;
  int64_t texture_id_ = -1;

  std::mutex mutex_;
  Size requested_size_;
  bool shut_down_ = false;
};

}  // namespace media_kit_video_elinux

#endif  // MEDIA_KIT_VIDEO_ELINUX_VIDEO_OUTPUT_H_
