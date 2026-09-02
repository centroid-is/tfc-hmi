/// The hot path: **one** `Timer.periodic` for the whole server, and the fixed
/// order it does its work in. Internal seam — an embedder starts a server, it
/// does not drive a tick.
///
/// **One timer per server, never one per session** (03-RESEARCH Finding 8).
/// The sweep model that finding measured — a `lastSeenMs` field plus a linear
/// scan, 0.05 µs for 100 sessions — is cheaper than the bookkeeping of the
/// alternative, and that is the smaller half of the argument. The larger half
/// is that a timer capturing a session closure is exactly the ghost 03-11's
/// kill-cycle test hunts: the session is closed, the registry no longer holds
/// it, and a `Timer.periodic` somewhere still owns its buffer, its listeners
/// and its socket. `grep -rn "Timer" lib/src/` is meant to find a *repeating*
/// timer in this file and nowhere else. The package's only other `Timer` is
/// `RelaySession._requestClose`'s zero-duration one-shot, which exists to put
/// a teardown behind the refusal that explains it and cannot outlive the turn
/// it was scheduled in — it holds nothing open and it never fires twice.
///
/// **The order inside one tick is fixed, and every step of it is load-bearing:**
///
///  1. `encoder.beginTick()` — the body cache's whole lifetime policy. A body
///     that outlived a tick would ship the previous tick's values under this
///     tick's timestamp.
///  2. `lag.poll(nowMs)` — *inside this callback*, not on a timer of its own
///     (Finding 10). When the loop is frozen both timers are frozen, and only
///     the callback that was supposed to be sending data knows how long the
///     data was not being sent. A stall the fan-out itself caused is visible
///     here and nowhere else.
///  3. per session: `buffer.poll(nowMs)` **before** `drain()`, act on the
///     verdict, drain, write the priority lane, write the conflated telemetry,
///     write the tick notification.
///  4. the heartbeat sweep, once, over every session ([TickEngine.reap]).
///
/// **Why the poll comes before the drain.** `ConflatingSendBuffer.drain()`
/// empties the buffer by contract — "recovery never has a backlog to flush" —
/// so a poll placed after it reads a pending count of zero on every tick and
/// no backpressure verdict can ever fire. The client that cannot keep up then
/// grows the server's heap in silence, which is the failure
/// `ConflatingSendBuffer` exists to convert into a visible reconnect
/// (Finding 5: `dart:io`'s WebSocket has no `bufferedAmount`, so the buffer's
/// own pending count is the *only* backpressure signal there is).
/// `tick_test.dart` asserts the overflow verdict fires with a full buffer,
/// which is the falsification of the wrong order.
///
/// **The accepted divergence, restated at the drain site** (03-CONTEXT;
/// Finding 5). Design §5 says flush when the previous write completes. On
/// `dart:io` WebSockets there is no such signal — no `bufferedAmount`, no
/// `flush()`, an `add` that returns `void` — so tick-paced draining plus the
/// buffer's own verdicts is what §5's flush-gating maps to on this transport.
/// A reader at this line does not have to go and find the plan.
///
/// **What the backpressure verdicts actually measure** (03-REVIEW WR-11, and
/// this is the honest version of the paragraph above). `drain()` runs
/// unconditionally every tick and `ws.sink.add` never blocks, so the buffer is
/// empty at the start of every tick by construction. What `poll` reads is
/// therefore **how much this server produced for one client during one tick** —
/// not how far behind that client is. A genuinely slow client's backlog
/// accumulates in the `dart:io` socket's own unbounded write buffer, which is
/// exactly the thing this process cannot see. So `maxPending` is a
/// per-client *production* ceiling wearing a backpressure ceiling's name, the
/// soft `peakThreshold` window measures sustained heavy production rather than
/// sustained client backlog, and **a slow client is detected only by the
/// heartbeat deadline** — a panel that stops reading stops sending heartbeats,
/// and the reaper is what notices.
///
/// This is the accepted `dart:io` divergence taken to its conclusion rather
/// than a defect in the implementation of a decision, but SRV-04's "convert
/// silent heap growth into a visible reconnect" is only half met and the docs
/// used to read as though it were fully met. Phase 6 has exactly two real
/// options and should choose deliberately: a periodic `ws.sink.done`-based
/// liveness check, or moving to `package:web_socket` if it ever exposes a
/// completion signal.
library;

import 'dart:async';
import 'dart:convert';

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'error_reporter.dart';
import 'frame_encoder.dart';
import 'lag_monitor.dart';
import 'relay_server.dart' show SessionRegistry;
import 'relay_session.dart';
import 'server_config.dart';

/// The `reason` a stalled gateway announces itself under.
///
/// One of `ResyncParams`' documented vocabulary, named here because this is
/// the only thing that emits it and a client branches on the string.
const gatewayStalled = 'gateway_stalled';

/// Drives every connected session from one timer.
final class TickEngine {
  TickEngine({
    required this.registry,
    required this.config,
    FrameEncoder? encoder,
    LagMonitor? lag,
    int Function()? clock,
    void Function(int nowMs)? sweep,
    int Function()? wallClock,
    this.onSessionError,
  })  : encoder = encoder ?? FrameEncoder(),
        lag = lag ??
            LagMonitor(
              periodMs: config.tick.inMilliseconds,
              thresholdMs: config.stallThreshold.inMilliseconds,
            ),
        _clock = clock,
        _sweep = sweep,
        _wallClock =
            wallClock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    // Anchored once, here, and never re-sampled. Re-reading the wall clock
    // per tick would put an NTP step straight into the timestamps a client
    // derives staleness from — which is the thing the monotonic clock below
    // exists to keep out of the measurement. One anchor means the wire moves
    // exactly as the monotonic clock does, offset to the epoch the client
    // already agreed on in `hello`.
    _epochAnchor = _wallClock() - now();
  }

  /// The sessions to drive. Read fresh every tick, never cached: a session
  /// that connected between two ticks must be served on the second one.
  final SessionRegistry registry;

  final ServerConfig config;

  /// The encode-once seam. One per server, because its cache is keyed by
  /// server-global handles and shared across the sessions that tick together.
  final FrameEncoder encoder;

  /// The drift monitor, polled inside [tickOnce] for the reason in the library
  /// doc.
  final LagMonitor lag;

  final int Function()? _clock;

  /// An override for the tick's final step, replacing [reap].
  ///
  /// A replacement rather than an addition: a test that wants to observe the
  /// sweep seam, or to drive ticks with no reaper at all, must be able to say
  /// so. Absent — which is every production path — the step is [reap], so the
  /// liveness deadline is not something a server has to be configured into.
  final void Function(int nowMs)? _sweep;

  /// Where a session that threw inside the tick is reported.
  ///
  /// Supplied by [RelayServer] from its own `onError`. Without it the throw
  /// went to the ambient zone, which for a package that logs nothing means it
  /// went nowhere: the symptom was "half the plant's panels went still" with
  /// no server-side trace of why.
  final RelayErrorHandler? onSessionError;

  /// The default clock: monotonic, and not the timer's own tick count.
  ///
  /// Finding 10 measures the gap between *arrivals* of the callback, so
  /// counting scheduled ticks would report a perfect loop while the plant view
  /// was frozen. `DateTime.now()` is wrong for the same measurement from the
  /// other side: it moves when NTP steps the machine, and a backwards step
  /// would show as a negative gap and a forwards one as a stall nobody
  /// experienced.
  final Stopwatch _uptime = Stopwatch()..start();

  final int Function() _wallClock;

  /// Wall-clock epoch ms minus the monotonic clock, sampled at construction.
  late final int _epochAnchor;

  /// The epoch-ms timestamp for a monotonic [nowMs] — the **wire** clock.
  ///
  /// **03-REVIEW CR-04.** This engine's clock is a `Stopwatch`, correctly: it
  /// measures callback *arrivals*, so it must not move when NTP steps the
  /// machine. But `UpdateParams.t`, `TickParams.serverTime` and
  /// `SubTick.evaluatedAt` are documented as UTC epoch ms
  /// (`messages.dart:222`, `wire_value.dart:4-6`), and until this existed they
  /// carried uptime instead — so a single `u` frame put its own `t` (uptime,
  /// ~150) beside the `WireValue.t` of the values inside it (epoch ms, ~1.79e12),
  /// two clocks about fifty-five years apart in one object, while
  /// `HelloResult.serverTime` — the field a client derives its offset from —
  /// carried the real epoch. Whichever field a client trusted, its staleness
  /// arithmetic was nonsense, which is exactly the "values are fresh or visibly
  /// stale" property this project exists to guarantee.
  ///
  /// So: monotonic for *measurement* (`lag.poll`, the reaper's trigger,
  /// `silentForMs`), converted here for *emission*. Nothing inside the engine
  /// reads this.
  int wallAt(int nowMs) => _epochAnchor + nowMs;

  Timer? _timer;

  /// How many ticks have run. Read by tests; a server that is ticking is the
  /// one thing no frame can prove on its own.
  int get ticks => _ticks;
  int _ticks = 0;

  /// How late the last tick arrived, in milliseconds past the configured
  /// period, or null before there have been two ticks.
  ///
  /// **The number `PIPE.event_loop_lag_ms` publishes** (HLTH-01). It is
  /// measured here rather than asked of [lag] because [LagMonitor] answers a
  /// *verdict* — a stall or not — and a health gauge that only ever read the
  /// stall threshold or nothing would tell an engineer that the isolate is
  /// fine right up until the moment it is not. Never negative: a tick that
  /// arrived early is not negative lag, it is zero lag and a timer with
  /// jitter.
  ///
  /// Null before the second tick, for the same reason `effective_hz` is: no
  /// measurement is not the same statement as a measurement of nothing.
  int? get lastLagMs => _lastLagMs;
  int? _lastLagMs;
  int? _prevTickMs;

  /// Whether the periodic timer is running.
  bool get running => _timer != null;

  int now() => _clock?.call() ?? _uptime.elapsedMilliseconds;

  /// Starts the one timer. Idempotent — a second call does not add a second
  /// timer, because two timers over one registry would double every client's
  /// frame rate and halve the value of every backpressure verdict.
  void start() {
    _timer ??= Timer.periodic(config.tick, (_) => tickOnce(now()));
  }

  /// Cancels the timer. Idempotent, and the engine is inert afterwards.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  /// One whole cycle, synchronously, at [nowMs].
  ///
  /// The seam every assertion in this phase is written against: a stall, a
  /// backpressure eviction and an idle heartbeat are all arithmetic on an
  /// injected timestamp rather than a sleep on a hosted runner.
  void tickOnce(int nowMs) {
    _ticks++;
    final prev = _prevTickMs;
    if (prev != null) {
      final excess = (nowMs - prev) - config.tick.inMilliseconds;
      _lastLagMs = excess < 0 ? 0 : excess;
    }
    _prevTickMs = nowMs;
    encoder.beginTick();
    final drift = lag.poll(nowMs);
    // `registry.sessions` is a copy, and the copy is the point: a session torn
    // down from another path mid-tick is not selected, and one that is already
    // gone cannot be picked up halfway through its own dismantling
    // (Finding 9's ordered teardown).
    for (final session in registry.sessions) {
      // **One client's dead socket is one client's problem.**
      //
      // Without this catch the tick had no containment anywhere:
      // `_tickSession` reaches `session.emit` → `_Connection.write` →
      // `writeFrame` → `ws.sink.add`, which is a `dart:io` socket write on a
      // connection that may have died between the last `_transportEnded` and
      // this tick. `registry.sessions` preserves connection order, so the
      // *same* session throws first on every subsequent tick — permanent
      // starvation of every session registered after it, plus a reaper
      // (below) that never runs, so nothing ever reaps the dead session
      // causing it. The timer itself survives, which is what made this quiet.
      //
      // The evicted session is closed with [CloseCodes.serverDraining]:
      // within the existing vocabulary that is the code whose meaning is
      // "reconnect, do not alarm", which is the right instruction to a panel
      // the server can no longer write to. It is deliberately not 4004 —
      // nothing here measured a backlog — and not 4003, which would claim the
      // client stopped talking when it may well not have.
      try {
        _tickSession(session, nowMs, drift);
      } catch (error, stack) {
        onSessionError?.call(error, stack, 'tick');
        unawaited(session.close(CloseCodes.serverDraining,
            'this session could not be served: $error'));
      }
    }
    // And the sweep separately, because a sweep that threw would take down the
    // tick from the other end — every session served, none of them reaped.
    try {
      (_sweep ?? reap)(nowMs);
    } catch (error, stack) {
      onSessionError?.call(error, stack, 'reap');
    }
  }

  /// Step 4 of the tick: close every session that has gone silent past
  /// `config.heartbeatDeadline`, with [CloseCodes.heartbeatTimeout].
  ///
  /// **This is the liveness reaper, and the WebSocket ping is not.**
  /// 03-RESEARCH Finding 7 measured half-open detection through `pingInterval`
  /// at **1.85x the interval** — a client black-holed at 308 ms was noticed at
  /// 4008 ms with `pingInterval: 2s`. Extrapolated to the design's 20 s
  /// interval that is a **~37 second** window in which the gateway holds a
  /// dead panel's subscriptions, its buffer and (from Phase 8) its upstream
  /// monitored items, against a project constraint that says half-open
  /// connections are detected in seconds. So the relationship the whole design
  /// rests on is: **the app-level heartbeat deadline is the primary reaper,
  /// and the ping is NAT keepalive plus a backstop for a client that is alive
  /// while its heartbeat logic is broken.** `ServerConfig` refuses to
  /// construct a config that inverts it, and `liveness_test.dart` watches the
  /// race being won rather than trusting that it must be.
  ///
  /// **A sweep, not a timer per session** (Finding 8). Cost is not the
  /// argument — 0.001 µs per reset against 0.11 µs, and 0.05 µs for a full
  /// 100-session scan — leak-safety is: a per-session `Timer` capturing the
  /// session closure is exactly the ghost `teardown_test.dart`'s kill cycle
  /// hunts, still owning a closed session's buffer, listeners and socket long
  /// after the registry has forgotten it exists. There is nothing here to
  /// cancel and therefore nothing to forget to cancel.
  ///
  /// **[tickNowMs] is the trigger and deliberately not the measurement.** Each
  /// session reports its own silence through `RelaySession.silentForMs`,
  /// because this engine's clock is a monotonic uptime `Stopwatch` and a
  /// session's `lastSeenMs` is wall-clock epoch milliseconds; the two are
  /// different by about fifty-five years, and a sweep that subtracted one from
  /// the other would never reap anything while looking entirely implemented.
  /// `registry.sessions` is read fresh rather than reusing the copy [tickOnce]
  /// is iterating: a session evicted by a backpressure verdict earlier in this
  /// same tick is already gone, and reaping it again would be a second
  /// teardown for a session that has none of its resources left.
  void reap(int tickNowMs) {
    final deadlineMs = config.heartbeatDeadline.inMilliseconds;
    for (final session in registry.sessions) {
      final silentMs = session.silentForMs();
      if (silentMs <= deadlineMs) continue;
      // `unawaited` is safe precisely because the registry removal is the
      // synchronous half of `close` (Finding 9, step 2): the session is out
      // before this loop reaches the next one, so nothing can be swept twice
      // and the next tick cannot fan out to it.
      unawaited(session.close(
          CloseCodes.heartbeatTimeout,
          'no heartbeat for $silentMs ms; the deadline is $deadlineMs ms'));
    }
  }

  void _tickSession(RelaySession session, int nowMs, LagVerdict drift) {
    final buffer = session.buffer;

    // Before the drain. See the library doc: after it, this always reads zero.
    //
    // The verdict is handed to the session rather than switched on here: the
    // close code has to reach the client *carried* by the thing that measured
    // the backlog, and one exhaustive switch over `BufferVerdict` in one place
    // is what keeps a future third verdict a compile error instead of a
    // silently dropped eviction (`RelaySession.applyVerdict`). A session that
    // did not survive is abandoned for the rest of this tick — no drain, no
    // stall announcement, no telemetry, no tick notification. It has already
    // left the registry by the time this returns.
    if (!session.applyVerdict(buffer.poll(nowMs))) return;

    // Into the priority lane, and only now: pushed before the poll it would
    // have counted against the client's own backlog, and evicting a panel for
    // the server's stall is exactly backwards. Pushed before the drain so it
    // leaves on *this* tick, ahead of the telemetry whose staleness it
    // explains.
    switch (drift) {
      case LagStalled(:final stalledMs):
        _announceStall(session, stalledMs);
      case LagOk():
        break;
    }

    final frame = buffer.drain();
    for (final message in frame.priority) {
      // Already-encoded frames pass through verbatim — re-encoding a string
      // the peer built would put an encode back on the per-client path. A map
      // is something the server pushed structured (a resync announcement) and
      // is encoded once, here, on a path that runs when something has gone
      // wrong rather than every tick.
      session.emit(message is String ? message : jsonEncode(message));
    }

    _fanOut(session, frame, nowMs);
    _writeTick(session, nowMs);
  }

  /// Tells every live subscription that this tick happened, and where its
  /// sequence stands.
  ///
  /// **The property is F25 / SRV-06:** silence must never be ambiguous. Over a
  /// socket that is still open, "this tag has not moved" and "the gateway
  /// stopped evaluating this tag" look identical, and they call for opposite
  /// responses from whoever is watching the screen. `evaluatedAt` is the
  /// difference, and it moves every tick whether or not `seq` does — `seq`
  /// counts *pushes*, so advancing it here would make the next real push look
  /// like a gap and send a healthy panel into a resync loop.
  ///
  /// Built by concatenation for the same reason [FrameEncoder.updateFrame] is:
  /// this runs for every subscription of every session on every tick, and
  /// nothing in it needs escaping — the numbers are integers this server
  /// produced and the names are the literals escaped once when the
  /// subscription was created. `tick_test.dart` decodes what comes out through
  /// [TickParams], so a hand-built frame that drifted from the DTO fails
  /// there.
  ///
  /// A session watching nothing is sent nothing: an empty `subs` map is bytes
  /// on a link that exists to carry plant data, and such a client has no
  /// subscription whose liveness could be in question.
  void _writeTick(RelaySession session, int nowMs) {
    final subs = session.subscriptions.subscriptions;
    if (subs.isEmpty) return;
    final wallMs = wallAt(nowMs);
    final frame = StringBuffer('{"jsonrpc":"2.0","method":"${Methods.tick}",'
        '"params":{"serverTime":$wallMs,"subs":{');
    var first = true;
    for (final state in subs) {
      if (!first) frame.write(',');
      first = false;
      frame
        ..write(state.literal(encoder.subLiteral))
        ..write(':{"seq":')
        ..write(state.seq)
        ..write(',"evaluatedAt":')
        ..write(wallMs)
        ..write('}');
    }
    frame.write('}}}');
    session.emit(frame.toString());
  }

  /// Pushes one `gateway_stalled` resync per live subscription of [session].
  ///
  /// One per subscription because resync is per subscription: a page that was
  /// not told keeps rendering pre-freeze values as current, which is the
  /// stale-number-on-a-screen failure this project exists to prevent. One
  /// announcement and no debounce because Finding 10 measured a 400 ms freeze
  /// producing exactly one oversized gap and **no** catch-up burst — a
  /// debounce here would be guarding against a storm that was measured not to
  /// happen.
  ///
  /// [stalledMs] is the **absolute** gap, straight from the monitor
  /// (03-CONTEXT amendment): a panel renders it as "the plant view was frozen
  /// for 400 ms", a statement about the plant, where the excess over the tick
  /// period is a statement about a number the client does not have.
  ///
  /// Pushed as a map rather than a string: this path runs when something has
  /// gone wrong, not every tick, so the one `jsonEncode` it costs at the drain
  /// buys the DTO's own field names instead of a hand-spliced envelope on the
  /// rarest path in the file.
  void _announceStall(RelaySession session, int stalledMs) {
    for (final state in session.subscriptions.subscriptions) {
      session.buffer.putPriority({
        'jsonrpc': '2.0',
        'method': Methods.resync,
        'params': ResyncParams(
          sub: state.sub,
          epoch: state.epoch,
          reason: gatewayStalled,
          stalledMs: stalledMs,
        ).toJson(),
      });
    }
  }

  /// Writes this session's conflated telemetry: one `u` frame per subscription
  /// that changed, each spliced around a body the whole tick shares.
  ///
  /// The two halves of Finding 3 meet here. [FrameEncoder.bodyFor] is keyed by
  /// the changed-*handle* set and handles are server-global, so fifty panels
  /// watching one line hand it one signature and pay one encode between them;
  /// the `sub` and `seq` that make the frame this client's own are
  /// concatenated around it, never encoded. Building a map per client and
  /// encoding that is the 7 639 µs strategy, and it is arrived at by accident
  /// rather than by choice.
  /// Puts a rate-limited subscription's pending changes back in the buffer,
  /// to be shipped by the first tick it is due on.
  ///
  /// **Put back, never dropped.** The drain has already emptied the lane, so
  /// a `maxRateHz` implemented by simply skipping the emit would discard the
  /// change — and if that tag never moved again the client would hold the
  /// previous value forever under a healthy link, which is the stale-number-
  /// on-a-screen failure this project exists to prevent. Re-buffering
  /// re-enters the same conflation: several skipped ticks collapse to the one
  /// latest value per handle, which is what a client asking for a slower rate
  /// is asking for.
  void _defer(RelaySession session, String sub, PendingSub pending) {
    final buffer = session.buffer;
    pending.changes.forEach((handle, value) {
      buffer.putValue(sub, handle, value);
    });
    pending.qualities.forEach((handle, quality) {
      buffer.putQuality(sub, handle, quality);
    });
    for (final handle in pending.removed) {
      buffer.remove(sub, handle);
    }
  }

  void _fanOut(RelaySession session, DrainedFrame frame, int nowMs) {
    frame.subs.forEach((sub, pending) {
      final state = session.subscriptions.get(sub);
      // Unsubscribed between the change and this tick. Dropping it is the
      // point of `unsubscribe`: a client that released a page must not be
      // handed one more frame for it, and there is no seq to advance.
      if (state == null) return;
      if (!state.dueAt(nowMs)) {
        _defer(session, sub, pending);
        return;
      }
      state.markPushed(nowMs);
      // A tick this session was actually served on, which is the measurement
      // `PIPE.effective_hz` publishes. Idempotent within a tick, so a panel
      // watching forty pages is not counted forty times.
      session.noteServedTick(nowMs);
      session.emit(encoder.updateFrame(
        sub: state.literal(encoder.subLiteral),
        seq: state.nextSeq(),
        t: wallAt(nowMs),
        generation: state.generation,
        body: encoder.bodyFor(
            pending.changes, pending.qualities, pending.removed),
      ));
    });
  }
}
