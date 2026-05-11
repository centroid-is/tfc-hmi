---
phase: 04-polish-error-ux-and-ci-hardening
plan: 03
subsystem: ui
tags: [elevator, editor, z-order, reorder, photoshop-convention, tdd, polish]

requires:
  - phase: 03-elevator-child-embedding
    provides: ElevatorChildEntry wrapper with stable UUID, _ElevatorConfigEditor add/edit/remove rows, Stack-based paint order over config.children
  - phase: 04-polish-error-ux-and-ci-hardening (plan 04-02)
    provides: Editor row/test conventions reused as the paint/regression baseline this plan extends
provides:
  - Up/down arrow IconButtons on every child row in _ElevatorConfigEditor that swap z-order in config.children
  - Photoshop/Figma display convention — editor list is rendered config.children.reversed (topmost paint at the top)
  - _onReorderChildPressed(entry, delta) handler: id-based lookup + neighbour-bounds gate, idempotent at boundaries
  - Disabled-button UX guard at boundaries (topmost row's "Move forward" disabled; bottommost row's "Move backward" disabled)
  - 5 widget tests locking the contract (display reversal, swap-on-tap, both boundary disables, paint-order-follows-list, ValueKey identity preservation)
affects: [page-creator-editor-conventions, future-multi-child-z-order-features]

tech-stack:
  added: []
  patterns:
    - "Photoshop/Figma display convention for layered child lists in HMI editors (visual-order = reversed list-order)"
    - "Defensive UI handlers — disabled buttons are a UX hint, the handler's neighbour-bounds check is the safety net (T-04-03-A)"
    - "id-based mutation lookup (indexWhere on entry.id) so handlers stay correct under reversed/sorted display orders"

key-files:
  created: []
  modified:
    - lib/page_creator/assets/elevator.dart (+58 lines: _onReorderChildPressed handler, reversed display loop, two new IconButtons per row)
    - test/page_creator/assets/elevator_widget_test.dart (+202 lines: new 'Editor — child reorder (z-order)' group, 5 tests)

key-decisions:
  - "Display the editor child list REVERSED relative to config.children (Photoshop/Figma convention) — topmost paint at top of editor"
  - "Up arrow raises z (later in config.children = paints later = on top); down arrow lowers z"
  - "Stack composition in build() left untouched — paint order continues to follow config.children index, so list mutation alone re-orders paint without runtime widget changes"
  - "Reorder handler looks up by entry.id (indexWhere), not by display index — robust against display reversal and future re-sorts"
  - "Boundary safety is enforced by the handler (j < 0 || j >= length → noop), not just by disabling buttons (T-04-03-A defence-in-depth)"

patterns-established:
  - "Editor list visual order MAY differ from data list order; always document the convention and lock it with a widget test"
  - "Reorder handlers in _ConfigEditor states should accept (entry, delta) signature and look up by id, not index"

requirements-completed: [ELEV-08, QUAL-08]

duration: ~25min
completed: 2026-05-06
---

# Phase 4 Plan 03: Editor Z-Order Reordering Summary

**Operators can now reorder z-order of overlapping children on an elevator platform via up/down arrow buttons in the editor, following the Photoshop/Figma convention (top of editor = paints on top).**

## Performance

- **Duration:** ~25 min (plan scaffold → RED → GREEN → SUMMARY)
- **Started:** 2026-05-06T13:25Z
- **Completed:** 2026-05-06T13:30Z
- **Tasks:** 2 (RED + GREEN per the TDD plan)
- **Files modified:** 2 (1 lib + 1 test)

## Accomplishments

- Added two IconButtons (`Icons.arrow_upward` "Move forward (paint on top)" / `Icons.arrow_downward` "Move backward (paint behind)") on every child row in `_ElevatorConfigEditor`, with disabled state at the topmost/bottommost boundaries.
- Reversed the editor's child-list display so the topmost-paint child appears at the top of the editor — matching operator muscle memory from Photoshop/Figma layer panels.
- Locked the contract with 5 deterministic widget tests covering: swap on tap, both boundary disables, paint order follows list order under reorder, and ValueKey identity preservation across the swap.

## Task Commits

TDD cadence preserved: `docs → test (RED) → feat (GREEN)`, no refactor needed.

1. **Plan scaffold** — `a3b326b` (docs(04-03)): scaffold editor z-order reorder plan
2. **Task 1 RED** — `1b9a3e5` (test(04-03)): add failing tests for editor z-order reorder controls (5 new widget tests in 'Editor — child reorder (z-order)' group; 4 RED, 1 baseline regression guard)
3. **Task 2 GREEN** — `dd9f6c7` (feat(04-03)): add z-order reorder controls to elevator child editor (ELEV-08) — `_onReorderChildPressed` handler, reversed display loop, two new IconButtons per row, plus a Rule-1 test fix (use `find.ancestor` for the disabled-button assertions because raw `find.byTooltip` returns the Tooltip widget, not the IconButton)

## Files Created/Modified

- `lib/page_creator/assets/elevator.dart` — added `_onReorderChildPressed` handler (id-based swap with neighbour-bounds gate), reversed the editor's child-list display loop, added two new IconButtons per row with boundary-aware `onPressed` (null at extremes)
- `test/page_creator/assets/elevator_widget_test.dart` — added new `group('Editor — child reorder (z-order)', ...)` at line 829 with 5 widget tests

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Editor renders `config.children.reversed` | Photoshop/Figma convention — operators expect topmost paint at top of layer list. UX-locked in plan context. |
| Up arrow raises z (later in list) | Matches the convention: "move toward viewer" = "move forward" = "paint on top". |
| Stack composition in `build()` untouched | Stack already iterates `config.children` index 0 → N-1, painting in order. Reordering the list naturally re-orders paint, so no runtime widget code needs to change — only the editor. Minimises blast radius. |
| Handler uses `indexWhere(e => e.id == entry.id)`, not display index | Robust against the reversed display and any future sorts. The display reversal is a view-layer concern; mutation is always on the canonical list. |
| Boundary safety in BOTH handler and UI | Disabled buttons are a UX hint, but `_onReorderChildPressed` also rejects out-of-range targets (T-04-03-A) — defence-in-depth in case button-disabled state lags a frame or is bypassed in tests. |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Disabled-button assertions targeted the wrong widget type**

- **Found during:** Task 2 (GREEN), running the new 'topmost has Move forward disabled' / 'bottommost has Move backward disabled' tests against the implementation.
- **Issue:** The original tests used `tester.widget<IconButton>(find.byTooltip('Move forward (paint on top)'))` to read `onPressed`. `find.byTooltip` matches the `Tooltip` widget that wraps the IconButton, not the IconButton itself, so the cast hit a `RawTooltip` and the assertion failed for the wrong reason.
- **Fix:** Switched to `find.ancestor(of: find.byTooltip(...), matching: find.byType(IconButton))` so the finder reaches the actual IconButton whose `onPressed` is being asserted.
- **Files modified:** `test/page_creator/assets/elevator_widget_test.dart` (the two boundary tests)
- **Verification:** Both boundary tests now pass deterministically; full test file passes 43/43.
- **Committed in:** `dd9f6c7` (folded into the GREEN feat commit alongside the production change, since the test was discovered failing for the wrong reason during the same iteration; both halves are required for green).

## Quality Gate Verification

- ✅ All Phase 1+2+3+4 tests still pass (page_creator/ test directory: 312/312 green; full elevator_widget_test.dart: 43/43)
- ✅ 5 new reorder tests pass deterministically 5/5 reruns
- ✅ TDD cadence: `1b9a3e5` (test) precedes `dd9f6c7` (feat)
- ✅ Editor row visual order is REVERSED relative to actual list (Photoshop convention)
- ✅ Topmost child has 'Move forward' disabled; bottommost has 'Move backward' disabled (locked by 2 tests)
- ✅ `flutter analyze` clean on both modified files (0 issues)

## TDD Gate Compliance

Plan-level gate sequence verified in git log:
- ✅ RED gate — `test(04-03): add failing tests for editor z-order reorder controls` (`1b9a3e5`)
- ✅ GREEN gate — `feat(04-03): add z-order reorder controls to elevator child editor (ELEV-08)` (`dd9f6c7`)
- — REFACTOR gate not needed (implementation was minimal and clean)

## Threat Model Outcomes

- **T-04-03-A (Tampering — Editor reorder buttons):** Mitigated. Handler rejects out-of-range targets (`j < 0 || j >= list.length → noop`); disabled buttons at boundaries are the UX hint, the handler is the safety net. No way to corrupt the list via repeated taps or stale UI state.
- **T-04-03-B (DoS — Editor reorder loop):** Accepted. Reorder is constant-time (one swap, one `indexWhere`). No per-frame cost.

No new threat surface introduced.

## Self-Check: PASSED

- ✅ `lib/page_creator/assets/elevator.dart` exists, contains `_onReorderChildPressed`, `config.children.reversed`, `Icons.arrow_upward`, `Icons.arrow_downward`, `'Move forward (paint on top)'`, `'Move backward (paint behind)'`
- ✅ `test/page_creator/assets/elevator_widget_test.dart` line 829 contains group `'Editor — child reorder (z-order)'`
- ✅ Commit `a3b326b` (plan scaffold) present in `git log`
- ✅ Commit `1b9a3e5` (RED test) present in `git log`
- ✅ Commit `dd9f6c7` (GREEN feat) present in `git log`
- ✅ Plan file `04-03-PLAN.md` exists in phase directory
