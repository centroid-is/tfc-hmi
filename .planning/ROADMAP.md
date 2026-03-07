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
- [ ] **Phase 10: Server Config UI** - Modbus server CRUD, connection status, poll group configuration
- [ ] **Phase 11: Key Repository UI** - Protocol switching, register type/address/data type/poll group configuration per key

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
**Plans**: TBD

Plans:
- [ ] 10-01: TBD

### Phase 11: Key Repository UI
**Goal**: Operators can assign Modbus register addresses to display keys through the key configuration UI
**Depends on**: Phase 10 (server config must exist to select servers)
**Requirements**: UIKY-01, UIKY-02, UIKY-03, UIKY-04, UIKY-05, UIKY-06, TEST-07
**Success Criteria** (what must be TRUE):
  1. User can switch a key's protocol between OPC UA, M2400, and Modbus in the key editor
  2. When Modbus is selected, user can choose a server alias, register type, address, data type, and poll group
  3. Data type selection auto-locks to "bit" when coil or discrete input register type is chosen
  4. Configured Modbus keys display live values from the connected device
**Plans**: TBD

Plans:
- [ ] 11-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10 -> 11
Note: Phases 1, 2, and 3 have no inter-dependencies and could execute in parallel.

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
| 10. Server Config UI | 0/1 | Not started | - |
| 11. Key Repository UI | 0/1 | Not started | - |
