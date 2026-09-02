// Copyright (c) Centroid. Part of CentroidX.
//
// Late-bound access to libmpv.
//
// The plugin deliberately does not link against libmpv: the eLinux toolchain
// image has no libmpv-dev, and by the time any video output is created
// package:media_kit has already loaded libmpv into the process itself. So the
// entry points are resolved by name at runtime, and a station without libmpv
// fails the channel call with a message instead of failing to start.

#ifndef MEDIA_KIT_VIDEO_ELINUX_MPV_LIBRARY_H_
#define MEDIA_KIT_VIDEO_ELINUX_MPV_LIBRARY_H_

#include <functional>
#include <string>
#include <vector>

#include "third_party/mpv/render.h"

namespace media_kit_video_elinux {

// The subset of libmpv this plugin calls.
struct MpvApi {
  int (*render_context_create)(mpv_render_context** res,
                               mpv_handle* mpv,
                               mpv_render_param* params) = nullptr;
  int (*render_context_render)(mpv_render_context* ctx,
                               mpv_render_param* params) = nullptr;
  void (*render_context_set_update_callback)(mpv_render_context* ctx,
                                             mpv_render_update_fn callback,
                                             void* callback_ctx) = nullptr;
  void (*render_context_free)(mpv_render_context* ctx) = nullptr;
  int (*get_property)(mpv_handle* ctx,
                      const char* name,
                      mpv_format format,
                      void* data) = nullptr;
  void (*free_node_contents)(mpv_node* node) = nullptr;
};

// Resolves a symbol name to an address, or nullptr.
using SymbolResolver = std::function<void*(const char*)>;

// The symbols LoadMpvApi asks for, in the order it asks for them.
const std::vector<std::string>& RequiredMpvSymbols();

// Fills `api` from `resolve`. On the first symbol that does not resolve,
// returns false, leaves `api` untouched-from-there and names the symbol in
// `missing_symbol` — a partially populated API is worse than none.
bool LoadMpvApi(const SymbolResolver& resolve,
                MpvApi* api,
                std::string* missing_symbol);

// The API backed by the libmpv already present in this process, or nullptr
// with `error` describing why not. Loaded once; the result is cached.
const MpvApi* MpvApiForProcess(std::string* error);

}  // namespace media_kit_video_elinux

#endif  // MEDIA_KIT_VIDEO_ELINUX_MPV_LIBRARY_H_
