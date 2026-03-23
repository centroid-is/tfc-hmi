/// Subprocess helper for log file integration test.
///
/// Writes Dart logger output to the file at args[0] via RandomAccessFile,
/// and creates an open62541 Client that produces native stdout output.
/// The parent test captures both to verify they coexist.
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:open62541/open62541.dart';
import 'package:tfc_dart/core/log_config.dart';

class _FileOutput extends LogOutput {
  final RandomAccessFile _f;
  _FileOutput(this._f);
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      _f.writeStringSync('$line\n');
    }
  }
}

Future<void> main(List<String> args) async {
  final logFilePath = args[0];
  final logFile = File(logFilePath).openSync(mode: FileMode.append);

  // Dart logger output → file (same as MSIX production path)
  initLogConfig();
  final logger = Logger(
    filter: EnvLogFilter(),
    printer: SimplePrinter(printTime: false),
    output: _FileOutput(logFile),
  );
  logger.i('DART_MARKER_INFO');
  logger.e('DART_MARKER_ERROR');

  // open62541 native output → stdout (captured by parent process)
  // Use INFO level so we get the "Client Status" line on connect attempt.
  final client = Client(logLevel: LogLevel.UA_LOGLEVEL_INFO);
  // 192.0.2.1 is TEST-NET (RFC 5737) — guaranteed unreachable, fast failure.
  try {
    await client.connect('opc.tcp://192.0.2.1:4840').timeout(
      Duration(seconds: 2),
      onTimeout: () {},
    );
  } catch (_) {}
  client.disconnect();

  logFile.closeSync();
  exit(0);
}
