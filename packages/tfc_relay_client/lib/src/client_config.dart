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

  /// How often a live hold-to-run feeds the plant's deadman counter.
  ///
  /// The operator is holding a button and a machine is jogging. What keeps it
  /// jogging is not a message saying "still held" — it is a counter on the tag
  /// that keeps going up, which the PLC watches and gives up on after
  /// [holdDeadman]. The panel sends one increment every [holdPulsePeriod]; the
  /// safety property is the increments STOPPING, so a panel that crashes, is
  /// backgrounded or loses its link stops the machine by doing nothing at all.
  ///
  /// **Why this is not spelled `holdTickPeriod`.** `client_config_test.dart`'s
  /// last case (`:202-222`, "the freshness deadline cannot learn a transport
  /// period") reads *this file* as text, strips the `///` lines, lowercases
  /// the remainder and asserts it does not contain the substring `tick`. That
  /// sweep is not fussiness. The gateway advertises its fan-out cadence at
  /// `hello` as `capabilities.tickMs`, measured at 50-100 ms; the moment this
  /// class can name that cadence, somebody derives the freshness deadline from
  /// it as "three periods", ships a 150 ms staleness horizon, and one garbage
  /// collection pause greys every value in the plant at once. The sweep exists
  /// so that the derivation cannot be written here at all, and the price of
  /// keeping it is this paragraph plus a field name without the substring.
  /// The alternatives were considered and rejected: putting the cadence on
  /// `HoldToRunController` or in a separate `HoldToRunConfig` would make the
  /// hold the one client timing number with no named injectable home in this
  /// class (04-01's must-have truths), which is a worse rule to break than a
  /// naming preference (D-P5-K).
  ///
  /// **Validated with `_positive`, never `_atLeastFloor`.** 100 ms is a fifth
  /// of the default [deadlineFloor], and routing a cadence through the
  /// deadline validator would make `ClientConfig()` with no arguments throw at
  /// construction. It is not a deadline: nothing waits on one pulse, and a
  /// dropped pulse costs nothing the next one does not fix.
  final Duration holdPulsePeriod;

  /// How many missed pulses the PLC tolerates before it drops the output.
  ///
  /// A *ratio*, for the same reason [subscriptionStalenessMultiple] is one:
  /// the quantity follows the cadence rather than being an independent
  /// millisecond count that somebody has to remember to change twice.
  /// [holdDeadman] is the product, and 100 ms x 10 is the one second the plant
  /// was configured for (05-CONTEXT decision 3 — the user chose tolerance for
  /// a Wi-Fi hiccup mid-jog over a near-instant stop, and accepted up to a
  /// second of coasting after a release on a dead link).
  ///
  /// **At least 3.** Below that, two dropped frames stop the machine — which
  /// is the tolerance decision inverted while wearing the clothes of a safety
  /// tightening. An operator whose jog cuts out every time the panel's Wi-Fi
  /// retransmits holds the button harder and then calls somebody.
  ///
  /// **Nothing in Dart enforces the PLC's timer.** This number is the client's
  /// *statement* of what the plant's `FB_HoldToRun` is configured for; the TON
  /// preset on the other side is a number in a PLC program that no Dart code
  /// can read or set. The two are kept in step by the design document
  /// (`relay-comm-design.md` §4.6a) and by nothing else, which is why the
  /// derived [holdDeadman] exists at all: so there is exactly one place to
  /// compare against when somebody changes one of them.
  final int holdMissedPulsesBeforeStop;

  /// How long the machine keeps moving after the pulses stop.
  ///
  /// **Derived, never stored.** Two independently settable numbers that must
  /// agree is precisely how they stop agreeing — and here the disagreement is
  /// invisible until an operator lets go of a button and something keeps
  /// moving for longer than anybody expected.
  Duration get holdDeadman => holdPulsePeriod * holdMissedPulsesBeforeStop;

  /// The smallest deadline any of the three above may be set to.
  ///
  /// A parameter rather than a constant on purpose; see the library doc.
  final Duration deadlineFloor;

  /// The credential this station presents on the first frame, or null when the
  /// gateway it dials runs no token file.
  ///
  /// **What it is.** A per-station secret the integrator mounts alongside the
  /// panel's other configuration — one opaque string that tells the gateway
  /// *which panel* is speaking and, through the gateway's own map, whether
  /// that panel may write or only watch.
  ///
  /// **What it is not: a person's identity.** Nobody logs in to a panel. The
  /// screen by the filleting line is used by whoever is standing at it, all
  /// shift, with wet gloves on — a credential that identified people would be
  /// a credential shared by everyone on the shift within a day, which is worse
  /// than no claim at all because it would look like an audit trail. This
  /// string answers "which station", and the plant's own supervision answers
  /// who was at it.
  ///
  /// **Null is the shipped default and stays supported.** Every fixture in
  /// this workspace dials a gateway running the permissive validator, and a
  /// panel with no token still sends a well-formed hello — the field is simply
  /// absent from the frame. So switching a gateway to a real token file is a
  /// deployment change, not a protocol change.
  ///
  /// **Not validated here.** A length or shape rule in this constructor would
  /// be a second opinion about a secret whose only real judge is the gateway,
  /// and a panel that refuses to construct because its mounted credential
  /// looks wrong is a dark screen at shift start instead of a refusal an
  /// operator can read. The gateway decides; this class carries.
  final String? token;

  /// Ten measured round trips. The default [deadlineFloor].
  static const Duration defaultDeadlineFloor = Duration(milliseconds: 500);

  /// The hard ceiling on [backoffCap]: past half a minute the operator has
  /// already decided the panel is dead.
  static const Duration maxBackoffCap = Duration(seconds: 30);

  /// The floor under [holdMissedPulsesBeforeStop]. See that field for why.
  static const int _minMissedPulses = 3;

  ClientConfig({
    this.controlDeadline = const Duration(seconds: 1),
    this.writeDeadline = const Duration(seconds: 2),
    this.freshnessDeadline = const Duration(seconds: 3),
    this.backoffBase = const Duration(milliseconds: 250),
    this.backoffCap = maxBackoffCap,
    this.implausibleClockThreshold = const Duration(minutes: 5),
    this.deadlineFloor = defaultDeadlineFloor,
    this.subscriptionStalenessMultiple = 30,
    this.holdPulsePeriod = const Duration(milliseconds: 100),
    this.holdMissedPulsesBeforeStop = 10,
    this.token,
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

    // `_positive`, and the choice is load-bearing: see [holdPulsePeriod]. The
    // deadline floor defaults to 500 ms and the cadence is 100 ms, so
    // `_atLeastFloor` here would throw on the default construction of this
    // class and no panel in the plant would start.
    _positive('holdPulsePeriod', holdPulsePeriod);
    if (holdMissedPulsesBeforeStop < _minMissedPulses) {
      throw ArgumentError('holdMissedPulsesBeforeStop '
          '($holdMissedPulsesBeforeStop) must be at least $_minMissedPulses: '
          'below that, two dropped frames stop the machine mid-jog, which '
          'inverts the tolerance the plant decided on — up to a second of '
          'coasting is accepted precisely so that one Wi-Fi retransmit does '
          'not drop the output under an operator who never let go');
    }

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
