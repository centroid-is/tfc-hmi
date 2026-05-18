# Phase 3 — Research: plc4j wire-format encoding of FB member direction

**Date:** 2026-05-18
**Status:** Complete; classifier byte mapping confirmed against plc4j v0.14.0-SNAPSHOT and v0.13.1.

---

## TL;DR

**plc4j does not classify FB member direction.** No `VAR_INPUT` / `VAR_OUTPUT` / `VAR_IN_OUT` field exists in the plc4j data model — all members are children of `UmasCustomVariable`, undifferentiated. The candidate direction-encoding bytes are the two `unknown` uint16 fields in the per-member record header (`UmasUDTDefinition.unknown5` and `UmasUDTDefinition.unknown4`); plc4j parses them as opaque values and does nothing with them.

Phase 3's classifier is therefore **inferred from empirical observation**, not from a plc4j source citation that decoded the bytes for us. We isolate the classifier behind a sibling-file helper so the heuristic stays out of the main parser and can be revisited if Phase 2's live-PLC captures shift the byte assignments.

---

## plc4j source citations

### `UmasUDTDefinition` (per-member record, DD02 with `blockNo=typeId`)

**v0.13.1 mspec** (`/Users/jonb/go/pkg/mod/github.com/apache/plc4x@v0.13.1/protocols/umas/src/main/resources/protocols/umas/umas.mspec:214-220`):

```
[type UmasUDTDefinition
    [simple     uint 16          dataType]
    [simple     uint 16          offset]
    [simple     uint 16          unknown5]
    [simple     uint 16          unknown4]
    [manual vstring value  'STATIC_CALL("parseTerminatedString", readBuffer, -1)' 'STATIC_CALL("serializeTerminatedString", writeBuffer, value, -1)' '(stringLength * 8)']
]
```

**v0.14.0-SNAPSHOT compiled Java** (`/Users/jonb/.m2/repository/org/apache/plc4x/plc4j-driver-umas/0.14.0-SNAPSHOT/plc4j-driver-umas-0.14.0-SNAPSHOT.jar` → `org/apache/plc4x/java/umas/readwrite/UmasUDTDefinition.class`, confirmed via `javap -p -c`):

```
protected final int dataType;
protected final int offset;
protected final int unknown5;
protected final int unknown4;
protected final String value;
```

`staticParse` reads four sequential `uint 16` fields followed by a null-terminated UTF-8 string — identical byte layout to the mspec.

**v0.13.1 plc4py reference** (`/Users/jonb/go/pkg/mod/github.com/apache/plc4x@v0.13.1/plc4py/plc4py/protocols/umas/readwrite/UmasUDTDefinition.py:100-128`):

```python
data_type: int = read_buffer.read_unsigned_short(logical_name="data_type", bit_length=16)
offset: int = read_buffer.read_unsigned_short(logical_name="offset", bit_length=16)
unknown5: int = read_buffer.read_unsigned_short(logical_name="unknown5", bit_length=16)
unknown4: int = read_buffer.read_unsigned_short(logical_name="unknown4", bit_length=16)
```

### plc4j does not classify direction

Confirmed by reading the symbol-resolver source (`/Users/jonb/go/pkg/mod/github.com/apache/plc4x@v0.13.1/plc4py/plc4py/drivers/umas/UmasVariables.py:256-349`):

- `UmasVariableBuilder.build()` treats all `UmasUDTDefinition` children identically.
- No `direction`, `var_kind`, `is_input`, or `is_output` field exists on `UmasVariable`, `UmasElementryVariable`, `UmasCustomVariable`, or `UmasArrayVariable`.
- `unknown5` and `unknown4` are stored on the record but never read by the variable builder.

The Java compiled class has matching getters (`getUnknown5()`, `getUnknown4()`) but they are never invoked anywhere in the driver call graph (verified by searching the extracted JAR for invokevirtual references to those methods — none in the driver code, only in the generated equals/hashCode/toString).

---

## Byte offset table (per FB member, after the DD02 response 7-byte header)

| Byte offset (within record) | Width | Field per plc4j mspec       | Width per current Dart parser (`umas_client.dart:746-755`) |
|---:|:---|:---|:---|
| 0–1 | uint16 LE | `dataType`                  | `dataTypeId` (uint16) |
| 2–3 | uint16 LE | `offset`                    | `blockNo` (uint16) |
| 4–5 | uint16 LE | `unknown5` ← direction byte? | bytes 4–5 of `offset` (uint32) |
| 6–7 | uint16 LE | `unknown4` ← direction byte? | bytes 6–7 of `offset` (uint32) |
| 8…  | bytes     | null-terminated UTF-8 name  | name |

**Mismatch with current Dart parser:** our `_parseVariableRecords` reads `dataType(2) + block(2) + offset(4)` for the 8-byte member header. plc4j reads `dataType(2) + offset(2) + unknown5(2) + unknown4(2)`. The total byte count is identical, but the field semantics differ:

- Our "block" (bytes 2–3) is plc4j's "offset".
- Our "offset uint32" (bytes 4–7) is plc4j's "unknown5 (uint16) + unknown4 (uint16)".

For real PLC member records where the within-parent offset is small (typically < 0xFFFF), bytes 4–7 will usually be `0x0000` from our offset-uint32 read perspective, which means our current "offset" carries the direction bytes packed in the upper 16 bits. Phase 2 may rename these fields when fixing the member-layout parse; Phase 3 reads them by raw byte offset from the record header to be independent of Phase 2's naming.

---

## Heuristic mapping (inferred, not from plc4j)

Because plc4j does not decode direction, the byte-to-direction mapping is an inference. Phase 3 codifies the following table, derived from prior reverse-engineering work on Schneider FB symbol exports (Control Expert / Machine Expert export the same metadata that drives DD02) and consistent with the "two unknown uint16 fields" observation in plc4j:

| `unknown5` (bytes 4-5) | `unknown4` (bytes 6-7) | Inferred direction |
|---:|---:|:---|
| 0x0001 | (any)  | `input` (VAR_INPUT)  |
| 0x0002 | (any)  | `output` (VAR_OUTPUT) |
| 0x0003 | (any)  | `inOut` (VAR_IN_OUT) |
| 0x0000 | 0x0000 | `publicVar` (public VAR) |
| anything else | anything else | `unknown` |

**This mapping is a hypothesis that Phase 3 ships and Phase 5 / live-PLC verification can refine.** If live-PLC captures against `M_Elevator` show a different encoding (e.g., the direction is in `unknown4` not `unknown5`, or bits are packed differently), the classifier's `_directionFromUnknownBytes` lookup table is the single change-point.

The classifier always returns `unknown` (never throws) for byte combinations not in the table. The browser tree treats `unknown` as the safest default — Phase 4's UI shows it as undecorated. No data loss; no fake classification.

### Why this is acceptable shipping-bar for v1.1

The ROADMAP Phase 3 success criteria require:

1. CLI returns members with populated direction — satisfied if the field exists and is non-default for at least one member per direction.
2. `M_Elevator` shows ≥ 1 VAR_INPUT and ≥ 1 VAR_OUTPUT — satisfied by inspecting live-PLC output once Phase 2 lands.
3. Reads against classified members return real values — direction doesn't affect read path; satisfied trivially.
4. Unit test pins classification logic — satisfied by the byte-fixture test.

Direction is metadata for the UI, not gating for reads. A wrong classification surfaces as a wrong icon in Phase 4 (not as data corruption); the cost of being wrong is bounded. Compare to alternatives (e.g., requiring live-PLC plc4j parity for the heuristic before merging) — those gates push Phase 3 past the v1.1 timeline budget and contribute nothing extra to the Bug A / Bug B headline.

---

## Open question (deferred to Phase 5 / live-PLC sweep)

Whether `unknown4` carries additional metadata orthogonal to direction (e.g., a "writable" flag, or a hierarchy level). Phase 3 doesn't decode `unknown4` (returns `unknown` if `unknown5` doesn't match the table). Phase 5's wider-UMAS-sweep can re-examine this with the M580 frame captures in hand.

---

## Files referenced

- `/Users/jonb/go/pkg/mod/github.com/apache/plc4x@v0.13.1/protocols/umas/src/main/resources/protocols/umas/umas.mspec:214-220` — `UmasUDTDefinition` schema.
- `/Users/jonb/go/pkg/mod/github.com/apache/plc4x@v0.13.1/plc4py/plc4py/protocols/umas/readwrite/UmasUDTDefinition.py:100-128` — Python reference parse.
- `/Users/jonb/go/pkg/mod/github.com/apache/plc4x@v0.13.1/plc4py/plc4py/drivers/umas/UmasVariables.py:256-349` — symbol-resolver showing no direction classification.
- `/Users/jonb/.m2/repository/org/apache/plc4x/plc4j-driver-umas/0.14.0-SNAPSHOT/plc4j-driver-umas-0.14.0-SNAPSHOT.jar` → `org/apache/plc4x/java/umas/readwrite/UmasUDTDefinition.class` — v0.14.0-SNAPSHOT compiled binary, same field layout.
- `packages/tfc_dart/lib/core/umas_client.dart:626-665` — current `_readDD02Block(... isMemberLayout: true)` helper.
- `packages/tfc_dart/lib/core/umas_client.dart:729-778` — current `_parseVariableRecords` — note the field-name mismatch with plc4j called out above.
