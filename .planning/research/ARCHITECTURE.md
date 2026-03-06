# Architecture Patterns: Modbus TCP Integration

**Domain:** Modbus TCP integration into Flutter HMI (TFC-HMI)
**Researched:** 2026-03-06

## Recommended Architecture

Follow the existing M2400 adapter pattern. The architecture is already defined by the codebase -- Modbus must conform to it.

### Component Chain

```
modbus_client_tcp (transport)
    |
    v
ModbusClientWrapper (connection lifecycle, polling, read/write)
    |
    v
ModbusDeviceClientAdapter (implements DeviceClient interface)
    |
    v
StateMan (protocol-agnostic device management)
    |
    v
UI (server_config.dart, key_repository.dart, display widgets)
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `modbus_client` (upstream) | Modbus protocol: element types, function codes, request construction, response parsing | modbus_client_tcp (transport layer) |
| `modbus_client_tcp` (fork) | TCP transport: MBAP framing, socket management, keepalive, transaction IDs | modbus_client (protocol), Dart Socket (OS) |
| `ModbusClientWrapper` | Connection lifecycle (connect/reconnect/backoff), poll group timers, read/write operations, DynamicValue conversion | modbus_client_tcp (sends requests), polledValues BehaviorSubjects (emits values) |
| `ModbusDeviceClientAdapter` | Adapts ModbusClientWrapper to DeviceClient interface. Maps DeviceClient.subscribe/read/write to wrapper methods. | ModbusClientWrapper (data operations), StateMan (via DeviceClient interface) |
| `StateMan` | Protocol-agnostic device management. Holds List<DeviceClient>. Routes subscribe/read/write by key lookup. | DeviceClient instances (OPC UA, M2400, Modbus), UI (via providers) |
| `ModbusConfig` | Server connection parameters: host, port, unitId, serverAlias, pollGroups | StateManConfig (serialization), server_config.dart (UI) |
| `ModbusNodeConfig` | Per-key parameters: registerType, address, dataType, pollGroup, serverAlias | KeyConfig (serialization), key_repository.dart (UI) |

### Data Flow

**Read path (polling):**
```
Timer fires (per poll group)
  -> ModbusClientWrapper._pollGroup()
  -> modbus_client_tcp.send(FC03/FC04 request)
  -> TCP socket write/read
  -> modbus_client parses response
  -> ModbusClientWrapper converts to DynamicValue
  -> BehaviorSubject.add(value)
  -> StateMan subscription listeners
  -> UI widget rebuild
```

**Write path:**
```
UI setpoint change
  -> StateMan.write(key, value)
  -> DeviceClient.write(key, value)
  -> ModbusDeviceClientAdapter.write()
  -> ModbusClientWrapper.writeNode()
  -> modbus_client_tcp.send(FC06/FC16 request)
  -> TCP socket write/read
  -> Response validation
```

**Connection status path:**
```
modbus_client_tcp connection state change
  -> ModbusClientWrapper._connectionController
  -> ModbusDeviceClientAdapter.connectionStream
  -> StateMan connection status aggregation
  -> UI connection badge
```

## Patterns to Follow

### Pattern 1: DeviceClient Adapter (from M2400)

**What:** Wrap protocol-specific client in an adapter implementing the DeviceClient interface. StateMan only interacts with DeviceClient.

**When:** Always. This is the mandatory integration pattern.

**Example:**
```dart
class ModbusDeviceClientAdapter implements DeviceClient {
  final ModbusClientWrapper _wrapper;
  final Map<String, ModbusNodeConfig> _keyConfigs;

  @override
  Future<DynamicValue> read(String key) {
    final config = _keyConfigs[key]!;
    return _wrapper.readNode(config);
  }

  @override
  Future<Stream<DynamicValue>> subscribe(String key) {
    final config = _keyConfigs[key]!;
    return _wrapper.subscribe(key, config);
  }

  @override
  Future<void> write(String key, DynamicValue value) {
    final config = _keyConfigs[key]!;
    return _wrapper.writeNode(config, value);
  }

  @override
  Stream<ConnectionStatus> get connectionStream =>
      _wrapper.connectionStream;
}
```

### Pattern 2: Poll Group Timers (from modbus-test branch)

**What:** Group keys by poll interval. Each group has its own Timer.periodic. When timer fires, read all keys in the group in a single batch (or sequential calls if grouping not supported).

**When:** Always for Modbus. Unlike OPC UA (which has server-side subscriptions), Modbus requires client-side polling.

**Example:**
```dart
void _startPollGroups() {
  for (final entry in _keyGroups.entries) {
    final groupName = entry.key;
    final keys = entry.value;
    final interval = config.pollGroups
        .firstWhere((g) => g.name == groupName)
        .interval;

    _pollTimers[groupName] = Timer.periodic(
      Duration(milliseconds: interval),
      (_) => _pollGroup(groupName, keys),
    );
  }
}
```

### Pattern 3: BehaviorSubject for Polled Values (from OPC UA/M2400)

**What:** Each subscribed key gets a BehaviorSubject that always holds the latest value. New subscribers get the current value immediately, then receive updates on each poll.

**When:** Always. This matches the OPC UA subscription pattern and allows the UI to work identically regardless of protocol.

### Pattern 4: Exponential Backoff Reconnect (from MSocket)

**What:** On connection failure, wait with exponential backoff (500ms -> 1s -> 2s -> 5s cap). Reset backoff on successful connection.

**When:** Always. Prevents hammering a downed server.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Protocol-Specific Branches in StateMan

**What:** Adding `if (key.isModbus) { ... } else if (key.isOpcUa) { ... }` logic inside StateMan methods.

**Why bad:** Breaks the open/closed principle. Every new protocol requires modifying StateMan. Tested with 2 protocols, breaks when adding a third.

**Instead:** Route through DeviceClient interface. StateMan holds `Map<String, DeviceClient>` mapping keys to their owning client. Lookup is by key, dispatch is polymorphic.

### Anti-Pattern 2: Sharing Connection Status Across Protocols

**What:** Having a single "connected" status that merges OPC UA + Modbus + M2400 states.

**Why bad:** If OPC UA is connected but Modbus is down, what does "connected" mean? Operators need per-connection status.

**Instead:** Each DeviceClient has its own connectionStream. UI shows per-server status badges.

### Anti-Pattern 3: Polling Inside the UI Layer

**What:** Creating Timer.periodic in Flutter widgets to poll Modbus values.

**Why bad:** Widget lifecycle management is unreliable. Timers leak on widget rebuild. Poll frequency is coupled to UI, not to the protocol layer.

**Instead:** Polling lives in ModbusClientWrapper. UI subscribes to BehaviorSubject streams. The wrapper manages timer lifecycle.

## Scalability Considerations

| Concern | 1-2 Modbus servers | 5-10 Modbus servers | 20+ Modbus servers |
|---------|---------------------|--------------------|--------------------|
| Connections | Direct TCP, no issues | Direct TCP, still fine | May need connection pooling |
| Poll load | Individual reads OK | Consider register grouping | Must use register grouping + concurrent requests |
| Memory | BehaviorSubjects per key, minimal | Moderate (~1KB per subject) | May need to dispose idle subscriptions |
| CPU | Timer overhead negligible | Timer overhead negligible | Consider consolidating poll groups across servers |

For TFC-HMI's expected use case (1-5 Modbus servers, 10-100 keys), individual reads with per-group timers are sufficient. Register grouping and concurrent requests are optimizations for later.

## Sources

- modbus-test branch -- Existing ModbusClientWrapper implementation (325 lines)
- M2400DeviceClientAdapter pattern in existing codebase
- MSocket source (packages/jbtm/lib/src/msocket.dart) -- Reconnect pattern
- PROJECT.md -- DeviceClient adapter requirement and anti-pattern documentation
