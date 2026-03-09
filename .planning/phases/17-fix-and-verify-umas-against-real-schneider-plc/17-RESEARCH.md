# Phase 17: Fix and Verify UMAS Against Real Schneider PLC - Research

**Researched:** 2026-03-09
**Domain:** UMAS protocol debugging/verification against real Schneider hardware; Dart test infrastructure for hardware integration
**Confidence:** HIGH (critical protocol bugs identified with mspec evidence)

## Summary

The UMAS implementation from Phase 14 was built and unit-tested against a Python stub server that echoes canned responses. Comparing the current Dart implementation against the authoritative Apache PLC4X mspec (protocol specification) reveals **three critical bugs** that will prevent communication with a real Schneider PLC:

1. **Incomplete 0x26 request payload** -- The current code sends only 2 bytes (record type) but the PLC expects 13 bytes: `recordType(2) + index(1) + hardwareId(4) + blockNo(2) + offset(2) + blank(2)`. A real PLC will reject or misparse this.

2. **No pagination support** -- The current code sends a single 0x26 request and expects the complete variable list in one response. PLC4X uses an offset-based pagination loop (`while offset != 0x0000 or first_message`), because real PLCs with many variables split the dictionary across multiple responses. The `range`/`nextAddress`/`noOfRecords` fields in the response header are not parsed.

3. **Missing init sequence data extraction** -- The init response contains `hardwareId`, `index` (from memory block identification via 0x02), and `maxFrameSize` that are required as parameters for subsequent 0x26 requests. The current code only extracts `maxFrameSize` and ignores the rest. It also does not call 0x02 (Read PLC ID) at all, which provides the `hardwareId` and `index` values needed by 0x26.

The stub server accepted the simplified requests because it was designed to match the (incorrect) implementation rather than real PLC behavior. This phase must fix the protocol implementation, write live hardware integration tests against the real Schneider PLC at 10.50.10.123, and update the stub server to match correct protocol behavior.

**Primary recommendation:** Fix the UmasClient to implement the full PLC4X-verified init sequence (0x01 -> 0x02 -> 0x26 with pagination), write live integration tests that skip by default but run with `--run-skipped` against 10.50.10.123, and update the stub server and existing unit tests to match the corrected protocol.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| modbus_client_tcp (fork) | local | TCP transport for FC90 frames | Already handles MBAP framing, FC90 large-frame exemption (65535 bytes) |
| modbus_client (fork) | local | Base ModbusRequest for UmasRequest | Already supports FunctionType.custom |
| dart:typed_data | built-in | ByteData for LE payload parsing | Standard Dart |
| test | ^1.25 | Pure Dart test framework | User requirement: tests in pure Dart, not Flutter |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| dart:io | built-in | Socket/Process for live tests | For network connectivity checks before live tests |
| dart:convert | built-in | UTF-8 string encoding | Variable name parsing from PLC responses |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Live test with `--run-skipped` | Always-running live tests | Would fail in CI without PLC; skip pattern matches existing modbus_live_test.dart |
| Manual Wireshark capture | Automated packet logging | Wireshark gives full visibility during initial debugging |

**No new packages needed.**

## Architecture Patterns

### Recommended Project Structure
```
packages/tfc_dart/lib/core/
  umas_client.dart          # Fix: full init sequence, pagination, correct request format
  umas_types.dart           # Fix: add UmasPlcIdent type for 0x02 response data
packages/tfc_dart/test/core/
  umas_client_test.dart     # Update: match corrected protocol format
test/
  umas_stub_server.py       # Update: match corrected protocol format
packages/tfc_dart/test/
  umas_live_test.dart       # NEW: live hardware integration tests (skip by default)
```

### Pattern 1: PLC4X-Verified Init Sequence
**What:** The correct initialization sequence that real Schneider PLCs require before data dictionary access.
**When to use:** Every time UmasClient.browse() is called.
**Sequence (from PLC4X UmasDevice.connect + _update_plc_project_info):**
1. `0x02` - Read PLC Identification (get hardwareId, memory block info, index)
2. `0x01` - Init Communications (get maxFrameSize, set pairing key)
3. `0x26` with `recordType=0xDD03` - Read data type definitions (paginated loop)
4. For each UDT (classIdentifier==2): read UDT member definitions
5. `0x26` with `recordType=0xDD02` - Read variable names (paginated loop)
6. Build variable tree from collected data

### Pattern 2: Offset-Based Pagination for 0x26
**What:** The data dictionary may be too large for one response. The PLC returns a chunk of records plus a `nextAddress` continuation marker. When `nextAddress` is 0x0000 (after the first request), pagination is complete.
**When to use:** All 0x26 requests (both DD02 and DD03).
**Example (from PLC4X):**
```dart
// Paginated data dictionary reading
Future<List<UmasVariable>> readAllVariableNames() async {
  final allVars = <UmasVariable>[];
  int offset = 0x0000;
  bool firstMessage = true;

  while (offset != 0x0000 || firstMessage) {
    firstMessage = false;
    final (nextOffset, vars) = await _sendReadVariableNamesRequest(offset);
    allVars.addAll(vars);
    offset = nextOffset;
  }

  return allVars;
}
```

### Pattern 3: Correct 0x26 Request Format
**What:** The full request payload that matches the PLC4X mspec.
**Wire format (from PLC4X mspec UmasPDUReadUnlocatedVariableNamesRequest):**
```
[uint16 LE] recordType     -- 0xDD02 for variable names, 0xDD03 for data types
[uint8]     index          -- from PlcMemoryBlockIdent (0x02 response)
[uint32 LE] hardwareId     -- from PlcMemoryBlockIdent (0x02 response)
[uint16 LE] blockNo        -- 0xFFFF for DD02, pagination offset for DD03
[uint16 LE] offset         -- pagination offset for DD02, 0x0000 for DD03
[uint16 LE] blank          -- always 0x0000
```
Total: 13 bytes payload (vs current 2 bytes)

### Pattern 4: Correct 0x26 Response Format
**What:** The response has a structured header before the record data.
**Wire format (from PLC4X mspec):**
```
For DD02 (UmasPDUReadUnlocatedVariableNamesResponse):
  [uint8]   range         -- next pagination marker
  [uint16]  nextAddress   -- continuation offset (0 = done)
  [uint16]  unknown1
  [uint16]  noOfRecords   -- number of variable records that follow
  [array]   records       -- UmasUnlocatedVariableReference[]

Each UmasUnlocatedVariableReference:
  [uint16 LE] dataType
  [uint16 LE] block
  [uint16 LE] offset
  [uint16 LE] unknown4
  [uint16 LE] stringLength
  [vstring]   value       -- null-terminated variable name

For DD03 (UmasPDUReadDatatypeNamesResponse):
  [uint8]   range         -- next pagination marker
  [uint16]  nextAddress   -- continuation offset (0 = done)
  [uint8]   unknown1
  [uint16]  noOfRecords   -- number of type records that follow
  [array]   records       -- UmasDatatypeReference[]

Each UmasDatatypeReference:
  [uint16 LE] dataSize
  [uint16 LE] unknown1
  [uint8]     classIdentifier  -- 2=UDT/struct, 4=array
  [uint8]     dataType
  [uint8]     stringLength
  [vstring]   value       -- null-terminated type name
```

### Pattern 5: Skip-By-Default Live Test
**What:** Tests that require real hardware are skipped by default, run with `--run-skipped`.
**When to use:** All tests against the Schneider PLC at 10.50.10.123.
**Example (matches existing modbus_live_test.dart pattern):**
```dart
const _host = '10.50.10.123';
const _port = 502;

void main() {
  group('UMAS Live @ $_host:$_port', () {
    test('init() returns valid maxFrameSize', () async {
      final tcp = ModbusClientTcp(_host, serverPort: _port, ...);
      await tcp.connect();
      final umas = UmasClient(sendFn: tcp.send);
      final result = await umas.init();
      expect(result.maxFrameSize, greaterThan(0));
      await tcp.disconnect();
    }, skip: 'Live test — requires Schneider PLC at $_host');
  });
}
```

### Anti-Patterns to Avoid
- **Testing only against the stub:** The stub was designed around the (incorrect) implementation. Fix the stub to match the corrected protocol, but also test against real hardware.
- **Assuming one response = all data:** Real PLCs paginate. The stub returning everything in one shot masked this bug.
- **Hardcoding blockNo/offset:** These values come from the PLC's 0x02 response and vary by PLC model and project.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| UMAS wire format | Guess the byte layout | PLC4X mspec as reference | Only authoritative source for the actual protocol |
| Pagination logic | Single-request assumption | PLC4X's offset loop pattern | Real PLCs with 50+ variables will paginate |
| Init sequence | Simplified init | Full 0x02 -> 0x01 -> 0x26 chain | PLC requires hardwareId and index from 0x02 |
| MBAP framing | Custom TCP | Existing ModbusClientTcp.send() | Already handles transaction IDs, FC90 exemption |

**Key insight:** The PLC4X Python implementation is the de facto reference. Its mspec defines the wire format, and the Python driver demonstrates the correct init/browse sequence with pagination. Every deviation from PLC4X's approach should be treated as suspect until verified against real hardware.

## Common Pitfalls

### Pitfall 1: Request Payload Too Short
**What goes wrong:** PLC receives 2-byte payload instead of 13-byte payload for 0x26 request.
**Why it happens:** Current implementation sends only `[0x02, 0xDD]` (record type) but PLC expects recordType + index + hardwareId + blockNo + offset + blank.
**How to avoid:** Build the full 13-byte payload per PLC4X mspec.
**Warning signs:** PLC returns error (0xFD status), timeout, or garbled response.

### Pitfall 2: Missing Pagination Causes Incomplete Variable List
**What goes wrong:** Only first batch of variables retrieved; rest silently lost.
**Why it happens:** No loop checking nextAddress/range for continuation.
**How to avoid:** Implement the `while (offset != 0x0000 || firstMessage)` pattern from PLC4X.
**Warning signs:** Variable count much lower than expected; missing variables in tree.

### Pitfall 3: Missing 0x02 (Read PLC ID) Step
**What goes wrong:** 0x26 request sent with wrong/zero hardwareId and index.
**Why it happens:** Current init() only calls 0x01 and extracts maxFrameSize. The hardwareId and memory block index come from 0x02 response.
**How to avoid:** Add readPlcId() method, call it before init(), store hardwareId and index.
**Warning signs:** Error response from PLC on 0x26 even when init succeeds.

### Pitfall 4: Response Header Parsing Mismatch
**What goes wrong:** Variable records are parsed from wrong byte offset because response header is not accounted for.
**Why it happens:** Current code assumes payload starts immediately after the 4-byte UMAS header (FC + pairing + status + subFunc). The actual 0x26 response has additional header fields: range(1) + nextAddress(2) + unknown(1-2) + noOfRecords(2).
**How to avoid:** Parse the response header first, then parse exactly noOfRecords records.
**Warning signs:** Garbled variable names, wrong blockNo/offset values, parse exceptions.

### Pitfall 5: Variable Record Format Difference
**What goes wrong:** Variable records parsed using wrong field order/sizes.
**Why it happens:** Current implementation uses: nameLen(2) + name + blockNo(2) + offset(2) + dataTypeId(2). PLC4X mspec uses: dataType(2) + block(2) + offset(2) + unknown4(2) + stringLength(2) + name (null-terminated). The field order is different.
**How to avoid:** Match PLC4X mspec field order exactly: dataType first, name last (null-terminated).
**Warning signs:** Data type IDs don't match known types, names contain binary garbage.

### Pitfall 6: Null-Terminated vs Length-Prefixed Strings
**What goes wrong:** Variable names parsed incorrectly.
**Why it happens:** PLC4X mspec uses `stringLength + vstring` (null-terminated strings), while current code uses `nameLen + UTF-8 bytes`. Real PLC responses may use null-terminated strings.
**How to avoid:** Parse stringLength field, then read that many bytes, handling potential null terminator.
**Warning signs:** Names have trailing null bytes, or are one byte too short/long.

## Code Examples

### Current (Broken) vs Corrected 0x26 Request

```dart
// CURRENT (broken): sends only 2 bytes
final request = UmasRequest(
  umasSubFunction: 0x26,
  pairingKey: _pairingKey,
  payload: Uint8List.fromList([0x02, 0xDD]),  // Just record type!
);

// CORRECTED: sends full 13-byte payload per PLC4X mspec
Uint8List _build0x26Payload({
  required int recordType,  // 0xDD02 or 0xDD03
  required int index,       // from 0x02 response
  required int hardwareId,  // from 0x02 response
  required int blockNo,     // 0xFFFF for DD02, pagination offset for DD03
  required int offset,      // pagination offset for DD02, 0x0000 for DD03
}) {
  final bd = ByteData(13);
  bd.setUint16(0, recordType, Endian.little);
  bd.setUint8(2, index);
  bd.setUint32(3, hardwareId, Endian.little);
  bd.setUint16(7, blockNo, Endian.little);
  bd.setUint16(9, offset, Endian.little);
  bd.setUint16(11, 0x0000, Endian.little); // blank
  return bd.buffer.asUint8List();
}
```

### Read PLC Identification (0x02) - New Method Needed

```dart
// Source: PLC4X mspec UmasPDUPlcIdentResponse
// Response fields:
//   range(2) + ident(4) + ... + numberOfMemoryBanks(1) +
//   PlcMemoryBlockIdent[] { address(2), blockType(uint8),
//   unknown(2), memoryLength(4) }
//
// We need: hardwareId (ident) and index (from memory banks)
Future<UmasPlcIdent> readPlcId() async {
  final request = UmasRequest(
    umasSubFunction: UmasSubFunction.readId.code,
    pairingKey: _pairingKey,
  );
  final code = await sendFn(request);
  // Parse response to extract hardwareId and memory block info
  // ...
}
```

### Paginated Browse - Corrected Implementation

```dart
// Source: PLC4X UmasDevice._update_plc_project_info
Future<List<UmasVariableTreeNode>> browse() async {
  final plcIdent = await readPlcId();  // NEW: get hardwareId + index
  await init();

  // Read data types (DD03) with pagination
  final dataTypes = <UmasDataTypeRef>[];
  int offset = 0x0000;
  bool firstMessage = true;
  while (offset != 0x0000 || firstMessage) {
    firstMessage = false;
    final result = await _readDataTypesPage(offset);
    dataTypes.addAll(result.records);
    offset = result.nextAddress;
  }

  // Read variable names (DD02) with pagination
  final variables = <UmasVariable>[];
  offset = 0x0000;
  firstMessage = true;
  while (offset != 0x0000 || firstMessage) {
    firstMessage = false;
    final result = await _readVariableNamesPage(offset);
    variables.addAll(result.records);
    offset = result.nextAddress;
  }

  return buildVariableTree(variables, dataTypes);
}
```

### Live Test Pattern (Pure Dart)

```dart
// Pattern from existing modbus_live_test.dart
@TestOn('vm')
library;

import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:test/test.dart';

const _host = '10.50.10.123';
const _port = 502;

void main() {
  late ModbusClientTcp tcp;

  setUp(() {
    tcp = ModbusClientTcp(
      _host,
      serverPort: _port,
      connectionTimeout: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    await tcp.disconnect();
  });

  test('full browse() reads variables from real PLC', () async {
    await tcp.connect();
    expect(tcp.isConnected, isTrue);

    final umas = UmasClient(sendFn: tcp.send);
    final tree = await umas.browse();

    expect(tree, isNotEmpty, reason: 'PLC should have at least one root node');
    // Print tree for manual verification
    void printTree(List<dynamic> nodes, [int depth = 0]) {
      for (final n in nodes) {
        print('${"  " * depth}${n.name} (${n.isFolder ? "folder" : n.dataType?.name ?? "??"})');
        printTree(n.children, depth + 1);
      }
    }
    printTree(tree);
  }, skip: 'Live test — requires Schneider PLC at $_host');
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Simplified 2-byte 0x26 payload | Full 13-byte payload with hardwareId, index, blockNo, offset | PLC4X mspec (current) | Required for real PLC communication |
| Single-response assumption | Offset-based pagination loop | PLC4X driver design | Required for PLCs with many variables |
| Skip 0x02 (Read PLC ID) | Full init: 0x02 -> 0x01 -> 0x26 | PLC4X UmasDevice.connect() | Required for obtaining hardwareId/index |
| nameLen + name + fields | dataType + block + offset + unknown + stringLength + name | PLC4X mspec | Real PLC response format |

**Key protocol differences found:**

| Aspect | Current (Stub) | Real PLC (PLC4X mspec) |
|--------|---------------|------------------------|
| 0x26 request payload | 2 bytes (record type only) | 13 bytes (recordType + index + hardwareId + blockNo + offset + blank) |
| 0x26 response header | None (records start at byte 0) | 5-7 bytes (range + nextAddress + unknown + noOfRecords) |
| Variable record format | nameLen(2) + name + blockNo(2) + offset(2) + typeId(2) | dataType(2) + block(2) + offset(2) + unknown(2) + strLen(2) + name |
| Data type record format | typeId(2) + nameLen(2) + name + byteSize(2) | dataSize(2) + unknown(2) + classId(1) + dataType(1) + strLen(1) + name |
| Pagination | None | offset-based loop until nextAddress == 0 |
| Pre-requisites for 0x26 | 0x01 only | 0x02 (plcIdent) then 0x01 (init) |

## Open Questions

1. **Exact 0x02 Response Field Layout**
   - What we know: PLC4X mspec defines UmasPDUPlcIdentResponse with fields including range, ident, numberOfMemoryBanks, and PlcMemoryBlockIdent array. The `ident` field (uint32) is used as `hardwareId`. The memory bank array provides `index`.
   - What's unclear: Which specific memory block index to use for data dictionary queries (PLC4X uses `self.index` set during `_send_plc_ident()`).
   - Recommendation: Start with index=0 and observe PLC behavior. Capture Wireshark traces to validate.

2. **Null-Terminated vs Length-Prefixed Strings**
   - What we know: PLC4X mspec uses `stringLength` + `vstring`. The vstring type may or may not include a null terminator.
   - What's unclear: Whether the null byte is counted in stringLength or is extra.
   - Recommendation: Parse stringLength bytes, strip any trailing null bytes. Test against real PLC output.

3. **UDT/Struct Member Resolution**
   - What we know: PLC4X makes additional requests for each data type with `classIdentifier==2` (UDTs/structs) to get their member definitions.
   - What's unclear: Whether the current key repository UI can handle nested struct types, or if leaf-only browsing is sufficient for v1.
   - Recommendation: For this phase, focus on elementary types. If real PLC has UDTs, log them but skip member expansion. This can be enhanced later.

4. **blockNo + offset -> Modbus Register Address Mapping**
   - What we know: The key repository currently calculates `address = blockNo + offset` (line 1437 in key_repository.dart). PLC4X uses a more complex scheme: `(block * 100000) + base_offset + offset` for sorting, and separate block/offset in read requests.
   - What's unclear: Whether `blockNo + offset` produces a valid Modbus holding register address for standard FC03 reads. UMAS variables may require UMAS sub-function 0x22 (READ_VARIABLES) instead of standard Modbus FC03.
   - Recommendation: Test with real PLC. Read a known variable via UMAS browse, note the blockNo/offset, then try reading the same value via standard FC03 at `blockNo + offset`. If it works, the mapping is correct. If not, UMAS 0x22 may be needed for ongoing reads.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | dart test (pure Dart, NOT flutter_test per user requirement) |
| Config file | packages/tfc_dart/pubspec.yaml (test dependency) |
| Quick run command | `cd /Users/jonb/Projects/tfc-hmi/packages/tfc_dart && dart test test/core/umas_client_test.dart` |
| Full suite command | `cd /Users/jonb/Projects/tfc-hmi/packages/tfc_dart && dart test` |
| Live test command | `cd /Users/jonb/Projects/tfc-hmi/packages/tfc_dart && dart test test/umas_live_test.dart --run-skipped` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIX-01 | 0x26 request sends full 13-byte payload | unit | `dart test test/core/umas_client_test.dart -x` | Exists (update) |
| FIX-02 | 0x02 (readPlcId) extracts hardwareId and index | unit | `dart test test/core/umas_client_test.dart -x` | Exists (extend) |
| FIX-03 | Paginated 0x26 reads accumulate across multiple responses | unit | `dart test test/core/umas_client_test.dart -x` | Exists (extend) |
| FIX-04 | Response header (range/nextAddress/noOfRecords) parsed before records | unit | `dart test test/core/umas_client_test.dart -x` | Exists (update) |
| FIX-05 | Variable record format matches mspec (dataType first, name last) | unit | `dart test test/core/umas_client_test.dart -x` | Exists (update) |
| FIX-06 | Data type record format matches mspec (classIdentifier, dataType fields) | unit | `dart test test/core/umas_client_test.dart -x` | Exists (update) |
| VER-01 | UmasClient.init() succeeds against real PLC | live (skip) | `dart test test/umas_live_test.dart --run-skipped` | Wave 0 |
| VER-02 | UmasClient.browse() returns variable tree from real PLC | live (skip) | `dart test test/umas_live_test.dart --run-skipped` | Wave 0 |
| VER-03 | Browse dialog shows real PLC variables in UI | manual | N/A | N/A |
| VER-04 | Selecting a UMAS variable fills correct address/type in key config | manual | N/A | N/A |

### Sampling Rate
- **Per task commit:** `dart test test/core/umas_client_test.dart`
- **Per wave merge:** `cd packages/tfc_dart && dart test`
- **Phase gate:** All unit tests green + live tests pass with `--run-skipped` against 10.50.10.123

### Wave 0 Gaps
- [ ] `packages/tfc_dart/test/umas_live_test.dart` -- live hardware integration tests (pure Dart)
- [ ] Update `test/umas_stub_server.py` to match corrected protocol format
- [ ] Update `packages/tfc_dart/test/core/umas_client_test.dart` to match corrected wire format

## Sources

### Primary (HIGH confidence)
- [Apache PLC4X UMAS mspec](https://github.com/apache/plc4x/blob/develop/protocols/umas/src/main/resources/protocols/umas/umas.mspec) -- Authoritative wire format definitions for UmasPDUReadUnlocatedVariableNamesRequest, Response, UmasUnlocatedVariableReference, UmasDatatypeReference
- [Apache PLC4X UmasDevice.py](https://github.com/apache/plc4x/blob/develop/plc4py/plc4py/drivers/umas/UmasDevice.py) -- Working Python implementation with pagination loop, init sequence (0x02 -> 0x01 -> 0x26), and variable tree building
- [Apache PLC4X UmasVariables.py](https://github.com/apache/plc4x/blob/develop/plc4py/plc4py/drivers/umas/UmasVariables.py) -- Variable type hierarchy (elementary, custom/UDT, array) and address calculation
- Existing codebase: `umas_client.dart` (319 lines), `umas_types.dart` (155 lines), `umas_client_test.dart` (261 lines), `umas_e2e_test.dart` (203 lines), `umas_browse.dart` (131 lines), `umas_stub_server.py` (183 lines)

### Secondary (MEDIUM confidence)
- [Kaspersky ICS CERT Report](https://ics-cert.kaspersky.com/publications/reports/2022/09/29/the-secrets-of-schneider-electrics-umas-protocol/) -- Function code list, session management, response status codes (0xFE=success, 0xFD=error)
- [Liras en la red blog Part II](http://lirasenlared.blogspot.com/2017/08/the-unity-umas-protocol-part-ii.html) -- Memory block reading (0x20), shifted CRC for 0x22, system bits/words addressing
- [Zaltzman UMAS Wireshark Dissector](https://github.com/zaltzman/UMAS-Wireshark-Dissector) -- 24+ function codes with parsing logic
- [PLC4X UMAS Documentation](https://plc4x.incubator.apache.org/plc4x/pre-release/users/protocols/umas.html) -- Driver overview, Data Dictionary requirement

### Tertiary (LOW confidence)
- [Weintek M340/M580 Symbolic Addressing Guide](https://dl.weintek.com/public/PLC_Connect_Guide/Schneider_M340_M580_Series_Symbolic_Addressing_Ethernet.pdf) -- Data Dictionary enable instructions (Tools > Project Settings > PLC embedded data)
- [John Wiltshire UMAS Protocol Explained](https://johnwiltshire.com/umas-protocol-explained/) -- Protocol overview and thesis reference

## Metadata

**Confidence breakdown:**
- Protocol bugs identified: HIGH -- PLC4X mspec provides exact wire format; diff against current code is clear
- Pagination requirement: HIGH -- PLC4X implementation demonstrates the loop; current code has none
- Init sequence gaps: HIGH -- PLC4X calls 0x02 before 0x26; current code skips 0x02 entirely
- Exact response field sizes: MEDIUM -- mspec is authoritative but may have edge cases with specific firmware versions
- Address mapping (blockNo+offset -> FC03 register): LOW -- needs real hardware verification

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (UMAS protocol is stable, low churn)
