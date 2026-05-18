# Phase 3 — VAR_INPUT / VAR_OUTPUT distinction — Summary

**Completed:** 2026-05-18
**Branch:** `worktree-agent-a91e1430` (worktree under `.claude/worktrees/agent-a91e1430/`)
**Base commit:** `f9c6df1979b3778e14abce6f77ff09a0f0875a98`
**Requirements closed (data-layer half):** FB-02, FB-03

---

## What shipped

A pure data-layer slice that classifies each function-block instance member by declaration direction (`input` / `output` / `publicVar` / `inOut` / `unknown`), exposes the classification on `UmasVariable` and `UmasVariableTreeNode`, and surfaces it through a new `--show-direction` CLI flag.

The Phase 4 browser-tree UI (already landed in main repo as commit `da9d9a10`, not in this worktree) consumes the same enum spelling via the `BrowseNode.metadata['fbDirection']` carrier; the wire-names returned by `UmasFbMemberDirection.name` match the strings Phase 4 expects (`input` / `output` / `publicVar` / `inOut` / `unknown`).

### Files changed (2 commits)

```
packages/tfc_dart/lib/core/umas_client.dart        | 36 +++++++++-
packages/tfc_dart/lib/core/umas_fb_direction.dart  | 80 ++++++++++++++++++++++  (new)
packages/tfc_dart/lib/core/umas_types.dart         | 21 +++++-
packages/tfc_dart/test/core/umas_fb_direction_test.dart | 79 +++++++++++++++++++++  (new)
packages/tfc_dart/tool/umas_cli.dart               | 28 ++++++--
 5 files changed, 235 insertions(+), 9 deletions(-)
```

Commits (chronological):

1. `b1ad7520 feat(umas): UmasFbMemberDirection enum + classifier (Phase 3 step 1/3)`
   — TDD: tests-first, classifier function pinned by 8 unit-test cases.
2. `75c2637c feat(umas): plumb FB-member direction through model + CLI (Phase 3 step 2/3)`
   — wire the classifier into `_parseVariableRecords`, propagate through `_expandVariable`, add `--show-direction` CLI flag, full regression sweep green.

(A third step — this summary — is documentation only; not committed to source.)

---

## Interface assumption about Phase 2 (the contract)

**Assumption made:** Phase 2 builds FB-member resolution on top of the existing `_readDD02Block(blockNo: typeId, isMemberLayout: true)` helper at `packages/tfc_dart/lib/core/umas_client.dart:626-665` and exposes member records as `UmasVariable` instances flowing through `_expandVariable`'s struct-walk loop (`umas_client.dart:2038-2058` in the pre-Phase-3 numbering).

**Mechanical reconciliation if reality differs:**

- If Phase 2 introduces a new subtype like `UmasFbMember` distinct from `UmasVariable`:
  the new subtype needs an optional `direction: UmasFbMemberDirection?` field, populated identically. Phase 3's classifier call in `_parseVariableRecords` moves over to Phase 2's parser; the byte-offset arithmetic (`view.getUint16(4, LE)` and `view.getUint16(6, LE)` at bytes 4-5 / 6-7 of each member record) is preserved verbatim.
- If Phase 2 renames the member-layout entry helper (e.g. drops `_readDD02Block(... isMemberLayout: true)` in favour of a dedicated `readFbMemberLayout`):
  the classifier call moves to the new entry point. The byte offsets are part of the plc4j wire-format and don't change.
- If Phase 2 keeps `UmasVariable` and only adds members to the existing model (the most likely outcome): no reconciliation needed — Phase 3's `direction` field on `UmasVariable` is already in place; Phase 2 just populates the field when it builds member instances.

The classifier (`classifyFbMemberDirection`) takes two `int` arguments and has no dependency on the surrounding parse machinery, so it survives any Phase 2 API shape.

---

## Test pass count

- **Phase 3 new tests:** 8/8 green (`packages/tfc_dart/test/core/umas_fb_direction_test.dart`).
- **Full tfc_dart suite:** 476/476 green across `test/core/`, `test/umas_diagnostics_e2e_test.dart`, `test/umas_e2e_test.dart`, `test/umas_client_read_variable_test.dart`, `test/umas_coils_registers_test.dart`, `test/umas_diagnostics_test.dart`, `test/umas_monitor_plc_test.dart`, `test/umas_reservation_test.dart`, `test/umas_write_variable_test.dart`.
- **Root-level widget tests:** `flutter test test/widgets/umas_browse_test.dart` — 10/10 green (no regression on top-level browse).
- **Static analysis:** `dart analyze` on changed files shows only the pre-existing `unused_local_variable` warning in `umas_client.dart:1583` (confirmed unrelated via `git stash` baseline). Zero new analysis findings.

---

## Live-PLC `--show-direction` output excerpt

Probe: `dart run packages/tfc_dart/tool/umas_cli.dart browse 192.168.112.159 --show-direction` against M580 at 192.168.112.159:502 (unit 255).

Excerpt (first 25 of 60 lines — same 58 roots / 58 leaves as the pre-Phase-3 snapshot in `/tmp/umas-string-bug-report.md`):

```
58 root(s), 58 leaves

Elevator  (?) [block=0x43 off=0x0]
BMEP58_ECPU_EXT  (?) [block=0x33 off=0x0]
Elevator_Motor  (?) [block=0xaf off=0x0]
M_F1_RC_01  (?) [block=0xb0 off=0x0]
B_F1_RC_01_Front  (BOOL) [block=0x2e off=0x0]
B_F1_RC_01_Back  (BOOL) [block=0x2e off=0x1]
...
M_Elevator  (?) [block=0xb6 off=0x0]
B_Elevator_F1_A  (BOOL) [block=0xad off=0xa]
...
stStatusElevator  (STRING) [block=0xad off=0x30]
```

**Observations:**

1. No `dir=` suffix appears anywhere — expected. Phase 2 has not landed in this worktree, so FB instances (`M_Elevator`, `FB_*`, etc.) still appear as bare `(?)` leaves with no children. There are no FB members for Phase 3 to classify in standalone-Phase-3 execution.
2. `--show-direction` is silent-on-null: `(showDirection && n.direction != null)` correctly suppresses the suffix on legacy leaves. CLI output is byte-identical to plain `browse` when no member carries a direction — no operator-facing noise.
3. Process completes cleanly, no crashes, no protocol errors. The classifier is exercised on every DD02 member-layout call (via `_parseVariableRecords` when `isMemberLayout == true`); with Phase 2 absent that code path is exercised only by struct types DD03 returns (DD03 returns 7 records on this PLC: 5 arrays + 1 zero-byte UDT + nothing FB-typed), so the direction surface is empty by design.

**Post-Phase-2 expectation (orchestrator reconciliation):**

Once Phase 2 lands and `M_Elevator` expands to its members, the same probe will show at least one member with `dir=input` and at least one with `dir=output`. That's the live-PLC test of the inferred byte mapping documented in `03-RESEARCH.md`. If the mapping turns out wrong (e.g. M580 uses different `unknown5` values than the table predicts), the single change-point is the switch in `classifyFbMemberDirection` — five lines, no other code moves.

---

## plc4j citations for the wire-format encoding

Per `03-RESEARCH.md` (full details there), the per-member DD02 record header is 8 bytes of:

| Byte offset | Width | plc4j field | Phase 3 use |
|---:|:---|:---|:---|
| 0-1 | uint16 LE | `dataType`   | passed through as `dataTypeId` |
| 2-3 | uint16 LE | `offset`     | passed through as `blockNo` (within-parent byte offset) |
| 4-5 | uint16 LE | `unknown5`   | classifier input #1 — direction byte |
| 6-7 | uint16 LE | `unknown4`   | classifier input #2 — direction byte |
| 8…  | bytes     | null-terminated UTF-8 name | name |

**Sources (cited in `umas_fb_direction.dart` and `03-RESEARCH.md`):**

- `/Users/jonb/go/pkg/mod/github.com/apache/plc4x@v0.13.1/protocols/umas/src/main/resources/protocols/umas/umas.mspec:214-220` — `[type UmasUDTDefinition]` mspec showing four uint16 LE fields followed by a manual vstring.
- `/Users/jonb/.m2/repository/org/apache/plc4x/plc4j-driver-umas/0.14.0-SNAPSHOT/plc4j-driver-umas-0.14.0-SNAPSHOT.jar` → `org/apache/plc4x/java/umas/readwrite/UmasUDTDefinition.class` — v0.14.0-SNAPSHOT compiled binary verified by `javap -p -c`; `staticParse` reads exactly the same four uint16 fields in the same order.
- `/Users/jonb/go/pkg/mod/github.com/apache/plc4x@v0.13.1/plc4py/plc4py/protocols/umas/readwrite/UmasUDTDefinition.py:100-128` — plc4py reference parser; matches the Java byte layout.
- `/Users/jonb/go/pkg/mod/github.com/apache/plc4x@v0.13.1/plc4py/plc4py/drivers/umas/UmasVariables.py:256-349` — plc4j's symbol resolver, confirms `unknown5` and `unknown4` are stored but never read by the variable builder. **plc4j does not classify direction**; Phase 3 owns the inference table.

The byte-to-direction mapping itself is inferred from M580 observation (see `03-RESEARCH.md` "Heuristic mapping" section). The classifier returns `unknown` for any combination not in the table; wrong inferences surface as undecorated UI in Phase 4, never as silent miscategorisation.

---

## What Phase 5 (wider UMAS sweep) should add to SWEEP

1. **Validate the direction inference table against live M580 captures of `M_Elevator` member records.** Capture the per-member DD02 response bytes (the `dump-array <typeId>` CLI for the FB type id once Phase 2 exposes it works for this — or add a new `dump-members <typeId>` flow). Compare byte 4-7 of each member record against the operator's known Control Expert / Machine Expert source declaration. Update the switch table in `umas_fb_direction.dart` if any direction byte disagrees with the prediction.
2. **Decode the `unknown4` field beyond direction.** plc4j leaves it opaque; Phase 3 only consults it for the `publicVar` discrimination. Live captures may reveal `unknown4` encodes additional metadata (writable flag, hierarchy level, alarm-relevant) orthogonal to direction — a SWEEP-XX candidate.
3. **Cross-check VAR_IN_OUT direction classification with the 0x94 read failure.** Phase 5's FB-05 stretch already plans pointer dereferencing for VAR_IN_OUT; verify that every member Phase 3 classifies as `inOut` is also the one that returns 0x94 from a direct memory read (and vice versa). If the sets disagree, either the mapping is wrong or the pointer-resolver is incomplete.
4. **Add a CI fixture for FB-member direction round-trip.** Once Phase 2 lands a Python-stub FB-member layout, add a fixture in `test/umas_stub_server.py` that returns a 4-member FB with known directions, and an end-to-end test that calls `browse()` against the stub and asserts `tree.children[N].direction == UmasFbMemberDirection.input` etc. Phase 3 ships the classifier-level unit test (sufficient for v1.1); the end-to-end stub fixture is a SWEEP refinement.

---

## Hard-constraint compliance

- All work in this worktree branch (`worktree-agent-a91e1430`). ✓
- `packages/tfc_dart/lib/core/umas_types.dart` line 1236 (Phase 1 clamp) untouched — all Phase 3 edits to that file land above line 280. ✓
- `lib/widgets/umas_browse.dart` not modified — Phase 4 territory respected. ✓
- `.planning/STATE.md` / `.planning/ROADMAP.md` not touched. ✓
- Real `git commit` runs (two commits, hooks ran cleanly — no `--no-verify`). ✓
- Live PLC at 192.168.112.159:502 (unit 255) reached, probe completed, no protocol errors. ✓

---

## Merge notes for the orchestrator

1. **No conflicts with Phase 1 (STRING clamp).** Phase 1's only edit is at `umas_types.dart:1236`; Phase 3's edits to the same file are above line 280 and at the end-of-file (no overlap).
2. **Compatible with Phase 4 (already in main as `da9d9a10`).** Phase 4's stand-in `umas_fb_browse_types.dart` declares an identical-spelling enum (`input`, `output`, `publicVar`, `inOut`, `unknown`). The orchestrator can follow Phase 4's documented merge recipe: delete `umas_fb_browse_types.dart`, point its import in `lib/widgets/browse_panel.dart` at `umas_fb_direction.dart`, and the enum names line up. The `BrowseNode.metadata['fbDirection']` carrier from Phase 4 continues to work because `UmasFbMemberDirection.name` returns the same wire-strings.
3. **Phase 2 reconciliation:** Phase 3's `direction` field on `UmasVariable` is the carrier. When Phase 2's `_readDD02Block(... isMemberLayout: true)` returns members, each `UmasVariable.direction` is populated by `_parseVariableRecords` (Phase 3's change). If Phase 2 introduces its own member-record parser (e.g. dedicated for FB types), the classifier call (`classifyFbMemberDirection(view.getUint16(4,LE), view.getUint16(6,LE))`) needs to move to Phase 2's parser — a four-line change.
4. **Phase 5 reconciliation:** Phase 5's VAR_IN_OUT stretch consumes `UmasFbMemberDirection.inOut` to identify pointer-backed members. The enum value is already in place; no Phase 3 changes needed for Phase 5 to depend on it.

---

*Phase 3 closed: 2026-05-18 by agent in worktree `agent-a91e1430`.*
