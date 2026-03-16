import 'dart:io';

import 'package:logger/logger.dart' as log;

/// Creates a [Logger] that writes all output to stderr.
///
/// This is critical for MCP servers: stdout is reserved exclusively for
/// JSON-RPC protocol messages. Any non-protocol output on stdout corrupts
/// the transport and disconnects the client.
log.Logger createServerLogger({log.Level level = log.Level.info}) {
  return log.Logger(
    level: level,
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
