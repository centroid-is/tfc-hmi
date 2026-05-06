---
phase: 03-elevator-child-embedding
plan: 03
subsystem: ui
tags: [flutter, dart, editor, dialog, simpledialog, filledbutton, slider, recursive-configure, polymorphic-dispatch, tdd]

# Dependency graph
requires:
  - phase: 02-elevator-foundation
    provides: ElevatorConfig + ElevatorChildEntry data model (Plan 02-02), AssetRegistry registration + Phase-2 _ElevatorConfigEditor dialog body with locked field surface (Plan 02-05)
  - phase: 03-elevator-child-embedding
    provides: Plan 03-01 — Stack composition + Positioned children (so the editor's mutations to `widget.config.children` immediately re-render via setState); Plan 03-02 — ElevatorConfig.allKeys override (so children added/removed via this UI flow into alarms/collectors automatically)
  - phase: 01-sensor-asset
    provides: SensorConfig.preview() factory + Sensor's "Detection State Key" field surface (used both as a child here and as the assertion target in the edit-flow test)

provides:
  - "Operator-facing add/edit/remove/offsetX UI for elevator children (ELEV-07, ELEV-08)"
  - "Hard-coded `_allowedChildFactories = {'Sensor': SensorConfig.preview, 'Conveyor': ConveyorConfig.preview}` map locked by 3 negative widget-test assertions (LED, Number, Button)"
  - "Recursive edit dispatch via `entry.child.configure(context)` wrapped in Dialog (any future BaseAsset attached as a child gets its own editor for free — polymorphic, no elevator-side switching)"
  - "Per-entry Slider (0..1, 100 divisions) for offsetX lateral position with real-time `entry.offsetX` mutation and live `Lateral position: NN%` label"
  - "Graceful empty-state — 'No children configured' text replaces the children list when empty (CONTEXT §Removing the last child)"
  - "Phase-2 'Children: 0 (managed in Phase 3)' read-only placeholder REMOVED from elevator.dart and from its smoke-test assertion"
  - "Regression-guard widget tests: 6 new tests under group 'Editor — child management (ELEV-07, ELEV-08)' covering filtered dropdown, append-Sensor (UUID + offsetX 0.5), append-Conveyor, edit-flow (recursive configure), remove-flow (empty-state), offsetX Slider mutation"
  - "Phase 3 closeout: all 10 Phase-3 requirements closed (ELEV-07, ELEV-08, ELEV-09, ELEV-10, ELEV-11, ELEV-12, ELEV-13, ELEV-19, QUAL-03, QUAL-08)"
affects:
  - "Phase 4 — operator-facing testing flows (manual smoke checklist in elevator_widget_test.dart will need a step covering the new add/edit/remove UI)"
  - "Any future asset that constrains its own children to a fixed allowed-types set — this plan establishes the hard-coded factory-map pattern (preferred over AssetRegistry iteration when the user has explicitly locked the allowed types)"
  - "alarm_man / collectors — children added through this UI flow into ElevatorConfig.allKeys via the Plan 03-02 override, so their state keys participate in alarm evaluation and time-series collection automatically"

# Tech tracking
tech-stack:
  added: []  # No new libraries — pure Material Flutter (FilledButton, SimpleDialog, Card, IconButton, Slider) + dart:core function-tear-offs
  patterns:
    - "Hard-coded allowed-children factory map: `static final Map<String, BaseAsset Function()> _allowedChildFactories = { 'Sensor': SensorConfig.preview, 'Conveyor': ConveyorConfig.preview };` — preferred over AssetRegistry.defaultFactories iteration when the user has locked the allowed types. Threat-model rationale: T-03-08 (operator adds arbitrary asset type) → mitigated by explicit list, NOT by registry filtering."
    - "Recursive editor dispatch via polymorphic `entry.child.configure(context)` wrapped in a `Dialog` — the elevator's editor never switches on child runtimeType. Any future BaseAsset attached as a child gets its own editor surface for free (mirrors the Plan 03-01 polymorphic-render pattern in the editor layer)."
    - "Add-child SimpleDialog flow: tapping FilledButton.icon('Add child') → showDialog<String> → SimpleDialog with one SimpleDialogOption per allowed factory key → on selection, factory() seeds a new BaseAsset and ElevatorChildEntry constructor auto-generates UUID. Chosen over showMenu/PopupMenuButton for test-reachability."
    - "tester.ensureVisible(...) before tap/drag in narrow-viewport widget tests where editor scrollables push the target below the 800x600 default test viewport."

key-files:
  created: []
  modified:
    - "lib/page_creator/assets/elevator.dart — `_ElevatorConfigEditorState` Children section rewritten: FilledButton.icon('Add child') + empty-state `Text('No children configured')` OR per-entry Card with type-name label, edit/remove IconButtons, and offsetX Slider. Three private handlers added: `_onAddChildPressed`, `_onEditChildPressed`, `_onRemoveChildPressed`. New `_allowedChildFactories` static map. Imports `SensorConfig` and `ConveyorConfig` from sibling files."
    - "test/page_creator/assets/elevator_widget_test.dart — updated existing 'all locked Phase-2 fields' smoke test to assert the new 'Add child' button and 'No children configured' empty-state (with explicit findsNothing on the removed placeholder); appended new test group 'Editor — child management (ELEV-07, ELEV-08)' with 6 widget tests."

key-decisions:
  - "SimpleDialog (rather than `showMenu` / `PopupMenuButton` / inline `AlertDialog`) for the add-child picker. Reason: option labels are reliably findable via `find.text('Sensor')` after `pumpAndSettle()` — locks the ELEV-07 filter test without a flake-prone overlay-position calculation."
  - "Hard-coded `_allowedChildFactories` map keyed by display name string (NOT by Type) — both for human-readable picker labels and for the negative-assertion gate (LED/Number/Button strings are stable). Threat-model T-03-08 explicitly disallows AssetRegistry iteration: any future-registered asset must NOT auto-appear in the elevator's add-child picker without an explicit user decision."
  - "Edit dialog uses `Dialog(child: entry.child.configure(context))` — same wrapper as `_ElevatorState._openConfigDialog` so the child's TextField/KeyField widgets find a Material ancestor. Mirrors sensor.dart precedent. The `.then((_) => setState(() {}))` after dismiss refreshes the elevator editor in case the child's fields changed."
  - "Remove uses `removeWhere((e) => e.id == entry.id)` rather than positional `removeAt(idx)`. Reason: the iteration is `config.children.map((entry) => Card(...))`, which doesn't carry an index in the closure scope. Identity-by-id is also safer if the list is mutated concurrently (e.g., another future operator action — defensive for V2)."
  - "No confirmation dialog on remove — matches conveyor.dart precedent. T-03-09 explicitly accepted: operator authority surface, no privilege escalation. Future 'Hide vs Delete' semantics are V2."
  - "tester.ensureVisible() before tapping the edit/remove IconButtons and dragging the Slider in widget tests — the editor's SingleChildScrollView puts these elements below the 800×600 default test viewport. This is a test-side adjustment (Rule 3 deviation per Plan 03-01 precedent), not a production code change."

patterns-established:
  - "Pattern: hard-coded child-factory map for parent assets that lock allowed children. Code shape: `static final Map<String, BaseAsset Function()> _allowedChildFactories = { 'Sensor': SensorConfig.preview, 'Conveyor': ConveyorConfig.preview };` plus negative widget-test assertions to lock the filter. Applies to any future parent asset that constrains its children (e.g., a multi-station 'Production Line' asset that only allows Conveyors and Augers)."
  - "Pattern: recursive sub-editor dispatch — `showDialog(builder: (_) => Dialog(child: entry.child.configure(context))).then((_) => setState(() {}))`. Locks polymorphic editor surface: parent never switches on child runtimeType, child's editor is reachable from inside the parent's editor."
  - "Pattern: SimpleDialog as test-reachable picker — when widget tests need to assert option labels (`find.text('Sensor')`) without relying on overlay-position calculation, SimpleDialog with SimpleDialogOption is the most reliable Material primitive."

requirements-completed: [ELEV-07, ELEV-08, QUAL-08]

# Metrics
duration: ~7min
completed: 2026-05-06
---

# Phase 3 Plan 3: Editor add/edit/remove/offsetX UI Summary

**Operator can attach Sensor and Conveyor children to an elevator via a hard-coded SimpleDialog picker, edit each via recursive `entry.child.configure(context)`, drag a per-entry Slider for offsetX, and remove children — closes ELEV-07/08 and the Phase-3 surface.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-05-06T12:18:24Z
- **Completed:** 2026-05-06T12:25:42Z
- **Tasks:** 3 (RED → GREEN → closeout sweep; closeout required no commit)
- **Files modified:** 2 (1 source + 1 test)

## Accomplishments

- `_ElevatorConfigEditorState` now mounts a `FilledButton.icon('Add child')` + per-entry Card list (with edit/remove IconButtons and offsetX Slider) in place of the Phase-2 `'Children: 0 (managed in Phase 3)'` read-only placeholder. The placeholder text is removed both from `elevator.dart` and from its widget-test assertion (Plan 02-05's smoke test was updated to assert the new surface).
- The add-child SimpleDialog is filtered to exactly `{'Sensor': SensorConfig.preview, 'Conveyor': ConveyorConfig.preview}` via a hard-coded `_allowedChildFactories` map. Three negative widget-test assertions (LED, Number, Button — all registered assets in `AssetRegistry.defaultFactories`) lock the filter. Threat T-03-08 (operator adds arbitrary asset type) is mitigated by the explicit list, not by registry filtering.
- Edit button opens `Dialog(child: entry.child.configure(context))` — the recursive polymorphic dispatch means any BaseAsset attached as a child surfaces its own editor without elevator-side switching. The `.then((_) => setState(() {}))` after dismiss refreshes the elevator's editor in case the child's fields changed.
- Remove button immediately deletes the entry via `removeWhere((e) => e.id == entry.id)` and refreshes; when the children list becomes empty, the editor flips to the `'No children configured'` graceful empty-state per CONTEXT §Removing the last child.
- Per-entry Slider (0..1, 100 divisions) mutates `entry.offsetX` in real time with a live `'Lateral position: NN%'` label; mirror of conveyor.dart:382-465 precedent.
- 29 widget tests pass 5/5 deterministic; 165 tests across the full elevator + sensor surface (`elevator_widget`, `elevator_config`, `elevator_painter`, `elevator_layout`, `sensor_widget`, `sensor_config`, `sensor_painter`) pass 5/5 deterministic. `flutter analyze` clean on all Phase-3 modified files.
- TDD discipline: `test(03-03):` precedes `feat(03-03):` in `git log` — `git log --oneline | grep -cE "(test|feat)\(03-03\)"` returns 2.

## Task Commits

Each task was committed atomically (TDD: RED → GREEN cadence):

1. **Task 1 [RED]: failing tests for editor add/edit/remove/offsetX + updated Phase-2 placeholder assertion** — `71d480b` (test)
2. **Task 2 [GREEN]: editor add/edit/remove/offsetX UI implemented; dropdown locked to {Sensor, Conveyor}; SimpleDialog flow; recursive configure dispatch; test-side ensureVisible adjustments** — `4a5e05d` (feat)
3. **Task 3 [closeout sweep]: 5x deterministic pass + analyze clean** — no commit (no changes required)

_Note: Plan 03-03 follows TDD discipline per QUAL-08; the plan itself is `type: execute` (not `type: tdd` at plan-level), but each behavioural assertion is locked test-first per individual task `tdd="true"` flags._

## Files Created/Modified

- `lib/page_creator/assets/elevator.dart` — `_ElevatorConfigEditorState`'s Children section rewritten (the locked Phase-2 fields above are untouched). New `_allowedChildFactories` static map. Three private handler methods: `_onAddChildPressed` (SimpleDialog flow, appends ElevatorChildEntry with auto-generated UUID), `_onEditChildPressed` (Dialog wrapping recursive `entry.child.configure(context)` + setState refresh on dismiss), `_onRemoveChildPressed` (removeWhere by entry.id + setState). New imports: `SensorConfig` from `sensor.dart`, `ConveyorConfig` from `conveyor.dart`.
- `test/page_creator/assets/elevator_widget_test.dart` — updated `'all locked Phase-2 fields'` smoke test to assert `find.widgetWithText(FilledButton, 'Add child')` + `find.text('No children configured')` + explicit `findsNothing` on the removed `'Children: 0 (managed in Phase 3)'` placeholder. Appended new test group `'Editor — child management (ELEV-07, ELEV-08)'` with 6 widget tests: filtered dropdown (3 negative assertions), append-Sensor, append-Conveyor, edit-flow, remove-flow + empty-state, offsetX Slider mutation. Added `tester.ensureVisible` before tap/drag for IconButton/Slider targets that sit below the 800×600 default test viewport.

## Decisions Made

- **SimpleDialog over showMenu/PopupMenuButton/AlertDialog for the add-child picker.** SimpleDialog's option labels are reliably findable via `find.text('Sensor')` in widget tests after `pumpAndSettle()` — no overlay-position math, no flake risk. The locked behaviour is "tap Add child → see Sensor + Conveyor options → pick one → child appended"; SimpleDialog is the most direct Material primitive.
- **Hard-coded `_allowedChildFactories` map keyed by display-name string (NOT Type).** Picker labels are the natural map keys; the negative-test assertion strings (LED, Number, Button) are stable; future-registered assets must not auto-appear (T-03-08 mitigation). Per CONTEXT §specifics, this is "the safer expression of the locked decision".
- **Recursive edit via `Dialog(child: entry.child.configure(context))`.** Reuses the same Dialog-wrap pattern as `_ElevatorState._openConfigDialog` (sensor.dart:256-263 precedent) so the child's TextField/KeyField widgets find a Material ancestor.
- **Identity-by-id removal (`removeWhere((e) => e.id == entry.id)`) rather than positional `removeAt(idx)`.** The Card iteration uses `.map((entry) => Card(...))` which doesn't carry an index in closure scope. Identity-by-id is also safer if the list is mutated concurrently (V2 defensiveness).
- **No confirmation dialog on remove** — matches conveyor.dart precedent; T-03-09 explicitly accepted (operator authority surface). Future Hide vs Delete semantics are V2.
- **`tester.ensureVisible(...)` before tap/drag in widget tests** — the editor's SingleChildScrollView puts the IconButton and Slider below the 800x600 default test viewport when a child Card is present. ensureVisible is the canonical Flutter test pattern for narrow viewports; not a production code change.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Editor IconButton/Slider hit-test fails in narrow test viewport**
- **Found during:** Task 2 (GREEN — first run after implementing the editor UI).
- **Issue:** With one ElevatorChildEntry mounted in the editor, the per-child Card (with edit/remove IconButtons + offsetX Slider) extended below the 800×600 default test viewport. Three widget tests failed: edit-flow, remove-flow, offsetX-Slider drag. Flutter's hit-test warning showed offsets like `(476.0, 556.0)` not actually hitting the IconButton's RenderBox — they were below the viewport edge.
- **Fix:** Test-side adjustment only — added `await tester.ensureVisible(target); await tester.pumpAndSettle();` before each `tester.tap(...)` / `tester.drag(...)` for the in-Card widgets. The editor's SingleChildScrollView naturally scrolls to expose the target. No production code change — the editor renders correctly in real-app dialogs which size to content (not bound by 800x600).
- **Files modified:** test/page_creator/assets/elevator_widget_test.dart (3 tests: edit-flow, remove-flow, offsetX-Slider).
- **Verification:** All 6 new editor tests + 1 updated Phase-2 smoke test pass; full elevator + sensor surface (165 tests) passes 5/5 deterministic.
- **Committed in:** `4a5e05d` (Task 2 GREEN commit, alongside the editor implementation).

---

**Total deviations:** 1 auto-fixed (Rule 3 — blocking, test-side viewport scroll).
**Impact on plan:** Zero scope creep. Mirror of Plan 03-01 deviation 2 (test-side fixture adjustment for narrow viewport hit-target). The production editor surface matches the plan's `<behavior>` section verbatim.

## Issues Encountered

- **Worktree was off origin/main, missing Phase 1+2 + Plans 03-01/03-02 outputs.** The worktree was created from `origin/main` (4bbede3 — UMAS hardening), which does not yet contain the Phase 3 work that lives on local `main` (d3f013c — through Plan 03-02 merge). Resolved by `git rebase main`, which applied cleanly with no conflicts and pulled in `.planning/phases/03-elevator-child-embedding/*`, the Phase-2 elevator.dart, and the Plan-03-01/02 elevator_widget_test.dart + elevator_config_test.dart updates. After the rebase, the baseline 23 elevator-widget tests + 32 elevator-config tests passed, confirming the rebase target was correct (mirrors Plan 03-02's "Issues Encountered" rebase note verbatim).
- **Default `BaseAsset.allKeys` introspection** still does not match `'wrapped_child'` envelope keys — but this was already addressed by Plan 03-02's `ElevatorConfig.allKeys` override, so any child added via the new editor UI flows into alarms/collectors automatically. No additional work required in this plan.

## TDD Gate Compliance

All required gates landed in order:

- **RED:** `71d480b` `test(03-03): add failing tests …` — 7 tests fail on the unmodified code path (1 updated Phase-2 smoke + 6 new editor tests); all other tests still pass. `flutter test` exit shows `+19 -7` at RED time.
- **GREEN:** `4a5e05d` `feat(03-03): add child management UI …` — all 29 widget tests pass; full elevator + sensor surface (165 tests) passes 5/5 deterministic. Source-grep gates: `managed in Phase 3` = 0 (comments-stripped), `FilledButton` ≥ 1, `'Add child'` ≥ 1, `'No children configured'` = 1, `SensorConfig.preview` ≥ 1, `ConveyorConfig.preview` ≥ 1, `Slider(` ≥ 1, `AssetRegistry.defaultFactories` = 0 (comments-stripped). Comments-stripped runtime-type-switch grep returns 0.
- **REFACTOR:** not applicable — the GREEN code is final-form.

`git log --oneline | grep -cE "(test|feat|fix)\(03-03\)"` returns 2 (test + feat; no fix commit needed).

## Verification Receipts

| Gate | Result |
|------|--------|
| `flutter test test/page_creator/assets/elevator_widget_test.dart` | 29/29 pass (13 Phase-2 + 7 Plan-03-01 + 3 goldens + 6 new Plan-03-03) |
| Full elevator + sensor surface (7 files, 165 tests) | 165/165 pass |
| 5x deterministic on the full surface | 5/5 |
| `flutter analyze` on Phase-3 modified files | No issues found |
| Comments-stripped runtime-type-switch grep on elevator.dart | 0 matches |
| `git log --oneline | grep -cE "(test|feat)\(03-03\)"` | 2 |
| `'managed in Phase 3'` comments-stripped grep on elevator.dart | 0 |
| `'No children configured'` grep on elevator.dart | 1 |

## Phase 3 Closeout — All Phase-3 Requirements Closed

| Requirement | Closed by Plan | Evidence |
|-------------|----------------|----------|
| ELEV-07 (operator can add a child via filtered dropdown) | 03-03 | `_allowedChildFactories` map + 3-negative-assertion widget test |
| ELEV-08 (operator can edit and remove children) | 03-03 | edit-flow + remove-flow widget tests; recursive `entry.child.configure(context)` dispatch |
| ELEV-09 (children render via Stack composition) | 03-01 | `_buildStack` with painter index 0 + Positioned children index 1..N |
| ELEV-10 (children Positioned.top tracks platformOffsetTop) | 03-01 | `Children Positioned.top follows _animProgress` widget test |
| ELEV-11 (no runtime-type switching on children) | 03-01 | source-level grep gate in elevator_widget_test.dart |
| ELEV-12 (ValueKey<String>(entry.id) preserves child State) | 03-01 | 50-progress-changes Pitfall-1 widget test |
| ELEV-13 (ElevatorConfig.allKeys flat-maps children) | 03-02 | `'allKeys flat-map (ELEV-13)'` test group with 6 tests |
| ELEV-19 (children's GestureDetectors fire mid-translation) | 03-01 | tap-during-translation widget test + LayoutRotatedBox.hitTest forwarding fix |
| QUAL-03 (3 integration goldens) | 03-01 | `elevator_with_children_progress_{0,50,100}.png` |
| QUAL-08 (TDD discipline — test before feat) | 03-01, 03-02, 03-03 | `git log --oneline | grep -cE "(test|feat)\(03-0[123]\)"` returns 7 (4 test + 3 feat across the three plans) |

**All 10 Phase-3 requirements are closed across Plans 03-01, 03-02, 03-03.**

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Phase 4 (per CONTEXT forward note):** ELEV-15 (out-of-range fault outline), QUAL-06 (multi-elevator smoke), QUAL-07 (LeakTesting mount/unmount). All three are independent of the editor surface; they touch the painter (ELEV-15), end-to-end test harness (QUAL-06, QUAL-07), and runtime widget (ELEV-15 outline). Plan 03-03's editor changes do not block any of them.
- **Manual smoke (Phase 3 closeout):** the manual checklist at the head of `elevator_widget_test.dart` should be extended to include "tap Add child → confirm SimpleDialog shows Sensor + Conveyor only", "tap Sensor option → confirm child appears at offsetX 0.5 with auto-generated id", "tap edit IconButton → confirm child's editor opens", "drag Slider → confirm child's lateral position changes on the page", "tap remove → confirm child disappears + 'No children configured' appears". This is operator-side verification only; can be done at Phase 4 closeout time alongside the existing Phase-2 smoke.
- **Saved-page back-compat:** Plan 02-02's `_childrenFromJson` legacy shim handles `null` / missing `children` gracefully; pages saved before this plan continue to load with `children: []`. New pages with operator-added children round-trip through `AssetRegistry.parse` via Plan 02-02's `_childFromJson` polymorphic helper. Verified at the JSON layer by `elevator_config_test.dart` group 'Polymorphic child round-trip'; the editor's UI never bypasses these helpers.

## Self-Check: PASSED

Verified before marking complete:
- `lib/page_creator/assets/elevator.dart` exists and contains: `Add child` (3 hits: 1 doc + SimpleDialog title + FilledButton label), `No children configured` (1 hit), `_allowedChildFactories` (3 hits: declaration + 2 references), `SensorConfig.preview` (1 hit), `ConveyorConfig.preview` (1 hit), `Slider(` (1 hit). VERIFIED.
- `'managed in Phase 3'` grep on `elevator.dart` (comments-stripped) returns 0. VERIFIED.
- `test/page_creator/assets/elevator_widget_test.dart` exists and contains: `'Editor — child management (ELEV-07, ELEV-08)'` group with 6 testWidgets calls (filtered dropdown, append-Sensor, append-Conveyor, edit-flow, remove-flow, offsetX-Slider). VERIFIED.
- Commit `71d480b` (test/RED) present in `git log --oneline`. VERIFIED.
- Commit `4a5e05d` (feat/GREEN) present in `git log --oneline`. VERIFIED.
- `flutter analyze` on `elevator.dart` + the two test files: No issues found. VERIFIED.
- 5x consecutive runs of the full elevator + sensor surface (7 files, 165 tests): 5/5 pass. VERIFIED.

## Threat Flags

None — the plan's threat model dispositions held.

- **T-03-08 (operator adds arbitrary asset type):** mitigated by hard-coded `_allowedChildFactories` map; locked by 3 negative widget-test assertions (LED, Number, Button).
- **T-03-09 (operator deletes child carrying critical force keys):** accepted — operator authority surface; no confirmation dialog (matches conveyor precedent).
- **T-03-10 (operator adds 1000 children via repeated taps):** mitigated by Plan 03-01's per-child `ValueListenableBuilder` with cached `child:` parameter (locked by Pitfall-1 test in Plan 03-01); editor mutation operations themselves are O(1) per tap.
- **T-03-11 (edit dialog leaks sub-asset's internal config):** accepted — same operator authority surface as a standalone Sensor/Conveyor.

The recursive `entry.child.configure(context)` dispatch does not introduce new attack surface — the child's editor is the same dialog content as if the child were placed standalone on the page.

---
*Phase: 03-elevator-child-embedding*
*Completed: 2026-05-06*
