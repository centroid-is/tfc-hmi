#ifndef RUNNER_TEST_TEST_HARNESS_H_
#define RUNNER_TEST_TEST_HARNESS_H_

// A ~60 line, dependency-free test harness.
//
// The runner has no other C++ tests and no package manager, so pulling in
// GoogleTest for a handful of state-machine assertions would cost more than it
// buys. If this file ever needs fixtures, parameterisation or death tests,
// that is the signal to switch to GoogleTest via FetchContent.
//
// Usage:
//   TEST(does_the_thing) {
//     CHECK(condition);
//     CHECK_EQ(actual, expected);
//   }
//   int main() { return tfc_test::RunAll(); }

#include <cstdio>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

namespace tfc_test {

struct TestCase {
  const char* name;
  std::function<void()> body;
};

inline std::vector<TestCase>& Registry() {
  static std::vector<TestCase> registry;
  return registry;
}

inline int& FailureCount() {
  static int failures = 0;
  return failures;
}

inline void ReportFailure(const char* file, int line, const std::string& what) {
  FailureCount()++;
  std::printf("    FAIL %s:%d\n         %s\n", file, line, what.c_str());
}

struct Registrar {
  Registrar(const char* name, std::function<void()> body) {
    Registry().push_back({name, std::move(body)});
  }
};

inline int RunAll() {
  int failed_tests = 0;
  for (const auto& test : Registry()) {
    int before = FailureCount();
    std::printf("  %s\n", test.name);
    test.body();
    if (FailureCount() != before) {
      failed_tests++;
    }
  }
  std::printf("\n%zu tests, %d failed, %d assertion failure(s)\n",
              Registry().size(), failed_tests, FailureCount());
  return FailureCount() == 0 ? 0 : 1;
}

}  // namespace tfc_test

#define TEST(name)                                                     \
  static void name();                                                  \
  static tfc_test::Registrar registrar_##name(#name, name);            \
  static void name()

#define CHECK(cond)                                                    \
  do {                                                                 \
    if (!(cond)) {                                                     \
      tfc_test::ReportFailure(__FILE__, __LINE__, "CHECK(" #cond ")"); \
    }                                                                  \
  } while (0)

#define CHECK_EQ(actual, expected)                                     \
  do {                                                                 \
    auto actual_value = (actual);                                      \
    auto expected_value = (expected);                                  \
    if (!(actual_value == expected_value)) {                           \
      std::ostringstream oss;                                          \
      oss << "CHECK_EQ(" #actual ", " #expected ") -- got "            \
          << actual_value << ", want " << expected_value;              \
      tfc_test::ReportFailure(__FILE__, __LINE__, oss.str());          \
    }                                                                  \
  } while (0)

#endif  // RUNNER_TEST_TEST_HARNESS_H_
