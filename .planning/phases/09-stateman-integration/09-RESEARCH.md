# Phase 9: StateMan Integration - Research

**Researched:** 2026-03-07
**Domain:** Wiring Modbus DeviceClient adapters into StateMan subscribe/read/readMany/write routing and data_acquisition_isolate
**Confidence:** HIGH

## Summary

Phase 9 connects all the Modbus infrastructure built in Phases 4-8 to the application layer. The ModbusDeviceClientAdapter (Phase 7) already implements the DeviceClient interface. The config classes ModbusConfig and ModbusNodeConfig (Phase 8) already serialize/deserialize in StateManConfig and KeyMappingEntry. What remains is: (1) adding Modbus key resolution to StateMan's subscribe/read/readMany/write methods so Modbus keys route to the correct DeviceClient adapter, (2) building the config-to-spec translation that converts KeyMappingEntry.modbusNode into ModbusRegisterSpec for the adapter, (3) wiring createModbusDeviceClients into data_acquisition_isolate and the Flutter UI provider, and (4) ensuring OPC UA and M2400 keys continue working unchanged.

The existing M2400 integration pattern provides a direct template. M2400 routing uses `_resolveM2400Key()` which checks `keyMappings.nodes[key]?.m2400Node` and finds the matching DeviceClient by server alias. Modbus routing follows the same pattern but is simpler: Modbus keys are flat (no dot-notation hierarchy, no status filters, no record type mapping). The adapter's `canSubscribe()` uses exact key match against its spec map, so routing just needs to find the DeviceClient that claims the key.

A critical gap exists in the current codebase: `readMany()` and `write()` do NOT route through DeviceClient at all -- they only support OPC UA. Phase 9 must extend both methods to check DeviceClient instances first, following the same pattern as `subscribe()` and `read()`.

**Primary recommendation:** Add a generic `_resolveDeviceClientKey()` method that checks ALL device clients (not just M2400) for key ownership, then use it uniformly in subscribe, read, readMany, and write. This replaces the M2400-specific `_resolveM2400Key()` with a protocol-agnostic approach that automatically supports future protocols.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INTG-02 | StateMan.subscribe() returns polling stream for Modbus keys transparently | StateMan.subscribe() currently routes M2400 via _resolveM2400Key(), falls through to OPC UA. Modbus routing follows same pattern: check modbusNode in keyMappings, find matching DeviceClient, delegate to adapter.subscribe(). Adapter already returns Stream<DynamicValue>. |
| INTG-03 | StateMan.read() returns current value for Modbus keys | StateMan.read() has M2400 routing via _resolveM2400Key(). Add parallel Modbus check: find DeviceClient that canSubscribe(key), call adapter.read(key). Adapter already returns DynamicValue?. |
| INTG-04 | StateMan.write() routes to Modbus device for Modbus keys | StateMan.write() currently ONLY supports OPC UA (no DeviceClient routing at all). Must add DeviceClient check before OPC UA fallthrough. Adapter.write() already delegates to wrapper.write(spec, value.value). |
| INTG-05 | Modbus keys coexist with OPC UA and M2400 keys without interference | Key routing is determined by KeyMappingEntry contents: if modbusNode is set, route to Modbus; if m2400Node is set, route to M2400; otherwise route to OPC UA. A key has exactly one protocol assignment. |
| INTG-08 | createModbusDeviceClients factory wired into data_acquisition_isolate | data_acquisition_isolate.dart currently creates M2400 device clients via createM2400DeviceClients(). Add parallel Modbus client creation from config.modbus + keymappings. Also wire into lib/providers/state_man.dart for Flutter UI. |
| TEST-05 | StateMan Modbus routing has integration tests alongside OPC UA keys | Existing test patterns: device_client_routing_test.dart (MockDeviceClient for subscribe), data_acquisition_m2400_test.dart (full pipeline with StubServer). Modbus tests can use MockModbusClient from modbus_device_client_test.dart. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| tfc_dart | local | StateMan, DeviceClient, ModbusDeviceClientAdapter | All integration targets are in this package |
| open62541 | git(main) | DynamicValue, NodeId types | Protocol-agnostic value type used by DeviceClient interface |
| rxdart | ^0.28.0 | BehaviorSubject for value streams | Already used throughout StateMan and ModbusClientWrapper |
| modbus_client | local fork | ModbusElementType, ModbusRegisterSpec | Already used by wrapper and adapter |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| test | ^1.25.0 | Unit and integration testing | TEST-05 tests |
| json_annotation | ^4.9.0 | JSON serialization annotations | Already on StateManConfig, KeyMappingEntry |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Generic DeviceClient routing | Modbus-specific _resolveModbusKey() | Generic approach supports future protocols without method proliferation; but M2400 has special logic (status filters, dot-notation) that prevents full unification now |
| Config-to-spec translation in StateMan | Translation in data_acquisition_isolate | StateMan.create() is where device clients are connected; translation must happen before adapter creation |

**Installation:**
No new packages needed. All dependencies already in `packages/tfc_dart/pubspec.yaml`.

## Architecture Patterns

### Recommended Project Structure
```
packages/tfc_dart/lib/core/
  state_man.dart                    # MODIFY: Add Modbus routing to subscribe/read/readMany/write
  modbus_device_client.dart         # MODIFY: Update createModbusDeviceClients to build specs from config

packages/tfc_dart/bin/
  data_acquisition_isolate.dart     # MODIFY: Add Modbus device client creation + isolate config
  main.dart                         # MODIFY: Add Modbus isolate spawning

lib/providers/
  state_man.dart                    # MODIFY: Add Modbus device client creation alongside M2400

packages/tfc_dart/test/
  core/modbus_stateman_routing_test.dart  # NEW: TEST-05 integration tests
```

### Pattern 1: Config-to-Spec Translation
**What:** Convert KeyMappingEntry.modbusNode (config model) to ModbusRegisterSpec (runtime model) for each key
**When to use:** When building ModbusDeviceClientAdapter instances from config
**Example:**
```dart
// Source: Derived from existing ModbusNodeConfig (state_man.dart:287-313)
//         and ModbusRegisterSpec (modbus_client_wrapper.dart:32-46)
Map<String, ModbusRegisterSpec> buildSpecsFromKeyMappings(
  KeyMappings keyMappings,
  String? serverAlias,
) {
  final specs = <String, ModbusRegisterSpec>{};
  for (final entry in keyMappings.nodes.entries) {
    final modbusNode = entry.value.modbusNode;
    if (modbusNode == null) continue;
    if (modbusNode.serverAlias != serverAlias) continue;
    specs[entry.key] = ModbusRegisterSpec(
      key: entry.key,
      registerType: modbusNode.registerType.toModbusElementType(),
      address: modbusNode.address,
      dataType: modbusNode.dataType,
      pollGroup: modbusNode.pollGroup,
    );
  }
  return specs;
}
```

### Pattern 2: Modbus Key Resolution in StateMan
**What:** Check if a key has a modbusNode in keyMappings, find the matching DeviceClient, and route to it
**When to use:** In StateMan.subscribe(), read(), readMany(), write()
**Example:**
```dart
// Source: Follows _resolveM2400Key() pattern (state_man.dart:1062-1105)
// but simpler -- no status filters, no dot-notation, no record type mapping
DeviceClient? _resolveModbusDeviceClient(String key) {
  final entry = keyMappings.nodes[key];
  if (entry?.modbusNode == null) return null;
  final alias = entry!.modbusNode!.serverAlias;
  for (final dc in deviceClients) {
    if (dc is ModbusDeviceClientAdapter && dc.serverAlias == alias) {
      if (dc.canSubscribe(key)) return dc;
    }
  }
  return null;
}
```

### Pattern 3: Data Acquisition Isolate Wiring
**What:** Create Modbus device clients from config and pass them to StateMan.create()
**When to use:** In dataAcquisitionIsolateEntry and Flutter UI provider
**Example:**
```dart
// Source: Follows M2400 pattern in data_acquisition_isolate.dart:66-74
// Build Modbus device clients from config + key mappings
List<DeviceClient> buildModbusDeviceClients(
  List<ModbusConfig> modbusConfigs,
  KeyMappings keyMappings,
) {
  return modbusConfigs.map((config) {
    final specs = buildSpecsFromKeyMappings(keyMappings, config.serverAlias);
    final wrapper = ModbusClientWrapper(config.host, config.port, config.unitId);
    // Pre-configure poll groups from config
    for (final pg in config.pollGroups) {
      wrapper.addPollGroup(pg.name, pg.interval);
    }
    return ModbusDeviceClientAdapter(wrapper, specs: specs, serverAlias: config.serverAlias);
  }).toList();
}
```

### Pattern 4: Extending readMany() and write() for DeviceClient
**What:** Add DeviceClient routing to readMany() and write() which currently only support OPC UA
**When to use:** These methods must be extended for any DeviceClient protocol, not just Modbus
**Example:**
```dart
// StateMan.write() -- add DeviceClient routing before OPC UA fallthrough
// Source: Follows subscribe() routing pattern (state_man.dart:1231-1250)
Future<void> write(String key, DynamicValue value) async {
  key = resolveKey(key);

  // Check Modbus (and any other DeviceClient) first
  final dc = _resolveModbusDeviceClient(key);
  if (dc != null) {
    await dc.write(key, value);
    return;
  }

  // Check M2400 -- write is unsupported (throws UnsupportedError)
  // No M2400 routing needed for write since M2400 is read-only

  // Fall through to OPC UA (existing code)
  // ...
}
```

### Anti-Patterns to Avoid
- **Adding M2400-specific routing to Modbus paths:** M2400 has status filters, dot-notation field extraction, and record type mapping. Modbus has none of these. Don't copy `_resolveM2400Key()` complexity into Modbus routing.
- **Nesting Modbus check inside M2400 check:** Keep routing checks sequential and independent: check M2400, check Modbus, fall through to OPC UA. Don't create nested if-else chains.
- **Passing raw ModbusConfig list to createModbusDeviceClients without specs:** The factory needs both config (host/port/unitId) AND specs (from keyMappings). The existing `createModbusDeviceClients` signature already takes `List<({ModbusConfig config, Map<String, ModbusRegisterSpec> specs})>`.
- **Forgetting to wire Modbus into both data_acquisition_isolate AND Flutter UI provider:** Both paths create StateMan instances and must create Modbus device clients.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Config-to-spec translation | Manual field-by-field copying in each callsite | Shared `buildSpecsFromKeyMappings()` function | Called from data_acquisition_isolate, Flutter provider, and tests -- must be consistent |
| Poll group configuration | Manual Timer setup per adapter | `wrapper.addPollGroup()` from ModbusPollGroupConfig | Wrapper already manages poll lifecycle tied to connection status |
| DynamicValue wrapping | Custom type conversion in routing | ModbusDeviceClientAdapter (Phase 7) | Adapter already handles Object? -> DynamicValue with spec-based typeId mapping |
| Key ownership check | String matching on key patterns | `DeviceClient.canSubscribe(key)` | Each adapter knows its own keys from its spec map |

**Key insight:** Phase 9 is purely wiring/routing. All the heavy lifting (connection, polling, batching, type conversion, config serialization) is already implemented in Phases 4-8. The risk is in routing logic correctness and ensuring no regression in OPC UA and M2400 paths.

## Common Pitfalls

### Pitfall 1: readMany() Only Supports OPC UA
**What goes wrong:** readMany() uses NodeId lookups and OPC UA readAttribute() -- it has zero DeviceClient routing. Calling readMany() with Modbus keys will throw "Key not found" because lookupNodeId() returns null for Modbus keys.
**Why it happens:** readMany() was written before the DeviceClient abstraction was introduced.
**How to avoid:** Add DeviceClient routing at the top of readMany(): for each key, check if any DeviceClient claims it, call dc.read(key) for those, and only send OPC UA keys through the existing NodeId/readAttribute path.
**Warning signs:** readMany() throws StateManException for keys that work fine with subscribe() and read().

### Pitfall 2: write() Only Supports OPC UA
**What goes wrong:** StateMan.write() goes directly to OPC UA client without checking DeviceClient instances. Modbus write requests will throw "Key not found".
**Why it happens:** DeviceClient.write() was added in Phase 7 but StateMan.write() was never updated to use it.
**How to avoid:** Add DeviceClient routing before OPC UA fallthrough in write(), exactly like subscribe() and read() do.
**Warning signs:** write() works for OPC UA keys but throws for Modbus keys that subscribe()/read() handle fine.

### Pitfall 3: DataAcquisitionIsolateConfig Missing Modbus Fields
**What goes wrong:** DataAcquisitionIsolateConfig only has serverJson (OPC UA) and jbtmJson (M2400). Modbus configs can't be passed to the isolate.
**Why it happens:** Config class was created before Modbus integration existed.
**How to avoid:** Add `modbusJson` field to DataAcquisitionIsolateConfig. Since Modbus device clients run in the same isolate as the StateMan, they need the config to create wrappers.
**Warning signs:** Modbus works in Flutter UI (main isolate) but not in data_acquisition for collection.

### Pitfall 4: Forgetting Flutter UI Provider
**What goes wrong:** lib/providers/state_man.dart creates M2400 device clients but not Modbus device clients. Subscribe/read/write work in data_acquisition_isolate but fail in the Flutter UI.
**Why it happens:** Two separate StateMan creation paths exist: one in data_acquisition_isolate (for collection) and one in lib/providers/state_man.dart (for UI).
**How to avoid:** Update both paths with identical Modbus client creation logic. Consider extracting a shared helper.
**Warning signs:** Modbus keys work in collector data but not in UI widgets.

### Pitfall 5: Server Alias Matching Breaks with null Alias
**What goes wrong:** If ModbusConfig.serverAlias is null and ModbusNodeConfig.serverAlias is null, `null == null` is true, so keys accidentally match the wrong server.
**Why it happens:** Same pitfall exists for OPC UA (see `_getClientWrapper` comment: "Be mindful that null == null is true").
**How to avoid:** Require serverAlias on ModbusConfig when multiple Modbus servers exist. Single-server configs can use null alias safely (matches all null-alias keys).
**Warning signs:** Keys route to wrong Modbus device when multiple devices are configured without aliases.

### Pitfall 6: Isolate Serialization Boundary
**What goes wrong:** ModbusClientWrapper contains Timer, Socket, and StreamController objects that can't cross isolate boundaries. Trying to pass a constructed adapter to Isolate.spawn() will fail.
**Why it happens:** Dart isolates only send primitive types and transferables.
**How to avoid:** Follow the M2400 pattern: pass JSON config across the isolate boundary, reconstruct objects inside the isolate. DataAcquisitionIsolateConfig already serializes as JSON maps.
**Warning signs:** "Illegal argument in isolate message" error at spawn time.

## Code Examples

Verified patterns from the existing codebase:

### M2400 Routing in StateMan.subscribe() (the pattern to extend)
```dart
// Source: state_man.dart:1231-1250
Future<Stream<DynamicValue>> subscribe(String key) async {
  key = resolveKey(key);

  // Check M2400 key mappings first
  final m2400 = _resolveM2400Key(key);
  if (m2400 != null) {
    Stream<DynamicValue> stream = m2400.dc.subscribe(m2400.subscribeKey);
    if (m2400.statusFilter != null) {
      stream = stream.where((dv) => dv['status'].asInt == m2400.statusFilter);
    }
    if (m2400.fieldName != null) {
      stream = stream.map((dv) => dv[m2400.fieldName!]);
    }
    return stream;
  }

  // Fall through to OPC UA
  return _monitor(key);
}
```

### M2400 Routing in StateMan.read() (the pattern to extend)
```dart
// Source: state_man.dart:1108-1149
Future<DynamicValue> read(String key) async {
  key = resolveKey(key);

  // Check M2400 key mappings first
  final m2400 = _resolveM2400Key(key);
  if (m2400 != null) {
    var value = m2400.dc.read(m2400.subscribeKey);
    // ... status filter and field extraction ...
    return value;
  }

  // Fall through to OPC UA
  // ...
}
```

### createM2400DeviceClients (the factory pattern to follow)
```dart
// Source: state_man.dart:771-776
List<DeviceClient> createM2400DeviceClients(List<M2400Config> configs) {
  return configs.map((config) {
    final wrapper = M2400ClientWrapper(config.host, config.port);
    return M2400DeviceClientAdapter(wrapper, serverAlias: config.serverAlias);
  }).toList();
}
```

### DataAcquisitionIsolateConfig (add modbusJson field here)
```dart
// Source: data_acquisition_isolate.dart:15-29
class DataAcquisitionIsolateConfig {
  final Map<String, dynamic>? serverJson;
  final Map<String, dynamic> dbConfigJson;
  final Map<String, dynamic> keyMappingsJson;
  final List<Map<String, dynamic>> jbtmJson;
  final bool enableStatsLogging;
  // Phase 9: Add modbusJson field
  // final List<Map<String, dynamic>> modbusJson;
}
```

### Flutter UI StateMan Provider (add Modbus clients here)
```dart
// Source: lib/providers/state_man.dart:53-57
final deviceClients = createM2400DeviceClients(config.jbtm);
// Phase 9: Add Modbus device clients
// final modbusClients = buildModbusDeviceClients(config.modbus, keyMappings);
// final allDeviceClients = [...deviceClients, ...modbusClients];
final stateMan = await StateMan.create(
    config: config,
    keyMappings: keyMappings,
    deviceClients: deviceClients);  // -> allDeviceClients
```

### createModbusDeviceClients Existing Signature
```dart
// Source: modbus_device_client.dart:108-123
List<DeviceClient> createModbusDeviceClients(
  List<({ModbusConfig config, Map<String, ModbusRegisterSpec> specs})> configs,
) {
  return configs.map((entry) {
    final wrapper = ModbusClientWrapper(
      entry.config.host,
      entry.config.port,
      entry.config.unitId,
    );
    return ModbusDeviceClientAdapter(
      wrapper,
      specs: entry.specs,
      serverAlias: entry.config.serverAlias,
    );
  }).toList();
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| M2400-specific _resolveM2400Key() in each method | Per-method M2400 check (subscribe, read only) | Phase 7 | write() and readMany() still OPC UA only -- must be extended |
| OPC UA-only readMany() | Still OPC UA-only | Original design | MUST be extended for Modbus (and ideally M2400 too) |
| OPC UA-only write() | Still OPC UA-only | Original design | MUST be extended for Modbus |
| M2400 device clients only in isolate | M2400 only | Phase integration tests | MUST add Modbus to both isolate and UI provider |

## Open Questions

1. **Should Modbus run in a separate isolate or same isolate as M2400?**
   - What we know: M2400 runs in a single shared isolate for all M2400 servers. OPC UA runs one isolate per server. Modbus uses poll-based reading (Timer.periodic) that is lightweight.
   - What's unclear: Whether Modbus polling timers interfere with OPC UA runIterate() in the same isolate.
   - Recommendation: Run Modbus in the same isolate as M2400 (or its own single shared isolate). Modbus polling is asynchronous and lightweight -- no CPU-intensive FFI loop like OPC UA's runIterate(). Pass all Modbus configs to a single isolate.

2. **Should readMany() support M2400 too, or just Modbus?**
   - What we know: readMany() currently only supports OPC UA. Adding Modbus support is required. M2400 support is not required by this phase.
   - Recommendation: Add generic DeviceClient routing to readMany() that handles any DeviceClient key. This naturally supports both Modbus and M2400 without extra work. However, don't block phase completion on M2400 readMany() support -- focus on Modbus keys.

3. **Does the createModbusDeviceClients factory need poll group pre-configuration?**
   - What we know: The existing factory in modbus_device_client.dart creates wrappers but does NOT call `wrapper.addPollGroup()` for configured poll groups. Without this, all subscriptions use the default 1-second poll interval.
   - Recommendation: Add poll group pre-configuration in the factory or in a new `buildModbusDeviceClients()` helper that reads `ModbusConfig.pollGroups` and calls `wrapper.addPollGroup()` for each.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | package:test v1.25.0 |
| Config file | none (standard dart test runner) |
| Quick run command | `cd packages/tfc_dart && dart test test/core/modbus_stateman_routing_test.dart` |
| Full suite command | `cd packages/tfc_dart && dart test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INTG-02 | subscribe() returns stream for Modbus key | unit | `cd packages/tfc_dart && dart test test/core/modbus_stateman_routing_test.dart -x` | Wave 0 |
| INTG-02 | subscribe() stream emits DynamicValue with correct typeId | unit | same file | Wave 0 |
| INTG-03 | read() returns cached DynamicValue for Modbus key | unit | same file | Wave 0 |
| INTG-03 | read() returns null/throws when no cached value | unit | same file | Wave 0 |
| INTG-04 | write() routes to Modbus DeviceClient | unit | same file | Wave 0 |
| INTG-04 | write() throws for read-only Modbus register types | unit | same file | Wave 0 |
| INTG-05 | OPC UA subscribe still works when Modbus keys present | unit | same file | Wave 0 |
| INTG-05 | M2400 subscribe still works when Modbus keys present | unit | same file | Wave 0 |
| INTG-05 | Mixed protocol readMany returns all values | unit | same file | Wave 0 |
| INTG-08 | buildModbusDeviceClients creates adapters from config | unit | same file | Wave 0 |
| INTG-08 | Poll groups pre-configured from ModbusConfig.pollGroups | unit | same file | Wave 0 |
| TEST-05 | All above tests pass (routing completeness) | unit | same file | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd packages/tfc_dart && dart test test/core/modbus_stateman_routing_test.dart`
- **Per wave merge:** `cd packages/tfc_dart && dart test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `packages/tfc_dart/test/core/modbus_stateman_routing_test.dart` -- covers INTG-02 through INTG-08, TEST-05
- [ ] No framework install needed -- `package:test` already in dev_dependencies
- [ ] MockModbusClient and createWrapperWithMock already exist in `modbus_device_client_test.dart` -- can be reused/extracted

## Sources

### Primary (HIGH confidence)
- `packages/tfc_dart/lib/core/state_man.dart` -- Full StateMan class with subscribe (line 1231), read (line 1108), readMany (line 1151), write (line 1199), DeviceClient interface (line 674), M2400DeviceClientAdapter (line 711), _resolveM2400Key (line 1062), StateManConfig (line 316), KeyMappingEntry (line 399), KeyMappings (line 424)
- `packages/tfc_dart/lib/core/modbus_device_client.dart` -- ModbusDeviceClientAdapter (line 11), createModbusDeviceClients factory (line 108)
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` -- ModbusClientWrapper with subscribe/read/write/addPollGroup APIs
- `packages/tfc_dart/bin/data_acquisition_isolate.dart` -- DataAcquisitionIsolateConfig (line 15), isolate entry point (line 36), M2400 client creation (line 66)
- `packages/tfc_dart/bin/main.dart` -- Main entry point spawning isolates per OPC UA server and one for M2400
- `lib/providers/state_man.dart` -- Flutter UI StateMan provider with M2400 device client creation (line 53)
- `packages/tfc_dart/test/core/modbus_device_client_test.dart` -- MockModbusClient, createWrapperWithMock, adapter contract tests
- `packages/tfc_dart/test/core/device_client_routing_test.dart` -- MockDeviceClient, DeviceClient routing tests
- `packages/tfc_dart/test/integration/data_acquisition_m2400_test.dart` -- Full M2400 pipeline integration test pattern

### Secondary (MEDIUM confidence)
- `.planning/phases/07-deviceclient-adapter/07-RESEARCH.md` -- Phase 7 architecture decisions and adapter patterns
- `.planning/phases/08-config-serialization/08-01-SUMMARY.md` -- Phase 8 config class details and createModbusDeviceClients signature

### Tertiary (LOW confidence)
None -- all findings verified against source code.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, all libraries already in use
- Architecture: HIGH -- direct extension of established M2400 routing pattern, all code paths verified
- Pitfalls: HIGH -- identified from reading actual current code (readMany/write gaps are factual, not speculative)
- Test strategy: HIGH -- follows existing test patterns (MockDeviceClient, MockModbusClient)

**Research date:** 2026-03-07
**Valid until:** 2026-04-07 (stable -- internal wiring, no external dependencies changing)
