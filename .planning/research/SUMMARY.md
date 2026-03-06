# Project Research Summary

**Project:** TFC-HMI Modbus TCP Integration
**Domain:** Industrial HMI -- Modbus TCP client integration into existing multi-protocol Flutter application
**Researched:** 2026-03-06
**Confidence:** HIGH

## Executive Summary

TFC-HMI needs to add Modbus TCP as a third protocol alongside OPC UA and M2400. The codebase already has a well-defined integration pattern (DeviceClient adapter) and 3300 lines of prior Modbus work on the modbus-test branch. The Dart Modbus ecosystem has one clear winner -- cabbi's `modbus_client` + `modbus_client_tcp` packages -- and the project already uses a centroid-is fork of the TCP package with keepalive support. The stack decision is settled; the work is fixing bugs in the fork and wiring the adapter chain correctly.

The recommended approach is dependency-first: fix the TCP transport bugs (frame length off-by-6, no TCP_NODELAY, single-response bottleneck) before building any integration code on top. The prior modbus-test branch failed because it bypassed the DeviceClient abstraction and broke OPC UA -- the architecture research confirms this must not happen again. The correct chain is `modbus_client_tcp` (transport) -> `ModbusClientWrapper` (lifecycle/polling) -> `ModbusDeviceClientAdapter` (DeviceClient interface) -> `StateMan` (protocol-agnostic routing).

The primary risks are: (1) TCP half-open connection blindness causing operators to see stale data as live -- the same problem already hit OPC UA and requires keepalive with short intervals, (2) building integration code on unfixed transport bugs that cause subtle data corruption under load, and (3) breaking existing OPC UA/M2400 deployments with config schema changes. All three have clear mitigations documented in the research.

## Key Findings

### Recommended Stack

The Dart Modbus ecosystem is small but adequate, with `modbus_client` (v1.4.4, verified publisher, 1050 weekly downloads) as the only serious option. The base package handles protocol framing, element types, and function codes well. The TCP transport (`modbus_client_tcp`) requires a fork -- upstream lacks keepalive, TCP_NODELAY, and concurrent request support, and has a frame length validation bug. The centroid-is fork on the `add-keepalive` branch is the starting point but needs additional fixes.

**Core technologies:**
- `modbus_client` v1.4.4 (pub.dev): Modbus protocol types and function codes -- best-in-class for Dart, rich type system, no fork needed unless FC15 bug requires it
- `modbus_client_tcp` (centroid-is fork, add-keepalive branch): TCP transport with keepalive -- fork required for keepalive, TCP_NODELAY, frame length fix, concurrent request support
- Existing project stack (rxdart, drift, json_serializable): Supporting infrastructure -- already in use, Modbus follows same patterns

**Known bugs to fix in dependencies:**
- modbus_client_tcp: Frame length check off by 6 bytes (HIGH severity)
- modbus_client_tcp: Single `_currentResponse` blocks concurrent requests (HIGH severity)
- modbus_client_tcp: No TCP_NODELAY adds 200ms Nagle latency (MEDIUM severity)
- modbus_client: FC15 quantity bug for 16+ coils (HIGH severity, may need fork)
- MSocket: No Windows keepalive constants (MEDIUM severity, affects MSIX builds)

### Expected Features

**Must have (table stakes):**
- Read holding/input registers (FC03/FC04) -- core Modbus operations
- Read coils/discrete inputs (FC01/FC02) -- digital I/O status
- Write single register/coil (FC06/FC05) -- basic control
- Write multiple registers (FC16) -- batch setpoint updates
- Auto-reconnect with backoff on connection loss
- Connection status indicator per server
- Configurable poll intervals via poll groups
- Multiple Modbus server support
- Standard data type interpretation (int16/32, uint16/32, float32/64)

**Should have (differentiators):**
- Concurrent request pipelining via transaction IDs -- faster multi-group polling
- TCP keepalive with fast dead-connection detection (~11s) -- industrial reliability
- Register grouping for batch reads -- reduced network traffic
- Cross-platform keepalive (Linux + macOS + Windows)
- Unified protocol switching in key config UI

**Defer (v2+):**
- FC15 fix for 16+ coils (workaround: use individual FC05 writes)
- Register grouping optimization (individual reads work correctly)
- Concurrent request pipelining (serialized requests work, just slower)

### Architecture Approach

The architecture is dictated by the existing codebase. Modbus must follow the M2400 adapter pattern: a protocol-specific wrapper manages connections and polling, an adapter implements the DeviceClient interface, and StateMan routes operations polymorphically without knowing anything about Modbus. The modbus-test branch's failure to follow this pattern (it added a parallel `modbusClients` list to StateMan) is a cautionary tale that must not be repeated.

**Major components:**
1. `modbus_client_tcp` (fork) -- TCP transport: MBAP framing, socket, keepalive, transaction IDs
2. `ModbusClientWrapper` -- Connection lifecycle, poll group timers, read/write ops, DynamicValue conversion
3. `ModbusDeviceClientAdapter` -- Implements DeviceClient interface, maps subscribe/read/write to wrapper
4. `ModbusConfig` / `ModbusNodeConfig` -- Server connection params and per-key register configuration (JSON serializable)
5. UI integration -- server_config.dart (add/remove servers), key_repository.dart (assign Modbus addresses to keys)

### Critical Pitfalls

1. **Bypassing DeviceClient abstraction** -- The old modbus-test branch did this and broke OPC UA. Follow the M2400 adapter pattern exactly. If any StateMan method has `if (protocol == modbus)` branches, the design is wrong.
2. **Building on unfixed transport bugs** -- Frame length errors and missing TCP_NODELAY cause subtle data corruption and latency. Fix the fork first, test with a Modbus simulator, then build the wrapper.
3. **TCP half-open connection blindness** -- Same problem that hit OPC UA (documented in MEMORY.md). Configure SO_KEEPALIVE with 5s idle, 2s interval, 3 probes. Operators must never see "connected" when the cable is pulled.
4. **Config backward incompatibility** -- Adding Modbus fields to config.json must not break existing deployments. Use `defaultValue: []` for server lists, nullable types for node configs, and test with production config files.
5. **Endianness mismatches** -- Different PLCs use different byte ordering for 32/64-bit values. Expose per-server endianness config, default to big-endian (Modbus standard).

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: TCP Transport Fixes

**Rationale:** Everything depends on a reliable transport layer. Building integration code on buggy TCP handling guarantees subtle failures that are extremely hard to diagnose later. This is the foundation.
**Delivers:** A production-quality modbus_client_tcp fork with all known bugs fixed and regression tests for all 8 function codes (FC01-FC06, FC15, FC16).
**Addresses:** Frame length off-by-6, TCP_NODELAY, length field validation, keepalive value verification
**Avoids:** Pitfall 2 (building on unfixed bugs), Pitfall 3 (half-open connections)

### Phase 2: ModbusClientWrapper + DeviceClient Adapter

**Rationale:** With transport fixed, build the integration layer. The wrapper handles connection lifecycle and polling; the adapter bridges to StateMan. These are tightly coupled and should ship together.
**Delivers:** Modbus reading/writing through the DeviceClient interface, auto-reconnect, poll group timers, DynamicValue conversion.
**Addresses:** All table-stakes read/write features (FC01-FC06, FC16), auto-reconnect, connection status, poll intervals
**Avoids:** Pitfall 1 (bypassing DeviceClient abstraction), Anti-Pattern 3 (polling in UI layer)

### Phase 3: Config Serialization + StateMan Integration

**Rationale:** The adapter exists but needs config infrastructure to be instantiated at runtime. ModbusConfig and ModbusNodeConfig need JSON round-tripping, and StateMan needs to create ModbusDeviceClientAdapter instances from config.
**Delivers:** Persistent Modbus server configuration, per-key Modbus node mapping, backward-compatible config.json schema.
**Addresses:** Multiple server support, configurable poll groups, data type configuration, endianness per server
**Avoids:** Pitfall 4 (config backward incompatibility)

### Phase 4: UI Integration

**Rationale:** Backend is complete; wire it to the UI. Server config page needs Modbus server add/edit/delete. Key repository needs Modbus register assignment fields.
**Delivers:** Operators can configure Modbus servers and assign register addresses to display keys through the UI.
**Addresses:** Server config UI, key config UI, unified protocol switching, connection status badges
**Avoids:** Modbus-specific UI leaking into protocol-agnostic components

### Phase 5: FC15 Fix + Performance Optimizations

**Rationale:** These are enhancements, not blockers. FC15 has a workaround (individual FC05 writes). Concurrent pipelining and register grouping are performance optimizations for scale.
**Delivers:** FC15 for 16+ coils, transaction ID pipelining, register batch reads, group write support.
**Addresses:** Differentiator features (concurrent requests, register grouping)

### Phase 6: Windows Keepalive (Cross-Platform)

**Rationale:** Independent of Modbus integration. Benefits all protocols (OPC UA, M2400, Modbus). Can be done in parallel or after Modbus ships.
**Delivers:** SO_KEEPALIVE with Windows socket option constants in MSocket. Enables MSIX builds to detect dead connections.
**Addresses:** Cross-platform keepalive differentiator

### Phase Ordering Rationale

- **Phases 1-4 are strictly sequential** -- each depends on the output of the previous. Transport must be fixed before the wrapper, the wrapper must exist before config can instantiate it, and config must work before the UI can drive it.
- **Phase 5 is deferrable** -- all features it addresses have workarounds. It should be planned but can be pushed to v2 if timeline is tight.
- **Phase 6 is independent** -- it touches MSocket, not Modbus code. It can be parallelized with any phase or deferred entirely if Windows deployment is not imminent.
- **The dependency chain from FEATURES.md confirms this order:** `modbus_client_tcp bug fixes -> ModbusClientWrapper -> ModbusDeviceClientAdapter -> StateMan integration -> UI`

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1 (TCP Transport Fixes):** The frame length bug and concurrent request redesign require reading the modbus_client_tcp fork source carefully. The Python Modbus simulator from the modbus-test branch should be used for regression testing.
- **Phase 3 (Config Serialization):** Need to verify backward compatibility with actual production config.json files from deployed systems.
- **Phase 5 (FC15 Fix):** Need to determine whether the FC15 bug is a real library defect or a usage error (test with ModbusCoil first, as maintainer suggested in issue #19).

Phases with standard patterns (skip research-phase):
- **Phase 2 (Wrapper + Adapter):** The M2400 adapter pattern is thoroughly documented in the codebase and the modbus-test branch has 325 lines of ModbusClientWrapper code to reference.
- **Phase 4 (UI Integration):** server_config.dart already handles OPC UA servers. Adding Modbus follows the same pattern.
- **Phase 6 (Windows Keepalive):** MSocket already has macOS/Linux keepalive. Windows constants are known (SIO_KEEPALIVE_VALS=3, TCP_KEEPIDLE=17, TCP_KEEPINTVL=16).

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Only one viable Dart Modbus library family. Fork already chosen. No decision ambiguity. |
| Features | HIGH | Modbus is a 45-year-old protocol. Table stakes are well-defined. Differentiators come from existing codebase patterns. |
| Architecture | HIGH | Architecture is dictated by existing codebase (DeviceClient pattern). Not a design decision -- it is a conformance requirement. |
| Pitfalls | HIGH | Three of five pitfalls are from direct project experience (OPC UA half-open, modbus-test branch failure, config breakage). Real-world, not theoretical. |

**Overall confidence:** HIGH

### Gaps to Address

- **FC15 bug nature:** Is it a real library defect or usage error? Test with ModbusCoil before deciding whether to fork modbus_client. This determines whether Phase 5 includes a second fork.
- **Concurrent request design:** The transaction ID map replacement for `_currentResponse` needs design work. How does it interact with the existing lock? Does it require API changes to modbus_client?
- **Production config files:** Need actual config.json and keymappings.json from deployed systems to validate backward compatibility before Phase 3.
- **Modbus-test branch reuse:** 3300 lines exist but violated the DeviceClient pattern. How much can be salvaged vs. rewritten? This affects Phase 2 effort estimates.

## Sources

### Primary (HIGH confidence)
- [modbus_client on pub.dev](https://pub.dev/packages/modbus_client) -- v1.4.4, verified publisher, feature set and type system
- [modbus_client_tcp on pub.dev](https://pub.dev/packages/modbus_client_tcp) -- v1.2.3, upstream TCP transport capabilities
- [cabbi/modbus_client GitHub](https://github.com/cabbi/modbus_client) -- Source code, issues (including FC15 #19)
- [cabbi/modbus_client_tcp GitHub](https://github.com/cabbi/modbus_client_tcp) -- Upstream source, design limitations
- modbus-test branch in tfc-hmi repo -- 3300 lines of existing Modbus integration work
- PROJECT.md -- Requirements, constraints, key decisions
- MEMORY.md -- TCP half-open connection problem from OPC UA experience
- MSocket source (packages/jbtm/lib/src/msocket.dart) -- Keepalive reference implementation

### Secondary (MEDIUM confidence)
- [centroid-is/modbus_client_tcp](https://github.com/centroid-is/modbus_client_tcp) -- Fork with add-keepalive branch (could not fully inspect branch diff)
- [modbus_client changelog](https://pub.dev/packages/modbus_client/changelog) -- v1.4.1 endianness support

### Tertiary (LOW confidence)
- FC15 issue #19 maintainer response -- Suggested ModbusCoil workaround, needs validation by testing

---
*Research completed: 2026-03-06*
*Ready for roadmap: yes*
