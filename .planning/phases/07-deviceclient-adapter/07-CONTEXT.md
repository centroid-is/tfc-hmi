# Phase 7: DeviceClient Adapter - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Wrap ModbusClientWrapper in a DeviceClient interface so StateMan can use Modbus devices through the same polymorphic pattern as M2400. The adapter translates between DeviceClient method signatures (key-based, DynamicValue) and ModbusClientWrapper operations (spec-based, Object?). Connection lifecycle, polling, reading, and writing are already implemented in Phases 4-6. StateMan routing wiring is Phase 9.

</domain>

<decisions>
## Implementation Decisions

### Key naming scheme
- Claude's discretion on key format -- choose based on how keymappings.json and StateMan already route keys
- Claude's discretion on one-adapter-per-device (matching M2400 pattern) vs single adapter for all devices
- Claude's discretion on canSubscribe() routing strategy (registry from config vs prefix-based)
- Claude's discretion on lazy vs eager subscription (when to call wrapper.subscribe())

### Write on DeviceClient
- Claude's discretion on whether to add write() to the abstract DeviceClient interface now (Phase 7) or defer to Phase 9
- Claude's discretion on M2400 adapter write stub strategy (UnsupportedError vs default impl on interface)
- Claude's discretion on key-to-spec translation for writes (adapter holds map vs wrapper adds key-based write)

### DynamicValue translation
- Claude's discretion on Object? to DynamicValue mapping strategy (derive typeId from register spec vs infer from runtime type)
- Claude's discretion on write-direction validation (validate DynamicValue.typeId matches spec vs pass through)
- Claude's discretion on quality/timestamp fields (value+typeId only vs connection-based quality)

### Register configuration
- Claude's discretion on how adapter receives register config (constructor injection vs dynamic registration)
- Claude's discretion on server alias (include for M2400 parity vs defer)
- Claude's discretion on createModbusDeviceClients() factory (include now for pattern parity vs defer to Phase 9 INTG-08)
- Claude's discretion on file location (state_man.dart vs separate file)

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

</decisions>

<specifics>
## Specific Ideas

- M2400DeviceClientAdapter (state_man.dart:565-613) is the direct reference pattern -- follow its structural approach
- DeviceClient interface (state_man.dart:531-558): subscribableKeys, canSubscribe, subscribe, read, connectionStatus, connectionStream, connect, dispose
- M2400 uses static `_validKeys = {'BATCH', 'STAT', 'INTRO', 'LUA'}` -- Modbus keys are dynamic (user-configured)
- M2400 adapter has `_mapStatus()` for jbtm.ConnectionStatus -> state_man.ConnectionStatus -- Modbus wrapper already uses state_man's ConnectionStatus enum directly (no mapping needed)
- createM2400DeviceClients() factory (state_man.dart:620-625) shows the config-to-adapter factory pattern
- Phase 6 wrapper has spec-based write: `write(ModbusRegisterSpec, Object?)` and `writeMultiple(ModbusRegisterSpec, Uint8List, {int? quantity})`
- Phase 5 wrapper has key-based subscribe: `subscribe(ModbusRegisterSpec)` returns `Stream<Object?>` and `read(String key)` returns `Object?`

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DeviceClient` abstract class (`state_man.dart:531-558`): Interface to implement
- `M2400DeviceClientAdapter` (`state_man.dart:565-613`): Reference pattern for structural parity
- `ModbusClientWrapper` (`packages/tfc_dart/lib/core/modbus_client_wrapper.dart`): Underlying wrapper with connect/subscribe/read/write
- `DynamicValue` (`state_man.dart`): Value wrapper with value + typeId for protocol-agnostic value passing
- `ConnectionStatus` enum: Used by both StateMan and ModbusClientWrapper (no mapping needed unlike M2400)
- `createM2400DeviceClients()` (`state_man.dart:620-625`): Factory pattern reference

### Established Patterns
- One adapter per device instance (M2400 pattern: one wrapper -> one adapter)
- Static `subscribableKeys` set for key routing
- `canSubscribe()` checks root key from dot-notation paths
- `subscribe()` delegates directly to wrapper
- `read()` delegates to wrapper's lastValue
- Connection status mapped from wrapper's stream
- Factory function creates adapter list from config list

### Integration Points
- `StateMan.deviceClients: List<DeviceClient>` -- adapter instances injected here (Phase 9)
- `StateMan.subscribe()` checks deviceClients first, falls through to OPC UA
- `StateMan.write()` currently OPC UA only -- needs DeviceClient routing (Phase 9)
- `data_acquisition_isolate` -- factory function wired here (Phase 9, INTG-08)

</code_context>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 07-deviceclient-adapter*
*Context gathered: 2026-03-06*
