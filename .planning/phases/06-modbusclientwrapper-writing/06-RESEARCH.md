# Phase 6: ModbusClientWrapper -- Writing - Research

**Researched:** 2026-03-06
**Domain:** Modbus TCP write operations (FC05, FC06, FC15, FC16) via wrapper API
**Confidence:** HIGH

## Summary

Phase 6 adds write capability to `ModbusClientWrapper`, which already has connection lifecycle (Phase 4) and poll-based reading (Phase 5). The modbus_client library already provides all the low-level write primitives: `ModbusElement.getWriteRequest(value)` handles FC05/FC06 single writes, and `ModbusElement.getMultipleWriteRequest(bytes, quantity)` handles FC15/FC16 multi-writes. `ModbusNumRegister.getWriteRequest()` intelligently auto-selects FC16 for multi-register types (int32, float32, etc.) when `byteCount > 2`. The library also already rejects writes to read-only types by checking `writeSingleFunction == null` and `writeMultipleFunction == null`, throwing `ModbusException`.

The wrapper's job is to: (1) provide a clean public API that accepts a key + value, (2) look up or create the correct `ModbusElement` for that key, (3) check connection status and reject writes when disconnected (SCADA safety -- no queuing), (4) issue `client.send(element.getWriteRequest(value))` and surface failures, and (5) reject writes to read-only types (discrete inputs, input registers) with a clear error. The existing `_createElement(ModbusRegisterSpec)` factory, `MockModbusClient.send()` pattern, and `_subscriptions` map provide direct reuse.

**Primary recommendation:** Add a `Future<void> write(String key, Object? value)` method to `ModbusClientWrapper` that reuses the existing element factory and send pattern, throwing exceptions for disconnected state and read-only register types. Write does NOT require prior subscription -- write-only control outputs must work without polling.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Write anywhere -- no prior subscription required. Supports write-only control outputs (setpoints, commands) that are never polled.
- Immediate error when disconnected -- do NOT queue writes. SCADA safety: stale queued values sent after reconnect could be dangerous for control outputs.

### Claude's Discretion
- Method signature design (align with DeviceClient.write(key, value))
- Write-only register registration approach
- Value type handling (raw Dart types vs Object? vs dynamic)
- Single vs multi-write API surface
- Auto-detection of FC06 vs FC16 for multi-register data types
- Array write support decision
- Failure surface (throw vs return code)
- Read-only type rejection timing (early wrapper check vs library exception)
- BehaviorSubject update strategy after write
- Write-only register observability
- Write concurrency model

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| WRIT-01 | User can write a single coil (FC05) via StateMan.write() | `ModbusCoil.getWriteRequest(bool)` uses FC05; `client.send()` returns `ModbusResponseCode` |
| WRIT-02 | User can write a single holding register (FC06) via StateMan.write() | `ModbusUint16Register.getWriteRequest(int)` uses FC06 when `byteCount == 2` |
| WRIT-03 | User can write multiple holding registers (FC16) via StateMan.write() | `ModbusNumRegister.getWriteRequest()` auto-selects FC16 when `byteCount > 2` (float32, int32, etc.); `getMultipleWriteRequest(bytes)` for explicit multi-register writes |
| WRIT-04 | User can write multiple coils (FC15) via StateMan.write() | `ModbusCoil.getMultipleWriteRequest(bytes, quantity: coilCount)` uses FC15; Phase 2 fixed quantity bug for 16+ coils |
| WRIT-05 | Write to read-only types rejected with clear error | `ModbusElementType.discreteInput` and `.inputRegister` have `writeSingleFunction == null` and `writeMultipleFunction == null`; library throws `ModbusException`; wrapper can add early check |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| modbus_client | local fork | Element types, write request builders, response codes | Already used by Phase 4/5; provides `getWriteRequest()` and `getMultipleWriteRequest()` |
| modbus_client_tcp | local fork | TCP transport, `send()` method | Already used; same `send()` call for reads and writes |
| rxdart | ^0.28.x | BehaviorSubject for value streams | Already used in wrapper for connection and read streams |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| test | ^1.25.x | Unit testing | TDD for all write operations |
| dart:typed_data | SDK | Uint8List for raw byte writes | Multi-coil and multi-register write payloads |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Throwing exceptions | Returning Result/ResponseCode | Exceptions align with `StateMan.write()` which wraps in `StateManException` |
| Early wrapper-level read-only check | Letting library throw `ModbusException` | Early check gives better error messages and avoids ambiguity; library check is defense-in-depth |

## Architecture Patterns

### Recommended Addition to ModbusClientWrapper

The write API adds methods to the existing `ModbusClientWrapper` class. No new files needed.

```
packages/tfc_dart/lib/core/modbus_client_wrapper.dart  (modify)
packages/tfc_dart/test/core/modbus_client_wrapper_test.dart  (modify)
```

### Pattern 1: Write Method Signature

**What:** `Future<void> write(ModbusRegisterSpec spec, Object? value)` -- takes a spec (describes the register) and a value to write.

**When to use:** For all single-value write operations. The spec provides register type, address, and data type needed to construct the correct `ModbusElement` and `getWriteRequest()`.

**Why spec-based rather than key-based:** Write-only registers may never be subscribed. The spec carries all metadata needed to construct the element. This avoids maintaining a separate "write registry." For registers that ARE subscribed, the caller already has the spec.

**Alignment with Phase 7:** `DeviceClient.write(key, DynamicValue)` will be added in Phase 7. The adapter will look up the spec from its registry and call `wrapper.write(spec, value.value)`. The wrapper does NOT need to know about DynamicValue.

```dart
// Source: Derived from existing patterns in modbus_client_wrapper.dart
Future<void> write(ModbusRegisterSpec spec, Object? value) async {
  if (_disposed) {
    throw StateError('ModbusClientWrapper has been disposed');
  }
  if (connectionStatus != ConnectionStatus.connected || _client == null) {
    throw StateError('Not connected -- cannot write (writes are not queued)');
  }

  // Reject read-only types early
  final type = spec.registerType;
  if (type == ModbusElementType.discreteInput ||
      type == ModbusElementType.inputRegister) {
    throw ArgumentError(
        'Cannot write to ${type == ModbusElementType.discreteInput ? "discrete input" : "input register"} -- read-only register type');
  }

  final element = _createElement(spec);
  final request = element.getWriteRequest(value);
  final result = await _client!.send(request);

  if (result != ModbusResponseCode.requestSucceed) {
    throw StateError('Write failed: ${result.name}');
  }

  // Update BehaviorSubject if this key is subscribed
  final sub = _subscriptions[spec.key];
  if (sub != null && !sub.value$.isClosed) {
    sub.value$.add(value);
  }
}
```

### Pattern 2: Write-Multiple API

**What:** `Future<void> writeMultiple(ModbusRegisterSpec spec, Uint8List bytes, {int? quantity})` for explicit multi-coil/multi-register array writes.

**When to use:** Writing contiguous arrays of coils or registers in a single FC15/FC16 transaction.

**Note:** For single-value writes of multi-register data types (float32, int32, etc.), the standard `write()` method handles this automatically -- `ModbusNumRegister.getWriteRequest()` auto-selects FC16 when `byteCount > 2`. The `writeMultiple()` method is for explicit array writes of N distinct coils or N distinct holding registers.

```dart
// Source: Derived from ModbusElement.getMultipleWriteRequest
Future<void> writeMultiple(ModbusRegisterSpec spec, Uint8List bytes,
    {int? quantity}) async {
  // Same connection/disposed/read-only checks as write()
  // ...
  final element = _createElement(spec);
  final request = element.getMultipleWriteRequest(bytes, quantity: quantity);
  final result = await _client!.send(request);
  if (result != ModbusResponseCode.requestSucceed) {
    throw StateError('Write multiple failed: ${result.name}');
  }
}
```

### Pattern 3: Optimistic BehaviorSubject Update

**What:** After a successful write, if the key has an active subscription, immediately update its BehaviorSubject with the written value.

**When to use:** Always on successful write when a subscription exists for the key.

**Why optimistic:** The write already succeeded on the device. Waiting for the next poll tick would cause a 1-second stale window. Read-after-write adds latency. Optimistic update provides immediate UI feedback. The next poll read will overwrite with the actual device value (which should match).

### Anti-Patterns to Avoid

- **Queuing writes for reconnect:** SCADA safety violation. A stale setpoint written after reconnect could cause dangerous physical output. The user decision explicitly forbids this.
- **Requiring subscription before write:** Write-only control outputs (setpoints, commands) are never polled. Write must work without prior subscribe().
- **Silently failing on read-only types:** WRIT-05 requires clear error, not silent failure or crash. Both early check and library exception should produce a catchable error.
- **Creating a separate element registry for writes:** The `_createElement()` factory already builds the correct element from a spec. Creating temporary elements per write call is simple and stateless.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| FC05/FC06 PDU construction | Manual byte packing | `ModbusElement.getWriteRequest(value)` | Handles coil encoding (0xFF00/0x0000), register byte order, endianness |
| FC15/FC16 PDU construction | Manual multi-write framing | `ModbusElement.getMultipleWriteRequest(bytes, quantity)` | Handles quantity vs byte-count distinction, endianness |
| FC06 vs FC16 auto-selection | Manual byteCount check | `ModbusNumRegister.getWriteRequest()` | Automatically uses FC16 for byteCount > 2 (int32, float32, etc.) |
| Coil value encoding | Manual 0xFF00/0x0000 | `ModbusBitElement._getRawValue(value)` | Handles bool, int, and truthiness correctly |
| Read-only type detection | Manual function code check | `ModbusElementType.writeSingleFunction == null` | Definitive check from type definition |

**Key insight:** The modbus_client library's element hierarchy already encapsulates ALL write PDU construction and value encoding. The wrapper's only job is connection gating, spec-to-element mapping, and error surfacing.

## Common Pitfalls

### Pitfall 1: Queuing Writes During Disconnect
**What goes wrong:** Write is buffered and sent after reconnect, applying a stale setpoint to physical equipment.
**Why it happens:** Natural inclination to "retry on failure" pattern.
**How to avoid:** Throw immediately when `connectionStatus != ConnectionStatus.connected`. The user decision explicitly requires this for SCADA safety.
**Warning signs:** Any write method that returns a Future without checking connection first.

### Pitfall 2: Forgetting Quantity for FC15 Multi-Coil Writes
**What goes wrong:** FC15 quantity field defaults to `bytes.length ~/ 2` (register formula), giving wrong coil count.
**Why it happens:** `getMultipleWriteRequest` defaults quantity to byte-based calculation which is wrong for coils.
**How to avoid:** Always pass explicit `quantity: coilCount` when writing multiple coils. Phase 2 fixed this bug.
**Warning signs:** Multi-coil writes where the coil count doesn't match the number of coils being written.

### Pitfall 3: Value Type Mismatch
**What goes wrong:** Passing a `double` to a coil write, or a `bool` to a register write, causing runtime errors in `_getRawValue()`.
**Why it happens:** The wrapper accepts `Object?` but the library expects specific types per element.
**How to avoid:** Coils expect `bool` (or `int` 0/1). Registers expect `num` (int or double). The library's `_getRawValue()` handles some conversion but not all edge cases. Document expected types per register type.
**Warning signs:** `ModbusException` or `TypeError` during write request construction.

### Pitfall 4: Race Between Write and Poll Read
**What goes wrong:** A poll read completes between write send and write response, reverting the BehaviorSubject to the old value momentarily.
**Why it happens:** Poll timers run independently of write operations.
**How to avoid:** Optimistic update after confirmed write is sufficient -- the next poll will read back the written value. This is standard SCADA behavior. The brief race window is cosmetic only.
**Warning signs:** UI value flickering after writes.

### Pitfall 5: Creating Element with Wrong Type for Existing Subscription
**What goes wrong:** Writing to a subscribed key creates a new element via `_createElement()` instead of reusing the subscription's element.
**Why it happens:** Write creates a temporary element from the spec.
**How to avoid:** For write-to-subscribed-key path, this is fine because the write element is temporary. The optimistic BehaviorSubject update handles the value propagation. The subscription element's value will be overwritten on the next poll read.
**Warning signs:** None -- this is actually the correct behavior.

## Code Examples

Verified patterns from the actual codebase:

### Single Coil Write (FC05)
```dart
// Source: packages/modbus_client/lib/src/element_type/modbus_element_bit.dart
// ModbusBitElement._getRawValue converts: true -> 0xFF00, false -> 0x0000
// This is the Modbus standard for FC05 coil write values.

final coil = ModbusCoil(name: 'output0', address: 0);
final request = coil.getWriteRequest(true);  // FC05, address=0, value=0xFF00
final result = await client.send(request);
// result == ModbusResponseCode.requestSucceed
```

### Single Holding Register Write (FC06)
```dart
// Source: packages/modbus_client/lib/src/element_type/modbus_element_num.dart
// For byteCount == 2 (uint16, int16), uses FC06 via super.getWriteRequest()

final reg = ModbusUint16Register(
  name: 'setpoint',
  address: 100,
  type: ModbusElementType.holdingRegister,
);
final request = reg.getWriteRequest(42);  // FC06, address=100, value=42
final result = await client.send(request);
```

### Multi-Register Write via Auto-Detection (FC16)
```dart
// Source: packages/modbus_client/lib/src/element_type/modbus_element_num.dart:32-49
// ModbusNumRegister.getWriteRequest() auto-selects FC16 when byteCount > 2

final reg = ModbusFloatRegister(
  name: 'temperature',
  address: 200,
  type: ModbusElementType.holdingRegister,
);
// byteCount == 4, so this automatically uses FC16 with 2 registers
final request = reg.getWriteRequest(23.5);  // FC16, address=200, 2 registers
final result = await client.send(request);
```

### Read-Only Type Rejection
```dart
// Source: packages/modbus_client/lib/src/modbus_element.dart:72-76
// writeSingleFunction is null for discreteInput and inputRegister

final di = ModbusDiscreteInput(name: 'sensor', address: 0);
try {
  di.getWriteRequest(true);  // throws ModbusException
} on ModbusException catch (e) {
  // e.msg: "discreteInput element does not support write request!"
}
```

### MockModbusClient Write Handling
```dart
// Source: packages/tfc_dart/test/core/modbus_client_wrapper_test.dart:48-65
// MockModbusClient.send() handles write requests via onSend callback

mock.onSend = (request) {
  if (request is ModbusWriteRequest) {
    // Write succeeded -- element.setValueFromBytes is called by
    // internalSetFromPduResponse for writeSingle responses
    return ModbusResponseCode.requestSucceed;
  }
  return ModbusResponseCode.requestSucceed;
};
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Individual element reads | Batch coalesced reads (Phase 5, Plan 02) | 2026-03-06 | Reads use `ModbusElementsGroup`; writes remain individual element operations |
| FC15 with wrong quantity | Fixed FC15 with explicit quantity parameter | Phase 2 (LIBFIX-01) | Multi-coil writes now reliable for 16+ coils |

**Key architectural note:** Writes are inherently individual operations (one write command per target register/coil), unlike reads which benefit from batch coalescing. The write API pattern is simpler than the read API.

## Open Questions

1. **Multi-coil array write API exposure**
   - What we know: FC15 multi-coil writes require `Uint8List` packed bytes and explicit `quantity`. The library supports it via `getMultipleWriteRequest()`.
   - What's unclear: Whether Phase 7's `DeviceClient.write(key, DynamicValue)` will need to expose multi-coil array writes, or if individual coil writes (FC05) suffice for the HMI use case.
   - Recommendation: Implement `writeMultiple()` in the wrapper as a low-level method. Phase 7 adapter can decide whether to expose it through `DeviceClient`. Most HMI control is single coil toggles.

2. **Write concurrency model**
   - What we know: Phase 1 added transaction ID-based concurrent request support. `client.send()` can handle multiple in-flight requests.
   - What's unclear: Whether concurrent writes from different UI interactions could conflict (e.g., two rapid writes to the same register).
   - Recommendation: No serialization needed at the wrapper level. The Modbus TCP transport already handles concurrent transactions via transaction IDs. The device itself serializes incoming writes. Let the transport handle it.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | dart test ^1.25.x |
| Config file | packages/tfc_dart/dart_test.yaml (if exists) or none |
| Quick run command | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart` |
| Full suite command | `cd packages/tfc_dart && dart test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| WRIT-01 | Single coil write (FC05) succeeds | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "coil write"` | Partially (file exists, write tests TBD) |
| WRIT-02 | Single holding register write (FC06) succeeds | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "holding register write"` | Partially |
| WRIT-03 | Multiple holding registers write (FC16) succeeds | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "multi-register write"` | Partially |
| WRIT-04 | Multiple coils write (FC15) succeeds | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "multi-coil write"` | Partially |
| WRIT-05 | Write to read-only types rejected with error | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "read-only"` | Partially |

### Sampling Rate
- **Per task commit:** `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart -x`
- **Per wave merge:** `cd packages/tfc_dart && dart test`
- **Phase gate:** Full suite green before /gsd:verify-work

### Wave 0 Gaps
None -- existing test file (`packages/tfc_dart/test/core/modbus_client_wrapper_test.dart`) already has MockModbusClient, createWrapperWithMock helper, and connection/read test groups. Write test groups will be added to this file following the same patterns.

## Sources

### Primary (HIGH confidence)
- `packages/modbus_client/lib/src/modbus_element.dart` - `getWriteRequest()` (line 67) and `getMultipleWriteRequest()` (line 100)
- `packages/modbus_client/lib/src/element_type/modbus_element_num.dart` - `ModbusNumRegister.getWriteRequest()` auto FC06/FC16 (line 32-49)
- `packages/modbus_client/lib/src/element_type/modbus_element_bit.dart` - `ModbusBitElement._getRawValue()` coil encoding (line 37-43)
- `packages/modbus_client/lib/modbus_client.dart` - `ModbusElementType` write function definitions (line 50-85)
- `packages/modbus_client/lib/src/modbus_request.dart` - `ModbusWriteRequest` class (line 176)
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` - existing wrapper with `_createElement()`, `_subscriptions`, connection status
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` - MockModbusClient patterns
- `packages/tfc_dart/lib/core/state_man.dart` - `DeviceClient` abstract class (line 531), `StateMan.write()` (line 1048), `StateManException` (line 340)

### Secondary (MEDIUM confidence)
- `.planning/phases/06-modbusclientwrapper-writing/06-CONTEXT.md` - User decisions and code context from discussion phase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries are local forks already in use by Phases 4/5
- Architecture: HIGH - Write pattern follows existing read pattern with `client.send(element.getRequest())`
- Pitfalls: HIGH - Known from Phase 2 FC15 fix and SCADA safety requirements from user discussion

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable -- local forks, no external dependency changes)
