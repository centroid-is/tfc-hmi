---
phase: 260511-ehy
plan: 01
type: tdd
wave: 1
depends_on: []
files_modified:
  - lib/page_creator/assets/elevator.dart
  - lib/page_creator/assets/elevator.g.dart
  - test/page_creator/assets/elevator_config_test.dart
  - test/page_creator/assets/elevator_widget_test.dart
autonomous: false
requirements: [ELEV-CHILD-OFFSET-Y]
tags: [elevator, child-layout, schema, codegen]

must_haves:
  truths:
    - "ElevatorChildEntry carries a double offsetY field defaulting to 0.0"
    - "offsetY round-trips through toJson/fromJson preserving its value"
    - "Legacy JSON without an offsetY key restores to offsetY = 0.0 (back-compat)"
    - "Child Positioned.top = platformY - childH * (1 + offsetY) at runtime"
    - "offsetY = 0 produces identical layout to the pre-change behavior (regression guard)"
    - "Positive offsetY raises the child (smaller top); negative offsetY lowers it (larger top)"
    - "Editor exposes a second slider per child (range -1.0..1.0) that mutates entry.offsetY"
    - "All existing elevator tests (JSON + widget + painter goldens) continue to pass unchanged"
    - "flutter analyze remains clean"
  artifacts:
    - path: "lib/page_creator/assets/elevator.dart"
      provides: "ElevatorChildEntry.offsetY field + Slider in _ElevatorConfigEditor + updated _buildPositionedChild formula"
      contains: "offsetY"
    - path: "lib/page_creator/assets/elevator.g.dart"
      provides: "Regenerated _$ElevatorChildEntryFromJson / _$ElevatorChildEntryToJson with offsetY field"
      contains: "offsetY"
    - path: "test/page_creator/assets/elevator_config_test.dart"
      provides: "ElevatorChildEntry offsetY default + round-trip + legacy-omit tests"
      contains: "offsetY"
    - path: "test/page_creator/assets/elevator_widget_test.dart"
      provides: "OffsetY anchor widget tests + editor slider smoke"
      contains: "OffsetY anchor (260511-ehy)"
  key_links:
    - from: "lib/page_creator/assets/elevator.dart::_buildPositionedChild"
      to: "Positioned.top"
      via: "anchor-offset formula"
      pattern: "platformY - childH \\* \\(1\\.0 \\+ entry\\.offsetY\\)"
    - from: "lib/page_creator/assets/elevator.dart::ElevatorChildEntry"
      to: "JSON"
      via: "@JsonKey default for legacy round-trip"
      pattern: "@JsonKey\\(defaultValue: 0\\.0\\)"
    - from: "lib/page_creator/assets/elevator.dart::_ElevatorConfigEditor"
      to: "entry.offsetY"
      via: "Slider with range -1.0..1.0 and setState mutation"
      pattern: "min: -1\\.0"
---

<objective>
Add an `offsetY` field to `ElevatorChildEntry` so an operator can raise (+) or lower (-) a child relative to the platform top. Default `0.0` preserves the current bottom-on-platform behavior. The child still rides the platform — `offsetY` only shifts the anchor.

Purpose: Operators can place a sensor BELOW the platform (e.g. an arrival sensor) or a label/indicator ABOVE the cargo without moving the underlying platform. Mirrors the existing dimensionless `offsetX` idiom but spans -1..+1 because vertical lifts and drops are both useful.

Output:
- `ElevatorChildEntry.offsetY` (double, default 0.0) with `@JsonKey(defaultValue: 0.0)` so legacy saved pages restore cleanly.
- `_buildPositionedChild` formula updated from `top = platformY - childH` → `top = platformY - childH * (1.0 + entry.offsetY)`.
- A second Slider per child in `_ElevatorConfigEditor` (range -1.0..1.0, divisions 200) directly below the existing offsetX slider.
- `elevator.g.dart` regenerated via build_runner so `_$ElevatorChildEntryFromJson` / `_$ElevatorChildEntryToJson` carry the new field.
- TDD-discipline tests covering: default, round-trip, legacy-omit back-compat, three widget geometry checks (offsetY=0/+0.5/-0.5), and an editor slider smoke.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@.planning/quick/260511-ehy-elevator-child-y-axis-anchor-offset-offs/260511-ehy-PROBLEM.md
</context>

<interfaces>
<!-- Key contracts the executor needs. Extracted from current HEAD. -->
<!-- Do NOT re-explore the codebase — the relevant shape is already here. -->

From `lib/page_creator/assets/elevator.dart` (post-260511-dxa HEAD):

```dart
@JsonSerializable(explicitToJson: true)
class ElevatorChildEntry {
  String id;

  /// Lateral position on the platform (0.0 = far left, 1.0 = far right). Default 0.5.
  double offsetX;

  @JsonKey(fromJson: _childFromJson, toJson: _childToJson)
  BaseAsset child;

  ElevatorChildEntry({
    String? id,
    this.offsetX = 0.5,
    required this.child,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  factory ElevatorChildEntry.fromJson(Map<String, dynamic> json) =>
      _$ElevatorChildEntryFromJson(json);
  Map<String, dynamic> toJson() => _$ElevatorChildEntryToJson(this);
}
```

The runtime composition (`_buildPositionedChild`, lines ~722–769):

```dart
Widget _buildPositionedChild(
  ElevatorChildEntry entry,
  Size paintSize,
  double platformH,
  double maxChildHeight,
) {
  final intrinsic = entry.child.size.toSize(paintSize);
  final childW = intrinsic.width <= 0 ? paintSize.shortestSide / 4 : intrinsic.width;
  final childH = intrinsic.height <= 0 ? paintSize.shortestSide / 4 : intrinsic.height;
  final left = entry.offsetX * paintSize.width - childW / 2;
  return ValueListenableBuilder<double>(
    valueListenable: _animProgress,
    child: KeyedSubtree(
      key: ValueKey<String>(entry.id),
      child: SizedBox(width: childW, height: childH, child: entry.child.build(context)),
    ),
    builder: (ctx, animProgress, builtChild) {
      final platformY = platformOffsetTop(animProgress, paintSize.height, platformH, maxChildHeight);
      // CURRENT: final top = platformY - childH;
      // NEW:     final top = platformY - childH * (1.0 + entry.offsetY);
      final top = platformY - childH;
      return Positioned(left: left, top: top, width: childW, height: childH, child: builtChild!);
    },
  );
}
```

Editor offsetX slider (lib/page_creator/assets/elevator.dart lines ~1165–1178):

```dart
Text(
  'Lateral position: ${(entry.offsetX * 100).round()}%',
  style: Theme.of(context).textTheme.bodySmall,
),
Slider(
  min: 0.0,
  max: 1.0,
  divisions: 100,
  value: entry.offsetX,
  label: '${(entry.offsetX * 100).round()}%',
  onChanged: (v) => setState(() => entry.offsetX = v),
),
```

`platformOffsetTop` signature (from `lib/page_creator/assets/elevator_layout.dart`):
```dart
double platformOffsetTop(double progress, double bboxH, double platformH, double maxChildHeight);
```

Test fixture from `elevator_widget_test.dart`:
- `wrap(...)` wraps the elevator in a `SizedBox(width: 200, height: 300)` (so paintSize = 200x300).
- `kPlatformHeightFraction = 0.08` → platformH = 24 inside a 300-tall bbox.
- `_FixedSizeChildConfig(width: 40, height: 40)` is the canonical single-child fixture.
- The state's `debugProgress` test seam is used to drive progress directly.
</interfaces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add offsetY to ElevatorChildEntry — schema, widget formula, editor slider</name>
  <files>
    lib/page_creator/assets/elevator.dart,
    lib/page_creator/assets/elevator.g.dart,
    test/page_creator/assets/elevator_config_test.dart,
    test/page_creator/assets/elevator_widget_test.dart
  </files>
  <behavior>
    Schema (elevator_config_test.dart — extends the existing `ElevatorChildEntry shape` and `Polymorphic child round-trip` groups):
    - Test A1: `ElevatorChildEntry(child: SensorConfig.preview()).offsetY` equals `0.0` (default).
    - Test A2: Constructing with `offsetY: 0.7` preserves the value on the instance.
    - Test A3: Round-trip — `ElevatorChildEntry(id: 'fixed-y', offsetX: 0.25, offsetY: 0.7, child: SensorConfig(detectionKey: '/k')).toJson()` → fromJson → toJson is deep-equal AND `restored.offsetY == 0.7`.
    - Test A4: Back-compat — `ElevatorChildEntry.fromJson({'id': 'legacy', 'offsetX': 0.5, 'child': SensorConfig.preview().toJson()})` (no `offsetY` key) produces an entry with `offsetY == 0.0` AND a subsequent toJson emits `offsetY: 0.0`.

    Widget geometry (elevator_widget_test.dart — new group `'OffsetY anchor (260511-ehy)'` placed AFTER the `'Children riding the platform (Phase 3)'` group, before the editor groups):
    Use the same `wrap(...)` (200x300 bbox), same `_FixedSizeChildConfig(width: 40, height: 40)` fixture, and the same `debugProgress` test seam. Constants:
      `const bboxH = 300.0;`
      `const platformH = bboxH * kPlatformHeightFraction;`  // 24
      `const childH = 40.0;`
      `const maxChildHeight = 40.0;`
    All assertions use `closeTo(..., 1.0)` (matches the precedent at line 675).

    - Test W1 ('offsetY = 0 produces top = platformY - childH (regression guard)'):
        single child with `offsetY: 0.0`, drive progress to 0.5, settle, read Positioned.top.
        Expected: `platformOffsetTop(0.5, bboxH, platformH, maxChildHeight) - childH`.

    - Test W2 ('offsetY = 0.5 raises the child by half a child height'):
        single child with `offsetY: 0.5`, drive progress to 0.0, settle.
        Expected: `platformOffsetTop(0.0, bboxH, platformH, maxChildHeight) - childH * 1.5`.
        Assert top is LESS than the offsetY=0 baseline (child rises).

    - Test W3 ('offsetY = -0.5 lowers the child by half a child height'):
        single child with `offsetY: -0.5`, drive progress to 0.0, settle.
        Expected: `platformOffsetTop(0.0, bboxH, platformH, maxChildHeight) - childH * 0.5`.
        Assert top is GREATER than the offsetY=0 baseline (child's bottom hangs below platform).

    Editor smoke (elevator_widget_test.dart — placed inside the existing `'Editor — child management (ELEV-07, ELEV-08)'` group, after the existing offsetX slider test at line 885):
    - Test E1 ('offsetY Slider mutates entry.offsetY in real time'):
        Use `openConfigEditor` with a single sensor child (offsetX: 0.5, offsetY: 0.0).
        Find the SECOND Slider in the editor (the per-entry sliders are ordered offsetX then offsetY).
        `ensureVisible` + `pumpAndSettle` then `drag(slider, const Offset(50, 0))` and `pump()`.
        Assert `config.children[0].offsetY != 0.0` AND `config.children[0].offsetY > 0.0`.
        Locator: `find.byType(Slider).at(1)` (entry 0 = offsetX, entry 1 = offsetY).

    RED-state expectation: tests A2–A4, W1–W3, E1 must FAIL with the current code (A2/A3/A4: no offsetY field; W1: passes incidentally — keep it as a regression guard; W2/W3: top mismatches; E1: only one slider exists).
  </behavior>
  <action>
    Follow strict RED → GREEN → REFACTOR.

    --- RED ---
    1. Add Test A1 (offsetY default) in `elevator_config_test.dart`, group `'ElevatorChildEntry shape'`, right after the existing 'default offsetX is 0.5' test. This test PASSES today only after the field exists, but write it now.
    2. Add Tests A2 (preserves value), A3 (round-trip), A4 (legacy-omit back-compat) — A2 inside `'ElevatorChildEntry shape'`, A3 + A4 inside `'Polymorphic child round-trip'`.
    3. Add the new `'OffsetY anchor (260511-ehy)'` group in `elevator_widget_test.dart` between the existing `'Children riding the platform (Phase 3)'` group's closing `});` and the comment banner introducing `'Editor — child management (ELEV-07, ELEV-08)'`. Three testWidgets per the §behavior block above.
    4. Add Test E1 inside the editor group, immediately after the existing offsetX Slider test.
    5. Run `flutter test test/page_creator/assets/elevator_config_test.dart test/page_creator/assets/elevator_widget_test.dart` and CONFIRM the new tests fail (A1 fails because the field doesn't exist yet; W2/W3 fail with geometry mismatch; E1 fails because only one slider exists). Commit: `test(260511-ehy): RED — offsetY field + anchor formula + editor slider`.

    --- GREEN ---
    6. Edit `lib/page_creator/assets/elevator.dart`:
       a. Add `double offsetY;` field to `ElevatorChildEntry` immediately after `offsetX` (around line 103). Add a `///` doc comment: "Anchor offset along Y (units of child height): -1.0..+1.0. Default 0.0 = bottom-on-platform. Positive raises the child above the platform; negative lowers it below. Unclamped — Stack(Clip.none) handles overhang."
       b. Annotate the field with `@JsonKey(defaultValue: 0.0)` so legacy JSON round-trips.
       c. Add `this.offsetY = 0.0,` to the constructor parameter list, placed after `this.offsetX = 0.5,`.
       d. In `_buildPositionedChild` (around line 759), replace `final top = platformY - childH;` with `final top = platformY - childH * (1.0 + entry.offsetY);`. Update the comment block immediately above the line to: "Anchor offset (260511-ehy): `top = platformY - childH * (1 + offsetY)`. offsetY = 0 keeps bottom-on-platform (Plan 260511-dxa invariant). Positive offsetY raises the child; negative lowers it. Unclamped — Stack(clipBehavior: Clip.none) tolerates overhang per Pitfall 7."
       e. In `_ElevatorConfigEditorState.build`, locate the existing offsetX Text + Slider pair (lines ~1166–1178) and append immediately after the Slider, before the closing `],` of the Card's inner Column:
          ```dart
          Text(
            'Vertical offset: ${(entry.offsetY * 100).round()}% of child height',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Slider(
            min: -1.0,
            max: 1.0,
            divisions: 200,
            value: entry.offsetY,
            label: 'Vertical offset: ${(entry.offsetY * 100).round()}%',
            onChanged: (v) => setState(() => entry.offsetY = v),
          ),
          ```
    7. Run codegen: `dart run build_runner build --delete-conflicting-outputs`.
    8. Run `flutter test test/page_creator/assets/elevator_config_test.dart test/page_creator/assets/elevator_widget_test.dart` and CONFIRM all new tests pass. Then run `flutter test test/page_creator/assets/elevator_painter_test.dart test/page_creator/assets/elevator_layout_test.dart test/page_creator/assets/elevator_config_test.dart test/page_creator/assets/elevator_widget_test.dart` (no `--update-goldens`) to confirm the existing painter goldens and other locked tests still pass — they MUST be untouched since offsetY=0 preserves all geometry.
    9. Run `flutter analyze` — must report 0 issues introduced by this change.
    10. Commit: `feat(260511-ehy): add offsetY anchor offset to ElevatorChildEntry`.

    --- REFACTOR (only if needed) ---
    11. Tidy: align doc comments, condense the offsetY label string if duplication with the slider `label:` reads awkwardly. If no refactor is needed, skip the commit entirely (per TDD discipline — no empty refactor commits).
  </action>
  <verify>
    <automated>flutter test test/page_creator/assets/elevator_config_test.dart test/page_creator/assets/elevator_widget_test.dart test/page_creator/assets/elevator_painter_test.dart test/page_creator/assets/elevator_layout_test.dart && flutter analyze lib/page_creator/assets/elevator.dart lib/page_creator/assets/elevator.g.dart</automated>
  </verify>
  <done>
    - `ElevatorChildEntry.offsetY` field exists with default 0.0 and `@JsonKey(defaultValue: 0.0)`.
    - `elevator.g.dart` regenerated; from/toJson include the offsetY field.
    - `_buildPositionedChild` uses the new formula `top = platformY - childH * (1.0 + entry.offsetY)`.
    - Editor renders a second slider (min: -1.0, max: 1.0) per child.
    - All four new schema tests + three new widget tests + one new editor test PASS.
    - All pre-existing elevator tests (~63 widget + JSON + painter goldens) PASS unchanged.
    - `flutter analyze` reports 0 new issues.
    - Three commits exist: RED → feat (GREEN) → optional refactor.
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <what-built>
    `offsetY` field on `ElevatorChildEntry` with editor slider (range -1.0..1.0, 0.01 step). Default 0.0 preserves all current behavior. Positive lifts the child above the platform; negative drops the child below.
  </what-built>
  <how-to-verify>
    1. `flutter run -d macos` (or your default device).
    2. Open the page editor (TFC_GOD must be set).
    3. Drag an Elevator onto a page. Open its config dialog. Add a Sensor child (offsetX = 0.5, offsetY = 0 by default).
    4. Confirm a new slider labelled "Vertical offset: 0% of child height" appears directly below the existing "Lateral position" slider.
    5. With Simulate motion ON, drag the offsetY slider:
       - To +0.5 → the sensor visibly rises ABOVE the platform top by half its height across the entire 0→100% sweep.
       - To +1.0 → the sensor sits one full sensor-height above the platform.
       - To -0.5 → the sensor's TOP edge sits on the platform; its bottom hangs below.
       - To -1.0 → the entire sensor is below the platform.
       - To 0.0 → the sensor's bottom sits exactly on the platform (current behavior).
    6. Save the page. Quit. Reopen. Confirm the offsetY value is preserved (JSON round-trip).
    7. Open a previously-saved page that contains an elevator with children but was saved BEFORE this change (if available). Confirm:
       - Page loads cleanly (no errors).
       - Children sit on the platform exactly as before (offsetY defaults to 0).
  </how-to-verify>
  <resume-signal>Type "approved" or describe any visual issues for triage.</resume-signal>
</task>

</tasks>

<verification>
- All new + existing elevator tests pass: `flutter test test/page_creator/assets/elevator_*`
- `flutter analyze` clean.
- Manual smoke (above) confirms the slider, geometry, and back-compat at the runtime layer.
</verification>

<success_criteria>
- A child placed on an elevator can be raised or lowered relative to the platform top via a per-child slider, with the value persisting through save / load.
- Legacy saved pages (no offsetY key) load unchanged and render identically to the pre-change behavior.
- No regressions in existing elevator behavior — all painter goldens, multi-elevator independence, leak test, simulate toggle, and Pitfall 1/2 lifecycle tests continue to pass.
</success_criteria>

<output>
After completion, create `.planning/quick/260511-ehy-elevator-child-y-axis-anchor-offset-offs/260511-ehy-SUMMARY.md` summarising:
- Field added + JSON shape change.
- Three commits (RED / feat / optional refactor).
- Test counts (new + total elevator tests passing).
- Manual smoke status.
</output>
