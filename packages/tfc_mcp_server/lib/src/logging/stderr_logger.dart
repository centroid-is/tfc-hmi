import 'dart:io';

import 'package:logger/logger.dart' as log;
import 'package:tfc_dart/core/log_config.dart';

/// Creates a [Logger] that writes all output to stderr.
///
/// This is critical for MCP servers: stdout is reserved exclusively for
/// JSON-RPC protocol messages. Any non-protocol output on stdout corrupts
/// the transport and disconnects the client.
///
/// Respects CENTROID_LOG_LEVEL env var via [EnvLogFilter]. Falls back to
/// [level] parameter if the env var is not set (default: info).
log.Logger createServerLogger({log.Level level = log.Level.info}) {
  return log.Logger(
    filter: EnvLogFilter(),
    printer: log.SimplePrinter(printTime: true, colors: false),
    output: _StderrOutput(),
  );
}

/// Logger output that writes to stderr instead of stdout.
class _StderrOutput extends log.LogOutput {
  @override
  void output(log.OutputEvent event) {
    for (final line in event.lines) {
      stderr.writeln(line);
    }
  }
}
