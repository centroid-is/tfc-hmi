# Roadmap: Modbus TCP Integration for TFC-HMI

## Overview

This roadmap delivers Modbus TCP as a third protocol in TFC-HMI alongside OPC UA and M2400. The work flows dependency-first: fix upstream library bugs that would undermine everything built on top, then build the wrapper and adapter layers following the proven DeviceClient pattern, wire config and StateMan integration, and finally add UI for operators to configure Modbus servers and keys. Every phase that adds code follows TDD -- tests written before implementation.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: TCP Transport Fixes** - Fix frame parsing, concurrent requests, validation, and socket options in modbus_client_tcp fork
- [x] **Phase 2: FC15 Coil Write Fix** - Fix Write Multiple Coils quantity bug for 16+ coils in modbus_client fork (completed 2026-03-06)
- [x] **Phase 3: Windows Keepalive** - Add SO_KEEPALIVE with Windows socket constants to MSocket (completed 2026-03-06)
- [ ] **Phase 4: ModbusClientWrapper -- Connection** - Connection lifecycle, auto-reconnect, status streaming, multi-device support
- [ ] **Phase 5: ModbusClientWrapper -- Reading** - Poll group timers, all register type reads, data type interpretation, batch reads
- [x] **Phase 6: ModbusClientWrapper -- Writing** - All write function codes, read-only rejection, multi-coil/register writes (completed 2026-03-06)
- [ ] **Phase 7: DeviceClient Adapter** - ModbusDeviceClientAdapter implementing DeviceClient interface
- [ ] **Phase 8: Config Serialization** - ModbusConfig and ModbusNodeConfig with backward-compatible JSON round-tripping
- [ ] **Phase 9: StateMan Integration** - Wire Modbus into subscribe, read, readMany, write and data_acquisition_isolate
- [x] **Phase 10: Server Config UI** - Modbus server CRUD, connection status, poll group configuration (completed 2026-03-07)
- [x] **Phase 11: Key Repository UI** - Protocol switching, register type/address/data type/poll group configuration per key (completed 2026-03-07)

## Phase Details

### Phase 1: TCP Transport Fixes
**Goal**: The modbus_client_tcp fork correctly parses all Modbus TCP frames, supports concurrent requests, validates responses, and communicates with low latency
**Depends on**: Nothing (first phase)
**Requirements**: TCPFIX-01, TCPFIX-02, TCPFIX-03, TCPFIX-04, TCPFIX-05, TEST-01
**Success Criteria** (what must be TRUE):
  1. Modbus TCP responses with payloads of all sizes (1 byte to 256 bytes) parse correctly without frame length errors
  2. Multiple in-flight requests to the same device resolve to their correct responses via transaction ID matching
  3. Malformed responses with invalid length fields (0 or >256) are rejected without crashing the client
  4. TCP_NODELAY is active on connections, eliminating Nagle algorithm latency
  5. Keepalive probes match MSocket values (5s idle, 2s interval, 3 probes) on macOS and Linux
**Plans:** 2 plans

Plans:
- [ ] 01-01-PLAN.md -- Fork into project, test infrastructure, fix frame parsing + validation + TCP_NODELAY + keepalive (TDD)
- [ ] 01-02-PLAN.md -- Add concurrent request support via transaction ID map (TDD)

### Phase 2: FC15 Coil Write Fix
**Goal**: Writing 16 or more coils in a single FC15 request reports the correct quantity in the response
**Depends on**: Nothing (independent library)
**Requirements**: LIBFIX-01, TEST-02
**Success Criteria** (what must be TRUE):
  1. FC15 (Write Multiple Coils) correctly encodes and verifies quantity for 16, 17, 32, and 64 coils
  2. Regression test confirms FC15 works for 1-15 coils (existing behavior preserved)
**Plans:** 1/1 plans complete

Plans:
- [ ] 02-01-PLAN.md -- Fork modbus_client, fix FC15 quantity bug with TDD (red/green)

### Phase 3: Windows Keepalive
**Goal**: MSocket detects dead TCP connections on Windows within ~11 seconds, matching macOS/Linux behavior
**Depends on**: Nothing (independent of Modbus)
**Requirements**: CONN-04
**Success Criteria** (what must be TRUE):
  1. MSocket sets SO_KEEPALIVE with Windows-specific constants (SIO_KEEPALIVE_VALS=3, TCP_KEEPIDLE=17, TCP_KEEPINTVL=16) on Platform.isWindows
  2. Dead connection detection time is consistent across macOS, Linux, and Windows (~11 seconds with 5s idle, 2s interval, 3 probes)
**Plans**: TBD

Plans:
- [ ] 03-01: TBD

### Phase 4: ModbusClientWrapper -- Connection
**Goal**: The application can establish, monitor, and automatically recover Modbus TCP connections to multiple devices
**Depends on**: Phase 1 (transport must be reliable)
**Requirements**: CONN-01, CONN-02, CONN-03, CONN-05, TEST-03
**Success Criteria** (what must be TRUE):
  1. ModbusClientWrapper connects to a Modbus device given host, port, and unit ID
  2. Connection status (connected, connecting, disconnected) streams via BehaviorSubject observable by any subscriber
  3. After connection loss, wrapper automatically reconnects with exponential backoff without manual intervention
  4. Multiple ModbusClientWrapper instances operate independently against different devices without interference
**Plans:** 1 plan

Plans:
- [ ] 04-01-PLAN.md -- ModbusClientWrapper connection lifecycle with TDD (red/green)

### Phase 5: ModbusClientWrapper -- Reading
**Goal**: All four Modbus register types can be read with configurable polling and correct data type interpretation
**Depends on**: Phase 4 (connection must work)
**Requirements**: READ-01, READ-02, READ-03, READ-04, READ-05, READ-06, READ-07
**Success Criteria** (what must be TRUE):
  1. Coils (FC01) and discrete inputs (FC02) return boolean values through the wrapper
  2. Holding registers (FC03) and input registers (FC04) return values interpreted as the configured data type (int16, uint16, int32, uint32, float32, int64, uint64, float64)
  3. Poll groups fire at their configured intervals and deliver updated values to BehaviorSubject streams
  4. Contiguous registers in the same poll group are coalesced into single batch read requests
**Plans:** 2 plans

Plans:
- [ ] 05-01-PLAN.md -- Poll groups, register reads for all types/data types with TDD (red/green)
- [ ] 05-02-PLAN.md -- Batch coalescing for contiguous same-type registers with TDD (red/green)

### Phase 6: ModbusClientWrapper -- Writing
**Goal**: The application can write values to coils and holding registers, with clear rejection of writes to read-only types
**Depends on**: Phase 5 (read infrastructure provides data type handling)
**Requirements**: WRIT-01, WRIT-02, WRIT-03, WRIT-04, WRIT-05
**Success Criteria** (what must be TRUE):
  1. Single coil (FC05) and single holding register (FC06) writes succeed through the wrapper
  2. Multiple coils (FC15) and multiple holding registers (FC16) writes succeed through the wrapper
  3. Attempting to write to input registers or discrete inputs returns a clear error (not a silent failure or crash)
**Plans:** 1/1 plans complete

Plans:
- [ ] 06-01-PLAN.md -- TDD write operations (write, writeMultiple) with SCADA-safe error handling

### Phase 7: DeviceClient Adapter
**Goal**: Modbus is accessible through the same DeviceClient interface as M2400, enabling polymorphic protocol handling
**Depends on**: Phase 6 (wrapper must support all read/write operations)
**Requirements**: INTG-01, TEST-04
**Success Criteria** (what must be TRUE):
  1. ModbusDeviceClientAdapter passes all DeviceClient interface contract tests (subscribe, read, write, connectionStream)
  2. Adapter correctly translates between DeviceClient method signatures and ModbusClientWrapper operations
  3. Adapter follows the same structural pattern as M2400DeviceClientAdapter (verifiable by code comparison)
**Plans:** 1 plan

Plans:
- [ ] 07-01-PLAN.md -- TDD ModbusDeviceClientAdapter implementing DeviceClient with Object?-to-DynamicValue translation and write() interface addition

### Phase 8: Config Serialization
**Goal**: Modbus server and node configurations persist through JSON serialization without breaking existing config files
**Depends on**: Phase 7 (adapter exists to be configured)
**Requirements**: INTG-06, INTG-07, TEST-06
**Success Criteria** (what must be TRUE):
  1. ModbusConfig (host, port, unitId, alias, pollGroups) round-trips through JSON without data loss
  2. ModbusNodeConfig (serverAlias, registerType, address, dataType, pollGroup) round-trips through JSON without data loss
  3. Existing config.json and keymappings.json files without Modbus fields load successfully (defaultValue: [] for server list, null for node config)
**Plans:** 1 plan

Plans:
- [ ] 08-01-PLAN.md -- TDD ModbusConfig/ModbusNodeConfig with backward-compatible JSON serialization (red/green)

### Phase 9: StateMan Integration
**Goal**: Modbus keys work transparently through StateMan.subscribe(), read(), readMany(), and write() alongside OPC UA and M2400 keys
**Depends on**: Phase 8 (config must drive adapter creation)
**Requirements**: INTG-02, INTG-03, INTG-04, INTG-05, INTG-08, TEST-05
**Success Criteria** (what must be TRUE):
  1. StateMan.subscribe() returns a polling stream for a Modbus key that updates at the configured poll interval
  2. StateMan.read() and readMany() return current cached values for Modbus keys
  3. StateMan.write() routes to the correct Modbus device and register for Modbus keys
  4. OPC UA and M2400 keys continue working identically when Modbus keys are present in the same config
  5. createModbusDeviceClients factory instantiates adapters from config and is wired into data_acquisition_isolate
**Plans:** 2 plans

Plans:
- [ ] 09-01-PLAN.md -- TDD Modbus routing in StateMan (subscribe/read/readMany/write) and buildSpecsFromKeyMappings helper
- [ ] 09-02-PLAN.md -- Wire Modbus into data_acquisition_isolate, main.dart, and Flutter UI provider

### Phase 10: Server Config UI
**Goal**: Operators can add, edit, remove, and monitor Modbus TCP servers through the settings UI
**Depends on**: Phase 9 (backend must be integrated for connection status)
**Requirements**: UISV-01, UISV-02, UISV-03, UISV-04, UISV-05, TEST-08
**Success Criteria** (what must be TRUE):
  1. User can add a new Modbus server by entering host, port, unit ID, and alias in the server config page
  2. User can edit and delete existing Modbus server entries
  3. Each Modbus server shows live connection status (connected/connecting/disconnected indicator)
  4. User can configure named poll groups with intervals per server
**Plans:** 2/2 plans complete

Plans:
- [ ] 10-01-PLAN.md -- TDD Modbus server section CRUD + connection status (clone JBTM pattern with unitId field)
- [ ] 10-02-PLAN.md -- TDD poll group expandable section in Modbus server card + visual verification

### Phase 11: Key Repository UI
**Goal**: Operators can assign Modbus register addresses to display keys through the key configuration UI
**Depends on**: Phase 10 (server config must exist to select servers)
**Requirements**: UIKY-01, UIKY-02, UIKY-03, UIKY-04, UIKY-05, UIKY-06, TEST-07
**Success Criteria** (what must be TRUE):
  1. User can switch a key's protocol between OPC UA, M2400, and Modbus in the key editor
  2. When Modbus is selected, user can choose a server alias, register type, address, data type, and poll group
  3. Data type selection auto-locks to "bit" when coil or discrete input register type is chosen
  4. Configured Modbus keys display live values from the connected device
**Plans:** 2/2 plans complete

Plans:
- [ ] 11-01-PLAN.md -- TDD Modbus config section in key repository (RED tests then GREEN implementation)
- [ ] 11-02-PLAN.md -- Visual verification of Modbus key repository UI

### Phase 12: Windows Keepalive Merge
**Goal:** MSocket detects dead TCP connections on Windows within ~11 seconds, matching macOS/Linux behavior — cherry-pick existing fix from main
**Depends on:** Nothing (independent fix)
**Requirements:** CONN-04
**Gap Closure:** Closes CONN-04 and Phase 3->MSocket integration gap from v1.0 audit
**Success Criteria** (what must be TRUE):
  1. MSocket sets SO_KEEPALIVE with Windows-specific constants on Platform.isWindows
  2. Dead connection detection time is consistent across macOS, Linux, and Windows (~11 seconds)
**Plans:** 1 plan

Plans:
- [ ] 12-01-PLAN.md -- Cherry-pick commit 29833ba from origin/main, verify MSocket Windows keepalive

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10 -> 11 -> 12
Note: Phases 1, 2, and 3 have no inter-dependencies and could execute in parallel.
Phase 12 is a gap closure phase from the v1.0 audit.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. TCP Transport Fixes | 0/2 | Planned | - |
| 2. FC15 Coil Write Fix | 1/1 | Complete   | 2026-03-06 |
| 3. Windows Keepalive | 0/1 | Complete    | 2026-03-06 |
| 4. Wrapper -- Connection | 0/1 | Planned | - |
| 5. Wrapper -- Reading | 0/2 | Not started | - |
| 6. Wrapper -- Writing | 1/1 | Complete   | 2026-03-06 |
| 7. DeviceClient Adapter | 0/1 | Not started | - |
| 8. Config Serialization | 0/1 | Not started | - |
| 9. StateMan Integration | 2/2 | Complete | 2026-03-07 |
| 10. Server Config UI | 2/2 | Complete    | 2026-03-07 |
| 11. Key Repository UI | 2/2 | Complete    | 2026-03-07 |
| 12. Windows Keepalive Merge | 0/1 | Gap Closure | - |

### Phase 13: manual test against a real device

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 12
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 13 to break down)

### Phase 14: UMAS protocol support - Schneider browse via FC90

**Goal:** Schneider PLC variables can be browsed by name via UMAS protocol through a shared protocol-agnostic browse dialog, with UMAS toggle in Modbus server config and Browse button in key repository
**Depends on:** Phase 11 (requires Modbus server config and key repository UI)
**Requirements**: UMAS-01, UMAS-02, UMAS-03, UMAS-04, UMAS-05, UMAS-06, UMAS-07, UMAS-08, TEST-10, TEST-11, TEST-12
**Success Criteria** (what must be TRUE):
  1. UmasClient sends FC90 frames through existing ModbusClientTcp transport and parses UMAS responses
  2. Data dictionary variable names and data types can be read from a Schneider PLC with Data Dictionary enabled
  3. Variable tree is built from flat dictionary data using dot-separated name hierarchy
  4. OPC UA browse dialog is extracted into a protocol-agnostic BrowsePanel widget
  5. OPC UA browse works identically through the new adapter layer (no visual or behavioral changes)
  6. UMAS checkbox appears in Modbus server config card
  7. Browse button appears in key repository Modbus config section when UMAS is enabled
  8. Selecting a UMAS variable populates register address and data type in key config
**Plans:** 3/3 plans complete

Plans:
- [ ] 14-01-PLAN.md -- UMAS protocol client: types, FC90 request/response, data dictionary reading (TDD)
- [ ] 14-02-PLAN.md -- Protocol-agnostic browse panel extraction + OPC UA adapter (TDD)
- [ ] 14-03-PLAN.md -- UMAS integration: config field, server checkbox, browse adapter, key repository Browse button

### Phase 15: Code Review Fixes: security, performance, correctness, and duplication

**Goal:** All identified code review issues (5 correctness bugs, 3 security gaps, 8 duplication instances, 2 performance issues) are resolved across the Modbus integration codebase, with shared UI widgets extracted and dead code removed
**Depends on:** Phase 14
**Requirements**: CORR-01, CORR-02, CORR-03, CORR-04, CORR-05, SEC-01, SEC-02, SEC-03, DUP-01, DUP-02, DUP-03, DUP-04, DUP-05, DUP-06, DUP-07, DUP-08, PERF-01, PERF-02
**Success Criteria** (what must be TRUE):
  1. StateMan.read() and write() throw immediately when key not found (no 17-minute hang)
  2. Config saves are awaited before subsequent reads in all three server config sections
  3. UMAS response parsing rejects oversized variable names and limits total count
  4. Port number validated to 1-65535 range, heartbeat address configurable
  5. ConnectionStatusChip is a single shared widget used by all three server card types
  6. Dead code (createModbusDeviceClients) removed, UMAS domain logic moved to domain layer
  7. UMAS tree node lookup is O(1) via path index
  8. All existing tests pass after all changes
**Plans:** 3/3 plans complete

Plans:
- [ ] 15-01-PLAN.md -- Fix correctness bugs, remove dead code, extract domain utilities, improve performance (non-UI files)
- [ ] 15-02-PLAN.md -- Fix missing await, port validation, heartbeat config, unawaited cleanup (server_config + wrapper)
- [ ] 15-03-PLAN.md -- Extract duplicated UI patterns into shared widgets (server_config deduplication)

### Phase 16: Modbus protocol spec research -- find bugs and missing features

**Goal:** All Modbus protocol compliance gaps identified in the spec audit are fixed (address validation, response byte count checking, unit ID response validation, write quantity limits), unit ID range expanded to 0-255 for TCP, write errors surface detailed exception information, and byte order is configurable per device for multi-register interoperability
**Depends on:** Phase 15
**Requirements**: BUG-01, BUG-02, BUG-03, BUG-05, VAL-03, FEAT-01, FEAT-03
**Success Criteria** (what must be TRUE):
  1. Register addresses are validated to 0-65535 at spec, config, and UI layers
  2. Response byte count is validated against expected size for read responses
  3. Unit ID in MBAP response header is validated against request unit ID
  4. FC15/FC16 write quantity limits are enforced per spec (max 1968 coils, 123 registers)
  5. Unit ID field accepts 0-255 for TCP connections (was 1-247)
  6. Write failure messages include exception code number and human-readable description
  7. Byte order (ABCD/CDAB/BADC/DCBA) is configurable per Modbus server
  8. Endianness from config flows through wrapper to modbus_client element constructors
**Plans:** 3/3 plans complete

Plans:
- [x] 16-01-PLAN.md -- Library-level response validation and write quantity limits (BUG-02, BUG-03, BUG-05)
- [x] 16-02-PLAN.md -- Wrapper/UI address validation, unit ID range, exception detail surfacing (BUG-01, VAL-03, FEAT-03)
- [x] 16-03-PLAN.md -- Byte order configuration per Modbus server (FEAT-01)
