/// The freshness seam — declared here, implemented in the GREEN step.
///
/// Source: 04-RESEARCH Finding 5 (the fan-out tick measured dead flat at
/// 50.0 ms over 121 samples). Present so `freshness_test.dart` fails by
/// **case name** rather than by compile error: a red run that only says
/// "unresolved import" names nothing, and a test that never named what it
/// wanted is not evidence.
library;

import 'package:tfc_relay_client/src/client_config.dart';

/// What arrived from the gateway. Any one of them proves the link is alive.
enum InboundFrame { tick, update, rpcResponse }

/// Called when the whole view flips between fresh and stale.
typedef ViewFreshnessChanged = void Function(bool stale);

/// One deadline for the link, reset by any inbound frame.
final class FreshnessWatchdog {
  final ClientConfig config;
  final ViewFreshnessChanged onViewFreshnessChanged;

  FreshnessWatchdog({
    required this.config,
    required this.onViewFreshnessChanged,
  });

  /// Whether the link is currently past its freshness deadline.
  bool get viewIsStale => throw UnimplementedError('freshness watchdog: viewIsStale');

  /// 0 or 1. Asserted by the suite, because the count is the design.
  int get debugTimerCount =>
      throw UnimplementedError('freshness watchdog: debugTimerCount');

  /// Records an inbound frame of any kind and restarts the deadline.
  void sawFrame(InboundFrame kind) =>
      throw UnimplementedError('freshness watchdog: sawFrame');

  /// Stops the deadline. Nothing fires afterwards.
  void dispose() => throw UnimplementedError('freshness watchdog: dispose');
}
