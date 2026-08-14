/// The four-state machine that owns a connection's life.
///
/// Source: 04-RESEARCH Finding 2. Seam only at this commit — the bodies arrive
/// with the implementation, so the red run names the cases it wanted rather
/// than an unresolved import.
library;

import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'backoff.dart';
import 'client_config.dart';
import 'clock_offset.dart';
import 'freshness_watchdog.dart';
import 'readiness_barrier.dart';
import 'subscription_state.dart';

/// Where a connection is in its life. Four, and no fifth.
enum LinkState { connecting, resyncing, ready, down }

/// Builds a socket, builds a peer, drives hello to snapshot, and schedules the
/// next attempt when the link dies.
final class ConnectionSupervisor {
  ConnectionSupervisor({
    required this.uri,
    required this.config,
    required this.backoff,
    required this.barrier,
    required this.watchdog,
    required this.subscriptions,
    required this.storeFor,
  });

  final Uri uri;
  final ClientConfig config;
  final Backoff backoff;
  final ReadinessBarrier barrier;
  final FreshnessWatchdog watchdog;
  final Map<String, SubscriptionState> subscriptions;
  final ValueStore Function(String sub) storeFor;

  final StreamController<LinkState> _states =
      StreamController<LinkState>.broadcast();

  /// Every transition, in order.
  Stream<LinkState> get states => _states.stream;

  LinkState get state => throw UnimplementedError();

  rpc.Peer? get peer => throw UnimplementedError();

  ClockOffset get clockOffset => throw UnimplementedError();

  bool get stopped => throw UnimplementedError();

  String? get stopReason => throw UnimplementedError();

  int get debugTimerCount => throw UnimplementedError();

  List<Duration> get debugScheduledWaits => throw UnimplementedError();

  void start() => throw UnimplementedError();

  Future<void> dispose() async {
    await _states.close();
  }
}
