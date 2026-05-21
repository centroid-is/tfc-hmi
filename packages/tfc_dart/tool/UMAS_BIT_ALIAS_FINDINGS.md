# UMAS bit-alias hunt — findings (2026-05-20)

## Question

Where on the wire does `p_Stat_xFault` (and the rest of the screenshot's
bit-alias names like `p_Stat_xSTO`, `p_CMD_xAutotune`,
`p_Stat_xMotorTemperatureFault`, `p_Stat_xPermissiveFwd/Rev`, `p_Mode_xMan/Auto`,
`p_CMD_xResetRuntime`, `xFailedToRun`, `xParentConvFault`) live?

## Answer (short)

**They are not in any unreserved wire-accessible section.** All 215+
sections enumerable via `READ_PROJECT_INFO` (`0x07`) and fetchable via
`READ_MEMORY_BLOCK` (`0x20`) were dumped (≈1.4 MB total), scanned in
ASCII / UTF-16 LE / UTF-16 BE, and decompressed where zlib-magic was
present. **None contain those literals in any encoding.**

The candidate "Upload Info" opcode is **`0x37`** (Schneider's
`READ_VARIABLE_LIST_BY_NAME` / DDT-by-name family). It responds with
**`0xFD err=0x82` to every payload shape on an unreserved session — the
PLC's "RESERVED required" signal**. Aveva is currently holding the
reservation, so `0x37` is unreachable to us.

## Method (matches Leads A–D in the brief)

### Lead A — UTF-16 LE/BE/ASCII scan of every section

| step | result |
|---|---|
| `strings -el` (UTF-16 LE) on 215 sections of v4 dump | **0 hits** on any screenshot token |
| `strings -eb` (UTF-16 BE) on same | **0 hits** |
| ASCII on same | **0 hits** for `xFault`/`xSTO`/`xAutotune`/`xMotorTemp`/`xParentConv` etc. |

Only ASCII strings that include `Fault` / `STO` are in:
- `sec-0x41.bin` — `"FIPIO Bus disconnected or in STOP"` (system message catalog).
- `sec-0x80.bin` — `"STO active (StO)"`, `"DCP (dCP)"`, etc. — embedded inside ARM machine code (drive's HMI text strings).

### Lead B — comprehensive zlib stream scan

Scanned every section's whole body for `78 9c` / `78 5e` / `78 da` at
any offset, attempting streaming decompress. Found **the same 19 zlib
streams** the prior agent found — no additional hidden streams. The
decompressed payloads are project XML (`<STExchangeFile>`) — full ST
source of the user FBs. **None of them mentions the screenshot's bit
names.**

### Lead C — opcode probing for "Upload Info"

Probed every shape (empty, sub-selector 0x00/01/02/ff, `dd 00 …`
trailer with typId 0/1/0x7d/0xce, hwId-only, hwId+idx) against
opcodes `0x37`, `0x39, 0x3A, 0x3B, 0x3C..0x4F`, `0x57`, `0x67..0x6F`.

Tool: `umas_upload_info_probe.dart`. Output:
`/tmp/bit-alias-final/upload-info/upload_info_probe.md`.

Notable results:

| opcode | unreserved verdict |
|---|---|
| **0x37** | **`0xFD err=0x82` (RESERVED required)** — for every payload. This is the most likely "Upload Info" / DDT-by-name opcode. |
| 0x39 | `0xFE` with 7 B `00 00 ff 80 00 da 04` (status-poll-like, no payload data) |
| 0x6c | `0xFE`. Behaves as memory read (mostly returns 1020 B of zeroes); `sel=0x01` returned 35 B looking like an event-log echo. Not a name catalog. |
| 0x46..0x4F, 0x57, 0x67..0x6F | only standard 0x86 / 0x83 / 0x88 errors |

### Lead D — page-boundary aware re-dump of all sections

Wrote `umas_huge_section_dump.dart` and `umas_full_resume_dump.dart`
which (unlike v4) **do not bail on short reads** and continue paging up
to declared cap. Result:

- Sec `0x10` recovered: **152 576 B** (v4 had 2 816 B — 98 % missed).
- Sec `0x11` recovered: **305 408 B** (v4 had 5 120 B — 98 % missed).
- Plus full recovery of `0x40, 0x41, 0x30, 0x33, 0xa8, 0xb3, 0xee, 0xf5,
  0xcd, 0xce, 0xd0, 0xd1`, etc.
- Also enumerated sections beyond 0xff via 16-bit section id (`0x100,
  0x101`).

Even with the much larger dump volume, **no screenshot token appears in
any encoding**.

## What we DID find on the wire (current FB type catalog)

`sec-0x7d` (3 840 B of 3 867 declared) and `sec-0xce` (4 206 B) contain
the user's project type catalog. Wire record format decoded:

```
<typeTag:1> <flags:1> <byteOffset:2 LE> <pad:4> <kind:1>
<name>\0
```

For `ST_ATV320_Public` at `sec-0x7d` offset `0x7e0`, the **only**
declared members are:

- `Status` (WORD @ offset 0x02)
- `CMD` (WORD @ offset 0x04)
- `Mode` (WORD @ offset 0x06)
- `Cfg` (WORD @ offset 0x08)
- `p_Stat_iThermalFaults` @ offset 0x0c
- `p_Stat_diRuntime` @ offset 0x10
- `Color` @ offset … (struct)

**There are no `Status.0` / `Status.1` bit aliases at the type level**
that the runtime PLC reports through 0x07/0x20.

`FB_ATV320` itself (the centroid wrapper) at `sec-0x7d` lists
`p_CMD_xReset, p_CMD_xManFwd, p_MODE_xAuto, p_Stat_xAuto, p_CMD_xStop,
p_Stat_xCleaning, p_CMD_xCleaning` as VAR_PUBLIC bits (kind=0x04). But
the screenshot's names (`p_Stat_xFault`, `p_Stat_xSTO`, etc.) are
**not** in this list either.

## Most-likely interpretation

The Control Expert screenshot is showing a fuller / library-level
`ST_ATV320_Public` or `FB_ATV320` view (probably from the project's
`.STA` engineering file or a Schneider library import) where the bit
aliases `p_Stat_xFault := Status.0` etc. **are defined**. The
**runtime PLC's exposed type catalog**, however, only retains the
WORD-level members (`Status`, `CMD`, `Mode`) — not the bit-level alias
metadata.

That metadata is what Control Expert reads via "Upload Info", which on
this PLC routes through `0x37` (or a peer in the upload family) and is
**reservation-gated** — confirmed by `err=0x82` on every payload shape.

## Worktree + commits

Branch: `umas-fb-dynamic-value` (in worktree
`.claude/worktrees/agent-a3363a2d`).

New probe tools (committed atomically):

- `packages/tfc_dart/tool/umas_huge_section_dump.dart` — aggressive
  paginator for large sections that doesn't bail on short reads.
- `packages/tfc_dart/tool/umas_full_resume_dump.dart` — resume-mode
  dumper that picks up where prior output left off and probes sections
  beyond 0xff.
- `packages/tfc_dart/tool/umas_upload_info_probe.dart` — opcode sweep
  for the "Upload Info" candidates (0x37 / 0x39 / 0x3A..0x4F / 0x57 /
  0x67..0x6F) with multiple payload shapes.
- `packages/tfc_dart/tool/umas_op6c_deep_probe.dart` — confirmed 0x6c
  is a memory-read peer, not a name catalog.

## Recommendation for `umas_client.dart`

Since the bit-alias map cannot be obtained from the unreserved wire:

1. Surface **what we do have** — the type catalog at sec-0x7d / sec-0xce
   has every WORD-level public member. Browse should expose
   `Status`, `CMD`, `Mode`, `Cfg`, `p_Stat_diRuntime`, etc. as
   readable members; **and where a known FB type matches a hard-coded
   bit-alias table** (e.g. for Schneider's stock ATV320 wrapper), expand
   to bit-level aliases client-side.
2. Keep the option of upgrading to wire-reported bit aliases if/when we
   add reservation handling (and a coordination story with Aveva for
   read-only co-existence).
