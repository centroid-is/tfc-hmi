# Pitfalls Research

**Domain:** Industrial HMI — vertical-translation parent assets carrying child widgets, multi-kind sensor visualisers driven by state keys
**Researched:** 2026-05-05
**Confidence:** HIGH (grounded in existing codebase: `conveyor.dart`, `conveyor_gate.dart`, `common.dart`, `state_man.dart`; ConveyorGate milestone post-mortem in `.claude/...gate-visual-feedback.md`; CONCERNS audit dated 2026-05-05)

This file enumerates the failure modes the elevator + sensor milestone must guard against. Each pitfall is keyed to an implementation phase. None are generic Flutter advice — every pitfall cites the specific tfc-hmi2 file it would manifest in.

---

## Critical Pitfalls

### Pitfall 1: Child-widget identity loss when elevator position changes

**What goes wrong:**
Each frame, the elevator wraps its assigned children inside a `Positioned` (or `Transform.translate`) whose `top`/`y` is computed from the live PLC 0–100% value. If the implementation rebuilds the child subtree and the `Positioned` ancestry changes — even subtly, e.g. swapping between `Transform.translate` and `Positioned` or wrapping/unwrapping a parent based on `position == 0.0` — Flutter's element-tree reconciliation cannot match the new element to the old one, so the child's `State` is destroyed and rebuilt. The visible symptom is a sensor light "blinking" each tick, the gate animation snapping back to closed every position update, or `StreamBuilder.connectionState` resetting to `waiting` mid-flight.

**Why it happens:**
The rebuild reordering is invisible: `_ConveyorGateState`'s `AnimationController` lives in `State`, and it gets reconstructed on element re-mounting. Without an explicit `Key` keyed on the child's identity, Flutter falls back to widget-type + position matching — which is fragile across structural rebuilds. The conveyor's existing child-gate code at `lib/page_creator/assets/conveyor.dart:846–899` does NOT pass a `Key` to the inner `ConveyorGate`; it gets away with it only because the Stack children list is stable per build.

**How to avoid:**
- Give every child of the elevator a stable `ValueKey<String>` derived from a per-child identity (e.g. `ValueKey('elevator-child-${entry.id}')` or `ValueKey(entry.gate.runtimeType.toString() + entry.position.toString())` — but prefer an opaque assignment id). Add an `id` field to the `ChildEntry` wrapper and back it with a UUID created in the constructor.
- Keep the wrapping widget structure constant across all position values. Do not conditionally wrap with `Transform` / `Positioned` based on `position == 0`. If a translation is zero, still emit the same `Positioned`/`Transform.translate` node.
- Drive the position with a `ValueListenableBuilder<double>` whose `child:` parameter holds the child subtree (so the subtree is built once and only the wrapping `Transform` rebuilds per tick). See `auger_conveyor_painter.dart` ValueNotifier pattern at `lib/page_creator/assets/conveyor.dart:494–495` for prior art.

**Warning signs:**
- Sensor LED visually flickers when the PLC position oscillates by ±0.1%.
- Force-open dialog closes spontaneously when the elevator position changes.
- `StreamBuilder.snapshot.connectionState` is `waiting` more than once for the same child after initial mount.
- A `print` added to a child's `initState` fires more than once per page load.

**Phase to address:** Phase that implements elevator child-rendering (likely Phase 2 or 3). Acceptance criterion: a smoke test that drives the position notifier through 100 frames and asserts a child widget's `State.initState` was called exactly once.

---

### Pitfall 2: StateKey resubscribe storm when elevator rebuilds children

**What goes wrong:**
The existing `_ConveyorGateState.build` calls `ref.watch(stateManProvider.future).asStream().asyncExpand((sm) => sm.subscribe(key).asStream().switchMap((s) => s))` directly inside the `StreamBuilder.stream:` argument (`lib/page_creator/assets/conveyor_gate.dart:336–342`). This is already flagged in `CONCERNS.md` as a fragile area. If the elevator child's `build()` runs on every position tick (~10–50 Hz from the PLC), each rebuild constructs a brand-new outer stream, which causes `AutoDisposingStream`'s ref-counting to churn: cancel → recreate the OPC UA monitored item → resubscribe. Under load this can produce dropped values (because the underlying `ReplaySubject` holds at most 1) and a high-frequency monitoring-item create/cancel storm against the OPC UA server.

**Why it happens:**
`asStream().asyncExpand(...)` is an inline expression. Stream literals returned from `build()` are not memoised by Flutter — a new instance is allocated each frame. `StreamBuilder` compares by `identical(oldStream, newStream)` and unsubscribes/resubscribes on mismatch.

**How to avoid:**
- Hoist stream construction to `initState`/`didChangeDependencies` and store it in a `State` field. Pass that field to `StreamBuilder.stream:`.
- For the elevator parent, subscribe to the position key ONCE in `initState`; convert the stream's emissions into `_positionNotifier.value = v.asDouble`. Children read the notifier, not the stream.
- For each sensor child, subscribe to the bool state key ONCE in `initState`, store the subscription in `cancelOnDispose`, and feed a local `ValueNotifier<bool>` that the painter listens to.
- Do NOT call `ref.watch(stateManProvider.future)` inside child `build()` — call it once in `initState` via `ref.read(stateManProvider.future)` and stash the result.

**Warning signs:**
- OPC UA logs show monitored-item create/cancel pairs per UI frame.
- `state_man.dart` `_AutoDisposingStream` listener-count traces oscillate.
- CPU profiler shows `_resolveSubscription` hot during steady-state operation (no PLC change should trigger it).
- Network capture shows redundant OPC UA `CreateMonitoredItems` / `DeleteMonitoredItems` requests.

**Phase to address:** Phase that builds the elevator widget and the sensor widget. This is the same shape of bug as the existing `_ConveyorGateState` issue — fix the new code AND consider opening a follow-up for the gate.

---

### Pitfall 3: Painter state leakage between sensor kinds

**What goes wrong:**
The sensor asset has a `kind` enum (red light beam, optic field, inductive field). When the operator changes the kind in the config dialog, the visible widget often retains residual paint artefacts from the previous kind: the beam still renders behind the new optic field, or the inductive coil's animation continues even though the painter is supposedly different. Symptoms include duplicated icons after kind change, stuck animations from the previous painter, and "ghost" geometry that disappears only after a full page reload.

**Why it happens:**
- A single `CustomPainter` reads `widget.config.kind` and switches inside `paint()` — but the painter caches state (e.g. `Path` objects, last-drawn positions) in instance fields that are not reset on `kind` change.
- `shouldRepaint` returns `false` for the new kind because only the kind enum changed, but the painter compares by `progress` notifier identity.
- A factory like `_createPainter()` returns the wrong subclass after kind switch because `setState` was called BEFORE the config mutation actually committed.
- Animation controllers spun up for the "red light beam" pulsing animation are not stopped/disposed when the kind changes to "inductive field", so two animations run simultaneously.

The `ConveyorGate._createPainter` switch (`lib/page_creator/assets/conveyor_gate.dart:240–266`) is the closest analog — it returns a different painter per `gateVariant`, but because the gate's progress is controlled by a single boolean state key with the same animation semantics, this hides the kind-leakage problem. Sensor kinds will be more divergent (beams have geometry; fields have radial pulses), so the bug surfaces more clearly.

**How to avoid:**
- Use ONE painter class per sensor kind. Do not branch inside `paint()`. Select the painter in `_createPainter(kind)` exactly the way the gate does.
- Override `shouldRepaint(oldDelegate)` to return `true` when `oldDelegate.runtimeType != runtimeType` (different kind) OR when colour / geometry-affecting params changed.
- When `kind` changes in `setState`, dispose any animation controller specific to the old kind and recreate it for the new kind. Hold a per-kind `AnimationController?` field.
- Write a behavioural unit test that constructs the widget with kind=A, pumps a few frames, then rebuilds with kind=B, and asserts the painter type via `find.byType(<NewPainter>)` and that no `<OldPainter>` is in the tree.

**Warning signs:**
- After changing kind in the config dialog the preview shows two overlapping shapes.
- An animation controller leak warning appears in `flutter_test` ("AnimationController was not disposed").
- `shouldRepaint` is called but the canvas content does not change.
- Golden tests pass for kind A and kind B in isolation but fail when run sequentially in the same test.

**Phase to address:** Phase that implements the multi-kind sensor painter. Mandate a `shouldRepaint` test and a kind-switch widget test before merge.

---

### Pitfall 4: Tween/animation jitter when PLC position oscillates within deadband

**What goes wrong:**
The PLC reports the elevator position as a 0–100% double, often via OPC UA from a servo encoder. Real hardware is noisy: at rest, the value can dither by ±0.05% every 100 ms. If the elevator widget naively plugs the live value into a `Tween` or animation controller (`controller.animateTo(newValue)`), the controller restarts on every minor change, causing visible jitter and excessive repaints. Worse, if the implementation uses `TweenAnimationBuilder<double>(value: livePosition, duration: 200ms)`, every dither restart creates a 200 ms interpolation that is interrupted before completion.

**Why it happens:**
- Servo encoders return raw measurements without HMI-side filtering. The HMI is mirroring PLC truth (per the milestone's design — "PLC owns debouncing"), but for visual smoothness a small client-side deadband is appropriate.
- Animation controllers are designed for discrete state transitions, not continuous smooth tracking.
- `Curves.easeOut` on a constantly-changing target produces a juddering visual.

**How to avoid:**
- Drive the position through a `ValueNotifier<double>` (no tween). Set `_positionNotifier.value = newValue` directly on each PLC tick. Flutter's repaint batching is sufficient for a smooth visual at 30+ fps.
- Apply a small client-side deadband (e.g. 0.2% of travel) ONLY to suppress repaints, not to mask the value: `if ((newValue - _lastNotified).abs() < 0.002) return;`. Document this is purely a render optimisation, not data filtering.
- Do NOT use `AnimationController.animateTo(livePosition)` for tracking — controllers are for predetermined transitions (open/close), not for continuous-target smoothing.
- If smoothing is desired (e.g. PLC reports at 1 Hz and visuals at 60 Hz), use a single low-pass filter or a one-shot `Tween` between the previous and current PLC sample with a duration matching the PLC update interval. Never restart an in-flight tween on each new sample without considering the previous tween's progress.

**Warning signs:**
- Elevator visually shudders even when the PLC value is constant per logs.
- Frame rate drops (visible in DevTools > Performance) when an idle elevator is on screen.
- `paint()` is called 60+ times per second despite the PLC updating at 10 Hz.

**Phase to address:** Phase that wires the elevator's vertical translation. Add a unit test that injects a synthetic position stream with ±0.05% noise around 50% and asserts the notifier's emission count is bounded.

---

### Pitfall 5: Backwards-compat traps with JSON migration

**What goes wrong:**
Existing saved pages contain old asset shapes that lack the new fields. Two specific traps from this codebase:
1. **`json_serializable` requires non-nullable fields to have defaults.** If you add a new required field (e.g. `List<ChildEntry> children`) to `ElevatorConfig` without a default, generated `_$ElevatorConfigFromJson` will throw `TypeError: type 'Null' is not a subtype of type 'List<dynamic>'` for any old saved page.
2. **Wrapper-promotion ambiguity.** The conveyor gate already had to handle "old format: gate config at root level with `asset_name`" vs "new format: `ChildGateEntry` with `gate` sub-object" (`lib/page_creator/assets/conveyor.dart:26–48`). The elevator + sensor milestone WILL hit the same shape: someone will start by storing `List<BaseAsset> children`, then realise they need per-child placement metadata (offset, attachment point), and need a `ChildElevatorEntry` wrapper. Without a custom `fromJson` migration, the upgrade silently drops existing children.
3. **Enum forward-compat.** Adding a new `SensorKind.someNewKind` later will break old apps reading new pages unless `@JsonKey(unknownEnumValue: SensorKind.fallback)` is set on every enum-typed field. The codebase already does this (e.g. `GateVariant`, `GateSide`); failing to follow the pattern silently corrupts.
4. **AssetRegistry-not-registered silent drop.** `centroid-hmi/lib/main.dart` lines 151–165 contain commented-out registry calls that the architecture doc explicitly warns about. If the elevator and sensor are not registered in `lib/page_creator/assets/registry.dart`, JSON loading silently skips them with no error.

**Why it happens:**
- `json_serializable`'s default null-handling is unforgiving for list/map fields.
- Iterating from "single child" to "list of children with metadata" is a natural mid-implementation refactor; the migration is easy to forget.
- Registry registration is in a different file than the asset, so it's easy to merge an asset PR without the registry update.

**How to avoid:**
- For every list field, use `@JsonKey(defaultValue: <const empty list>)` AND default to `[]` in the constructor. For nullable/optional new fields, use `T?` plus `?? sensibleDefault` at read sites — or `@JsonKey(defaultValue: ...)`.
- For every enum field, use `@JsonKey(unknownEnumValue: EnumType.firstSafeValue)`.
- Anticipate the wrapper promotion: design `ChildElevatorEntry { String id; double offsetX; double offsetY; BaseAsset child; }` from day one, even if the milestone only uses `child`. Codify the JSON format in a unit test on day one.
- Write a "load old golden page" regression test: check in a sample JSON that represents the pre-milestone state and assert it loads with sensible defaults.
- Immediately add elevator/sensor registrations to `AssetRegistry._fromJsonFactories` AND `defaultFactories` in the same PR; cross-link from the asset file to the registry file with a comment.

**Warning signs:**
- An end-to-end "open existing page" test starts failing only on environments with old saved pages.
- New asset works in a fresh page but not when added to a page that was saved before the asset existed.
- `AssetRegistry.parse` returns assets in a different order than the JSON list (silent drop reorders).

**Phase to address:** Phase that introduces the elevator config (children list) and the sensor config (kind enum). Migration test must land in the same PR as the schema change.

---

### Pitfall 6: Goldens drift / brittle visual tests

**What goes wrong:**
Golden tests for the elevator and sensor painters fail intermittently:
- On CI, because the macOS-only guard at `test/page_creator/assets/conveyor_gate_golden_test.dart:67` (`skip: !Platform.isMacOS`) means Linux CI never enforces them — and the next change made on Linux silently breaks the goldens. This is already flagged in `CONCERNS.md`.
- Because the elevator's vertical position appears in goldens — one frame at 47% vs another at 47.001% produces pixel diffs.
- Because the sensor's animated detection ring has phase-dependent rendering.
- Because one test mutates a shared `ValueNotifier` and the next test sees that state.

**Why it happens:**
- Animations: pumping `WidgetTester.pumpAndSettle` does NOT settle infinite animations (e.g. a perpetually-pulsing field sensor). Tests time out or capture an arbitrary frame.
- Floating-point position: representing position as a double makes pixel-perfect goldens impossible without snapping.
- Shared painter state: `ValueNotifier`s declared as top-level variables persist across tests in the same file.

**How to avoid:**
- Pin `progress.value` and `position.value` to deterministic values in tests (e.g. `0.0`, `0.5`, `1.0`). Use `tester.pump(Duration.zero)` after setting the notifier; do NOT use `pumpAndSettle` if the painter has any infinite animation.
- Disable infinite sensor animations in tests via a config flag (e.g. `disableAmbientAnimations: bool`) set in `ConveyorGate` already implicitly via `_progress`. Make the same explicit on the sensor painter.
- Round the `position` to discrete steps (e.g. nearest 1%) in goldens by snapping the notifier value before passing to the painter under test.
- Add Linux/macOS matrix to `flutter_goldens` or relax the macOS-only guard with a known-bad-platform skip. Track a follow-up to make this CI-enforced.
- Reset all top-level/static state in `setUp`. Prefer per-test painter construction.
- Co-locate goldens by feature subdirectory (`test/page_creator/assets/goldens/elevator/`, `.../sensor/`).

**Warning signs:**
- Golden test passes locally on macOS, fails on Linux (or vice versa).
- Same test passes when run alone, fails when run as part of the suite.
- Tiny refactor that doesn't change painter logic causes 0.0001% pixel diff.

**Phase to address:** Phase that adds painters. Establish golden-test contract (deterministic-only, no infinite animations during golden capture) before any goldens are committed.

---

### Pitfall 7: Hit-test issues for assets riding the elevator

**What goes wrong:**
A sensor placed on the elevator is interactive (e.g. tap-to-show details). When the elevator moves to 95%, the sensor's hit area is offset by the parent's `Transform.translate` — but if the implementation uses raw `Transform.translate(offset: Offset(0, dy), child: child)`, hit-testing works correctly. If instead the implementation uses `Transform(transform: Matrix4.translationValues(0, dy, 0), transformHitTests: false)`, taps land where the child WAS at 0%, not where it now is. Same problem for overlap with `RotatedBox`-style ancestors.

The conveyor's existing pattern uses a custom `LayoutRotatedBox` with manual hit-test code (`lib/page_creator/assets/common.dart:1334–1360`). This is a hand-rolled implementation that already needed special hit-test handling to work — proof that the codebase's transform pattern is non-standard and needs care.

**Why it happens:**
- `Transform.translate` defaults to `transformHitTests: true`. `Transform()` constructor defaults to `true` as well, but custom `RenderObject`s might not honour the contract.
- Wrapping the child in `IgnorePointer` to disable hit-testing during animation is sometimes copy-pasted without removing `IgnorePointer` for the at-rest case.

**How to avoid:**
- Use `Transform.translate(offset: Offset(0, -dy), child: child)` — the named constructor — not the raw `Transform` constructor. Verify that `transformHitTests` is left at default `true`.
- For positioned children inside a `Stack`, mutate the `Positioned.top`/`bottom` in lockstep with the position notifier. Hit-testing on `Positioned` is correct by construction.
- Write a hit-test integration test: place a sensor on an elevator at 80%, simulate a tap at the on-screen position, assert the sensor's `onTap` fired.
- If extending `LayoutRotatedBox`-style custom render objects, ensure `hitTest` is overridden and respects the inverse transform. Reference `_RenderLayoutRotatedBox.hitTest` at `lib/page_creator/assets/common.dart:1334`.

**Warning signs:**
- Tapping a sensor on a moving elevator opens the wrong sensor (or no sensor).
- Tap target is correct at position 0% but offset at position 100%.
- Long-press / drag-to-rearrange in the editor works only when the elevator is at rest.

**Phase to address:** Phase that wires interactive sensor children. Acceptance test must include a hit-test at non-zero positions.

---

### Pitfall 8: Off-by-one with bbox-based travel range (top/bottom interpretation)

**What goes wrong:**
The milestone defines: "Elevator travel range = its bounding box (0% = bottom, 100% = top)." Two off-by-one traps:
1. **Y-axis inversion.** Flutter's coordinate system has `y=0` at the top. A naive implementation translates the platform by `position * height` — which produces 0% at TOP, not bottom (the opposite of the spec). The fix is `dy = (1 - position) * height` for the platform's `top` offset, or `bottom = position * height` for `Positioned.bottom`.
2. **Platform thickness.** The "platform" widget has finite height. At 100%, does the platform's top edge align with the bbox's top, or does the platform's bottom edge align? If you forget to subtract `platformHeight` at 100%, the platform overhangs the bbox. This was effectively the same class of bug as the gate's `outsideOverhang` calculation at `lib/page_creator/assets/conveyor.dart:855–859`.
3. **Children attached to the platform** must move WITH the platform, not relative to the bbox top. The reference frame for the child's offset is the platform's current Y, not the bbox's coordinate space — easy to confuse when reading the code months later.

**Why it happens:**
- Y-down coordinate system trips up everyone occasionally.
- "Travel range = bbox" is ambiguous about whether the bbox is the SHAFT extent or the PLATFORM travel extent (they differ by platform height).
- Specs that say "0% = bottom, 100% = top" don't address platform-thickness deltas.

**How to avoid:**
- Define a single helper: `double platformOffsetTop(double position, double bboxHeight, double platformHeight) => (1 - position) * (bboxHeight - platformHeight);`. Use it everywhere. Unit-test it with three samples: (0%, h=100, ph=20) → 80, (100%, h=100, ph=20) → 0, (50%, h=100, ph=20) → 40.
- Add a visual debug overlay (toggleable via a config flag) that draws the bbox edges and the platform extent so operators can verify visually.
- Document the "0% = platform-bottom-touches-bbox-bottom" or "0% = platform-centre-at-bbox-bottom" convention prominently in the asset's class doc comment, with an ASCII diagram.
- Children are positioned relative to the platform (`platformOffsetTop + childRelativeOffset`), NOT relative to the bbox.

**Warning signs:**
- At position=1.0, the platform extends above the bbox.
- At position=0.0, the children appear at the top of the bbox instead of the bottom.
- Children appear slightly out of sync with the platform (drift = platform thickness).
- Position 50% does not visually correspond to the geometric centre of the travel range.

**Phase to address:** Phase that wires the elevator's vertical translation. Mandate a unit test for the `platformOffsetTop` helper before any visuals are built.

---

### Pitfall 9: Rotation handling for sensors placed on rotated conveyors / elevators

**What goes wrong:**
The codebase's `BaseAsset.coordinates.angle` allows assets to be rotated (`lib/page_creator/assets/common.dart` Coordinates struct). The conveyor's `_buildConveyorVisual` already rotates via `LayoutRotatedBox(angle: (config.coordinates.angle ?? 0.0) * pi / 180, ...)`. If a sensor is placed on a 90°-rotated conveyor or a tilted elevator, multiple subtle bugs surface:
1. The sensor's own painter draws "horizontally" but the parent rotation makes it appear vertical — fine if the child is rotation-aware, broken otherwise.
2. The sensor's beam (red light kind) has a sender-and-receiver pair connected by a beam path. If the child computes that path in its local coordinate system but the parent rotates the result, the beam path can end up off-axis or reversed.
3. Hit-testing through nested rotations: a tap at screen position S must inverse-transform through ALL ancestor rotations to find the child. The custom `LayoutRotatedBox` already had to special-case this (`common.dart:1334–1360`).
4. Animation directions become reversed depending on the rotation: a "pulse outward" animation in the painter's local space pulses inward when the parent applies a 180° flip. The gate diverter's animation-direction-vs-side bug (`CONCERNS.md` BUG-Gate-animation) is a smaller version of this trap.

**Why it happens:**
- The asset system has TWO rotation mechanisms: per-asset `coordinates.angle` AND `Transform.rotate` inside the conveyor's child positioning (`conveyor.dart:876–880`). The elevator will be a third stacking layer.
- Painters draw in their local Size, ignoring ancestor transforms.
- "Direction" in animation code is implicit — sign of an offset in painter space.

**How to avoid:**
- Decide at the architecture level: is the elevator a "screen-aligned" widget (its content always renders upright regardless of `coordinates.angle`) or a "frame-aligned" widget (content rotates with the asset)? Document the choice in the asset's class doc.
- For sensor painters: NEVER assume a particular orientation in `paint()`. Read `Size`'s aspect ratio and adapt; or expose a `painterAngleDegrees` parameter the parent fills in based on the effective rotation it knows.
- For the red-light-beam kind: paint the sender at a relative position `(0, h/2)` and the receiver at `(w, h/2)`. The beam is always a horizontal line in the painter's frame. Whatever rotation gets applied externally is the parent's responsibility.
- Write a widget test that places a sensor on a 90°-rotated parent and asserts the rendered output (golden) AND a tap at the rotated position lands on the child.

**Warning signs:**
- Sensor visually appears rotated incorrectly when parent is rotated.
- Beam between sender and receiver appears vertical when the conveyor is horizontal (and vice versa).
- Tap target is offset from visual when nested rotations are present.
- Pulsing animation appears to contract instead of expand on a 180°-rotated parent.

**Phase to address:** Phase that integrates sensors with rotated parents (likely after the standalone painter phase). Test matrix must include 0°, 90°, 180°, 270° parent rotation × sensor on/off elevator.

---

### Pitfall 10: Memory leaks from animation controllers not disposed when child detaches

**What goes wrong:**
The sensor with red-light-beam kind has an ambient pulsing animation (the beam shimmers). If the operator removes a sensor from an elevator (unassigns it from the children list), the sensor widget unmounts — but if the `AnimationController` is held by a top-level provider, a pre-cached controller, or a static cache keyed by sensor id, it survives unmount. Symptoms: progressive memory growth on a long-running HMI session as operators reconfigure pages; eventually frame drops or OOM on the embedded Linux target.

The codebase already had two near-misses:
- `_ConveyorGateState` correctly disposes its controller in `dispose()` (`conveyor_gate.dart:213–218`). Good.
- BUT the `_ConveyorGateConfigEditorState` also has a controller (line 540–571) — also correctly disposed. Good. These set the precedent the new code must follow.
- `CONCERNS.md` flags "Animation controller disposal" as untested in the gate painters: "no test verifies ... animation controller disposal". A future refactor could break this silently.

**Why it happens:**
- Developers add an animation controller to a `State`, forget the `dispose()`, and the leak is invisible until production sessions run for hours.
- Cached painters in a top-level map outlive their widgets.
- A `ValueNotifier` constructed at top level (file scope) is never disposed.

**How to avoid:**
- ALL `AnimationController`s in elevator/sensor widget code MUST be disposed in `State.dispose()`. Code review checklist item.
- Add a behavioural unit test for each new `Stateful` widget: pump it, then `tester.pumpWidget(SizedBox())` to unmount, then assert no controllers remain (use Flutter's `LeakTesting` mode or count via `ServicesBinding.instance` introspection).
- Any `ValueNotifier` created in `initState` MUST be disposed in `dispose()`.
- Avoid top-level static caches of painters/controllers. If caching is needed (for performance), ref-count by widget id and dispose on zero refcount.
- If a painter holds a `ValueNotifier` via `super(repaint: progress)`, the notifier MUST belong to the State that constructs the painter, not be passed in from outside without ownership clarity.

**Warning signs:**
- `flutter test` reports "AnimationController was not disposed" warnings (set `LeakTesting.enable()`).
- Memory monitor shows growth correlating with sensor add/remove cycles.
- DevTools "Object Inspector" shows orphan `_AnimationController` instances after page navigation.

**Phase to address:** Phase that introduces ambient animations on the sensor (red-light beam shimmer). Acceptance test: leak-test mount/unmount cycle.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Inline `ref.watch(stateManProvider.future).asStream()...` in `StreamBuilder.stream` (gate's existing pattern at `conveyor_gate.dart:336`) | Compact code; no `initState` boilerplate | Stream resubscribe storm under high-frequency parent rebuilds (Pitfall 2) | Never for elevator children — rebuild rate is too high |
| Single painter that switches on `kind` in `paint()` | One file, less indirection | Painter-state leakage between kinds (Pitfall 3); harder testing | Never — always one painter class per kind |
| `setState` inside `_onStateChanged` driven by stream emission | Easy to write | Excessive rebuilds on noisy PLC; loses notifier-based optimisation | Only for the rare-event boolean (sensor detected → not detected). Position MUST use `ValueNotifier` |
| Hardcoded preview duration (gate had `1200ms` hardcoded — fixed in last milestone) | Quick to ship | Diverges from runtime behaviour; UI feels off | Never — read from config |
| Skip backwards-compat migration test ("we'll add it later") | Saves a day | Silent data loss for existing users | Never for any schema-affecting change |
| Skip `ValueKey` on children inside the elevator's child list | Simpler `Stack` builder | Identity loss on reorder / position change (Pitfall 1) | Never for stateful children |
| Register asset only in `AssetRegistry`, forget `defaultFactories` | One-line fix | Asset doesn't appear in palette but loads from JSON — confusing | Never |
| Read PLC position with no client-side deadband | Mirrors PLC truth | Excessive repaints from 0.05% encoder dither (Pitfall 4) | Never — render-only deadband does not affect data |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `StateMan.subscribe(key)` for position | Treat as stream of `bool` and call `.asBool` (silently returns false for double values) | Read `.asDouble` (`number.dart:316` reference); guard with `value.isDouble \|\| value.isInteger` (per `analog_box.dart:516`) |
| `StateMan.subscribe(key)` for sensor bool | Forget that `subscribe` returns `Future<Stream<DynamicValue>>` (not `Stream<DynamicValue>` directly) | `await sm.subscribe(key)` then operate on the returned stream — store in `State`, do NOT inline in `build()` |
| `AssetRegistry` registration | Register only in `_fromJsonFactories`, forget `defaultFactories` (palette) | Register in BOTH maps in the SAME PR; cross-link with comments |
| Key substitution (`$varName`) | Subscribe BEFORE `resolveKey`, key not substituted | Use `stateMan.resolveKey(key)` before `subscribe` if assets reference dynamic positions |
| `json_serializable` enum field | Add new enum value in this version → old versions crash on read | Always `@JsonKey(unknownEnumValue: SafeFallback)` from the FIRST commit |
| `ChildEntry`-style wrappers | Store the child as a typed `BaseAsset` field without a custom `fromJson`/`toJson` | Use `@JsonKey(fromJson: _xFromJson, toJson: _xToJson)` (mirror `_gateFromJson` pattern in `conveyor_gate.dart:63–65`) |
| Riverpod inside `keepAlive` providers | `ref.watch(otherProvider)` cascades invalidation | `ref.read(otherProvider.future)` for one-shot init (per `ARCHITECTURE.md` anti-pattern) |
| OPC UA `DynamicValue.asDouble` | Crash if value is a String / NULL during reconnect | Guard with `if (snap.hasData && snap.data!.isDouble)` and grey out otherwise (per `analog_box.dart:737` pattern) |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Position drives `setState` instead of `ValueNotifier` | Whole subtree rebuilds at PLC rate; CPU pegged | Hold position in `ValueNotifier<double>`, use `ValueListenableBuilder` with stable `child:` | At 30+ Hz PLC update rate, or with multiple elevators on one page |
| New stream constructed inside `build()` (Pitfall 2) | OPC UA monitored items churn; dropped values | Hoist to `initState` | Always — even at 1 Hz this is wrong |
| `pumpAndSettle` on infinite ambient animations | Tests time out at 10 minutes | Pin `progress` to a deterministic value; use `pump(Duration.zero)` | Always in tests with sensor pulses |
| Goldens with floating-point position | Pixel diffs on every commit | Snap to discrete steps in tests | At any non-zero position |
| Stack with N children rebuilds entire stack on position change | Sensor LEDs flicker; FPS drops with many children | `RepaintBoundary` per child + stable `Key`s + `ValueListenableBuilder` with `child:` cached subtree | At 5+ children per elevator |
| `unawaited(stateMan.write(...))` in tap handler called on every animation tick | Network saturation; OPC UA write queue overflow | Bind writes to genuine user actions only; no writes from `paint()` or animation listeners | Always |
| Painter holding non-trivial state in instance fields rebuilt each frame | `paint()` allocates Path / Paint per call | Allocate Paint objects once in painter constructor; cache Paths keyed by progress | At 60 fps with complex geometry |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Allow operator to type any OPC UA key into the elevator's "force position" write field, no validation | Operator types a critical-safety key by accident; widget writes to it | Force keys for elevator should be display-only in this milestone (write is out of scope per spec). For future milestones, validate against a write-allow-list in `StateManConfig` |
| Sensor "force-detected" debug feature | Operator forces a sensor true to bypass interlocks | Out of scope for this milestone. If added later, gate behind PAM auth via `lib/pages/dbus_login.dart` |
| Position write capability via tap on the elevator visual | Inadvertent jog causes equipment crash | Spec is read-only for position. Do not add tap-to-drive in this milestone. If added, route through `ElicitationDialog` for confirmation (`lib/chat/elicitation_dialog.dart` precedent) |
| Sensor edge-delay state keys exposed to MCP / LLM as writable | LLM agent silently changes PLC config | Spec is display-only. Do not expose write capability to MCP tool surface |
| State-key field accepts substitution syntax (`$varName`) without validation | Malformed substitution silently no-ops, operator thinks the key is bound | Validate that resolved key is non-empty at config-save time; warn in the editor if substitution variable is undefined |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Elevator at 0% renders identical to "no data" (both at bottom) | Operator can't tell if PLC is offline or genuinely at 0 | Mirror gate's grey-when-disconnected pattern (`conveyor_gate.dart:325`). At 0%, render in normal colour; on disconnect, render grey or with a fault indicator |
| Sensor kind icons indistinguishable at small sizes | Operator can't tell red-light from optic field on a dense page | Each kind gets a distinctive silhouette readable at min size (e.g. 32×32 px); test by rendering a 32×32 thumbnail and asking a non-author to identify the kind |
| Sensor edge-delay state-key fields mixed with rising-edge / falling-edge fields with no clear pairing | Operator types delay key into wrong slot | Group rising/falling edge fields visually with sub-headers; use the `KeyField` widget pattern from gate's force-control section (`conveyor_gate.dart:876–900`) for consistency |
| Removing a child from the elevator silently drops its config | Operator loses force keys / state keys configured on the child | Confirmation dialog before removing a child; or "Hide" vs "Delete" semantics |
| Child appears outside elevator bbox visually (overflow) | Operator confused why a sensor is "floating" | Wrap the elevator's child stack in `Clip.hardEdge` or visualise the bbox in the editor mode |
| Force-position controls appear in editor preview | Operator triggers writes while editing | Disable interactivity in editor mode; mirror gate's preview-only mode in `_ConveyorGateConfigEditor` |
| Multiple elevators with the same PLC position key indistinguishable | Operator confuses two elevators feeding from one position signal | This is intended (one PLC drives multiple visualisations) but warn in the editor when the same key is used by N visible elevators on the page |
| Sensor's ambient pulsing animation runs in the asset palette | Distracting in the palette dropdown | Disable ambient animations in palette/preview mode (`_buildPreview` should pass a `static: true` flag to the painter) |
| Edge-delay values hidden from operator | Operator wants to see "what delay is the PLC using right now?" but the milestone says display-only | Show the delay values prominently as text overlay on the sensor when both keys are configured; do not hide |

---

## "Looks Done But Isn't" Checklist

- [ ] **Elevator vertical translation:** Often missing the platform-thickness offset — verify position 0% has platform's BOTTOM at bbox bottom AND position 100% has platform's TOP at bbox top.
- [ ] **Sensor kind switch:** Often missing `shouldRepaint` returning true on `runtimeType` change — verify by switching kinds in editor and watching for stale frame artefacts.
- [ ] **Children riding the elevator:** Often missing stable `Key`s — verify by adding `print('initState')` to a child and confirming it logs exactly once on page load, not on every position change.
- [ ] **Backwards compat:** Often missing the migration test for old saved pages — verify by checking in a sample legacy JSON and running it through `AssetRegistry.parse` in a test.
- [ ] **AssetRegistry registration:** Often missing in BOTH `_fromJsonFactories` AND `defaultFactories` — verify the new asset appears in the palette AND a saved page round-trips.
- [ ] **Animation controller disposal:** Often missing — verify with `LeakTesting.enable()` in widget tests.
- [ ] **PLC position deadband:** Often missing render-only deadband — verify by injecting noisy synthetic position and counting `paint()` calls (should be < update rate × 1.1).
- [ ] **Hit-testing on moving elevator:** Often missing — verify by tapping a sensor at non-zero elevator position and confirming the correct sensor's `onTap` fires.
- [ ] **Goldens determinism:** Often missing — verify by running the goldens test 10 times in a row; any flake is a determinism bug.
- [ ] **Disconnected state visual:** Often missing — verify by stopping the OPC UA server and confirming the elevator + sensor both render grey (not last-known position / state).
- [ ] **Force-control editor-mode disable:** Often missing — verify by entering the page editor; tapping a sensor should not write to PLC.
- [ ] **Enum forward-compat:** Often missing `unknownEnumValue` — verify by editing JSON to a fictional `kind: "futureKind"` and confirming the asset loads with a sensible fallback.
- [ ] **Multi-elevator on one page:** Often missing — verify by placing 5 elevators with the same position key and confirming smooth animation, no stuttering.
- [ ] **Edge-delay display:** Often missing — verify the values from the rising/falling-edge state keys are shown to the operator (display-only per spec) AND the visual flips immediately on the bool key (delays do NOT affect the visual).
- [ ] **Rotation pass-through:** Often missing — verify a sensor on a 90°-rotated conveyor renders correctly AND is tappable.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Backwards-compat broken in shipped release | HIGH | (1) Hotfix `_*FromJson` to accept both old and new shapes; (2) emit telemetry on which path was taken; (3) auto-migrate on save by writing the new shape; (4) post-mortem on missing migration test |
| Memory leak from undisposed controllers | MEDIUM | Identify via DevTools; add `dispose()` calls; backport `LeakTesting.enable()` to widget test suite; ship a follow-up |
| Resubscribe storm | MEDIUM | Hoist stream construction out of `build()`; verify with OPC UA server logs; add a test that pumps frames at 60 Hz and asserts subscription count is bounded |
| Painter state leakage | LOW | One painter per kind; per-kind controller; ship as a single PR; add kind-switch widget test |
| Goldens broken after a Linux PR landed | LOW | Regenerate goldens on macOS; investigate why Linux CI didn't catch it (per `CONCERNS.md` golden-CI gap); add CI matrix as follow-up |
| Hit-test offset on rotated parent | LOW | Replace bare `Transform()` with `Transform.translate()`; verify `transformHitTests: true`; add an integration test |
| Y-axis off-by-one (top vs bottom interpretation) | LOW | Localise to the `platformOffsetTop` helper; flip the formula; update unit tests |
| Animation jitter on PLC dither | LOW | Add render-only deadband (0.2%); document the value; visual is unaffected |

---

## Pitfall-to-Phase Mapping

(Phase numbers are placeholders. The roadmap will assign real numbers; this mapping records WHICH phase is responsible.)

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. Child identity loss | Elevator-rendering phase | Widget test asserts `initState` called once across 100 position frames |
| 2. Resubscribe storm | Elevator + sensor data-binding phase | OPC UA server log shows monitored-item create/cancel rate ≤ 1 per genuine config change |
| 3. Painter state leakage | Sensor multi-kind painter phase | Kind-switch widget test asserts new painter type and old painter unmount |
| 4. Animation jitter | Elevator-rendering phase | Synthetic-noise position test asserts paint count bounded |
| 5. JSON migration | Config-schema phase (likely first phase) | Legacy-JSON regression test; registry round-trip test |
| 6. Goldens drift | Each painter phase | Determinism test (run goldens 10× in CI); CI matrix includes Linux |
| 7. Hit-test issues | Sensor-on-elevator integration phase | Tap-at-non-zero-position integration test |
| 8. Bbox off-by-one | Elevator-rendering phase | Unit test on `platformOffsetTop` helper at 0 / 50 / 100 |
| 9. Rotation handling | Sensor-on-rotated-parent integration phase | Test matrix: rotation × on-elevator × off-elevator |
| 10. Animation controller leaks | Sensor ambient-animation phase | `LeakTesting.enable()` mount/unmount test |

---

## Codebase References

Key files cited (paths absolute under `/Users/jonb/Projects/tfc-hmi2`):

- `lib/page_creator/assets/conveyor_gate.dart` — animation controller pattern (lines 195–218); inline-stream anti-pattern (lines 336–342); `_createPainter` switch (240–266); force-key pattern (291–302); config editor with preview (525–615)
- `lib/page_creator/assets/conveyor.dart` — `_positionedChildGate` (846–899); `_gatesFromJson` legacy migration (26–48); `_gatesToJson` (50–51); auger ValueNotifier pattern (494–495); LayoutRotatedBox usage (792, 840)
- `lib/page_creator/assets/conveyor_gate_painter.dart` — painter-with-progress-notifier pattern (108–127)
- `lib/page_creator/assets/common.dart` — `BaseAsset` (100), `Coordinates` (37), `RelativeSize` (54), `LayoutRotatedBox` (1250), `_RenderLayoutRotatedBox.hitTest` (1334–1360)
- `lib/page_creator/assets/registry.dart` — `registerFromJsonFactory` (113), `registerDefaultFactory` (118)
- `lib/page_creator/assets/analog_box.dart` — typed-value guards (`isDouble || isInteger`) at line 516
- `lib/providers/state_man.dart` — `stateManProvider` usage with `ref.read(...future)` precedent (line 35)
- `packages/tfc_dart/lib/core/state_man.dart` — `AutoDisposingStream` ref-counting (the entity that suffers under Pitfall 2)
- `.planning/codebase/CONCERNS.md` — `_ConveyorGateState` fragile pattern at lines 163–167; macOS-only goldens at lines 168–172; gate animation direction bug at lines 100–104
- `.claude/...gate-visual-feedback.md` — slider painter rotation hack failure; diverter animation-direction-vs-side bug; gate top/bottom positioning UX gap (the prior milestone's open issues)

---

## Sources

- Existing tfc-hmi2 codebase (HIGH confidence — direct citations above)
- `.planning/codebase/CONCERNS.md` (2026-05-05)
- `.planning/codebase/ARCHITECTURE.md` (2026-05-05) — anti-patterns section
- `.planning/codebase/CONVENTIONS.md` (2026-05-05) — `@JsonKey(unknownEnumValue:)` and `keepAlive` provider conventions
- `.claude/projects/-Users-jonb-Projects-tfc-hmi2/memory/gate-visual-feedback.md` (2026-03-07; flagged stale by system reminder, but the open-issue items match `CONCERNS.md` BUG entries dated 2026-05-05, so the post-mortem signal is still valid)
- Flutter framework knowledge: `Transform.translate` hit-testing semantics, `ValueListenableBuilder.child` rebuild optimisation, `AnimationController.dispose` contract, `json_serializable` null-handling for collection fields (HIGH confidence — standard framework behaviour)

---
*Pitfalls research for: industrial HMI vertical-translation parent assets and multi-kind sensor visualisers*
*Researched: 2026-05-05*
