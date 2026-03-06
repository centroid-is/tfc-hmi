# Requirements: Modbus TCP Integration for TFC-HMI

**Defined:** 2026-03-06
**Core Value:** Modbus devices can be read from and written to through the same StateMan interface as OPC UA and M2400, without breaking existing protocol integrations.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Library Fixes (modbus_client_tcp fork)

- [x] **TCPFIX-01**: Frame length check accounts for 6-byte MBAP header (fix off-by-6 bug at line 297)
- [x] **TCPFIX-02**: Concurrent requests supported via transaction ID map (replace single _currentResponse with Map<int, _TcpResponse>)
- [x] **TCPFIX-03**: MBAP length field validated (1-256 range, reject malformed responses)
- [x] **TCPFIX-04**: TCP_NODELAY enabled after socket connect for low-latency communication
- [x] **TCPFIX-05**: Keepalive values match MSocket (5s idle, 2s interval, 3 probes) across all platforms

### Library Fixes (modbus_client fork)

- [x] **LIBFIX-01**: FC15 (Write Multiple Coils) correctly reports quantity for 16+ coils

### Connection

- [x] **CONN-01**: User can connect to a Modbus TCP device by specifying host, port, and unit ID
- [x] **CONN-02**: Connection auto-recovers with exponential backoff after loss (matching MSocket pattern)
- [x] **CONN-03**: Connection status streams to UI (connected, connecting, disconnected)
- [ ] **CONN-04**: TCP keepalive detects dead connections within ~11 seconds on all platforms (macOS, Linux, Windows)
- [x] **CONN-05**: User can connect to multiple independent Modbus devices simultaneously

### Reading

- [ ] **READ-01**: User can read coils (FC01) and see boolean values
- [ ] **READ-02**: User can read discrete inputs (FC02) and see boolean values
- [ ] **READ-03**: User can read holding registers (FC03) with configurable data types
- [ ] **READ-04**: User can read input registers (FC04) with configurable data types
- [ ] **READ-05**: Data types supported: bit, int16, uint16, int32, uint32, float32, int64, uint64, float64
- [ ] **READ-06**: Contiguous registers can be read in a single batch request (register grouping/coalescing)
- [ ] **READ-07**: Poll groups with configurable intervals control how often registers are read

### Writing

- [ ] **WRIT-01**: User can write a single coil (FC05) via StateMan.write()
- [ ] **WRIT-02**: User can write a single holding register (FC06) via StateMan.write()
- [ ] **WRIT-03**: User can write multiple holding registers (FC16) via StateMan.write()
- [ ] **WRIT-04**: User can write multiple coils (FC15) via StateMan.write()
- [ ] **WRIT-05**: Write operations to read-only register types (input registers, discrete inputs) are rejected with clear error

### Integration

- [ ] **INTG-01**: ModbusDeviceClientAdapter implements DeviceClient interface (same pattern as M2400DeviceClientAdapter)
- [ ] **INTG-02**: StateMan.subscribe() returns polling stream for Modbus keys transparently
- [ ] **INTG-03**: StateMan.read() returns current value for Modbus keys
- [ ] **INTG-04**: StateMan.write() routes to Modbus device for Modbus keys
- [ ] **INTG-05**: Modbus keys coexist with OPC UA and M2400 keys without interference
- [ ] **INTG-06**: ModbusConfig stored in StateManConfig with backward-compatible JSON (defaultValue: [])
- [ ] **INTG-07**: ModbusNodeConfig stored in KeyMappingEntry alongside opcuaNode and m2400Node
- [ ] **INTG-08**: createModbusDeviceClients factory wired into data_acquisition_isolate

### UI — Server Configuration

- [ ] **UISV-01**: User can add a Modbus TCP server with host, port, unit ID, and alias
- [ ] **UISV-02**: User can edit existing Modbus server configuration
- [ ] **UISV-03**: User can remove a Modbus server
- [ ] **UISV-04**: User can see live connection status per Modbus server
- [ ] **UISV-05**: User can configure poll groups per server (name + interval in ms)

### Testing (TDD)

- [x] **TEST-01**: modbus_client_tcp fork fixes have unit tests covering frame parsing, concurrent transactions, length validation, and keepalive
- [x] **TEST-02**: modbus_client fork FC15 fix has regression test for 16+ coils
- [x] **TEST-03**: ModbusClientWrapper has unit tests for connection lifecycle, polling, read/write, and reconnect behavior
- [ ] **TEST-04**: ModbusDeviceClientAdapter has unit tests verifying DeviceClient interface contract
- [ ] **TEST-05**: StateMan Modbus routing has integration tests (subscribe, read, readMany, write) alongside OPC UA keys
- [ ] **TEST-06**: ModbusConfig and ModbusNodeConfig have JSON round-trip serialization tests
- [ ] **TEST-07**: Key repository Modbus config UI has widget tests
- [ ] **TEST-08**: Server config Modbus section has widget tests
- [ ] **TEST-09**: Tests written before implementation (TDD — red/green/refactor cycle)

### UI — Key Repository

- [ ] **UIKY-01**: User can switch a key between OPC UA, M2400, and Modbus protocols
- [ ] **UIKY-02**: User can select Modbus server (by alias) for a key
- [ ] **UIKY-03**: User can configure register type (coil, discrete input, holding register, input register)
- [ ] **UIKY-04**: User can set register address
- [ ] **UIKY-05**: User can select data type (auto-locked to bit for coil/discrete input)
- [ ] **UIKY-06**: User can assign key to a poll group

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Protocol

- **ADV-01**: Byte/word order configuration per device (AB CD, CD AB, BA DC, DC BA) for multi-register types
- **ADV-02**: Mask write register (FC22) support
- **ADV-03**: Read/write multiple registers combined (FC23) support
- **ADV-04**: Modbus RTU over serial support

### Advanced UI

- **ADVUI-01**: Register browser / discovery tool to scan address ranges
- **ADVUI-02**: Manual read/write test panel for debugging
- **ADVUI-03**: Poll performance metrics (response time, error rate)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Modbus RTU (serial/RS-485) | No current requirement. TCP only for now. |
| Modbus UDP | Rarely used in practice. TCP provides reliability. |
| Modbus server/slave mode | TFC-HMI is client only. |
| File record operations (FC 0x14/0x15) | Rarely used in HMI context. |
| FFI wrapping of C++ centroid-is/modbus | Dart packages sufficient after fixes. |
| Custom Modbus framing on MSocket | modbus_client_tcp handles framing. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TCPFIX-01 | Phase 1 | Complete |
| TCPFIX-02 | Phase 1 | Complete |
| TCPFIX-03 | Phase 1 | Complete |
| TCPFIX-04 | Phase 1 | Complete |
| TCPFIX-05 | Phase 1 | Complete |
| LIBFIX-01 | Phase 2 | Complete |
| CONN-01 | Phase 4 | Complete |
| CONN-02 | Phase 4 | Complete |
| CONN-03 | Phase 4 | Complete |
| CONN-04 | Phase 3 | Complete |
| CONN-05 | Phase 4 | Complete |
| READ-01 | Phase 5 | Pending |
| READ-02 | Phase 5 | Pending |
| READ-03 | Phase 5 | Pending |
| READ-04 | Phase 5 | Pending |
| READ-05 | Phase 5 | Pending |
| READ-06 | Phase 5 | Pending |
| READ-07 | Phase 5 | Pending |
| WRIT-01 | Phase 6 | Pending |
| WRIT-02 | Phase 6 | Pending |
| WRIT-03 | Phase 6 | Pending |
| WRIT-04 | Phase 6 | Pending |
| WRIT-05 | Phase 6 | Pending |
| INTG-01 | Phase 7 | Pending |
| INTG-02 | Phase 9 | Pending |
| INTG-03 | Phase 9 | Pending |
| INTG-04 | Phase 9 | Pending |
| INTG-05 | Phase 9 | Pending |
| INTG-06 | Phase 8 | Pending |
| INTG-07 | Phase 8 | Pending |
| INTG-08 | Phase 9 | Pending |
| UISV-01 | Phase 10 | Pending |
| UISV-02 | Phase 10 | Pending |
| UISV-03 | Phase 10 | Pending |
| UISV-04 | Phase 10 | Pending |
| UISV-05 | Phase 10 | Pending |
| UIKY-01 | Phase 11 | Pending |
| UIKY-02 | Phase 11 | Pending |
| UIKY-03 | Phase 11 | Pending |
| UIKY-04 | Phase 11 | Pending |
| UIKY-05 | Phase 11 | Pending |
| UIKY-06 | Phase 11 | Pending |
| TEST-01 | Phase 1 | Complete |
| TEST-02 | Phase 2 | Complete |
| TEST-03 | Phase 4 | Complete |
| TEST-04 | Phase 7 | Pending |
| TEST-05 | Phase 9 | Pending |
| TEST-06 | Phase 8 | Pending |
| TEST-07 | Phase 11 | Pending |
| TEST-08 | Phase 10 | Pending |
| TEST-09 | Cross-cutting (all phases) | Pending |

**Coverage:**
- v1 requirements: 51 total
- Mapped to phases: 50 (unique phase assignment)
- Cross-cutting: 1 (TEST-09 -- TDD process applies to all phases)
- Unmapped: 0

---
*Requirements defined: 2026-03-06*
*Last updated: 2026-03-06 after roadmap creation*
