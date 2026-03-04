// TCP proxy for M2400 devices: connects once upstream and fans out to multiple
// downstream clients.
//
// Usage:
//   dart run bin/m2400_proxy.dart <upstream-host> [upstream-port] [listen-port]
//
// Examples:
//   dart run bin/m2400_proxy.dart 192.168.1.100
//   dart run bin/m2400_proxy.dart 192.168.1.100 52211 9000
//
// Defaults to port 52211 for both upstream and listen. Press Ctrl+C to stop.

import 'dart:io';

import 'package:jbtm/jbtm.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
        'Usage: dart run bin/m2400_proxy.dart <upstream-host> [upstream-port] [listen-port]');
    stderr.writeln(
        '  upstream-host  - IP or hostname of the M2400 device');
    stderr.writeln(
        '  upstream-port  - M2400 TCP port (default: 52211)');
    stderr.writeln(
        '  listen-port    - Local port for clients (default: 52211)');
    exit(1);
  }

  final upstreamHost = args[0];
  final upstreamPort = args.length > 1 ? int.tryParse(args[1]) : 52211;
  if (upstreamPort == null) {
    stderr.writeln('Error: invalid upstream port "${args[1]}"');
    exit(1);
  }
  final listenPort = args.length > 2 ? int.tryParse(args[2]) : 52211;
  if (listenPort == null) {
    stderr.writeln('Error: invalid listen port "${args[2]}"');
    exit(1);
  }

  final proxy = M2400Proxy(
    upstreamHost: upstreamHost,
    upstreamPort: upstreamPort,
    listenPort: listenPort,
  );

  void shutdown() {
    stdout.writeln('\nShutting down...');
    proxy.shutdown().then((_) {
      stdout.writeln('Done.');
      exit(0);
    });
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }

  stdout.writeln('M2400 Proxy');
  stdout.writeln('  Upstream: $upstreamHost:$upstreamPort');
  stdout.writeln('  Listen:   0.0.0.0:$listenPort');
  stdout.writeln('Press Ctrl+C to stop.\n');

  await proxy.start();
}
