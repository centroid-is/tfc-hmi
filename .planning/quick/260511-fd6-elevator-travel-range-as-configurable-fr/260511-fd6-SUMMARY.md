---
phase: 260511-fd6
plan: 01
status: complete
status_reason: "Human visual verification approved on 2026-05-11. Travel range slider works as designed; width-only auto-deduce bug resolved."
subsystem: ui/page_creator/elevator
tags: [elevator, travel-range, config, json-serializable, slider, goldens, 260511-fd6]

# Dependency graph
requires:
  - phase: 260511-dxa
    provides: "Travel-range-as-tallest-child auto-deduce in _buildStack + 4-arg platformOffsetTop signature (replaced here by operator-explicit config field)."
  - phase: 260511-ehy
    provides: "Per-child offsetY anchor field (preserved bit-identically at offsetY=0)."
provides:
  - "ElevatorConfig.travelRange field (double, default 1.0, @JsonKey(defaultValue: 1.0))"
  - "Operator-explicit Slider (range 0..1, divisions=100) in _ElevatorConfigEditor"
  - "Removal of children.map().reduce(max) auto-deduce in _buildStack"
  - "Regenerated widget-level goldens (progress_50.png and progress_100.png)"
  - "Back-compat: legacy JSON without travelRange restores to 1.0"
affects: [elevator, page_creator, future elevator visual edits]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Operator-explicit config field replaces auto-deduce — fixes width-affects-height coupling bug"
    - "JsonKey defaultValue back-compat shim for new schema fields (mirrors 260511-ehy offsetY precedent)"
    - "Documentation rename in shared helper (`platformOffsetTop`) when parameter semantics shift but math is unchanged"

key-files:
  created: []
  modified:
    - "lib/page_creator/assets/elevator.dart"
    - "lib/page_creator/assets/elevator.g.dart"
    - "lib/page_creator/assets/elevator_layout.dart"
    - "lib/page_creator/assets/elevator_painter.dart"
    - "test/page_creator/assets/elevator_config_test.dart"
    - "test/page_creator/assets/elevator_widget_test.dart"
    - "test/page_creator/assets/elevator_layout_test.dart"
    - "test/page_creator/assets/goldens/elevator_with_children_progress_50.png"
    - "test/page_creator/assets/goldens/elevator_with_children_progress_100.png"

key-decisions:
  - "travelRange is operator-explicit (Slider), not auto-deduced — the auto-deduce coupled child WIDTH to platform travel (via the `shortestSide / 4` intrinsic-height fallback for unset children), which surfaced as the original width-affects-height bug."
  - "Default 1.0 (full headroom climb) restores the pre-260511-dxa visual — pages saved before any auto-deduce existed will render bit-identically."
  - "Child overhang at high travelRange is the operator's responsibility — locked tradeoff, Stack(Clip.none) tolerates the overflow."
  - "Local variable name `maxChildHeight` retained in _buildStack / ElevatorPainter to minimise diff — only semantics changed (now `effective travel in pixels`)."
  - "Painter-level goldens are NOT regenerated: the painter harness passes `maxChildHeight: 100.0` as an explicit numeric, unchanged by the config schema."

patterns-established:
  - "Operator-explicit > auto-deduce when an auto-deduce couples unrelated dimensions"
  - "When a parameter's MEANING changes but the math is identical, update docstrings + tests but not the math"

requirements-completed: [ELEV-10]

# Metrics
duration: ~35 min
completed: 2026-05-11
---

# Plan 260511-fd6: Elevator Travel Range as Configurable Fraction Summary

**ElevatorConfig.travelRange (double, default 1.0) replaces the child-height auto-deduce in _buildStack; operator picks travel via a 0..1 Slider in the config editor.**

## Performance

- **Duration:** ~35 min (RED tests + GREEN impl + golden regen, paused before checkpoint commit)
- **Started:** 2026-05-11T10:46Z (approx — first RED commit at 0fdc040)
- **Completed (so far):** 2026-05-11T11:18Z (golden regen done; awaiting human approval)
- **Tasks:** 2 of 3 complete (Task 3 paused at human-verify checkpoint)
- **Files modified:** 9 (4 lib + 3 test + 2 goldens; goldens staged but uncommitted pending approval)

## Status: INCOMPLETE — checkpoint pending

Plan execution paused at Task 3's `checkpoint:human-verify` gate. The two regenerated widget goldens are STAGED but NOT committed; the SUMMARY/STATE updates are also pending human approval per the plan's locked workflow.

## Accomplishments

- **Schema:** `ElevatorConfig.travelRange` added with `@JsonKey(defaultValue: 1.0)`; codegen regenerated; legacy JSON without the key restores to 1.0 (back-compat lock).
- **Runtime:** `_buildStack` no longer reads child heights to compute travel. The local variable `maxChildHeight` is now `(config.travelRange.clamp(0,1) × paintSize.height).clamp(0, headroom)` — operator-explicit, decoupled from child sizes.
- **Editor:** Slider (range 0..1, divisions=100) with percentage label and helper text inserted between the position-key field and the simulate switch. Mutates `config.travelRange` in real time.
- **Goldens:** `elevator_with_children_progress_50.png` and `..._100.png` regenerated to reflect the new default travelRange=1.0 visual. `progress_0.png` is byte-identical (platform at bottom regardless of travel range) and untouched.
- **Tests:** 140/140 elevator tests pass.

## Task Commits

1. **Task 1 — RED:** `0fdc040` (test) — failing tests for travelRange field, geometry, editor slider.
2. **Task 2 — GREEN:** `8b396d8` (feat) — travelRange field + codegen + _buildStack rewrite + editor slider + test-fixture adjustments for OffsetY group + slider-locator shifts + ensureVisible on Add child.
3. **Task 3 — REFACTOR (paused at checkpoint):** widget goldens regenerated and staged; commit deferred until human approves the visual.

## Files Created/Modified

- `lib/page_creator/assets/elevator.dart` — Added `travelRange` field with `@JsonKey(defaultValue: 1.0)`, updated constructor, replaced auto-deduce block in `_buildStack`, inserted Slider + label + helper text in `_ElevatorConfigEditor`, dropped unused `max` from `dart:math` import.
- `lib/page_creator/assets/elevator.g.dart` — Regenerated by `dart run build_runner build --delete-conflicting-outputs`; fromJson defaults missing travelRange to 1.0; toJson always emits the field.
- `lib/page_creator/assets/elevator_layout.dart` — Docstring update; the 4th parameter (`maxChildHeight`) is semantically "the platform's vertical travel range" as of this plan. Math unchanged.
- `lib/page_creator/assets/elevator_painter.dart` — Docstring update on `maxChildHeight` field; now "travel range driver" derived from `config.travelRange × bbox height`. Field name retained to minimise diff.
- `test/page_creator/assets/elevator_config_test.dart` — Added 3 tests for travelRange (default 1.0, round-trip at 0.7, back-compat legacy JSON).
- `test/page_creator/assets/elevator_widget_test.dart` — Updated `children Positioned.top follows _animProgress` numerics for default travelRange=1.0; DELETED `children Positioned.top clamps to >= 0` test (its invariant no longer holds at default); added new "TravelRange (260511-fd6)" group (4 geometry tests); added "Travel range editor slider (260511-fd6)" group (2 editor tests); pinned `travelRange = childH/bboxH` on OffsetY anchor fixtures (regression-guard preserved bit-identically); ensureVisible before Add-child taps (3 sites); shifted offsetX/offsetY slider locators to index 1/2 to skip the new config-level travel-range slider at index 0.
- `test/page_creator/assets/elevator_layout_test.dart` — Added semantic-rename documentation test locking the 4th-arg semantics as "travel range, not child height".
- `test/page_creator/assets/goldens/elevator_with_children_progress_50.png` — Regenerated. Platform now sits at vertical centre with children fully inside the bbox (default travelRange=1.0 → effectiveTravel=276 → platformY=138 at progress=0.5).
- `test/page_creator/assets/goldens/elevator_with_children_progress_100.png` — Regenerated. Platform at bbox top; children have ridden up and now overhang the bbox top (locked tradeoff at high travelRange with mid-sized children).

## Decisions Made

See `key-decisions` in the frontmatter. The most consequential ones:

1. **Default travelRange = 1.0**, not 0.5 or "auto." Restores the pre-260511-dxa "full headroom climb" visual that operators learned during Phase 2. Operators who want shorter travel can dial it down via the slider.
2. **Field name `maxChildHeight` kept** in the painter and the helper signature. The math is unchanged; only the meaning shifted. A wider rename would have churned far more code (painter + 17 layout tests + multi-elevator tests + simulate tests) for zero behaviour gain. The new doctring + the layout-test "semantics" documentation lock make the new meaning grep-discoverable.
3. **Pin `travelRange = childH / bboxH`** on the OffsetY anchor regression-guard fixtures. The offsetY contract (offsetY=0 → bottom-on-platform; +/- moves the anchor) is independent of travel range — but the absolute geometry the tests were written against assumed `maxChildHeight = childH`. Pinning travelRange preserves the bit-identical contract without forking the test math.

## Key Invariants Preserved

- **offsetY semantics (260511-ehy):** `top = platformY - childH * (1 + offsetY)` — bit-identical at offsetY=0; positive raises, negative lowers. All 3 OffsetY tests pass.
- **Pitfall 1 (child State identity):** 50 progress changes → 1 initState. Test passes unchanged.
- **Pitfall 2 (stream lifecycle):** 100 rebuilds with same positionKey → identical stream reference. Test passes unchanged.
- **Out-of-range (ELEV-15):** Stream value > 100 or < 0 still clamps + sets isOutOfRange. All 4 tests pass.
- **Multi-elevator independence (QUAL-06):** Two elevators with different positionKeys remain isolated. Test passes unchanged.
- **Leak contract (QUAL-07):** Mount/unmount cancels stream + disposes notifiers + cancels sim timer. Tests pass unchanged.
- **Simulate (QUAL-08):** All 7 simulation tests pass — sim timer behaviour, mutual-exclusivity with PLC stream, dispose cleanup.
- **Polymorphic child dispatch (ELEV-11):** No `is SensorConfig`/`is ConveyorConfig`/runtimeType-switch added. Source-level grep gate still passes.
- **allKeys flat-map (ELEV-13):** Test pass unchanged — `travelRange` is not a state-key field, so allKeys is untouched.
- **Editor surface (ELEV-07/08):** Add/edit/remove/reorder + offsetX/offsetY sliders still pass — locator indices shifted by +1 to accommodate the new travel-range slider at index 0.
- **JSON round-trip stability:** All 6 JSON round-trip tests pass; default ElevatorConfig now carries `travelRange: 1.0` in the canonical shape.
- **AssetRegistry registration (ELEV-16/18):** Unchanged. Saved pages without `travelRange` still parse cleanly via the back-compat default.

## Locked Tradeoff

**Child overhang at high travelRange is the operator's responsibility.** With default `travelRange = 1.0` and any child shorter than the headroom, the child will visually extend above the bbox at high progress values. `Stack(clipBehavior: Clip.none)` tolerates this overflow. Operators who want children kept inside the bbox can dial `travelRange` down to `childH / bboxH` (the pre-260511-fd6 auto-deduced value) — but they pick it explicitly now.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug in existing tests, caused by deliberate schema change] OffsetY anchor regression-guard fixtures referenced the old auto-deduced geometry.**
- **Found during:** Task 2 GREEN verification — `flutter test test/page_creator/assets/elevator_widget_test.dart` initially failed in the OffsetY group (3 tests) with `expected 216.0, got 98.0` (etc.) at progress=0.5/0.0.
- **Issue:** The OffsetY tests' fixtures relied on `maxChildHeight = childH = 40` (the old auto-deduce). With the new default `travelRange = 1.0`, effectiveTravel = 276, so the platform sits 138px lower than the assertions expected.
- **Fix:** Pin `travelRange = childH / bboxH ≈ 0.1333` on each of the three OffsetY fixtures. The math the tests assert is now bit-identical to the pre-change behaviour. The offsetY contract itself (locking offsetY=0/+0.5/-0.5 semantics relative to platformY) is unchanged and still passes.
- **Files modified:** `test/page_creator/assets/elevator_widget_test.dart` (3 fixture sites in the OffsetY group; const `travelRangeFor40pxChild` added).
- **Verification:** All 3 OffsetY tests pass; the offsetY=0 regression-guard still asserts `top = platformY - childH` exactly.
- **Committed in:** `8b396d8` (Task 2 commit).

**2. [Rule 1 — Bug in existing tests, caused by editor widget addition] Editor child-management tests failed because the new travel-range slider pushed the "Add child" button below the 600px test viewport.**
- **Found during:** Task 2 GREEN verification — 3 tests in `Editor — child management` failed with "Offset(...) is outside the bounds of the root render tree, Size(800.0, 600.0)" when tapping `find.widgetWithText(FilledButton, 'Add child')`.
- **Issue:** The newly-inserted Slider + label + helper-text widgets in `_ElevatorConfigEditor` increased the editor body's vertical extent by ~70px. The "Add child" button (which previously fit) now lives below the visible viewport, and direct `tester.tap()` falls back to a hit-test miss warning + a downstream "no Sensor option" assertion failure.
- **Fix:** Added `tester.ensureVisible(addBtn) + pumpAndSettle` before `tap` in the 3 affected tests, mirroring the existing precedent from the `Edit button` and `Remove button` tests.
- **Files modified:** `test/page_creator/assets/elevator_widget_test.dart` (3 sites).
- **Verification:** All 3 editor-management tests pass.
- **Committed in:** `8b396d8` (Task 2 commit).

**3. [Rule 1 — Bug in existing tests, caused by Slider order shift] offsetX/offsetY slider locator tests used `find.byType(Slider).first` / `.at(1)`, but the new config-level travel-range slider now sits at index 0.**
- **Found during:** Task 2 GREEN verification — the two slider-mutation tests failed because their locators pointed at the wrong Slider widget.
- **Issue:** As of Plan 260511-fd6 the editor renders three Sliders when a child is present: travel-range (config level, index 0), then per-child offsetX (index 1) and offsetY (index 2). The old tests assumed offsetX at index 0 and offsetY at index 1.
- **Fix:** Shifted locators by +1 — offsetX at `.at(1)`, offsetY at `.at(2)`. Inline comment documents the new order.
- **Files modified:** `test/page_creator/assets/elevator_widget_test.dart` (2 sites).
- **Verification:** Both slider-mutation tests pass.
- **Committed in:** `8b396d8` (Task 2 commit).

---

**Total deviations:** 3 auto-fixed (all Rule 1 — bugs in existing tests caused by the deliberate design change in this plan, not unrelated regressions).
**Impact on plan:** All three deviations were predictable mechanical consequences of the schema/UI change and were resolved without altering the design. No scope creep.

## Tests Added / Updated / Removed

### Added
- `elevator_config_test.dart`: 3 tests in `JSON round-trip` group — default travelRange, round-trip, legacy back-compat.
- `elevator_layout_test.dart`: 1 test in `platformOffsetTop` group — effective-travel semantics documentation lock.
- `elevator_widget_test.dart`: 4 tests in new `TravelRange (260511-fd6)` group — default=1.0 / 0.5 / 0.0 / clamp=1.5.
- `elevator_widget_test.dart`: 2 tests in new `Travel range editor slider (260511-fd6)` group — slider mutates, label format.

### Updated
- `elevator_widget_test.dart` `children Positioned.top follows _animProgress` — recomputed expected numerics for default travelRange=1.0 (top at -40 at progress=1.0, overhang permitted). Direction lock (topAt0 > topAt1) unchanged.
- `elevator_widget_test.dart` OffsetY anchor group — pinned `travelRange = childH/bboxH` on all 3 fixtures to preserve bit-identical offsetY geometry.
- `elevator_widget_test.dart` Editor child-management group — 3 sites add `ensureVisible(addBtn) + pumpAndSettle` before `tap`.
- `elevator_widget_test.dart` offsetX/offsetY slider tests — locator indices shifted from `.first` / `.at(1)` to `.at(1)` / `.at(2)`.

### Removed
- `elevator_widget_test.dart` `children Positioned.top clamps to >= 0 at progress=1.0 (child remains inside bbox)` — invariant no longer holds at default travelRange=1.0 (child overhang is the locked operator-tradeoff). Replaced with an explanatory comment block pointing to the new TravelRange group. Per TDD discipline: deliberately removed because the invariant ceased to reflect the locked design (not a regression).

## Issues Encountered

None beyond the three auto-fixed deviations above.

## Self-Check

**Files created/modified verified:**
- `lib/page_creator/assets/elevator.dart` — FOUND
- `lib/page_creator/assets/elevator.g.dart` — FOUND (contains `travelRange` at 2 sites)
- `lib/page_creator/assets/elevator_layout.dart` — FOUND
- `lib/page_creator/assets/elevator_painter.dart` — FOUND
- `test/page_creator/assets/elevator_config_test.dart` — FOUND
- `test/page_creator/assets/elevator_widget_test.dart` — FOUND
- `test/page_creator/assets/elevator_layout_test.dart` — FOUND
- `test/page_creator/assets/goldens/elevator_with_children_progress_50.png` — FOUND (regenerated, staged)
- `test/page_creator/assets/goldens/elevator_with_children_progress_100.png` — FOUND (regenerated, staged)

**Commits verified in git log:**
- `0fdc040` (test RED) — FOUND
- `8b396d8` (feat GREEN) — FOUND

## Self-Check: PASSED

## Awaiting (Checkpoint)

Human visual approval of the two regenerated widget goldens. Once approved, the orchestrator will:
1. Commit the staged goldens (`test(260511-fd6): REFACTOR — regenerate widget goldens for travelRange=1.0 default`).
2. Update STATE.md `Quick Tasks Completed` table.
3. Flip this SUMMARY's status from `incomplete` to `complete`.
4. Final commit covering SUMMARY.md + STATE.md.

## Follow-ups

None expected. The plan landed all locked decisions and preserved every invariant from earlier plans. Future plans that touch `_buildStack` should be aware that the local var name `maxChildHeight` now means "effective travel in pixels," not "tallest child height" — the docstring on `platformOffsetTop` and `ElevatorPainter.maxChildHeight` are the source of truth.

---
*Phase: 260511-fd6 (quick task)*
*Status: incomplete — paused at Task 3 human-verify checkpoint*
*As of: 2026-05-11T11:18Z*
