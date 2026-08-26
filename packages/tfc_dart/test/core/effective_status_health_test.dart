import 'dart:async';

import 'package:test/test.dart';
import 'package:open62541/open62541.dart'
    show ClientApi, ClientState, SecureChannelState, SessionState;
import 'package:tfc_dart/core/state_man.dart';

/// The health derivation never touches the client — it reads only the
/// wrapper's own bookkeeping — so an exploding stub keeps the tests honest.
class FakeClientApi implements ClientApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// The frozen-session incidents (docs/opcua-frozen-session-repro.md) all share
// one property: the client dies without emitting a single further event, so
// any status derived purely from events reads "connected" forever. These
// tests pin the timer-derived effectiveStatus that closes that gap.
void main() {
  ClientState activated() => ClientState(
        channelState: SecureChannelState.UA_SECURECHANNELSTATE_OPEN,
        sessionState: SessionState.UA_SESSIONSTATE_ACTIVATED,
        recoveryStatus: 0,
      );

  ClientState channelOpenSessionClosed() => ClientState(
        channelState: SecureChannelState.UA_SECURECHANNELSTATE_OPEN,
        sessionState: SessionState.UA_SESSIONSTATE_CLOSED,
        recoveryStatus: 0,
      );

  late ClientWrapper wrapper;

  setUp(() {
    wrapper = ClientWrapper(FakeClientApi(), OpcUAConfig()..serverAlias = 'plc');
  });

  tearDown(() => wrapper.dispose());

  test('starts disconnected', () {
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.disconnected);
  });

  test('channel open without a session is connecting, not connected', () {
    wrapper.updateConnectionStatus(channelOpenSessionClosed());
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.connecting);
  });

  test('fresh connect without a heartbeat yet stays connecting (grace)', () {
    wrapper.updateConnectionStatus(activated());
    // No heartbeat tick has arrived, but we are inside heartbeatStartGrace.
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.connecting);
  });

  test('heartbeat tick promotes to connected', () {
    wrapper.updateConnectionStatus(activated());
    wrapper.debugSetLastHeartbeatTick(DateTime.now());
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.connected);
  });

  test('stale heartbeat demotes connected to opcuaUnhealthy', () {
    wrapper.updateConnectionStatus(activated());
    wrapper.debugSetLastHeartbeatTick(DateTime.now()
        .subtract(ClientWrapper.heartbeatStaleAfter + const Duration(seconds: 1)));
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.opcuaUnhealthy);
  });

  test('frozen session: connected status with no event ever again', () {
    // The real incident: session activates, data flows, then the client
    // dies silently. connectionStatus stays `connected` forever because no
    // ClientState event is ever delivered again.
    wrapper.updateConnectionStatus(activated());
    wrapper.debugSetLastHeartbeatTick(DateTime.now());
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.connected);

    // Time passes; nothing else happens. The event-driven status is stale…
    wrapper.debugSetLastHeartbeatTick(
        DateTime.now().subtract(const Duration(minutes: 5)));
    expect(wrapper.connectionStatus, ConnectionStatus.connected,
        reason: 'event-driven status is stale by design here');
    // …but the derived health is not.
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.opcuaUnhealthy);
  });

  test('inactivity marks unhealthy until recovery', () {
    wrapper.updateConnectionStatus(activated());
    wrapper.debugSetLastHeartbeatTick(DateTime.now());
    wrapper.simulateInactivity();
    wrapper.debugRecomputeEffectiveStatus();
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.opcuaUnhealthy);

    wrapper.simulateHeartbeatTick(); // triggers _handleRecovery
    wrapper.debugSetLastHeartbeatTick(DateTime.now());
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.connected);
  });

  test('lost session marks unhealthy until cleared', () {
    wrapper.updateConnectionStatus(activated());
    wrapper.debugSetLastHeartbeatTick(DateTime.now());
    wrapper.markSessionLost();
    wrapper.debugRecomputeEffectiveStatus();
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.opcuaUnhealthy);

    wrapper.sessionLost = false; // what the resubscribe path does
    wrapper.debugSetLastHeartbeatTick(DateTime.now());
    expect(wrapper.effectiveStatus, EffectiveDeviceStatus.connected);
  });

  test('health timer only runs while the stream has listeners', () async {
    // Regression: an always-on periodic timer in the constructor failed
    // every widget test that builds a StateMan and never drains it —
    // flutter_test's "A Timer is still pending" invariant. The clock must
    // start with the first stream listener and stop with the last; an
    // unobserved wrapper stays timer-free because the synchronous getter
    // re-derives on every read.
    final timers = <Timer>[];
    await runZoned(() async {
      final w =
          ClientWrapper(FakeClientApi(), OpcUAConfig()..serverAlias = 'plc');
      w.updateConnectionStatus(activated());
      expect(w.effectiveStatus, EffectiveDeviceStatus.connecting);
      expect(timers, isEmpty,
          reason: 'no listener → no clock, however much the wrapper is used');

      final sub = w.effectiveStatusStream.listen((_) {});
      expect(timers, hasLength(1), reason: 'first listener starts the clock');

      await sub.cancel();
      expect(timers.single.isActive, isFalse,
          reason: 'last listener leaving must stop the clock');

      w.dispose();
      expect(timers.where((t) => t.isActive), isEmpty);
    },
        zoneSpecification: ZoneSpecification(
      createPeriodicTimer: (self, parent, zone, period, f) {
        final timer = parent.createPeriodicTimer(zone, period, f);
        timers.add(timer);
        return timer;
      },
    ));
  });

  test('stream emits transitions exactly once per change', () async {
    final seen = <EffectiveDeviceStatus>[];
    final sub = wrapper.effectiveStatusStream.listen(seen.add);

    wrapper.updateConnectionStatus(activated());
    wrapper.debugSetLastHeartbeatTick(DateTime.now());
    wrapper.debugRecomputeEffectiveStatus(); // no-op: value unchanged
    wrapper.debugSetLastHeartbeatTick(
        DateTime.now().subtract(const Duration(minutes: 1)));
    await Future<void>.delayed(Duration.zero);

    expect(
        seen,
        containsAllInOrder([
          EffectiveDeviceStatus.disconnected, // BehaviorSubject seed
          EffectiveDeviceStatus.connecting,
          EffectiveDeviceStatus.connected,
          EffectiveDeviceStatus.opcuaUnhealthy,
        ]));
    expect(seen.length, 4, reason: 'unchanged recomputes must not emit');
    await sub.cancel();
  });
}
