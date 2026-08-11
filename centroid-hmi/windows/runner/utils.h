#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Redirects stdout and stderr to an already-attached console.
void RedirectIOToConsole();

// Redirects stdout and stderr to a log file. Truncates |path|; call
// RotateLogs first to keep the previous run.
void RedirectIOToFile(const char* path);

// Default log file location: %LOCALAPPDATA%\centroid-hmi\logs\hmi.log,
// creating the directory. Returns an empty string if it cannot be created.
//
// Logging to a file by default is deliberate: this is a windowed app, so
// without a console and without CENTROID_LOG_FILE set, everything written to
// stdout/stderr — including crash records — goes nowhere at all.
std::string DefaultLogPath();

// Directory part of |path|, empty if it has none.
std::string DirectoryOf(const std::string& path);

// Moves previous runs aside so this run starts a fresh file, keeping
// |max_archives| generations (hmi.1.log, hmi.2.log, ...). Without this the
// log from the run that crashed is destroyed by the relaunch that goes
// looking for it.
void RotateLogs(const std::string& path, int max_archives);

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
