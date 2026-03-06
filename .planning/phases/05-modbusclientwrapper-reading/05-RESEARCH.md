# Phase 5: ModbusClientWrapper -- Reading - Research

**Researched:** 2026-03-06
**Domain:** Modbus register polling, batch coalescing, and data type interpretation in Dart
**Confidence:** HIGH

## Summary

This phase extends the existing `ModbusClientWrapper` (built in Phase 4) with poll-based reading of all four Modbus register types: coils (FC01), discrete inputs (FC02), holding registers (FC03), and input registers (FC04). The wrapper must support configurable poll groups with independent intervals, automatic coalescing of contiguous same-type registers into batch reads via `ModbusElementsGroup`, BehaviorSubject-based value streams per registered key, synchronous read of last-known values, and dynamic add/remove of register subscriptions at runtime.

The modbus_client library already provides complete data type interpretation infrastructure: `ModbusBitElement` for booleans (coils/discrete inputs), `ModbusInt16Register` through `ModbusDoubleRegister` (float64) for numeric types, and `ModbusElementsGroup` for batch reads with automatic per-element value parsing from response data. The library handles address range calculation, byte extraction per element, and endianness. The wrapper's job is to orchestrate polling timers, manage subscription lifecycle, build and rebuild coalesced groups, and pipe parsed values into BehaviorSubject streams.

The Collector class in the codebase provides the `Timer.periodic` polling pattern to follow. The existing `MockModbusClient` from Phase 4 tests needs extension to support mocking `send()` responses for read operations. The key design challenge is the coalescing algorithm: grouping contiguous same-type registers in the same poll group into `ModbusElementsGroup` instances, handling gaps (read through small gaps for efficiency), splitting oversized batches (125 register / 2000 coil limit), and recalculating groups when subscriptions change.

**Primary recommendation:** Extend `ModbusClientWrapper` with a `ModbusPollManager` internal class (or inline in wrapper) that manages named poll groups. Each poll group owns a `Timer.periodic` that, on tick, builds coalesced `ModbusElementsGroup` instances from its registered specs, calls `client.send(group.getReadRequest())`, and pipes parsed `ModbusElement.value` results into per-key `BehaviorSubject` streams. Use raw Dart types (not DynamicValue) for the value streams -- Phase 7 adapter will convert.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- Auto-start poll timers when connectionStatus becomes connected, pause on disconnect, resume on reconnect
- No separate start/stop API for polling -- tied to connection lifecycle
- Default poll interval: 1 second when no explicit interval is configured
- Multiple named poll groups per device supported (e.g., 'fast' at 200ms, 'slow' at 5s)
- On disconnect: skip reads silently, resume polling on next reconnect. No catch-up reads. Last-known values remain in BehaviorSubjects until updated.
- Structured config object (ModbusRegisterSpec) with fields: registerType, address, dataType, pollGroup
- Dynamic add/remove of registers at runtime while polls are running. Timer picks up changes on next tick.
- Both stream + synchronous read: subscribe() returns Stream, read() returns last-known cached value (BehaviorSubject.valueOrNull pattern)
- Keep last-known value in BehaviorSubject on read failure (standard SCADA behavior -- operators expect values to persist until updated)
- Modbus exception responses (illegal address, device busy): log at warning level, skip that register for this poll cycle, continue with remaining registers. Don't crash the poll group for one bad register.
- No consecutive-failure threshold -- poll forever, matching Phase 4's "retry forever" philosophy
- Read timeouts configurable per poll group (fast groups need short timeouts to not block next cycle)
- Automatic coalescing: wrapper detects contiguous same-type registers in the same poll group and groups them into ModbusElementsGroup batch reads. Transparent to subscribers.
- Gap handling: read gaps too -- if registers 100 and 105 are both subscribed, read 100-105 as one batch and discard unused. Standard SCADA practice for small gaps.
- Recalculate batch groups when registers are dynamically added/removed, before the next poll tick
- Auto-split oversized batches that exceed Modbus limits (125 registers / 2000 coils per request)
- Follow the Collector's Timer.periodic pattern for poll timers (fire-and-forget async callback)
- Use ModbusElementsGroup.getReadRequest() for batch reads
- The modbus_client library's ModbusElement.value already parses data types -- no manual byte interpretation needed
- BehaviorSubject per registered key gives both stream and sync read for free (.stream and .valueOrNull)

### Claude's Discretion
- Value type emitted by register streams (DynamicValue vs raw Dart types -- choose based on cleanest layering with Phase 7 adapter)
- Gap threshold for coalescing (whether to cap the gap size for batch reads)
- Internal data structure for tracking subscriptions (Map keying strategy)
- ModbusRegisterSpec exact field names and constructor design
- Poll group naming conventions and validation

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| READ-01 | User can read coils (FC01) and see boolean values | `ModbusCoil` element with `ModbusElementType.coil` + `ModbusBitElement.setValueFromBytes()` returns bool |
| READ-02 | User can read discrete inputs (FC02) and see boolean values | `ModbusDiscreteInput` element with `ModbusElementType.discreteInput` + `ModbusBitElement.setValueFromBytes()` returns bool |
| READ-03 | User can read holding registers (FC03) with configurable data types | `ModbusElementType.holdingRegister` + `ModbusInt16Register` through `ModbusDoubleRegister` for all numeric types |
| READ-04 | User can read input registers (FC04) with configurable data types | `ModbusElementType.inputRegister` + same register classes as FC03 |
| READ-05 | Data types supported: bit, int16, uint16, int32, uint32, float32, int64, uint64, float64 | Full mapping: bit->ModbusBitElement, int16->ModbusInt16Register, uint16->ModbusUint16Register, int32->ModbusInt32Register, uint32->ModbusUint32Register, float32->ModbusFloatRegister, int64->ModbusInt64Register, uint64->ModbusUint64Register, float64->ModbusDoubleRegister |
| READ-06 | Contiguous registers can be read in a single batch request (register grouping/coalescing) | `ModbusElementsGroup` handles batch reads with `getReadRequest()`, auto-parses per-element values in `internalSetElementData()`, enforces 125-register/2000-coil limits |
| READ-07 | Poll groups with configurable intervals control how often registers are read | `Timer.periodic(interval, callback)` per named poll group, auto-started on connect, paused on disconnect |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| modbus_client (fork) | local | ModbusElement types, ModbusElementsGroup, read requests, data type parsing | Already forked; provides all element types and batch read infrastructure |
| modbus_client_tcp (fork) | 1.2.3 (local) | `client.send(request)` for actual TCP read operations | Already forked and fixed in Phases 1-3; wrapper already holds the client |
| rxdart | ^0.28.0 | BehaviorSubject per registered key for value streams with replay + sync read | Already used by Phase 4 wrapper for connection status |
| dart:async | (stdlib) | Timer.periodic for poll groups, StreamSubscription for connection listener | Standard Dart; Collector already uses this pattern |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| test | ^1.25.0 (dev) | Unit testing framework | All Phase 5 tests |
| logger | ^2.4.0 | Warning-level logging for read failures, exception responses | Error handling during polls |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Raw Dart types in BehaviorSubject | DynamicValue from open62541 | DynamicValue is OPC UA-specific, heavy; raw types (bool, int, double) are cleaner for Modbus. Phase 7 adapter wraps to DynamicValue. |
| Timer.periodic per poll group | Stream.periodic or isolate-based timers | Timer.periodic is simpler, proven in Collector, sufficient for HMI polling rates |
| ModbusElementsGroup for coalescing | Manual PDU construction | Group already handles address range, byte extraction per element, size limits; manual construction duplicates tested code |

## Architecture Patterns

### Recommended Project Structure
```
packages/tfc_dart/lib/core/
  modbus_client_wrapper.dart     # Extended with poll/read API (this phase)
  state_man.dart                 # ConnectionStatus enum (imported by wrapper)

packages/tfc_dart/test/core/
  modbus_client_wrapper_test.dart  # Extended with poll/read tests (this phase)
```

No new files needed -- Phase 5 extends the existing wrapper file and test file. The wrapper grows from ~200 lines to ~400-500 lines.

### Pattern 1: Named Poll Groups with Timer.periodic

**What:** Each poll group is a named timer with its own interval and set of registered specs. The timer callback collects specs, builds coalesced read groups, sends batch reads, and pipes results to BehaviorSubjects.
**When to use:** Any periodic data acquisition with multiple update rates.
**Example:**

```dart
// Source: Collector pattern (packages/tfc_dart/lib/core/collector.dart line 198)
// adapted for poll groups

class _PollGroup {
  final String name;
  final Duration interval;
  final Duration? responseTimeout;
  Timer? _timer;
  final List<_RegisterSubscription> _subscriptions = [];
  bool _dirty = true; // recalculate groups flag
  List<ModbusElementsGroup> _cachedGroups = [];

  void start(Future<void> Function() pollCallback) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) async {
      await pollCallback();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
```

### Pattern 2: Coalescing Algorithm

**What:** Before each poll tick, group registered specs by register type, sort by address, merge contiguous (or near-contiguous) specs into `ModbusElementsGroup` batches, split batches that exceed Modbus limits.
**When to use:** Any batch Modbus read scenario.
**Key constraints from `ModbusElementsGroup`:**
- All elements must be same type (enforced by `_checkAndUpdate`)
- Max 125 registers or 2000 coils per group (enforced by `_checkAndUpdate`)
- Elements are sorted by address automatically
- `_addressRange` = last element's (address + registerSize) - first element's address

**Coalescing flow:**
1. Group specs by `ModbusElementType` (coil, discreteInput, holdingRegister, inputRegister)
2. Within each type group, sort by address
3. Merge into batches: start a new batch when:
   - Gap exceeds threshold (recommended: 10 registers for registers, 100 for coils)
   - Batch would exceed Modbus limit (125 registers / 2000 coils)
4. For each batch, create `ModbusElementsGroup` with all elements (including gap-filler elements if needed)
5. Cache groups until subscriptions change (dirty flag)

**Critical implementation detail:** `ModbusElementsGroup` auto-includes gap registers in its address range calculation. When you add elements at address 100 and 105 (both uint16), the group's `_addressRange` is 6 (105 - 100 + 1), so the read request reads 6 registers. The response parser (`internalSetElementData`) extracts each element by its offset from `startAddress`. Gap values are simply not consumed by any element -- they're read and discarded. You do NOT need to create placeholder elements for gaps.

### Pattern 3: Connection-Lifecycle-Tied Polling

**What:** Listen to the wrapper's own `connectionStream`. When status becomes `connected`, start all poll timers. When status becomes `disconnected`, stop all timers. When status becomes `connected` again, restart timers.
**When to use:** Any polling system that depends on an active connection.
**Example:**

```dart
// In ModbusClientWrapper, after existing connection loop setup:
StreamSubscription<ConnectionStatus>? _pollLifecycleSubscription;

void _initPollLifecycle() {
  _pollLifecycleSubscription = connectionStream.listen((status) {
    if (status == ConnectionStatus.connected) {
      _startAllPolling();
    } else {
      _stopAllPolling();
    }
  });
}
```

### Pattern 4: Per-Key BehaviorSubject with Factory Creation

**What:** Each registered key (e.g., "coil:0" or a user-defined alias) gets a lazily-created `BehaviorSubject`. The subject is created on first `subscribe()` or `addRegister()`, seeded with null (or no seed for `BehaviorSubject<T?>`). Poll results pipe into it. `read()` returns `subject.valueOrNull`.
**When to use:** When subscribers need both stream and sync access to the same value.

```dart
// Per registered spec
class _RegisterSubscription {
  final ModbusRegisterSpec spec;
  final ModbusElement element; // the typed modbus_client element
  final BehaviorSubject<Object?> value$; // bool, int, or double

  Object? get currentValue => value$.valueOrNull;
  Stream<Object?> get stream => value$.stream;
}
```

### Anti-Patterns to Avoid

- **Creating ModbusElement instances on every poll tick:** Elements should be created once when a register is added, cached, and reused. The `ModbusElement.value` field is updated in-place by `setValueFromBytes()` during response parsing. Creating new elements each tick wastes allocations and loses the value update callback.
- **Awaiting `client.send()` for each element individually in a loop:** This serializes reads. Instead, use `ModbusElementsGroup.getReadRequest()` for batch reads. A single `send()` reads an entire contiguous range.
- **Trying to create ModbusElementsGroup with mixed types:** The group enforces homogeneous types -- mixing coils and holding registers throws `ModbusException`. Group by type first.
- **Ignoring the dirty flag for coalescing:** Recalculating groups on every tick is wasteful. Only recalculate when subscriptions change.
- **Using `BehaviorSubject<DynamicValue>` for register values:** DynamicValue is an OPC UA type from open62541. Modbus values are simple (bool, int, double). Using DynamicValue couples the wrapper to OPC UA infrastructure. Phase 7 adapter performs the conversion.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Data type parsing from bytes | Custom byte extraction logic | `ModbusElement.setValueFromBytes()` (already in modbus_client) | Handles endianness, signed/unsigned, float, 16/32/64-bit correctly |
| Batch read address calculation | Manual PDU construction with address math | `ModbusElementsGroup.getReadRequest()` | Calculates start address, address range, handles bit vs register addressing |
| Per-element value extraction from batch response | Manual byte slicing from response PDU | `ModbusReadGroupRequest.internalSetElementData()` | Automatically routes response bytes to each element by address offset |
| Value stream with replay + sync read | StreamController + cached variable | `BehaviorSubject<T?>` from rxdart | Thread-safe, automatic replay to new subscribers, `.valueOrNull` for sync |
| Periodic timer | Custom Future.delayed loop | `Timer.periodic()` from dart:async | Standard Dart, non-drifting, cancelable, proven in Collector |

**Key insight:** The modbus_client library does the heavy lifting for data type parsing and batch read mechanics. The wrapper's job is orchestration: managing timers, building groups from specs, calling send, and piping results to subjects. Nearly zero byte-level manipulation is needed.

## Common Pitfalls

### Pitfall 1: ModbusElementsGroup Throws on Oversized Range
**What goes wrong:** Adding elements that span more than 125 registers (or 2000 coils) to a single `ModbusElementsGroup` throws `ModbusException`.
**Why it happens:** `_checkAndUpdate()` enforces `maxRegistersRange = 125` and `maxCoilsRange = 2000`, and it rolls back the add if the constraint is violated.
**How to avoid:** Pre-split elements into groups that fit within limits before creating `ModbusElementsGroup`. Calculate the address range before adding: `lastAddress + lastByteCount/2 - firstAddress <= 125` for registers.
**Warning signs:** `ModbusException: Address range exceeds 125!` at runtime.

### Pitfall 2: ModbusElementsGroup Throws on Mixed Types
**What goes wrong:** Adding coil elements and holding register elements to the same group throws.
**Why it happens:** `_checkAndUpdate()` checks `_elements.any((e) => e.type == _type)` -- all must be same type.
**How to avoid:** Group elements by `ModbusElementType` before creating groups. The coalescing algorithm must handle four separate type buckets.
**Warning signs:** `ModbusException: All elements must be of same type!`

### Pitfall 3: send() Returns Error Code, Doesn't Throw
**What goes wrong:** Treating `client.send(request)` as throwing on failure. It returns `ModbusResponseCode`, not an exception.
**Why it happens:** The Modbus protocol uses response codes (exception codes) as the error signaling mechanism, and the library mirrors this.
**How to avoid:** Always check the return value: `if (result != ModbusResponseCode.requestSucceed)`. Log and skip on failure. Don't try/catch -- the future resolves normally with an error code.
**Warning signs:** Errors being silently swallowed, or unhandled exception from wrong error handling pattern.

### Pitfall 4: Timer.periodic Callback Overlap
**What goes wrong:** If a poll tick takes longer than the interval (e.g., 200ms interval but read takes 500ms), the next tick fires while the previous is still running, leading to concurrent sends.
**Why it happens:** `Timer.periodic` fires regardless of whether the callback completed.
**How to avoid:** Use a guard flag (`_pollInProgress`) to skip the tick if the previous one hasn't finished. This is standard SCADA practice -- skip reads rather than queue them.
**Warning signs:** Multiple concurrent reads to the same device, response routing confusion, timeout storms.

### Pitfall 5: BehaviorSubject Close During Active Poll
**What goes wrong:** If `dispose()` closes BehaviorSubjects while a poll callback is still running, adding to a closed subject throws.
**Why it happens:** The poll callback is async. `dispose()` may run between the `await send()` and the `subject.add(value)`.
**How to avoid:** Stop all timers before closing subjects. Check `!subject.isClosed` before adding. Set a `_disposed` flag and check it in the poll callback after every await.
**Warning signs:** `Unhandled exception: Cannot add event after closing.`

### Pitfall 6: ModbusElement.value Side Effect in setValueFromBytes
**What goes wrong:** `setValueFromBytes()` both returns the value AND stores it in the element's `_value` field. If you share elements across groups, the value gets overwritten by whichever group reads last.
**Why it happens:** ModbusElement is stateful -- `value` is a mutable field, not just a return value.
**How to avoid:** Each registered spec should own its own `ModbusElement` instance. Never share elements between groups or subscriptions. After `send()`, read the value from `element.value` and pipe it to the BehaviorSubject.
**Warning signs:** Values from one poll group appearing in another's stream.

### Pitfall 7: Bit Element Addressing in Group Response Parsing
**What goes wrong:** Bit elements (coils/discrete inputs) use bit-level addressing in batch responses, not byte-level. The `internalSetElementData` for `ModbusReadGroupRequest` handles this correctly (`byteIndex = offset ~/ 8`, `bitIndex = offset % 8`), but only when elements are correctly positioned relative to the group's `startAddress`.
**Why it happens:** Coil/discrete input responses pack 8 values per byte.
**How to avoid:** Trust `ModbusElementsGroup`'s response parsing -- it handles bit addressing correctly. Don't try to manually extract bit values from the response.
**Warning signs:** Coil values reading as wrong booleans, off-by-one bit positions.

## Code Examples

### Creating ModbusElement Instances from a Register Spec

```dart
// Source: packages/modbus_client/lib/src/modbus_element.dart and element_type/ files

/// Factory to create the correct ModbusElement from a ModbusRegisterSpec
ModbusElement _createElement(ModbusRegisterSpec spec) {
  final type = spec.registerType; // ModbusElementType
  final address = spec.address;
  final name = spec.key; // or generated name

  // Bit types (coils and discrete inputs)
  if (type == ModbusElementType.coil) {
    return ModbusCoil(name: name, address: address);
  }
  if (type == ModbusElementType.discreteInput) {
    return ModbusDiscreteInput(name: name, address: address);
  }

  // Register types -- select by dataType
  switch (spec.dataType) {
    case ModbusDataType.int16:
      return ModbusInt16Register(name: name, address: address, type: type);
    case ModbusDataType.uint16:
      return ModbusUint16Register(name: name, address: address, type: type);
    case ModbusDataType.int32:
      return ModbusInt32Register(name: name, address: address, type: type);
    case ModbusDataType.uint32:
      return ModbusUint32Register(name: name, address: address, type: type);
    case ModbusDataType.float32:
      return ModbusFloatRegister(name: name, address: address, type: type);
    case ModbusDataType.int64:
      return ModbusInt64Register(name: name, address: address, type: type);
    case ModbusDataType.uint64:
      return ModbusUint64Register(name: name, address: address, type: type);
    case ModbusDataType.float64:
      return ModbusDoubleRegister(name: name, address: address, type: type);
    default: // bit for register type defaults to uint16
      return ModbusUint16Register(name: name, address: address, type: type);
  }
}
```

### Batch Read via ModbusElementsGroup

```dart
// Source: packages/modbus_client/lib/src/modbus_element_group.dart

// Create a group of contiguous holding registers
final group = ModbusElementsGroup([
  ModbusUint16Register(
    name: 'speed', address: 100, type: ModbusElementType.holdingRegister),
  ModbusUint16Register(
    name: 'temp', address: 101, type: ModbusElementType.holdingRegister),
  ModbusFloat32Register(
    name: 'pressure', address: 102, type: ModbusElementType.holdingRegister),
  // address 102-103 (float32 = 2 registers)
]);

// group.startAddress == 100
// group.addressRange == 4 (100, 101, 102, 103)

// Send batch read
final result = await client.send(group.getReadRequest());
if (result == ModbusResponseCode.requestSucceed) {
  // Each element's .value is now populated:
  // group[0].value == int (uint16 at address 100)
  // group[1].value == int (uint16 at address 101)
  // group[2].value == double (float32 at address 102-103)
}
```

### Coalescing Algorithm

```dart
// Build coalesced groups from a list of subscriptions
List<ModbusElementsGroup> _buildCoalescedGroups(
    List<_RegisterSubscription> subs) {
  if (subs.isEmpty) return [];

  // Group by element type
  final byType = <ModbusElementType, List<_RegisterSubscription>>{};
  for (final sub in subs) {
    byType.putIfAbsent(sub.element.type, () => []).add(sub);
  }

  final groups = <ModbusElementsGroup>[];
  for (final typeSubs in byType.values) {
    // Sort by address
    typeSubs.sort((a, b) => a.element.address - b.element.address);

    final isRegister = typeSubs.first.element.type.isRegister;
    final maxRange = isRegister
        ? ModbusElementsGroup.maxRegistersRange  // 125
        : ModbusElementsGroup.maxCoilsRange;     // 2000
    final gapThreshold = isRegister ? 10 : 100;

    var currentBatch = <_RegisterSubscription>[typeSubs.first];

    for (var i = 1; i < typeSubs.length; i++) {
      final prev = currentBatch.last;
      final curr = typeSubs[i];
      final prevEnd = prev.element.address +
          (isRegister ? prev.element.byteCount ~/ 2 : 1);
      final gap = curr.element.address - prevEnd;

      // Start new batch if gap too large or batch would exceed limit
      final batchEnd = curr.element.address +
          (isRegister ? curr.element.byteCount ~/ 2 : 1);
      final batchRange = batchEnd - currentBatch.first.element.address;

      if (gap > gapThreshold || batchRange > maxRange) {
        groups.add(ModbusElementsGroup(
            currentBatch.map((s) => s.element)));
        currentBatch = [curr];
      } else {
        currentBatch.add(curr);
      }
    }
    if (currentBatch.isNotEmpty) {
      groups.add(ModbusElementsGroup(
          currentBatch.map((s) => s.element)));
    }
  }
  return groups;
}
```

### Poll Tick Implementation

```dart
// Fire-and-forget async callback for Timer.periodic
Future<void> _onPollTick(_PollGroup group) async {
  if (_disposed || connectionStatus != ConnectionStatus.connected) return;
  if (group._pollInProgress) return; // skip if previous tick still running
  group._pollInProgress = true;

  try {
    if (group._dirty) {
      group._cachedGroups = _buildCoalescedGroups(group._subscriptions);
      group._dirty = false;
    }

    for (final elemGroup in group._cachedGroups) {
      if (_disposed || connectionStatus != ConnectionStatus.connected) break;

      final request = elemGroup.getReadRequest(
        responseTimeout: group.responseTimeout,
      );
      final result = await _client!.send(request);

      if (result == ModbusResponseCode.requestSucceed) {
        // Values are already parsed into each element by the library
        for (final sub in group._subscriptions) {
          if (!sub.value$.isClosed) {
            sub.value$.add(sub.element.value);
          }
        }
      } else {
        _log.w('Poll group "${group.name}" read failed: ${result.name}');
        // Last-known values remain in BehaviorSubjects (SCADA behavior)
      }
    }
  } finally {
    group._pollInProgress = false;
  }
}
```

### Extending MockModbusClient for Read Tests

```dart
// Extension of Phase 4 MockModbusClient to support send() mocking
class MockModbusClient extends ModbusClientTcp {
  bool _connected = false;
  bool shouldFailConnect = false;
  int connectCallCount = 0;
  int disconnectCallCount = 0;

  /// Response handler: given a request, return response code and optionally
  /// populate element values. Defaults to requestSucceed.
  ModbusResponseCode Function(ModbusRequest request)? onSend;

  MockModbusClient()
      : super('mock',
            serverPort: 0,
            connectionMode: ModbusConnectionMode.doNotConnect);

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect() async {
    connectCallCount++;
    if (shouldFailConnect) return false;
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCallCount++;
    _connected = false;
  }

  @override
  Future<ModbusResponseCode> send(ModbusRequest request) async {
    if (!_connected) return ModbusResponseCode.connectionFailed;
    if (onSend != null) return onSend!(request);

    // Default: succeed and set element values to defaults
    if (request is ModbusReadRequest) {
      // Set a default value on the element
      final byteCount = request.element.byteCount;
      request.element.setValueFromBytes(Uint8List(byteCount));
    }
    if (request is ModbusReadGroupRequest) {
      // Set default values for all elements in group
      final dataSize = request.elementGroup.type!.isRegister
          ? request.elementGroup.addressRange * 2
          : (request.elementGroup.addressRange + 7) ~/ 8;
      request.internalSetElementData(Uint8List(dataSize));
    }
    return ModbusResponseCode.requestSucceed;
  }

  void simulateDisconnect() {
    _connected = false;
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Individual reads per element | Batch reads via ModbusElementsGroup | Existing in library | Reduces round-trips: N registers in 1 request instead of N requests |
| Manual byte parsing | ModbusElement.setValueFromBytes() | Existing in library | Zero byte manipulation code needed in wrapper |
| Fixed polling with StreamController | Timer.periodic + BehaviorSubject | Project pattern (Collector) | Built-in replay, sync read, clean subscription management |

**Key version notes:**
- modbus_client library is a local fork -- API is stable and under project control
- ModbusElementsGroup validates constraints at add-time (not send-time) -- groups are always valid once created
- ModbusElement.value is set in-place by the library's response parser -- no need to extract from response manually

## Open Questions

1. **Value type for register streams**
   - What we know: Phase 7 adapter wraps to `DynamicValue` (from open62541). Modbus reads produce `bool` (bits), `int` (16/32/64-bit integers), or `double` (float/double).
   - Options: `BehaviorSubject<Object?>` (nullable, holds bool/int/double), `BehaviorSubject<num?>` (loses bool), or typed subjects per data type.
   - Recommendation: Use `BehaviorSubject<Object?>` with null seed. This is the simplest approach -- bool, int, and double are all Object. Phase 7 adapter reads the value type from the spec to construct the correct DynamicValue. The alternative (typed generics) adds complexity without benefit since the Phase 7 adapter needs the spec anyway to determine the DynamicValue type.

2. **Gap threshold for coalescing**
   - What we know: Standard SCADA practice is to read through small gaps. Large gaps waste bandwidth.
   - Options: Fixed threshold (10 registers), proportional (gap < 50% of batch size), no limit (always coalesce).
   - Recommendation: **10 registers for register types, 100 for coil types.** This balances bandwidth waste (20 extra bytes worst case for registers) against request reduction. Reading 10 extra registers is trivial vs. the overhead of a separate TCP round-trip. This can be tuned later without API changes since coalescing is internal.

3. **ModbusRegisterSpec field names**
   - Recommendation:
   ```dart
   class ModbusRegisterSpec {
     final String key;           // unique identifier for this registration
     final ModbusElementType registerType; // coil, discreteInput, holdingRegister, inputRegister
     final int address;          // 0-based register address
     final ModbusDataType dataType;  // int16, uint16, etc. (ignored for bit types)
     final String pollGroup;     // name of the poll group (default: 'default')
   }
   ```
   - `ModbusDataType` should be a simple enum: `{ bit, int16, uint16, int32, uint32, float32, int64, uint64, float64 }`
   - For bit types (coil/discreteInput), `dataType` is ignored (always bool)

4. **Poll group naming**
   - Recommendation: Free-form strings with a `'default'` constant. No validation beyond non-empty. The wrapper creates poll groups lazily when the first spec references them. Interval is set when the group is first created (or has a sensible default of 1s).
   - Poll group configuration: Either a map passed to a configure method, or inferred from first registration. Recommend: `addPollGroup(name, interval, {responseTimeout})` method, with automatic creation of 'default' group at 1s if used without explicit configuration.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | dart test ^1.25.0 |
| Config file | packages/tfc_dart/dart_test.yaml (concurrency: 1) |
| Quick run command | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart` |
| Full suite command | `cd packages/tfc_dart && dart test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| READ-01 | Coils (FC01) return boolean values | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "coil" -r compact` | Extends existing file |
| READ-02 | Discrete inputs (FC02) return boolean values | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "discrete" -r compact` | Extends existing file |
| READ-03 | Holding registers (FC03) with configurable data types | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "holding" -r compact` | Extends existing file |
| READ-04 | Input registers (FC04) with configurable data types | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "input register" -r compact` | Extends existing file |
| READ-05 | All data types (bit through float64) supported | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "data type" -r compact` | Extends existing file |
| READ-06 | Contiguous registers coalesced into batch reads | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "coalesce" -r compact` | Extends existing file |
| READ-07 | Poll groups with configurable intervals | unit | `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart --name "poll group" -r compact` | Extends existing file |

### Sampling Rate
- **Per task commit:** `cd packages/tfc_dart && dart test test/core/modbus_client_wrapper_test.dart`
- **Per wave merge:** `cd packages/tfc_dart && dart test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] Extend `MockModbusClient` in test file with `send()` override and configurable response handler
- [ ] Add new test groups for READ-01 through READ-07 to existing `modbus_client_wrapper_test.dart`
- [ ] No new test infrastructure files needed -- all tests extend existing file and mock

## Discretion Recommendations

### Value type: `Object?` (raw Dart types)
**Rationale:** Modbus registers produce `bool`, `int`, or `double`. These are primitive Dart types. Using `Object?` in BehaviorSubject allows all three without generics complexity. Phase 7 adapter knows the spec and can construct the correct `DynamicValue` wrapper. Using DynamicValue directly would couple the Modbus wrapper to the open62541 package unnecessarily.

### Gap threshold: 10 registers / 100 coils
**Rationale:** At 2 bytes per register, reading 10 extra registers wastes 20 bytes per poll -- trivial compared to the TCP overhead of an extra request (~60 bytes for MBAP + response framing + TCP ACK latency). For coils, 100 extra bits is just 13 extra bytes. This threshold is conservative and suitable for typical HMI register layouts.

### Subscription tracking: Map<String, _RegisterSubscription> keyed by spec.key
**Rationale:** Each registered spec has a unique `key` field. A flat map provides O(1) lookup for subscribe/unsubscribe/read operations. Poll groups hold references to their subscriptions via a separate list. The `_dirty` flag on each group triggers recoalescing when subscriptions change.

### ModbusRegisterSpec design: Immutable value class
**Rationale:** Specs are configuration data, not mutable state. Making them immutable (final fields, no setters) prevents accidental mutation during runtime. Equality based on `key` for map operations.

### Poll group naming: Free-form strings, lazy creation, 'default' fallback
**Rationale:** Maximum flexibility for the user. If a spec references poll group 'fast' and no such group exists, create it with the default interval (1s). Allow explicit configuration via `addPollGroup()` for custom intervals. This avoids requiring poll group pre-registration while still supporting named groups.

## Sources

### Primary (HIGH confidence)
- `packages/modbus_client/lib/src/modbus_element.dart` -- ModbusElement base class, getReadRequest(), setValueFromBytes()
- `packages/modbus_client/lib/src/element_type/modbus_element_num.dart` -- All numeric register types (Int16 through Double), byte parsing, byteCount values
- `packages/modbus_client/lib/src/element_type/modbus_element_bit.dart` -- ModbusBitElement, ModbusCoil, ModbusDiscreteInput, boolean parsing
- `packages/modbus_client/lib/src/modbus_element_group.dart` -- ModbusElementsGroup, batch reads, address range calculation, 125/2000 limits, response parsing
- `packages/modbus_client/lib/src/modbus_request.dart` -- ModbusReadGroupRequest.internalSetElementData() -- per-element value extraction from batch response
- `packages/modbus_client/lib/modbus_client.dart` -- ModbusElementType (coil, discreteInput, holdingRegister, inputRegister), ModbusResponseCode enum
- `packages/modbus_client_tcp/lib/src/modbus_client_tcp.dart` -- ModbusClientTcp.send() API, response handling
- `packages/tfc_dart/lib/core/modbus_client_wrapper.dart` -- Existing Phase 4 wrapper (connection lifecycle, BehaviorSubject status, factory injection)
- `packages/tfc_dart/test/core/modbus_client_wrapper_test.dart` -- Existing Phase 4 tests and MockModbusClient
- `packages/tfc_dart/lib/core/collector.dart` -- Timer.periodic polling pattern (line 198)
- `packages/tfc_dart/lib/core/state_man.dart` -- DeviceClient interface, DynamicValue type, ConnectionStatus enum

### Secondary (MEDIUM confidence)
- `packages/modbus_client_tcp/test/modbus_test_server.dart` -- Test server with MBAP response construction helpers (useful if integration tests desired later)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries are local forks already in use, APIs verified from source code
- Architecture: HIGH -- patterns (Timer.periodic, BehaviorSubject, factory injection) are established in codebase (Collector, Phase 4 wrapper)
- Pitfalls: HIGH -- identified from direct source code analysis of ModbusElementsGroup constraints, ModbusElement statefulness, and Timer.periodic behavior
- Data type mapping: HIGH -- every ModbusElement subclass verified against the actual source code with byte counts and parse methods confirmed

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable -- all dependencies are local forks under project control)
