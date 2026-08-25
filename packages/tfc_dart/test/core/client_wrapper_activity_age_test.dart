import 'package:test/test.dart';
import 'package:tfc_dart/core/state_man.dart';

import 'client_wrapper_stream_registry_test.dart' show DrivableClientApi;

// The plant freeze the bench could reproduce but the harness could not
// (#345, #346 bench notes 2026-08-25): on the TwinCAT servers the heartbeat
// (server-time monitored item) never ticks at all. lastDataAgeSec answered 0
// for "no tick yet", so the stale watchdog read a born-dead heartbeat as
// perfectly fresh forever, and a server-side FIN was never noticed -- data
// emissions did not refresh the age either, only heartbeat ticks did.
void main() {
  test('a heartbeat that never ticks goes stale, not fresh-forever', () async {
    final wrapper = ClientWrapper(DrivableClientApi(), OpcUAConfig());
    wrapper.subscriptionId = 1;
    // Arming the heartbeat starts the clock. The fake's monitoredItems
    // stream never emits -- the TwinCAT condition.
    wrapper.startHeartbeat(1);
    await Future.delayed(const Duration(milliseconds: 300));
    expect(wrapper.lastDataAgeSec, greaterThan(0.25),
        reason: 'with the heartbeat armed but silent, age must grow from the '
            'arming instant; reading 0 makes the stale watchdog blind to a '
            'heartbeat that never worked');
    wrapper.dispose();
  });

  test('data emissions are activity: they reset the age', () async {
    final wrapper = ClientWrapper(DrivableClientApi(), OpcUAConfig());
    wrapper.subscriptionId = 1;
    wrapper.startHeartbeat(1);
    await Future.delayed(const Duration(milliseconds: 300));
    // A monitored-item value arrives (routed through recordRequest in the
    // subscribe path). On a server whose heartbeat never ticks, this is the
    // ONLY freshness signal -- and it stopping is the FIN symptom.
    wrapper.recordRequest();
    await Future.delayed(const Duration(milliseconds: 100));
    final age = wrapper.lastDataAgeSec;
    expect(age, greaterThan(0.05),
        reason: 'age is measured, not pinned to zero');
    expect(age, lessThan(0.25),
        reason: 'the data emission must reset the age; if only heartbeat '
            'ticks count, a flowing-data/no-heartbeat server reads stale and '
            'gets torn down while healthy -- or, before arming existed, '
            'read fresh forever and never got torn down at all');
    wrapper.dispose();
  });

  test('before any subscription the age stays 0 (watchdog is gated off)', () {
    final wrapper = ClientWrapper(DrivableClientApi(), OpcUAConfig());
    expect(wrapper.lastDataAgeSec, 0,
        reason: 'pre-subscription there is nothing to be stale; the '
            'supervisor additionally gates on subscriptionId != null');
    wrapper.dispose();
  });
}
