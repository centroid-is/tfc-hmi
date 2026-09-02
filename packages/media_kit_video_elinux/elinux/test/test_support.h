// Copyright (c) Centroid. Part of CentroidX.
//
// A three-macro test harness. The eLinux toolchain image carries cmake and a
// compiler and nothing else, so the alternative to twenty lines here is a
// network fetch in CI for a test binary that asserts arithmetic.

#ifndef MEDIA_KIT_VIDEO_ELINUX_TEST_SUPPORT_H_
#define MEDIA_KIT_VIDEO_ELINUX_TEST_SUPPORT_H_

#include <functional>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace test_support {

struct Case {
  std::string name;
  std::function<void()> body;
};

inline std::vector<Case>& Cases() {
  static std::vector<Case> cases;
  return cases;
}

inline int& Failures() {
  static int failures = 0;
  return failures;
}

struct Registrar {
  Registrar(const std::string& name, std::function<void()> body) {
    Cases().push_back({name, std::move(body)});
  }
};

inline void Fail(const char* file, int line, const std::string& message) {
  ++Failures();
  std::cerr << "  FAIL " << file << ":" << line << ": " << message << "\n";
}

}  // namespace test_support

#define TEST(name)                                                    \
  static void name();                                                 \
  static ::test_support::Registrar registrar_##name(#name, name);     \
  static void name()

#define EXPECT_TRUE(condition)                                        \
  do {                                                                \
    if (!(condition)) {                                               \
      ::test_support::Fail(__FILE__, __LINE__, #condition);           \
    }                                                                 \
  } while (0)

#define EXPECT_EQ(actual, expected)                                   \
  do {                                                                \
    auto&& actual_value = (actual);                                   \
    auto&& expected_value = (expected);                               \
    if (!(actual_value == expected_value)) {                          \
      std::ostringstream out;                                         \
      out << #actual << " == " << #expected;                          \
      ::test_support::Fail(__FILE__, __LINE__, out.str());            \
    }                                                                 \
  } while (0)

#endif  // MEDIA_KIT_VIDEO_ELINUX_TEST_SUPPORT_H_
