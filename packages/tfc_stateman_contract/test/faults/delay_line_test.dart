/// Proof that a stalled consumer cannot make the proxy eat the test host.
///
/// RESEARCH Finding 7 measured the naive proxy — `to.add(data)` and move on —
/// going from 163 MB to **4463 MB** of RSS in four seconds against a consumer
/// whose subscription was paused, because `dart:io`'s `Socket` sink buffers
/// without limit and offers no `bufferedAmount` to notice with. The gated
/// version measured 164 → 181 MB at 4 s and 188 → 193 MB at 12 s, with an
/// internal queue peaking at 1.26 and 1.29 MB against a 1 MiB high-water.
///
/// The two numbers that matter are the pair, not either one alone. A queue
/// that is merely *slower* also looks small at four seconds; what says
/// "bounded" is that twelve seconds does not cost three times as much. So the
/// long arm here asserts the 12 s peak against the 4 s peak, and both assert
/// the absolute bound — which is high-water plus one socket buffer, hence
/// [_bound] at 4 MiB rather than at exactly 1 MiB.
///
/// What is being defended is the ability to observe a fault at all. Every mode
/// in this phase — latency, throttle, blackhole, flap — parks bytes in this
/// queue while it does its work. An unbounded line means the test host dies of
/// RSS before the fault it was injecting is observed, and the CI failure names
/// the runner rather than the mode.
@Tags(['faults'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tfc_stateman_contract/faults.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart';

/// The absolute ceiling both stalled-consumer arms assert.
///
/// Four times the 1 MiB high-water. RESEARCH measured the real peak at
/// 1.26–1.29 MB: `dart:io` has already handed the line a chunk by the time the
/// pause takes effect, so the bound is "high-water plus one socket buffer" and
/// an assertion written at exactly 1 MiB would be measuring the kernel's
/// buffer-sizing heuristics rather than the queue's policy.
const _bound = 4 * 1024 * 1024;

/// How long the short stalled-consumer window runs.
const _shortRun = Duration(seconds: 4);

/// How long the long stalled-consumer window runs.
///
/// Three times [_shortRun], which is what makes the comparison meaningful: an
/// unbounded queue grows with time, so tripling the window would triple the
/// peak.
const _longRun = Duration(seconds: 12);

/// The most the twelve-second sample may exceed the four-second one.
///
/// Both samples come from **one** rig, which is the only way this comparison
/// means anything: peak pending bytes vary by a megabyte between rigs
/// depending on how much `dart:io` had already buffered when the pause landed
/// and how the kernel sized that connection's buffers, so two rigs compared
/// against each other measure that variance and fail on a busy machine.
/// Sampled twice in one run, the number is monotonic and the ratio is a
/// statement about growth and nothing else. 1.5x is generous for a queue that
/// fills within the first second and far below the 3x an unbounded one shows
/// over 3x the window.
const _growthAllowance = 1.5;

/// Chunk size the firehose writes.
const _chunkBytes = 64 * 1024;

/// The least the firehose must have pushed for a bounded-memory arm to mean
/// anything.
///
/// Without it, a rig that failed to connect reports a peak of zero and the
/// bound passes vacuously — the same shape of lie RESEARCH Pitfall 2 found in
/// the first leak counter.
const _minimumOffered = 1024 * 1024;

const _connectBudget = Duration(seconds: 5);
const _arrivalBudget = Duration(seconds: 20);

void main() {
  test('carries bytes through intact and in order', () async {
    final rig = await _Rig.open(stalled: false);
    final payload = _pattern(512 * 1024);

    rig.firehose.add(payload);
    await rig.firehose.flush();

    await within(
      rig.receivedAtLeast(payload.length),
      'every byte written into the line came out of the far side',
      budget: _arrivalBudget,
    );

    final received = rig.takeReceived();
    expect(received.length, payload.length,
        reason: 'a line that drops or duplicates bytes turns every later mode '
            'test into a coin flip: cutMidFrame(137) cannot be judged against '
            'a transport that loses bytes on its own');
    final firstDifference = _firstDifference(received, payload);
    expect(firstDifference, -1,
        reason: 'byte $firstDifference differs, so the line reordered or '
            'corrupted the stream — a proxy that does that makes every fault '
            'mode built on it unfalsifiable');
  });

  test('holds its queue under the bound against a consumer that never reads',
      () async {
    final run = await _measureStalledRun(_shortRun, sampleAt: _shortRun);

    expect(run.bytesOffered, greaterThanOrEqualTo(_minimumOffered),
        reason: 'the firehose only managed ${run.bytesOffered} bytes, so the '
            'rig never pressured the line and its peak of ${run.peakAtEnd} '
            'proves nothing — a bounded-memory arm that never applied '
            'pressure is the vacuous pass this phase keeps finding');
    expect(run.peakAtEnd, lessThan(_bound),
        reason: 'the line held ${run.peakAtEnd} bytes against a bound of '
            '$_bound; ungated, RESEARCH measured the same four seconds cost '
            '4463 MB of RSS, and a test host that dies of memory never reports '
            'on the fault it was injecting');
  });

  test(
      'is bounded rather than merely slower: three times the window is not '
      'three times the queue', () async {
    // One rig, sampled twice. Two rigs compared against each other measure
    // per-connection buffer variance, which is about a megabyte and has
    // nothing to do with whether the queue grows.
    final run = await _measureStalledRun(_longRun, sampleAt: _shortRun);

    expect(run.bytesOffered, greaterThanOrEqualTo(_minimumOffered),
        reason: 'the long window pushed only ${run.bytesOffered} bytes, so '
            'the comparison below is between two readings of an idle rig');
    expect(run.peakAtSample, lessThan(_bound),
        reason: 'the line held ${run.peakAtSample} bytes at '
            '${_shortRun.inSeconds} s against a bound of $_bound');
    expect(run.peakAtEnd, lessThan(_bound),
        reason: 'the line held ${run.peakAtEnd} bytes at '
            '${_longRun.inSeconds} s against a bound of $_bound');
    expect(
      run.peakAtEnd,
      lessThanOrEqualTo((run.peakAtSample * _growthAllowance).ceil()),
      reason: 'the same line peaked at ${run.peakAtSample} bytes after '
          '${_shortRun.inSeconds} s and ${run.peakAtEnd} after '
          '${_longRun.inSeconds} s. The queue must be *bounded*, not merely '
          'slower to fill: a line that grows with time passes a four-second '
          'test and takes the soak run down at minute forty, where the '
          'failure looks like a memory leak in whatever the harness was '
          'testing',
    );
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('pauses its source at the high-water mark and resumes below the low',
      () async {
    final rig = await _Rig.open(stalled: true);
    // Both subscribed before any pressure is applied, so neither can miss the
    // transition it is waiting for.
    final paused =
        rig.line.sourcePausedChanges.firstWhere((p) => p, orElse: () => false);
    final resumed =
        rig.line.sourcePausedChanges.firstWhere((p) => !p, orElse: () => true);

    var stopped = false;
    final firehose = _firehoseUntil(rig.firehose, () => stopped);

    // `orElse` reports the stream closing without the transition, so the
    // assertion below reads the same either way instead of arriving as a
    // StateError from inside `firstWhere`.
    final sawPause = await within(paused, 'the line paused its source',
        budget: _arrivalBudget);
    expect(sawPause, isTrue,
        reason: 'the line never stopped reading from its source, so the only '
            'thing standing between a stalled consumer and the test host\'s '
            'heap is how fast the sender happens to be');
    expect(rig.line.sourcePaused, isTrue,
        reason: 'the pause event and the flag must agree, or callers that '
            'poll the flag see a different line from callers that watch the '
            'stream');
    expect(rig.line.pendingBytes, greaterThan(0),
        reason: 'a line that pauses with nothing pending is pausing on '
            'something other than its own queue depth');

    stopped = true;
    rig.consumer.resume();

    final sawResume = await within(resumed, 'the line resumed its source',
        budget: _arrivalBudget);
    expect(sawResume, isFalse,
        reason: 'the line stayed paused after its consumer started reading '
            'again, so one burst of backpressure wedges the connection for '
            'good — a fault mode that never ends is not a fault mode');
    expect(rig.line.sourcePaused, isFalse,
        reason: 'the resume event and the flag must agree, or callers that '
            'poll the flag see a different line from callers that watch the '
            'stream');

    await firehose;
  });

  test('closes without hanging while bytes are still pending, and lets go of '
      'its source', () async {
    final rig = await _Rig.open(stalled: true);
    var stopped = false;
    final firehose = _firehoseUntil(rig.firehose, () => stopped);

    await within(
      rig.line.sourcePausedChanges.firstWhere((p) => p, orElse: () => false),
      'the line filled its queue against the stalled consumer',
      budget: _arrivalBudget,
    );
    stopped = true;

    await within(rig.line.close(), 'close() returned while bytes were pending',
        budget: const Duration(seconds: 5));
    await within(rig.line.done, 'the line reported itself finished',
        budget: const Duration(seconds: 5));

    expect(rig.line.pendingBytes, 0,
        reason: 'a closed line still holding bytes is holding them for ever: '
            'nothing will drain it, and every teardown in the suite leaks that '
            'much heap per connection');

    await firehose;
  });
}

/// One stalled-consumer window, read at two points on the same rig.
typedef _StalledRun = ({int peakAtSample, int peakAtEnd, int bytesOffered});

/// Runs a firehose into a line whose consumer never reads, for [window],
/// recording the peak at [sampleAt] on the way past.
Future<_StalledRun> _measureStalledRun(Duration window,
    {required Duration sampleAt}) async {
  final rig = await _Rig.open(stalled: true);
  var stopped = false;
  final firehose = _firehoseUntil(rig.firehose, () => stopped);

  // A measurement window, not synchronisation. The property under test is
  // "the queue does not grow while time passes", so time passing *is* the
  // experiment — there is no event to await, because the assertion is about
  // the absence of one. Written in the unparameterised form so the phase-wide
  // grep for sleeps finds it.
  await Future.delayed(sampleAt);
  final peakAtSample = rig.line.peakPendingBytes;
  await Future.delayed(window - sampleAt);
  final peakAtEnd = rig.line.peakPendingBytes;

  stopped = true;
  rig.firehose.destroy();
  final offered = await firehose;
  await rig.line.close();
  // Printed, not merely asserted: RESEARCH's table is a pair of numbers per
  // window, and a future regression is far easier to read as "the peak tripled
  // when the window tripled" than as one failed comparison.
  print('stalled consumer: peak pending $peakAtSample bytes at '
      '${sampleAt.inSeconds} s, $peakAtEnd at ${window.inSeconds} s, '
      '$offered bytes offered');
  return (
    peakAtSample: peakAtSample,
    peakAtEnd: peakAtEnd,
    bytesOffered: offered
  );
}

/// Writes as fast as the far side will take it, gating on `flush()`.
///
/// The gate is what keeps the *rig* honest: an ungated firehose buffers inside
/// its own `dart:io` sink and reproduces Finding 7's 4.5 GB in the test rather
/// than in the code under test.
Future<int> _firehoseUntil(Socket socket, bool Function() stopped) async {
  final chunk = Uint8List(_chunkBytes);
  var offered = 0;
  try {
    while (!stopped()) {
      socket.add(chunk);
      await socket.flush();
      offered += chunk.length;
    }
  } catch (_) {
    // The rig destroyed the socket to end the window; the write in flight
    // failing is how this loop is meant to stop.
  }
  return offered;
}

/// A line under test, with a firehose on one end and a consumer on the other.
///
/// Both ends are real loopback sockets. CONTEXT's test-realism policy restricts
/// injected clocks and fake transports to pure state machines, and this is the
/// opposite of one: what is being measured is how `dart:io` behaves when the
/// kernel stops accepting writes.
final class _Rig {
  _Rig._(this.line, this.firehose, this.consumer, this._received);

  final DelayLine line;

  /// Writes into the socket the line reads from.
  final Socket firehose;

  /// The far side. Paused for the whole test when the rig is stalled.
  final StreamSubscription<Uint8List> consumer;

  final BytesBuilder _received;
  int _target = -1;
  Completer<void>? _reached;

  int get receivedBytes => _received.length;

  Uint8List takeReceived() => _received.takeBytes();

  /// Completes once at least [bytes] have arrived at the consumer.
  Future<void> receivedAtLeast(int bytes) {
    if (_received.length >= bytes) return Future<void>.value();
    _target = bytes;
    return (_reached ??= Completer<void>()).future;
  }

  void _onReceived(Uint8List data) {
    _received.add(data);
    final reached = _reached;
    if (reached != null && !reached.isCompleted && _received.length >= _target) {
      reached.complete();
    }
  }

  /// Builds the rig and registers every teardown at acquisition.
  static Future<_Rig> open({required bool stalled}) async {
    final consumerListener =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(consumerListener.close);
    final consumerAccepted = Completer<Socket>();
    final consumerAccepts = consumerListener.listen(consumerAccepted.complete);
    addTearDown(consumerAccepts.cancel);

    final destination = await within(
      Socket.connect(consumerListener.address, consumerListener.port),
      'the line reached its destination on loopback',
      budget: _connectBudget,
    );
    addTearDown(destination.destroy);
    _ignoreDone(destination);

    final consumerSocket = await within(consumerAccepted.future,
        'the consumer accepted the line\'s destination socket',
        budget: _connectBudget);
    addTearDown(consumerSocket.destroy);
    _ignoreDone(consumerSocket);

    final sourceListener =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(sourceListener.close);
    final sourceAccepted = Completer<Socket>();
    final sourceAccepts = sourceListener.listen(sourceAccepted.complete);
    addTearDown(sourceAccepts.cancel);

    final firehose = await within(
      Socket.connect(sourceListener.address, sourceListener.port),
      'the firehose reached the line\'s source listener',
      budget: _connectBudget,
    );
    addTearDown(firehose.destroy);
    _ignoreDone(firehose);

    final source = await within(
        sourceAccepted.future, 'the line\'s source socket was accepted',
        budget: _connectBudget);
    addTearDown(source.destroy);
    _ignoreDone(source);

    final rig = _Rig._(
      DelayLine(destination: destination),
      firehose,
      consumerSocket.listen(null),
      BytesBuilder(copy: false),
    );
    rig.consumer.onData(rig._onReceived);
    if (stalled) rig.consumer.pause();
    addTearDown(rig.consumer.cancel);
    addTearDown(rig.line.close);

    rig.line.start(source);
    return rig;
  }
}

/// Swallows a socket's `done` failure.
///
/// Every socket in this file is destroyed at teardown, and a destroyed socket
/// completes `done` with an error nobody is waiting for — which `package:test`
/// reports as an unhandled async error against whichever test happens to be
/// running when it lands.
void _ignoreDone(Socket socket) {
  unawaited(socket.done.catchError((Object _) => socket));
}

/// A deterministic pattern whose shifts are visible.
///
/// A run of zeroes would let a line that dropped a chunk still compare equal.
Uint8List _pattern(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = (i * 31 + i ~/ 251) & 0xff;
  }
  return bytes;
}

/// The index of the first differing byte, or -1 when the prefixes match.
///
/// Compared by index rather than by `expect(a, b)` so a failure names one
/// offset instead of printing half a megabyte of hex into the CI log.
int _firstDifference(List<int> a, List<int> b) {
  final shared = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shared; i++) {
    if (a[i] != b[i]) return i;
  }
  return a.length == b.length ? -1 : shared;
}
