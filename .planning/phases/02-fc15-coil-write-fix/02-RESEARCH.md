# Phase 2: FC15 Coil Write Fix - Research

**Researched:** 2026-03-06
**Domain:** Modbus base library fork (Dart, modbus_client 1.4.4 — `getMultipleWriteRequest` bug)
**Confidence:** HIGH

## Summary

The bug is in `getMultipleWriteRequest` in `modbus_element.dart` line 109. It uses `bytes.length ~/ 2` for the FC15 quantity field, which is correct for FC16 (holding registers — 2 bytes per register) but wrong for FC15 (coils — 1 bit per coil, packed). For coils, the quantity field must equal the number of coils, not the number of packed bytes divided by two.

**Every coil count is broken.** For 1-8 coils `bytes.length ~/ 2 = 0`. For 9-15 coils it returns 1. For 16 coils it returns 1. For 32 coils it returns 2. Only by accident of matching does any value come close. Since `ModbusBitElement` never calls `getMultipleWriteRequest` today (it only supports single-coil FC05 writes via `getWriteRequest`), the method has never been exercised for FC15. Phase 6 (WRIT-04) will need it to work correctly.

The fix is a one-line change: add an optional `quantity` parameter to `getMultipleWriteRequest`. When provided, use it for the PDU quantity field; when absent, fall back to `bytes.length ~/ 2` (preserving FC16 correctness). Tests inspect PDU bytes directly — no TCP socket needed for the unit tests.

**Primary recommendation:** Fork `modbus_client` 1.4.4 into `packages/modbus_client/`, fix the one-line bug with the quantity parameter approach, update `modbus_client_tcp/pubspec.yaml` to depend on the local fork, and write PDU-byte unit tests following the pattern established in `modbus_client-1.4.4/test/modbus_endianness_test.dart`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Skip diagnosis — the code is clearly wrong for coils (`bytes.length ~/ 2` != coil count when coils > 15)
- Go straight to fix + test (TDD: write failing test first)
- Fork entire `modbus_client` package (v1.4.4) from pub cache into `packages/modbus_client/`
- Same pattern as Phase 1's `modbus_client_tcp` fork — enables TDD, version control, CI
- Update `modbus_client_tcp/pubspec.yaml` to use `path: ../modbus_client` (local dep chain)
- Fork the full package, not a minimal subset — future phases (especially Phase 6: Writing) will need more of it
- Full round-trip: test PDU encoding AND mock server response parsing
- Test boundary cases: 1-15 coils (regression) AND 16, 17, 32, 64 coils (the broken cases)

### Claude's Discretion
- Fix architecture: type-aware quantity parameter vs override in subclass
- Whether to add byte count validation (assert `bytes.length == ceil(quantity / 8)` for coils)
- Test infrastructure details
- Upstream coordination (not important right now)

### Deferred Ideas (OUT OF SCOPE)
- Group write capability (`ModbusWriteGroupRequest`) — commented out in `modbus_element_group.dart`, could be its own phase or part of Phase 6
- Upstream contribution to `modbus_client` pub.dev package — fix locally first, consider PR later
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LIBFIX-01 | FC15 (Write Multiple Coils) correctly reports quantity for 16+ coils | Bug located at `modbus_element.dart:109` — `setUint16(3, bytes.length ~/ 2)`. Fix: add optional `quantity` parameter, use it when provided. Full byte layout documented below. |
| TEST-02 | modbus_client fork FC15 fix has regression test for 16+ coils | Test pattern: inspect `request.protocolDataUnit` bytes directly (no TCP needed). Existing `modbus_endianness_test.dart` shows exact pattern. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| modbus_client | 1.4.4 (local fork in `packages/modbus_client/`) | Base Modbus protocol types, elements, request classes | The library being fixed. Single-file bug in `modbus_element.dart`. |
| modbus_client_tcp | 1.2.3 (local fork, Phase 1) | TCP transport — depends on modbus_client | Must update dep from pub.dev to `path: ../modbus_client` |
| test | ^1.21.0 (already in modbus_client dev_deps) | Dart test framework | Already in the upstream package's dev_dependencies |
| dart:typed_data | SDK | `Uint8List`, `ByteData` for PDU byte inspection | Already used throughout the library |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| collection | ^1.17.1 | Already a modbus_client dep | No changes needed |
| synchronized | ^3.1.0+1 | Already a modbus_client dep | No changes needed |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Optional `quantity` parameter | Override `getMultipleWriteRequest` in `ModbusBitElement` | Override approach: `ModbusBitElement` can override the method but the quantity (bit count) is not recoverable from packed bytes — you'd have to track it externally. Parameter approach is cleaner. |
| Parameter approach | `type.isBit` check inside the base method | Would need to compute quantity from byte count for bits, but `ceil(bytes.length * 8)` is wrong (can't know how many bits were in the last byte). Parameter is the only accurate approach. |
| Local fork | Pub cache patch | Pub cache patches are lost on `dart pub get`. Fork for version control and CI. |

**Installation (copy from pub cache):**
```bash
cp -r ~/.pub-cache/hosted/pub.dev/modbus_client-1.4.4 packages/modbus_client
```

## Architecture Patterns

### Recommended Project Structure
```
packages/modbus_client/
├── lib/
│   ├── modbus_client.dart                    # Barrel export (unchanged)
│   └── src/
│       ├── modbus_element.dart               # FIX TARGET: getMultipleWriteRequest
│       ├── modbus_request.dart               # Unchanged
│       ├── modbus_client.dart                # Unchanged
│       ├── modbus_element_group.dart         # Unchanged
│       ├── modbus_app_logger.dart            # Unchanged
│       ├── modbus_file_record.dart           # Unchanged
│       └── element_type/
│           ├── modbus_element_bit.dart       # Unchanged (no getMultipleWriteRequest override)
│           ├── modbus_element_num.dart       # Unchanged
│           └── ...
├── test/
│   └── modbus_fc15_test.dart                 # NEW: FC15 bug regression + fix tests
├── pubspec.yaml                              # Unchanged (already has test: ^1.21.0 in dev_deps)
└── CHANGELOG.md
```

### Pattern 1: PDU Byte Inspection Test (from existing `modbus_endianness_test.dart`)

**What:** Inspect `request.protocolDataUnit` bytes directly to verify correct encoding, without any network I/O.

**When to use:** All FC15 PDU encoding tests. This is the established pattern in the upstream library.

**Example (from `modbus_endianness_test.dart`):**
```dart
// Source: /Users/jonb/.pub-cache/hosted/pub.dev/modbus_client-1.4.4/test/modbus_endianness_test.dart
var write = reg.getWriteRequest(num);
expect(write.protocolDataUnit.sublist(6), bytes);  // inspect raw PDU bytes
```

### Pattern 2: FC15 PDU Byte Layout

**FC15 Write Multiple Coils — Request PDU structure:**
```
[0]     = 0x0F          (function code)
[1][2]  = address       (uint16 big-endian, starting coil address)
[3][4]  = quantity      (uint16 big-endian, NUMBER OF COILS — THE BUG IS HERE)
[5]     = byte count    (ceil(quantity / 8))
[6..N]  = packed bits   (coil values, one bit per coil, LSB first per byte)
```

**FC15 Response PDU structure (echoed by server):**
```
[0]     = 0x0F          (function code echo)
[1][2]  = address       (starting address echo)
[3][4]  = quantity      (coil count echo)
Total = 5 bytes (matches ModbusWriteRequest.responsePduLength = 5)
```

**Example verifying the fix for 16 coils:**
```dart
// Source: analysis of modbus_element.dart:95-115
var coil = ModbusCoil(name: 'c', address: 0);
// Pack 16 coils into 2 bytes (all ON = 0xFF, 0xFF)
var bytes = Uint8List.fromList([0xFF, 0xFF]);
var req = coil.getMultipleWriteRequest(bytes, quantity: 16);
var pdu = req.protocolDataUnit;
// [0] = 0x0F (FC15)
expect(pdu[0], equals(0x0F));
// [1][2] = address = 0
expect(ByteData.view(pdu.buffer).getUint16(1), equals(0));
// [3][4] = quantity = 16 (THE FIX — was: bytes.length ~/ 2 = 1)
expect(ByteData.view(pdu.buffer).getUint16(3), equals(16));
// [5] = byte count = 2
expect(pdu[5], equals(2));
// [6][7] = packed bits = 0xFF, 0xFF
expect(pdu[6], equals(0xFF));
expect(pdu[7], equals(0xFF));
```

### Pattern 3: Response Parsing Test (without TCP)

**What:** Simulate server response by calling `request.setFromPduResponse()` directly.

**When to use:** "Round-trip" test that also verifies the client handles FC15 response correctly.

```dart
// Craft a valid FC15 response PDU (5 bytes: FC + address + quantity)
var coil = ModbusCoil(name: 'c', address: 0);
var bytes = Uint8List.fromList([0xFF, 0xFF]);
var req = coil.getMultipleWriteRequest(bytes, quantity: 16);

// Simulate server echoing back: FC=0x0F, address=0x00 0x00, quantity=0x00 0x10
var responsePdu = Uint8List.fromList([0x0F, 0x00, 0x00, 0x00, 0x10]);
req.setFromPduResponse(responsePdu);
// Expect success (completer resolves with requestSucceed)
final code = await req.responseCode;
expect(code, equals(ModbusResponseCode.requestSucceed));
```

### The Bug (precise location)

```dart
// Source: /Users/jonb/.pub-cache/hosted/pub.dev/modbus_client-1.4.4/lib/src/modbus_element.dart:109
// Line 109 — CURRENT (WRONG for FC15):
..setUint16(3, bytes.length ~/ 2) // value register count

// THE FIX — add quantity parameter:
ModbusWriteRequest getMultipleWriteRequest(Uint8List bytes,
    {int? quantity,        // ADD: explicit coil count for FC15
     int? unitId, Duration? responseTimeout, ModbusEndianness? endianness}) {
  // ...
  ..setUint16(3, quantity ?? bytes.length ~/ 2)  // coil count OR register count
```

### Quantity Bug Table (all counts)

| Coil count | bytes.length | Wrong quantity (current) | Correct quantity (fix) |
|-----------|--------------|--------------------------|------------------------|
| 1 | 1 | 0 | 1 |
| 8 | 1 | 0 | 8 |
| 9 | 2 | 1 | 9 |
| 15 | 2 | 1 | 15 |
| 16 | 2 | 1 | 16 |
| 17 | 3 | 1 | 17 |
| 32 | 4 | 2 | 32 |
| 64 | 8 | 4 | 64 |

**ALL coil counts are wrong.** The CONTEXT's "16 or more coils" focus is where the symptom is most obvious, but the math is broken for all values since byte packing means you can't recover coil count from byte count alone.

### FC16 Backward Compatibility

FC16 (Write Multiple Holding Registers) uses `bytes.length ~/ 2` correctly because each register is exactly 2 bytes. Callers that use `getMultipleWriteRequest` for registers DO NOT pass `quantity`, so the fallback `bytes.length ~/ 2` is used — preserving existing behavior.

**Affected callers (must NOT break):**
- `ModbusNumRegister.getWriteRequest` — calls `getMultipleWriteRequest(_toBytes(numValue))` for int32/uint32/float64 etc.
- `ModbusBytesElement.getWriteRequest` — calls `getMultipleWriteRequest(value)` directly

### Anti-Patterns to Avoid

- **Recovering quantity from bytes in the base class:** `bytes.length * 8` gives max possible coils, not actual coils (last byte may be partially used). The caller must pass the count.
- **Patching pub cache:** Changes lost on `dart pub get`. Always fork into `packages/`.
- **Writing FC15 tests that require a live TCP connection:** PDU byte inspection is sufficient and faster. The `modbus_endianness_test.dart` establishes this pattern.
- **Overriding `getMultipleWriteRequest` in `ModbusBitElement`:** Can't recover bit count from packed bytes inside the override. Parameter approach is the only accurate fix.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Coil bit packing | Custom bit-packing logic | Caller provides pre-packed `Uint8List bytes` | API contract: caller packs, library encodes. Don't add packing to this method. |
| Byte count validation | Assert in base class | Optional: assert `bytes.length == (quantity + 7) ~/ 8` if quantity provided | Standard Dart assert, not custom logic |
| Test TCP server | `ModbusTestServer` from Phase 1 | Direct PDU byte inspection | FC15 is a base library concern; no TCP needed for these unit tests |
| Response quantity validation | Parse server's echoed quantity | Current behavior (no validation) is acceptable | The library trusts the server echo; quantity correctness is guaranteed by our correct PDU encoding |

**Key insight:** The fix is literally one line. The surrounding infrastructure (fork, dep update, test setup) is the main task.

## Common Pitfalls

### Pitfall 1: Forgetting to Update modbus_client_tcp's Dependency
**What goes wrong:** `modbus_client_tcp/pubspec.yaml` still points to `modbus_client: ^1.4.2` from pub.dev. Tests in `packages/modbus_client/test/` pass, but any code that uses `modbus_client_tcp` still gets the unfixed pub.dev version of modbus_client.
**Why it happens:** Two separate package manifests, easy to update one and forget the other.
**How to avoid:** Update `modbus_client_tcp/pubspec.yaml` to `modbus_client: path: ../modbus_client` as part of the same task that creates the fork.
**Warning signs:** `dart pub get` in `modbus_client_tcp/` fetches from pub.dev, not the local fork.

### Pitfall 2: Regression on FC16 (Registers)
**What goes wrong:** Changing `getMultipleWriteRequest` breaks the existing behavior where callers don't pass `quantity` (for FC16 register writes).
**Why it happens:** Adding a required parameter or changing the fallback logic.
**How to avoid:** Make `quantity` optional with `int? quantity`. When `null`, use `bytes.length ~/ 2` (existing behavior). Run the existing `modbus_endianness_test.dart` tests to confirm no regression.
**Warning signs:** `ModbusNumRegister.getWriteRequest` tests fail after the change.

### Pitfall 3: Wrong Byte Count for Partial Coil Bytes
**What goes wrong:** The `byte count` field (`pdu[5]`) uses `bytes.length` which is already the pre-packed byte count from the caller. This is CORRECT — byte count = number of packed bytes.
**Why it happens:** Confusion between byte count (always `bytes.length`) and quantity (coil count, NOT `bytes.length`).
**How to avoid:** Only `setUint16(3, ...)` changes. `setUint8(5, bytes.length)` stays the same.
**Warning signs:** Tests fail because `pdu[5]` is wrong.

### Pitfall 4: Dart Part File Structure
**What goes wrong:** `modbus_element_bit.dart` uses `part of '../modbus_element.dart'` — it's a Dart "part" file, not a library. Adding imports to it directly will fail.
**Why it happens:** The bit element file looks like a normal Dart file but it's a part.
**How to avoid:** Any new imports needed for the fix go in `modbus_element.dart` (the main library file), not in the part files.
**Warning signs:** `Compiler error: 'import' directives must not appear in a part file`

### Pitfall 5: tfc_dart Transitive Dependency
**What goes wrong:** `tfc_dart` has a transitive dep on `modbus_client` via `modbus_client_tcp`. When `modbus_client_tcp` switches to `path: ../modbus_client`, Dart's pub correctly resolves transitively. But if there's a version conflict or if `tfc_dart` has its own `dependency_overrides`, resolution may fail.
**Why it happens:** Dart's pub tool resolves path deps relative to the declaring package — this is correct and works. But direct pub.dev conflicts can override path deps.
**How to avoid:** After updating `modbus_client_tcp/pubspec.yaml`, run `dart pub get` in both `modbus_client_tcp/` and `packages/tfc_dart/` to verify resolution succeeds.
**Warning signs:** `Resolving dependencies... Error: modbus_client >=1.4.2 doesn't match...`

## Code Examples

Verified patterns from actual source:

### Fix Location (`modbus_element.dart:95-115`)
```dart
// Source: /Users/jonb/.pub-cache/hosted/pub.dev/modbus_client-1.4.4/lib/src/modbus_element.dart:95-115

// BEFORE (current broken code):
ModbusWriteRequest getMultipleWriteRequest(Uint8List bytes,
    {int? unitId, Duration? responseTimeout, ModbusEndianness? endianness}) {
  if (type.writeMultipleFunction == null) {
    throw ModbusException(
        context: "ModbusBitElement",
        msg: "$type element does not support multiple write request!");
  }
  var pdu = Uint8List(6 + bytes.length);
  pdu.setAll(
      6, endianness == null ? bytes : endianness.getEndianBytes(bytes));
  ByteData.view(pdu.buffer)
    ..setUint8(0, type.writeMultipleFunction!.code)
    ..setUint16(1, address)
    ..setUint16(3, bytes.length ~/ 2)   // <-- BUG: wrong for FC15
    ..setUint8(5, bytes.length);
  return ModbusWriteRequest(this, pdu, type.writeMultipleFunction!,
      unitId: unitId,
      responseTimeout: responseTimeout,
      endianness: endianness ?? this.endianness);
}

// AFTER (fixed):
ModbusWriteRequest getMultipleWriteRequest(Uint8List bytes,
    {int? quantity,         // explicit coil/output count for FC15
     int? unitId, Duration? responseTimeout, ModbusEndianness? endianness}) {
  if (type.writeMultipleFunction == null) {
    throw ModbusException(
        context: "ModbusBitElement",
        msg: "$type element does not support multiple write request!");
  }
  var pdu = Uint8List(6 + bytes.length);
  pdu.setAll(
      6, endianness == null ? bytes : endianness.getEndianBytes(bytes));
  ByteData.view(pdu.buffer)
    ..setUint8(0, type.writeMultipleFunction!.code)
    ..setUint16(1, address)
    ..setUint16(3, quantity ?? bytes.length ~/ 2)   // <-- FIX: coil count when provided
    ..setUint8(5, bytes.length);                     // byte count unchanged
  return ModbusWriteRequest(this, pdu, type.writeMultipleFunction!,
      unitId: unitId,
      responseTimeout: responseTimeout,
      endianness: endianness ?? this.endianness);
}
```

### Test — PDU Encoding (no TCP)
```dart
// Source: Pattern from modbus_endianness_test.dart
import 'dart:typed_data';
import 'package:modbus_client/modbus_client.dart';
import 'package:test/test.dart';

group('FC15 Write Multiple Coils quantity (LIBFIX-01)', () {
  test('16 coils encodes quantity=16 in PDU bytes [3][4]', () {
    var coil = ModbusCoil(name: 'c', address: 100);
    var bytes = Uint8List.fromList([0xFF, 0xFF]); // 16 coils all ON
    var req = coil.getMultipleWriteRequest(bytes, quantity: 16);
    var pdu = req.protocolDataUnit;
    expect(pdu[0], equals(0x0F));                                   // FC15
    expect(ByteData.view(pdu.buffer).getUint16(1), equals(100));    // address
    expect(ByteData.view(pdu.buffer).getUint16(3), equals(16));     // quantity = 16
    expect(pdu[5], equals(2));                                       // byte count = 2
  });

  test('1 coil encodes quantity=1 (regression: was encoding 0)', () {
    var coil = ModbusCoil(name: 'c', address: 0);
    var bytes = Uint8List.fromList([0x01]); // 1 coil ON
    var req = coil.getMultipleWriteRequest(bytes, quantity: 1);
    expect(ByteData.view(req.protocolDataUnit.buffer).getUint16(3), equals(1));
  });

  test('FC16 regression: no quantity param preserves bytes.length ~/ 2', () {
    // 32-bit register = 4 bytes = 2 registers
    var reg = ModbusUint32Register(
        name: 'r', address: 0, type: ModbusElementType.holdingRegister);
    var req = reg.getWriteRequest(0x12345678);
    expect(req.protocolDataUnit[0], equals(0x10));  // FC16
    expect(ByteData.view(req.protocolDataUnit.buffer).getUint16(3), equals(2)); // 2 registers
  });
});
```

### Coil Bit Packing (for documentation of caller contract)
```dart
// Callers are responsible for packing coil values into bytes.
// Standard Modbus FC15 bit packing: LSB first within each byte, lower addresses first.
// Example: 16 coils, addresses 0-15, all ON:
//   Byte 0: coils 0-7  = 0xFF (all 8 bits set)
//   Byte 1: coils 8-15 = 0xFF (all 8 bits set)
//
// Example: 17 coils, addresses 0-16, all ON:
//   Byte 0: coils 0-7  = 0xFF
//   Byte 1: coils 8-15 = 0xFF
//   Byte 2: coil 16    = 0x01 (only bit 0 set, bits 1-7 are padding zeros)
var bytes = Uint8List(((quantity + 7) ~/ 8));  // ceil(quantity / 8)
// ... set bits ...
var req = coil.getMultipleWriteRequest(bytes, quantity: quantity);
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `bytes.length ~/ 2` for all `getMultipleWriteRequest` calls | `quantity ?? bytes.length ~/ 2` | This phase (LIBFIX-01) | FC15 works for any coil count |
| `modbus_client_tcp` depends on pub.dev `modbus_client` | `path: ../modbus_client` local fork | This phase | Local fork of base library is the source of truth |

**Upstream situation:** The pub.dev `modbus_client` 1.4.4 has this bug unfixed. There is a GitHub issue (#19) from the maintainer suggesting the caller should use `ModbusCoil` directly — but that doesn't expose a multi-coil write path. The bug is real and needs the local fix.

## Open Questions

1. **Should `ModbusBitElement` also override `getMultipleWriteRequest` for ergonomics?**
   - What we know: The base class fix with `quantity` parameter is sufficient. But callers must remember to pass `quantity` when using FC15.
   - What's unclear: Whether a type-safe override on `ModbusBitElement` (requiring `quantity`) would prevent footguns.
   - Recommendation: Claude's discretion. The base class parameter is the minimal correct fix. An override that makes `quantity` required for bit elements is nice but out of scope for this phase.

2. **Should byte count be validated when `quantity` is provided?**
   - What we know: `bytes.length` must equal `(quantity + 7) ~/ 8` for valid FC15 encoding.
   - What's unclear: Whether to assert this or silently trust the caller.
   - Recommendation: Claude's discretion. An `assert(bytes.length == (quantity + 7) ~/ 8)` in debug mode would catch bugs at development time without affecting production performance.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Dart `test` ^1.21.0 (already in `modbus_client-1.4.4/pubspec.yaml` dev_deps) |
| Config file | None — default test discovery |
| Quick run command | `cd /Users/jonb/Projects/tfc-hmi/packages/modbus_client && dart test` |
| Full suite command | `cd /Users/jonb/Projects/tfc-hmi/packages/modbus_client && dart test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LIBFIX-01 | FC15 quantity field = coil count (not `bytes.length ~/ 2`) | unit | `cd packages/modbus_client && dart test test/modbus_fc15_test.dart -n "FC15"` | No — Wave 0 |
| LIBFIX-01 | FC15 works for 1, 8, 9, 15 coils (all broken before fix) | unit | `cd packages/modbus_client && dart test test/modbus_fc15_test.dart -n "1 coil\|15 coils"` | No — Wave 0 |
| LIBFIX-01 | FC15 works for 16, 17, 32, 64 coils (primary broken cases) | unit | `cd packages/modbus_client && dart test test/modbus_fc15_test.dart -n "16\|17\|32\|64"` | No — Wave 0 |
| LIBFIX-01 | FC16 registers regression: `quantity` absent still uses `bytes.length ~/ 2` | unit | `cd packages/modbus_client && dart test test/modbus_fc15_test.dart -n "FC16 regression"` | No — Wave 0 |
| TEST-02 | Round-trip: FC15 response parsing via `setFromPduResponse()` | unit | `cd packages/modbus_client && dart test test/modbus_fc15_test.dart -n "response"` | No — Wave 0 |

### Sampling Rate
- **Per task commit:** `cd packages/modbus_client && dart test`
- **Per wave merge:** `cd packages/modbus_client && dart test && cd ../modbus_client_tcp && dart test`
- **Phase gate:** Both `modbus_client` and `modbus_client_tcp` test suites green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `packages/modbus_client/` — copy fork from pub cache: `cp -r ~/.pub-cache/hosted/pub.dev/modbus_client-1.4.4 packages/modbus_client`
- [ ] `packages/modbus_client/test/modbus_fc15_test.dart` — all FC15 test groups (encoding, boundary cases, FC16 regression, response parsing)
- [ ] `packages/modbus_client_tcp/pubspec.yaml` — change `modbus_client: ^1.4.2` to `modbus_client:\n  path: ../modbus_client`

*(If no gaps: "None — existing test infrastructure covers all phase requirements")*

## Sources

### Primary (HIGH confidence)
- **Actual bug location:** `/Users/jonb/.pub-cache/hosted/pub.dev/modbus_client-1.4.4/lib/src/modbus_element.dart:109` — read directly
- **FC15 PDU layout:** Modbus spec (derived from modbus_request.dart comments and function code definitions in modbus_client.dart) — verified from source
- **Test pattern:** `/Users/jonb/.pub-cache/hosted/pub.dev/modbus_client-1.4.4/test/modbus_endianness_test.dart` — read directly; establishes PDU byte inspection pattern
- **Existing callers of `getMultipleWriteRequest`:** `modbus_element_num.dart` and `modbus_element_bytes.dart` — confirmed neither passes `quantity`, so fallback preserves FC16 behavior
- **Phase 1 test infrastructure:** `/Users/jonb/Projects/tfc-hmi/packages/modbus_client_tcp/test/` — read directly; available as reference but not needed for FC15 unit tests

### Secondary (MEDIUM confidence)
- [Modbus FC15 specification (Write Multiple Coils)](https://modbus.org/docs/Modbus_Application_Protocol_V1_1b3.pdf) — response PDU = 5 bytes (FC + address + quantity), consistent with `ModbusWriteRequest.responsePduLength = 5` in the library

### Tertiary (LOW confidence)
- None — all findings verified directly from source code

## Metadata

**Confidence breakdown:**
- Bug diagnosis: HIGH — read the exact line, verified the math for all coil counts
- Fix approach: HIGH — optional parameter is the only approach that works; callers of FC16 don't break
- Test approach: HIGH — existing `modbus_endianness_test.dart` establishes the exact pattern to follow
- Dependency chain: HIGH — read all three pubspec.yaml files; path dep chain is straightforward

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable — upstream library at 1.4.4, no active development observed)
