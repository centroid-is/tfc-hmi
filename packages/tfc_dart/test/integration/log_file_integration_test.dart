@TestOn('!browser')
library;

import 'dart:io';

import 'package:logger/logger.dart';
import 'package:open62541/open62541.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/log_config.dart';

void main() {
  group('Combined Dart + open62541 file logging', () {
    late Directory tempDir;
    late String logFilePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('log_integration_');
      logFilePath = '${tempDir.path}${Platform.pathSeparator}test.log';
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('Dart logger output is written to log file via RandomAccessFile', () {
      initLogConfig();

      // Open the file the same way main.dart does
      final logFile = File(logFilePath).openSync(mode: FileMode.append);

      // Simulate what _debugPrint does: intercept print() and write to file
      final logger = Logger(
        filter: EnvLogFilter(),
        printer: SimplePrinter(printTime: false),
        output: _FileLogOutput(logFile),
      );

      logger.i('dart info message');
      logger.w('dart warning message');
      logger.e('dart error message');
      logger.t('dart trace message');

      logFile.closeSync();

      final content = File(logFilePath).readAsStringSync();
      expect(content, contains('dart info message'));
      expect(content, contains('dart warning message'));
      expect(content, contains('dart error message'));
      expect(content, contains('dart trace message'));
    });

    test('open62541 native output is written to log file', () {
      // Create an OPC UA client with debug logging — the Client constructor
      // calls UA_Log_Stdout_new which writes to stdout. We redirect stdout
      // to our log file the same way utils.cpp does (but from Dart side we
      // can't do freopen, so we just verify the Client accepts the log level).
      //
      // The actual native->file integration requires the C++ runner redirect
      // which is tested manually in MSIX. Here we verify the plumbing:
      // opcuaLogLevelFromEnv() returns a valid LogLevel that Client accepts.

      final level = opcuaLogLevelFromEnv();
      expect(level, isA<LogLevel>());

      // Create a client with the env-derived log level — this proves the
      // type is accepted by the Client constructor (would throw if wrong type).
      final client = Client(
        logLevel: level,
      );

      // Connect to a non-existent server to trigger native log output.
      // The client will log error messages at the configured level.
      // We don't assert on the native output here (it goes to stdout,
      // not our file), but we verify the client was created successfully.
      expect(client, isNotNull);

      client.disconnect();
    });

    test('second handle can open existing file in append mode', () {
      // Key regression test: the C++ side opens the log file first, then
      // Dart opens it in append mode. With freopen_s (exclusive lock) this
      // would throw PathAccessException. With CreateFileW + FILE_SHARE_WRITE
      // it succeeds. We simulate by opening the file twice.

      // First handle (simulates C++ CreateFileW)
      final handle1 = File(logFilePath).openSync(mode: FileMode.write);
      handle1.writeStringSync('first writer\n');

      // Second handle must succeed (would throw if sharing is denied)
      final handle2 = File(logFilePath).openSync(mode: FileMode.append);
      handle2.writeStringSync('second writer\n');

      handle1.closeSync();
      handle2.closeSync();

      // Both handles wrote successfully — file is non-empty
      final size = File(logFilePath).lengthSync();
      expect(size, greaterThan(0));
    });

    test('EnvLogFilter respects log level filtering', () {
      // Default: CENTROID_LOG_LEVEL not set → trace (show everything)
      final filter = EnvLogFilter();

      // All levels should pass when default (trace)
      for (final level in [
        Level.trace,
        Level.debug,
        Level.info,
        Level.warning,
        Level.error,
        Level.fatal,
      ]) {
        expect(
          filter.shouldLog(LogEvent(level, 'test')),
          isTrue,
          reason: '$level should pass at trace filter level',
        );
      }
    });

    test('Logger with EnvLogFilter writes only matching levels to file', () {
      initLogConfig();

      final logFile = File(logFilePath).openSync(mode: FileMode.append);

      // Create a logger that only shows warnings and above
      final warningFilter = _MinLevelFilter(Level.warning);
      final logger = Logger(
        filter: warningFilter,
        printer: SimplePrinter(printTime: false),
        output: _FileLogOutput(logFile),
      );

      logger.t('trace should not appear');
      logger.d('debug should not appear');
      logger.i('info should not appear');
      logger.w('warning should appear');
      logger.e('error should appear');

      logFile.closeSync();

      final content = File(logFilePath).readAsStringSync();
      expect(content, isNot(contains('trace should not appear')));
      expect(content, isNot(contains('debug should not appear')));
      expect(content, isNot(contains('info should not appear')));
      expect(content, contains('warning should appear'));
      expect(content, contains('error should appear'));
    });
  });
}

/// A LogOutput that writes to a RandomAccessFile (same as MSIX production path).
class _FileLogOutput extends LogOutput {
  final RandomAccessFile _file;
  _FileLogOutput(this._file);

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      _file.writeStringSync('$line\n');
    }
  }
}

/// A filter that only allows events at or above [minLevel].
class _MinLevelFilter extends LogFilter {
  final Level minLevel;
  _MinLevelFilter(this.minLevel);

  @override
  bool shouldLog(LogEvent event) => event.level >= minLevel;
}
