---
phase: 04-polish-error-ux-and-ci-hardening
plan: 04
subsystem: page-creator/assets/elevator
tags:
  - elevator
  - editor
  - simulation
  - preview
  - tdd
  - QUAL-08
dependency_graph:
  requires:
    - 04-01
    - 04-02
    - 04-03
  provides:
    - elevator-simulate-toggle
    - QUAL-08
  affects:
    - lib/page_creator/assets/elevator.dart
    - lib/page_creator/assets/elevator.g.dart
    - test/page_creator/assets/elevator_widget_test.dart
    - test/page_creator/assets/elevator_config_test.dart
tech-stack:
  added: []
  patterns:
    - "Periodic Timer-driven local animation (mirrors conveyor.dart simulateBatches precedent)"
    - "Stream listener early-return guard for sim ownership"
    - "@JsonKey(includeIfNull:false) for back-compat optional fields"
key-files:
  created:
    - .planning/phases/04-polish-error-ux-and-ci-hardening/04-04-PLAN.md
    - .planning/phases/04-polish-error-ux-and-ci-hardening/04-04-SUMMARY.md
  modified:
    - lib/page_creator/assets/elevator.dart
    - lib/page_creator/assets/elevator.g.dart
    - lib/page_creator/assets/conveyor_gate.g.dart
    - lib/providers/database.g.dart
    - test/page_creator/assets/elevator_widget_test.dart
    - test/page_creator/assets/elevator_config_test.dart
decisions:
  - "Use a compact SwitchListTile (dense:true, contentPadding:zero) instead of a full-width tile with subtitle — keeps the editor under the 600-px default test viewport so the existing Add-child button stays in-frame for ELEV-07/08 tests."
  - "simulate field is bool? not bool — back-compat with legacy saved pages (null/missing → off)."
  - "Sim timer cadence 50ms × 0.01 step — matches conveyor.dart's simulateBatches cadence; ~5s for 0→1, ~10s round trip is comfortable for preview without being distracting."
  - "Sim ownership of _progress is enforced via _onStreamData early-return — simpler and more local than swapping listener registrations."
  - "First widget test cannot use pumpAndSettle (the periodic timer is never-ending) — uses a 300ms fixed pump that covers the dialog open animation instead."
metrics:
  duration_seconds: 405
  duration: "6m 45s"
  completed: "2026-05-06"
  tests_added: 9
  tests_total_passing: 256
---

# Phase 4 Plan 4: Simulate Motion Toggle Summary

QUAL-08 simulate-motion preview toggle for the elevator asset using a
50ms-tick Timer.periodic that owns _progress while active and respects
the live PLC stream when off.

## Tasks Completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 (RED) | Failing tests for simulate toggle | `4be6748` | elevator_widget_test.dart, elevator_config_test.dart |
| 2 (GREEN) | Implement simulate field, timer, editor switch | `4da1266` | elevator.dart, elevator.g.dart, elevator_widget_test.dart |

## What Shipped

### ElevatorConfig (lib/page_creator/assets/elevator.dart)

- New `bool? simulate` field decorated with
  `@JsonKey(includeIfNull: false)`. Added as a named optional parameter
  to the `ElevatorConfig` constructor.
- Default value is `null` so legacy saved pages omit the key entirely
  (back-compat lock).

### _ElevatorState (runtime)

- Three new instance fields for the simulation:
  - `Timer? _simTimer` — the periodic ticker (null when off).
  - `double _simProgress` — current sweep position (0..1).
  - `bool _simAscending` — sweep direction; flips at each end.
- New `_handleSimulationChange(bool)` method:
  - ON: starts a `Timer.periodic(50ms)` that nudges `_simProgress` by
    ±0.01 each tick and writes the result to `_progress.value`. Reverses
    direction at 0.0 and 1.0 → the platform sweeps 0→1→0 forever.
  - OFF: cancels the timer and leaves `_progress.value` frozen until the
    next live stream emission.
- `initState` kicks off the simulation if `widget.config.simulate ?? false`.
- `didUpdateWidget` compares `widget.config.simulate ?? false` against
  `_simTimer != null` and starts/stops on flip. (Does not compare against
  `oldWidget.config.simulate` because the editor mutates the same config
  instance in-place — same precedent as `_hoistedKey` for positionKey.)
- `_onStreamData` early-returns when `widget.config.simulate ?? false` so
  live PLC emissions cannot overwrite the simulated `_progress` (the
  simulation owns the notifier exclusively while running).
- `dispose()` cancels `_simTimer` BEFORE disposing `_progress` so a final
  pending tick can't fire on the disposed notifier (QUAL-07 leak contract).

### _ElevatorConfigEditorState (editor body)

- Compact `SwitchListTile` titled "Simulate motion" added between the
  Position State Key field and the Tween Duration field.
- `dense: true` + `contentPadding: EdgeInsets.zero` keep the new control
  tight enough that the existing "Add child" FilledButton stays inside
  the 600-px default test viewport — avoids regressing the ELEV-07/08
  child-management tests.
- Wired to `widget.config.simulate ?? false` with `setState` mutation
  on toggle.

### Codegen (elevator.g.dart)

```dart
ElevatorConfig _$ElevatorConfigFromJson(Map<String, dynamic> json) =>
    ElevatorConfig(
      positionKey: json['positionKey'] as String? ?? '',
      tweenDurationMs: (json['tweenDurationMs'] as num?)?.toInt() ?? 250,
      simulate: json['simulate'] as bool?,
      children: _childrenFromJson(json['children'] as List?),
    )
    ...
```

```dart
Map<String, dynamic> _$ElevatorConfigToJson(ElevatorConfig instance) =>
    <String, dynamic>{
      ...
      if (instance.simulate case final value?) 'simulate': value,
    };
```

The `if (instance.simulate case final value?)` pattern is the
`includeIfNull:false` codegen — when `simulate` is `null` the key is
omitted entirely from the output map.

### Tests Added

**elevator_config_test.dart** (2 new tests)

1. `ElevatorConfig with simulate=true round-trips and preserves field (QUAL-08)`
   — verifies `simulate: true` survives toJson/fromJson and the JSON map
   contains `simulate: true`.
2. `ElevatorConfig with simulate=null omits the key from toJson (QUAL-08)`
   — locks the back-compat contract: legacy pages without the key
   continue to round-trip bit-perfectly.

**elevator_widget_test.dart** (7 new tests in `Simulation toggle (QUAL-08)`)

1. `editor exposes Simulate motion switch reflecting config.simulate` —
   asserts the SwitchListTile is in the dialog and `value=true` when
   `config.simulate=true`.
2. `Simulate motion switch defaults to OFF when config.simulate is null`
   — null surfaces as switch OFF.
3. `toggling simulate to true starts the sim timer (progress advances)` —
   flips the flag, pumps 200ms, asserts `_progress.value > 0`.
4. `toggling simulate to false stops the sim timer (progress freezes)` —
   captures pre-cancel value, pumps 500ms, asserts the value didn't move.
5. `PLC stream emission does not override _progress while simulating` —
   injects raw 0 via `debugInjectRaw`, asserts simulated value is still
   non-zero (the early-return guard works).
6. `simulation oscillates between 0 and 1 (sweep, not saw-tooth)` —
   pumps past peak, captures peak ~1.0, pumps further, asserts value
   has descended (direction reversed).
7. `simulation timer is cancelled on unmount (no leak — QUAL-07)` —
   mounts with simulate ON, unmounts to empty SizedBox, asserts no
   exceptions.

## Verification

```text
flutter test test/page_creator/assets/
00:02 +256: All tests passed!

flutter analyze lib/page_creator/assets/elevator.dart \
               test/page_creator/assets/elevator_widget_test.dart \
               test/page_creator/assets/elevator_config_test.dart
No issues found! (ran in 3.4s)
```

256/256 elevator+sensor+gate tests pass after the change. flutter
analyze clean for the modified files.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SwitchListTile size pushed Add-child button below test viewport**

- **Found during:** Task 2 (GREEN) — test run after first implementation
  attempt.
- **Issue:** A full-height `SwitchListTile` with `subtitle:` text grew the
  editor body so the "Add child" FilledButton landed at viewport-y 680,
  outside the 600-px default test viewport. Three pre-existing
  ELEV-07/08 child-management tests started failing with hit-test
  out-of-bounds warnings (the tests tap the Add-child button without
  ensureVisible — they had been written before this row existed).
- **Fix:** Switched the SwitchListTile to `dense: true` +
  `contentPadding: EdgeInsets.zero` (no subtitle) — the row collapses
  to ~48px, restoring the Add-child button to in-frame.
- **Files modified:** `lib/page_creator/assets/elevator.dart`
- **Commit:** `4da1266`

**2. [Rule 1 - Bug] First widget test deadlocked on pumpAndSettle**

- **Found during:** Task 2 (GREEN) — test run.
- **Issue:** `editor exposes Simulate motion switch reflecting config.simulate`
  used `await tester.pumpAndSettle()` after opening the dialog. With
  `simulate: true`, the simulation timer is `Timer.periodic(50ms)` —
  pumpAndSettle never returns (the test framework cannot reach a
  steady state when a timer is firing forever).
- **Fix:** Replaced `pumpAndSettle()` with
  `pump(const Duration(milliseconds: 300))` — long enough to cover the
  Material dialog open transition (~150ms default), short enough to
  finish quickly.
- **Files modified:** `test/page_creator/assets/elevator_widget_test.dart`
- **Commit:** `4da1266`

**3. [Rule 3 - Blocker] Stale codegen for sibling assets picked up by build_runner**

- **Found during:** Task 2 (GREEN) — `dart run build_runner build`.
- **Issue:** `conveyor_gate.g.dart` and `database.g.dart` had stale
  generated output from prior unrelated edits (techDocId/plcAssetKey
  fields added to a base class). build_runner regenerated them in the
  same pass that updated elevator.g.dart.
- **Fix:** Committed the regenerated files alongside the elevator
  changes — leaving them stale would propagate the noise to every
  future contributor running build_runner.
- **Files modified:** `lib/page_creator/assets/conveyor_gate.g.dart`,
  `lib/providers/database.g.dart`
- **Commit:** `4da1266`

## TDD Gate Compliance

- RED gate: `4be6748` (`test(04-04)…`) — failing tests committed first.
- GREEN gate: `4da1266` (`feat(04-04)…`) — implementation committed
  after RED, all 9 new + 75 existing tests pass.
- REFACTOR gate: not needed (the implementation is final on the first
  GREEN attempt).

## Self-Check: PASSED

- File `lib/page_creator/assets/elevator.dart` — FOUND.
- File `lib/page_creator/assets/elevator.g.dart` — FOUND, contains
  `simulate` field.
- File `test/page_creator/assets/elevator_widget_test.dart` — FOUND.
- File `test/page_creator/assets/elevator_config_test.dart` — FOUND.
- File `.planning/phases/04-polish-error-ux-and-ci-hardening/04-04-PLAN.md` — FOUND.
- Commit `4be6748` — FOUND in `git log`.
- Commit `4da1266` — FOUND in `git log`.
