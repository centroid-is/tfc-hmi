---
phase: 01-sensor-asset
plan: 01
subsystem: ui
tags: [sensor, config, json, json_serializable, color_converter, tdd, dart, flutter]

# Dependency graph
requires:
  - phase: pre-existing
    provides: BaseAsset (lib/page_creator/assets/common.dart), ColorConverter (lib/converter/color_converter.dart), conveyor_gate.dart + led.dart analogs
provides:
  - SensorKind enum (redLight, opticField, inductiveField)
  - SensorConfig data class with JSON round-trip + legacy-tolerance + unknown-enum forward-compat
  - sensorIsActive(rawBool, invertActivePolarity) polarity helper (locked formula)
  - 21-test contract that locks defaults, enum, JSON round-trip, legacy migration, allKeys plumbing, polarity truth-table
affects: [01-02-painter, 01-03-widget, 01-04-registry, 01-05-dialog, 03-elevator-children]

# Tech tracking
tech-stack:
  added: []  # No new dependencies — re-uses json_annotation, json_serializable, build_runner, flutter_test
  patterns:
    - "Polarity helper as top-level function (testable without widget tree)"
    - "@ColorConverter() annotation matches led.dart convention; supersedes conveyor_gate.dart's local int-based _colorFromJson/_colorToJson for new assets"

key-files:
  created:
    - lib/page_creator/assets/sensor.dart
    - lib/page_creator/assets/sensor.g.dart
    - test/page_creator/assets/sensor_config_test.dart
    - .planning/phases/01-sensor-asset/01-01-SUMMARY.md
  modified: []

key-decisions:
  - "Use @ColorConverter() (red/green/blue/alpha JSON shape) — matches led.dart, the active style for new assets"
  - "Polarity helper is a top-level function, not a static method — keeps unit tests free of widget tree setup"
  - "Default activeColor = Colors.green (matches led.dart onColor); default inactiveColor = Colors.grey.shade400 (per UI-SPEC color matrix)"
  - "build() and configure() throw UnimplementedError — explicit deferral to Plans 03 and 05 keeps Plan 01 a pure data-model contract"
  - "@JsonKey(unknownEnumValue: SensorKind.redLight) on `kind` field — locks forward-compat against future enum additions"

patterns-established:
  - "TDD gate cadence: every behaviour has a test(...) commit before its feat(...) commit (5 commits, alternating test→feat)"
  - "Legacy-tolerance tests run as regression guard (pass on first run under correct json_serializable wiring; lock the contract for refactor safety)"
  - "Round-trip determinism via Map deep-equality: toJson → fromJson → toJson MUST equal first toJson bit-for-bit (locked test catches any future field-default drift)"
  - "Helper function placeholder pattern: feat task creates UnimplementedError stub so file compiles; later TDD task replaces stub with locked formula"

requirements-completed:
  - SENS-02
  - SENS-03  # partial — kind enum exists; painter dispatch is Plan 02
  - SENS-08
  - SENS-09
  - SENS-10
  - SENS-12
  - SENS-13
  - SENS-17
  - QUAL-05
  - QUAL-08

# Metrics
duration: ~12 min
completed: 2026-05-06
---

# Phase 01 Plan 01: SensorConfig Data Model Summary

**SensorKind enum + SensorConfig data class with JSON round-trip, legacy migration tolerance, unknown-enum forward-compat, and locked polarity inversion helper — all under TDD discipline with 21 unit tests.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-06T07:33:00Z (approx — initial file Read)
- **Completed:** 2026-05-06T07:45:29Z
- **Tasks:** 5 (4 TDD + 1 sweep)
- **Files modified:** 3 created (1 source, 1 generated, 1 test)
- **Tests added:** 21 (all green)
- **Commits:** 5 (3 test, 2 feat) — RED-before-GREEN cadence verified

## Accomplishments

- `SensorKind` enum locked at three values: `redLight`, `opticField`, `inductiveField`
- `SensorConfig` data class extends `BaseAsset`, carries 8 serialisable fields plus inherited `Coordinates`/`RelativeSize`/`text`/`textPos`/`techDocId`/`plcAssetKey`
- JSON round-trip is bit-for-bit deterministic (Map deep equality)
- Legacy JSON loads safely: missing `invertActivePolarity`, `risingEdgeDelayKey`, `fallingEdgeDelayKey`, `tag`, `activeColor`, `inactiveColor` → all defaults applied
- Unknown `SensorKind` value (e.g. future `thermalSensor`) falls back to `redLight` without throwing — covered by test
- `sensorIsActive(rawBool, invertActivePolarity)` implements locked formula `invertActivePolarity ? !rawBool : rawBool` with full 4-row truth-table coverage
- `allKeys` correctly returns `detectionKey`, `risingEdgeDelayKey`, `fallingEdgeDelayKey` and explicitly excludes `tag` (T-01-03 mitigation verified by test)

## Task Commits

Each task was committed atomically; TDD cadence (RED → GREEN) is preserved in git log:

1. **Task 1 [RED]:** failing tests for defaults, enum, JSON round-trip — `c6ddc8a` (test)
2. **Task 2 [GREEN]:** implement `SensorConfig` + `SensorKind` + codegen — `f92ee2a` (feat)
3. **Task 3 [RED]:** failing tests for legacy JSON tolerance + unknown enum fallback + `allKeys` — `2dea0e7` (test) — regression guard pattern (passed on first run under correct Task 2 wiring)
4. **Task 4 [RED]:** failing polarity-inversion truth-table (4 cases) — `db6afa2` (test) — confirmed `UnimplementedError` for all 4
5. **Task 4 [GREEN]:** implement `sensorIsActive` locked formula — `f5a89f6` (feat)

**Plan metadata:** SUMMARY.md committed in next step (worktree mode — no STATE.md/ROADMAP.md updates here)

_Note: Task 5 (regression sweep) ran `flutter test` (21/21 green) and `flutter analyze` (4 info-level deprecations only, matching existing project convention in `conveyor_gate_test.dart`). No bytes changed, so no commit was needed for Task 5 itself._

## Files Created/Modified

- `lib/page_creator/assets/sensor.dart` (101 lines) — `SensorKind` enum + `SensorConfig extends BaseAsset` + `sensorIsActive` helper. `build()` and `configure()` throw `UnimplementedError` (intentional deferral to Plans 03/05).
- `lib/page_creator/assets/sensor.g.dart` (69 lines, generated) — `_$SensorConfigFromJson`, `_$SensorConfigToJson`, `_$SensorKindEnumMap`. Includes `unknownValue: SensorKind.redLight` fallback and `?? ''`/`?? false` defaults for missing legacy fields.
- `test/page_creator/assets/sensor_config_test.dart` (190 lines) — 5 groups, 21 tests covering defaults, enum, JSON round-trip, legacy tolerance, unknown-enum fallback, allKeys plumbing, polarity truth-table.

## Decisions Made

- Used `@ColorConverter()` (the `led.dart` convention with `red/green/blue/alpha` JSON keys) rather than `conveyor_gate.dart`'s local int-based helpers. This matches the active style for new assets per `01-CONTEXT.md` "Reusable Assets".
- `sensorIsActive` is a top-level function (not a static method on `SensorConfig`) so unit tests can exercise it directly without instantiating the config. Aligns with the plan's locked formula in `01-UI-SPEC.md`.
- `build()` and `configure()` throw `UnimplementedError` with explicit Plan-N references — keeps the file compilable for Plan 02 painter / Plan 03 widget consumers while making missing wiring obvious if anyone tries to render the asset prematurely.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Used real `ColorConverter` JSON keys (`red/green/blue/alpha`) in legacy-tolerance test, not the plan's example shape (`r/g/b/a`)**
- **Found during:** Task 3 (writing the unknown-enum-fallback test)
- **Issue:** The plan's Task 3 action body shows example legacy JSON with color shape `{'r': 76, 'g': 175, 'b': 80, 'a': 255}`. The actual `lib/converter/color_converter.dart` uses `{'red': 0.298, 'green': 0.686, 'blue': 0.314, 'alpha': 1.0}` (named keys, 0–1 doubles, not 0–255 ints). Using the plan's shape would have produced a test that either failed or silently fell back to defaults, masking the actual round-trip semantics.
- **Fix:** Used the real `ColorConverter` JSON shape in the unknown-enum legacy test. Test still verifies the contract (kind falls back to redLight) without coupling to the wrong color shape.
- **Files modified:** test/page_creator/assets/sensor_config_test.dart
- **Verification:** Test passes; the unknown-enum-fallback assertion is still the load-bearing check.
- **Committed in:** 2dea0e7 (Task 3 commit)

**2. [Rule 2 - Missing Critical] Added explicit `tag NOT in allKeys` assertion (T-01-03 mitigation)**
- **Found during:** Task 3 (writing the `allKeys` test)
- **Issue:** The plan's threat model lists T-01-03 (Information Disclosure: `tag` mis-classified as a key would be picked up by collector key extraction). The plan's hint suggests adding `expect(keys, isNot(contains('PE-101A')))` "if not already present". My test instance carries `tag: 'PE-101A'`, so I added the explicit `isNot(contains(...))` assertion to lock the threat-model mitigation.
- **Fix:** Added `expect(keys, isNot(contains('PE-101A')))` to the `allKeys` test.
- **Files modified:** test/page_creator/assets/sensor_config_test.dart
- **Verification:** Test passes — confirms `BaseAsset._keyFieldPattern` correctly excludes the `tag` field name.
- **Committed in:** 2dea0e7 (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (1 bug — wrong JSON shape in plan example; 1 missing critical — threat-model mitigation needed explicit assertion)
**Impact on plan:** Both deviations strengthen the test contract without changing the production code or scope. No scope creep — all production behaviour is exactly as specified in the plan.

## Issues Encountered

- **Worktree had no `.planning/` directory.** The worktree was created from a clean tree; `.planning/` is gitignored at root via `.claude/` (the worktree itself lives under `.claude/worktrees/`), and the planning files exist only in the main checkout. Read all plan/context files from `/Users/jonb/Projects/tfc-hmi2/.planning/...` (the absolute path) and created `.planning/phases/01-sensor-asset/` fresh inside the worktree to host this SUMMARY. Resolved without code changes.
- **Round-trip determinism risk** flagged by the plan: tested by the round-trip test (`equals(json)` Map deep-equality) — passed on first GREEN. The constructor's `Color? activeColor` / `Color? inactiveColor` parameters were the concern (legacy JSON loads them as null → defaulted in constructor; explicit JSON loads them as colored maps → preserved). Both paths produce a populated Color, so `toJson` always emits the colored map; round-trip is deterministic.

## TDD Gate Compliance

- **RED gate (test commit):** ✅ — `c6ddc8a`, `2dea0e7`, `db6afa2` all `test(01-01)` and predate their corresponding `feat(01-01)` commits.
- **GREEN gate (feat commit after RED):** ✅ — `f92ee2a` follows `c6ddc8a`; `f5a89f6` follows `db6afa2`.
- **REFACTOR gate:** Not applicable — Task 4 GREEN was minimal (single ternary), no refactor needed.
- **Commit count vs success criterion (`≥4`):** 5 commits — passes.

## Threat Flags

No new threat surface introduced beyond the `<threat_model>` register in the PLAN.md. T-01-01 (json_serializable type validation + unknownEnumValue) and T-01-03 (tag NOT in allKeys) are covered by tests in this plan.

## Known Stubs

- `SensorConfig.build(BuildContext)` — throws `UnimplementedError('Sensor widget — Plan 03')`. Intentional deferral. Plan 03 will replace with the actual widget that wires `StateMan.subscribe(detectionKey)` → `sensorIsActive` → painter.
- `SensorConfig.configure(BuildContext)` — throws `UnimplementedError('Sensor config dialog — Plan 05')`. Intentional deferral. Plan 05 will replace with `_SensorConfigEditor` (mirror of `_ConveyorGateConfigEditor`).

Both stubs are explicit, named, and reference the future plan that resolves them. They are non-blocking for downstream plans 02 (painter) and 04 (registry), which consume only the data model.

## Self-Check

- ✅ `lib/page_creator/assets/sensor.dart` exists (101 lines)
- ✅ `lib/page_creator/assets/sensor.g.dart` exists (69 lines, generated)
- ✅ `test/page_creator/assets/sensor_config_test.dart` exists (190 lines, 21 tests passing)
- ✅ Commit `c6ddc8a` exists in worktree branch
- ✅ Commit `f92ee2a` exists in worktree branch
- ✅ Commit `2dea0e7` exists in worktree branch
- ✅ Commit `db6afa2` exists in worktree branch
- ✅ Commit `f5a89f6` exists in worktree branch
- ✅ `flutter test test/page_creator/assets/sensor_config_test.dart` exits 0 (21/21 green)
- ✅ `flutter analyze` reports 0 errors and 0 warnings on the two target files (4 info-level `Color.value` deprecations match existing project convention in `conveyor_gate_test.dart`)
- ✅ `git log --oneline | grep -E "(test|feat|refactor)\(01-01\)" | wc -l` = 5 (≥ 4 required)
- ✅ `grep -c "import 'package:tfc/page_creator/assets/sensor.dart'" test/page_creator/assets/sensor_config_test.dart` = 1
- ✅ `grep -c "^enum SensorKind" lib/page_creator/assets/sensor.dart` = 1
- ✅ `grep -c "class SensorConfig extends BaseAsset" lib/page_creator/assets/sensor.dart` = 1
- ✅ `grep -c "_\$SensorConfigFromJson" lib/page_creator/assets/sensor.g.dart` = 1
- ✅ `grep -c "invertActivePolarity ? !rawBool : rawBool" lib/page_creator/assets/sensor.dart` ≥ 1 (2 — comment + code)

## Self-Check: PASSED

## User Setup Required

None — no external service configuration required. Pure-Dart / pure-Flutter unit tests, no PLC or DB dependencies.

## Next Phase Readiness

- **Plan 02 (painter)** can import `SensorKind` and `SensorConfig.activeColor/inactiveColor` directly. The painter constructors take primitives only (per UI-SPEC §Painter Decomposition); no further data-model work is needed.
- **Plan 03 (widget)** can import `sensorIsActive` and call `SensorConfig.fromJson` for AssetRegistry integration; widget will replace `SensorConfig.build()`.
- **Plan 04 (registry)** can register `SensorConfig` in both `_fromJsonFactories` and `defaultFactories` of `lib/page_creator/assets/registry.dart` (per Pitfall 5).
- **Plan 05 (config dialog)** will replace `SensorConfig.configure()` with `_SensorConfigEditor`; field order is locked in `01-UI-SPEC.md` §Config Dialog Layout.

No blockers. The data model contract is locked — downstream plans can rely on the 21 tests as a regression boundary.

---
*Phase: 01-sensor-asset*
*Plan: 01*
*Completed: 2026-05-06*
