/// Whether the panel is still hearing from the gateway at all — one deadline
/// for the whole link, restarted by anything that arrives on it.
///
/// Source: 04-RESEARCH Finding 5. The gateway's fan-out was measured at a dead
/// flat **50.0 ms** — 121 tick notifications in 7001 ms, inter-tick deltas
/// `[51, 50, 50, 49, 50, 51, …]`, no drift, no outliers — with a production
/// default period of 100 ms, and **zero update frames** in that window because
/// nothing in the plant changed. The tick alone is the liveness signal.
///
/// **Why no number here is derived from that measurement.** Reading CLI-04's
/// "3× tick" literally against the measured cadence gives a 150–300 ms
/// deadline, and then one garbage collection pause on the panel, or one Wi-Fi
/// retransmit on the plant WAN, greys every value on the screen at once while
/// the gateway is perfectly healthy. Grey that cries wolf is grey the operator
/// stops reading. So the deadline is [ClientConfig.freshnessDeadline] — a
/// configured duration, default 3 s — and this file contains no arithmetic on
/// the transport cadence. The client could not learn it anyway: `HelloResult`
/// carries no tick field and the live handshake returned `capabilities: {}`.
///
/// **One timer, not one per subscription** (Finding 5's timer discipline). N
/// timers on a 1500-key page is N cancellations to get right on every
/// reconnect, and the one that is missed fires into a torn-down page. And the
/// reset comes from frames, never from socket state: `readyState` lies after
/// an OS sleep (STACK), so liveness is what arrived, not what the socket says
/// about itself.
///
/// What breaks in the plant without this file: silence is ambiguous. A socket
/// half-opened over a sleeping NAT looks exactly like a quiet plant, and the
/// operator reads a five-minute-old tank level as current. Freshness is the
/// product.
library;

import 'dart:async';

import 'package:tfc_relay_client/src/client_config.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// What arrived from the gateway.
///
/// A vocabulary rather than a bare `sawFrame()` because the distinction is
/// exactly the one the watchdog must *not* make: every one of these proves the
/// link is alive, and an implementation that rescheduled on ticks only would
/// call a plant dead precisely when it was busiest.
enum InboundFrame {
  /// The fixed-cadence heartbeat. On an idle plant it is the only traffic.
  tick,

  /// A subscription update: values actually changed.
  update,

  /// A reply to something this panel asked for.
  rpcResponse,
}

/// Announced when the whole view flips between fresh and stale, and only then.
typedef ViewFreshnessChanged = void Function(bool stale);

/// One deadline for the link, restarted by any inbound frame.
final class FreshnessWatchdog {
  /// Where the deadline comes from. Nothing here invents a duration.
  final ClientConfig config;

  /// Called on transitions only — an indicator that repaints twenty times a
  /// second is an indicator nobody sees change.
  final ViewFreshnessChanged onViewFreshnessChanged;

  /// The one timer. Not `late`, not a list: the type is the design.
  Timer? _deadline;

  bool _viewIsStale = false;
  bool _disposed = false;

  FreshnessWatchdog({
    required this.config,
    required this.onViewFreshnessChanged,
  });

  /// Whether the link has gone [ClientConfig.freshnessDeadline] without a
  /// single frame of any kind.
  bool get viewIsStale => _viewIsStale;

  /// 0 before the first frame and after [dispose], 1 while armed — never more,
  /// whatever else the client is tracking. The suite asserts this because the
  /// count is the design, not an implementation detail.
  int get debugTimerCount => _deadline == null ? 0 : 1;

  /// Records an inbound frame of any [kind] and restarts the link deadline.
  ///
  /// Runs on every frame — twenty times a second on the measured cadence — so
  /// it stays a cancel and a reschedule and nothing else.
  void sawFrame(InboundFrame kind) {
    if (_disposed) return;
    _deadline?.cancel();
    _deadline = Timer(config.freshnessDeadline, _linkWentQuiet);
    _becomeFresh();
  }

  /// Records a tick and re-judges every subscription. Declared here so the
  /// per-subscription cases fail by name; implemented in the GREEN step.
  void sawTick(TickParams tick) =>
      throw UnimplementedError('freshness watchdog: sawTick');

  /// Subscriptions whose source had stopped evaluating as of the last tick.
  Set<String> get staleSubscriptions =>
      throw UnimplementedError('freshness watchdog: staleSubscriptions');

  /// The same verdict for one subscription id.
  bool isSubscriptionStale(String subId) =>
      throw UnimplementedError('freshness watchdog: isSubscriptionStale');

  /// The same verdict between ticks, from a local instant plus the offset.
  Set<String> staleSubscriptionsAt(int localNowMs, {required int clockOffsetMs}) =>
      throw UnimplementedError('freshness watchdog: staleSubscriptionsAt');

  /// Forgets a subscription that is no longer displayed.
  void forgetSubscription(String subId) =>
      throw UnimplementedError('freshness watchdog: forgetSubscription');

  /// Drops the deadline. Nothing fires afterwards, and later frames are
  /// ignored rather than re-arming a watchdog whose page is gone.
  void dispose() {
    _disposed = true;
    _deadline?.cancel();
    _deadline = null;
  }

  void _linkWentQuiet() {
    _deadline = null;
    if (_viewIsStale) return;
    _viewIsStale = true;
    onViewFreshnessChanged(true);
  }

  void _becomeFresh() {
    if (!_viewIsStale) return;
    _viewIsStale = false;
    onViewFreshnessChanged(false);
  }
}
