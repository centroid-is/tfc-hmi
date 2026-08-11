cmake_minimum_required(VERSION 3.14)
project(runner_tests LANGUAGES CXX)

# Standalone project, deliberately NOT included by ../CMakeLists.txt: the
# Flutter Windows build should not have to build tests, and these tests should
# not need Windows. Everything under test here is platform-free, so this
# configures and runs on Linux and macOS too.
#
#   cmake -S . -B build && cmake --build build && ctest --test-dir build

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

enable_testing()

add_executable(gpu_watchdog_test
  "gpu_watchdog_test.cpp"
  "../gpu_watchdog.cpp"
)
target_include_directories(gpu_watchdog_test PRIVATE "..")

add_executable(log_rotation_test
  "log_rotation_test.cpp"
  "../log_rotation.cpp"
)
target_include_directories(log_rotation_test PRIVATE "..")

foreach(target gpu_watchdog_test log_rotation_test)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra)
  endif()
endforeach()

add_test(NAME gpu_watchdog COMMAND gpu_watchdog_test)
add_test(NAME log_rotation COMMAND log_rotation_test)
