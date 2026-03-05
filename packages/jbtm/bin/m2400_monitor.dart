// Manual test script: connects to a real M2400 device and prints all records.
//
// Usage:
//   dart run bin/m2400_monitor.dart <host> [port]
//
// Examples:
//   dart run bin/m2400_monitor.dart 192.168.1.100
//   dart run bin/m2400_monitor.dart 192.168.1.100 52212
//
// Defaults to port 52211. Press Ctrl+C to stop.

import 'dart:async';
import 'dart:io';

import 'package:jbtm/jbtm.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run bin/m2400_monitor.dart <host> [port]');
    stderr.writeln('  host  - IP address or hostname of the M2400 device');
    stderr.writeln('  port  - TCP port (default: 52211)');
    exit(1);
  }

  final host = args[0];
  final port = args.length > 1 ? int.tryParse(args[1]) : 52211;
  if (port == null) {
    stderr.writeln('Error: invalid port "${args[1]}"');
    exit(1);
  }

  final socket = MSocket(host, port);
  final subscriptions = <StreamSubscription<dynamic>>[];

  void shutdown() {
    stdout.writeln('\nShutting down...');
    for (final sub in subscriptions) {
      sub.cancel();
    }
    socket.dispose();
    stdout.writeln('Done.');
    exit(0);
  }

  // Handle Ctrl+C (SIGINT) for clean shutdown.
  ProcessSignal.sigint.watch().listen((_) => shutdown());

  // Also handle SIGTERM if available (not supported on Windows).
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }

  // Print connection status changes.
  subscriptions.add(
    socket.statusStream.listen((status) {
      final label = switch (status) {
        ConnectionStatus.connecting => 'CONNECTING',
        ConnectionStatus.connected => 'CONNECTED',
        ConnectionStatus.disconnected => 'DISCONNECTED',
      };
      stdout.writeln('[STATUS] $label  ($host:$port)');
    }),
  );

  // Parse frames and print records.
  var recordCount = 0;
  subscriptions.add(
    socket.dataStream
        .transform(M2400FrameParser())
        .map(parseM2400Frame)
        .where((record) => record != null)
        .cast<M2400Record>()
        .listen(
      (record) {
        recordCount++;
        stdout.writeln('[#$recordCount] ${record.type.name}');
        for (final entry in record.fields.entries) {
          stdout.writeln('  ${entry.key} = ${entry.value}');
        }
        stdout.writeln('');
      },
      onError: (Object e) {
        stderr.writeln('[ERROR] $e');
      },
    ),
  );

  stdout.writeln('M2400 Monitor — connecting to $host:$port ...');
  stdout.writeln('Press Ctrl+C to stop.\n');
  socket.connect();
}
