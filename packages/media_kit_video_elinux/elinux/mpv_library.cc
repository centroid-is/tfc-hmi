// Copyright (c) Centroid. Part of CentroidX.

#include "mpv_library.h"

#include <dlfcn.h>

#include <mutex>

namespace media_kit_video_elinux {
namespace {

// Same names, in the same order, package:media_kit tries from Dart.
constexpr const char* kLibraryNames[] = {
    "libmpv.so",
    "libmpv.so.2",
    "libmpv.so.1",
};

}  // namespace

const std::vector<std::string>& RequiredMpvSymbols() {
  static const std::vector<std::string> symbols = {
      "mpv_render_context_create",
      "mpv_render_context_render",
      "mpv_render_context_set_update_callback",
      "mpv_render_context_free",
      "mpv_get_property",
      "mpv_free_node_contents",
  };
  return symbols;
}

bool LoadMpvApi(const SymbolResolver& resolve,
                MpvApi* api,
                std::string* missing_symbol) {
  const auto& names = RequiredMpvSymbols();
  std::vector<void*> addresses;
  addresses.reserve(names.size());
  for (const auto& name : names) {
    void* address = resolve(name.c_str());
    if (address == nullptr) {
      if (missing_symbol != nullptr) {
        *missing_symbol = name;
      }
      return false;
    }
    addresses.push_back(address);
  }

  size_t index = 0;
  api->render_context_create =
      reinterpret_cast<decltype(api->render_context_create)>(
          addresses[index++]);
  api->render_context_render =
      reinterpret_cast<decltype(api->render_context_render)>(
          addresses[index++]);
  api->render_context_set_update_callback =
      reinterpret_cast<decltype(api->render_context_set_update_callback)>(
          addresses[index++]);
  api->render_context_free =
      reinterpret_cast<decltype(api->render_context_free)>(addresses[index++]);
  api->get_property =
      reinterpret_cast<decltype(api->get_property)>(addresses[index++]);
  api->free_node_contents =
      reinterpret_cast<decltype(api->free_node_contents)>(addresses[index++]);
  return true;
}

const MpvApi* MpvApiForProcess(std::string* error) {
  static std::once_flag once;
  static MpvApi api;
  static bool loaded = false;
  static std::string load_error;

  std::call_once(once, [] {
    void* library = nullptr;
    for (const char* name : kLibraryNames) {
      // Already-loaded libraries are returned with their reference count
      // bumped, so this finds the copy media_kit opened from Dart rather than
      // mapping a second one.
      library = dlopen(name, RTLD_LAZY);
      if (library != nullptr) {
        break;
      }
    }
    if (library == nullptr) {
      load_error =
          "libmpv is not loaded in this process. Install the libmpv shared "
          "library (Debian: libmpv2) or ship it beside the bundle.";
      return;
    }
    std::string missing;
    if (!LoadMpvApi(
            [library](const char* name) { return dlsym(library, name); }, &api,
            &missing)) {
      load_error = "libmpv is missing the symbol " + missing +
                   "; it is too old for the render API this plugin needs.";
      return;
    }
    loaded = true;
  });

  if (!loaded) {
    if (error != nullptr) {
      *error = load_error;
    }
    return nullptr;
  }
  return &api;
}

}  // namespace media_kit_video_elinux
