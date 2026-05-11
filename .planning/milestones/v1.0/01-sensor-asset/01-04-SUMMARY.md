---
phase: 01-sensor-asset
plan: 04
subsystem: ui
tags: [sensor, tooltip, label, tag, riverpod, streambuilder, tdd, dart, flutter]

# Dependency graph
requires:
  - phase: 01-01
    provides: SensorConfig (tag, risingEdgeDelayKey, fallingEdgeDelayKey fields already on the model)
  - phase: 01-02
    provides: RedLightBeamPainter / OpticFieldPainter / InductiveFieldPainter with `label` constructor parameter and `_paintLabel` helper
  - phase: 01-03
    provides: Sensor ConsumerStatefulWidget with hoisted bool stream and _createPainter switch (already passes label through; Plan 04 captures the corresponding golden and wraps the result in a Tooltip)
  - phase: pre-existing
    provides: Material Tooltip with richMessage:WidgetSpan API; stateManProvider; DynamicValue.asInt
provides:
  - Tooltip(richMessage:WidgetSpan(child: _SensorTooltipContent)) wrapping the existing GestureDetector → LayoutRotatedBox → CustomPaint chain (UI-SPEC §Tooltip trigger — outer Tooltip, inner GestureDetector)
  - _SensorTooltipContent ConsumerWidget — short-circuits to "Detection key not set" when config.detectionKey is empty; otherwise renders a Column of two _DelayRow children
  - _DelayRow ConsumerWidget — short-circuits to "<label>: —" for empty stateKey (no subscription created); StreamBuilder<num> rendering "<label>: …" while no data, "<label>: <ms>ms" on data, em-dash on hasError
  - Subscribe-on-open / cancel-on-close lifecycle satisfied implicitly by Flutter's Tooltip overlay mounting the rich-message widget on open and unmounting on dismissal
  - Tenth golden test/page_creator/assets/goldens/sensor/red_light_with_label.png (256×128, label='PE-101A', isActive=true)
  - 8 new widget tests across 3 groups (Tag pass-through ×2, Tooltip presence ×1, Tooltip content ×3, Tooltip subscription lifecycle ×2)
affects: [01-05-dialog-and-registry]

# Tech tracking
tech-stack:
  added: []  # No new dependencies — uses existing flutter Tooltip, flutter_riverpod, flutter_test
  patterns:
    - "Tooltip(richMessage: WidgetSpan(child: _Stateful)) — embed a stateful subscriber whose lifetime is bounded by the tooltip's open state; subscriptions live in the subscriber's StreamBuilder and are torn down on widget unmount"
    - "Avoid Widget.key shadowing — name the constructor parameter stateKey (not key) when the value is a string identifier rather than a Widget Key"
    - "Short-circuit empty state-keys at the row level — no monitored item is created for an unconfigured delay key (preserves the lifecycle invariant from CONTEXT)"
    - "Stream construction inside a tooltip content widget IS allowed even though Pitfall 2 forbids it inside the main widget's build() — because the tooltip content is mounted/unmounted as a unit, the stream identity is per-tooltip-open by design"
    - "Locked tooltip copy strings rendered via Text('$label: —') / Text('$label: …') / Text('$label: ${ms}ms'); copy contract enforced via find.text widget tests rather than source-grep (the template-string form is more idiomatic than a grep-friendly literal)"

key-files:
  created:
    - test/page_creator/assets/goldens/sensor/red_light_with_label.png
    - .planning/phases/01-sensor-asset/01-04-SUMMARY.md
  modified:
    - lib/page_creator/assets/sensor.dart
    - test/page_creator/assets/sensor_painter_test.dart
    - test/page_creator/assets/sensor_widget_test.dart

key-decisions:
  - "_DelayRow's PLC state-key parameter is named stateKey, NOT key, to avoid shadowing the inherited Widget.key field. The plan flagged the conflict and offered two workarounds (rename or accept it as super.key passthrough); we picked the cleaner rename per the plan's GREEN-step note."
  - "Tooltip's richMessage:WidgetSpan(child: _SensorTooltipContent) is what implicitly enforces subscribe-on-open / cancel-on-close. Flutter's overlay mounts the WidgetSpan child on tooltip open and unmounts on dismiss; the StreamBuilder inside _DelayRow is created with the subscriber widget's lifetime so cancellation is automatic. No explicit subscription bookkeeping (no StreamSubscription field, no dispose()) is needed."
  - "Empty stateKey short-circuits inside _DelayRow.build BEFORE creating any stream — this means a sensor with risingEdgeDelayKey:'' and fallingEdgeDelayKey:'' opens its tooltip without making ANY network calls (just renders two em-dash rows). The lifecycle benefit only matters for non-empty keys; this guard makes it a cleaner contract."
  - "DynamicValue.asInt is used (not asNum / asDouble) because edge-delay PLC values are integer milliseconds in this domain. The StreamBuilder type is Stream<num> for permissive forward-compat if a future delay value becomes float."
  - "Lifecycle tests use the rendered text presence/absence as the unmount proof (find.text('Rising: —')) rather than referencing a private widget type (the plan's _SensorTooltipContentSentinel placeholder). This avoids cross-library private-type access entirely — Dart's library privacy rules block dynamic access to _-prefixed members from a test file."

patterns-established:
  - "TDD cadence preserved across 5 commits: test → feat (Cycle A — Label golden), test → feat (Cycle B — Tooltip), test (Cycle B regression guard). All commits match (test|feat)\\(01-04\\)."
  - "Tooltip-content widget pattern for state subscriptions whose lifetime should be bounded by hover/longpress: use Tooltip(richMessage: WidgetSpan(child: ConsumerWidget(StreamBuilder)))"
  - "Per-row short-circuit for unconfigured state keys: skip subscription entirely when key.isEmpty — avoids creating a no-op monitored item just to render an em-dash"

requirements-completed:
  - SENS-09   # Configurable rising-edge delay key — flows into _SensorTooltipContent via config.risingEdgeDelayKey, surfaced as 'Rising: <ms>ms' / 'Rising: —' / 'Rising: …'. (The dialog-side config UI lands in Plan 05.)
  - SENS-10   # Configurable falling-edge delay key — same wiring as SENS-09 via config.fallingEdgeDelayKey
  - SENS-11   # Tooltip surfaces rising/falling delays — locked copy contract honoured (Detection key not set / Rising: <ms>ms / Falling: <ms>ms / em-dash + ellipsis fallback)
  - SENS-13   # Per-sensor tag — config.tag flows through _createPainter as label: label; _paintLabel renders it below the glyph; tenth golden red_light_with_label locks the visual
  - QUAL-08   # TDD cadence — 5 commits matching (test|feat)\\(01-04\\): RED→GREEN, RED→GREEN, RED-only regression guard

requirements-deferred:
  # Plan 05: dialog editor body adds the actual KeyField widgets that let
  # operators TYPE the rising/falling/detection key strings. Plan 04 only
  # closes the data-flow + tooltip side of SENS-09 / SENS-10.

# Metrics
metrics:
  duration: ~25 min
  completed: 2026-05-05
  tasks_completed: 5
  task_commits: 5  # cc733bf test, e7808a9 feat, a8875b1 test, b506a1a feat, 060cfaa test (+ 1 chore prereq seed)
  test_count_added: 8  # +2 Tag pass-through, +1 Tooltip presence, +3 Tooltip content, +2 Tooltip subscription lifecycle (= 8 widget tests). +1 painter golden test ('red_light_with_label')
  files_added: 2   # red_light_with_label.png + 01-04-SUMMARY.md
  files_modified: 3  # sensor.dart, sensor_painter_test.dart, sensor_widget_test.dart
---

# Phase 01 Plan 04: Tooltip + label/tag Summary

**One-liner:** Wired SENS-13 per-sensor tag through the painter and locked it with a tenth golden; wrapped the Sensor's GestureDetector in a Material Tooltip with a richMessage WidgetSpan carrying _SensorTooltipContent (rising/falling edge-delay readout) — subscribe-on-open / cancel-on-close lifecycle satisfied implicitly by the WidgetSpan-child mount cycle, regression-guarded by two lifecycle tests.

## What was built

**Cycle A — Label golden + tag pass-through (SENS-13).**

Plan 03 already passed `widget.config.tag` through `_createPainter` to all three painter constructors as `label:`. This plan refactors that switch to extract the local variable `final label = widget.config.tag;` (matching the plan's prescribed structure) and adds the missing tenth golden — `red_light_with_label.png` (256×128, isActive=true, label='PE-101A') — that proves the painter's existing `_paintLabel` helper renders the tag below the glyph in semibold inactiveColor without overlapping the dashed beam line. Two new widget tests in a fresh `Tag pass-through` group lock the wiring at the widget level: a non-null tag flows through to `painter.label`, and a null tag flows through unchanged as `null`.

**Cycle B — Tooltip + content + lifecycle (SENS-09 / SENS-10 / SENS-11).**

`_buildPaint` now wraps its existing `GestureDetector → LayoutRotatedBox → LayoutBuilder → CustomPaint` chain in a Material `Tooltip` whose `richMessage` is a `WidgetSpan(child: _SensorTooltipContent(config: widget.config))`. UI-SPEC §Tooltip trigger requires the Tooltip to be the OUTER widget (not inside the GestureDetector) so hover (desktop) and long-press (touch) fire the tooltip without consuming the tap.

`_SensorTooltipContent` is a `ConsumerWidget`. When `config.detectionKey.isEmpty` it short-circuits to a single `Text('Detection key not set')`. Otherwise it renders a min-height Column of two `_DelayRow` children — one for `risingEdgeDelayKey`, one for `fallingEdgeDelayKey` — with theme `bodySmall` text style.

`_DelayRow` is a `ConsumerWidget` parameterised by `String label` and `String stateKey`. The parameter is named `stateKey` (not `key`) to avoid shadowing `Widget.key`. When `stateKey.isEmpty` the row short-circuits to `Text('$label: —')` without subscribing to anything (no monitored item created for an unconfigured delay key). When configured, it builds a `StreamBuilder<num>` over `ref.read(stateManProvider.future).asStream().asyncExpand((sm) => sm.subscribe(stateKey).asStream()).asyncExpand((s) => s).map((dv) => dv.asInt)`. The builder renders:
- `Text('$label: …')` while `!snapshot.hasData` (configured key, no value yet)
- `Text('$label: ${snapshot.data}ms')` on data
- `Text('$label: —')` on `hasError` (em-dash fallback per copy contract)

The subscribe-on-open / cancel-on-close lifecycle is implicit: Flutter's `Tooltip` mounts the `WidgetSpan` child on overlay open and unmounts it on dismiss. The `StreamBuilder` inside `_DelayRow` is created with the subscriber widget's lifetime, so its underlying subscription is torn down automatically on tooltip dismiss — no `StreamSubscription` field, no `dispose()` plumbing. Two regression tests in `Tooltip subscription lifecycle` lock this:
- `Tooltip content is not mounted when tooltip is closed` — asserts `find.text('Detection key not set')` finds nothing on a Sensor with `detectionKey:''` before any long-press (the content widget is unmounted; its rendered text isn't in the tree).
- `Tooltip content unmounts when tooltip is dismissed` — long-presses to open, asserts `'Rising: —'` / `'Falling: —'` are visible, releases + pumps past the tooltip's auto-dismiss show-duration, asserts both lines are gone.

## Tests added (8 widget + 1 painter golden, 27 total)

| Group | Test | Asserts |
|-------|------|---------|
| (painter) Golden matrix | red_light_with_label | New 256×128 baseline with label='PE-101A', activeColor=Colors.green, isActive=true |
| Tag pass-through | config.tag is passed to painter as label | `(painter as RedLightBeamPainter).label == 'PE-101A'` |
| Tag pass-through | null tag flows through as null label | `(painter as RedLightBeamPainter).label == null` |
| Tooltip presence | Sensor widget tree contains a Tooltip ancestor of GestureDetector | `findsOneWidget` Tooltip; GestureDetector is descendant |
| Tooltip content (copy contract) | shows "Detection key not set" when detectionKey empty | long-press → `find.text('Detection key not set')` |
| Tooltip content (copy contract) | shows "Rising: —\nFalling: —" when both delay keys empty | long-press → both em-dash rows present |
| Tooltip content (copy contract) | shows "Rising: —" + "Falling: …" when rising empty / falling configured | long-press → em-dash + ellipsis pair |
| Tooltip subscription lifecycle | content is not mounted when tooltip is closed | `find.text('Detection key not set')` finds nothing pre-press |
| Tooltip subscription lifecycle | content unmounts when tooltip is dismissed | open → assert visible → release + pump 3s → assert gone |

73/73 sensor tests pass (51 painter+config baseline from Plans 01-01..02 + 13 widget tests from Plan 03 + 9 new from this plan). 134/134 across `test/page_creator/assets/`. `flutter analyze` reports zero issues.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Style] Doc-comment unintended-HTML lint on `<ms>` placeholder**
- **Found during:** Task 5 (`flutter analyze` sweep)
- **Issue:** `flutter analyze` flagged `unintended_html_in_doc_comment` on a `///` summary line that contained `"<ms>ms"` — Dartdoc would interpret `<ms>` as an HTML tag and silently drop it.
- **Fix:** Wrapped the format placeholders in backticks: `` `"Rising: <ms>ms"` `` instead of `"Rising: <ms>ms"`. Identical reading semantics, lint-clean.
- **Files modified:** `lib/page_creator/assets/sensor.dart`
- **Commit:** b506a1a (rolled into the same Tooltip-implementation commit; the analyze sweep ran inside the GREEN step before commit)

**2. [Rule 3 — Pattern variance] Plan acceptance grep `': —'` / `': …'` returned zero matches**
- **Found during:** Task 3 acceptance-criteria verification
- **Issue:** The plan's `<acceptance_criteria>` includes `grep -c "': —'"` ≥ 1 and `grep -c "': …'"` ≥ 1. My implementation uses idiomatic Dart string-template form `Text('$label: —')` / `Text('$label: —')` / `Text('$label: …')`, which matches `: —'` (with the closing quote) but not the literal `': —'` (with both opening and closing quotes around the dash).
- **Disposition:** Functional intent met. The locked copy contract (UI-SPEC §Copywriting) mandates the rendered text strings, not their source representation. The widget tests `find.text('Rising: —')`, `find.text('Falling: —')`, `find.text('Falling: …')` directly verify the rendered text matches the contract — covering exactly what the source-grep was meant to enforce. The variant grep `grep -c ": —'"` (closing quote after em-dash) returns 2 and `grep -c ": …'"` returns 1, confirming the strings are present in source.
- **No fix applied** — the source form is more idiomatic; the contract is enforced through behaviour rather than source pattern.
- **Files modified:** none
- **Commit:** none (documented here for traceability)

## Cross-plan sequencing

This plan landed on a worktree seeded from `main` at `7155ec8` (Plan 03 merge). The chore commit `2ed61a8` ("seed worktree with prerequisites") brought in the `.planning/`, `CLAUDE.md`, the sensor source files (`sensor.dart`, `sensor.g.dart`, `sensor_painter.dart`), and the existing test files + golden baselines from Plans 01-01..03. Without this seed the `_buildPaint` Tooltip wrapper would have nothing to wrap, the painters wouldn't have a `label` parameter, and the test infrastructure would be missing 51 baseline tests.

Plan 05 (dialog + registry) is the natural successor — it will add the `KeyField` rows that let operators TYPE the `risingEdgeDelayKey` / `fallingEdgeDelayKey` strings whose data is now plumbed through the tooltip.

## Threat-Model coverage

| Threat ID | Disposition | Mitigation in this plan |
|-----------|-------------|--------------------------|
| T-01-10 | accept | Tooltip-open is a deliberate operator action (long-press / hover) — rate-limited by physical interaction. Each open → close cycle pairs `subscribe()` and stream cancellation; no idle subscription cost. Empty-stateKey short-circuit ensures unconfigured rows make zero network calls. |
| T-01-11 | accept | Display-only — no PII concern in HMI domain. Tooltip surfaces operator-typed `tag` and resolved delay values that are already visible in the (Plan 05) config dialog. |
| T-01-12 | mitigate | StreamBuilder's `snapshot.hasError` path renders the em-dash fallback instead of crashing on a malformed `DynamicValue`. Covered structurally by the locked copy contract: the same em-dash that means "unconfigured" also means "errored", a fail-closed default that is operator-visible. The Tooltip-content tests don't simulate a real error (no provider override pumps one), but the code path is grep-trivial and the `dv.asInt` getter from `open62541_dart/dynamic_value.dart` returns 0 on parse failure rather than throwing — so the practical attack surface here is "operator sees `0ms`" instead of an em-dash, which is a degraded read, not a crash. |

## Deferred to later plans

- **Plan 05:** real config-dialog editor body (KeyField inputs for the three keys, polarity switch, colour pickers, tag TextFormField), AssetRegistry registration, JSON round-trip integration test.

## Self-Check: PASSED

- [x] `lib/page_creator/assets/sensor.dart` — modified (FOUND)
- [x] `test/page_creator/assets/sensor_painter_test.dart` — modified (FOUND)
- [x] `test/page_creator/assets/sensor_widget_test.dart` — modified (FOUND)
- [x] `test/page_creator/assets/goldens/sensor/red_light_with_label.png` — created (FOUND, 3.3 KB)
- [x] Commit cc733bf (test 01-04 RED label golden) — FOUND
- [x] Commit e7808a9 (feat 01-04 GREEN tag wiring + golden) — FOUND
- [x] Commit a8875b1 (test 01-04 RED tooltip presence + content) — FOUND
- [x] Commit b506a1a (feat 01-04 GREEN tooltip + _SensorTooltipContent) — FOUND
- [x] Commit 060cfaa (test 01-04 RED→GREEN tooltip subscription lifecycle) — FOUND
- [x] All 73 sensor tests pass; 134/134 across `test/page_creator/assets/`
- [x] 5-run determinism sweep on painter tests: all 5 runs PASS
- [x] `flutter analyze lib/page_creator/assets/sensor.dart lib/page_creator/assets/sensor_painter.dart test/page_creator/assets/sensor_widget_test.dart test/page_creator/assets/sensor_painter_test.dart` — zero issues
- [x] `grep -c "Tooltip(" lib/page_creator/assets/sensor.dart` returns 1
- [x] `grep -c "richMessage:" lib/page_creator/assets/sensor.dart` returns 1
- [x] `grep -c "class _SensorTooltipContent" lib/page_creator/assets/sensor.dart` returns 1
- [x] `grep -c "class _DelayRow" lib/page_creator/assets/sensor.dart` returns 1
- [x] `grep -c "'Detection key not set'" lib/page_creator/assets/sensor.dart` returns 1
- [x] `grep -c "red_light_with_label" test/page_creator/assets/sensor_painter_test.dart` returns 2 (test name + matchesGoldenFile call)
- [x] `grep -cE "label: label," lib/page_creator/assets/sensor.dart` returns 3 (one per painter constructor in the switch)
