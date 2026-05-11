---
phase: 01-sensor-asset
plan: 03
subsystem: ui
tags: [sensor, widget, gesture, stream, riverpod, tdd, dart, flutter, pitfall-2]

# Dependency graph
requires:
  - phase: 01-01
    provides: SensorConfig + SensorKind enum + sensorIsActive() polarity helper
  - phase: 01-02
    provides: RedLightBeamPainter, OpticFieldPainter, InductiveFieldPainter (uniform constructor signature with isStale flag)
  - phase: pre-existing
    provides: BaseAsset, Coordinates, LayoutRotatedBox (lib/page_creator/assets/common.dart); stateManProvider (lib/providers/state_man.dart); ConsumerStatefulWidget (flutter_riverpod); led.dart + conveyor_gate.dart as analog widget patterns
provides:
  - Sensor ConsumerStatefulWidget — runtime entry point returned by SensorConfig.build(context)
  - _SensorState with hoisted bool stream, didUpdateWidget re-hoist, exhaustive _createPainter switch
  - GestureDetector tap-to-configure that survives a Transform.translate ancestor (forward-compat for Phase 3 elevator child)
  - Three stale paths driving painter isStale=true (empty key, no data, error)
  - Polarity inversion via sensorIsActive() applied before painter receives isActive
  - LayoutRotatedBox honouring config.coordinates.angle (degrees → radians)
  - AlertDialog placeholder body in SensorConfig.configure() (Plan 05 will replace the body)
  - Two @visibleForTesting test seams: resolveIsActive(rawBool), debugDetectionStream getter
  - 13 widget tests across 5 groups (Tap to configure, Stale rendering, Rotation, Polarity through widget, Stream lifecycle)
affects: [01-04-tooltip-label, 01-05-dialog-and-registry, 03-elevator-children]

# Tech tracking
tech-stack:
  added: []  # No new dependencies — uses existing flutter_riverpod, flutter_test, json_annotation, flutter material
  patterns:
    - "Stream hoisted in initState + tracked-key field for didUpdateWidget rehoist (Pitfall 2 invariant survives in-place SensorConfig mutation by the editor)"
    - "GestureDetector OUTSIDE LayoutRotatedBox (matches conveyor_gate.dart _buildGate; LayoutRotatedBox.hitTest in common.dart does not forward to its child, so gestures inside it are dropped)"
    - "LayoutBuilder propagates parent constraints into CustomPaint.size so the gesture box has a non-zero hit area"
    - "@visibleForTesting test seams (resolveIsActive, debugDetectionStream) — Dart library privacy blocks dynamic access to _-prefixed members from a test file"
    - "Source-level grep guards in widget tests for SENS-05 (no AnimationController) and Pitfall 2 (no stream construction inside build())"

key-files:
  created:
    - test/page_creator/assets/sensor_widget_test.dart
    - .planning/phases/01-sensor-asset/01-03-SUMMARY.md
  modified:
    - lib/page_creator/assets/sensor.dart

key-decisions:
  - "GestureDetector wraps LayoutRotatedBox (outside, not inside) — this deviates from the plan's prescribed structure but is required because LayoutRotatedBox.hitTest in lib/page_creator/assets/common.dart at lines 1334-1364 does not forward to its child. Matches the existing conveyor_gate.dart _buildGate convention exactly."
  - "didUpdateWidget compares against an internally-tracked _hoistedKey:String?, NOT oldWidget.config.detectionKey. The editor mutates the same SensorConfig instance in-place, so oldWidget.config and widget.config are identity-equal references — comparing keys through them would silently drop the rehoist. Discovered by the 'changing detectionKey re-hoists' regression test (Rule-1 bug fix during Task 4)."
  - "Two @visibleForTesting test seams added (resolveIsActive, debugDetectionStream get) — minimal API surface that exposes only what the polarity + lifecycle tests need. Both are documented as test-only and route to the same private state."
  - "Stale path is the single source of truth for 'no data right now' — empty detectionKey, !snapshot.hasData, and snapshot.hasError all converge on _createPainter(isActive: false, isStale: true). The painters then render the entire glyph in Colors.grey (UI-SPEC §Color matrix)."
  - "configure() returns AlertDialog placeholder with title 'Configure Sensor' so Task 1's tap test can assert dialog presence (UI-SPEC §Copywriting Contract — title is host-provided, but the AlertDialog body must already be tap-test-friendly today; Plan 05 replaces the body)."
  - "Sensor extends ConsumerStatefulWidget (not ConsumerWidget like Led). The State is required because the bool stream must be HOISTED — it cannot live in build() and cannot be a top-level Provider (per-widget identity is required for Pitfall 10)."

patterns-established:
  - "TDD cadence preserved: 4 commits matching (test|feat|fix\\+test)\\(01-03\\) — RED test → GREEN feat → RED test → GREEN feat → fix+test (Rule 1 bug uncovered by test)"
  - "Test seam idiom: @visibleForTesting public getter onto private state (debugDetectionStream) so tests can assert reference identity without casting through dynamic"
  - "Source-level regression guards (read sensor.dart as a string, regex-scan build() body) lock invariants that runtime tests can't easily catch — useful for Pitfall 2 and SENS-05"
  - "Three-way stale convergence: detectionKey.isEmpty, !snapshot.hasData, snapshot.hasError all route to the same isStale=true rendering — no separate code paths for the three causes"

requirements-completed:
  - SENS-01   # Sensor renders + tap-to-configure (GestureDetector → AlertDialog)
  - SENS-05   # Visual flips immediately on bool emit — grep-guarded against AnimationController/TweenAnimationBuilder/animateTo
  - SENS-12   # Polarity inversion through the widget — sensorIsActive() applied before painter; @visibleForTesting resolveIsActive validates
  - SENS-14   # Stale rendering on empty key, no data, error — three convergent paths to isStale=true
  - QUAL-08   # TDD cadence visible in commit log: test → feat → test → feat → fix+test

requirements-deferred:
  # Tooltip + label rendering = Plan 04
  # Config dialog editor body = Plan 05
  # AssetRegistry registration + JSON round-trip integration = Plan 05

# Metrics
metrics:
  duration: ~30 min
  completed: 2026-05-06
  tasks_completed: 5
  task_commits: 5  # ddbf952 test, 48085f4 feat, aa7a098 test, fc7cf1c feat, 3779f1f fix+test (+ 2 chore commits — prereq seed and lint cleanup)
  test_count_added: 13  # +13 widget tests across 5 groups; 51 painter+config tests carried as regression baseline → 64 total sensor tests
  files_added: 1   # test/page_creator/assets/sensor_widget_test.dart
  files_modified: 1  # lib/page_creator/assets/sensor.dart
---

# Phase 01 Plan 03: Sensor widget — GestureDetector + stream hoisting Summary

**One-liner:** Built `Sensor` ConsumerStatefulWidget with hoisted bool stream (Pitfall 2), GestureDetector tap-to-configure that survives Transform.translate (Phase 3 forward-compat), three convergent stale paths, polarity inversion through `sensorIsActive`, and grep-guarded SENS-05 immediate-flip — all behaviour covered by 13 widget tests in 5 groups.

## What was built

`Sensor` is the runtime widget that `SensorConfig.build(context)` returns. It owns a `Stream<bool>` constructed exactly once per mount in `initState` (Pitfall 2 — the existing `conveyor_gate.dart` anti-pattern of inline stream construction in `build()` is explicitly avoided). When the editor mutates `config.detectionKey` in-place, `didUpdateWidget` re-hoists the stream by comparing against an internally-tracked `_hoistedKey` (because the same `SensorConfig` instance is reused across rebuilds — `oldWidget.config` and `widget.config` reference the same object, so comparing through them silently drops the change).

A `StreamBuilder<bool>` flips `isActive` immediately on each emission (no `AnimationController`, no `TweenAnimationBuilder`, no `animateTo` — locked at the source level by a regression test that scans `sensor.dart` as a string per SENS-05). `_createPainter` exhaustively switches on `SensorKind` to instantiate the right painter from Plan 02 (`RedLightBeamPainter`, `OpticFieldPainter`, `InductiveFieldPainter`). Three convergent paths drive `isStale: true` (renders entirely in `Colors.grey`):

1. `detectionKey.isEmpty` → no stream constructed, painter rendered immediately
2. `!snapshot.hasData` → stream attached but hasn't emitted yet
3. `snapshot.hasError` → stream errored

`_buildPaint` composes the visual stack: `GestureDetector(behavior: HitTestBehavior.opaque, onTap: …) → LayoutRotatedBox(angle: deg → rad) → LayoutBuilder → CustomPaint(size: paintSize, painter: …)`. The `GestureDetector` lives OUTSIDE the `LayoutRotatedBox` because `_RenderLayoutRotatedBox.hitTest` in `lib/page_creator/assets/common.dart` (lines 1334–1364) does not forward hits to its child — it only adds a self-entry. Putting the gesture inside drops every tap. This matches the existing `conveyor_gate.dart` `_buildGate` pattern. Tap-through-`Transform.translate` (Phase 3 forward-compat) is unaffected: `Transform.translate` defaults `transformHitTests: true`, and the widget test `'tap survives Transform.translate ancestor'` proves it.

`SensorConfig.configure()` returns an `AlertDialog` placeholder so Task 1's tap test can assert dialog presence — Plan 05 will replace the body with the real editor (kind selector, key fields, colour pickers, polarity switch).

## Tests added (13, 5 groups)

| Group | Test | Asserts |
|-------|------|---------|
| Tap to configure | tap on sensor with empty detectionKey opens AlertDialog | `find.byType(AlertDialog)` and `find.text('Configure Sensor')` after `tester.tap` |
| Tap to configure | tap survives Transform.translate ancestor (Phase 3 forward-compat) | Same dialog assertions through a `Transform.translate(offset: Offset(0, 100))` ancestor |
| Stale rendering | empty detectionKey causes painter to receive isStale=true | `RedLightBeamPainter.isStale == true` |
| Stale rendering | opticField + empty detectionKey | `OpticFieldPainter.isStale == true` |
| Stale rendering | inductiveField + empty detectionKey | `InductiveFieldPainter.isStale == true` |
| Rotation | config.coordinates.angle is honoured via LayoutRotatedBox | `LayoutRotatedBox.angle == 90° in radians` |
| Rotation | null angle defaults to 0 radians | `LayoutRotatedBox.angle == 0.0` |
| Polarity through widget | rawBool=true with invertActivePolarity=false | `resolveIsActive(true) == true && resolveIsActive(false) == false` |
| Polarity through widget | invertActivePolarity=true flips both directions | `resolveIsActive(true) == false && resolveIsActive(false) == true` |
| Polarity through widget | SENS-05 immediate-flip guard | `sensor.dart` source contains no `AnimationController`, `TweenAnimationBuilder`, `animateTo` |
| Stream lifecycle | rebuilds with same detectionKey do not re-hoist | `identical(stream1, stream2) == true` after rebuild |
| Stream lifecycle | changing detectionKey re-hoists the stream | `identical(stream1, stream2) == false` after `config.detectionKey = '/k2'` |
| Stream lifecycle | build() does not construct a stream inline (Pitfall 2 source-level guard) | regex on `sensor.dart` `build()` body forbids `stateManProvider` and `subscribe(` |

64/64 sensor tests pass (51 from Plans 01-01/01-02 + 13 from this plan). `flutter analyze` reports zero issues.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] GestureDetector positioning required deviating from plan's prescribed widget structure**
- **Found during:** Task 2 (GREEN test runs with the plan's prescribed `LayoutRotatedBox → GestureDetector → CustomPaint` order)
- **Issue:** `tester.tap(find.byType(Sensor))` did not trigger the dialog — the `GestureDetector` `onTap` callback never fired even though the SizedBox was 80×40 and the painter rect was non-zero.
- **Root cause:** `_RenderLayoutRotatedBox.hitTest` in `lib/page_creator/assets/common.dart` (lines 1334–1364) does NOT propagate the hit test to its child render object. It only calls `result.add(BoxHitTestEntry(this, position))` and returns `true`. So gestures sitting INSIDE `LayoutRotatedBox` never receive taps. The existing `conveyor_gate.dart` works around this by ALWAYS placing `GestureDetector` outside `LayoutRotatedBox` (see `_buildGate` at line 268 + the four `GestureDetector(onTap: ..., child: gate)` call-sites in `build`).
- **Fix:** Reordered `_buildPaint` to `GestureDetector → LayoutRotatedBox → LayoutBuilder → CustomPaint`. Inner `LayoutBuilder` propagates parent constraints into `CustomPaint.size:` so the gesture box has non-zero hit area (mirrors `conveyor_gate.dart:271-285`).
- **Forward-compat unaffected:** the Phase 3 `Transform.translate` ancestor hit-test still works because `Transform.translate` defaults `transformHitTests: true`. Widget test `'tap survives Transform.translate ancestor'` proves it.
- **Files modified:** `lib/page_creator/assets/sensor.dart`
- **Commit:** 48085f4

**2. [Rule 1 - Bug] didUpdateWidget compared the wrong key reference, dropping rehoists when the editor mutates SensorConfig in-place**
- **Found during:** Task 4 (`'changing detectionKey re-hoists the stream'` test)
- **Issue:** Initial implementation compared `oldWidget.config.detectionKey != widget.config.detectionKey`. When the editor dialog mutates the same `SensorConfig` instance and triggers a rebuild, `oldWidget.config` and `widget.config` are the SAME reference — both observe the new key, the comparison is `false`, and `_hoistStream()` is silently skipped. This is a Pitfall-2 regression vector (the bool stream stays subscribed to the OLD key).
- **Fix:** Added `String? _hoistedKey` field on `_SensorState`. `_hoistStream()` writes the current key into `_hoistedKey`. `didUpdateWidget` compares `_hoistedKey != widget.config.detectionKey` — robust against in-place config mutation.
- **Files modified:** `lib/page_creator/assets/sensor.dart`
- **Commit:** 3779f1f

**3. [Rule 3 - Blocking issue] Test seams required for private state access**
- **Found during:** Tasks 3 (polarity tests) and 4 (stream lifecycle tests)
- **Issue:** Dart's library privacy blocks `_`-prefixed name access from a test file in a different library, even via `dynamic`. The plan's snippets used `state._detectionStream` and assumed it would work — it does not.
- **Fix:** Added two minimal `@visibleForTesting` test seams on `_SensorState`:
  - `bool resolveIsActive(bool rawBool)` — for polarity assertions without a real `StateMan` (delegates to the same `sensorIsActive` helper used by `build`).
  - `Stream<bool>? get debugDetectionStream` — for stream-identity assertions in lifecycle tests.
- Both are documented as test-only with usage references back to the test file.
- **Files modified:** `lib/page_creator/assets/sensor.dart`
- **Commits:** fc7cf1c (resolveIsActive), 3779f1f (debugDetectionStream)

**4. [Rule 3 - Blocking issue] Doc-comment "no AnimationController" contradicted SENS-05 grep guard**
- **Found during:** Task 3 (immediate-flip guard test)
- **Issue:** The grep guard reads `sensor.dart` as a string and asserts `isNot(contains('AnimationController'))`. My initial Sensor class docstring contained the exact phrase "no AnimationController, no debounce..." — the guard correctly flagged this as a violation even though no animation primitives were imported.
- **Fix:** Rephrased the docstring to "no client-side animation, no tween, no debounce, no smoothing" — semantically identical, no forbidden literal token.
- **Files modified:** `lib/page_creator/assets/sensor.dart`
- **Commit:** fc7cf1c

**5. [Rule 3 - Style] Analyzer info-lints**
- **Found during:** Task 5 (regression sweep)
- **Issue:** Two info-level lints — `unnecessary_import` (flutter/foundation re-exported by material) and `no_leading_underscores_for_local_identifiers` (test helper `_wrap`).
- **Fix:** Dropped redundant import; renamed `_wrap` → `wrap`.
- **Files modified:** `lib/page_creator/assets/sensor.dart`, `test/page_creator/assets/sensor_widget_test.dart`
- **Commit:** a502cbf

## Cross-plan sequencing

This plan and Plan 02 ran in parallel on Wave 2 (disjoint files: `sensor_painter.dart` vs `sensor.dart`). The worktree was seeded with Plan 01-01 (`sensor.dart` data-model) and Plan 01-02 (`sensor_painter.dart` with the three painter classes) before this plan started. The `_createPainter` switch in this plan compiles cleanly because Plan 02 is already merged on `main`. **If running purely standalone (Plan 02 not merged), `flutter analyze` and tests would fail** until both plans are integrated. The chore commits at the start of this branch (`2d02ba8`, `0ae4db9`, `3e9cc6b`) seed those prerequisites into the worktree.

## Threat-Model coverage

| Threat ID | Disposition | Mitigation in this plan |
|-----------|-------------|--------------------------|
| T-01-06 | mitigate | (1) Stream hoisted to `initState`, (2) didUpdateWidget compares against `_hoistedKey` so in-place config mutation still triggers exactly one rehoist (not zero, not many), (3) widget test `'rebuilds with same detectionKey do not re-hoist'` asserts `identical(stream1, stream2)`, (4) widget test `'changing detectionKey re-hoists'` asserts non-identity after key mutation, (5) source-level grep guard `'build() does not construct a stream inline'` forbids `stateManProvider` and `subscribe(` from appearing inside the `build()` body |
| T-01-07 | accept | DynamicValue.asBool returns false for non-bool types (existing StateMan behaviour); a misconfigured key renders inactive — visible to operators (looks stuck), not silently corrupt. No code added in this plan. |
| T-01-08 | accept | UI-SPEC explicitly locks tap-opens-dialog. The Plan 05 dialog (replacing the placeholder here) will have no destructive actions. In editor mode the page editor's outer GestureDetector intercepts (existing tfc-hmi2 behaviour). No code added in this plan. |
| T-01-09 | mitigate | This plan's `configure()` returns a placeholder `AlertDialog` with no `stateMan.write` call. The future Plan 05 dialog will mutate the local `SensorConfig` object only; a write-capable feature would need explicit policy gating. |

## Deferred to later plans

- **Plan 04:** Tooltip + painter label rendering (`config.tag` is wired through `_createPainter` here so the painters receive `label:`, but this plan does NOT add the on-hover tooltip with rising/falling-edge keys; that's Plan 04).
- **Plan 05:** Real config-dialog editor body, AssetRegistry registration, JSON round-trip integration test.

## Self-Check: PASSED

- [x] `lib/page_creator/assets/sensor.dart` — modified (FOUND)
- [x] `test/page_creator/assets/sensor_widget_test.dart` — created (FOUND)
- [x] Commit ddbf952 (test 01-03 RED tap/translate/stale/rotation) — FOUND
- [x] Commit 48085f4 (feat 01-03 Sensor widget GREEN) — FOUND
- [x] Commit aa7a098 (test 01-03 RED polarity + immediate-flip guard) — FOUND
- [x] Commit fc7cf1c (feat 01-03 GREEN resolveIsActive + doc fix) — FOUND
- [x] Commit 3779f1f (fix+test 01-03 stream-lifecycle Pitfall 2) — FOUND
- [x] Commit a502cbf (chore 01-03 lint cleanup) — FOUND
- [x] All 13 widget tests pass; 64/64 sensor tests pass (incl. Plans 01-01 + 01-02 baseline)
- [x] `flutter analyze lib/page_creator/assets/sensor.dart test/page_creator/assets/sensor_widget_test.dart` — zero issues
- [x] `grep -c "AnimationController" lib/page_creator/assets/sensor.dart` returns 0
- [x] `grep -c "TweenAnimationBuilder" lib/page_creator/assets/sensor.dart` returns 0
- [x] `grep -c "animateTo" lib/page_creator/assets/sensor.dart` returns 0
