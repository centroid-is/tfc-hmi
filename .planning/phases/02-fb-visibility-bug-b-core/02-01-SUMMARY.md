# Phase 2 Summary — FB visibility (Bug B core)

**Authored:** 2026-05-18
**Phase agent:** worktree-agent-ae2f6e62 (autonomous)
**Base commit:** f9c6df1979b3778e14abce6f77ff09a0f0875a98
**Plan:** `.planning/phases/02-fb-visibility-bug-b-core/02-01-PLAN.md`
**Research:** `.planning/phases/02-fb-visibility-bug-b-core/02-RESEARCH.md`

---

## What was built

A protocol-layer fix in `_expandVariable` that recovers function-block
(FB) instance members on M580 firmware revisions that omit FB types
from DD03. The driver now speculatively issues a DD02 query keyed on
the variable's `dataTypeId` (not 0xFFFF) whenever DD03 didn't resolve
the type and the type isn't a built-in scalar; the response is parsed
either as a `UmasArrayTypeDefinition` (`classId == 0x04`) or as a
`UmasPDUReadUmasUDTDefinitionResponse` (member records). This matches
plc4j's `parseCustomTypeBlock` logic (`UmasProtocolLogic.java:1130-1146`)
broadened to the DD03-missing case.

Result on the live M580 at 192.168.112.159:
**every** previously `(?)`-leaf FB instance now expands into its
member tree. Pre-fix: 58 roots, 58 leaves, 0 FB expansion. Post-fix:
**58 roots, 984 leaves, 30 FB instances expanded (23 top-level FBs in
the original bug report plus 7 nested-FB roots discovered through the
expansion).** Headline goal exceeded.

The protocol path is verified against (a) a new Python stub fixture
plus (b) 4 new Dart tests, both running in CI without live hardware.

---

## File-by-file changes

| File | Lines | Purpose |
|---|---|---|
| `test/umas_stub_server.py` | +51 | New `FB_TYPES` fixture, `M_Elevator` variable, DD02 handler branch that returns `UmasPDUReadUmasUDTDefinitionResponse` for typeIds NOT in DD03, member-value seeds in variable store |
| `packages/tfc_dart/test/core/umas_fb_visibility_test.dart` | +247 | New e2e test exercising FB expansion and member reads against the stub |
| `packages/tfc_dart/lib/core/umas_client.dart` | +97 / -3 | Speculative DD02 resolution in `_expandVariable`; type now nullable with `resolvedType` non-null view after gate; plc4j source citations inline |
| `packages/tfc_dart/test/umas_e2e_test.dart` | +5 / -3 | Bump the existing `Application` browse assertions from 3→4 child folders and 11→12 variables to reflect the new stub FB fixture |

**Total: 4 files, +400 / -6 lines.**

Files explicitly **NOT** touched (per phase boundary):
- `packages/tfc_dart/lib/core/umas_types.dart` (Phase 1's STRING clamp lives at line 1236 — left alone)
- `lib/widgets/umas_browse.dart` (Phase 4's UI affordances)
- `.planning/STATE.md`, `.planning/ROADMAP.md` (orchestrator-owned)

---

## must_haves verification

ROADMAP Phase 2 success criteria 1-5, verbatim:

### 1. browse expansion

> `dart run packages/tfc_dart/tool/umas_cli.dart browse 192.168.112.159`
> reports a non-zero number of children for every `(?)` FB instance
> from the pre-fix snapshot (target: 23/23 of the FB instances captured
> in `/tmp/umas-string-bug-report.md`).

**PASS.** Live M580. Command output (head):

```
58 root(s), 984 leaves

Elevator  (FB) [block=0x43 off=0x0]
  q_rVelocity  (REAL) [block=0x43 off=0x8]
  q_xUp  (BOOL) [block=0x43 off=0xc]
  ...
M_Elevator  (FB) [block=0xb6 off=0x0]
  i_xFreshness  (BOOL) [block=0xb6 off=0x0]
  i_xFwd  (BOOL) [block=0xb6 off=0x1]
  ...
  i_stDTM  (FB) [block=0xb6 off=0x8]
    ETA  (WORD) [block=0xb6 off=0x8]
    RFR  (INT) [block=0xb6 off=0xa]
    ...
```

- Pre-fix snapshot: 58 leaves, 0 FB expansion, all 23 named FB
  instances `(?)` leaves.
- Post-fix: **984 leaves**, **30 FB instances expanded** (each with
  member children; some FB members are themselves nested FBs that
  also expand — e.g. `M_Elevator.i_stDTM` and `M_Elevator.HMI`).
- Remaining `(?)` leaves: 3 (`LS_HEALTH`, `DIO_HEALTH`, `DIO_CTRL`
  inside `BMEP58_ECPU_EXT` — these are device-status types of a kind
  that returns empty UDT bodies; cleanly falls into the no-children
  leaf path, no exception thrown).
- "Buffer underflow" appears 0 times in the output (no STRING bleed
  through; that's Phase 1's territory and Phase 1's clamp isn't in
  this worktree).

Log: `/tmp/p2-browse.log` (1049 lines).

### 2. read M_Elevator

> `dart run packages/tfc_dart/tool/umas_cli.dart read 192.168.112.159
> M_Elevator` returns at least one leaf with a real value (public VAR
> or readable input/output).

**PASS.** Live M580. Command tail:

```
M_Elevator: 46 leaf/leaves
  M_Elevator.i_xFreshness  BOOL [block=0xb6 off=0x0]  =  true
  M_Elevator.i_xFwd  BOOL [block=0xb6 off=0x1]  =  false
  ...
  M_Elevator.i_stDTM.ETA  WORD [block=0xb6 off=0x8]  =  173
  M_Elevator.i_stDTM.LCR  UINT [block=0xb6 off=0xc]  =  20
  ...
  M_Elevator.q_sStatus  STRING [block=0xb6 off=0x27]  -> 0x0
  ...
  M_Elevator.p_Cfg_rVelocity  REAL [block=0xb6 off=0xa8]  =  0.0

45 ok / 1 fail
```

- Pre-fix: `M_Elevator: 0 leaf/leaves`.
- Post-fix: **46 leaves discovered, 45 reading back real values
  (booleans, INT, WORD, UINT, DINT, REAL). The 1 fail is the STRING
  leaf `q_sStatus` hitting Phase 1's Bug A `underflow` — out of Phase
  2's scope, will resolve when Phase 1's 1-line clamp lands.**

Log: `/tmp/p2-read-elevator.log` (50 lines).

### 3. Unit/integration test with stub fixtures

> A unit/integration test exercises FB-member tree assembly from a
> fixture mirroring the M580 DD02/DD03 shape; the Python stub at
> `test/umas_stub_server.py` returns matching fixtures so CI runs
> without live hardware.

**PASS.** Tasks 1 + 2 deliverables:

- `test/umas_stub_server.py` — new `FB_TYPES[200] = [(speed, 8, 0),
  (torque, 8, 4), (enabled, 1, 8)]` table; DD02 handler returns a
  `UmasPDUReadUmasUDTDefinitionResponse` body when `block_no` keys
  into `FB_TYPES`; stub now serves 12 variables (was 11).
- `packages/tfc_dart/test/core/umas_fb_visibility_test.dart` — 4 new
  tests:
  1. `FB instance with type missing from DD03 expands into members`
  2. `FB member offsets and types match the FB_TYPES layout`
  3. `FB members read back their seeded values via readVariables`
  4. `Existing non-FB tree (GVL/Motor/Counters) still expands correctly`
     (regression guard)

```
$ cd packages/tfc_dart && dart test test/core/umas_fb_visibility_test.dart
00:00 +4: All tests passed!
```

### 4. plc4j divergence annotation in code

> Any behavioural divergence from `plc4j`'s
> `UmasPDUReadDatatypeNamesRequest` / member-layout resolution path is
> annotated in code comments at the resolution site, referencing the
> plc4j source file + line.

**PASS.** `packages/tfc_dart/lib/core/umas_client.dart` now carries
verbatim plc4j citations at the FB-resolution site:

```dart
/// plc4j(UmasProtocolLogic.java:1079-1097, 1130-1146): for any custom-type
/// reference whose `classIdentifier != 0`, plc4j issues a DD02 request keyed
/// on the type's index (NOT 0xFFFF) and discriminates on the first response
/// byte. `classId == 0x04` ⇒ UmasArrayTypeDefinition; anything else ⇒
/// UmasPDUReadUmasUDTDefinitionResponse (member records). We extend this
/// gate to ALSO fire for variables whose `dataTypeId` did not appear in
/// DD03 at all — the live M580 at 192.168.112.159 omits FB types from DD03
/// even though their UDT bodies are accessible via DD02-on-typeIndex. plc4j
/// strictly gates on the non-zero classIdentifier of a *resolved* DD03
/// record and would silently drop these FB instances; we resolve
/// speculatively to surface them. See `.planning/phases/02-fb-visibility-bug-b-core/02-RESEARCH.md`.
```

`grep -n "plc4j(UmasProtocolLogic.java" packages/tfc_dart/lib/core/umas_client.dart | wc -l` → 1 (in the doc-comment above `_expandVariable`). The body also has a second inline `// Mirrors plc4j parseCustomTypeBlock's classId discriminator (UmasProtocolLogic.java:1130-1146)` comment.

### 5. Existing happy-path tests stay green

> Existing happy-path tests in
> `packages/tfc_dart/test/core/umas_client_test.dart` (1958 lines)
> remain green — pairing-key and session lifecycle untouched.

**PASS.** Regression sweep across all non-integration tests:

```
$ cd packages/tfc_dart && find test -name "*_test.dart" -not -path "test/integration/*" | xargs dart test --concurrency=1
...
02:21 +614 ~32: All tests passed!
```

**614 tests pass, 32 skipped, 0 failed.**

Skipped tests are pre-existing live-hardware-only tests (e.g. JBTM
M2400 devices not in the worktree). Failed tests in
`test/integration/` are pre-existing flakes around docker-compose
port collisions (port 15432 already in use, etc.) — documented in
`.planning/codebase/CONCERNS.md`. None relate to my changes.

Pairing-key / session lifecycle tests inside the 1958-line
`umas_client_test.dart` are all green.

---

## plc4j divergences logged

1. **Speculative resolution gate broadened.** plc4j's `resolveCustomTypes`
   (UmasProtocolLogic.java:1064-1078) strictly fires `resolveCustomType`
   only on DD03 records with `classIdentifier != 0`. We additionally fire
   for variables whose `dataTypeId` is absent from DD03 — necessary to
   recover FB instances on M580 firmware that elides FB types from DD03.
   Documented inline in `_expandVariable`'s doc-comment.

2. **Cache lifetime per-browse, not per-driver-context.** plc4j stores
   resolved types in `umasDriverContext.addCustomType` (lifetime = PLC
   session). We pass `memberCache` and `arrayCache` as locals into
   `_expandVariable`, so the cache is per-`browse()` call. Same
   correctness; slight inefficiency on repeated browses. Worth a
   refactor in a follow-up phase if scaling demands it.

3. **Defensive empty-cache on failure.** When the speculative DD02
   throws `UmasException` or returns an empty member list, we cache an
   empty list to prevent retry on every FB instance of the same type.
   plc4j doesn't have this case because its gate is stricter.

No outright protocol-divergences — wire-format requests + response
parsing match plc4j byte-for-byte.

---

## Items flagged for Phase 5 sweep

None of these blocked Phase 2; all surface naturally given the
live-PLC evidence and merit triage during Phase 5's planner-led
discovery pass.

### SWEEP candidates discovered during Phase 2

- **3 nested `(?)` leaves under `BMEP58_ECPU_EXT`**: `LS_HEALTH`,
  `DIO_HEALTH`, `DIO_CTRL`. These are health/control aggregates that
  the PLC returns empty UDT bodies for. Today they cleanly fall to
  no-children leaves (no exception, no value). May or may not be
  worth pursuing — depends on whether operators need to read them.
  Suggested REQ-ID if accepted: `SWEEP-02`. Defer to Phase 5 triage.

- **STRING leaves inside FB instances still bleed Bug A through the
  0x50 path**: my `read M_Elevator` output shows `q_sStatus STRING
  [block=0xb6 off=0x27] -> 0x0` (`UmasException` from
  `parseReadAllResponse`). This is exactly Phase 1's Bug A surface
  — the 1-line clamp at `umas_types.dart:1236` will fix it. **No
  separate SWEEP item needed.** Phase 1 + Phase 2 compose cleanly.

- **per-browse cache vs per-driver-context cache** (divergence #2
  above). Minor performance opportunity; suggested REQ-ID if accepted:
  `SWEEP-03`. Defer.

- **The `_useMonitorPlc` (M580 detection) flag and the path it
  selects**: my change affects only the `browse` path (via
  `_expandVariable`), not the read path. The read path on M580 still
  routes through `MonitorPlc (0x50)` and inherits Bug A's STRING
  issue. No new finding here — but worth noting for Phase 5 that the
  read-path divergence between 0x22 and 0x50 has more surfaces than
  Bug A captures.

### Not blocked anywhere

The Phase 1 STRING-clamp work at `umas_types.dart:1236` is the *only*
piece that prevents 46-of-46 read on M_Elevator. Phase 2's protocol
fix is functionally complete on its own.

---

## Commits in this phase (worktree branch only)

```
1ecde5fd feat(02-fb-visibility): speculative DD02 resolution for FB instances absent from DD03
60ff979e test(02-fb-visibility): failing FB-member tree assembly test
2a7dd4f5 feat(02-fb-visibility): extend stub with FB_TYPES fixture for typeId 200
612030a1 docs(02-fb-visibility): plan FB visibility implementation
83b31413 docs(02-fb-visibility): research plc4j FB resolution approach
```

(Plus this SUMMARY.md commit, landing next.)

All commits to `worktree-agent-ae2f6e62`. No push. No `--no-verify`.
No modifications to `STATE.md` or `ROADMAP.md`.

---

## Outstanding orchestrator notes

- Phase 1's STRING clamp at `umas_types.dart:1236` is **not** in this
  worktree. The 1-fail in `read M_Elevator` is Phase 1's, not Phase
  2's — merging Phase 1 + Phase 2 will deliver 46/46 reads on M_Elevator.
- The e2e test fixup (`umas_e2e_test.dart` from 11→12 variables, 3→4
  child folders) is purely additive — the new stub fixture introduces
  `Application.Motors.M_Elevator`, and the existing assertions about
  `GVL` / `Motor` / `Counters` are unchanged.
- The `Motors` (plural) vs `Motor` (singular) folder is intentional —
  the new FB lives under `Application.Motors.M_Elevator` so it doesn't
  collide with the existing `Application.Motor.{speed,torque,enabled}`
  scalar leaves.

---

*Phase 2 complete: 2026-05-18.*
