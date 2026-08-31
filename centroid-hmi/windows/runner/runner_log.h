#ifndef RUNNER_RUNNER_LOG_H_
#define RUNNER_RUNNER_LOG_H_

#include <string>

// A log sink for the runner's own diagnostics that survives the terminal.
//
// The 2026-08-31 freeze was investigated three times from fragments, and each
// time the decisive line was missing -- not because nothing was written, but
// because of where it went. That run was started from a shell, so
// ChooseOutputTarget correctly left stdout and stderr alone and every
// [gpu-watchdog] line went to a console window nobody was capturing.
// %TEMP%\hmi-stderr.log was zero bytes. The evidence existed for as long as
// the scrollback did.
//
// So the runner's diagnostics now go to BOTH:
//
//   * stderr, wherever that points -- unchanged, so a developer watching a
//     console still sees everything as it happens; and
//   * hmi-runner.log, a file beside CENTROID_LOG_FILE that ONLY the runner
//     writes.
//
// The sidecar is not fastidiousness. The first version of this appended to
// CENTROID_LOG_FILE itself, on the reasoning that one log is easier to read
// than two. Measured on a live run, that loses most of what it writes: the
// Dart logger holds the same path open on its own handle with its own offset
// and marches over the appended lines. 23 [gpu-watchdog] lines reached stderr
// and 6 were still in the file; a line read once was gone by the next read.
// utils.cpp already documents the same hazard for open62541's writes. A log
// that silently drops three quarters of an incident is worse than no log,
// because it is trusted. One file, one writer.
//
// It survives across runs (append, rolled to .prev past 8 MB), because the
// question being asked is usually about the run before this one.
//
// The file half is opened once, best effort, and every failure is silent by
// design: a station must not fail to start because a log file could not be
// opened, and the stderr half still works.
//
// Deliberately NOT a general logging framework. Two calls, one tag, no levels,
// no configuration. The interesting logic -- how much of a repeating line to
// print -- lives in log_throttle.h where it can be tested.

namespace tfc {

// Opens the durable half: hmi-runner.log in the same directory as |log_path|,
// which is normally CENTROID_LOG_FILE. Safe to call with an empty path, which
// leaves only the stderr half. Calling it more than once is a no-op after the
// first success.
void InitRunnerLog(const std::string& log_path);

// Writes one line: a local timestamp, |tag|, then |message|. Thread safe --
// the GPU watchdog now runs on a timer-queue thread precisely so that it does
// not depend on the platform thread, and it logs from there.
void RunnerLogLine(const char* tag, const std::string& message);

// Writes a pre-formatted multi-line block verbatim to both sinks, with no
// timestamp or tag of its own. For FormatLossReport, whose lines already carry
// the [gpu-loss] prefix that run-hmi.ps1 -Report greps for.
void RunnerLogBlock(const std::string& block);

// True when the durable half is open, so startup can say which sinks are live
// rather than leaving the reader to guess.
bool RunnerLogHasFile();

// The path the durable half is writing to, empty when there is none.
const std::string& RunnerLogPath();

}  // namespace tfc

#endif  // RUNNER_RUNNER_LOG_H_
