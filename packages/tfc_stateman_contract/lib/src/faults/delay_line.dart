/// One direction of one proxied connection: a bounded queue that gates every
/// write on the previous `flush()`.
///
/// **The measurement this file exists for.** RESEARCH Finding 7 ran a firehose
/// through a proxy into a consumer whose subscription was paused. The obvious
/// implementation — `destination.add(data)` and move on, which is what
/// `tfc_dart/test/proxy.dart:121-143` does in both directions — took the host
/// from 163 MB to **4463 MB** of RSS in four seconds. `dart:io`'s `Socket`
/// sink buffers without limit and exposes no `bufferedAmount`, so nothing in
/// the proxy can even notice it is happening; the same hazard the repo's
/// CLAUDE.md already flags for WebSocket. Gating on `flush()` with a 1 MiB
/// high-water and a 256 KiB low-water measured 164 → 181 MB at four seconds
/// and 188 → 193 MB at twelve, with the internal queue peaking at 1.26 and
/// 1.29 MB.
///
/// **The bound is high-water plus one socket buffer, not high-water.** The
/// peak overshoots [highWaterBytes] by up to ~2.3x because `dart:io` has
/// already handed over a chunk by the time the pause takes effect. An
/// assertion belongs at roughly 4 MiB; one written at exactly 1 MiB is
/// measuring the kernel's buffer-sizing heuristics and will fail on a machine
/// that sizes them differently.
///
/// **Why this is the phase keystone.** Latency, throttle, blackhole and
/// backpressure are all decisions about *when and whether* a queued chunk is
/// forwarded, so they compose on one queue per direction rather than
/// interacting through three. RESEARCH Risk 2: building the modes first makes
/// the bounded-memory and socket-leak criteria fail late, for a reason that
/// looks like a mode bug.
///
/// **Deliberate divergence from the bounded-policy analog.**
/// `tfc_relay_protocol/lib/src/send_buffer.dart:6-7` opens with "pure state
/// machine: no I/O, no clock — callers pass timestamps". This file is the
/// opposite by mandate: it holds real sockets and will hold real timers,
/// because CONTEXT restricts injected clocks to pure state machines, and a
/// backpressure gate driven by a fake clock is exactly the machinery that
/// stops being tested. What is copied from that analog is the *shape* of the
/// policy — ceilings declared as named fields with the reason in the doc, not
/// magic numbers buried in a method. Do not "fix" this file toward its analog.
///
/// The line never destroys the sockets it is given. Lifetime belongs to the
/// pair that opened them (`fault_proxy.dart`), because both directions share
/// them and a line that closed its destination would cut the other direction
/// out from under its partner.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

/// Pending bytes at which the line stops reading from its source.
///
/// 1 MiB, the value RESEARCH Finding 7 measured. Big enough that ordinary
/// bursts never touch it, small enough that a stalled consumer is caught
/// within a few chunks.
const defaultHighWaterBytes = 1024 * 1024;

/// Pending bytes at which the line starts reading again.
///
/// 256 KiB — a quarter of [defaultHighWaterBytes]. The gap is hysteresis: a
/// low-water equal to the high-water pauses and resumes on every chunk, which
/// costs a syscall pair per chunk and makes the pause events useless as a
/// backpressure signal.
const defaultLowWaterBytes = 256 * 1024;

/// A flush-gated, bounded, one-directional byte pipe.
final class DelayLine {
  DelayLine({
    required Socket destination,
    this.highWaterBytes = defaultHighWaterBytes,
    this.lowWaterBytes = defaultLowWaterBytes,
  })  : assert(lowWaterBytes <= highWaterBytes,
            'the low-water mark must not sit above the high-water mark, or '
            'the line pauses and immediately resumes for ever'),
        _destination = destination;

  /// Pending bytes at which this line pauses its source subscription.
  final int highWaterBytes;

  /// Pending bytes at which this line resumes its source subscription.
  final int lowWaterBytes;

  final Socket _destination;
  final Queue<List<int>> _pending = Queue<List<int>>();
  final StreamController<bool> _pauseChanges = StreamController<bool>.broadcast();
  final Completer<void> _finished = Completer<void>();

  StreamSubscription<List<int>>? _source;
  int _pendingBytes = 0;
  int _peakPendingBytes = 0;
  bool _sourceDone = false;
  bool _writing = false;
  bool _paused = false;
  bool _closed = false;

  // ---------------------------------------------------------------------
  // Mode seats.
  //
  // Declared now, read by nothing in this file. Each mode plan fills its own
  // seat without restructuring the line, which is the point: the queue that
  // enforces the memory bound and the queue the modes act on have to be the
  // same object, or the bound proved here is not the bound they inherit.
  //
  // These are not silent no-ops in disguise. The only public way to reach
  // them is a `FaultProxy` lever, and every lever whose mode has not landed
  // throws `UnimplementedError` naming its plan rather than setting one of
  // these and returning.
  // ---------------------------------------------------------------------

  /// Per-chunk delay before a queued chunk is forwarded. Null means no delay.
  ///
  /// The seat `latency` and `jitter` take in plan 02-04. A function rather
  /// than a `Duration` so jitter can be redrawn per chunk.
  Duration Function()? chunkDelay;

  /// Bytes per second this line may forward. Null means unmetered.
  ///
  /// The seat `throttle` takes in plan 02-04.
  int? bytesPerSecond;

  /// Drop queued chunks instead of forwarding them. False means forward.
  ///
  /// The seat `blackhole` takes in plan 02-09 — a true half-open, where the
  /// socket stays up and the bytes stop arriving.
  bool discardInsteadOfForward = false;

  /// Hold queued chunks back until released. False means forward.
  ///
  /// The seat `bufferServerToClient` takes in plan 02-09. Withholding differs
  /// from [discardInsteadOfForward] in that the bytes are still owed, which is
  /// why it must live behind the same high-water mark as everything else.
  bool withholdUntilReleased = false;

  /// Bytes this line has accepted and not yet delivered.
  ///
  /// Includes the chunk currently in flight: it has left the queue but the
  /// destination has not acknowledged it, and a caller asking what the line is
  /// holding is asking about that chunk too.
  int get pendingBytes => _pendingBytes;

  /// The largest [pendingBytes] has ever been.
  ///
  /// The observable the bounded-memory criterion is stated against. Sampling
  /// RSS instead would measure the whole test host — including the payload the
  /// firehose is generating — and could not tell a bounded queue from a lucky
  /// garbage collection.
  int get peakPendingBytes => _peakPendingBytes;

  /// Whether the line is currently refusing to read from its source.
  bool get sourcePaused => _paused;

  /// Every transition of [sourcePaused]: true on pause, false on resume.
  ///
  /// Broadcast, and it emits only on transitions, so a test can await the
  /// backpressure event itself instead of sleeping and hoping. Subscribe
  /// before applying pressure — a broadcast stream has no history.
  Stream<bool> get sourcePausedChanges => _pauseChanges.stream;

  /// Completes when the source has ended and everything it sent has been
  /// written, or when [close] is called.
  Future<void> get done => _finished.future;

  /// Begins carrying [source] to the destination.
  ///
  /// A source error is treated as the end of the stream rather than propagated:
  /// on a socket it means the peer went away mid-connection, which is the
  /// normal end of a proxied pair and, for half this phase's modes, the
  /// deliberate one.
  void start(Stream<List<int>> source) {
    if (_source != null) {
      throw StateError('this delay line is already carrying a source; one '
          'line carries one direction of one connection, so a second source '
          'would interleave two conversations into one stream');
    }
    if (_closed) return;
    _source = source.listen(
      _onData,
      onDone: _onSourceEnded,
      onError: (Object _) => _onSourceEnded(),
      cancelOnError: false,
    );
  }

  /// Stops the line, cancels its source subscription, and drops what is queued.
  ///
  /// Completes rather than hanging even with bytes pending and a destination
  /// that has stopped accepting them. Awaiting the in-flight `flush()` here
  /// would be awaiting a peer that is, in this phase, quite deliberately not
  /// reading — so teardown would inherit the very stall the harness injects.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final source = _source;
    _source = null;
    _pending.clear();
    _pendingBytes = 0;
    _paused = false;
    await source?.cancel();
    if (!_pauseChanges.isClosed) await _pauseChanges.close();
    if (!_finished.isCompleted) _finished.complete();
  }

  void _onData(List<int> chunk) {
    if (_closed || chunk.isEmpty) return;
    _pending.addLast(chunk);
    _pendingBytes += chunk.length;
    if (_pendingBytes > _peakPendingBytes) _peakPendingBytes = _pendingBytes;
    if (!_paused && _pendingBytes >= highWaterBytes) {
      _paused = true;
      _source?.pause();
      _announce(true);
    }
    unawaited(_pump());
  }

  void _onSourceEnded() {
    _sourceDone = true;
    if (!_writing && _pending.isEmpty && !_finished.isCompleted) {
      _finished.complete();
    }
  }

  /// The one place bytes are written to the destination.
  ///
  /// Every `add` is followed by an awaited `flush()` before the next chunk
  /// leaves the queue. That single line is the whole memory bound: without it
  /// the loop hands `dart:io` chunks faster than the kernel takes them and the
  /// queue that is supposed to be bounded lives inside the socket sink, where
  /// nothing can see or limit it.
  Future<void> _pump() async {
    if (_writing) return;
    _writing = true;
    try {
      while (!_closed && _pending.isNotEmpty) {
        final chunk = _pending.first;
        try {
          _destination.add(chunk);
          await _destination.flush();
        } catch (_) {
          // The destination went away — a closed or reset socket throws from
          // `add`, and `flush` completes with the error the peer sent. Either
          // way this direction is over, and it is not this line's business to
          // decide what that means for the connection.
          await close();
          return;
        }
        // Re-read the state the await suspended across: `close()` empties the
        // queue, and a pump that resumed into a cleared queue would take the
        // teardown down with a `Bad state: No element` naming this line rather
        // than the teardown.
        if (_closed) return;
        _pending.removeFirst();
        _pendingBytes -= chunk.length;
        if (_paused && _pendingBytes <= lowWaterBytes) {
          _paused = false;
          _source?.resume();
          _announce(false);
        }
      }
    } finally {
      _writing = false;
    }
    if (_sourceDone && _pending.isEmpty && !_finished.isCompleted) {
      _finished.complete();
    }
  }

  void _announce(bool paused) {
    if (!_pauseChanges.isClosed) _pauseChanges.add(paused);
  }
}
