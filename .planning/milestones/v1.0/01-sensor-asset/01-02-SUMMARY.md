---
phase: 01-sensor-asset
plan: 02
subsystem: ui
tags: [sensor, painter, golden, tdd, custom-painter, dart, flutter]

# Dependency graph
requires:
  - phase: 01-sensor-asset
    plan: 01
    provides: SensorKind enum + SensorConfig data model + sensorIsActive helper
provides:
  - RedLightBeamPainter (CustomPainter) — paired beam glyph, dashed when broken
  - OpticFieldPainter (CustomPainter) — housing + cone, filled at α=0.40 when active
  - InductiveFieldPainter (CustomPainter) — housing puck + bubble ellipse, filled at α=0.40 when active
  - shouldRepaint contract enforcing cross-runtimeType guard (Pitfall 3) + per-field equality
  - 8-state golden matrix from UI-SPEC §Test Coverage Contract + 1 stale golden = 9 PNG baselines
  - Eight locked proportional constants (`kHousingFraction`, `kBeamStrokeWidth`, `kFieldStrokeWidth`, `kBorderStrokeWidth`, `kDashOnPx`, `kDashOffPx`, `kFieldFillAlpha`, `kLabelFontFraction`)
affects: [01-03-widget, 01-04-registry]

# Tech tracking
tech-stack:
  added: []  # No new dependencies — re-uses flutter (CustomPainter, TextPainter), flutter_test (matchesGoldenFile)
  patterns:
    - "Painter takes primitives only — no WidgetRef, no Stream, no Provider (Pitfall 2)"
    - "One CustomPainter subclass per kind — no `switch (kind)` inside paint() (Pitfall 3)"
    - "shouldRepaint(covariant CustomPainter oldDelegate) with runtimeType guard BEFORE cast — handles cross-kind without throwing"
    - "Paint objects allocated inside paint() — never as instance fields (avoids stale Paint on parameter change)"
    - "Polarity-pair golden duplication is byte-identical (cmp-verified) — locks the contract that polarity is pre-painter"
    - "Skip-on-non-macOS golden guard mirrors conveyor_gate_golden_test.dart (Pitfall 6 platform determinism)"

key-files:
  created:
    - lib/page_creator/assets/sensor_painter.dart
    - test/page_creator/assets/sensor_painter_test.dart
    - test/page_creator/assets/goldens/sensor/red_light_clear.png
    - test/page_creator/assets/goldens/sensor/red_light_broken.png
    - test/page_creator/assets/goldens/sensor/red_light_clear_inverted.png
    - test/page_creator/assets/goldens/sensor/red_light_broken_inverted.png
    - test/page_creator/assets/goldens/sensor/optic_field_inactive.png
    - test/page_creator/assets/goldens/sensor/optic_field_active.png
    - test/page_creator/assets/goldens/sensor/inductive_field_inactive.png
    - test/page_creator/assets/goldens/sensor/inductive_field_active.png
    - test/page_creator/assets/goldens/sensor/stale.png
    - .planning/phases/01-sensor-asset/01-02-SUMMARY.md
  modified: []

key-decisions:
  - "Skip golden tests on non-macOS via Platform.isMacOS guard at the group level — matches existing conveyor_gate_golden_test.dart convention; goldens are macOS-locked (Pitfall 6)"
  - "Inline SizedBox(width: 256, height: 128) in each golden test rather than a shared helper — satisfies the plan's literal acceptance regex AND keeps each test fully self-describing for future maintainers"
  - "Beam drawn UNDER pucks (not over) so the stroke endpoints tuck beneath the housings — cleaner appearance at small sizes, no visual change at large sizes"
  - "Stale flag overrides isActive completely (proven by stale golden using isActive=true)"
  - "shouldRepaint uses `covariant CustomPainter oldDelegate` so the framework signature compiles AND the runtimeType guard runs BEFORE the down-cast — cross-kind expectations don't throw"
  - "Removed unused _resolve helper after analyzer flagged it — paint() bodies inline the colour decisions per kind, which is clearer than a 4-arg helper"

patterns-established:
  - "Two-cycle TDD per plan: Cycle A = shouldRepaint contract (test→feat); Cycle B = golden matrix (test→feat). Each cycle has its own RED-then-GREEN commit pair, total 4 commits visible in git log."
  - "Polarity pairs share the SAME painter input (both inputs equal `isActive=false` for clear pair, both `isActive=true` for broken pair) — the polarity inversion is upstream in the widget layer (Plan 03), so the painter's golden is identical."
  - "Capture-then-verify-then-commit golden discipline: --update-goldens, visually inspect each PNG, cmp polarity-pairs, run again WITHOUT --update-goldens to confirm compare-mode passes, only then commit."

requirements-completed:
  - SENS-03  # per-kind subclass dispatch (RedLight/Optic/Inductive painters)
  - SENS-04  # red-light emitter + receiver + beam glyph
  - SENS-06  # solid-vs-dashed beam (clear vs broken)
  - SENS-07  # filled-vs-outlined field (active vs inactive)
  - SENS-08  # configurable activeColor + inactiveColor (via constructor primitives)
  - SENS-14  # partial — isStale flag rendering (widget wires it in Plan 03)
  - QUAL-01  # shouldRepaint contract enforced
  - QUAL-02  # 8-golden matrix locked
  - QUAL-08  # RED→GREEN cadence visible in git log

# Metrics
duration: ~10 min
completed: 2026-05-06
---

# Phase 01 Plan 02: Sensor Painters + Golden Matrix Summary

**Three `CustomPainter` subclasses (RedLight / OpticField / InductiveField) plus a 9-image golden matrix capturing the 8-state colour contract + 1 stale state — all under TDD discipline with 30 tests and a cross-runtimeType repaint guard that closes Pitfall 3.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-06T07:50:00Z
- **Completed:** 2026-05-06T07:59:51Z
- **Tasks:** 5 (4 TDD + 1 sweep)
- **Tests added:** 30 (21 shouldRepaint + 9 golden) — all green
- **Determinism:** 5 consecutive `flutter test` runs all PASS
- **Commits:** 4 (2 test, 2 feat) — RED-before-GREEN cadence verified
- **Files created:** 11 (1 source, 1 test, 9 golden PNGs)

## Accomplishments

- `RedLightBeamPainter`, `OpticFieldPainter`, `InductiveFieldPainter` all extend `CustomPainter` with the locked uniform constructor signature (`isActive`, `activeColor`, `inactiveColor`, `label?`, `isStale`).
- `shouldRepaint(covariant CustomPainter oldDelegate)` returns `true` for any cross-runtimeType call (Pitfall 3), `isActive` flip, `activeColor`/`inactiveColor` change, `label` change, or `isStale` change. Returns `false` only when ALL five inputs are identical.
- Eight proportional constants live at file scope (`kHousingFraction`, `kBeamStrokeWidth`, `kFieldStrokeWidth`, `kBorderStrokeWidth`, `kDashOnPx`, `kDashOffPx`, `kFieldFillAlpha`, `kLabelFontFraction`) — locked from UI-SPEC §Painter proportional ladder.
- `RedLightBeamPainter` glyph: emitter puck at (0.15·w, 0.5·h), receiver puck at (0.85·w, 0.5·h), both `kHousingFraction · shortestSide` diameter; beam line spans the puck centres at `kBeamStrokeWidth · shortestSide`. Solid grey when clear, dashed activeColor (6-on / 4-off absolute pixels) when broken, all-grey when stale.
- `OpticFieldPainter` glyph: housing rectangle at (0.05·w, 0.30·h)–(0.30·w, 0.70·h); cone path apex at housing right-centre, base spans (0.95·w, 0.20·h)–(0.95·w, 0.80·h). Outlined inactiveColor when inactive, filled `activeColor.withValues(alpha: 0.40)` + activeColor outline (visible underneath) when active, grey-outlined when stale.
- `InductiveFieldPainter` glyph: housing puck centred at (0.30·w, 0.50·h) `kHousingFraction · shortestSide` diameter; bubble ellipse `Rect.fromCenter(center: (0.65·w, 0.50·h), width: 2·0.25·w, height: 2·0.30·h)`. Same colour-state rules as optic field.
- 9-image golden matrix captured at 256×128 canvas; `red_light_clear.png` + `red_light_clear_inverted.png` byte-identical (cmp passes); `red_light_broken.png` + `red_light_broken_inverted.png` byte-identical. `stale.png` shows all-grey rendering with `isActive=true` (proves stale overrides active mapping).
- Determinism guard: 5 consecutive `flutter test` runs all pass; no flakes.
- `flutter analyze` clean: zero errors, zero warnings on both target files.

## Task Commits

Each task committed atomically; TDD cadence (RED → GREEN) preserved in git log:

1. **Setup chore:** seed worktree with plan 01-01 prerequisites + planning docs — `c65ea71` (chore)
2. **Task 1 [RED]:** failing shouldRepaint contract tests (21 tests, 3 cross-runtimeType + 18 per-field) — `1cd8e54` (test)
3. **Task 2 [GREEN]:** painter skeletons with shouldRepaint correct, paint() transparent stubs — `c7d8346` (feat)
4. **Task 3 [RED]:** failing 9-test golden matrix (8 colour states + 1 stale) — `6461490` (test)
5. **Task 4 [GREEN]:** paint() bodies + 9 PNG baselines captured — `6161c74` (feat)

_Note: Task 5 (determinism + summary) ran `flutter test` 5x (all green), `flutter analyze` (no issues), and produced this SUMMARY. The summary commit lands separately as the final metadata commit._

## Files Created/Modified

- `lib/page_creator/assets/sensor_painter.dart` (~310 lines) — Three CustomPainter subclasses, eight file-scope constants, two private helpers (`_paintLabel`, `_drawDashedLine`, `_housingFill`, `_housingBorder`).
- `test/page_creator/assets/sensor_painter_test.dart` (~590 lines) — 21 shouldRepaint tests + 9 golden tests; goldens skipped on non-macOS via Platform.isMacOS guard.
- `test/page_creator/assets/goldens/sensor/*.png` × 9 — Locked baselines:
  - `red_light_clear.png` (2948 bytes) — solid grey beam between grey pucks
  - `red_light_broken.png` (3089 bytes) — dashed green beam
  - `red_light_clear_inverted.png` — byte-identical to `red_light_clear.png`
  - `red_light_broken_inverted.png` — byte-identical to `red_light_broken.png`
  - `optic_field_inactive.png` (3615 bytes) — grey housing + grey-outlined cone
  - `optic_field_active.png` (3765 bytes) — green-filled translucent cone with green outline
  - `inductive_field_inactive.png` (5015 bytes) — grey puck + grey-outlined ellipse
  - `inductive_field_active.png` (4906 bytes) — grey puck + green-filled translucent ellipse with green outline
  - `stale.png` (1966 bytes) — all-grey beam glyph (no green even though `isActive=true`)

## Decisions Made

- **Used `Platform.isMacOS` guard at group level for goldens** — matches the existing convention in `conveyor_gate_golden_test.dart`. This integrates the new tests with the project's existing CI behaviour (where goldens only capture on macOS to avoid platform-specific font/rendering drift). The plan didn't explicitly require this, but it's the responsible default per Pitfall 6.
- **Inlined `SizedBox(width: 256, height: 128)` in each of the 9 golden tests** rather than extracting a shared `paintWidget` helper. Two reasons: (1) the plan's literal acceptance criterion regex `grep -c "width: 256,"` returns ≥9 only with the inlined form, and (2) per-test inlining means future maintainers reading any one test see the full setup without jumping to a helper.
- **Beam line drawn before pucks** in `RedLightBeamPainter` so puck borders mask the dashed beam endpoints. At small sizes the dashed-pattern phase doesn't always end on a clean dash, and tucking the beam under the puck border hides any partial-dash artifact.
- **`shouldRepaint(covariant CustomPainter oldDelegate)` with explicit `runtimeType` check before the down-cast** — without the `runtimeType` guard, the `as RedLightBeamPainter` cast would throw on a cross-kind comparison. The check-then-cast pattern is the only safe way to satisfy the framework's `covariant` signature AND the cross-kind acceptance test simultaneously.
- **Removed the unused `_resolve` helper** after analyzer flagged it — each painter inlines its own colour decisions (3 short ternaries per painter), which is more readable than threading 4 args through a helper just to save a few lines.
- **Applied `RepaintBoundary(key: goldenKey)` wrapper inside the `MaterialApp/Scaffold` chrome** so `find.byKey(goldenKey)` matches only the painter's own pixels, not the surrounding Material padding. This is the standard golden-test pattern from `conveyor_gate_golden_test.dart`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused `_resolve` helper that the plan suggested but never used in the painter bodies**

- **Found during:** Task 4 (post-write `flutter analyze` run)
- **Issue:** The plan's Task 4 action body specifies a `_resolve` helper with the signature `Color _resolve({required bool isStale, required bool isActive, required Color activeColor, required Color inactiveColor})`. After implementing `paint()` bodies for all three painters, none of them actually called `_resolve` — each painter's colour decisions are short enough (two ternaries) to inline directly. The analyzer flagged the unused declaration as a warning.
- **Fix:** Removed the helper. Inline ternaries used instead: `final labelColour = isStale ? Colors.grey : inactiveColor;` and the `isStale ? grey : (isActive ? activeColor : inactiveColor)` decisions inside each painter.
- **Files modified:** `lib/page_creator/assets/sensor_painter.dart`
- **Verification:** `flutter analyze` returns no issues; all 30 tests still pass.
- **Committed in:** `6161c74` (Task 4 commit)

**2. [Rule 2 - Missing Critical] Added `Platform.isMacOS` skip guard to the Golden matrix group**

- **Found during:** Task 3 (writing the golden test group)
- **Issue:** The plan describes the golden test pattern but doesn't specify the platform-skip guard. Without the guard, the goldens would be invoked on non-macOS CI runs and either (a) fail because the captured baselines were macOS-rendered, or (b) regenerate baselines that look different on Linux/Windows. The existing `conveyor_gate_golden_test.dart` uses `skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null` — Pitfall 6 (platform determinism). Without this guard, future CI runs would flake.
- **Fix:** Added `import 'dart:io' show Platform;` and `skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null` to the `group('Golden matrix', ...)` call. Mirrors the existing convention exactly.
- **Files modified:** `test/page_creator/assets/sensor_painter_test.dart`
- **Verification:** Tests pass on macOS (where this work was done); skip is exercised on non-macOS — matches the gate test convention.
- **Committed in:** `6461490` (Task 3 commit, baked in from the start)

---

**Total deviations:** 2 auto-fixed (1 bug — unused helper that the plan suggested but never actually consumed; 1 missing critical — platform-skip guard for golden tests).
**Impact on plan:** Both deviations strengthen the contract without changing the core production behaviour. The unused helper removal is purely cosmetic (analyzer cleanliness). The skip guard is the responsible default for cross-platform golden testing.

## Issues Encountered

- **Worktree had no `.planning/` directory or plan-01 outputs.** The worktree branch `worktree-agent-aa1db2c0` was created from `7326ed7` (an older `main` commit), predating Plan 01-01's outputs. Solution: `git checkout dac8a08 -- .planning/ CLAUDE.md lib/page_creator/assets/sensor.dart lib/page_creator/assets/sensor.g.dart test/page_creator/assets/sensor_config_test.dart .gitignore` to bring in plan-01 files, then committed as `chore(01-02): seed worktree with plan 01-01 prerequisites and planning docs` (c65ea71). This is a worktree-orchestration artefact, not a code issue.
- **BSD grep doesn't span newlines for `.*` regex.** The plan's acceptance criterion uses `grep -cE "RedLightBeamPainter\(.*\).shouldRepaint\(OpticFieldPainter|..."` which requires the painter construction + `.shouldRepaint(...)` call on a single physical line. The initial test layout split construction across multiple lines (idiomatic Dart). Resolved by writing the cross-runtimeType expectations on long single lines — gives 3 regex hits (≥2 required).

## TDD Gate Compliance

- **RED gate (test commit):** ✅ — `1cd8e54` (Task 1) and `6461490` (Task 3) both `test(01-02)` and predate their `feat(01-02)` partners.
- **GREEN gate (feat commit after RED):** ✅ — `c7d8346` follows `1cd8e54`; `6161c74` follows `6461490`.
- **REFACTOR gate:** Not applicable — neither GREEN required a structural cleanup pass beyond removing the unused `_resolve` helper (which happened pre-commit during the same Task 4 GREEN, not as a separate refactor commit).
- **Commit count vs success criterion (`≥4`):** 4 commits — passes exactly.

## Threat Flags

No new threat surface introduced. Both registered threats from the PLAN.md `<threat_model>` are addressed:

- **T-01-04 (Tampering — golden file substitution masking buggy paint code):** Mitigated by (a) visual review of all 9 PNGs at capture time (each was opened and confirmed against the UI-SPEC contract), (b) byte-identity assertion on polarity pairs via `cmp` (proves the polarity-inversion contract is pre-painter), (c) 5-run determinism check rejects any non-deterministic paint code.
- **T-01-05 (Information Disclosure — operator-typed label drawn to canvas):** Accepted — `_paintLabel` calls `TextPainter` which renders only paint commands (no script execution possible). HMI labels are operator-controlled and intentionally rendered.

## Known Stubs

None. All three painters have full `paint()` bodies; no `// TODO`, no `UnimplementedError`. The label is drawn whenever `label != null && label.isNotEmpty` — implementations of every visual state are complete.

The downstream `SensorConfig.build()` and `SensorConfig.configure()` stubs from Plan 01-01 remain in place — those are explicitly deferred to Plans 03 and 05 respectively, and are not in scope for Plan 02.

## Self-Check

- ✅ `lib/page_creator/assets/sensor_painter.dart` exists (~310 lines)
- ✅ `test/page_creator/assets/sensor_painter_test.dart` exists (~590 lines, 30 tests passing)
- ✅ All 9 golden PNGs exist on disk
- ✅ Polarity pair PNGs byte-identical (cmp exit 0 for both pairs)
- ✅ Commit `1cd8e54` exists in worktree branch (Task 1 RED)
- ✅ Commit `c7d8346` exists in worktree branch (Task 2 GREEN)
- ✅ Commit `6461490` exists in worktree branch (Task 3 RED)
- ✅ Commit `6161c74` exists in worktree branch (Task 4 GREEN)
- ✅ `flutter test test/page_creator/assets/sensor_painter_test.dart` exits 0 (30/30 green)
- ✅ 5 consecutive `flutter test` runs all pass (determinism)
- ✅ `flutter analyze` reports 0 errors, 0 warnings on both target files
- ✅ `git log --oneline | grep -E "(test|feat)\(01-02\)" | wc -l` = 4 (≥ 4 required)
- ✅ `grep -c "import 'package:tfc/page_creator/assets/sensor_painter.dart'" test/page_creator/assets/sensor_painter_test.dart` = 1
- ✅ `grep -cE "^class (RedLightBeamPainter|OpticFieldPainter|InductiveFieldPainter) extends CustomPainter" lib/page_creator/assets/sensor_painter.dart` = 3
- ✅ `grep -c "oldDelegate.runtimeType != runtimeType" lib/page_creator/assets/sensor_painter.dart` = 3
- ✅ `grep -cE "^const double (kHousingFraction|kBeamStrokeWidth|kFieldStrokeWidth|kBorderStrokeWidth|kDashOnPx|kDashOffPx|kFieldFillAlpha|kLabelFontFraction)" lib/page_creator/assets/sensor_painter.dart` = 8
- ✅ `grep -c "WidgetRef\|Stream\|Provider" lib/page_creator/assets/sensor_painter.dart` = 0 (painter purity)
- ✅ `grep -c "_drawDashedLine" lib/page_creator/assets/sensor_painter.dart` = 2 (≥2 required)
- ✅ `grep -c "// STUB — full implementation in Task 4" lib/page_creator/assets/sensor_painter.dart` = 0

## Self-Check: PASSED

## User Setup Required

None — no external service configuration required. Pure Flutter `CustomPainter` work; no PLC, no DB, no network. The golden baselines are macOS-locked (Pitfall 6) so any future contributor running these tests on a non-macOS host will see the group skipped automatically.

## Next Phase Readiness

- **Plan 03 (widget)** can now construct any of the three painters with stream-resolved primitives. Painters take `bool isActive` (already polarity-applied via `sensorIsActive`), `Color activeColor`, `Color inactiveColor`, `String? label`, `bool isStale`. The widget will own the `StreamBuilder`, `_isStale` derivation, and `Tooltip` chrome. Painter file zero changes anticipated.
- **Plan 04 (registry)** can register `SensorConfig` in `AssetRegistry._fromJsonFactories` + `defaultFactories`. The painter file is consumed only via `Sensor.build()` (Plan 03), not by registry directly. No painter API changes anticipated.
- **Plan 05 (config dialog)** will not touch the painter file at all — colour pickers and segmented buttons live in `SensorConfig.configure()` only.

No blockers. The painter contract is locked: 30 tests + 9 byte-identical-on-rerun goldens + Pitfall 3 cross-runtimeType guard. Downstream plans can rely on this contract for visual regression coverage.

---
*Phase: 01-sensor-asset*
*Plan: 02*
*Completed: 2026-05-06*
