import 'package:logger/logger.dart';
import 'package:open62541/open62541.dart' show LogLevel;
import 'package:test/test.dart';

import 'package:tfc_dart/core/log_config.dart';

void main() {
  group('EnvLogFilter', () {
    test('shouldLog returns true for events at or above min level', () {
      final filter = EnvLogFilter(); // defaults to trace (env not set)

      expect(filter.shouldLog(LogEvent(Level.trace, '')), isTrue);
      expect(filter.shouldLog(LogEvent(Level.debug, '')), isTrue);
      expect(filter.shouldLog(LogEvent(Level.info, '')), isTrue);
      expect(filter.shouldLog(LogEvent(Level.warning, '')), isTrue);
      expect(filter.shouldLog(LogEvent(Level.error, '')), isTrue);
      expect(filter.shouldLog(LogEvent(Level.fatal, '')), isTrue);
    });

    test('initLogConfig sets Logger.defaultFilter', () {
      initLogConfig();
      final filter = Logger.defaultFilter();
      expect(filter, isA<EnvLogFilter>());
    });
  });

  group('logLevelFromEnv', () {
    // Note: logLevelFromEnv reads Platform.environment directly so we can't
    // easily inject different values. We test the default (unset) behavior
    // and verify the function returns a valid Level.
    test('returns Level.trace when env var is not set', () {
      // CENTROID_LOG_LEVEL is not set in test environment
      expect(logLevelFromEnv(), equals(Level.trace));
    });
  });

  group('opcuaLogLevelFromEnv', () {
    test('returns a valid LogLevel', () {
      final level = opcuaLogLevelFromEnv();
      expect(LogLevel.values, contains(level));
    });
  });
}
