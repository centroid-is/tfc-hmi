/// Every number the gateway runs on, in one place, with the combinations that
/// cannot work refused at construction.
///
/// Pure data: no I/O, no clock — nothing here reads `DateTime.now` or starts a
/// `Timer`. The tick engine owns the clock and is handed one of these.
///
/// A number that lives at five call sites is a number that drifts, and three
/// of these were measured rather than chosen:
///
/// * **The heartbeat deadline must be shorter than the ping interval.**
///   03-RESEARCH Finding 7 measured a black-holed client — socket open,
///   traffic dropped both directions — being reaped 3.70 s after the blackhole
///   at a 2 s `pingInterval`. That is **1.85×** the interval, and at the
///   design's 20 s it extrapolates to a **~37 second** window in which the
///   gateway still believes a dead panel is alive: still holding its
///   subscriptions, its send buffer, and its upstream monitored items. The
///   project constraint is "half-open connections detected in seconds". So the
///   app-level heartbeat is the reaper and the WS ping is NAT keepalive plus a
///   backstop for the case where the client is alive but its heartbeat logic
///   is broken. Encoding that as a construction rule rather than a convention
///   is what stops the ~37 s hole being configured back in by someone who
///   reads `pingInterval` as the liveness deadline — which is exactly how it
///   reads.
/// * **The stall threshold sits above the noise floor.** Finding 10 measured
///   idle event-loop drift at ±2 ms. A threshold inside that reports a stalled
///   loop on a server doing nothing, and an alarm that is always on is an
///   alarm nobody reads.
/// * **The tick band is 50–100 ms** (SRV-03). Outside it the server still
///   runs and still passes every functional test; it is just a different
///   product. A 500 ms tick is a slideshow of the plant.
library;

/// The knobs a gateway is started with.
///
/// Named arguments with defaults, in the style of
/// `ConflatingSendBuffer` — the caller sets what it cares about and the rest
/// are the researched numbers.
final class ServerConfig {
  /// How often the tick engine drains, polls backpressure, sweeps heartbeats
  /// and samples event-loop lag. Must be within [minTick]–[maxTick].
  final Duration tick;

  /// How long a session may go without an app-level heartbeat before it is
  /// reaped. 6 s is OPC UA's 3× LifetimeCount ratio over a 2 s app heartbeat.
  /// This — not [pingInterval] — is the liveness deadline.
  final Duration heartbeatDeadline;

  /// WebSocket ping period: NAT keepalive, and a backstop for a client whose
  /// heartbeat logic is broken while its socket still works. Never the reaper.
  final Duration pingInterval;

  /// How far the event loop may drift past a scheduled tick before the lag
  /// monitor calls it a stall. An absolute duration (03-CONTEXT amendment),
  /// defaulting to three ticks.
  final Duration stallThreshold;

  /// Hard ceiling on entries pending for one client; exceeding it is an
  /// immediate disconnect (HA: MAX_PENDING_MSG). Handed straight to each
  /// session's `ConflatingSendBuffer`.
  final int maxPending;

  /// Soft ceiling: staying above it for [peakWindowMs] continuously means the
  /// client cannot keep up (HA: PENDING_MSG_PEAK).
  final int? peakThreshold;

  /// How long [peakThreshold] may be exceeded continuously before the session
  /// is disconnected. Matches `ConflatingSendBuffer`'s own default.
  final int peakWindowMs;

  /// Browser origins allowed to open a WebSocket, passed to
  /// `shelf_web_socket`. Empty — the default — rejects every browser `Origin`
  /// with 403 while leaving the panels, which are not browsers and send no
  /// `Origin`, entirely unaffected (03-RESEARCH Finding 1). Phase 6 supplies
  /// the real list when the web bundle ships; until then an empty list is the
  /// cross-site-WebSocket-hijacking defence, not a gap.
  final List<String> allowedOrigins;

  /// Ceiling on keys in a single `subscribe` call. A real panel carries about
  /// 1500 keys, so the default has headroom for the largest screen and still
  /// refuses an unbounded list — one of the two cheapest denial-of-service
  /// shapes against this server (03-05 threat register T-03-13). 03-05's
  /// handler is what enforces it; this is where the number lives.
  final int maxKeysPerSubscribe;

  /// Ceiling on live subscriptions held by one session. The other cheap
  /// denial-of-service shape: one authenticated client opening subscriptions
  /// until the server's memory is gone (T-03-14).
  final int maxSubscriptionsPerSession;

  /// The tick band's lower bound (SRV-03).
  static const Duration minTick = Duration(milliseconds: 50);

  /// The tick band's upper bound (SRV-03).
  static const Duration maxTick = Duration(milliseconds: 100);

  /// The measured idle event-loop drift noise floor is ±2 ms (Finding 10);
  /// this is the smallest stall threshold that means anything above it.
  static const Duration minStallThreshold = Duration(milliseconds: 10);

  ServerConfig({
    this.tick = const Duration(milliseconds: 100),
    this.heartbeatDeadline = const Duration(seconds: 6),
    this.pingInterval = const Duration(seconds: 20),
    this.stallThreshold = const Duration(milliseconds: 300),
    this.maxPending = 4096,
    this.peakThreshold = 1024,
    this.peakWindowMs = 10_000,
    this.allowedOrigins = const [],
    this.maxKeysPerSubscribe = 2000,
    this.maxSubscriptionsPerSession = 32,
  }) {
    if (tick < minTick || tick > maxTick) {
      throw ArgumentError('tick (${_ms(tick)}) is outside the supported band '
          '${_ms(minTick)}–${_ms(maxTick)}: below it the server burns a core '
          'redrawing screens nobody reads that fast, above it the plant '
          'arrives as a slideshow');
    }
    if (heartbeatDeadline >= pingInterval) {
      throw ArgumentError(
          'heartbeatDeadline (${_ms(heartbeatDeadline)}) must be shorter than '
          'pingInterval (${_ms(pingInterval)}): half-open detection through '
          'the ping was measured at 1.85x the interval, so a deadline the '
          'ping could beat leaves a window — ~37 s at a 20 s interval — in '
          'which the gateway serves a dead panel\'s subscriptions to nobody');
    }
    if (stallThreshold < minStallThreshold) {
      throw ArgumentError('stallThreshold (${_ms(stallThreshold)}) is inside '
          'the measured +/-2 ms idle drift; it must be at least '
          '${_ms(minStallThreshold)} or the lag monitor reports a stall on an '
          'idle server');
    }
    _positive('maxPending', maxPending);
    _positive('peakWindowMs', peakWindowMs);
    _positive('maxKeysPerSubscribe', maxKeysPerSubscribe);
    _positive('maxSubscriptionsPerSession', maxSubscriptionsPerSession);
    final peak = peakThreshold;
    if (peak != null && peak <= 0) {
      _positive('peakThreshold', peak);
    }
  }

  static void _positive(String name, int value) {
    if (value <= 0) {
      throw ArgumentError('$name ($value) must be positive: a non-positive '
          'ceiling refuses work the server exists to do');
    }
  }

  static String _ms(Duration d) => '${d.inMilliseconds} ms';
}
