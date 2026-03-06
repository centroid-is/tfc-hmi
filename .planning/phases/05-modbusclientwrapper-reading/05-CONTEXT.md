# Phase 5: ModbusClientWrapper -- Reading - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

All four Modbus register types can be read with configurable polling and correct data type interpretation. The wrapper adds poll group timers, register subscription with BehaviorSubject value streams, batch coalescing, and a synchronous read API. Writing is Phase 6, DeviceClient adapter is Phase 7.

</domain>

<decisions>
## Implementation Decisions

### Poll group lifecycle
- Auto-start poll timers when connectionStatus becomes connected, pause on disconnect, resume on reconnect
- No separate start/stop API for polling -- tied to connection lifecycle
- Default poll interval: 1 second when no explicit interval is configured
- Multiple named poll groups per device supported (e.g., 'fast' at 200ms, 'slow' at 5s)
- On disconnect: skip reads silently, resume polling on next reconnect. No catch-up reads. Last-known values remain in BehaviorSubjects until updated.

### Register subscription API
- Structured config object (ModbusRegisterSpec) with fields: registerType, address, dataType, pollGroup
- Dynamic add/remove of registers at runtime while polls are running. Timer picks up changes on next tick.
- Both stream + synchronous read: subscribe() returns Stream, read() returns last-known cached value (BehaviorSubject.valueOrNull pattern)

### Read failure handling
- Keep last-known value in BehaviorSubject on read failure (standard SCADA behavior -- operators expect values to persist until updated)
- Modbus exception responses (illegal address, device busy): log at warning level, skip that register for this poll cycle, continue with remaining registers. Don't crash the poll group for one bad register.
- No consecutive-failure threshold -- poll forever, matching Phase 4's "retry forever" philosophy
- Read timeouts configurable per poll group (fast groups need short timeouts to not block next cycle)

### Batch coalescing strategy
- Automatic coalescing: wrapper detects contiguous same-type registers in the same poll group and groups them into ModbusElementsGroup batch reads. Transparent to subscribers.
- Gap handling: read gaps too -- if registers 100 and 105 are both subscribed, read 100-105 as one batch and discard unused. Standard SCADA practice for small gaps.
- Recalculate batch groups when registers are dynamically added/removed, before the next poll tick
- Auto-split oversized batches that exceed Modbus limits (125 registers / 2000 coils per request)

### Claude's Discretion
- Value type emitted by register streams (DynamicValue vs raw Dart types -- choose based on cleanest layering with Phase 7 adapter)
- Gap threshold for coalescing (whether to cap the gap size for batch reads)
- Internal data structure for tracking subscriptions (Map keying strategy)
- ModbusRegisterSpec exact field names and constructor design
- Poll group naming conventions and validation

</decisions>

<specifics>
## Specific Ideas

- Follow the Collector's `Timer.periodic` pattern for poll timers (fire-and-forget async callback)
- Use `ModbusElementsGroup.getReadRequest()` for batch reads -- it handles address range calculation and per-element value parsing automatically
- The modbus_client library's `ModbusElement.value` already parses data types (int16 through float64, bit) -- no manual byte interpretation needed
- BehaviorSubject per registered key gives both stream and sync read for free (`.stream` and `.valueOrNull`)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ModbusClientWrapper` (`packages/tfc_dart/lib/core/modbus_client_wrapper.dart`): Phase 4 connection lifecycle -- this phase extends it with poll/read capabilities
- `ModbusElementsGroup` (`packages/modbus_client/lib/src/modbus_element_group.dart`): Batch read support for contiguous same-type registers, max 125 registers or 2000 coils per group
- `ModbusInt16Register`, `ModbusUint16Register`, `ModbusFloat32Register`, etc. (`packages/modbus_client/lib/src/element_type/`): Data type interpretation with endianness support
- `ModbusBitElement` (`packages/modbus_client/`): Boolean coil/discrete input reads
- `Collector` (`packages/tfc_dart/lib/core/collector.dart`): Timer.periodic pattern for sample intervals (line 198)

### Established Patterns
- `BehaviorSubject<T>.seeded()` for value streams with replay to new subscribers
- `Timer.periodic(interval, (timer) async { ... })` for fire-and-forget polling (Collector)
- `client.send(element.getReadRequest())` to read a single element, `client.send(group.getReadRequest())` for batch reads
- Factory injection for testability (MockModbusClient from Phase 4)

### Integration Points
- `ModbusClientWrapper.client` exposes the connected `ModbusClientTcp` for issuing reads
- `ModbusClientWrapper.connectionStream` provides connect/disconnect events to trigger poll start/pause
- `DeviceClient.subscribe(key)` returns `Stream<DynamicValue>` -- Phase 7 adapter will wrap this wrapper's streams
- `DeviceClient.read(key)` returns `DynamicValue?` -- Phase 7 adapter will use this wrapper's sync read

</code_context>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 05-modbusclientwrapper-reading*
*Context gathered: 2026-03-06*
