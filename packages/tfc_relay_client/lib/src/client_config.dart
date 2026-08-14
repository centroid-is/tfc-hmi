/// Every number the panel side runs on, in one place, with the combinations
/// that cannot work refused at construction.
///
/// Pure data: no I/O, no clock — nothing here reads `DateTime.now` or starts a
/// `Timer`. The supervisor and the watchdog own the clock and are handed one
/// of these. Same shape as the gateway's `ServerConfig`, for the same reason:
/// a number that lives at five call sites is a number that drifts.
///
/// Three of these numbers were measured or ruled on rather than chosen:
///
/// * **The deadline floor is one round trip, rounded up.** 04-RESEARCH
///   Finding 8 measured this transport at a **50.0 ms mean round trip over 50
///   `ping` calls**, quantised to the gateway's 50–100 ms fan-out period — an
///   RPC cannot come back faster than the next fan-out, because that is when
///   the reply is flushed. So the cheapest possible call already costs most of
///   a tenth of a second, and a deadline set anywhere near it fires on a
///   perfectly healthy link. On the control plane that is a reconnect loop; on
///   the write path it is worse, because a fired write deadline does not throw
///   — it resolves `WriteUnknown`, by design, since the write may well have
///   landed. A plant where ordinary writes come back "unknown" is a plant
///   where the operator stops believing the screen, and believing the screen
///   is the whole product. 500 ms is ten measured round trips: comfortably
///   above the floor, comfortably inside human patience.
/// * **The floor is itself a parameter.** [deadlineFloor] is a named argument
///   so a test can lower it deliberately. `truncated_write_test`'s polarity
///   flip — the case that proves a truncated write resolves unknown instead of
///   hanging — is only meaningful if the write deadline can fire inside the
///   case's own budget, which is a few hundred milliseconds. A hard floor
///   would make the flip untestable, and an untestable safety property is a
///   hope. Lowering it is explicit at the call site and greppable, which is
///   the point: nobody lowers it in production by accident.
/// * **Freshness is configured, never derived.** The 04-CONTEXT ruling: the
///   freshness deadline is a configured duration defaulting to **3 s** (design
///   band 2–5 s), and it is never computed from the transport cadence.
///   Finding 5 is why. The fan-out runs at 50–100 ms, so "death = three
///   periods" evaluates to 150–300 ms — a fine number on loopback and an
///   unusable one on a plant WAN, where a single garbage collection pause or
///   one Wi-Fi retransmit would grey every value on the screen at once. This
///   class therefore exposes no field the cadence could arrive through, and
///   `client_config_test.dart` reads this file as text to keep it that way.
///
/// The backoff ceiling is a refusal rather than a default because STACK
/// rejected `web_socket_client` over an infinite backoff loop. A panel that
/// has backed off to ten minutes is indistinguishable, to the operator
/// standing in front of it, from a panel that is dead — so they power-cycle
/// it, and the recovery path that was supposed to be automatic never runs.
library;

/// The knobs a `RemoteStateMan` is constructed with.
///
/// Named arguments with defaults, in `ServerConfig`'s style — the caller sets
/// what it cares about and the rest are the researched numbers.
final class ClientConfig {
  /// Deadline for control-plane calls: `hello`, `subscribe`, `unsubscribe`,
  /// `read`, `readMany`. `json_rpc_2` has no per-request timeout of its own
  /// (04-RESEARCH Finding 1) and a peer that stops answering without closing
  /// leaves the future pending forever, so this is the only thing standing
  /// between a malformed peer and a panel stuck on a spinner.
  final Duration controlDeadline;

  /// Deadline for `write`. Longer than [controlDeadline] because a write
  /// travels further — through the gateway into the PLC and back — and because
  /// expiry here is not an error but a three-state outcome: the call resolves
  /// `WriteUnknown`, never throws, and is never auto-retried. `writeStatus` on
  /// reconnect is how the unknown is resolved.
  final Duration writeDeadline;

  /// How long a value may go without a refresh before it is shown as stale.
  ///
  /// A configured number, deliberately independent of the gateway's fan-out
  /// cadence — see the library doc. The watchdog is a single deadline reset by
  /// *any* inbound frame, not one timer per subscription, because `readyState`
  /// lies after an OS sleep (STACK) and because N timers on a 1500-key page is
  /// N timers to cancel correctly on every reconnect.
  final Duration freshnessDeadline;

  /// First reconnect window. Attempt *n* draws uniformly from
  /// `[0, min(backoffCap, backoffBase * 2^n)]` — full jitter, so the first
  /// retry after a one-second blip is usually well under this.
  final Duration backoffBase;

  /// Ceiling on the reconnect window, at most [maxBackoffCap].
  final Duration backoffCap;

  /// How far the gateway's clock may sit from this panel's before the client
  /// says so.
  ///
  /// Exceeding it **warns and keeps using the gateway's clock** for staleness
  /// (04-RESEARCH Finding 5b: `clockOffset = localNowMs - hello.serverTime`,
  /// captured at each hello; measured at 52 ms same-machine). It never greys
  /// the plant — a panel whose own clock drifted must still show values, and a
  /// disagreement about wall time is not a disagreement about the process.
  final Duration implausibleClockThreshold;

  /// How many gateway fan-out periods a subscription may go without being
  /// re-evaluated before it is reported stale.
  ///
  /// A *ratio*, not a duration, and that is the point (04-REVIEW WR-08). The
  /// per-subscription verdict answers "has the plant stopped evaluating this
  /// page", which is a question about the gateway's cadence — advertised at
  /// `hello` as `capabilities.tickMs` — and not about the socket. Reusing
  /// [freshnessDeadline] for it marked every slowly-evaluated page permanently
  /// stale, which is the grey that cries wolf.
  ///
  /// 30 against the measured 50 ms fan-out is 1.5 s, and against a 1 s
  /// production tick is 30 s: the limit follows the plant rather than the
  /// panel. `FreshnessWatchdog` floors it at [freshnessDeadline], so it can
  /// never fire before "the link is gone" and send somebody to look at a
  /// sensor when the problem is a switch.
  final double subscriptionStalenessMultiple;

  /// The smallest deadline any of the three above may be set to.
  ///
  /// A parameter rather than a constant on purpose; see the library doc.
  final Duration deadlineFloor;

  /// Ten measured round trips. The default [deadlineFloor].
  static const Duration defaultDeadlineFloor = Duration(milliseconds: 500);

  /// The hard ceiling on [backoffCap]: past half a minute the operator has
  /// already decided the panel is dead.
  static const Duration maxBackoffCap = Duration(seconds: 30);

  ClientConfig({
    this.controlDeadline = const Duration(seconds: 1),
    this.writeDeadline = const Duration(seconds: 2),
    this.freshnessDeadline = const Duration(seconds: 3),
    this.backoffBase = const Duration(milliseconds: 250),
    this.backoffCap = maxBackoffCap,
    this.implausibleClockThreshold = const Duration(minutes: 5),
    this.deadlineFloor = defaultDeadlineFloor,
    this.subscriptionStalenessMultiple = 30,
  }) {
    if (!(subscriptionStalenessMultiple > 1)) {
      throw ArgumentError('subscriptionStalenessMultiple '
          '($subscriptionStalenessMultiple) must be greater than 1: at one '
          'period or less every subscription is stale again immediately after '
          'the refresh that cleared it, and a page that is always grey is a '
          'page nobody reads');
    }
    _positive('deadlineFloor', deadlineFloor);
    _atLeastFloor('controlDeadline', controlDeadline);
    _atLeastFloor('writeDeadline', writeDeadline);
    _atLeastFloor('freshnessDeadline', freshnessDeadline);

    _positive('backoffBase', backoffBase);
    _positive('backoffCap', backoffCap);
    _positive('implausibleClockThreshold', implausibleClockThreshold);

    if (backoffCap > maxBackoffCap) {
      throw ArgumentError('backoffCap (${_ms(backoffCap)}) is above the hard '
          'ceiling ${_ms(maxBackoffCap)}: a panel that waits longer than that '
          'to retry looks dead to the operator standing in front of it, who '
          'power-cycles it instead of letting the reconnect run');
    }
    if (backoffBase > backoffCap) {
      throw ArgumentError('backoffBase (${_ms(backoffBase)}) is above '
          'backoffCap (${_ms(backoffCap)}): the very first retry would already '
          'be clamped, which makes the schedule a constant, and a constant '
          'brings every panel in the factory back in the same instant');
    }
  }

  void _atLeastFloor(String name, Duration value) {
    if (value < deadlineFloor) {
      throw ArgumentError('$name (${_ms(value)}) is below the deadline floor '
          '(${_ms(deadlineFloor)}): a measured round trip on this transport is '
          '50 ms and is quantised to the gateway fan-out, so a deadline that '
          'short expires on a healthy link — turning every write into a false '
          'unknown and every subscribe into a reconnect. Lower deadlineFloor '
          'explicitly if this is a test that needs the deadline to fire.');
    }
  }

  static void _positive(String name, Duration value) {
    if (value <= Duration.zero) {
      throw ArgumentError('$name (${_ms(value)}) must be positive: a '
          'non-positive interval either disables the check it belongs to or '
          'turns a retry into a spin');
    }
  }

  static String _ms(Duration d) => '${d.inMilliseconds} ms';
}
