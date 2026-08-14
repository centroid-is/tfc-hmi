/// The rules that govern the eight modes together.
///
/// Two halves, and they are opposite claims about the same table.
///
/// **What composes.** `latency`, `throttle` and `flap` set at once, all three
/// measured in one run: a round trip that costs the configured delay, a
/// sustained rate inside its band, and then the dropout at the end of the
/// up-window. The measurement is the proof. A proxy that accepted all three
/// and silently applied one would pass any test that only checked the levers
/// were set, and RESEARCH Finding 7's closing paragraph is why this works at
/// all — one flush-gated delay line per direction, so the three modes are
/// three gates on one queue rather than three buffers interacting.
///
/// **What cannot coexist.** Every pair in `exclusiveModePairs` throws at the
/// moment the second one is set, naming both. Not at forward time, and not by
/// quietly letting one win: a proxy in a state nobody designed produces a test
/// that passes for a reason its author did not intend, which is the most
/// expensive kind of green in this phase.
///
/// The exclusion half is driven off the table itself, in both orders, so a
/// pair added later without a test here is impossible — the test count is
/// asserted against the table's length at the bottom of the group.
@Tags(['faults'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tfc_stateman_contract/faults.dart';

/// The one-way delay the compose arm sets. A round trip costs twice it.
const _latency = Duration(milliseconds: 50);

/// F20's rate, in bytes per second: one hundred kilobits.
const _rate = 100 * 1000 ~/ 8;

/// The band either side of [_rate] a measurement may land in.
///
/// The same twentieth `throttle_test.dart` uses, and for the same reason
/// (Assumption A5). Composition must not widen it: a throttle that only holds
/// its rate when it is the only mode set is a throttle this phase cannot use.
const _rateTolerance = 0.05;

/// How long the rate is measured over.
///
/// Finding 5's floor. Below about two seconds the bucket's one-second burst
/// cap dominates the reading.
const _rateWindow = Duration(seconds: 3);

/// The up half of the compose arm's flap.
///
/// Long enough to hold a connect, a latency probe and a full rate window with
/// room to spare — the measurements must not straddle a transition, or the
/// arm becomes a test of how fast the runner is.
const _up = Duration(seconds: 8);
const _down = Duration(seconds: 1);

/// What a round trip may cost on top of `2 * latency`.
///
/// `latency_test.dart` allows 20 ms for the proxy's own overhead. This allows
/// 60, because the probe also crosses a throttle that hands out its budget in
/// slices of a fiftieth of a second, and a slice boundary can be waited for in
/// each direction. Still far tighter than the failure it is here to catch: a
/// composition that dropped the latency mode would come back in single-digit
/// milliseconds.
const _roundTripSlack = Duration(milliseconds: 60);

const _probeBytes = 64;
const _blockBytes = 64 * 1024;
const _connectBudget = Duration(seconds: 5);

/// The byte that tells the upstream server to start firehosing.
const _firehose = 0xf0;

void main() {
  test('latency, throttle and flap all bite in the same run', () async {
    final rig = await _Rig.open();
    rig.proxy.latency = _latency;
    rig.proxy.throttleBytesPerSec = _rate;
    rig.proxy.flap(_up, _down);
    final run = Stopwatch()..start();

    final client = await _Client.connect(rig.proxy.port);
    final roundTrip = await client.probe();
    final measured = await client.rateOver(_rateWindow);
    final droppedAt = await client.awaitDrop(budget: _up * 2);
    run.stop();

    print('composed: round trip ${roundTrip.inMilliseconds} ms against '
        '${(_latency * 2).inMilliseconds} ms configured, '
        '${measured.round()} B/s against $_rate B/s, dropout at '
        '${droppedAt.inMilliseconds} ms against an up-window of '
        '${_up.inMilliseconds} ms');

    expect(
      roundTrip.inMicroseconds,
      inInclusiveRange((_latency * 2).inMicroseconds,
          (_latency * 2 + _roundTripSlack).inMicroseconds),
      reason: 'the round trip cost ${roundTrip.inMilliseconds} ms with '
          'latency, throttle and flap all set. Under the floor means the '
          'latency mode was dropped when the others were set — the silent '
          'failure this arm exists for, and one that no assertion about the '
          'levers themselves can see',
    );
    expect(
      measured,
      inInclusiveRange(_rate * (1 - _rateTolerance), _rate * (1 + _rateTolerance)),
      reason: 'the composed link delivered ${measured.round()} B/s against a '
          'configured $_rate. A throttle that only holds its rate alone is '
          'not usable by any scenario that also degrades the link, which is '
          'most of them',
    );
    expect(
      droppedAt,
      greaterThanOrEqualTo(_up - const Duration(milliseconds: 500)),
      reason: 'the link went away after ${droppedAt.inMilliseconds} ms of an '
          '${_up.inMilliseconds} ms up-window, so something other than the '
          'flap cut it — a composition that turned the latency or throttle '
          'path into a teardown would show here and nowhere else',
    );
    expect(
      droppedAt,
      lessThan(_up + const Duration(seconds: 2)),
      reason: 'no dropout arrived within ${(_up + const Duration(seconds: 2)).inSeconds} s, '
          'so the flap was not running while the other two modes were set. '
          'All three have to be observable in one run; two out of three is '
          'the exact result a table of levers cannot distinguish from three',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  group('what cannot coexist', () {
    var cases = 0;

    for (final conflict in exclusiveModePairs) {
      for (final order in <({String first, String second})>[
        (first: conflict.a, second: conflict.b),
        (first: conflict.b, second: conflict.a),
      ]) {
        cases++;
        test('${order.first} then ${order.second}', () async {
          final rig = await _Rig.open();
          await _setMode(rig.proxy, order.first);

          expect(
            () => _setMode(rig.proxy, order.second),
            throwsA(isA<StateError>()
                .having((e) => e.message, 'message', contains(order.first))
                .having((e) => e.message, 'message', contains(order.second))),
            reason: 'setting ${order.second} while ${order.first} is set has '
                'to throw here, at set time, with both names in the message. '
                'Both names because the caller pulled one lever and the '
                'conflict is with a lever pulled somewhere else — a message '
                'naming only the one that threw sends the reader to the wrong '
                'line. At set time because the alternative is a proxy that '
                'accepted the pair and behaved as one of them, and a test '
                'passing against that is passing for a reason nobody chose: '
                '${conflict.why}',
          );
        });
      }
    }

    test('has a case for every declared pair, in both orders', () {
      expect(cases, exclusiveModePairs.length * 2,
          reason: 'the table declares ${exclusiveModePairs.length} exclusive '
              'pairs and this group generated $cases cases. The count is '
              'asserted rather than trusted so a pair added to the table '
              'later cannot arrive without its test — the loop above is '
              'generated from the table, so the only way these disagree is a '
              'pair filtered out on the way in');
    });

    test('names only real modes, once each', () {
      for (final conflict in exclusiveModePairs) {
        expect(conflict.a, isIn(faultModes),
            reason: '${conflict.a} is not a declared mode, so this row '
                'excludes nothing while reading as though it did');
        expect(conflict.b, isIn(faultModes),
            reason: '${conflict.b} is not a declared mode');
        expect(conflict.a, isNot(conflict.b),
            reason: 'a mode cannot exclude itself; this row would make '
                '${conflict.a} unsettable the moment it was set');
        expect(conflict.why, isNotEmpty,
            reason: 'the row carries the sentence the exception prints, and '
                'an empty one leaves the caller with two names and no reason');
      }
      final keys = exclusiveModePairs
          .map((c) => (<String>[c.a, c.b]..sort()).join('×'))
          .toList();
      expect(keys.toSet(), hasLength(keys.length),
          reason: 'a pair declared twice generates two identical cases and '
              'makes the count above agree with a table that is wrong');
    });
  });

  test('clearing one member makes the other settable again', () async {
    final rig = await _Rig.open();
    rig.proxy.blackhole();

    expect(() => rig.proxy.bufferServerToClient = true,
        throwsA(isA<StateError>()),
        reason: 'the pair has to be refused while both would be set, or the '
            'arm below proves nothing');

    rig.proxy.blackhole(enabled: false);
    expect(() => rig.proxy.bufferServerToClient = true, returnsNormally,
        reason: 'blackhole was cleared, so the direction it was discarding is '
            'free for the withhold to take. A rule implemented as a latch — '
            '"this proxy has had blackhole set, so buffering is out for '
            'good" — would fail here, and every scenario that moves from one '
            'fault to another on one proxy would fail with it');
  });

  test('clearing a mode is never refused, whatever else is set', () async {
    final rig = await _Rig.open();
    rig.proxy.latency = _latency;
    rig.proxy.latency = null;
    // Reject excludes every shaping mode, so with it set the shaping levers
    // are closed — but their *off* positions must stay open, or a scenario
    // could reach a state it cannot leave.
    await rig.proxy.reject();

    expect(() => rig.proxy.latency = null, returnsNormally,
        reason: 'clearing latency while rejecting has to be allowed: the '
            'check is about what is being switched on, not about which '
            'levers are named in the table. A proxy that refused an off '
            'switch would be a proxy a scenario can drive into a corner');
    expect(() => rig.proxy.blackhole(enabled: false), returnsNormally,
        reason: 'the same for the off position of a mode that was never on');
    expect(() => rig.proxy.flap(_up, _down, enabled: false), returnsNormally,
        reason: 'and the same for the flap, whose off switch carries the '
            'durations only because the lever is one function');
  });
}

/// Sets [mode] on [proxy] the way a caller would.
///
/// One switch rather than a map, so a mode added to `faultModes` without a
/// line here is a compile-time hole the default case reports by name at run
/// time rather than a silently missing key.
Future<void> _setMode(FaultProxy proxy, String mode) {
  switch (mode) {
    case 'flap':
      proxy.flap(_up, _down);
    case 'latency':
      proxy.latency = _latency;
    case 'throttle':
      proxy.throttleBytesPerSec = _rate;
    case 'blackhole':
      proxy.blackhole();
    case 'cutMidFrame':
      proxy.cutMidFrame(137);
    case 'killOnce':
      proxy.killOnce();
    case 'reject':
      // Returned rather than awaited inside the switch: the conflict check
      // runs before the first await, so the throw reaches an `expect` that is
      // watching for a synchronous one. A `reject` that validated after an
      // await would deliver its refusal as an unhandled future error instead,
      // attributed to whichever test was running when it landed.
      return proxy.reject();
    case 'bufferServerToClient':
      proxy.bufferServerToClient = true;
    default:
      fail('no setter for mode "$mode" in this test, so the pair naming it '
          'cannot be exercised — add one beside the others');
  }
  return Future<void>.value();
}

/// A client that can measure a round trip, then a rate, then a dropout.
final class _Client {
  _Client._(this._socket) {
    _socket.listen(_onData,
        onError: (Object _) => _onEnd(), onDone: _onEnd, cancelOnError: true);
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) {}));
  }

  final Socket _socket;
  final Stopwatch _run = Stopwatch()..start();

  Completer<void>? _probeDone;
  int _probeBytesSeen = 0;

  Completer<double>? _rateDone;
  Stopwatch? _delivery;
  int _delivered = 0;
  Duration _window = Duration.zero;

  final Completer<Duration> _dropped = Completer<Duration>();

  static Future<_Client> connect(int port) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port,
        timeout: _connectBudget);
    addTearDown(socket.destroy);
    return _Client._(socket);
  }

  /// Sends a small payload and returns how long the echo took to come back.
  Future<Duration> probe() async {
    final done = _probeDone = Completer<void>();
    final started = Stopwatch()..start();
    _socket.add(_pattern(_probeBytes));
    await _socket.flush();
    await done.future.timeout(const Duration(seconds: 20));
    started.stop();
    return started.elapsed;
  }

  /// Asks the upstream for a firehose and measures bytes per second over
  /// [window], timed from the first byte delivered.
  ///
  /// From the first byte and not from the request, because everything before
  /// it — the command crossing the link, the first chunk waiting out the
  /// latency, the bucket filling its first slice — is dead time that drags the
  /// measured rate down and lets a throttle running fast pass.
  Future<double> rateOver(Duration window) {
    _window = window;
    final done = _rateDone = Completer<double>();
    _socket.add(<int>[_firehose]);
    unawaited(_socket.flush());
    return done.future.timeout(window + const Duration(seconds: 30));
  }

  /// Waits for the link to go away and returns how far into the run it did.
  Future<Duration> awaitDrop({required Duration budget}) =>
      _dropped.future.timeout(budget);

  void _onData(Uint8List data) {
    final probe = _probeDone;
    if (probe != null && !probe.isCompleted) {
      _probeBytesSeen += data.length;
      if (_probeBytesSeen >= _probeBytes) probe.complete();
      return;
    }
    final rate = _rateDone;
    if (rate == null || rate.isCompleted) return;
    final delivery = _delivery;
    if (delivery == null) {
      // The chunk that starts the clock is not counted. It can only bias the
      // measurement downward, so a throttle delivering too fast cannot hide
      // behind it.
      _delivery = Stopwatch()..start();
      return;
    }
    _delivered += data.length;
    if (delivery.elapsed < _window) return;
    delivery.stop();
    rate.complete(_delivered *
        Duration.microsecondsPerSecond /
        delivery.elapsed.inMicroseconds);
  }

  void _onEnd() {
    if (!_dropped.isCompleted) _dropped.complete(_run.elapsed);
  }
}

/// A proxy in front of an upstream that echoes, and firehoses on command.
final class _Rig {
  _Rig._(this.proxy);

  final FaultProxy proxy;

  static Future<_Rig> open() async {
    final upstream = await _upstreamServer();
    final proxy = FaultProxy(targetPort: upstream.port);
    await proxy.start();
    addTearDown(proxy.shutdown);
    return _Rig._(proxy);
  }
}

/// Echoes what it is sent, until it is sent [_firehose] alone.
Future<ServerSocket> _upstreamServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));
    var firehosing = false;
    socket.listen(
      (data) {
        if (firehosing) return;
        if (data.length == 1 && data.first == _firehose) {
          firehosing = true;
          unawaited(_firehoseInto(socket));
          return;
        }
        try {
          socket.add(data);
        } catch (_) {
          // The proxy cut this connection mid-echo, which several of the
          // modes under test do on purpose.
        }
      },
      onError: (Object _) => socket.destroy(),
      onDone: socket.destroy,
      cancelOnError: true,
    );
  });
  addTearDown(server.close);
  return server;
}

/// Writes blocks as fast as the socket will take them, until it will not.
///
/// Awaiting the flush each time is what makes this a firehose rather than a
/// memory leak: the sender follows the kernel's pace, and the queue that is
/// supposed to be bounded stays in the proxy where the test can see it.
Future<void> _firehoseInto(Socket socket) async {
  final block = _pattern(_blockBytes);
  while (true) {
    try {
      socket.add(block);
      await socket.flush();
    } catch (_) {
      return;
    }
  }
}

Uint8List _pattern(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 7 + 13) & 0xff));
