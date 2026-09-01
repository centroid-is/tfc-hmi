/// A real in-process OPC UA server, a real client, and a seam to break the
/// wire between them.
///
/// The precedent is `packages/tfc_dart/test/subscription_inactivity_test.dart`,
/// which has been standing an in-process `Server` up in CI on ubuntu and macOS
/// on every push and which nobody had noticed: `Server(port: …)`,
/// `server.start()`, `addVariableNode`, a `Timer.periodic(10 ms,
/// server.runIterate)` driver, a real `Client`, and a byte-level TCP proxy in
/// between. This fixture is that arrangement with three changes — the port is
/// not a literal ([withFreePort]), the proxy is Phase 2's [FaultProxy] rather
/// than the buffer-only one, and the levers each carry the plan that earned
/// them.
///
/// **Teardown order is the fixture's whole content.** Cancel the iterate
/// driver, `shutdown()` inside `try/catch` because a test may have killed the
/// server already, then `delete()`. Getting it wrong does not fail a test — it
/// SEGVs the VM, which is project memory from the open62541_dart repo
/// (state-after-delete). The existing fixture's order (`:51-57`) is copied
/// exactly and this comment is why.
library;

import 'dart:async';

import 'package:open62541/open62541.dart';
import 'package:tfc_stateman_contract/faults.dart';

import 'free_port.dart';

/// How often the iterate driver turns the server's crank.
///
/// 10 ms, the existing fixture's figure. `runIterate` is a blocking FFI call,
/// so this is also the granularity at which the test isolate's event loop is
/// interrupted — which is why `dart_test.yaml` in this package pins
/// `concurrency: 1`.
const Duration serverIteratePeriod = Duration(milliseconds: 10);

/// The namespace the fixture's own nodes live in. Namespace 0 is the server's,
/// and writing into it is how a test accidentally edits `ServerStatus`.
const int fixtureNamespace = 1;

/// The node id one gateway key maps to.
///
/// A string node id spelled with the key itself, so a failure message names
/// the tag the operator would have typed rather than a number.
NodeId fixtureNodeId(String key) => NodeId.fromString(fixtureNamespace, key);

/// A binding value with an explicit OPC UA type.
///
/// **An `int` has no deducible OPC UA type and the binding says so by
/// throwing** (`opcua_serializer.dart:334`): Int16/Int32/Int64/UInt* are all
/// candidates and guessing one silently would produce a node whose data type
/// disagrees with every later write. `subscription_inactivity_test.dart:43-44`
/// passes `typeId: NodeId.int32` for the same reason; this is that, in one
/// place, so no lever can forget it.
DynamicValue fixtureValue(Object? value, {String? name}) => DynamicValue(
      value: value,
      name: name,
      typeId: value is int ? NodeId.int32 : null,
    );

/// An in-process OPC UA server with the levers this phase's plans need.
///
/// Two kinds of node, because the binding gives them different powers and the
/// difference is load-bearing:
///
///  * **Plain variable nodes** ([valueKeys]) hold a stored `UA_DataValue`. The
///    server stamps `sourceTimestamp` when the value is written and that stamp
///    is what every later monitored-item sample reports — which is the only
///    way to produce a source instant that is measurably *older than its own
///    arrival* without touching the pinned binding. 08-07's headline arm needs
///    exactly that.
///  * **Data-source nodes** ([writeKeys]) are backed by a read callback and an
///    optional write callback (`server.dart:443`). They can count writes — the
///    behavioural no-retry arm counts at the server, not at the adapter — and
///    they can fail a read on demand, which is how a *live* node produces a Bad
///    status. Their source timestamp is stamped per sample, so they are the
///    wrong node for the offset arm and the right one for everything else.
final class OpcUaServerFixture {
  OpcUaServerFixture._({
    required this.port,
    required this.valueKeys,
    required this.writeKeys,
    required this.logLevel,
    required Server server,
    required Timer driver,
    required this.proxy,
  })  : _server = server,
        _driver = driver;

  /// The port the OPC UA server itself is listening on.
  final int port;

  /// Keys served by plain variable nodes.
  final List<String> valueKeys;

  /// Keys served by data-source nodes: writable, countable, failable.
  final List<String> writeKeys;

  /// The server's log level, kept so [restart] can rebuild an identical one.
  final LogLevel logLevel;

  /// The fault seam, or null when the fixture was built without one.
  ///
  /// Present, the client connects through it and every one of Phase 2's eight
  /// modes is available against `opc.tcp` unchanged: the injection is at the
  /// TCP level and a server at `MessageSecurityMode.NONE` has no TLS record
  /// layer to swallow a mid-frame cut.
  final FaultProxy? proxy;

  Server _server;
  Timer _driver;
  bool _disposed = false;

  /// The last value written to each plain node, so [restart] can restore them.
  final Map<String, DynamicValue> _plainValues = <String, DynamicValue>{};

  /// The current value of each data-source node.
  final Map<String, DynamicValue> _sourceValues = <String, DynamicValue>{};

  /// Data-source keys whose read callback is currently made to throw.
  final Set<String> _failingReads = <String>{};

  /// How many writes each data-source node has been handed **by the server**.
  ///
  /// This is the counter the behavioural no-retry arm reads. It counts at the
  /// far end of the wire, which is the only place that can tell a re-issued
  /// write from a re-tried one.
  final Map<String, int> _writeCounts = <String, int>{};

  /// Everything each data-source node was written, in order.
  final Map<String, List<DynamicValue>> _writeLog =
      <String, List<DynamicValue>>{};

  /// The endpoint a client should dial.
  ///
  /// Through the proxy when there is one — which is the point of having it:
  /// nothing else in the fixture changes, so a fault leg and a clean leg
  /// exercise the same adapter over the same code path.
  String get endpoint => proxy == null
      ? 'opc.tcp://127.0.0.1:$port'
      : 'opc.tcp://127.0.0.1:${proxy!.port}';

  /// Stands the server up, with an optional fault proxy in front of it.
  static Future<OpcUaServerFixture> start({
    Iterable<String> valueKeys = const <String>[],
    Iterable<String> writeKeys = const <String>[],
    bool viaFaultProxy = false,
    LogLevel logLevel = LogLevel.UA_LOGLEVEL_ERROR,
  }) async {
    final values = valueKeys.toList();
    final writes = writeKeys.toList();

    final built = await withFreePort<({Server server, int port})>((port) async {
      final server = Server(port: port, logLevel: logLevel);
      server.start();
      return (server: server, port: port);
    });

    final fixture = OpcUaServerFixture._(
      port: built.port,
      valueKeys: values,
      writeKeys: writes,
      logLevel: logLevel,
      server: built.server,
      // Armed immediately: the nodes below are added while the crank is
      // already turning, exactly as the existing fixture does it.
      driver: Timer.periodic(
          serverIteratePeriod, (_) => _crank(() => built.server)),
      proxy: viaFaultProxy ? FaultProxy(targetPort: built.port) : null,
    );
    fixture._addNodes();
    await fixture.proxy?.start();
    return fixture;
  }

  /// One turn of the crank, guarded.
  ///
  /// A `runIterate` on a server a test has already shut down is not a test
  /// failure worth reporting and it must not become an unhandled zone error;
  /// the teardown cancels this timer first precisely so it normally cannot
  /// happen, and this guard is what makes "normally" not matter.
  static void _crank(Server Function() server) {
    try {
      server().runIterate();
    } catch (_) {
      // Deliberately swallowed. See above.
    }
  }

  void _addNodes() {
    for (final key in valueKeys) {
      final seed = _plainValues[key] ?? fixtureValue(0, name: key);
      _server.addVariableNode(fixtureNodeId(key), seed);
      _plainValues[key] = seed;
    }
    for (final key in writeKeys) {
      _writeCounts.putIfAbsent(key, () => 0);
      _writeLog.putIfAbsent(key, () => <DynamicValue>[]);
      _sourceValues.putIfAbsent(key, () => fixtureValue(0, name: key));
      _server.addDataSourceVariableNode(
        fixtureNodeId(key),
        browseName: key,
        onRead: () {
          if (_failingReads.contains(key)) {
            // A throw out of the read callback becomes UA_STATUSCODE_
            // BADINTERNALERROR on the wire (`server.dart:318-320`), which is
            // exactly the 0x80020000 08-01's probe measured. That is a Bad
            // status on a node that still exists — the other half of the
            // quality table from a deleted node's BadNodeIdUnknown.
            throw StateError('fixture: read of $key is failing on purpose');
          }
          return _sourceValues[key]!;
        },
        onWrite: (value) {
          _writeCounts[key] = (_writeCounts[key] ?? 0) + 1;
          _writeLog[key]!.add(value);
          _sourceValues[key] = value;
        },
      );
    }
  }

  // ------------------------------------------------------------- the levers
  //
  // Each names the plan that earned it. Nothing may be added here without a
  // test in the same commit — a lever with no caller is a fixture growing a
  // surface nobody is judged by.

  /// **08-07.** Publishes [value] for [key].
  ///
  /// On a plain node this writes the stored `UA_DataValue`, and the server
  /// stamps its `sourceTimestamp` **now** and keeps it. Every later sample
  /// reports that instant, so a write followed by a wait produces a value
  /// whose source time is provably older than its arrival.
  void setValue(String key, Object? value) {
    final shaped = fixtureValue(value, name: key);
    if (_sourceValues.containsKey(key)) {
      _sourceValues[key] = shaped;
      return;
    }
    _plainValues[key] = shaped;
    _server.write(fixtureNodeId(key), shaped);
  }

  /// **08-07.** Makes [key]'s reads fail (or stop failing) at the server.
  ///
  /// Data-source keys only — a plain node has no callback to fail. The Bad
  /// code the client sees is `BadInternalError`; for `BadNodeIdUnknown` use
  /// [deleteNode], because the two are different instructions to an operator
  /// and this fixture must be able to produce both.
  void setReadFails(String key, {bool failing = true}) {
    if (!_sourceValues.containsKey(key)) {
      throw ArgumentError.value(key, 'key',
          'setReadFails works on a data-source node; pass it in writeKeys');
    }
    if (failing) {
      _failingReads.add(key);
    } else {
      _failingReads.remove(key);
    }
  }

  /// **08-08.** The tag leaves the address space.
  ///
  /// A monitored item on a deleted node reports `BadNodeIdUnknown`, which the
  /// adapter maps to `Quality.errorConfig` — waiting will not bring it back,
  /// and that is a different thing to tell an operator than a comms fault.
  void deleteNode(String key) {
    _server.deleteNode(fixtureNodeId(key));
    _plainValues.remove(key);
    _sourceValues.remove(key);
  }

  /// **08-07.** How many writes the *server* has accepted for [key].
  int writeCount(String key) => _writeCounts[key] ?? 0;

  /// **08-07.** Everything the server was written for [key], in order.
  List<DynamicValue> writeLog(String key) =>
      List<DynamicValue>.unmodifiable(_writeLog[key] ?? const <DynamicValue>[]);

  /// **08-08.** Shuts the server down and brings a new one up on the same port.
  ///
  /// `Server_ServerStatus_StartTime` (ns=0, i=2257) genuinely moves, which is
  /// what makes the epoch arm a measurement rather than an assertion about a
  /// counter this fixture incremented. The port is held across the gap by
  /// nothing at all — there is a window in which it is free, which is the same
  /// race [freePort] documents and the same reason the caller retries.
  ///
  /// Write counts survive; node values are restored from what was last set, so
  /// a test that restarts does not also have to re-seed.
  Future<void> restart() async {
    _driver.cancel();
    try {
      _server.shutdown();
    } catch (_) {
      // Already down. See the teardown comment.
    }
    _server.delete();
    // The OS holds the listening socket briefly after a close; giving it a
    // turn of the event loop is not a fix for that and is not pretending to
    // be one — `Server.start()` throws if the port is still taken and the
    // caller's retry is what handles it.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final replacement = Server(port: port, logLevel: logLevel);
    replacement.start();
    _server = replacement;
    _driver =
        Timer.periodic(serverIteratePeriod, (_) => _crank(() => replacement));
    _addNodes();
  }

  /// Tears the fixture down in the one order that does not crash the VM.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // 1. The driver first. A `runIterate` racing a `shutdown()` is the SEGV.
    _driver.cancel();
    // 2. The proxy next, so nothing is still trying to reach the server.
    await proxy?.shutdown();
    // 3. shutdown() inside try/catch: a test may have killed the server
    //    already (`subscription_inactivity_test.dart:51-57` does exactly
    //    this, and says the same thing).
    try {
      _server.shutdown();
    } catch (_) {
      // Already shut down.
    }
    // 4. delete() last, and only after shutdown. The binding refuses the
    //    other order (`server.dart:1333-1336`) and the native side does not.
    _server.delete();
  }
}
