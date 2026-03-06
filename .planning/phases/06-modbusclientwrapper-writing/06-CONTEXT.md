# Phase 6: ModbusClientWrapper -- Writing - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Write capability for `ModbusClientWrapper`: single coil (FC05), single holding register (FC06), multiple coils (FC15), and multiple holding registers (FC16) writes, with clear rejection of writes to read-only types (input registers, discrete inputs). Connection lifecycle, polling, and reading are Phase 4/5. DeviceClient adapter is Phase 7.

</domain>

<decisions>
## Implementation Decisions

### Write API design
- Write anywhere -- no prior subscription required. Supports write-only control outputs (setpoints, commands) that are never polled.
- Claude's discretion on method signature -- align with Phase 7 `DeviceClient.write(key, value)` contract
- Claude's discretion on write-only register registration (explicit `registerWrite()` vs auto-register on first write vs temporary element per call)
- Claude's discretion on value types (raw Dart types vs `Object?` matching read streams vs dynamic)

### Multi-write semantics
- Claude's discretion on API surface (single `write()` handling both vs separate `writeMultiple()`)
- Claude's discretion on auto-detecting FC06 vs FC16 based on data type byte count (e.g., float32 auto-uses FC16)
- Claude's discretion on explicit array writes (writing contiguous coil/register arrays in single transaction)

### Error reporting
- Immediate error when disconnected -- do NOT queue writes. SCADA safety: stale queued values sent after reconnect could be dangerous for control outputs.
- Claude's discretion on failure surface (throw exceptions vs return result code) -- consider alignment with `StateMan.write()` which throws `StateManException`
- Claude's discretion on read-only rejection strategy (early check in wrapper vs catch library's `ModbusException`)

### Write-back behavior
- Claude's discretion on BehaviorSubject update after write (optimistic vs wait-for-poll vs read-after-write)
- Claude's discretion on write-only register observability (no stream vs return confirmation)
- Claude's discretion on write concurrency (serialize behind lock vs leverage Phase 1's transaction ID concurrency)

### Claude's Discretion
- Method signature design (align with DeviceClient.write(key, value))
- Write-only register registration approach
- Value type handling (raw Dart types vs Object? vs dynamic)
- Single vs multi-write API surface
- Auto-detection of FC06 vs FC16 for multi-register data types
- Array write support decision
- Failure surface (throw vs return code)
- Read-only type rejection timing (early wrapper check vs library exception)
- BehaviorSubject update strategy after write
- Write-only register observability
- Write concurrency model

</decisions>

<specifics>
## Specific Ideas

- `ModbusElement.getWriteRequest(dynamic value)` already handles FC05 (coils) and FC06 (holding registers) single writes
- `ModbusElement.getMultipleWriteRequest(Uint8List bytes, {int? quantity})` handles FC15/FC16 multi-writes
- `ModbusElementType.writeSingleFunction` is null for `discreteInput` and `inputRegister` -- library already throws `ModbusException` on write attempts
- `ModbusNumRegister.getWriteRequest()` auto-uses FC16 for multi-register types (int32, float32, etc.) when byteCount > 2
- `client.send(element.getWriteRequest(value))` returns `ModbusResponseCode` -- same pattern as reads
- Phase 2 fixed FC15 quantity bug for 16+ coils -- multi-coil writes now reliable

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ModbusClientWrapper` (`packages/tfc_dart/lib/core/modbus_client_wrapper.dart`): Phase 4/5 connection lifecycle and read infrastructure -- this phase adds write methods
- `ModbusElement.getWriteRequest(value)` (`packages/modbus_client/lib/src/modbus_element.dart:67`): Single write request builder (FC05/FC06)
- `ModbusElement.getMultipleWriteRequest(bytes, quantity)` (`packages/modbus_client/lib/src/modbus_element.dart:100`): Multi-write request builder (FC15/FC16)
- `_createElement(ModbusRegisterSpec)` (`modbus_client_wrapper.dart:542`): Factory already builds correct ModbusElement subclass from spec -- reusable for write-only elements
- `MockModbusClient` (from Phase 4 tests): Factory injection for write testing

### Established Patterns
- `client.send(request)` returns `Future<ModbusResponseCode>` -- same send pattern for reads and writes
- `ModbusResponseCode.requestSucceed` for success checking
- `ModbusElementType` encodes writability: coil and holdingRegister have write functions, discreteInput and inputRegister do not
- `_subscriptions` map keyed by string key -- write-only elements could use same or parallel registry

### Integration Points
- `ModbusClientWrapper._client` exposes connected `ModbusClientTcp` for issuing writes via `client.send()`
- `DeviceClient.write(key, DynamicValue)` (Phase 7) -- wrapper's write API feeds into this adapter
- `StateMan.write(key, DynamicValue)` (Phase 9) -- routes through DeviceClient adapter to wrapper

</code_context>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 06-modbusclientwrapper-writing*
*Context gathered: 2026-03-06*
