import 'dart:io';

import 'package:logger/logger.dart' as log;
import 'package:tfc_dart/core/log_config.dart';

/// Creates a [Logger] that writes all output to stderr.
///
/// This is critical for MCP servers: stdout is reserved exclusively for
/// JSON-RPC protocol messages. Any non-protocol output on stdout corrupts
/// the transport and disconnects the client.
///
/// The level comes from CENTROID_LOG_LEVEL via [EnvLogFilter], defaulting to
/// [defaultLogLevel] when unset.
///
/// [level] is a *floor*: the returned logger never emits below it, whatever
/// the environment asks for. It defaults to [log.Level.trace], i.e. no floor,
/// so that turning CENTROID_LOG_LEVEL up actually turns this logger up. It
/// used to be accepted and then silently dropped on the floor.
log.Logger createServerLogger({log.Level level = log.Level.trace}) {
  return log.Logger(
    filter: EnvLogFilter(),
    printer: log.SimplePrinter(printTime: true, colors: false),
    output: _StderrOutput(),
    level: level,
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
