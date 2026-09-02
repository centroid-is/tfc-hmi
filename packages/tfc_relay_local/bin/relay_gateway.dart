/// The gateway process.
///
/// **The whole composition is visible on one screen below**, and that is this
/// file's entire value. Everything it does is a named function in
/// `lib/src/gateway_config.dart`; if `main` ever needs a second screen, the
/// thing that grew belongs in a function there rather than here.
///
/// Read it as four lines: build the plant, connect the plant, serve the plant,
/// and stop in the reverse order.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:tfc_dart/core/state_man.dart' show KeyMappings;
import 'package:tfc_relay_local/tfc_relay_local.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(gatewayUsage);
    return;
  }
  final path = _configPath(args);
  if (path == null) {
    stderr.write(gatewayUsage);
    exitCode = 64; // EX_USAGE
    return;
  }

  // The level is chosen, not defaulted: this repository has already measured
  // `trace` + `PrettyPrinter` turning per-node logging into seconds of lag
  // (PR #210). A gateway logs conditions, not events.
  final log = Logger(
    level: Level.info,
    printer: PrefixPrinter(SimplePrinter(printTime: true)),
  );

  final config = GatewayConfig.readFile(path);
  final mappings = KeyMappings.fromJson(
      (jsonDecode(File(config.keyMappingsPath).readAsStringSync()) as Map)
          .cast<String, dynamic>());

  final gateway =
      await buildGateway(config, mappings: mappings, log: log);

  // Once, at boot, naming every offender — HLTH-03 (T-08-51). Not one line per
  // panel that asks for one, and not a refusal to start: the rest of the file
  // is fine and a plant does not go dark for a typo.
  if (gateway.refusedKeys.isNotEmpty) {
    log.w('${gateway.refusedKeys.length} keymapping entries claim the '
        'reserved PIPE. prefix and were refused; every other entry is '
        'served: ${gateway.refusedKeys.join(', ')}');
  }

  // SRV-08's status wiring is NOT here. It was, for exactly as long as it took
  // the end-to-end leg to notice that a gateway composed by anything but this
  // file announced nothing: it belongs to `buildGateway`, beside everything
  // else the composition owns, and `Gateway.stop` cancels it.
  await gateway.plant.start();
  await gateway.server.start();

  for (final link in config.links) {
    log.i('upstream ${link.alias}: '
        '${upstreamProtocolWireNames.entries.firstWhere(
              (e) => e.value == link.protocol,
            ).key} ${link.endpoint}');
  }
  log.i('serving on ${config.server.address.address}:${gateway.server.port}, '
      'TLS ${config.server.tls == null ? 'OFF' : 'on'}');

  final stopped = Completer<void>();
  Future<void> shutdown(ProcessSignal signal) async {
    if (stopped.isCompleted) return;
    log.i('$signal: stopping');
    // Announcements off, then the server, then the links — see [Gateway.stop]
    // for what the reverse order serves a panel.
    await gateway.stop();
    stopped.complete();
  }

  final sigint = ProcessSignal.sigint.watch().listen(shutdown);
  // SIGTERM is what a container runtime sends, and it is not deliverable on
  // Windows; the gateway's deployment target is Linux, and a listener that
  // throws at boot on a developer's machine would be worse than a signal that
  // is never raised there.
  final sigterm =
      Platform.isWindows ? null : ProcessSignal.sigterm.watch().listen(shutdown);

  await stopped.future;
  await sigint.cancel();
  await sigterm?.cancel();
}

/// `--config <path>` or `--config=<path>`. Both, because both get typed.
String? _configPath(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--config' && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('--config=')) return arg.substring('--config='.length);
  }
  return null;
}
