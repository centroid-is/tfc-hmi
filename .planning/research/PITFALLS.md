# Domain Pitfalls: Modbus TCP Integration

**Domain:** Industrial HMI -- Modbus TCP client in Dart/Flutter
**Researched:** 2026-03-06

## Critical Pitfalls

Mistakes that cause rewrites or major issues.

### Pitfall 1: Bypassing the DeviceClient Abstraction

**What goes wrong:** Adding Modbus as a separate client list on StateMan instead of going through the DeviceClient adapter pattern. This is exactly what the old modbus-test branch did -- it added `modbusClients` as a parallel list alongside OPC UA clients, which broke OPC UA at runtime.

**Why it happens:** It feels faster to add Modbus-specific code directly to StateMan than to implement the full adapter chain (ModbusClientWrapper -> ModbusDeviceClientAdapter -> DeviceClient -> StateMan).

**Consequences:** StateMan internals fork into protocol-specific branches. Every new feature (subscribe, read, write, reconnect) must be duplicated per protocol. OPC UA regressions from interleaved Modbus code. Unmaintainable.

**Prevention:** Follow the M2400 pattern exactly. ModbusDeviceClientAdapter implements DeviceClient. StateMan only knows about DeviceClient instances.

**Detection:** If any StateMan method has `if (protocol == modbus)` branches, the abstraction has been violated.

### Pitfall 2: Building on Unfixed modbus_client_tcp Bugs

**What goes wrong:** Writing ModbusClientWrapper integration code before fixing the TCP transport bugs (frame length off-by-6, no concurrent requests, no TCP_NODELAY). The wrapper appears to work in basic testing but fails under load or with specific response patterns.

**Why it happens:** The bugs are intermittent. Frame length errors only manifest with certain PDU sizes. The lack of concurrent requests only matters when multiple poll groups fire simultaneously. TCP_NODELAY latency is invisible in development but noticeable on real networks.

**Consequences:** Subtle data corruption from misframed responses. Missed poll cycles when requests queue behind the lock. 200ms Nagle latency making the HMI feel sluggish compared to OPC UA. These bugs are extremely hard to diagnose after the integration layer is built on top.

**Prevention:** Fix the TCP transport bugs first, before writing any ModbusClientWrapper code. Write integration tests against a Modbus simulator (the modbus-test branch has a Python Modbus server for this).

**Detection:** Enable FINEST logging in modbus_client. Watch for transaction ID mismatches, unexpected PDU lengths, or response timeouts that succeed on retry.

### Pitfall 3: TCP Half-Open Connection Blindness

**What goes wrong:** The Modbus TCP connection appears ESTABLISHED but the remote device is actually offline (cable pulled, PLC rebooted). The HMI shows "connected" status but polls return nothing or stale data.

**Why it happens:** This is the same problem documented in MEMORY.md for OPC UA. Linux default `tcp_keepalive_time=7200` (2 hours). Without application-level keepalive or `SO_KEEPALIVE` with short intervals, TCP never probes the dead connection.

**Consequences:** Operators make decisions based on stale data, believing the connection is live. In an industrial setting this is a safety concern.

**Prevention:** Configure `SO_KEEPALIVE` with 5s idle, 2s interval, 3 probes (~11s detection) in the modbus_client_tcp fork. This matches the MSocket pattern. Also consider an application-level health check (periodic FC03 read of a known register) as defense-in-depth.

**Detection:** The connection status badge stays green when the physical cable is disconnected.

## Moderate Pitfalls

### Pitfall 1: Endianness Mismatches

**What goes wrong:** Modbus registers are big-endian by spec (network byte order), but PLCs from different vendors may use different byte ordering for 32-bit and 64-bit values (big-endian, little-endian, mid-big, mid-little). Reading a float32 as big-endian when the PLC sends little-endian gives garbage values.

**Prevention:** modbus_client v1.4.1 added ModbusEndianness support. Expose endianness configuration per server in ModbusConfig. Default to big-endian (Modbus standard) but allow override.

### Pitfall 2: Unit ID Confusion

**What goes wrong:** Using unit ID 0 or 255 when the device expects a specific ID (typically 1). Or using the wrong unit ID when multiple devices are behind a Modbus gateway.

**Prevention:** Make unit ID a required field in ModbusConfig with a sensible default of 1 (most common for standalone PLCs). Document that unit ID 0 means "broadcast" and 255 is reserved.

### Pitfall 3: Poll Group Timer Drift

**What goes wrong:** Poll timers accumulate drift because the timer fires at fixed intervals but the poll itself takes variable time. A 100ms poll group that takes 50ms to execute eventually has polls overlapping or drifting apart.

**Prevention:** Use Timer.periodic for the interval but measure actual elapsed time. If a poll takes longer than the interval, skip the next tick rather than queueing. Log warnings when poll duration exceeds 50% of the interval.

### Pitfall 4: Backward Incompatibility in Config Files

**What goes wrong:** Adding modbus fields to config.json/keymappings.json breaks existing deployments that don't have these fields. JSON deserialization throws on missing keys.

**Prevention:** Use `defaultValue: []` for the modbus server list in StateManConfig (already noted in PROJECT.md constraints). Use nullable types for ModbusNodeConfig on keys that don't have Modbus mappings. Test deserialization with config files from current production deployments.

## Minor Pitfalls

### Pitfall 1: Modbus Address Confusion (0-based vs 1-based)

**What goes wrong:** Modbus protocol uses 0-based addresses, but many PLC programming tools and documentation use 1-based addresses (with prefix: 40001 = holding register 0). Users enter the wrong address.

**Prevention:** Use 0-based addresses internally (matches the protocol wire format). In the UI, label clearly: "Register Address (0-based)". Consider showing both formats in the key config UI.

### Pitfall 2: Connection Timeout Too Aggressive

**What goes wrong:** Setting connection timeout too low (e.g., 500ms) causes false disconnections on busy networks. Too high (e.g., 30s) causes long waits when the server is actually down.

**Prevention:** Use 3s connection timeout (matches existing ModbusClientWrapper code). This is reasonable for LAN environments where PLCs are typically <1ms away.

### Pitfall 3: Forgetting TCP_NODELAY

**What goes wrong:** Nagle's algorithm batches small packets (typical Modbus requests are 12-20 bytes) and adds up to 200ms latency waiting for more data. The HMI feels sluggish.

**Prevention:** Set TCP_NODELAY immediately after socket.connect() in the modbus_client_tcp fork. This is already in PROJECT.md requirements.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| TCP fork bug fixes | Frame length fix might break other response parsing | Write regression tests for all 8 function codes (FC01-FC06, FC15, FC16) before fixing |
| FC15 investigation | May need to fork modbus_client (not just TCP) if it is a real bug, not usage error | Test with ModbusCoil first as maintainer suggested. Only fork if that fails. |
| ModbusClientWrapper | Temptation to add Modbus-specific methods to StateMan | Follow M2400 adapter pattern strictly. Wrapper -> Adapter -> DeviceClient -> StateMan. |
| Config serialization | Breaking existing config.json deployments | Test with production config files. Default values for all new fields. |
| UI integration | Modbus-specific UI leaking into protocol-agnostic components | Key repository should show protocol-appropriate fields based on selection, not always show Modbus fields. |
| Windows keepalive | Different socket option constants per platform | Use the same pattern as MSocket._configureKeepalive() with Platform.isWindows branch. Test on actual Windows, not just compile. |

## Sources

- MEMORY.md -- TCP half-open connection problem documentation from OPC UA experience
- PROJECT.md -- Requirements, constraints, and key decisions
- modbus-test branch -- Previous integration attempt that violated DeviceClient abstraction
- [modbus_client changelog](https://pub.dev/packages/modbus_client/changelog) -- v1.4.1 endianness fix
- [cabbi/modbus_client_tcp source](https://github.com/cabbi/modbus_client_tcp) -- Single _currentResponse design, no TCP_NODELAY
- MSocket source (packages/jbtm/lib/src/msocket.dart) -- Keepalive reference implementation
