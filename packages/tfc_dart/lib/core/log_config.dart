import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:open62541/open62541.dart' show LogLevel;

/// Reads CENTROID_LOG_LEVEL env var and returns the corresponding [Level].
///
/// Valid values: trace, debug, info, warning, error, fatal, off, all
/// Defaults to [Level.trace] (show everything) if unset or unrecognized.
Level logLevelFromEnv() {
  final value = Platform.environment['CENTROID_LOG_LEVEL']?.toLowerCase();
  return switch (value) {
    'all' || 'trace' => Level.trace,
    'debug' => Level.debug,
    'info' => Level.info,
    'warning' || 'warn' => Level.warning,
    'error' => Level.error,
    'fatal' => Level.fatal,
    'off' || 'none' => Level.off,
    _ => Level.trace,
  };
}

/// Reads CENTROID_OPCUA_LOG_LEVEL env var and returns the corresponding
/// open62541 [LogLevel].
///
/// Valid values: trace, debug, info, warning, error, fatal
/// Defaults to [LogLevel.UA_LOGLEVEL_INFO] if unset or unrecognized.
LogLevel opcuaLogLevelFromEnv() {
  final value = Platform.environment['CENTROID_OPCUA_LOG_LEVEL']?.toLowerCase();
  return switch (value) {
    'trace' => LogLevel.UA_LOGLEVEL_TRACE,
    'debug' => LogLevel.UA_LOGLEVEL_DEBUG,
    'info' => LogLevel.UA_LOGLEVEL_INFO,
    'warning' || 'warn' => LogLevel.UA_LOGLEVEL_WARNING,
    'error' => LogLevel.UA_LOGLEVEL_ERROR,
    'fatal' => LogLevel.UA_LOGLEVEL_FATAL,
    _ => LogLevel.UA_LOGLEVEL_INFO,
  };
}

/// A [LogFilter] that uses [CENTROID_LOG_LEVEL] to control which messages
/// are logged. Messages at or above the configured level pass through.
class EnvLogFilter extends LogFilter {
  final Level _minLevel;

  EnvLogFilter() : _minLevel = logLevelFromEnv();

  @override
  bool shouldLog(LogEvent event) {
    return event.level >= _minLevel;
  }
}

/// Writes each log line straight to the file, flushed as it goes.
///
/// Flushing per event costs a little throughput and buys the property that
/// matters when diagnosing a hang: whatever was logged before the process
/// stopped is actually on disk.
///
/// Deliberately a [RandomAccessFile] and not an [IOSink]. `IOSink.flush()`
/// marks the sink bound for the whole duration of the flush -- which is
/// asynchronous -- and any `writeln` landing in that window throws
/// `StateError: StreamSink is bound to a stream`. Flushing per event made
/// that window permanent. `logger` catches the throw and prints it, so the
/// symptom was a stack trace on stdout for nearly every line, and the line
/// itself missing from the file. `flush()` also throws *synchronously*, so
/// the `catchError` that was attached to it could never have caught it.
class _FileOutput extends LogOutput {
  _FileOutput(this._file);

  final RandomAccessFile _file;

  @override
  void output(OutputEvent event) {
    // Logging must never throw into whoever called the logger: LogOutput
    // failures surface as printed stack traces from inside logger itself,
    // which is far noisier than the line that was being logged.
    try {
      _file.writeStringSync('${event.lines.join('\n')}\n');
      _file.flushSync();
    } catch (_) {}
  }
}

RandomAccessFile? _logFile;

/// Call once at startup (before creating any Logger instances) to configure
/// the global log filter from CENTROID_LOG_LEVEL, and -- when
/// CENTROID_LOG_FILE is set -- to mirror every log line into that file.
///
/// The file sink exists because [ConsoleOutput] writes through `print()`,
/// which only reaches a file if whoever launched the process happens to be
/// capturing stdout. Under an IDE the output is trapped in a console pane no
/// tool can read, and when `flutter run` exits while the app keeps running,
/// the capture disappears entirely -- precisely when a fault needs a record.
/// Writing from inside the process removes that dependency.
void initLogConfig() {
  Logger.defaultFilter = () => EnvLogFilter();

  final path = Platform.environment['CENTROID_LOG_FILE'];
  if (path == null || path.isEmpty) return;

  // The Windows runner sets this once it has already pointed the process
  // stdout at that same file. ConsoleOutput therefore lands there anyway, and
  // opening it a second time here gives two writers with independent file
  // positions -- the runner writing from offset 0, this one appending at EOF,
  // each overwriting the other. main.dart already honours the flag for its
  // own file; the logger has to as well.
  if (Platform.environment['CENTROID_LOG_REDIRECTED'] == '1') return;

  try {
    _logFile ??= File(path).openSync(mode: FileMode.append);
    final file = _logFile!;
    Logger.defaultOutput = () => MultiOutput([ConsoleOutput(), _FileOutput(file)]);
    file.writeStringSync(
        '--- log opened ${DateTime.now().toIso8601String()} ---\n');
  } catch (e) {
    stderr.writeln('[log] file logging unavailable ($path): $e');
  }
}
