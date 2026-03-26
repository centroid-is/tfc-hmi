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

/// Call once at startup (before creating any Logger instances) to configure
/// the global log filter from CENTROID_LOG_LEVEL.
void initLogConfig() {
  Logger.defaultFilter = () => EnvLogFilter();
}
