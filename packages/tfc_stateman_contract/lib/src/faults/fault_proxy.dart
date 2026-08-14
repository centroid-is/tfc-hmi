/// A TCP proxy that can break the connection on purpose, one lever at a time.
///
/// A fresh rewrite of `packages/tfc_dart/test/proxy.dart` rather than an
/// extension of it (CONTEXT). Two of that file's behaviours are hard-won and
/// deliberately kept — binding on port 0 with a [port] accessor, and
/// destroying both ends of every pair on close. Three of its habits are
/// deliberately not: the ungated `to.add(data)` in both directions (RESEARCH
/// Finding 7: 4463 MB of RSS in four seconds against a stalled consumer, which
/// is why every byte here goes through a [DelayLine]), the 100 ms sleep
/// inside `reject()` — a guess about someone else's scheduler, simultaneously
/// too slow for every run and too short for a loaded CI box, which is what
/// `within()` exists to replace — and the doc claiming `destroy()` sends a
/// reset
/// (Finding 1: on POSIX it is a clean FIN except by coincidence — see
/// `socket_ops.dart`).
///
/// **Every mode is declared before any is implemented.** [faultModes] names
/// all eight, each has its lever on this class today, and the levers whose
/// behaviour has not landed throw [UnimplementedError] naming the plan. The
/// alternative — adding levers as the modes arrive — means a test written
/// against a mode that does not exist yet fails to compile, which is fine, but
/// a lever that exists and quietly does nothing is not: the mode test passes,
/// the fault was never injected, and CI reports coverage of precisely the
/// property that is missing.
///
/// **Loopback only.** The listener binds [InternetAddress.loopbackIPv4] and
/// there is no option to widen it. A process whose whole purpose is to sever
/// connections, withhold responses and reset sockets must not be reachable
/// from another machine, and a `bindAddress` parameter is how that becomes
/// possible by accident on somebody's laptop.
///
/// **Lever names echo `StateManHarness`** where the concepts overlap
/// (CONTEXT), and the correspondence is stated on both sides:
/// `StateManHarness.disconnectUpstream` already names `flap(down)` as its
/// proxy counterpart, and `reconnectUpstream` names `flap(up)`. A case written
/// against one transfers to the other unchanged, which is the entire reason
/// Phase 3 and Phase 4 can run their halves of the contract suite through
/// this proxy without rewriting their assertions.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'delay_line.dart';
import 'socket_ops.dart';

/// The eight fault modes, as data.
///
/// The one place that knows the proxy has eight modes — the same
/// registry-as-data argument `tfc_stateman_contract.dart:89-104` makes for the
/// seven contract sub-suites. Plan 02-14's integrity sweep iterates this list
/// in both directions: every named mode must have a test that proves it bites,
/// and every mode test must name a mode declared here. Both failures are
/// silent otherwise, and they are different failures — an unnamed mode is one
/// nobody is testing, a named mode with no test is one that reads as
/// delivered.
const faultModes = <String>[
  'flap',
  'latency',
  'throttle',
  'blackhole',
  'cutMidFrame',
  'killOnce',
  'reject',
  'bufferServerToClient',
];

/// How long the proxy waits for the upstream server before giving up.
const _upstreamConnectTimeout = Duration(seconds: 5);

/// A loopback TCP proxy in front of an upstream server.
final class FaultProxy {
  FaultProxy({
    required this.targetPort,
    this.listenPort = 0,
  });

  /// The port of the upstream server this proxy forwards to, on loopback.
  final int targetPort;

  /// The port to bind. 0 — the default — lets the OS assign one.
  ///
  /// Tests should leave it at 0 and read [port]: a fixed port collides with
  /// the other tests in the suite and with whatever else is running on a CI
  /// box, and the collision surfaces as a fault-mode failure.
  final int listenPort;

  ServerSocket? _server;
  StreamSubscription<Socket>? _accepts;
  final Set<_ProxiedPair> _pairs = <_ProxiedPair>{};
  bool _shutDown = false;
  int? _lastUpstreamConnectErrno;

  /// Where jitter is drawn from.
  ///
  /// Not seeded: the property under test is that successive round trips
  /// *differ* and all land inside the band, which a fixed seed would turn into
  /// a check that one particular sequence of draws still lands there.
  final Random _jitterSource = Random();

  Duration? _latency;
  Duration? _jitter;

  /// The high-water reading of every pair that has already closed.
  int _retiredPeakPendingBytes = 0;

  /// The per-chunk delay every line gets, rebuilt when [latency] or [jitter]
  /// changes and handed to pairs accepted afterwards.
  ///
  /// Null when neither lever is set, which is how a line goes back to the
  /// undelayed write path rather than to a closure returning zero.
  Duration Function()? _perChunkDelay;

  /// The port this proxy is listening on.
  ///
  /// Throws [StateError] before [start] has completed, rather than the
  /// null-check failure the original proxy's `_server!.port` produced — a test
  /// that forgot to await `start()` should be told that, not shown a line
  /// number in this file.
  int get port {
    final server = _server;
    if (server == null) {
      throw StateError('the proxy has no port until start() has completed; '
          'bind first, then read port — the OS assigns it during the bind');
    }
    return server.port;
  }

  /// Whether the listener is up.
  bool get isRunning => _server != null;

  /// How many client↔upstream pairs are alive right now.
  ///
  /// The observable behind the socket-leak criterion's per-cycle half: a cycle
  /// that ends with a live pair has leaked two descriptors, and this says so
  /// before the fd count does.
  int get livePairs => _pairs.length;

  /// The most any one direction of any one pair has ever held.
  ///
  /// The bounded-memory criterion restated at the proxy, where a test can
  /// reach it: `DelayLine.peakPendingBytes` is the real observable, but the
  /// lines belong to pairs this class owns and a test has no other handle on
  /// them. Sampling RSS instead would measure the whole test host, including
  /// the payload the firehose is generating, and could not tell a bounded
  /// queue from a lucky garbage collection.
  ///
  /// Retired pairs are remembered. A pair whose peak vanished when its
  /// connection closed would let a test that tore its client down first read
  /// zero and pass, which is the worst kind of green: the run that actually
  /// grew is the one that ends with a closed connection.
  int get peakPendingBytes {
    var peak = _retiredPeakPendingBytes;
    for (final pair in _pairs) {
      final pairPeak = pair.peakPendingBytes;
      if (pairPeak > peak) peak = pairPeak;
    }
    return peak;
  }

  /// The errno of the last failed upstream connection, or null if none failed.
  ///
  /// Read through `errnoOf` because `Socket.connect` throws a bare [OSError]
  /// against a resetting listener (RESEARCH Finding 9), which is not a
  /// [SocketException] and so escapes the natural catch clause entirely.
  int? get lastUpstreamConnectErrno => _lastUpstreamConnectErrno;

  /// Binds the listener. A second call while running is a no-op.
  Future<void> start() async {
    if (_server != null) return;
    if (_shutDown) {
      throw StateError('this proxy has been shut down; build a new one rather '
          'than restarting it, so a test cannot silently reuse a listener '
          'another test tore down');
    }
    final server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, listenPort);
    _server = server;
    _accepts = server.listen(_accept);
  }

  /// Closes the listener and every live pair. Terminal, and idempotent.
  ///
  /// Registered with `addTearDown` immediately after [start] by every test in
  /// this phase, and called in the body by some of them, so a second call has
  /// to be a no-op rather than a throw — otherwise an ordinary teardown fails
  /// and the failure is attributed to whichever mode the test was about.
  Future<void> shutdown() async {
    if (_shutDown) return;
    _shutDown = true;
    final accepts = _accepts;
    _accepts = null;
    final server = _server;
    _server = null;
    await accepts?.cancel();
    try {
      await server?.close();
    } catch (_) {
      // Cancelling the accept subscription already closed it on some
      // platforms. The listener is down either way, which is what was asked.
    }
    for (final pair in List.of(_pairs)) {
      await pair.close();
    }
    _pairs.clear();
  }

  // ---------------------------------------------------------------------
  // The eight levers. Declared now, implemented one plan at a time.
  // ---------------------------------------------------------------------

  /// The link goes down for [down], comes back for [up], and repeats.
  ///
  /// The proxy counterpart of `StateManHarness.disconnectUpstream` (the down
  /// half) and `reconnectUpstream` (the up half), which name it from the other
  /// side. A case written against either transfers unchanged.
  ///
  /// Assertions about a flapping proxy must be about windows, not instants:
  /// RESEARCH Finding 10 measured a connect attempt completing on the far side
  /// of a state transition, so the flag read at assertion time did not
  /// describe what the connection experienced.
  void flap(Duration up, Duration down) => _notYet('flap', '02-11');

  /// One-way delay applied to every chunk in both directions.
  ///
  /// Applied per direction, so an application round trip through the proxy
  /// costs `2 * value`. Overhead is a small constant, 1–2.5 ms per direction
  /// (Finding 6), so tests assert `inInclusiveRange(2 * d, 2 * d + 20ms)`
  /// rather than a percentage band — the constant is bigger than a percentage
  /// allows at 50 ms and smaller than one allows at 500 ms.
  ///
  /// Live: setting it reaches the pairs that are already open as well as the
  /// ones accepted later. A lever that only worked before connect could not
  /// express "the link degrades while the client is connected", which is the
  /// only shape the slow-link scenarios come in. Null turns it off.
  ///
  /// Setter-only. A getter would answer with the configured number, and the
  /// question worth asking — what did the connection actually experience — is
  /// answered by measuring a round trip, which is what `latency_test.dart`
  /// does.
  set latency(Duration? value) {
    _latency = value;
    _applyDelay();
  }

  /// Random extra delay added on top of [latency], redrawn per chunk.
  ///
  /// Part of the `latency` mode rather than a ninth one — hence no separate
  /// entry in [faultModes] and no separate test file. Drawn uniformly from
  /// zero to this value, independently per chunk and per direction, so a round
  /// trip lands in `[2d, 2d + 2 * jitter + overhead]`.
  set jitter(Duration? value) {
    _jitter = value;
    _applyDelay();
  }

  /// Bytes per second the proxy will forward.
  ///
  /// Measured over a window of at least 3 s with a ±5% band (Assumption A5),
  /// because the interesting failure is a sustained rate, not an instant one.
  set throttleBytesPerSec(int? value) => _notYet('throttle', '02-04');

  /// The link goes silent while the sockets stay up — a true half-open.
  ///
  /// The proxy counterpart of `StateManHarness.disconnectUpstream`. This is
  /// the fault the whole project is built against: a peer that has not closed
  /// anything and has simply stopped answering, which no `onDone` will ever
  /// report.
  void blackhole() => _notYet('blackhole', '02-09');

  /// Deliver exactly [n] bytes of the next response, then end the connection.
  ///
  /// Cuts with FIN, never with a reset: Finding 3 measured an RST discarding
  /// the peer's unread data, so `cutMidFrame(137)` delivered 0 of 137 bytes in
  /// 50 of 50 runs against a peer that was not actively reading. A mode built
  /// on a reset passes a naive test and silently does nothing in production.
  void cutMidFrame(int n) => _notYet('cutMidFrame', '02-07');

  /// Reset the current connection once, then serve normally again.
  ///
  /// The reset half of the pair [cutMidFrame] is the FIN half of:
  /// `SO_LINGER{1,0}` then `destroy()`, via `forceReset` in `socket_ops.dart`,
  /// which measured a genuine RST in 50 of 50 runs.
  void killOnce() => _notYet('killOnce', '02-07');

  /// Destroy live connections and refuse new ones, keeping the listener open.
  ///
  /// The listener stays bound on purpose: on Windows a closed listener turns a
  /// connect attempt into a slow timeout instead of a fast refusal. The price
  /// is POSIX determinism — Finding 8 measured the handshake racing the reset,
  /// so a client sees either a failed connect or a connect that is immediately
  /// reset. Tests assert a terminal failure within a budget, never an errno.
  Future<void> reject() => _notYet('reject', '02-09');

  /// Withhold server→client traffic while still forwarding client→server.
  ///
  /// The asymmetry is the point, and it is why this is one mode rather than
  /// half of [blackhole]: forwarding client→server keeps the server side alive
  /// and answering, so the peer does not time out while its replies are held.
  set bufferServerToClient(bool value) =>
      _notYet('bufferServerToClient', '02-09');

  /// Rebuilds the per-chunk delay and pushes it to every live pair.
  ///
  /// Both directions of every pair get the *same* closure, and it redraws its
  /// jitter on each call, so the two directions of one round trip draw
  /// independently rather than sharing one number.
  void _applyDelay() {
    _perChunkDelay = _buildDelay();
    for (final pair in _pairs) {
      pair.applyChunkDelay(_perChunkDelay);
    }
  }

  /// The delay function the current [latency] and [jitter] describe.
  Duration Function()? _buildDelay() {
    final base = _latency ?? Duration.zero;
    final spread = _jitter ?? Duration.zero;
    if (base <= Duration.zero && spread <= Duration.zero) return null;
    if (spread <= Duration.zero) return () => base;
    // `+ 1` because `nextInt` is exclusive at the top and the spread reads as
    // an inclusive maximum everywhere it is written down.
    final spreadMicros = spread.inMicroseconds;
    return () =>
        base + Duration(microseconds: _jitterSource.nextInt(spreadMicros + 1));
  }

  Never _notYet(String mode, String plan) => throw UnimplementedError(
      'mode $mode lands in plan $plan; the lever is declared now and throws '
      'rather than accepting the setting silently, because a mode that can be '
      'switched on and does nothing makes its own test pass');

  Future<void> _accept(Socket client) async {
    if (_shutDown) {
      client.destroy();
      return;
    }
    final Socket upstream;
    try {
      upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        targetPort,
        timeout: _upstreamConnectTimeout,
      );
    } catch (error) {
      // Object, not SocketException: Finding 9 measured a bare OSError here,
      // which a narrowed clause would let escape into an unhandled async error
      // attributed to whichever test was running.
      _lastUpstreamConnectErrno = errnoOf(error);
      client.destroy();
      return;
    }
    if (_shutDown) {
      client.destroy();
      upstream.destroy();
      return;
    }
    final pair = _ProxiedPair(client, upstream);
    // Before `start`, so the first chunk of a connection accepted while a
    // lever is set is already subject to it. A pair that picked its settings
    // up one event loop later would deliver the opening bytes of every
    // connection unmodified, which is exactly the traffic a handshake test
    // cares about.
    pair.applyChunkDelay(_perChunkDelay);
    _pairs.add(pair);
    pair.start(_retire);
  }

  /// Drops a closed pair, keeping the one number that outlives it.
  void _retire(_ProxiedPair pair) {
    final peak = pair.peakPendingBytes;
    if (peak > _retiredPeakPendingBytes) _retiredPeakPendingBytes = peak;
    _pairs.remove(pair);
  }
}

/// One client↔upstream conversation: two delay lines and two sockets.
final class _ProxiedPair {
  _ProxiedPair(this.client, this.upstream)
      : toUpstream = DelayLine(destination: upstream),
        toClient = DelayLine(destination: client);

  /// The socket this proxy's listener accepted from the client.
  final Socket client;

  /// The socket this proxy opened to the upstream server.
  ///
  /// The one RESEARCH Finding 11 measured leaking exactly one descriptor per
  /// cycle: when its peer went away the stream ended, and nothing destroyed
  /// the socket. [close] below is what stops that, and `test/faults/
  /// leak_test.dart` is what stops [close] from quietly losing the line again.
  final Socket upstream;

  final DelayLine toUpstream;
  final DelayLine toClient;
  bool _closed = false;

  /// The most either direction of this pair has ever held.
  int get peakPendingBytes => toUpstream.peakPendingBytes > toClient.peakPendingBytes
      ? toUpstream.peakPendingBytes
      : toClient.peakPendingBytes;

  /// Applies a per-chunk delay to **both** directions.
  ///
  /// Both, because `latency` is documented as a one-way delay and a round trip
  /// crosses the proxy twice: setting it on one direction would halve the
  /// number every test measures, and the failure would read as a scheduler
  /// problem rather than as a missing line here.
  void applyChunkDelay(Duration Function()? delay) {
    toUpstream.chunkDelay = delay;
    toClient.chunkDelay = delay;
  }

  void start(void Function(_ProxiedPair pair) onClosed) {
    // A destroyed socket completes `done` with an error nobody is waiting for,
    // which package:test reports as an unhandled async error against whichever
    // test happens to be running when it lands.
    unawaited(client.done.catchError((Object _) => client));
    unawaited(upstream.done.catchError((Object _) => upstream));
    toUpstream.start(client);
    toClient.start(upstream);
    unawaited(_closeWhenEitherEnds(onClosed));
  }

  /// Tears the pair down as soon as either direction ends.
  ///
  /// This is the `onDone` / `onError` destroy Finding 11 called for, moved one
  /// level out: each [DelayLine] treats the end of its source — clean or
  /// errored — as the end of that direction, and the pair owns both sockets
  /// because both directions share them.
  Future<void> _closeWhenEitherEnds(
      void Function(_ProxiedPair pair) onClosed) async {
    await Future.any<void>([toUpstream.done, toClient.done]);
    await close();
    onClosed(this);
  }

  /// Cancels both directions and destroys **both** sockets.
  ///
  /// Each destroy in its own try/catch: a first socket that throws must not
  /// leave the second one open, which is the shape the leak this file's tests
  /// exist to catch took in the first place.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await toUpstream.close();
    await toClient.close();
    try {
      client.destroy();
    } catch (_) {
      // Already gone. The descriptor is closed either way, which is the
      // question the leak criterion asks.
    }
    try {
      upstream.destroy();
    } catch (_) {
      // Same, and this is the one that leaked when it was missing: with this
      // block deleted, `test/faults/leak_test.dart` fails at the +10
      // checkpoint with a delta of 10 — one descriptor per cycle, the rate
      // RESEARCH Finding 11 measured before it was added.
    }
  }
}
