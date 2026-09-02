cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "media_kit_video_elinux")
project(${PROJECT_NAME} LANGUAGES CXX)

# Used by flutter-elinux when generating the plugin registrant; do not rename.
set(PLUGIN_NAME "media_kit_video_elinux_plugin")

add_library(${PLUGIN_NAME} SHARED
  "media_kit_video_elinux_plugin.cc"
  "video_output.cc"
  "video_geometry.cc"
  "mpv_library.cc"
)
apply_standard_settings(${PLUGIN_NAME})
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

# libmpv is resolved at runtime rather than linked (see mpv_library.h), so the
# only extra library here is the dynamic loader itself.
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  ${CMAKE_DL_LIBS})

# List of absolute paths to libraries that should be bundled with the plugin.
set(media_kit_video_elinux_bundled_libraries
  ""
  PARENT_SCOPE
)
