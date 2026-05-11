---
phase: 260511-dxa
plan: 01
type: tdd
wave: 1
depends_on: []
files_modified:
  - lib/page_creator/assets/elevator_layout.dart
  - lib/page_creator/assets/elevator_painter.dart
  - lib/page_creator/assets/elevator.dart
  - test/page_creator/assets/elevator_layout_test.dart
  - test/page_creator/assets/elevator_widget_test.dart
  - test/page_creator/assets/elevator_painter_test.dart
  - test/page_creator/assets/goldens/elevator/position_0.png
  - test/page_creator/assets/goldens/elevator/position_50.png
  - test/page_creator/assets/goldens/elevator/position_100.png
autonomous: false
requirements: [ELEV-10]
tags: [elevator, layout, painter, golden]

must_haves:
  truths:
    - "Platform travel range equals tallest child's height when children exist"
    - "Platform travel range is 0 when no children exist (pinned at bottom)"
    - "Platform travel range clamps to (bbox - platformH) when tallest child exceeds available headroom"
    - "Child Positioned.top is never clamped (formula: platformY - childH) and remains >= 0 by construction"
    - "Painter renders platform at the bottom for all progress values when maxChildHeight=0"
    - "Existing widget tests (Pitfall 1, Pitfall 2, allKeys, out-of-range, multi-elevator, leak, simulate) pass unchanged"
    - "flutter analyze remains clean"
  artifacts:
    - path: "lib/page_creator/assets/elevator_layout.dart"
      provides: "platformOffsetTop with maxChildHeight parameter"
      contains: "maxChildHeight"
    - path: "lib/page_creator/assets/elevator_painter.dart"
      provides: "ElevatorPainter with maxChildHeight field"
      contains: "maxChildHeight"
    - path: "lib/page_creator/assets/elevator.dart"
      provides: "_buildStack computes maxChildHeight once; _buildPositionedChild uses unclamped top"
      contains: "maxChildHeight"
    - path: "test/page_creator/assets/elevator_layout_test.dart"
      provides: "Updated platformOffsetTop tests covering 4 new travel-range cases"
    - path: "test/page_creator/assets/elevator_widget_test.dart"
      provides: "Updated child-top assertions with recomputed expected positions"
    - path: "test/page_creator/assets/goldens/elevator/position_0.png"
      provides: "Regenerated golden reflecting new travel range"
    - path: "test/page_creator/assets/goldens/elevator/position_50.png"
      provides: "Regenerated golden reflecting new travel range"
    - path: "test/page_creator/assets/goldens/elevator/position_100.png"
      provides: "Regenerated golden reflecting new travel range"
  key_links:
    - from: "lib/page_creator/assets/elevator.dart::_buildStack"
      to: "platformOffsetTop"
      via: "passes computed maxChildHeight"
      pattern: "platformOffsetTop\\(.*maxChildHeight"
    - from: "lib/page_creator/assets/elevator_painter.dart::paint"
      to: "platformOffsetTop"
      via: "passes maxChildHeight field"
      pattern: "platformOffsetTop\\(.*maxChildHeight"
    - from: "lib/page_creator/assets/elevator.dart::_buildPositionedChild"
      to: "Positioned.top"
      via: "unclamped formula: platformY - childH"
      pattern: "top = platformY - childH"
---

<objective>
Change the elevator's platform travel range from `bboxHeight - platformHeight` to the tallest child's height (clamped to available headroom). This removes the defensive `max(0.0, ...)` clamp on the child's `Positioned.top` that pinned children to the top of the bbox at high progress — making them appear frozen.

Purpose: Operators see children ride the platform smoothly across the entire 0–100% cycle without visual freezing. Closes the residual UX issue from Plan 04-02 (which introduced the clamp as a defensive measure rather than fixing the underlying range).

Output:
- `platformOffsetTop` signature accepts `maxChildHeight` and computes `(bboxHeight - platformHeight) - progress * clamp(maxChildHeight, 0, bboxHeight - platformHeight)` (formula derived in §Geometry below — this is the closed form that gives the locked semantics at progress=0 and progress=1).
- `ElevatorPainter` accepts `maxChildHeight` as a field; `shouldRepaint` recognises changes.
- `Elevator._buildStack` computes `maxChildHeight` once per build by reducing children's intrinsic heights with `max` (zero-fallback for empty list).
- `Elevator._buildPositionedChild` uses the unclamped formula `top = platformY - childH` (clamp becomes a no-op because the range is now sized correctly).
- Tests updated for the new contract; 3 painter goldens regenerated.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@lib/page_creator/assets/elevator_layout.dart
@lib/page_creator/assets/elevator_painter.dart
@lib/page_creator/assets/elevator.dart
@test/page_creator/assets/elevator_layout_test.dart
@test/page_creator/assets/elevator_painter_test.dart

# Geometry derivation (locked)
#
# Current formula:
#   platformY = (1 - progress) * (bboxH - platformH)
#   range = bboxH - platformH (always)
#
# New formula:
#   effectiveTravel = min(maxChildHeight, bboxH - platformH)   # clamp to headroom
#   effectiveTravel = max(0, effectiveTravel)                  # clamp to >= 0
#   platformY = (bboxH - platformH) - progress * effectiveTravel
#
# Sanity check (bboxH=200, platformH=10, tallest child H=40):
#   progress=0: platformY = 190 - 0 = 190 (bottom)               OK
#   progress=1: platformY = 190 - 40 = 150 (top - travel of 40)  OK
#   child.top at progress=1: 150 - 40 = 110 (well inside bbox)   OK
#
# No-children case (maxChildHeight=0):
#   platformY = (bboxH - platformH) for all progress             OK pinned at bottom
#
# Oversized-child case (maxChildHeight > bboxH - platformH):
#   clamped to (bboxH - platformH), restoring original behaviour OK
#
# Backwards-compatible default: maxChildHeight=0 in the painter ctor preserves
# old behaviour for any direct painter use (e.g., existing goldens that don't
# pass maxChildHeight).

<interfaces>
<!-- Key signatures the executor will modify. -->

From lib/page_creator/assets/elevator_layout.dart (NEW signature):
```dart
double platformOffsetTop(
  double progress,
  double bboxHeight,
  double platformHeight,
  double maxChildHeight,  // NEW — clamped internally to [0, bboxHeight - platformHeight]
);
```

From lib/page_creator/assets/elevator_painter.dart (NEW field):
```dart
class ElevatorPainter extends CustomPainter {
  final ValueListenable<double> progress;
  final bool isStale;
  final bool isOutOfRange;
  final Color activeColor;
  final double maxChildHeight;  // NEW — default 0.0 (no travel when no children)
  // ...
}
```

From lib/page_creator/assets/elevator.dart::_buildStack (NEW local):
```dart
// Pseudocode — compute once per build:
final maxChildHeight = config.children.isEmpty
    ? 0.0
    : config.children.map((e) {
        final s = e.child.size.toSize(paintSize);
        return s.height <= 0 ? paintSize.shortestSide / 4 : s.height;
      }).reduce(max);
```

From lib/page_creator/assets/elevator.dart::_buildPositionedChild (CHANGED line):
```dart
// OLD: final top = max(0.0, platformY - childH);
// NEW: final top = platformY - childH;  // unclamped — range now guarantees top >= 0
```
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: RED — update layout helper tests and add new travel-range cases</name>
  <files>test/page_creator/assets/elevator_layout_test.dart</files>
  <behavior>
    Update existing `platformOffsetTop` tests to pass a 4th argument
    (`maxChildHeight`). For the existing 8 cases, pass `maxChildHeight =
    bboxHeight - platformHeight` so the *old* behaviour is preserved (travel
    equals full headroom). Then add new tests covering the locked semantics:

    - `'no children (maxChildHeight=0) -> platform pinned at bottom for progress=0'`:
      `platformOffsetTop(0.0, 200.0, 10.0, 0.0)` == 190.0
    - `'no children (maxChildHeight=0) -> platform pinned at bottom for progress=0.5'`:
      `platformOffsetTop(0.5, 200.0, 10.0, 0.0)` == 190.0
    - `'no children (maxChildHeight=0) -> platform pinned at bottom for progress=1.0'`:
      `platformOffsetTop(1.0, 200.0, 10.0, 0.0)` == 190.0
    - `'tallest child smaller than headroom -> travel equals childHeight'`:
      `platformOffsetTop(1.0, 200.0, 10.0, 40.0)` == 150.0 (190 - 40)
    - `'tallest child smaller than headroom at progress=0.5 -> half-travel'`:
      `platformOffsetTop(0.5, 200.0, 10.0, 40.0)` == 170.0 (190 - 20)
    - `'tallest child equals headroom -> full original behaviour at progress=1'`:
      `platformOffsetTop(1.0, 200.0, 10.0, 190.0)` == 0.0
    - `'tallest child exceeds headroom -> clamps to headroom at progress=1'`:
      `platformOffsetTop(1.0, 200.0, 10.0, 500.0)` == 0.0
    - `'tallest child exceeds headroom -> clamps to headroom at progress=0.5'`:
      `platformOffsetTop(0.5, 200.0, 10.0, 500.0)` == 95.0 (190 - 95)
    - `'negative maxChildHeight -> clamps to 0 (defensive)'`:
      `platformOffsetTop(1.0, 200.0, 10.0, -5.0)` == 190.0

    Also keep the existing `platformProgress` test group untouched.

    Run the test — it MUST fail (current `platformOffsetTop` takes only 3
    args, so Dart will produce compile errors on every updated call site).
    This is the RED step.
  </behavior>
  <action>
    1. Open `test/page_creator/assets/elevator_layout_test.dart`.
    2. Update every existing `platformOffsetTop(...)` call inside the
       `'platformOffsetTop'` group to pass `maxChildHeight = bboxHeight -
       platformHeight` as the 4th argument. The existing expected values
       remain unchanged (because that range was the old behaviour).
       - For the two degenerate `'platform-fills-bbox'` cases (bbox=100,
         ph=100, headroom=0): pass `0.0` as the 4th arg. The expected `0.0`
         result stays correct.
    3. Append the 9 new tests listed in &lt;behavior&gt; above to the same
       `'platformOffsetTop'` group, each with a descriptive name making the
       locked semantics readable.
    4. Run `flutter test test/page_creator/assets/elevator_layout_test.dart`
       and capture the failure output. Confirm it's a *compile* failure on
       the new signature — that is the expected RED state.
    5. Commit with message:
       `test(260511-dxa): RED — platformOffsetTop accepts maxChildHeight (ELEV-10)`
  </action>
  <verify>
    <automated>flutter test test/page_creator/assets/elevator_layout_test.dart 2>&amp;1 | grep -E "(error|FAILED|compilation)" | head -5</automated>
  </verify>
  <done>
    Test file updated, RED commit lands. `flutter test` on
    `elevator_layout_test.dart` fails with a compile error referencing the
    `maxChildHeight` parameter (proving the test asserts the new signature
    before implementation exists).
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: GREEN — implement travel range in helper, painter, and widget</name>
  <files>
    lib/page_creator/assets/elevator_layout.dart,
    lib/page_creator/assets/elevator_painter.dart,
    lib/page_creator/assets/elevator.dart,
    test/page_creator/assets/elevator_widget_test.dart
  </files>
  <behavior>
    After this task:
    - `flutter test test/page_creator/assets/elevator_layout_test.dart`
      passes (all old + 9 new cases).
    - `flutter test test/page_creator/assets/elevator_widget_test.dart`
      passes (recomputed child-top expectations + everything else unchanged).
    - `flutter analyze` clean (no unused imports — `max` was already imported
      in `elevator.dart` so this is a no-op; keep the import).

    Behavioural guarantees baked into the implementation:
    - `platformOffsetTop` with `maxChildHeight=0` keeps the platform at
      `bboxH - platformH` for all progress values.
    - `platformOffsetTop` with `maxChildHeight >= bboxH - platformH`
      reproduces the old full-range behaviour exactly.
    - In `_buildPositionedChild`, `top = platformY - childH` (no clamp).
      Because `maxChildHeight` is the max of all child heights, `platformY -
      childH >= platformY - maxChildHeight >= (bboxH - platformH) -
      maxChildHeight >= 0` — the invariant is structural.
  </behavior>
  <action>
    **Step 2a — implement helper (lib/page_creator/assets/elevator_layout.dart):**
    1. Change `platformOffsetTop` signature to:
       ```dart
       double platformOffsetTop(
         double progress,
         double bboxHeight,
         double platformHeight,
         double maxChildHeight,
       ) {
         final headroom = bboxHeight - platformHeight;
         final effectiveTravel = maxChildHeight.clamp(0.0, headroom);
         return headroom - progress * effectiveTravel;
       }
       ```
    2. Update the docstring to describe the new semantics: travel range now
       equals `maxChildHeight` (clamped to headroom). At `progress=0` the
       platform still sits at `bboxH - platformH`; at `progress=1` the
       platform sits at `(bboxH - platformH) - clamp(maxChildHeight, 0,
       headroom)`. Mention the no-children case (travel=0 → platform pinned).
       Link to ELEV-10 and this quick directory.

    **Step 2b — implement painter (lib/page_creator/assets/elevator_painter.dart):**
    1. Add field: `final double maxChildHeight;` with doc comment:
       ```
       /// Travel range driver — equals the tallest attached child's height
       /// (clamped to `bboxH - platformH` internally by [platformOffsetTop]).
       /// Defaults to 0.0: with no children, the platform stays at the
       /// bottom for all progress values. Set by [Elevator] from
       /// `config.children` once per build.
       ```
    2. Add `this.maxChildHeight = 0.0` to the constructor (default preserves
       no-children behaviour for direct painter callers, including older
       golden setups that don't pass it).
    3. In `paint()`, change the `platformOffsetTop` call to pass
       `maxChildHeight` as the 4th argument.
    4. In `shouldRepaint`, add `|| maxChildHeight != o.maxChildHeight`
       to the return expression.

    **Step 2c — implement widget (lib/page_creator/assets/elevator.dart):**
    1. In `_buildStack`, immediately after computing `platformH`, compute:
       ```dart
       final maxChildHeight = widget.config.children.isEmpty
           ? 0.0
           : widget.config.children.map((e) {
               final s = e.child.size.toSize(paintSize);
               return s.height &lt;= 0 ? paintSize.shortestSide / 4 : s.height;
             }).reduce(max);
       ```
       The fallback `paintSize.shortestSide / 4` mirrors the same fallback
       used in `_buildPositionedChild` (lines 715–721) — keeps the two
       formulas welded so the structural invariant `top >= 0` holds.
    2. Pass `maxChildHeight: maxChildHeight` to the `ElevatorPainter`
       constructor in `_buildStack`.
    3. Pass `maxChildHeight` as a new parameter to `_buildPositionedChild`
       and use it when calling `platformOffsetTop` (so the widget and
       painter share the same value).
    4. In `_buildPositionedChild`, change:
       ```dart
       final platformY =
           platformOffsetTop(animProgress, paintSize.height, platformH);
       // ...
       final top = max(0.0, platformY - childH);
       ```
       to:
       ```dart
       final platformY = platformOffsetTop(
         animProgress,
         paintSize.height,
         platformH,
         maxChildHeight,
       );
       // Unclamped: the travel range is sized to maxChildHeight so
       // (platformY - childH) is guaranteed >= 0 when childH &lt;= maxChildHeight.
       // For children shorter than maxChildHeight, the value sits comfortably
       // inside the bbox. See plan 260511-dxa for the derivation.
       final top = platformY - childH;
       ```
    5. Replace the multi-line comment block above the old clamp with a
       one-line comment pointing at the structural invariant (the long
       Plan 04-02 commentary about the safety clamp is now historical).

    **Step 2d — update widget tests (test/page_creator/assets/elevator_widget_test.dart):**
    1. In test `'children Positioned.top follows _animProgress (ELEV-10)'`
       (around line 621): update the local constants and expectations.
       - The fixture uses bbox 200x300, child 40x40. So `bboxH=300`,
         `platformH=24`, `childH=40`, `maxChildHeight=40`.
       - At progress=0: `platformY=276`, `top=276-40=236`.
       - At progress=1: `platformY=276-40=236`, `top=236-40=196`.
       - Replace the `max(0.0, ...)` expression with the direct formula:
         ```dart
         const bboxH = 300.0;
         const platformH = bboxH * kPlatformHeightFraction;
         const childH = 40.0;
         const maxChildHeight = childH; // single child
         final expectedTopAt0 = platformOffsetTop(0.0, bboxH, platformH, maxChildHeight) - childH;
         final expectedTopAt1 = platformOffsetTop(1.0, bboxH, platformH, maxChildHeight) - childH;
         ```
       - `closeTo(expectedTop*, 1.0)` tolerance stays the same.
    2. In test `'children Positioned.top clamps to >= 0 at progress=1.0 ...'`
       (around line 676): the *invariant* (top >= 0) still holds — that's
       the whole point of the new range. Update the reason string to:
       ```
       'Child must remain visible inside the elevator bbox at progress=1.0 '
       '— top must remain >= 0. With the travel range now equal to the '
       'tallest child (Plan 260511-dxa), this invariant is structural: '
       'top = platformY - childH = (bboxH - platformH) - progress * '
       'min(maxChildHeight, headroom) - childH, which is >= 0 when '
       'childH &lt;= maxChildHeight.'
       ```
       The assertion itself (`greaterThanOrEqualTo(0.0)`) is unchanged.
    3. In the `'Stack uses Clip.none so children may overhang bbox'` test
       (around line 711): the child is 80x200 in a 200x300 bbox. With the
       new range, `maxChildHeight = clamp(200, 0, 276) = 200`. At progress=1
       the platform sits at `(276 - 200) = 76`, child top = `76 - 200 = -124`
       (overhangs above the bbox — Clip.none is exactly what's needed). Read
       this test and confirm it doesn't assert a numeric top — it only
       confirms the Stack uses `Clip.none`. If it doesn't assert tops,
       leave it alone. If it does, recompute.
    4. Search the file for any other assertion on a `Positioned.top` that
       compares against `max(0.0, ...)` or assumes the old range — recompute
       using the new formula. (The fixed-children tests are the main two
       above; the simulate / Pitfall-1 / Pitfall-2 / multi-elevator / leak
       tests don't assert child top numerically.)
    5. If the file imports `max` from `dart:math` only for the
       `Positioned.top` clamp recomputation and that import becomes unused
       after the rewrite, leave it (the test file has multiple uses).
       `flutter analyze` will flag unused imports if any remain.

    **Step 2e — verification:**
    1. `flutter test test/page_creator/assets/elevator_layout_test.dart` —
       must pass (17 tests).
    2. `flutter test test/page_creator/assets/elevator_widget_test.dart` —
       must pass (all existing groups stay green).
    3. `flutter test test/page_creator/assets/elevator_painter_test.dart` —
       all NON-golden tests must pass (shouldRepaint contract, default
       colour). The 3 progress goldens will FAIL because their painter is
       constructed with no children → `maxChildHeight=0` → platform sits at
       the bottom for all 3, so position_0 stays valid but position_50 and
       position_100 now match position_0 visually. This is expected — Task 3
       regenerates them.
    4. `flutter analyze lib/page_creator/assets/elevator*.dart test/page_creator/assets/elevator*.dart`
       — must be clean.
    5. Commit with message:
       `feat(260511-dxa): elevator travel range equals tallest child height (ELEV-10)`
  </action>
  <verify>
    <automated>flutter test test/page_creator/assets/elevator_layout_test.dart test/page_creator/assets/elevator_widget_test.dart &amp;&amp; flutter analyze lib/page_creator/assets/elevator_layout.dart lib/page_creator/assets/elevator_painter.dart lib/page_creator/assets/elevator.dart 2>&amp;1 | grep -v "^Analyzing\|info •\|No issues found" | head -5</automated>
  </verify>
  <done>
    All layout + widget tests pass. `flutter analyze` reports no errors or
    warnings on the three modified library files. GREEN commit lands.
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Regenerate painter goldens + visual verification</name>
  <files>
    test/page_creator/assets/elevator_painter_test.dart,
    test/page_creator/assets/goldens/elevator/position_0.png,
    test/page_creator/assets/goldens/elevator/position_50.png,
    test/page_creator/assets/goldens/elevator/position_100.png
  </files>
  <action>
    **Step 3a — wire maxChildHeight into the painter golden harness:**

    1. Edit `test/page_creator/assets/elevator_painter_test.dart`.
    2. In `pumpElevator(WidgetTester tester, {...})`, add a named parameter
       `double maxChildHeight = 0.0` and pass it to the `ElevatorPainter`
       constructor.
    3. Update the 3 progress-variant golden tests (`position_0.png`,
       `position_50.png`, `position_100.png`) to call
       `pumpElevator(..., maxChildHeight: 100.0)`.
       Rationale: the painted bbox is 200x300, platformH = 300 * 0.08 = 24,
       headroom = 276. `maxChildHeight=100` gives a clearly visible travel
       of 100px without saturating to the top of the bbox — visually distinct
       from `position_0` and `position_50` is the geometric midpoint at 50px.
    4. Leave `stale.png` and `position_50_out_of_range.png` unchanged —
       their semantics don't depend on travel range; the platform-at-bottom
       rendering is fine for those goldens.

    **Step 3b — regenerate goldens:**

    1. Run:
       `flutter test --update-goldens test/page_creator/assets/elevator_painter_test.dart`
    2. Run the same test WITHOUT `--update-goldens`:
       `flutter test test/page_creator/assets/elevator_painter_test.dart`
       — must pass.
    3. Run the full elevator test suite to confirm nothing else regressed:
       `flutter test test/page_creator/assets/elevator_layout_test.dart test/page_creator/assets/elevator_widget_test.dart test/page_creator/assets/elevator_painter_test.dart test/page_creator/assets/elevator_config_test.dart`

    **Step 3c — commit:**

    Stage and commit:
    - `test/page_creator/assets/elevator_painter_test.dart`
    - `test/page_creator/assets/goldens/elevator/position_0.png`
    - `test/page_creator/assets/goldens/elevator/position_50.png`
    - `test/page_creator/assets/goldens/elevator/position_100.png`

    Commit message:
    `test(260511-dxa): regenerate painter goldens for new travel range (ELEV-10)`

    **Step 3d — pause for human visual verification (see &lt;how-to-verify&gt;).**
  </action>
  <what-built>
    The travel-range change visually affects the 3 progress-variant painter
    goldens (`position_0.png`, `position_50.png`, `position_100.png`). With
    the painter's default `maxChildHeight=0.0`, all three would render the
    platform at the bottom — visually identical, which is correct for a
    no-children setup but defeats the goldens' purpose.

    The action above updates the painter golden harness in
    `test/page_creator/assets/elevator_painter_test.dart` to pass an
    explicit `maxChildHeight=100.0` so the goldens visually capture the new
    travel behaviour at progress {0.0, 0.5, 1.0}, then regenerates them.

    After commit, the human visually inspects both the regenerated goldens
    and the runtime behaviour with a real Sensor child attached to a live
    Elevator under "Simulate motion".
  </what-built>
  <how-to-verify>
    **Human visual checks (after the automated steps in &lt;action&gt;):**

    1. Open the 3 regenerated golden PNGs in an image viewer.
       Visually inspect that:
       - `position_0.png` — platform at the BOTTOM (no change from before).
       - `position_50.png` — platform 50px up from the bottom (visibly
         risen, but not reaching the top of the bbox).
       - `position_100.png` — platform 100px up from the bottom (clearly
         higher than position_50, still well below the top of the bbox —
         not touching the top, because travel is now 100px out of 276px
         available).
    2. Open the app: `flutter run -d macos` (or your normal device).
    3. Open the page editor (TFC_GOD), drag an Elevator onto a page, attach
       a Sensor child via the elevator config dialog, save the page.
    4. Open the runtime page, toggle the elevator's "Simulate motion"
       switch on (in the config dialog).
    5. Watch the sensor ride the platform across the FULL cycle. Confirm:
       - The sensor smoothly translates up and down with the platform.
       - The sensor NEVER appears frozen at the top of the bbox during the
         upper portion of the cycle (this is the bug being fixed).
       - The sensor's bottom edge stays glued to the platform's top edge
         throughout the sweep.
       - At the top of the sweep, the platform stops well below the top of
         the bbox (it has only travelled the sensor's height, not the full
         bbox range).
    6. Add a Conveyor child too (different height than the sensor). Confirm:
       - The tallest child gates the travel range — both children translate
         the same distance.
       - The shorter child sits comfortably inside the bbox at all
         progress values.
    7. Run `flutter analyze` once more to confirm overall cleanliness.

    Reply with:
    - `approved` if all visual checks pass.
    - A description of any visual issue if not (e.g. "position_50 looks
      identical to position_0" indicates the harness `maxChildHeight` was
      not wired through correctly).
  </how-to-verify>
  <verify>
    <automated>flutter test test/page_creator/assets/elevator_painter_test.dart 2>&amp;1 | tail -5</automated>
  </verify>
  <done>
    Painter goldens regenerated and committed. Painter test suite passes
    with the new goldens. Human confirms via `approved` that:
    (a) the 3 regenerated PNGs visually show distinct platform positions,
    (b) the runtime sensor-on-elevator smoke shows no top-of-cycle freeze.
  </done>
  <resume-signal>Type "approved" or describe issues</resume-signal>
</task>

</tasks>

<verification>
- `flutter test test/page_creator/assets/elevator_layout_test.dart` passes (17 tests — 8 original + 9 new).
- `flutter test test/page_creator/assets/elevator_widget_test.dart` passes (~63 tests, child-top expectations recomputed).
- `flutter test test/page_creator/assets/elevator_painter_test.dart` passes (5 goldens + 5 contract tests).
- `flutter test test/page_creator/assets/elevator_config_test.dart` passes (no changes — sanity check).
- `flutter analyze lib/page_creator/assets/elevator_layout.dart lib/page_creator/assets/elevator_painter.dart lib/page_creator/assets/elevator.dart` clean.
- Manual smoke: child rides platform smoothly across 0–100% cycle; no freezing at the top.
</verification>

<success_criteria>
- Elevator travel range equals `min(tallestChildHeight, bboxHeight - platformHeight)`.
- No-children case: travel = 0, platform pinned at bottom.
- Oversized-child case: travel clamps to available headroom.
- The `max(0.0, platformY - childH)` clamp is removed from
  `_buildPositionedChild`; the formula is structurally guaranteed to
  produce `top >= 0`.
- Existing locked invariants preserved:
  - Pitfall 1 (child State identity across animation): unchanged — the
    `KeyedSubtree(ValueKey<String>(entry.id))` and the
    `ValueListenableBuilder` `child:` slot pattern are untouched.
  - Pitfall 2 (stream identity across rebuilds): unchanged — `_hoistStream`
    is not modified.
  - ELEV-15 (out-of-range outline mutually exclusive with stale): unchanged.
  - QUAL-08 (simulate motion): unchanged — simulation drives `_progress`
    which feeds the new travel range exactly as before.
- All elevator unit + widget + golden tests green.
- `flutter analyze` clean.
- 3 commits land: RED (test), GREEN (impl + test recompute), goldens
  (regeneration + visual approval).
</success_criteria>

<output>
After completion, create `.planning/quick/260511-dxa-elevator-travel-range-equals-tallest-chi/260511-dxa-SUMMARY.md`
summarising: what changed, the geometry derivation, the test recomputations
performed, and any surprises encountered during golden regeneration.
</output>
