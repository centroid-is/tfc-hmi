---
phase: 5
plan: 5.1
requirements: [FB-05, SWEEP-01]
status: complete
worktree: worktree-agent-ad776bc2
base_commit: f9c6df1979b3778e14abce6f77ff09a0f0875a98
commits:
  - 6a4b0857 plan(phase-5): VAR_IN_OUT stretch + UMAS sweep candidates
  - 4dc98532 feat(umas): FB-05 graceful labeling + SWEEP-03/04/05 hardening
---

# Plan 5.1 SUMMARY — VAR_IN_OUT stretch + UMAS sweep

## VAR_IN_OUT decision (FB-05)

**Path (b) — graceful labeling.** plc4j (Apache PLC4X) does NOT
implement pointer-resolution for VAR_IN_OUT (verified by direct
inspection of
`https://github.com/apache/plc4x/blob/develop/plc4j/drivers/umas/src/main/java/org/apache/plc4x/java/umas/readwrite/protocol/UmasProtocolLogic.java`,
quoted in `05-RESEARCH-IN_OUT.md`: "treats all symbols uniformly as
readable/writable entities without explicit support for parameter
direction metadata"). Path (a) would require fresh wire-format
discovery work outside the days-timeline budget.

### What shipped

1. New `packages/tfc_dart/lib/core/umas_fb_direction.dart`
   - `UmasFbMemberDirection` enum: `input`, `output`, `inOut`,
     `publicVar`, `unknown`
   - `classifyFbMemberDirection(unknown5, unknown4)` — Phase 3 stub
     contract; the wire-byte mapping is empirical per
     `.planning/phases/03-...`
2. New `packages/tfc_dart/lib/core/umas_var_in_out.dart`
   - `unreadableReasonForDirection(direction)` — returns
     `"VAR_IN_OUT (PLC returns 0x94; plc4j drops with reason)"` for
     the in_out direction, `null` otherwise. The literal "VAR_IN_OUT"
     and "0x94" substrings are part of the FB-05 contract.
   - `isReadableForDirection(direction)` — returns `false` for
     `inOut`, `true` otherwise.
3. Extended `UmasVariableTreeNode` (in `umas_types.dart`) with
   additive backward-compatible fields:
   - `UmasFbMemberDirection? direction`
   - `bool readable` (default `true`)
   - `String? unreadableReason`
   - `toString()` updated to include the new fields when non-default.

### Integration point for orchestrator merge

Phase 2's FB expansion code (not in this worktree) constructs
`UmasVariableTreeNode` instances for FB members. When merging,
Phase 2's expander should:

```dart
import 'umas_fb_direction.dart';
import 'umas_var_in_out.dart';

// In the per-member loop where the DD02 record's unknown5/unknown4
// bytes are available:
final direction = classifyFbMemberDirection(unknown5, unknown4);
children.add(UmasVariableTreeNode(
  name: member.name,
  path: '$parentPath.${member.name}',
  variable: member,
  dataType: resolvedType,
  direction: direction,
  readable: isReadableForDirection(direction),
  unreadableReason: unreadableReasonForDirection(direction),
));
```

This is a 5-line addition, fully testable, with no protocol changes.

## Sweep candidate count

**Surfaced:** 8 (see `05-SWEEP-CANDIDATES.md`).
**Accepted into v1.1:** 3 new REQ-IDs.
**Folded into existing Phase 1 scope:** 1 (C-04 — 0x50 vs 0x22
STRING divergence, already in BUG-01/02).
**Deferred to v2:** 4 (with v2 entries — MON-01, RETRY-01, TYPE-01;
1 cross-layer doc-only).

### New REQ-IDs created (for orchestrator to fold into REQUIREMENTS.md)

- **SWEEP-03**: UMAS error messages include sub-function name.
  Doc-string contract on `_checkStatus`; tests pin the format.
- **SWEEP-04**: `_handleSessionError()` clears `_projectCrc` so a
  PLC reboot mid-session doesn't carry stale CRC into next session.
- **SWEEP-05**: `_log.w()` when `writeVariable` /
  `readVariable` truncates at the 255-ref cap, so silent data loss
  is visible in operator logs.

All 3 implemented in commit `4dc98532` with regression tests.

### v2 entries (deferred)

- **MON-01**: monitor-table recovery after PLC reboot (adapter
  re-registers entries after session re-pair).
- **RETRY-01**: UI badge / toast when database retry queue saturates.
- **TYPE-01**: extend `UmasDataTypes` test coverage to BYTE_STRING,
  WSTRING, multi-dim arrays once a customer PLC declares them.

## Must-haves and verification status

| Phase 5 success criterion | Status |
|---|---|
| FB-05 decision recorded (a or b) | ✓ Path (b) — see 05-RESEARCH-IN_OUT.md |
| No silent omission of VAR_IN_OUT members | ✓ `readable=false` + `unreadableReason` on tree node |
| Code comment cites plc4j drop-with-reason | ✓ In `umas_var_in_out.dart` library doc |
| SWEEP-01: candidate list written | ✓ 8 candidates in 05-SWEEP-CANDIDATES.md |
| SWEEP-01: triage decisions logged | ✓ 05-SWEEP-TRIAGE.md |
| Accepted SWEEP items get new REQ-IDs | ✓ SWEEP-03/04/05 |
| Accepted SWEEP items implemented | ✓ Commit 4dc98532 |
| Live PLC `check` pass rate preserved | ✓ 35/35 (same as baseline) |
| Existing tfc_dart unit tests stay green | ✓ 631 tests pass |
| New unit-test count | +21 (15 fb_direction + 6 sweep) |

## Live PLC verification

```
$ dart run packages/tfc_dart/tool/umas_cli.dart check 192.168.112.159 --json
{
  "roots": 58, "leaves": 58,
  "scalars": {"ok": 35, "fail": 0},
  "arrays": {"ok": 0, "fail": 0, "fb_in_out": 0, "count": 0, ...},
  "failures": []
}
```

Identical to baseline before changes. No regression.

## Files touched (commit 4dc98532)

| File | Change |
|---|---|
| `packages/tfc_dart/lib/core/umas_fb_direction.dart` | NEW — Phase 3 stub contract |
| `packages/tfc_dart/lib/core/umas_var_in_out.dart` | NEW — Phase 5 / FB-05 helpers |
| `packages/tfc_dart/lib/core/umas_types.dart` | extended `UmasVariableTreeNode` |
| `packages/tfc_dart/lib/core/umas_client.dart` | SWEEP-03 doc / SWEEP-04 / SWEEP-05 |
| `packages/tfc_dart/test/umas_fb_direction_test.dart` | NEW — 15 tests |
| `packages/tfc_dart/test/umas_sweep_test.dart` | NEW — 6 tests |

Plus the planning docs in commit `6a4b0857`.

## Coordination notes for the orchestrator

1. **Phase 2 wiring.** Phase 2's FB expander needs to call
   `classifyFbMemberDirection(unknown5, unknown4)` and populate the
   new tree-node fields. See "Integration point" section above for
   exact code. If Phase 2 also adds an enum, dedupe — Phase 3's
   research file is the canonical source of the byte mapping.

2. **Phase 3 enum compatibility.** Phase 3 may have a different
   set of enum values (e.g. `inputDir` vs `input`). The
   names chosen here (`input`, `output`, `inOut`, `publicVar`,
   `unknown`) match the pre-existing stub test that was planted in
   the worktree (`packages/tfc_dart/test/core/umas_fb_direction_test.dart`
   from the orchestrator — disappeared mid-session but the contract
   it pinned is preserved here in `test/umas_fb_direction_test.dart`).
   If Phase 3 lands with different names, the orchestrator should
   reconcile on Phase 3's side since Phase 3 owns the canonical
   classifier.

3. **REQUIREMENTS.md update at merge.** Add SWEEP-03, SWEEP-04,
   SWEEP-05 to the v1.1 Active section under
   `### Wider Sweep (planner-discovered)`. Add MON-01, RETRY-01,
   TYPE-01 to v2. See `05-SWEEP-TRIAGE.md` for exact text.

4. **No conflicts expected with Phase 1 (string clamp).** Phase 1
   touches `umas_types.dart:1232-1237` (`parseReadAllResponse`);
   this plan touches `umas_types.dart:1-5` (import) and the
   `UmasVariableTreeNode` class around lines 232-285. No overlap.

5. **No conflicts expected with Phase 4 (UI).** Phase 4 consumes
   the new tree-node fields read-only. No code-merge conflicts.
