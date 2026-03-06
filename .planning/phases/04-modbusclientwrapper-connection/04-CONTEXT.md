# Phase 4: ModbusClientWrapper -- Connection - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Connection lifecycle, auto-reconnect, status streaming, and multi-device support for Modbus TCP devices. The wrapper wraps `ModbusClientTcp` (forked in `packages/modbus_client_tcp/`) and provides a `BehaviorSubject<ConnectionStatus>` stream. Reading, writing, and DeviceClient adapter are separate phases (5, 6, 7).

</domain>

<decisions>
## Implementation Decisions

### Reconnect & health monitoring
- Claude's discretion on health monitoring approach (TCP keepalive only vs app-level health read)
- Connection status uses existing `ConnectionStatus` enum (connected, connecting, disconnected) — match MSocket and OPC UA
- Claude's discretion on error translation (pass-through vs wrapper-specific exceptions)
- Claude's discretion on disconnect detection (immediate vs quick-probe first)

### Backoff & retry policy
- Match MSocket backoff: 500ms initial, 5s max, immediate reset on successful reconnect
- Retry forever — never give up. HMI should always try to reconnect. Operator removes device if permanently gone.
- Claude's discretion on logging (reconnect attempt logging vs status stream only)

### Package & file structure
- Claude's discretion on file location — choose based on dependency graph and existing conventions
- Phase 4 is wrapper only — DeviceClient adapter is Phase 7, no stub
- Claude's discretion on exports and barrel files — follow existing import patterns
- Claude's discretion on constructor signature (raw params vs config object) — consider Phase 8 config serialization needs

### Connection mode & lifecycle
- Claude's discretion on whether to use ModbusClientTcp's built-in autoConnectAndKeepConnected or manage own connection loop
- Claude's discretion on connect() semantics (fire-and-forget vs await first attempt)
- Provide both disconnect() and dispose() — disconnect() stops reconnect loop but allows later reconnect, dispose() is terminal (closes streams, can't reuse)
- Factory injection for ModbusClientTcp — constructor accepts optional factory for test injection, matching M2400ClientWrapper's socketFactory pattern

### Claude's Discretion
- Health monitoring approach (TCP keepalive vs app-level heartbeat read)
- Error handling strategy (pass-through vs wrapper exceptions)
- Disconnect detection timing (immediate vs probe-first)
- Reconnect logging verbosity
- File location within packages/
- Constructor parameter style (raw vs config object)
- Connection loop management (own loop vs built-in auto-connect)
- connect() return type semantics

</decisions>

<specifics>
## Specific Ideas

- Follow MSocket's `_connectionLoop()` pattern as reference — proven in production for M2400
- M2400ClientWrapper's `socketFactory` injection pattern enables clean TDD with mock transport
- The TCP half-open connection problem (from OPC UA experience) applies here too — ModbusClientTcp's keepalive should handle TCP-level detection, but application-level hangs are a consideration

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MSocket` (`packages/jbtm/lib/src/msocket.dart`): Connection loop, exponential backoff, BehaviorSubject status — reference pattern for wrapper design
- `M2400ClientWrapper` (`packages/jbtm/lib/src/m2400_client_wrapper.dart`): BehaviorSubject<ConnectionStatus>, connect/disconnect/dispose lifecycle, factory injection — direct pattern to follow
- `ModbusClientTcp` (`packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart`): TCP transport with keepalive, connect()/disconnect()/isConnected, connectionMode options
- `modbus_test_server.dart` (`packages/modbus_client_tcp/test/`): Mock TCP server for testing — can be adapted for wrapper tests

### Established Patterns
- `BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.disconnected)` for status streaming
- Dual API: synchronous `connectionStatus` getter + async `connectionStream`
- Factory injection for testability (`socketFactory` in M2400ClientWrapper)
- Exponential backoff: `_backoff = clamp(_backoff * 2, Duration.zero, _maxBackoff)`
- `ConnectionStatus` enum: `connected`, `connecting`, `disconnected` (defined in multiple places — MSocket, state_man.dart)

### Integration Points
- `DeviceClient` interface (`packages/tfc_dart/lib/core/state_man.dart:523-558`): Phase 7 adapter will wrap this wrapper
- `StateMan` constructor accepts `deviceClients: List<DeviceClient>` — wrapper feeds into this via adapter
- `ModbusClient.connect()` returns `Future<bool>`, `disconnect()` returns `Future<void>`
- Keepalive already configured in ModbusClientTcp (5s/2s/3 probes, cross-platform)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-modbusclientwrapper-connection*
*Context gathered: 2026-03-06*
