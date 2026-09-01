// Copyright (c) Centroid. Part of CentroidX.

#include "../mpv_library.h"

#include <string>
#include <vector>

#include "test_support.h"

namespace {

using media_kit_video_elinux::LoadMpvApi;
using media_kit_video_elinux::MpvApi;
using media_kit_video_elinux::RequiredMpvSymbols;

// Any non-null address will do: the loader only stores what it is handed.
void* FakeAddress(const char* name) {
  return const_cast<char*>(name);
}

TEST(AsksForTheRenderApiItCalls) {
  // Spelling these out is the point: a symbol resolved by name typoed here
  // is a crash at the first frame, not a compile error.
  const std::vector<std::string> expected = {
      "mpv_render_context_create",
      "mpv_render_context_render",
      "mpv_render_context_set_update_callback",
      "mpv_render_context_free",
      "mpv_get_property",
      "mpv_free_node_contents",
  };
  EXPECT_EQ(RequiredMpvSymbols(), expected);
}

TEST(PopulatesEveryEntryPoint) {
  MpvApi api;
  std::string missing;
  EXPECT_TRUE(LoadMpvApi(FakeAddress, &api, &missing));
  EXPECT_TRUE(missing.empty());
  EXPECT_TRUE(api.render_context_create != nullptr);
  EXPECT_TRUE(api.render_context_render != nullptr);
  EXPECT_TRUE(api.render_context_set_update_callback != nullptr);
  EXPECT_TRUE(api.render_context_free != nullptr);
  EXPECT_TRUE(api.get_property != nullptr);
  EXPECT_TRUE(api.free_node_contents != nullptr);
}

TEST(NamesTheSymbolAnOldLibmpvIsMissing) {
  MpvApi api;
  std::string missing;
  const auto resolve = [](const char* name) -> void* {
    return std::string(name) == "mpv_render_context_render" ? nullptr
                                                            : FakeAddress(name);
  };
  EXPECT_TRUE(!LoadMpvApi(resolve, &api, &missing));
  EXPECT_EQ(missing, std::string("mpv_render_context_render"));
}

TEST(LeavesTheApiUnusableWhenASymbolIsMissing) {
  // Half a render API is a segfault waiting for the first frame; the caller
  // must be able to trust that a false return means "do not use this".
  MpvApi api;
  std::string missing;
  const auto resolve = [](const char* name) -> void* {
    return std::string(name) == "mpv_render_context_create" ? nullptr
                                                            : FakeAddress(name);
  };
  EXPECT_TRUE(!LoadMpvApi(resolve, &api, &missing));
  EXPECT_TRUE(api.render_context_create == nullptr);
  EXPECT_TRUE(api.render_context_render == nullptr);
}

}  // namespace
