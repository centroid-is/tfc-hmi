/// Which implementation `stateManProvider` builds, and nothing else.
///
/// The two properties worth a test are the two that fail silently: a station
/// in gateway mode must **not** open OPC UA sessions, Modbus sockets and a
/// collector — and a station in direct mode must keep doing exactly that, on
/// the same seam it always did. Both are observed through
/// `stateManFactoryProvider`, the seam `guard_wiring_test.dart` already uses,
/// which is the only way to watch the local construction happen without
/// actually performing it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/core/gateway_config.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';
import 'package:tfc_dart/core/state_man.dart';

import '../helpers/test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SecureStorage.setInstance(FakeSecureStorage());
  });

  /// A container whose device-local store is [local], and whose local
  /// `StateMan` path is a tripwire rather than a real construction.
  ProviderContainer harness({
    required PreferencesApi local,
    void Function()? onLocalBuild,
  }) =>
      ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith((ref) => createTestPreferences(
                stateManConfig: StateManConfig(opcua: const []),
              )),
          systemPreferencesProvider.overrideWith((ref) => createTestPreferences(
                stateManConfig: StateManConfig(opcua: const []),
              )),
          localPreferencesProvider.overrideWithValue(local),
          stateManFactoryProvider.overrideWithValue(({
            required StateManConfig config,
            required KeyMappings keyMappings,
            List<DeviceClient> deviceClients = const [],
          }) async {
            onLocalBuild?.call();
            throw StateError('local StateMan construction reached');
          }),
        ],
      );

  test('a gateway station builds no local StateMan', () async {
    var localBuilt = false;
    final local = InMemoryPreferences();
    await writeGatewayConfig(
      local,
      // A port nothing answers on: the client dials in the background and
      // backs off. What is under test is which object was built, not whether
      // it connected.
      const GatewayConfig(
          mode: TransportMode.gateway, url: 'ws://127.0.0.1:1'),
    );

    final ref = harness(local: local, onLocalBuild: () => localBuilt = true);
    addTearDown(ref.dispose);

    final stateMan = await ref.read(stateManProvider.future);

    expect(localBuilt, isFalse,
        reason: 'a gateway station must open no OPC UA session, no Modbus '
            'socket and no collector of its own');

    // The object it did build behaves as the adapter: it hands out no live
    // upstream client objects, and it refuses connection metadata rather than
    // answering emptily. A local StateMan does neither.
    expect(stateMan.clients, isEmpty);
    expect(stateMan.deviceClients, isEmpty);
    expect(stateMan.connMetaAliases, isEmpty);
    expect(() => stateMan.subscribeConnMeta('plc1'),
        throwsA(isA<StateManException>()));

    // Access control is a property of the panel, not of the transport, so the
    // guard is still in front of it.
    expect(stateMan, isA<StateMan>());
  });

  // wss with no pinned root is the one combination that would otherwise fail
  // every handshake with the message a real impostor produces. The provider
  // refuses it by name rather than letting the panel report an attack.
  test('gateway mode with an undiallable address fails loudly', () async {
    final local = InMemoryPreferences();
    await writeGatewayConfig(
      local,
      const GatewayConfig(
          mode: TransportMode.gateway, url: 'wss://10.50.10.11:9443'),
    );

    final ref = harness(local: local);
    addTearDown(ref.dispose);

    await expectLater(
        ref.read(stateManProvider.future), throwsA(isA<StateError>()));
  });

  test('an unconfigured station still takes the local path', () async {
    var localBuilt = false;
    final ref = harness(
        local: InMemoryPreferences(), onLocalBuild: () => localBuilt = true);
    addTearDown(ref.dispose);

    // The seam throws once reached, which is exactly the observation wanted:
    // direct mode is unchanged and still goes through it.
    await expectLater(
        ref.read(stateManProvider.future), throwsA(isA<StateError>()));
    expect(localBuilt, isTrue,
        reason: 'direct mode must keep building its own StateMan, on the same '
            'seam it always did');
  });
}
