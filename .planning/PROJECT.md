# Modbus TCP Integration for TFC-HMI

## What This Is

Adding Modbus TCP protocol support to the TFC-HMI Flutter application, enabling read and write communication with Modbus devices (PLCs, sensors, actuators). This extends the existing multi-protocol architecture alongside OPC UA and M2400, using the same DeviceClient adapter pattern. Includes fixing critical bugs in upstream Dart Modbus libraries.

## Core Value

Modbus devices can be read from and written to through the same StateMan interface as OPC UA and M2400, without breaking existing protocol integrations.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Fix modbus_client fork: FC15 (Write Multiple Coils) quantity bug for 16+ coils
- [ ] Fix modbus_client fork: implement group write operations (ModbusWriteGroupRequest)
- [ ] Fix modbus_client_tcp fork: frame length check off by 6 bytes (line 297)
- [ ] Fix modbus_client_tcp fork: support concurrent requests via transaction ID map (replace single _currentResponse)
- [ ] Fix modbus_client_tcp fork: add length field validation (1-256 range)
- [ ] Fix modbus_client_tcp fork: add TCP_NODELAY after connect
- [ ] Fix modbus_client_tcp fork: match MSocket keepalive values (5s idle, 2s interval, 3 probes)
- [ ] Add Windows keepalive support to MSocket in jbtm (Platform.isWindows branch with constants 3, 17, 16)
- [ ] Create ModbusClientWrapper with connection lifecycle, poll group timers, read/write, and subscribe via BehaviorSubject streams
- [ ] Create ModbusDeviceClientAdapter implementing DeviceClient interface (like M2400DeviceClientAdapter)
- [ ] Add ModbusConfig and ModbusNodeConfig to StateManConfig with JSON serialization
- [ ] Integrate Modbus into StateMan.subscribe, read, readMany, write — polymorphic alongside OPC UA and M2400
- [ ] Add createModbusDeviceClients factory and wire into data_acquisition_isolate
- [ ] Add Modbus server CRUD to server_config.dart (host, port, unit ID, server alias, poll groups, connection status)
- [ ] Add Modbus key configuration to key_repository.dart (protocol switching, register type, address, data type, poll group)
- [ ] Support reading coils, discrete inputs, holding registers, and input registers
- [ ] Support writing to coils and holding registers (setpoints and control outputs)
- [ ] Auto-reconnect with exponential backoff on connection loss

### Out of Scope

- Modbus RTU (serial/RS-485) — TCP only for now
- Modbus UDP — not needed
- FFI wrapping of C++ centroid-is/modbus library — Dart packages sufficient after fixes
- Modbus server/slave mode — client only
- File record operations (FC 0x14/0x15) — rarely used in HMI context

## Context

- **Existing architecture**: TFC-HMI uses a `DeviceClient` interface abstraction. M2400 implements this via `M2400DeviceClientAdapter` wrapping `M2400ClientWrapper`. Modbus must follow the same pattern.
- **Old modbus-test branch**: Contains ~3300 lines of work (modbus_client.dart, state_man changes, UI). Broke OPC UA at runtime because it added `modbusClients` as a separate list instead of using the DeviceClient abstraction. Code is reusable but architecture must change.
- **Upstream Dart libraries**: `modbus_client` (pub.dev, v1.4.4) has an open FC15 bug and no group writes. `modbus_client_tcp` (centroid fork, add-keepalive branch) has a frame length parsing bug and no concurrent request support.
- **MSocket (jbtm)**: Battle-tested TCP socket with SO_KEEPALIVE (5s/2s/3) and auto-reconnect. Handles macOS and Linux but not Windows.
- **Reference implementations**: centroid-is/modbus (C++) for protocol correctness, centroid-is/postgresql-dart (add-keepalive-test branch) for cross-platform keepalive pattern.
- **M2400 pattern to follow**: MSocket → M2400ClientWrapper → M2400DeviceClientAdapter → StateMan. Modbus equivalent: modbus_client_tcp → ModbusClientWrapper → ModbusDeviceClientAdapter → StateMan.

## Constraints

- **No OPC UA breakage**: Modbus integration must not change OPC UA or M2400 behavior. Use DeviceClient interface, not separate client lists on StateMan.
- **Tech stack**: Dart/Flutter, modbus_client + modbus_client_tcp (centroid forks), existing StateMan architecture.
- **Cross-platform**: Must work on Linux (Docker deployment), macOS (development), Windows (new MSIX build target — current branch).
- **Backward compatibility**: Existing keymappings.json and config.json without modbus keys must continue working (use defaultValue: [] for modbus config list).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use DeviceClient adapter pattern (not separate modbusClients list) | Old branch broke OPC UA by forking StateMan internals. Adapter pattern is proven with M2400. | — Pending |
| Fix upstream forks rather than replace libraries | modbus_client handles protocol complexity (register types, function codes, data encoding). Replacing it means reimplementing Modbus from scratch. Fixing specific bugs is lower risk. | — Pending |
| Keep modbus_client_tcp for TCP layer (not MSocket) | modbus_client_tcp integrates with modbus_client's send/receive pattern. MSocket is raw TCP — would require reimplementing Modbus framing on top. Fix the fork instead. | — Pending |
| Add Windows keepalive to MSocket | MSocket already handles macOS/Linux. Windows constants known from postgresql-dart fork. Small fix, benefits m2400 too. | — Pending |
| Polling-based data acquisition (not subscription) | Modbus has no native subscription mechanism — must poll. Use configurable poll groups with different intervals per group. | — Pending |

---
*Last updated: 2026-03-06 after initialization*
