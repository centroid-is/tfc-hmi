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
// The adapter is deliberately not on the package barrel (the seam type
// `TimeseriesSink` is the public surface); the composition root reaches it by
// its src path, exactly as 8b-02 recorded.
import 'package:tfc_relay_local/src/collect/timescale_sink.dart';
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
  //
  // **`ProductionFilter` is not a preference either, and leaving it out was a
  // bug that shipped silently.** `package:logger`'s default is
  // `DevelopmentFilter`, whose whole body is inside an `assert` — so it logs
  // only when asserts are evaluated, and *"in release mode ALL logs are
  // omitted"* (`development_filter.dart:7`). `dart run` does not enable
  // asserts and `dart compile exe` cannot, so the gateway that runs at the
  // plant printed **nothing at all**: not the links it opened, not the port it
  // bound, not the reserved keys it refused, not the signal it stopped on.
  // Measured: a 25-second run against a live in-process PLC produced an empty
  // log and exit 0. A process whose only operator-facing output is suppressed
  // by its logging library's default is one nobody can diagnose, and the fault
  // it hides is the one that made somebody look.
  final log = Logger(
    filter: ProductionFilter(),
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

  // Collection: built only when the config's deliberate two-field act says
  // so — no block, or enabled: false, means no database object exists at all.
  TimescaleSink? sink;
  CollectionRunner? runner;
  final collection = config.collection;
  if (collection != null && collection.enabled) {
    sink = TimescaleSink(collection, publisherId: config.server.publisherId);
    // `unroutable:` is the router ingest's own verdict — the keys whose
    // mappings were refused at the door. Passed rather than re-derived, so
    // the plan cannot drift from `KeyRouter`'s rules; `Gateway.refusedKeys`
    // is NOT a substitute (it holds only the PIPE-prefix squatters).
    final plan = CollectionPlan.from(
      mappings,
      collection,
      unroutable: gateway.plant.router.lastIngest.rejected.keys.toSet(),
    );
    await sink.start();
    runner = CollectionRunner(
      plan: plan,
      stateMan: gateway.plant,
      sink: sink,
      health: gateway.plant.collectHealth,
    );
    // NOT awaited (WR-03): start() awaits ensureTable per entry, and on a
    // database that connects fast but answers slowly each of those is a
    // real round trip bounded only by queryTimeout — ~430 entries × 30 s of
    // sequential awaits between process start and the WebSocket existing.
    // Panels must never wait on retention registration: a database that is
    // down, slow or absent costs collection and nothing else. The startup
    // log moves to completion, where entryFailures is finally a fact; the
    // runner's own per-entry guards mean the future cannot reject in
    // ordinary operation, and the handler is for the day that stops being
    // true. stop() racing a still-starting runner is safe: collectEntry
    // re-checks _stopped across its awaits (WR-04).
    final started = runner;
    unawaited(runner.start().then((_) {
      // ONE line, 08-13's rule: a gateway whose startup is forty lines is
      // one whose real problem is invisible.
      log.i('collecting ${plan.entries.length} keys into '
          '"${collection.tablePrefix}"-prefixed tables '
          '(${plan.rejected.length} rejected, ${plan.adjusted.length} '
          'retention-adjusted, ${started.entryFailures.length} failed to '
          'start)');
    }).catchError((Object error, StackTrace stack) {
      log.e('collection failed to start', error: error, stackTrace: stack);
    }));
  }

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
  // The handler is a named function in `lib/` — see [gatewayShutdown] for the
  // two ways the version that lived here failed, and for why "a bin/ file is
  // not addressable by any package: URI" is the reason nothing caught them.
  // Announcements off, then the server, then the links: see [Gateway.stop] for
  // what the reverse order serves a panel.
  final shutdown = gatewayShutdown(
    // Collection is torn down FIRST, with the plant side it subscribes to,
    // for 08-13's shutdown-ordering reason read from the historian's side:
    // the runner is a consumer of the plant's store and a holder of database
    // buffers, so it must stop sampling before the links it samples are
    // disposed, and its last rows must be flushed while the sink still owns
    // a connection. Then `Gateway.stop` does what it always did: the server
    // (so panels see a closed socket, not confident stale numbers), then the
    // plant and its links.
    stop: () async {
      await runner?.stop();
      await sink?.close();
      await gateway.stop();
    },
    stopped: stopped,
    onSignal: (signal) => log.i('$signal: stopping'),
    onError: (error, stack) =>
        log.e('stop failed; exiting anyway', error: error, stackTrace: stack),
  );

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
