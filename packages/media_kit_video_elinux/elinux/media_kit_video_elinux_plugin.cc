// Copyright (c) Centroid. Part of CentroidX.
//
// Answers the method channel package:media_kit_video's native video
// controller talks to. Upstream implements it for GTK, which flutter-elinux
// cannot register; the Dart half of media_kit_video is unmodified and does
// not care which native half replies.

#include "include/media_kit_video_elinux/media_kit_video_elinux_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/standard_method_codec.h>

#include <iostream>
#include <map>
#include <memory>
#include <string>

#include "mpv_library.h"
#include "video_geometry.h"
#include "video_output.h"

namespace media_kit_video_elinux {
namespace {

constexpr char kChannelName[] = "com.alexmercerind/media_kit_video";
constexpr char kMethodCreate[] = "VideoOutputManager.Create";
constexpr char kMethodSetSize[] = "VideoOutputManager.SetSize";
constexpr char kMethodDispose[] = "VideoOutputManager.Dispose";
constexpr char kMethodResize[] = "VideoOutput.Resize";

using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

const flutter::EncodableValue* Lookup(const flutter::EncodableMap& map,
                                      const char* key) {
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  return it == map.end() ? nullptr : &it->second;
}

std::string StringAt(const flutter::EncodableMap& map, const char* key) {
  const flutter::EncodableValue* value = Lookup(map, key);
  if (value == nullptr || !std::holds_alternative<std::string>(*value)) {
    return std::string();
  }
  return std::get<std::string>(*value);
}

// Every dimension and handle crosses this channel as a string; see
// package:media_kit_video's native_video_controller.
std::optional<int64_t> IntAt(const flutter::EncodableMap& map,
                             const char* key) {
  return ParseNullableInt(StringAt(map, key));
}

class MediaKitVideoElinuxPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrar* registrar) {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), kChannelName,
            &flutter::StandardMethodCodec::GetInstance());
    auto plugin = std::make_unique<MediaKitVideoElinuxPlugin>(
        registrar->texture_registrar(), std::move(channel));
    plugin->Listen();
    registrar->AddPlugin(std::move(plugin));
  }

  MediaKitVideoElinuxPlugin(
      flutter::TextureRegistrar* texture_registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel)
      : texture_registrar_(texture_registrar), channel_(std::move(channel)) {}

  ~MediaKitVideoElinuxPlugin() override {
    // Engine teardown with players still open: stop rendering before the
    // registrar goes away rather than leaving live textures behind.
    for (auto& entry : outputs_) {
      entry.second->Shutdown(entry.second);
    }
    outputs_.clear();
  }

  void Listen() {
    channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) { Handle(call, *result); });
  }

 private:
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              MethodResult& result) {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (arguments == nullptr) {
      result.Error("bad-arguments", "Expected a map of arguments.");
      return;
    }
    const std::optional<int64_t> handle = IntAt(*arguments, "handle");
    if (!handle.has_value()) {
      result.Error("bad-arguments", "Missing or unparseable mpv handle.");
      return;
    }

    if (call.method_name() == kMethodCreate) {
      Create(*handle, *arguments, result);
    } else if (call.method_name() == kMethodSetSize) {
      SetSize(*handle, *arguments, result);
    } else if (call.method_name() == kMethodDispose) {
      Dispose(*handle, result);
    } else {
      result.NotImplemented();
    }
  }

  void Create(int64_t handle,
              const flutter::EncodableMap& arguments,
              MethodResult& result) {
    if (outputs_.count(handle) > 0) {
      result.Success();
      return;
    }

    std::string error;
    const MpvApi* mpv = MpvApiForProcess(&error);
    if (mpv == nullptr) {
      result.Error("libmpv-unavailable", error);
      return;
    }

    Size requested;
    if (const auto* configuration =
            std::get_if<flutter::EncodableMap>(Lookup(arguments, "configuration"))) {
      requested = Size{IntAt(*configuration, "width").value_or(0),
                       IntAt(*configuration, "height").value_or(0)};
      // enableHardwareAcceleration is accepted and ignored: this output is
      // always software rendered, see video_output.h.
    }

    auto output = std::make_shared<VideoOutput>(
        reinterpret_cast<mpv_handle*>(handle), mpv, texture_registrar_);
    if (!output->Initialize(requested, &error)) {
      result.Error("video-output-unavailable", error);
      return;
    }
    outputs_[handle] = output;
    result.Success();
    NotifyResize(handle, *output);
  }

  void SetSize(int64_t handle,
               const flutter::EncodableMap& arguments,
               MethodResult& result) {
    const auto output = Find(handle);
    if (output == nullptr) {
      result.Error("unknown-handle", "No video output for this player.");
      return;
    }
    output->SetRequestedSize(Size{IntAt(arguments, "width").value_or(0),
                                  IntAt(arguments, "height").value_or(0)});
    result.Success();
    NotifyResize(handle, *output);
  }

  void Dispose(int64_t handle, MethodResult& result) {
    const auto output = Find(handle);
    if (output == nullptr) {
      // Disposing twice is not an error; the player may have been torn down
      // before its controller ever came up.
      result.Success();
      return;
    }
    outputs_.erase(handle);
    output->Shutdown(output);
    result.Success();
  }

  std::shared_ptr<VideoOutput> Find(int64_t handle) {
    const auto it = outputs_.find(handle);
    return it == outputs_.end() ? nullptr : it->second;
  }

  // Tells Dart which texture to show and how big it is. media_kit_video
  // learns the texture id from here and nowhere else, so this has to happen
  // for the very first frame as well as for every later resize.
  void NotifyResize(int64_t handle, VideoOutput& output) {
    const Size size = NotifiableSize(output.CurrentSize());
    const flutter::EncodableMap rect = {
        {flutter::EncodableValue("left"), flutter::EncodableValue(0)},
        {flutter::EncodableValue("top"), flutter::EncodableValue(0)},
        {flutter::EncodableValue("width"), flutter::EncodableValue(size.width)},
        {flutter::EncodableValue("height"),
         flutter::EncodableValue(size.height)},
    };
    const flutter::EncodableMap message = {
        {flutter::EncodableValue("handle"), flutter::EncodableValue(handle)},
        {flutter::EncodableValue("id"),
         flutter::EncodableValue(output.texture_id())},
        {flutter::EncodableValue("rect"), flutter::EncodableValue(rect)},
    };
    channel_->InvokeMethod(kMethodResize,
                           std::make_unique<flutter::EncodableValue>(message));
  }

  flutter::TextureRegistrar* texture_registrar_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::map<int64_t, std::shared_ptr<VideoOutput>> outputs_;
};

}  // namespace
}  // namespace media_kit_video_elinux

void MediaKitVideoElinuxPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  media_kit_video_elinux::MediaKitVideoElinuxPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrar>(registrar));
}
