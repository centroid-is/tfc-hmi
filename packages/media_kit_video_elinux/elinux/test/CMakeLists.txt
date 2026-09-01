# Host-buildable tests for the parts of the plugin that are neither Flutter
# nor mpv. Built standalone (no Flutter toolchain):
#
#   cmake -S elinux/test -B build/test && cmake --build build/test && ctest --test-dir build/test
cmake_minimum_required(VERSION 3.15)
project(media_kit_video_elinux_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

enable_testing()

add_executable(media_kit_video_elinux_tests
  test_main.cc
  video_geometry_test.cc
  mpv_library_test.cc
  ../video_geometry.cc
  ../mpv_library.cc
)
target_include_directories(media_kit_video_elinux_tests PRIVATE ..)
target_compile_options(media_kit_video_elinux_tests PRIVATE -Wall -Wextra -Werror)
target_link_libraries(media_kit_video_elinux_tests PRIVATE ${CMAKE_DL_LIBS})

add_test(NAME media_kit_video_elinux_tests COMMAND media_kit_video_elinux_tests)
