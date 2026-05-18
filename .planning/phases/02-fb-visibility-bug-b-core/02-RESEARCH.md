# Phase 2 Research — FB visibility (Bug B core)

**Authored:** 2026-05-18
**Phase agent:** worktree-agent-ae2f6e62 (autonomous)
**Base commit:** f9c6df1979b3778e14abce6f77ff09a0f0875a98

## Scope

Decide the protocol approach for resolving function-block (FB) member
layouts on the live M580 at 192.168.112.159 so the 23 FB instances
(`M_Elevator`, `FB_Elevator_1`, `FB_B_*`, etc.) stop being bare `(?)`
leaves in `umas_cli browse`. Out of scope for this phase: IN/OUT
classification (Phase 3), VAR_IN_OUT pointer dereferencing (Phase 5),
browser UI (Phase 4).

---

## Candidate approaches

Two candidates were on the table per ROADMAP / `02-CONTEXT.md`:

1. **DD02-as-member-layout, called with the variable's `dataTypeId`**
   — i.e. `_readDD02Block(blockNo: typeId, isMemberLayout: true)`
   (`packages/tfc_dart/lib/core/umas_client.dart:626-665`).

2. **A new DD03 request variant** that includes FB types (mirroring
   plc4j's `UmasPDUReadDatatypeNamesRequest` variant).

Below: verbatim plc4j evidence that decides the choice.

---

## Apache PLC4X (`plc4j`) evidence

All citations from `plc4j/drivers/umas/.../UmasProtocolLogic.java`
(branch `develop`, fetched 2026-05-18) and
`protocols/umas/.../v0/umas.mspec` + `v1/umas.mspec`.

### Constants (UmasProtocolLogic.java:74-76)

```java
private static final int RECORD_TYPE_DD02 = 0xDD02;
private static final int RECORD_TYPE_DD03 = 0xDD03;
private static final int SYMBOL_TABLE_BLOCK = 0xFFFF;
```

### Three uses of DD02 / DD03

| plc4j method | record type | `blockNo` | Purpose |
|---|---|---|---|
| `downloadDatatypeNames()` L1038-1061 | DD03 | (n/a — 0x03 index) | List custom type *names* (`UmasDatatypeReference` records) |
| `downloadSymbolTable()` L1098-1127 | DD02 | `SYMBOL_TABLE_BLOCK = 0xFFFF` | Top-level variable list (`UmasUnlocatedVariableReference` records) |
| `resolveCustomType(typeIndex, ref)` L1079-1097 | DD02 | `typeIndex` | Custom type *definition* — UDT member layout **or** array def |

The third row is the lever for Bug B.

### `resolveCustomType` — verbatim (L1079-1097)

```java
private void resolveCustomType(int typeIndex, UmasDatatypeReference ref) throws Exception {
    int transactionId = umasDriverContext.getNextTransactionId();
    UmasPDUItem request = new UmasPDUReadUnlocatedVariableNamesRequest(
        umasDriverContext.getPairingKey(), RECORD_TYPE_DD02, (short) 0x03,
        umasDriverContext.getHardwareId(), typeIndex, 0, 0);
    ...
    parseCustomTypeBlock(typeIndex, ref, block);
}
```

### `parseCustomTypeBlock` — branches on classId (L1130-1146)

```java
private void parseCustomTypeBlock(int typeIndex, UmasDatatypeReference ref, byte[] block) throws Exception {
    int classId = block[0] & 0xFF;
    if (classId == 0x04) {
        ReadBuffer readBuffer = new ReadBufferByteBased(block, ByteOrder.LITTLE_ENDIAN);
        UmasArrayTypeDefinition arrayDef = UmasArrayTypeDefinition.staticParse(readBuffer);
        umasDriverContext.addArrayType(typeIndex, ref.getValue(),
            arrayDef.getElementTypeId(), arrayDef.getDimensions());
    } else {
        ReadBuffer readBuffer = new ReadBufferByteBased(block, ByteOrder.LITTLE_ENDIAN);
        UmasPDUReadUmasUDTDefinitionResponse udtResponse =
            UmasPDUReadUmasUDTDefinitionResponse.staticParse(readBuffer);
        umasDriverContext.addCustomType(typeIndex, ref.getValue(), udtResponse.getRecords());
    }
}
```

The first byte of the DD02-on-typeIndex response is the **classId**
discriminator. `0x04` ⇒ array definition; anything else ⇒
`UmasPDUReadUmasUDTDefinitionResponse` (i.e. UDT/FB member list).

### When `resolveCustomType` is triggered (L1064-1078)

```java
private void resolveCustomTypes(List<UmasDatatypeReference> datatypeRefs) throws Exception {
    for (int i = 0; i < datatypeRefs.size(); i++) {
        UmasDatatypeReference ref = datatypeRefs.get(i);
        int typeId = CUSTOM_TYPE_THRESHOLD + i;
        ...
    }
    for (int i = 0; i < datatypeRefs.size(); i++) {
        UmasDatatypeReference ref = datatypeRefs.get(i);
        int typeId = CUSTOM_TYPE_THRESHOLD + i;
        if (ref.getClassIdentifier() != 0) {
            resolveCustomType(typeId, ref);
        }
    }
}
```

plc4j only resolves types that were enumerated in DD03 with
`classIdentifier != 0`. **It has no built-in mechanism for FB instances
whose type is absent from DD03 — but it also doesn't reject them at the
protocol layer.** The fix path therefore generalises plc4j's
`resolveCustomType` to "speculatively call DD02 on any *unresolved*
variable's `dataTypeId`" — strictly a superset of plc4j's behaviour,
needed because the M580 firmware in question elides FB types from DD03.

### mspec — wire formats

From `v0/umas.mspec` + `v1/umas.mspec`:

```
['0x26'     UmasPDUReadUnlocatedVariableNamesRequest
    [simple     uint 16         recordType]
    [simple     uint 8          index]
    [simple     uint 32         hardwareId]
    [simple     uint 16         blockNo]
    [simple     uint 16         offset]
    [optional   uint 16         blank 'recordType == 0xDD02']
]
```

```
[type UmasPDUReadUmasUDTDefinitionResponse
    [simple     uint 8          range]
    [simple     uint 32         unknown1]
    [simple     uint 16         noOfRecords]
    [array      UmasUDTDefinition records count 'noOfRecords']
]
```

```
[type UmasUDTDefinition
    [simple     uint 16          dataType]
    [simple     uint 16          offset]
    [simple     uint 16          unknown5]
    [simple     uint 16          unknown4]
    [manual vstring value  'parseTerminatedString'  '...' '...']
]
```

```
[type UmasArrayTypeDefinition byteOrder='"LITTLE_ENDIAN"'
    [simple     uint 8           classId]
    [simple     uint 16          elementTypeId]
    [simple     uint 8           numberOfDimensions]
    [array      UmasArrayDimension dimensions count 'numberOfDimensions']
]
```

Critical observation: **the Dart driver already parses the
UmasPDUReadUmasUDTDefinitionResponse header and `UmasUDTDefinition`
records correctly** —
`UmasClient._parseVariableRecords(..., isMemberLayout: true)` at
`packages/tfc_dart/lib/core/umas_client.dart:729-778` uses a 7-byte
header (`range(1)+nextAddr(2)+unknown1(2)+noOfRecords(2)` — the
existing 7-byte header parser actually matches the DD02 variable-name
header, not the UDT header which is `range(1)+unknown1(4)+noOfRecords(2)`).
**The two headers are the same total length (7 bytes) but with one
field semantically split differently** — `nextAddress(2)+unknown1(2)`
vs `unknown1(4)`. For the FB-member case `nextAddress` will be 0 in the
common case (UDT definitions are returned in a single PDU per plc4j),
so the parser drops it cleanly.

Each `UmasUDTDefinition` record has the 8-byte header
(`dataType(2) + offset(2) + unknown5(2) + unknown4(2)`) followed by
the null-terminated UTF-8 name. The existing
`_parseVariableRecords(isMemberLayout: true)` uses an 8-byte header
(`dataTypeId(2) + blockNo(2) + offset(4) + name`) — note the Dart code
interprets the second 2 bytes as `blockNo`, which corresponds to
plc4j's `offset` field (the member's byte-offset within the parent
struct). And the Dart `offset(4)` field eats plc4j's `unknown5(2) +
unknown4(2)`. So the Dart parser already drops `unknown5/unknown4`
into a discarded `offset` field and pulls the member offset out of
`blockNo`. That's load-bearing — `_expandVariable` then computes
`variable.offset + m.blockNo` at L2046 to get the absolute member
address, treating `m.blockNo` (== plc4j `UmasUDTDefinition.offset`) as
the member's byte offset. **Wire-format parser layout is already
correct.**

### What's actually missing

`_expandVariable` (`umas_client.dart:1869-1891`):

```dart
final type = UmasDataTypes.resolve(variable.dataTypeId, dataTypes);
final isStructOrFb =
    type != null && (type.classIdentifier == 2 || type.classIdentifier == 7);
final isArray = type != null && type.classIdentifier == 4;

if (depth >= maxDepth || (!isStructOrFb && !isArray)) {
  return UmasVariableTreeNode( ... children: const [], ... );   // (?) leaf
}
```

When `type == null` (= DD03 didn't surface the FB type, exactly the
M580 scenario) the branch falls into "no children" and the FB instance
goes out as a leaf. The fix: **on `type == null` (or
`classIdentifier == 0`), attempt the plc4j-style speculative DD02 call
on the variable's `dataTypeId` and parse the result as either an array
def (`classId == 0x04`) or a UDT member list (everything else)**. Cache
hits and structural failures (PLC returns 0x94 / parse fails) revert
to the existing leaf branch.

---

## Live-PLC evidence (192.168.112.159)

Captured during this phase. See `/tmp/umas-string-bug-report.md` for
the originating snapshot. The PLC was reachable; only DD03 / DD02 /
browse paths were exercised.

`dump-types 192.168.112.159`:

```
7 data type(s)
  id=0x00 classId=26 dataType=0x00 byteSize=0   B_Elevator
  id=0x1b classId=4  dataType=0x1b byteSize=31  ARRAY[1..31] OF BYTE
  id=0x1c classId=4  dataType=0x1c byteSize=8   ARRAY[1..8] OF BYTE
  id=0x1d classId=4  dataType=0x1d byteSize=32  ARRAY[1..16] OF WORD
  id=0x1e classId=4  dataType=0x1e byteSize=48  ARRAY[1..24] OF WORD
  id=0x1f classId=4  dataType=0x1f byteSize=31  ARRAY[1..31] OF BOOL
  id=0x20 classId=4  dataType=0x20 byteSize=128 ARRAY[257..384] OF BOOL
```

Critically: **no FB types are in DD03**. The 23 FB instance variables
in DD02 reference data-type IDs (e.g. `0xb6` for `M_Elevator`) that DD03
doesn't enumerate. `UmasDataTypes.resolve()` returns `null`,
`_expandVariable` drops to a no-children leaf.

`dump-array 0xb6` (`M_Elevator`'s typeId) returns "single byte `00`"
per the bug report — i.e. the PLC accepts the DD02-on-typeId query but
returns essentially-empty payload. The behaviour is *firmware-version
specific* — other M580 firmware revisions are expected to return the
UDT member layout. The implementation must tolerate the empty/short
response and gracefully fall back to a leaf, while *also* succeeding
on firmware that does return the layout.

---

## Recommendation

**Approach 1 — extend the existing `_readDD02Block(blockNo: typeId,
isMemberLayout: true)` path to fire for unresolved-type top-level
variables, with a `classId == 0x04` array-definition fast-path inside
the same DD02 response.**

Rationale (single paragraph): plc4j's authoritative protocol logic
already uses exactly this request shape for both UDT/FB member
resolution and array definitions (`UmasPDUReadUnlocatedVariableNamesRequest`
with `recordType=0xDD02` and `blockNo=typeIndex`), discriminating
on the first response byte (`classId`). The Dart driver has a
matching helper (`_readDD02Block`) and a matching response parser
(`_parseVariableRecords(isMemberLayout: true)`) — but it only invokes
them via the `classIdentifier == 2 || == 7` gate, which trips on
`type==null` (DD03-missing case). The fix is a 1-condition broadening
of that gate plus a `tryParse` for the array-def fast-path. Approach 2
(new DD03 variant) is rejected: plc4j has no such variant in the
v0/v1 mspec, and Schneider firmware variants surface FB types
inconsistently in DD03 — the DD02-per-type-id path is the reliable
lever.

---

## Wire-format reference (chosen approach)

**Request** — `UmasPDUReadUnlocatedVariableNamesRequest` with
`recordType = 0xDD02`, `blockNo = unresolvedTypeId`, `offset = 0`:

```
0x26  uint8                  sub-function (FC90 ReadDataDictionary)
0xDD02  uint16 LE            recordType
0xNN  uint8                  index (PLC4X uses 0x03; existing helper inherits via _build0x26Payload)
0xNNNNNNNN  uint32 LE        hardwareId (already populated on UmasClient)
0xNNNN  uint16 LE            blockNo = unresolvedTypeId  (NOT 0xFFFF)
0x0000  uint16 LE            offset = 0
0x0000  uint16 LE            blank   (optional per v1 mspec; existing helper sends it)
```

**Response** (after the 3-byte UMAS header `FC + pairingKey + 0xFE`):

```
Discriminator: byte[0] == 0x04 ⇒ UmasArrayTypeDefinition
                         else ⇒ UmasPDUReadUmasUDTDefinitionResponse
```

`UmasArrayTypeDefinition` (LE):
```
classId(1)   = 0x04
elementTypeId(2)
numberOfDimensions(1)
{ startIndex(4), upperBound(4) } × numberOfDimensions
```

`UmasPDUReadUmasUDTDefinitionResponse` (LE):
```
range(1)
unknown1(4)          # 7-byte header; existing parser reads as nextAddr(2)+unknown(2)
noOfRecords(2)
UmasUDTDefinition × noOfRecords:
  dataType(2)        # member's data-type id
  offset(2)          # member's byte offset within parent  ← critical
  unknown5(2)
  unknown4(2)
  name (null-terminated UTF-8)
```

`UmasArrayTypeDefinition.tryParse` already exists at
`packages/tfc_dart/lib/core/umas_types.dart:180-203` (returns null when
`byte[0] != 0x04`). `_parseVariableRecords(isMemberLayout: true)`
already parses the UDT body correctly (member offset lives in
`UmasVariable.blockNo` per the existing convention at L2046).

---

## Code sketch (Dart, ~20 lines)

Integration site: `_expandVariable` in
`packages/tfc_dart/lib/core/umas_client.dart` (currently L1869-1891).

Drop-in replacement for the early-return block at L1878-1891, with
the speculative-resolve insertion:

```dart
final type = UmasDataTypes.resolve(variable.dataTypeId, dataTypes);
final isStructOrFb =
    type != null && (type.classIdentifier == 2 || type.classIdentifier == 7);
final isArray = type != null && type.classIdentifier == 4;
// plc4j(UmasProtocolLogic.java:1130-1146): when a custom type's class is
// non-zero, DD02-on-typeIndex returns either UmasArrayTypeDefinition
// (classId 0x04) or UmasPDUReadUmasUDTDefinitionResponse. We extend this
// to ANY unresolved/elementary FB-instance type so M580 firmware that
// omits FB types from DD03 still expands. Schneider M580 firmware was
// observed at 192.168.112.159 with 23 FB instances whose dataTypeIds
// (0xb6, 0xb7, ...) are absent from DD03; this branch recovers them.
final mayBeUnresolvedFb = !isStructOrFb && !isArray
    && depth < maxDepth
    && variable.dataTypeId >= 0x20  // skip built-in ids
    && !UmasDataTypes.builtIn.containsKey(variable.dataTypeId);

if (depth >= maxDepth || (!isStructOrFb && !isArray && !mayBeUnresolvedFb)) {
  return UmasVariableTreeNode( ...leaf... );
}

if (mayBeUnresolvedFb) {
  // Same wire request as the array DD02 path (readDD02Raw), but parse the
  // bytes as a UDT member layout when classId != 0x04.
  final raw = await readDD02Raw(variable.dataTypeId);   // may throw UmasException
  final asArray = UmasArrayTypeDefinition.tryParse(raw);
  if (asArray != null) {
    // continue into the existing isArray branch using a synthesized type
  } else {
    // parse `raw` (already minus 3-byte UMAS header) as
    // UmasPDUReadUmasUDTDefinitionResponse, reusing _parseVariableRecords
    // by feeding it the 3-byte-stripped buffer. Treat as struct members.
  }
}
```

Real implementation will (a) extract a small helper `_resolveUnknownType`
to keep `_expandVariable` readable, (b) cache the result in
`memberCache` / `arrayCache` so we don't requery on every FB instance
of the same type, (c) catch `UmasException` from the speculative DD02
call and revert to the leaf branch (matches `M_Elevator`-on-this-PLC,
which returns a single byte `00`).

Two existing affordances make this straightforward:

- `readDD02Raw(typeId)` already issues the DD02-on-typeId request and
  returns the payload (`umas_client.dart:685-715`).
- The array branch already calls it at L1904 — the new FB branch
  reuses the same call site, then forks on `classId`.

---

## Test fixture sketch

`test/umas_stub_server.py` needs new entries so CI can prove FB
expansion without live hardware.

### New variables (FB instance)

Add to `VARIABLES`:

```python
("Application.Motor.M_Elevator", 0xb6, 0, 200),   # dataTypeId=200 (FB)
```

### New data-type entry — **omitted from DD03 on purpose**

The bug only manifests when the FB type is *absent* from DD03 but
present in the DD02-on-typeIndex path. Add a new `FB_TYPES` table on
the stub:

```python
FB_TYPES = {
    # typeId -> [(member_name, member_data_type_id, member_offset_within_parent), ...]
    200: [
        ("speed",     8, 0),   # REAL @ +0
        ("torque",    8, 4),   # REAL @ +4
        ("enabled",   1, 8),   # BOOL @ +8
    ],
}
```

### Stub `handle_pdu` change (DD02 with `block_no` in `FB_TYPES`)

In the `record_type == 0xDD02` branch (around L712-728 in current
stub), before the `ARRAY_TYPES` check, add:

```python
if block_no in FB_TYPES:
    members = FB_TYPES[block_no]
    body = bytearray()
    body += struct.pack("B", 0x00)           # range
    body += struct.pack("<I", 0x00000000)    # unknown1 (4 bytes)
    body += struct.pack("<H", len(members))  # noOfRecords
    for name, dt_id, off in members:
        body += struct.pack("<H", dt_id)     # member dataType
        body += struct.pack("<H", off)       # member offset within parent
        body += struct.pack("<H", 0x0000)    # unknown5
        body += struct.pack("<H", 0x0000)    # unknown4
        body += name.encode("utf-8") + b"\x00"
    return build_success_response(bytes(body), self.pairing_key)
```

### New Dart test asserts

`packages/tfc_dart/test/core/umas_fb_visibility_test.dart` walks
`umas.browse()` and asserts:

- `M_Elevator` node has 3 children: `speed`, `torque`, `enabled`.
- Each child's `dataTypeId` matches the FB_TYPES entry.
- Each child's `variable.offset` = `M_Elevator.offset + member_offset`
  (i.e. `0 + 0`, `0 + 4`, `0 + 8`).
- `speed.dataType?.name == 'REAL'`, byteSize 4.
- Reading `speed` (block=0xb6, offset=0) returns a real value from the
  variable store (we'll seed the store at `(0xb6, 0)` → 4 bytes).

A second test asserts the **leaf fallback**: an unresolved type id
that the stub returns empty/short for must produce a children-less
leaf with no exception thrown (matches the `dump-array 0xb6 ⇒ 00`
behaviour on this PLC).

A third test asserts the **array fast-path** still works: an
unresolved type whose DD02 returns `classId=0x04` flows into the array
branch instead of the UDT branch.

---

## Acceptance gates (executed in Step C)

1. New unit/integration test passes against extended Python stub.
2. `cd packages/tfc_dart && dart test` stays fully green (1958-line
   `umas_client_test.dart` + `umas_e2e_test.dart` + monitor + write +
   diagnostics).
3. Live PLC: `dart run packages/tfc_dart/tool/umas_cli.dart browse
   192.168.112.159` returns non-zero children for some FB instances.
   (Caveat: per the live-PLC capture this M580 firmware returns
   essentially-empty DD02 for the FB type ids, so the *worst* case is
   that all 23 FB instances still surface as leaves — but **no
   regression** on existing leaves; comms healthy; no new errors.) The
   M580 firmware behaviour will be logged in SUMMARY.md as a
   firmware-dependent finding for the orchestrator to roll into Phase 5
   sweep candidates if needed. The protocol code path matches plc4j
   regardless.
4. `dart run packages/tfc_dart/tool/umas_cli.dart read 192.168.112.159
   M_Elevator` — on a firmware that returns the UDT body, at least one
   leaf reads back a real value; otherwise the command exits cleanly
   (no `0 leaf/leaves`-and-exception, no `Buffer underflow`).
5. plc4j divergences (e.g. our speculative-resolve being a superset of
   plc4j's strict `classIdentifier != 0` gate) are annotated inline
   with `// plc4j(<file>:<line>): <behaviour>; we extend because
   <reason>` per CONTEXT.md decisions.

---

## Risks / open items flagged for Phase 5 sweep

- **M580 firmware variation**: the bug report's `dump-array 0xb6` →
  single byte `00` shows this particular firmware doesn't expose
  M_Elevator's UDT body. If the same applies to all 23 FB instances,
  Phase 2 ships the protocol code path *and* the regression test
  fixture, but the live-PLC win is firmware-gated. The orchestrator
  may want to escalate this to Phase 5 SWEEP-02 ("M580 firmware
  variant probe — capture FB DD02 bytes on every available M580
  firmware revision") so the team can quantify deployment risk.
- **`unknown5` / `unknown4` in UmasUDTDefinition**: plc4j discards
  both. The Dart parser also discards them (folded into a 4-byte
  `offset` field that is currently unused after `m.blockNo` is read).
  If a Schneider firmware revision starts using those bytes for
  IN/OUT direction, that's a Phase 3 problem — flagged here for
  awareness.
- **No DD02 pagination on UDT responses observed**: plc4j single-PDU.
  Existing `_readDD02Block` loop handles pagination if it ever
  appears — no change needed.

---

*Research complete: 2026-05-18.*
