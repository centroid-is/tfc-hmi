// Copyright (c) Centroid. Part of CentroidX.

#include "video_output.h"

#include <cstring>
#include <iostream>

namespace media_kit_video_elinux {
namespace {

// mpv writes R, G, B and a padding byte; the embedder uploads the buffer as
// GL_RGBA. Same format upstream's GNU/Linux software path uses.
constexpr const char* kSoftwareFormat = "rgb0";

}  // namespace

VideoOutput::VideoOutput(mpv_handle* handle,
                         const MpvApi* mpv,
                         flutter::TextureRegistrar* texture_registrar)
    : handle_(handle), mpv_(mpv), texture_registrar_(texture_registrar) {}

VideoOutput::~VideoOutput() {
  // mpv allows only one mpv_render_* call at a time, and CopyPixelBuffer runs
  // on another thread; the lock is what makes "no render is in flight" true
  // rather than merely likely.
  std::lock_guard<std::mutex> lock(mutex_);
  shut_down_ = true;
  if (render_context_ != nullptr) {
    mpv_->render_context_set_update_callback(render_context_, nullptr, nullptr);
    mpv_->render_context_free(render_context_);
    render_context_ = nullptr;
  }
}

bool VideoOutput::Initialize(const Size& requested_size, std::string* error) {
  requested_size_ = requested_size;

  texture_ =
      std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
          [this](size_t width, size_t height) -> const FlutterDesktopPixelBuffer* {
            return CopyPixelBuffer(width, height);
          }));
  texture_id_ = texture_registrar_->RegisterTexture(texture_.get());
  if (texture_id_ < 0) {
    *error = "The embedder refused to register a pixel buffer texture.";
    return false;
  }

  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE,
       const_cast<char*>(MPV_RENDER_API_TYPE_SW)},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  const int status =
      mpv_->render_context_create(&render_context_, handle_, params);
  if (status != 0) {
    texture_registrar_->UnregisterTexture(texture_id_, nullptr);
    texture_id_ = -1;
    *error = "mpv_render_context_create failed with status " +
             std::to_string(status) + ".";
    return false;
  }

  // Nothing but marking the texture dirty may happen in here: mpv forbids
  // calling any mpv_render_* function from inside this callback.
  mpv_->render_context_set_update_callback(
      render_context_,
      [](void* context) {
        static_cast<VideoOutput*>(context)->OnMpvRenderUpdate();
      },
      this);
  return true;
}

void VideoOutput::Shutdown(std::shared_ptr<VideoOutput> keep_alive) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    shut_down_ = true;
  }
  // Stop mpv first: an update callback arriving after the texture is gone
  // would mark a texture id the embedder has already forgotten.
  if (render_context_ != nullptr) {
    mpv_->render_context_set_update_callback(render_context_, nullptr, nullptr);
  }
  if (texture_id_ >= 0) {
    const int64_t texture_id = texture_id_;
    texture_id_ = -1;
    texture_registrar_->UnregisterTexture(
        texture_id, [keep_alive = std::move(keep_alive)]() mutable {
          // Dropping the last reference here — on the thread that has just
          // finished with the texture — is the point of this callback.
          keep_alive.reset();
        });
  }
}

void VideoOutput::SetRequestedSize(const Size& size) {
  std::lock_guard<std::mutex> lock(mutex_);
  requested_size_ = size;
}

Size VideoOutput::CurrentSize() {
  std::lock_guard<std::mutex> lock(mutex_);
  return CurrentSizeLocked();
}

Size VideoOutput::CurrentSizeLocked() {
  return ResolveRenderSize(requested_size_, VideoSizeFromMpvLocked());
}

Size VideoOutput::VideoSizeFromMpvLocked() {
  // media_kit pushes the video's dimensions down from Dart as they are
  // observed, but the first frames can arrive before that round trip; asking
  // mpv directly is what keeps a stream from staying blank until something
  // else resizes it.
  mpv_node node = {};
  if (mpv_->get_property(handle_, "video-out-params", MPV_FORMAT_NODE, &node) <
      0) {
    return Size{};
  }
  int64_t dw = 0;
  int64_t dh = 0;
  int64_t rotate = 0;
  if (node.format == MPV_FORMAT_NODE_MAP) {
    for (int32_t i = 0; i < node.u.list->num; i++) {
      const char* key = node.u.list->keys[i];
      const mpv_node& value = node.u.list->values[i];
      if (value.format != MPV_FORMAT_INT64) {
        continue;
      }
      if (std::strcmp(key, "dw") == 0) {
        dw = value.u.int64;
      } else if (std::strcmp(key, "dh") == 0) {
        dh = value.u.int64;
      } else if (std::strcmp(key, "rotate") == 0) {
        rotate = value.u.int64;
      }
    }
  }
  mpv_->free_node_contents(&node);

  const bool upright = rotate == 0 || rotate == 180;
  return Size{upright ? dw : dh, upright ? dh : dw};
}

void VideoOutput::OnMpvRenderUpdate() {
  // MarkTextureFrameAvailable posts to the platform thread when called from
  // anywhere else, so this is safe on an mpv thread.
  if (texture_id_ >= 0) {
    texture_registrar_->MarkTextureFrameAvailable(texture_id_);
  }
}

const FlutterDesktopPixelBuffer* VideoOutput::CopyPixelBuffer(size_t,
                                                              size_t) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (shut_down_ || render_context_ == nullptr) {
    return nullptr;
  }
  const Size size = CurrentSizeLocked();
  if (size.IsEmpty()) {
    // Nothing has told us how big the video is yet. Returning no buffer
    // leaves the previous frame on screen instead of flashing a blank one.
    return nullptr;
  }

  const size_t required = PixelBufferBytes(size);
  if (pixels_.size() < required) {
    pixels_.resize(required);
  }

  int32_t sw_size[2] = {static_cast<int32_t>(size.width),
                        static_cast<int32_t>(size.height)};
  int32_t stride = StrideBytes(size);
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_SW_SIZE, sw_size},
      {MPV_RENDER_PARAM_SW_FORMAT, const_cast<char*>(kSoftwareFormat)},
      {MPV_RENDER_PARAM_SW_STRIDE, &stride},
      {MPV_RENDER_PARAM_SW_POINTER, pixels_.data()},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  const int status = mpv_->render_context_render(render_context_, params);
  if (status != 0) {
    return nullptr;
  }

  buffer_descriptor_.buffer = pixels_.data();
  buffer_descriptor_.width = static_cast<size_t>(size.width);
  buffer_descriptor_.height = static_cast<size_t>(size.height);
  return &buffer_descriptor_;
}

}  // namespace media_kit_video_elinux
