# Feature Landscape: Modbus TCP Integration

**Domain:** Industrial HMI -- Modbus TCP client
**Researched:** 2026-03-06

## Table Stakes

Features users expect. Missing = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Read holding registers (FC03) | Core Modbus operation. Every PLC exposes data here. | Low | modbus_client handles natively |
| Read input registers (FC04) | Sensor/process values. Standard in any Modbus HMI. | Low | modbus_client handles natively |
| Read coils (FC01) | Digital outputs status. Expected for discrete I/O display. | Low | modbus_client handles natively |
| Read discrete inputs (FC02) | Digital inputs status. Expected for sensor state display. | Low | modbus_client handles natively |
| Write single coil (FC05) | Toggle outputs. Basic control capability. | Low | modbus_client handles natively |
| Write single register (FC06) | Set setpoints. Basic control capability. | Low | modbus_client handles natively |
| Write multiple registers (FC16) | Batch setpoint updates. Expected for multi-parameter control. | Low | modbus_client handles natively |
| Write multiple coils (FC15) | Batch output control. Expected when >1 coil needs setting. | Med | Upstream bug for 16+ coils (issue #19). Needs fix or workaround. |
| Auto-reconnect on connection loss | Industrial environments have power cycles, cable pulls. HMI must recover. | Med | ModbusClientWrapper handles with backoff loop, matching OPC UA and M2400 patterns |
| Connection status indicator | Operators need to know if data is live or stale. | Low | ConnectionStatus enum + UI badge, same as existing protocols |
| Configurable poll intervals | Different data changes at different rates. Temperatures: 5s. Alarms: 500ms. | Med | Poll group system with named groups and per-group intervals |
| Multiple Modbus server support | Plant may have multiple PLCs on different IPs. | Med | StateManConfig already supports a list of ModbusConfig entries |
| Data type support (int16/32, uint16/32, float32/64) | Registers hold different data types. Must interpret correctly. | Low | modbus_client provides ModbusNumRegister variants for all types |

## Differentiators

Features that set product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Concurrent Modbus requests (transaction ID pipelining) | Faster polling when multiple poll groups fire simultaneously. Most Dart Modbus clients serialize requests. | High | Requires replacing _currentResponse with transaction ID map in modbus_client_tcp fork |
| TCP keepalive with fast dead-connection detection | Detect cable pulls in ~11s instead of 2 hours (Linux default). Critical for industrial reliability. | Med | Already partially implemented in fork. MSocket reference code available. |
| Register grouping for batch reads | Read contiguous registers in one FC03/FC04 call instead of individual reads. Reduces network traffic and latency. | Med | modbus_client's ModbusElementsGroup supports this for reads. Need to expose through ModbusClientWrapper. |
| Cross-platform keepalive (Linux + macOS + Windows) | MSIX Windows builds need same reliability as Linux Docker deployment. | Med | macOS/Linux done in MSocket. Windows constants known but not yet implemented. |
| Unified protocol switching in key config UI | Operator can change a key from OPC UA to Modbus without leaving the key editor. | Low | UI-only work. DeviceClient abstraction makes the backend transparent. |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Modbus RTU (serial/RS-485) | No current requirement. Adds serial port complexity, platform-specific USB handling. | Stick to TCP. If RTU needed later, modbus_client_serial exists in the same package family. |
| Modbus UDP | Rarely used in practice. TCP provides reliability guarantees needed for HMI. | Not applicable. |
| Modbus server/slave mode | TFC-HMI is a client/master only. Server mode adds complexity with no use case. | Not applicable. |
| File record operations (FC 0x14/0x15) | Exotic function codes rarely used in HMI context. modbus_client supports them but no need to expose. | Ignore. Available in library if ever needed. |
| FFI wrapping of C++ centroid-is/modbus | Dart packages are sufficient after fixes. FFI adds build complexity, platform-specific compilation, and crash risk. | Fix the Dart packages instead. |
| Custom Modbus framing on MSocket | MSocket is raw TCP. Building Modbus MBAP framing on top means reimplementing modbus_client_tcp from scratch. | Use the modbus_client_tcp fork. |

## Feature Dependencies

```
modbus_client_tcp bug fixes --> ModbusClientWrapper
modbus_client FC15 fix --> ModbusClientWrapper (write path)
ModbusClientWrapper --> ModbusDeviceClientAdapter
ModbusDeviceClientAdapter --> StateMan integration
StateMan integration --> server_config.dart UI
StateMan integration --> key_repository.dart UI
ModbusConfig JSON serialization --> StateMan integration
ModbusNodeConfig JSON serialization --> key_repository.dart UI
MSocket Windows keepalive --> cross-platform deployment (independent of Modbus)
```

## MVP Recommendation

Prioritize:
1. Read holding/input registers with configurable poll groups (covers 90% of HMI use cases)
2. Write single register/coil (setpoint control)
3. Connection lifecycle with auto-reconnect and status indicator
4. Server config UI (add/remove Modbus servers)
5. Key config UI (assign Modbus addresses to display keys)

Defer:
- **Write multiple coils (FC15) fix**: Only needed for batch digital output control. Can use individual FC05 writes as workaround until fixed.
- **Concurrent request pipelining**: Serialized requests work correctly. Only matters at scale with many poll groups.
- **Register grouping optimization**: Individual reads work. Grouping is a performance optimization for high-key-count deployments.

## Sources

- [modbus_client on pub.dev](https://pub.dev/packages/modbus_client) -- Feature set and function code support
- [modbus_client_tcp on pub.dev](https://pub.dev/packages/modbus_client_tcp) -- TCP transport capabilities
- [FC15 issue #19](https://github.com/cabbi/modbus_client/issues/19) -- Confirmed FC15 bug
- modbus-test branch in tfc-hmi repo -- Existing implementation covering most table stakes features
- PROJECT.md -- Requirements and scope definition
