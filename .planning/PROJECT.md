# jbtm

## What This Is

A Dart package that integrates industrial weighing/grading devices into the TFC state management system. It provides a general-purpose TCP socket layer (msocket), protocol implementations starting with M2400/M2200, and UI for configuring device connections and key mappings. The package makes device data accessible as DynamicValue streams through state_man.

## Core Value

Reliable, real-time acquisition of device data into state_man — if the device pushes a record, the system captures it and makes it available as a DynamicValue stream.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] General-purpose TCP socket (msocket) with SO_KEEPALIVE and configurable low timeouts for disconnect detection
- [ ] M2400 ASCII protocol parser — STX/ETX framing, tab-separated key-value records
- [ ] M2400 field enums (FLD_WEIGHT, FLD_STATUS, FLD_DEVID, etc.) and record types (REC_WGT, REC_LUA, REC_INTRO, REC_STAT)
- [ ] DynamicValue binarize/serialize for M2400 protocol (protocol-specific, not OPC UA-specific)
- [ ] Extract binarize from DynamicValue in open62541_dart to allow protocol-dependent serialization
- [ ] M2400 TCP client that connects to device (ports 52211/52212) and receives pushed records
- [ ] Test stub server for M2400 protocol (TDD)
- [ ] Integration with state_man — similar pattern to modbus-test branch (config, client wrapper, subscribe)
- [ ] Device pushes records → state_man emits DynamicValue streams per key
- [ ] Keys use named fields: e.g. `WGT` for full record, `WGT.WEIGHT` for individual field
- [ ] Data acquisition tests using stub server
- [ ] Connection resilience — auto-reconnect, flaky connection handling (test with proxy.dart)
- [ ] UI: Server configuration (host, port, alias) similar to modbus feature branch
- [ ] UI: Key repository with servers picker distinguishing key type
- [ ] UI: Option lists to select REC and FLD when servers picker is M2400
- [ ] UI: CRUD for key mappings

### Out of Scope

- M3000 support (XML protocol) — future phase, will reuse msocket
- Pluto support — future phase, will reuse msocket
- Innova support — future phase, will reuse msocket
- Writing/commanding to device — read/receive only for now

## Context

- **Existing packages**: tfc_dart (core), open62541 (OPC UA), open62541_dart (Dart bindings with DynamicValue)
- **state_man**: Central abstraction managing OPC UA and Modbus connections through ClientWrapper/ModbusClientWrapper pattern. The modbus-test branch shows the integration pattern to follow.
- **DynamicValue**: Currently in open62541_dart with OPC UA-specific binarize via PayloadType. Branch `make-dynamicvalue-more-generic` exists for extracting this.
- **M2400 protocol**: ASCII-based, device pushes records. Format: `STX (REC_TYPE\tFLD1\tVAL1\tFLD2\tVAL2\r\n ETX`. Values are strings that need type-specific parsing (Decimal for weights, int for IDs, percentage for belt usage, etc.).
- **Test infrastructure**: proxy.dart in tfc_dart/test provides TCP proxy for simulating flaky connections.
- **jbtm scaffold**: Empty package already exists at packages/jbtm/ with lib/src/msocket.dart and lib/src/m2400.dart.

## Constraints

- **Open source**: Repository is public — keep naming generic, no vendor-specific commentary
- **TDD**: All features test-first with stub server
- **Package boundary**: jbtm is a separate package under packages/, similar to tfc_dart
- **DynamicValue dependency**: Must modify open62541_dart to decouple binarize before implementing protocol-specific serialization
- **TCP ports**: M2400 devices use 52211 or 52212
- **Device-push model**: M2400 pushes records, no polling needed (unlike Modbus)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Separate jbtm package | Keep device protocols isolated from core tfc_dart | — Pending |
| Extract binarize from DynamicValue | Allow protocol-specific serialization (M2400 ASCII, M3000 XML, etc.) | — Pending |
| msocket as reusable TCP layer | Future protocols (pluto, m3000, innova) will share socket infrastructure | — Pending |
| Named keys (WGT.WEIGHT not 3.1) | Human-readable, consistent with how fields are referenced | — Pending |
| Device-push model (no polling) | M2400 sends records as events occur, simpler than Modbus polling | — Pending |
| Stub server for TDD | Enables reliable testing without physical hardware | — Pending |

---
*Last updated: 2026-03-04 after initialization*
