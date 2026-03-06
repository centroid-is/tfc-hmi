# Phase 7: DeviceClient Adapter - Research

**Researched:** 2026-03-06
**Domain:** Dart adapter pattern -- wrapping ModbusClientWrapper in the DeviceClient abstract interface
**Confidence:** HIGH

## Summary

Phase 7 is a pure adapter/translation layer. The ModbusClientWrapper (Phases 4-6) already implements all connection, subscribe, read, and write operations. The DeviceClient abstract class (state_man.dart:531-558) defines 8 methods. The M2400DeviceClientAdapter (state_man.dart:565-613) provides a direct structural template with ~50 lines of code. The Modbus adapter is simpler than M2400 in some ways (no status mapping needed -- both use state_man's ConnectionStatus directly) but more complex in others (dynamic keys from register specs vs static key set, Object? to DynamicValue translation).

The primary engineering challenges are: (1) translating between ModbusClientWrapper's `Object?` value streams and DeviceClient's `DynamicValue` streams, requiring a ModbusDataType-to-NodeId typeId mapping; (2) handling dynamic subscribable keys derived from register configuration rather than a static set; and (3) deciding whether to add `write()` to the DeviceClient interface now or defer to Phase 9.

**Primary recommendation:** Follow the M2400DeviceClientAdapter pattern exactly -- one adapter per device, constructor-injected wrapper + register specs, spec-derived typeId for DynamicValue wrapping. Add write support to DeviceClient interface in this phase to keep the adapter complete.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None -- all implementation decisions are at Claude's discretion.

### Claude's Discretion
- Key naming format and routing mechanism
- One adapter per device vs shared adapter
- Lazy vs eager subscription strategy
- Whether to add write() to DeviceClient interface now
- M2400 adapter write handling
- Key-to-spec translation approach
- DynamicValue type mapping strategy (spec-based vs runtime inference)
- Write direction type validation
- Quality/timestamp field handling
- Register config injection mechanism
- Server alias inclusion
- Factory function inclusion
- File location for adapter class

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INTG-01 | ModbusDeviceClientAdapter implements DeviceClient interface (same pattern as M2400DeviceClientAdapter) | M2400 adapter analyzed line-by-line (state_man.dart:565-613); all 8 interface methods mapped to wrapper equivalents; DynamicValue translation strategy defined |
| TEST-04 | ModbusDeviceClientAdapter has unit tests verifying DeviceClient interface contract | Existing test patterns analyzed: MockModbusClient (modbus_client_wrapper_test.dart), MockDeviceClient (device_client_routing_test.dart); test framework is `package:test` v1.25.0 |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| open62541 | git(main) | DynamicValue and NodeId types for protocol-agnostic values | Already used by StateMan and DeviceClient interface |
| rxdart | ^0.28.0 | BehaviorSubject for connection streams | Already used by ModbusClientWrapper |
| modbus_client | local fork | ModbusElementType, ModbusRegisterSpec types | Already used by ModbusClientWrapper |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| test | ^1.25.0 | Unit testing framework | All TEST-04 tests |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Spec-based typeId mapping | Runtime type inference from Object? | Runtime inference is ambiguous (int could be int16/int32/uint16/etc.); spec-based is deterministic |
| One adapter per device | Single shared adapter for all Modbus devices | Breaks M2400 pattern parity; complicates connection status per-device |

**Installation:**
No new packages needed. All dependencies already in `packages/tfc_dart/pubspec.yaml`.

## Architecture Patterns

### Recommended Project Structure
```
packages/tfc_dart/lib/core/
  state_man.dart              # DeviceClient interface + M2400DeviceClientAdapter (existing)
  modbus_client_wrapper.dart  # ModbusClientWrapper (existing, Phases 4-6)
  modbus_device_client.dart   # NEW: ModbusDeviceClientAdapter + factory function

packages/tfc_dart/test/core/
  modbus_device_client_test.dart  # NEW: TEST-04 contract tests
```

**Rationale for separate file:** The adapter is a distinct concern from the wrapper itself. M2400DeviceClientAdapter lives in state_man.dart because it's tightly coupled to M2400ClientWrapper from jbtm. ModbusDeviceClientAdapter wraps a local class (ModbusClientWrapper) and benefits from its own file to keep state_man.dart focused. However, the factory function `createModbusDeviceClients()` should go in the same file for pattern parity with `createM2400DeviceClients()`.

### Pattern 1: Adapter Structure (follow M2400 exactly)
**What:** One-to-one adapter wrapping ModbusClientWrapper as DeviceClient
**When to use:** Always -- this is the only pattern
**Example:**
```dart
// Source: M2400DeviceClientAdapter (state_man.dart:565-613)
class ModbusDeviceClientAdapter implements DeviceClient {
  final ModbusClientWrapper wrapper;
  final String? serverAlias;
  final Map<String, ModbusRegisterSpec> _specs;

  // Keys derived from register specs (dynamic, not static like M2400)
  @override
  Set<String> get subscribableKeys => _specs.keys.toSet();

  @override
  bool canSubscribe(String key) => _specs.containsKey(key);

  @override
  Stream<DynamicValue> subscribe(String key) {
    final spec = _specs[key];
    if (spec == null) throw ArgumentError('Unknown key: $key');
    return wrapper.subscribe(spec).map((value) => _toDynamicValue(value, spec));
  }

  @override
  DynamicValue? read(String key) {
    final raw = wrapper.read(key);
    if (raw == null) return null;
    final spec = _specs[key];
    if (spec == null) return null;
    return _toDynamicValue(raw, spec);
  }

  // No status mapping needed (unlike M2400)
  @override
  ConnectionStatus get connectionStatus => wrapper.connectionStatus;

  @override
  Stream<ConnectionStatus> get connectionStream => wrapper.connectionStream;

  @override
  void connect() => wrapper.connect();

  @override
  void dispose() => wrapper.dispose();
}
```

### Pattern 2: Object? to DynamicValue Translation (spec-based typeId)
**What:** Map ModbusDataType from the register spec to NodeId for DynamicValue.typeId
**When to use:** Every subscribe() and read() call
**Example:**
```dart
// Source: NodeId static getters (open62541_dart node_id.dart:52-108)
// Source: ModbusDataType enum (modbus_client_wrapper.dart:16-26)
static NodeId _typeIdFromDataType(ModbusDataType dataType) {
  switch (dataType) {
    case ModbusDataType.bit:
      return NodeId.boolean;
    case ModbusDataType.int16:
      return NodeId.int16;
    case ModbusDataType.uint16:
      return NodeId.uint16;
    case ModbusDataType.int32:
      return NodeId.int32;
    case ModbusDataType.uint32:
      return NodeId.uint32;
    case ModbusDataType.float32:
      return NodeId.float;
    case ModbusDataType.int64:
      return NodeId.int64;
    case ModbusDataType.uint64:
      return NodeId.uint64;
    case ModbusDataType.float64:
      return NodeId.double;
  }
}

static DynamicValue _toDynamicValue(Object? value, ModbusRegisterSpec spec) {
  return DynamicValue(
    value: value,
    typeId: _typeIdFromDataType(spec.dataType),
  );
}
```

### Pattern 3: Write Support on DeviceClient
**What:** Add `Future<void> write(String key, DynamicValue value)` to the abstract DeviceClient interface
**When to use:** Phase 7 (keeps adapter complete; Phase 9 StateMan routing consumes it)
**Example:**
```dart
// Add to DeviceClient abstract class:
Future<void> write(String key, DynamicValue value);

// M2400DeviceClientAdapter: throw UnsupportedError (M2400 is read-only)
@override
Future<void> write(String key, DynamicValue value) {
  throw UnsupportedError('M2400 does not support writes');
}

// ModbusDeviceClientAdapter: translate DynamicValue back to Object? and delegate
@override
Future<void> write(String key, DynamicValue value) async {
  final spec = _specs[key];
  if (spec == null) throw ArgumentError('Unknown Modbus key: $key');
  await wrapper.write(spec, value.value);
}
```

### Pattern 4: Factory Function (for Phase 9 wiring)
**What:** `createModbusDeviceClients()` mirrors `createM2400DeviceClients()` (state_man.dart:620-625)
**When to use:** Include in this phase for pattern parity; Phase 9 wires it into data_acquisition_isolate
**Example:**
```dart
// Source: createM2400DeviceClients (state_man.dart:620-625)
List<DeviceClient> createModbusDeviceClients(List<ModbusDeviceConfig> configs) {
  return configs.map((config) {
    final wrapper = ModbusClientWrapper(config.host, config.port, config.unitId);
    // Pre-configure poll groups from config
    for (final pg in config.pollGroups) {
      wrapper.addPollGroup(pg.name, pg.interval);
    }
    return ModbusDeviceClientAdapter(
      wrapper,
      specs: {for (final s in config.specs) s.key: s},
      serverAlias: config.alias,
    );
  }).toList();
}
```

**Note:** The `ModbusDeviceConfig` type does not exist yet -- it will be defined in Phase 8 (INTG-06). For Phase 7, the adapter class and its constructor should be designed to accept a `Map<String, ModbusRegisterSpec>` directly. The factory function can be stubbed or deferred to Phase 8/9 when the config types exist.

### Anti-Patterns to Avoid
- **Runtime type inference for DynamicValue.typeId:** Don't infer typeId from `value.runtimeType` -- `num` from Modbus library is always `double` for register types (due to multiplier formula), making int16/uint16/int32 indistinguishable at runtime. Always use spec.dataType.
- **Shared adapter for multiple devices:** Don't merge multiple ModbusClientWrapper instances into one adapter. Each device has its own connection lifecycle, and M2400 uses one-adapter-per-device.
- **Dot-notation key routing in Modbus adapter:** M2400 uses `key.split('.').first` for dot-notation keys like `BATCH.weight`. Modbus keys are flat register keys (no hierarchy), so `canSubscribe` should use exact key match, not prefix matching.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DynamicValue type mapping | Custom type inference from runtime values | Spec-based `ModbusDataType -> NodeId` static map | Runtime `num` is always double; can't distinguish int16 from uint32 |
| Connection status mapping | Custom status enum translation | Direct passthrough (`wrapper.connectionStatus`) | ModbusClientWrapper already uses state_man's `ConnectionStatus` -- no mapping needed (unlike M2400 which has its own enum) |
| Key validation | Runtime key string parsing | `Map<String, ModbusRegisterSpec>` lookup | Register specs are known at construction time from config |

**Key insight:** The Modbus adapter is simpler than M2400 in connection status (direct passthrough) but requires the DynamicValue translation layer that M2400 doesn't need (M2400ClientWrapper already returns DynamicValue).

## Common Pitfalls

### Pitfall 1: ModbusClientWrapper returns Object?, not DynamicValue
**What goes wrong:** DeviceClient.subscribe() must return `Stream<DynamicValue>`, but wrapper.subscribe() returns `Stream<Object?>`.
**Why it happens:** Phase 5 decision: "Object? as BehaviorSubject value type -- bool/int/double are all Object; Phase 7 adapter wraps to DynamicValue."
**How to avoid:** Use `.map()` on the wrapper's stream to wrap each value in `DynamicValue(value: v, typeId: typeIdFromSpec)`.
**Warning signs:** Type errors at compile time if you forget the mapping.

### Pitfall 2: ModbusNumRegister returns double, not int
**What goes wrong:** Register values like int16 and uint16 come through as `double` (num) from the modbus_client library due to its multiplier formula.
**Why it happens:** Phase 5 finding: "ModbusNumRegister returns num (double due to multiplier formula) -- library behavior, not wrapper choice."
**How to avoid:** Don't try to cast values to specific Dart types based on ModbusDataType. Pass through as-is in DynamicValue.value. The typeId is what matters for downstream interpretation.
**Warning signs:** Assertion failures or cast exceptions if you assume int for integer register types.

### Pitfall 3: canSubscribe exact match vs prefix match
**What goes wrong:** Using M2400's `key.split('.').first` pattern when Modbus keys are flat.
**Why it happens:** Copy-paste from M2400DeviceClientAdapter.
**How to avoid:** Modbus keys are exact matches to spec.key (e.g., `"pump1_speed"`, `"tank_level"`). No dot-notation hierarchy. Use `_specs.containsKey(key)` directly.
**Warning signs:** Keys like `"pump1_speed.subfield"` incorrectly matching.

### Pitfall 4: Forgetting to add write() to M2400DeviceClientAdapter
**What goes wrong:** Adding write() to DeviceClient interface breaks M2400DeviceClientAdapter compilation.
**Why it happens:** Abstract interface change requires all implementors to update.
**How to avoid:** Add the write() override to M2400DeviceClientAdapter (throw UnsupportedError) and to MockDeviceClient in tests at the same time.
**Warning signs:** dart analyze errors on M2400DeviceClientAdapter and test mocks.

### Pitfall 5: Eager subscription in constructor
**What goes wrong:** Calling wrapper.subscribe() during adapter construction before connect() is called.
**Why it happens:** Misunderstanding the lifecycle -- subscribe() should be called by StateMan when a UI widget requests data.
**How to avoid:** Adapter stores specs but doesn't subscribe until DeviceClient.subscribe(key) is called. This matches M2400 pattern where wrapper.subscribe() is called on demand.
**Warning signs:** Subscriptions created before connection, poll groups starting without connection.

## Code Examples

Verified patterns from the existing codebase:

### M2400DeviceClientAdapter (the pattern to follow)
```dart
// Source: state_man.dart:565-613
class M2400DeviceClientAdapter implements DeviceClient {
  final M2400ClientWrapper wrapper;
  final String? serverAlias;
  static const _validKeys = {'BATCH', 'STAT', 'INTRO', 'LUA'};

  M2400DeviceClientAdapter(this.wrapper, {this.serverAlias});

  @override
  Set<String> get subscribableKeys => _validKeys;

  @override
  bool canSubscribe(String key) => _validKeys.contains(key.split('.').first);

  @override
  Stream<DynamicValue> subscribe(String key) => wrapper.subscribe(key);

  @override
  DynamicValue? read(String key) => wrapper.lastValue(key);

  @override
  ConnectionStatus get connectionStatus => _mapStatus(wrapper.status);

  @override
  Stream<ConnectionStatus> get connectionStream =>
      wrapper.statusStream.map(_mapStatus);

  @override
  void connect() => wrapper.connect();

  @override
  void dispose() => wrapper.dispose();

  static ConnectionStatus _mapStatus(jbtm.ConnectionStatus s) { ... }
}
```

### ModbusClientWrapper subscribe API (what adapter wraps)
```dart
// Source: modbus_client_wrapper.dart:272-299
Stream<Object?> subscribe(ModbusRegisterSpec spec)
// Returns Stream<Object?> backed by BehaviorSubject

// Source: modbus_client_wrapper.dart:303-305
Object? read(String key)
// Returns last-known cached value, or null

// Source: modbus_client_wrapper.dart:342-358
Future<void> write(ModbusRegisterSpec spec, Object? value) async
// Throws StateError if disconnected/disposed, ArgumentError for read-only types
```

### MockModbusClient pattern (for adapter tests)
```dart
// Source: modbus_client_wrapper_test.dart:11-70
class MockModbusClient extends ModbusClientTcp {
  bool _connected = false;
  bool shouldFailConnect = false;
  // ... mock methods for connect/disconnect/send
}

({ModbusClientWrapper wrapper, MockModbusClient mock}) createWrapperWithMock() {
  final mock = MockModbusClient();
  final wrapper = ModbusClientWrapper('127.0.0.1', 502, 1,
      clientFactory: (h, p, u) => mock);
  return (wrapper: wrapper, mock: mock);
}
```

### DynamicValue construction
```dart
// Source: open62541_dart dynamic_value.dart:118
DynamicValue({this.value, this.description, this.typeId, this.displayName, this.name});

// Minimal construction for Modbus values:
DynamicValue(value: 42.0, typeId: NodeId.float)
DynamicValue(value: true, typeId: NodeId.boolean)
DynamicValue(value: 1234, typeId: NodeId.uint16)
```

### NodeId type identifiers (complete mapping)
```dart
// Source: open62541_dart node_id.dart:52-108
NodeId.boolean   // for ModbusDataType.bit (coils, discrete inputs)
NodeId.int16     // for ModbusDataType.int16
NodeId.uint16    // for ModbusDataType.uint16
NodeId.int32     // for ModbusDataType.int32
NodeId.uint32    // for ModbusDataType.uint32
NodeId.int64     // for ModbusDataType.int64
NodeId.uint64    // for ModbusDataType.uint64
NodeId.float     // for ModbusDataType.float32
NodeId.double    // for ModbusDataType.float64
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| M2400-only device clients | Polymorphic DeviceClient for any protocol | Phase 7 (now) | Modbus uses same subscribe/read/write interface |
| Manual status mapping per adapter | Direct passthrough when enums match | Phase 4 design | ModbusClientWrapper uses state_man's ConnectionStatus directly |
| Static key sets | Dynamic key sets from register config | Phase 7 (now) | Modbus keys come from user configuration, not hardcoded |

## Open Questions

1. **Should write() be added to DeviceClient now or Phase 9?**
   - What we know: StateMan.write() currently only routes to OPC UA. Phase 9 (INTG-04) adds Modbus write routing.
   - What's unclear: Whether adding write() to the interface in Phase 7 creates unnecessary churn if Phase 9 changes the signature.
   - Recommendation: Add write() now. The signature `Future<void> write(String key, DynamicValue value)` mirrors StateMan.write() exactly. Adding it later means reopening the adapter, the interface, M2400 adapter, and all test mocks. Better to do it once.

2. **Factory function: include or defer?**
   - What we know: `ModbusDeviceConfig` doesn't exist yet (Phase 8 INTG-06 creates it). `createM2400DeviceClients()` takes `List<M2400Config>`.
   - What's unclear: Exact shape of ModbusDeviceConfig.
   - Recommendation: Include a minimal factory that takes the data the adapter needs (host/port/unitId/specs/alias) without depending on the Phase 8 config class. Phase 8 can add proper config-to-adapter wiring.

3. **Lazy vs eager subscription?**
   - What we know: M2400 subscribes lazily (on demand via DeviceClient.subscribe()). ModbusClientWrapper.subscribe() creates poll groups and starts polling.
   - Recommendation: Lazy subscription (same as M2400). Adapter's subscribe() calls wrapper.subscribe() on first request per key. This is consistent with M2400 pattern and avoids polling registers nobody is watching.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | package:test v1.25.0 |
| Config file | none (standard dart test runner) |
| Quick run command | `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart` |
| Full suite command | `cd packages/tfc_dart && dart test test/core/` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INTG-01 | subscribableKeys returns spec keys | unit | `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart -x` | Wave 0 |
| INTG-01 | canSubscribe returns true for spec keys | unit | same file | Wave 0 |
| INTG-01 | canSubscribe returns false for unknown keys | unit | same file | Wave 0 |
| INTG-01 | subscribe returns DynamicValue stream with correct typeId | unit | same file | Wave 0 |
| INTG-01 | read returns DynamicValue with correct typeId or null | unit | same file | Wave 0 |
| INTG-01 | connectionStatus delegates to wrapper | unit | same file | Wave 0 |
| INTG-01 | connectionStream delegates to wrapper | unit | same file | Wave 0 |
| INTG-01 | connect delegates to wrapper | unit | same file | Wave 0 |
| INTG-01 | dispose delegates to wrapper | unit | same file | Wave 0 |
| INTG-01 | write translates DynamicValue to Object? and delegates | unit | same file | Wave 0 |
| INTG-01 | write throws for unknown key | unit | same file | Wave 0 |
| TEST-04 | All above tests pass (contract completeness) | unit | same file | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd packages/tfc_dart && dart test test/core/modbus_device_client_test.dart`
- **Per wave merge:** `cd packages/tfc_dart && dart test test/core/`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `packages/tfc_dart/test/core/modbus_device_client_test.dart` -- covers INTG-01, TEST-04
- [ ] No framework install needed -- `package:test` already in dev_dependencies
- [ ] MockModbusClient already exists in `modbus_client_wrapper_test.dart` -- can be extracted or duplicated

## Sources

### Primary (HIGH confidence)
- `packages/tfc_dart/lib/core/state_man.dart:531-625` -- DeviceClient interface, M2400DeviceClientAdapter, createM2400DeviceClients factory
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` -- Full ModbusClientWrapper API (subscribe, read, write, connectionStream)
- `~/.pub-cache/git/open62541_dart-33ed12b.../lib/src/dynamic_value.dart:57-118` -- DynamicValue class definition
- `~/.pub-cache/git/open62541_dart-33ed12b.../lib/src/node_id.dart:52-108` -- NodeId static type getters (boolean, int16, uint16, etc.)
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart:11-86` -- MockModbusClient and createWrapperWithMock patterns
- `packages/tfc_dart/test/core/device_client_routing_test.dart` -- MockDeviceClient and DeviceClient contract test patterns

### Secondary (MEDIUM confidence)
- `.planning/phases/07-deviceclient-adapter/07-CONTEXT.md` -- Phase context with user decisions and code insights
- `.planning/REQUIREMENTS.md` -- INTG-01 and TEST-04 requirement definitions

### Tertiary (LOW confidence)
None -- all findings verified against source code.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries already in use, no new dependencies
- Architecture: HIGH -- direct pattern parity with M2400DeviceClientAdapter (verified line-by-line)
- Pitfalls: HIGH -- derived from concrete Phase 5 decisions and observed code behavior
- DynamicValue translation: HIGH -- verified NodeId static getters match ModbusDataType enum 1:1

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable -- internal adapter pattern, no external dependencies changing)
