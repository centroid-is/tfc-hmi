---
phase: 04-polish-error-ux-and-ci-hardening
plan: 05
subsystem: ui
tags: [flutter, gestures, dialog, sensor, elevator, page-creator, hmi]

# Dependency graph
requires:
  - phase: 01-sensor-foundation
    provides: Sensor widget with GestureDetector and config dialog
  - phase: 02-elevator-foundation
    provides: Elevator widget with GestureDetector and config dialog
  - phase: 03-elevator-children
    provides: ELEV-19 hit-test-through-translation contract
  - phase: 04-04-simulate-motion
    provides: ElevatorConfig.simulate flag surfaced in details dialog
provides:
  - Read-only details dialog on Sensor runtime tap (SENS-01)
  - Read-only details dialog on Elevator runtime tap (ELEV-01)
  - Editor-only configure() routing preserved via page_editor.dart
  - Shared (file-private) _DetailRow helper pattern across both assets
affects: [future polish plans, operator-UX guidelines]

# Tech tracking
tech-stack:
  added: []  # No new dependencies — uses existing Flutter Material AlertDialog/SelectableText
  patterns:
    - "Runtime details dialog vs editor-only configure(): operators inspect, never mutate"
    - "GestureDetector.onTap → _showDetailsDialog (runtime); page_editor.dart → asset.configure() (edit)"
    - "Snapshot-of-state dialogs: capture ValueNotifier value at open-time vs running ValueListenableBuilder inside dialog"
    - "Editor-coverage tests routed via openConfigEditor() helper that invokes config.configure(context) directly — decouples editor coverage from runtime tap"

key-files:
  created: []
  modified:
    - "lib/page_creator/assets/sensor.dart"
    - "lib/page_creator/assets/elevator.dart"
    - "test/page_creator/assets/sensor_widget_test.dart"
    - "test/page_creator/assets/elevator_widget_test.dart"

key-decisions:
  - "Sensor 'Detection state' row falls back to '(see glyph)' / 'no key configured' rather than re-plumbing live stream into dialog — painter glyph already surfaces live state visually; not worth the complexity for polish-phase feature"
  - "Elevator details dialog snapshots _progress.value at open-time; operator closes+reopens to refresh — avoids forcing dialog rebuild on every 50ms simulator tick"
  - "_DetailRow helper duplicated in elevator.dart (file-private) instead of promoted to common.dart; promote only if a third call site emerges"
  - "SelectableText for value column — operators copy state-key strings while troubleshooting"
  - "Editor-coverage tests rebuilt via openConfigEditor() helper invoking config.configure(context) directly; decouples editor surface coverage from runtime tap path"
  - "ELEV-19 reorder-keyed-subtree-identity test rebuilt around runtime-Elevator + editor-as-overlay setup (mirrors page_editor.dart) so runtime ValueKey wrappers stay in scope while editor mutates config.children"

patterns-established:
  - "Runtime tap surface: AlertDialog with _DetailRow rows + Close TextButton; no PLC writes, no config edits"
  - "Editor entry point: ONLY page_editor.dart → asset.configure(BuildContext); never wired to runtime GestureDetector"
  - "Test helper: openConfigEditor(WidgetTester, AssetConfig) wraps configure() in Dialog under an ElevatedButton — replaces 'tap on asset to open config' pattern"

requirements-completed: [SENS-01, ELEV-01, QUAL-08]

# Metrics
duration: ~25 min
completed: 2026-05-06
---

# Phase 04 Plan 05: Runtime Tap Opens Read-Only Details Dialog Summary

**Sensor and Elevator runtime taps now open AlertDialog with read-only state (kind, keys, progress %, simulate flag, child count); configure() remains editor-only via page_editor.dart, preserving the operator-cannot-mutate-config invariant (SENS-01, ELEV-01).**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-06T16:25:00Z
- **Completed:** 2026-05-06T16:54:27Z
- **Tasks:** 3 atomic commits (RED test, sensor feat, elevator feat)
- **Files modified:** 4

## Accomplishments
- Sensor runtime tap → read-only AlertDialog (Kind, Detection key, Detection state, Active polarity inverted, Rising/Falling edge delay key, optional Tag); no editor controls.
- Elevator runtime tap → read-only AlertDialog (Position key, Current position with stale/simulating fallback, Tween duration, Out-of-range, Stale, Simulate motion, Children count); no editor controls.
- ELEV-19 hit-test-through-translation contract preserved: tap on a Sensor child mid-translation lands on the child's GestureDetector and opens the **child's** details dialog (`Detection key` label) — not the elevator's, and not any editor.
- All 1799 project tests pass; analyze clean for the changed files; no regressions in Phases 1–4.

## Task Commits

Each task was committed atomically:

1. **RED — runtime tap opens read-only details dialog (test scaffolding)** — `1890ae8` (test)
2. **Sensor implementation: _showDetailsDialog + _DetailRow** — `11f3e69` (feat)
3. **Elevator implementation: _showDetailsDialog + _DetailRow + ELEV-19 test fix** — `1f6be24` (feat)

_TDD pairing: test commit precedes both feat commits (RED gate satisfied). Verified failing-then-passing locally for the runtime-tap-opens-details assertions before writing implementation._

## Files Created/Modified
- `lib/page_creator/assets/sensor.dart` — Replaced `_openConfigDialog` with `_showDetailsDialog`; added file-private `_DetailRow`. GestureDetector.onTap now wires to details dialog.
- `lib/page_creator/assets/elevator.dart` — Replaced `_openConfigDialog` with `_showDetailsDialog`; added file-private `_DetailRow`. GestureDetector.onTap now wires to details dialog.
- `test/page_creator/assets/sensor_widget_test.dart` — Renamed group "Tap to configure" → "Tap to show details (Plan 04-05)" with 5 details-dialog assertions; "Config dialog smoke" group rerouted through new `openConfigEditor()` helper invoking `config.configure(context)` directly.
- `test/page_creator/assets/elevator_widget_test.dart` — Same restructure for elevator; added `openConfigEditor()` helper at top of `main()`; routed all editor-coverage tests (child mgmt, z-order reorder, simulate motion) through it. ELEV-19 hit-test-during-translation test updated to assert child details dialog. ValueKey reorder-identity test rebuilt with runtime-Elevator-plus-editor-overlay fixture.

## Decisions Made
- **"Detection state" row in sensor dialog**: falls back to `'(see glyph)'` / `'no key configured'` rather than re-plumbing the live stream into the dialog. The painter glyph already surfaces live state visually; wiring it twice is not worth the complexity for a polish-phase feature. Plan explicitly permitted this fallback.
- **Snapshot-of-state for elevator dialog**: captured `_progress.value` at open-time rather than running a `ValueListenableBuilder` inside the AlertDialog. This avoids forcing the dialog to rebuild on every 50ms simulator tick or PLC emission. Operator closes and reopens to refresh; matches the polish-feature scope.
- **`_DetailRow` duplicated in elevator.dart**: Plan permitted "duplicate to keep changes scoped". The widget is 17 lines; promoting to `common.dart` would broaden public API surface for a one-screen polish feature. Documented in elevator.dart that promotion threshold is "third call site emerges".
- **Editor-coverage tests routed via `openConfigEditor()` helper**: The helper invokes `config.configure(context)` directly inside a `Dialog`, mirroring `page_editor.dart:_showConfigDialog`. This decouples the editor surface from the runtime tap path so future runtime-tap refactors don't break editor-only assertions.
- **ELEV-19 test rebuild**: The "reorder preserves ValueKey identity" test asserts on runtime widget tree (not editor). Tapping the runtime GestureDetector previously opened both the editor (overlay) and kept the runtime mounted underneath. With the runtime tap now opening details (not editor), I rebuilt the test to render Elevator at root and open the editor as a Stack-overlay via an ElevatedButton — matches `page_editor.dart` real-world setup.

## Deviations from Plan

None - plan executed exactly as written.

The plan's quality gate items all hold:
- All Phase 1–4 tests still pass after change (regression-clean) ✓
- `flutter analyze` clean for the changed files ✓
- Tests updated to expect details dialog (not config dialog) on runtime tap ✓
- Page editor's `configure()` flow untouched — `grep configure(BuildContext` in sensor.dart / elevator.dart still returns the editor widget signatures (lines 94 and 222) ✓
- Gestures still survive translation (ELEV-19 test passes with updated expectation: child's details dialog) ✓
- TDD: test commit precedes both feat commits ✓

## Issues Encountered

**`reorder preserves keyed subtree identity (ValueKey)` test failure during GREEN.** First run after sensor+elevator implementation showed this one test failing because routing it through `openConfigEditor()` removed the runtime Elevator from the widget tree, so `find.byKey(ValueKey<String>('A'))` (which targets runtime children inside `_buildStack`) found nothing. Fixed by rebuilding the test fixture: render the Elevator runtime at root and open the editor as a Stack-overlay button — matches the production setup in `page_editor.dart`. All 53 elevator widget tests then pass.

## User Setup Required

None — no external service configuration, no PLC config changes, no migrations.

Operators may notice the change immediately: tapping a Sensor or Elevator on a saved page now opens an information dialog instead of the editor. The locked field surface is documented in the dialog itself (Kind, Detection key, etc. for sensors; Position key, Current position, etc. for elevators). Editor access remains via the page editor's right-click / asset-selection flow (TFC_GOD-gated).

## Next Phase Readiness

Phase 4 (Polish) is now closer to complete with this UX safety improvement. The remaining Phase 4 items track in ROADMAP:
- Plans 04-01 through 04-04 already completed (out-of-range outline, golden-review fixes, z-order reorder, simulate motion).
- Plan 04-05 (this plan) closes the SENS-01 / ELEV-01 / QUAL-08 requirement triple.

No blockers. The patterns established here (runtime details dialog vs editor configure routing) can serve as a template if other assets need similar runtime/edit separation.

## Self-Check: PASSED

Verifications performed:
- `[ -f lib/page_creator/assets/sensor.dart ] && grep -q '_showDetailsDialog' lib/page_creator/assets/sensor.dart` → FOUND
- `[ -f lib/page_creator/assets/elevator.dart ] && grep -q '_showDetailsDialog' lib/page_creator/assets/elevator.dart` → FOUND
- `git log --oneline | grep 1890ae8` → FOUND (test RED commit)
- `git log --oneline | grep 11f3e69` → FOUND (sensor feat commit)
- `git log --oneline | grep 1f6be24` → FOUND (elevator feat commit)
- `flutter test test/page_creator/assets/` → 262 tests passed
- `flutter test` (project-wide) → 1799 passed, 4 skipped, 0 failed
- `flutter analyze lib/page_creator/assets/sensor.dart lib/page_creator/assets/elevator.dart` → "No issues found!"
- `grep 'configure(BuildContext' lib/page_creator/assets/sensor.dart lib/page_creator/assets/elevator.dart` → both files preserve their configure() entry points (sensor.dart:94, elevator.dart:222)

## TDD Gate Compliance

Plan 04-05 is a `type: tdd` plan. Gate sequence in git log:
1. **RED gate (test commit):** `1890ae8 test(04-05): RED — runtime tap opens read-only details dialog (SENS-01, ELEV-01)` ✓
2. **GREEN gate #1 (feat commit):** `11f3e69 feat(04-05): runtime tap on sensor opens read-only details dialog (SENS-01)` ✓
3. **GREEN gate #2 (feat commit):** `1f6be24 feat(04-05): runtime tap on elevator opens read-only details dialog (ELEV-01)` ✓
4. **REFACTOR:** none required — implementation matched plan structure on first GREEN.

RED commit verified to fail at the new "Tap to show details" assertions (5 sensor failures observed locally) before either feat commit was written.

---
*Phase: 04-polish-error-ux-and-ci-hardening*
*Completed: 2026-05-06*
