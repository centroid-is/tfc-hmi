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

import 'dart:io' show InternetAddress;

import 'tls/tls_config.dart';

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
  ///
  /// **It bounds *production*, not client backlog** (03-REVIEW WR-11). The
  /// engine drains every tick and `ws.sink.add` never blocks, so the count
  /// this is compared against is what the server produced for one client
  /// during one tick. On `dart:io` WebSockets there is no observable client
  /// backlog at all — it sits in the socket's own unbounded write buffer — so
  /// a genuinely slow client is detected only by [heartbeatDeadline]: it stops
  /// reading, therefore it stops sending heartbeats, and the reaper is what
  /// notices. `tick_engine.dart`'s library doc carries the full statement and
  /// the two options Phase 6 has.
  final int maxPending;

  /// Soft ceiling: staying above it for [peakWindowMs] continuously means the
  /// client cannot keep up (HA: PENDING_MSG_PEAK). Same caveat as
  /// [maxPending]: what stays above it is production, not backlog.
  final int? peakThreshold;

  /// How long [peakThreshold] may be exceeded continuously before the session
  /// is disconnected. Matches `ConflatingSendBuffer`'s own default.
  ///
  /// The window only accumulates because `drain()` no longer clears it
  /// (03-REVIEW WR-02): a drain is the server's own schedule, and only a poll
  /// that reads a count under the threshold counts as recovery.
  final int peakWindowMs;

  /// Ceiling on the size of one **inbound** frame, in bytes, enforced before
  /// `jsonDecode` ever sees it (03-REVIEW WR-04, threat T-03-29).
  ///
  /// There was no frame-size limit anywhere in the path: `shelf_web_socket`
  /// sets only `pingInterval`
  /// (`shelf_web_socket-3.0.0/lib/src/web_socket_handler.dart:93`). The
  /// default is generous against what legitimately arrives — the largest real
  /// request is a `subscribe` carrying [maxKeysPerSubscribe] keys, about
  /// 120 kB at 2000 keys — and small against the amplification shape, where
  /// one garbage frame is echoed back verbatim by json_rpc_2's parse-error
  /// responder and held in the priority lane until the next tick.
  ///
  /// Phase 6 owns the full ingress hardening; this is the number, in place,
  /// with a refusal that names itself.
  final int maxFrameBytes;

  /// Byte budget for one session's priority lane, handed to its
  /// `ConflatingSendBuffer`. See [ConflatingSendBuffer.maxPendingBytes]:
  /// [maxPending] counts entries, and 4096 arbitrarily large entries is a
  /// heap rather than a queue.
  final int maxPendingBytes;

  /// Browser origins allowed to open a WebSocket, passed to
  /// `shelf_web_socket`. Empty — the default — rejects every browser `Origin`
  /// with 403 while leaving the panels, which are not browsers and send no
  /// `Origin`, entirely unaffected (03-RESEARCH Finding 1). Phase 6 supplies
  /// the real list when the web bundle ships; until then an empty list is the
  /// cross-site-WebSocket-hijacking defence, not a gap.
  ///
  /// **Not nullable, and that is a tested property** (`origin_test.dart`).
  /// `shelf_web_socket` skips the check entirely when the list is `null`
  /// (`web_socket_handler.dart:71-77`: `origin != null && _allowedOrigins !=
  /// null && …`), measured in 06-RESEARCH §F.1 — so `null` is not "no
  /// restriction configured yet", it is "cross-site WebSocket hijacking is
  /// permitted". An empty list and a null list read almost identically in a
  /// diff and mean opposite things, and the type is the only thing standing
  /// between them. Anyone tidying `List<String>` into `List<String>?` to
  /// express "unset" is removing the defence; a structural pin fails first.
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

  /// How long the gateway remembers what became of a write, so `writeStatus`
  /// can answer about it after a reconnect.
  ///
  /// It is a window and not a permanent ledger because the log is per-session
  /// memory an authenticated client can grow one write at a time (T-04-06),
  /// and because the question it answers has a shelf life: an operator
  /// reconciling a button press does it within seconds of the link coming
  /// back, not the next morning.
  ///
  /// The number is also the boundary of a *safety* claim rather than of a
  /// convenience. `writeStatus` may answer `not_received` — the one outcome
  /// that tells an operator a re-send is safe — only for a command minted
  /// inside this window, because outside it the gateway cannot tell "never
  /// arrived" from "arrived, and forgotten". 60 s is the reconnect budget
  /// (backoff capped at 30 s, so one full retry cycle plus a resync) with
  /// room to spare.
  final Duration writeOutcomeTtl;

  /// The certificate and key the gateway presents, or `null` for plaintext
  /// `ws://`.
  ///
  /// **`null` is the default and it means plaintext.** Not because cleartext
  /// on a plant LAN is acceptable — it is what SEC-02 exists to end — but
  /// because the alternative is worse in exactly one way that matters: ten
  /// bind/dial fixture sites in this package construct a `ServerConfig` with
  /// no TLS argument and bind loopback on an ephemeral port, and a default
  /// that made them all TLS would rewrite ten fixtures for no requirement.
  /// A rewritten fixture is how a suite quietly stops testing what it used to.
  ///
  /// `null` here is therefore an **explicit choice, visible in a config
  /// diff** — and it is a categorically different thing from a gateway that
  /// was configured with TLS and fell back to plaintext because a path was
  /// misspelled. There is no such fallback: [RelayServer.start] lets the
  /// `FileSystemException` out (`tls_test.dart`, "a misspelled certificate
  /// path fails the start, it does not serve ws").
  final TlsConfig? tls;

  /// The interface the gateway binds.
  ///
  /// Loopback by default (threat T-03-11), and the default is deliberately
  /// **not** the deployment: exposing the gateway on a plant interface is a
  /// decision with a firewall attached to it, not something a default should
  /// do quietly. This field is what lets a deployment be deliberate about it.
  final InternetAddress address;

  /// The TCP port the gateway binds. `0` asks the operating system for an
  /// ephemeral one, which is why two servers can run in one test process
  /// without agreeing on a number.
  final int port;

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
    this.maxFrameBytes = 1024 * 1024,
    this.maxPendingBytes = 8 * 1024 * 1024,
    this.writeOutcomeTtl = const Duration(seconds: 60),
    this.tls,
    InternetAddress? address,
    this.port = 0,
  }) : address = address ?? InternetAddress.loopbackIPv4 {
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
    if (writeOutcomeTtl <= Duration.zero) {
      throw ArgumentError('writeOutcomeTtl (${_ms(writeOutcomeTtl)}) must be '
          'positive: a gateway that remembers no write outcome for any length '
          'of time answers every writeStatus with "never received", which is '
          'the one answer that tells an operator it is safe to actuate the '
          'machine a second time');
    }
    // Deliberately not `_positive` (trap 7): 0 is not a broken ceiling here,
    // it is the ephemeral-port request every fixture in the package depends
    // on. What is refused is a number no `bind` can accept — which otherwise
    // surfaces as a raw `SocketException` from deep inside `start()`.
    if (port < 0 || port > 65535) {
      throw ArgumentError('port ($port) is outside 0-65535: 0 asks the '
          'operating system for an ephemeral port and anything else must be '
          'a real one, or the gateway fails to bind at boot on a plant '
          'machine nobody is standing next to');
    }
    _positive('maxPending', maxPending);
    _positive('peakWindowMs', peakWindowMs);
    _positive('maxKeysPerSubscribe', maxKeysPerSubscribe);
    _positive('maxFrameBytes', maxFrameBytes);
    _positive('maxPendingBytes', maxPendingBytes);
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
