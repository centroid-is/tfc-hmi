# Phase 3: Elevator Child Embedding - Context

**Gathered:** 2026-05-06
**Status:** Ready for planning
**Mode:** TDD — tests first, implementation to satisfy them

<domain>
## Phase Boundary

Operators can attach Sensor and Conveyor child assets to an elevator via a dropdown in the config dialog, edit and remove them through the same dialog, and watch every child physically ride the platform up and down. Children retain widget identity across position changes (`ValueKey<String>` keyed on the UUID schema locked in Phase 2). Each child renders via its own polymorphic `BaseAsset.build(context)` — the elevator never switches on child runtime type. The elevator's `allKeys` override flat-maps children's keys so alarms/collectors discover nested keys.

Critical user directive (from `feedback_gesture_through_translation.md`): children's GestureDetectors must continue to receive taps while the platform is mid-translation. The hit-test region must follow the rendered position, not the layout-time position. This is achieved by using `Positioned.top` driven by `ValueListenableBuilder<double>` inside a `Stack` — the widget tree's hit-test geometry naturally follows.

</domain>

<decisions>
## Implementation Decisions

### Child Layout & Identity
- Stack composition: (1) `CustomPaint(painter: ElevatorPainter, ...)` for rails + platform via `_progress` notifier, (2) one `Positioned` per child whose `top` follows platform Y in real time via `ValueListenableBuilder<double>`.
- Each child's outer wrapper uses `ValueKey<String>(entry.id)` — the UUID locked in Plan 02-02's ElevatorChildEntry schema.
- Child intrinsic sizing: `entry.child.size.toSize(parentPlatformSize)` (mirror conveyor_gate dual-mode pattern); fall back to a sensible default when child has no RelativeSize.
- Vertical anchor: child's bottom edge sits on platform's top edge — `top: platformY - childHeight`. Children "ride on" the platform like cargo on a lift.
- `Stack(clipBehavior: Clip.none)` so children may extend outside the elevator bbox during translation without being clipped.

### Editor & allKeys
- "Add child" button: tap → AskUserQuestion-style dropdown of {Sensor, Conveyor} → creates new ElevatorChildEntry with auto-generated UUID (`DateTime.now().microsecondsSinceEpoch.toString()`) + `offsetX = 0.5` default. Append to `children` list and `setState`.
- "Edit child": tap an existing entry in the list → opens that child's `configure()` dialog (recursive — uses BaseAsset's existing dialog flow). Save returns to elevator dialog.
- "Remove child": delete icon next to entry → confirm → remove from list.
- Per-entry `Slider` 0..1 for offsetX (lateral position on platform).
- `ElevatorConfig.allKeys` override: `[positionKey, ...children.expand((e) => e.child.allKeys)]`. Filter out empty positionKey if not configured.

### Hit-Test Through Translation (CRITICAL — user directive)
- Children's hit-test follows their `Positioned.top` value. Because Flutter's hit-test walks the widget tree's layout, NOT paint-time offsets, using `Positioned` (which lives in the layout tree) ensures taps land on the rendered glyph regardless of platform position.
- A widget test verifies this: place a Sensor on an Elevator, drive _progress to 0.5, simulate `tester.tap(find.byType(Sensor))`, assert the sensor's config dialog opens.
- Anti-pattern explicitly avoided: `Transform.translate` on the painter without a corresponding layout-tree wrapper around children. Use `Positioned` per child; do NOT translate the painter.

### Backwards-Compat
- `_childrenFromJson` legacy shim already in Plan 02-02 (mirror of `_gatesFromJson`). This phase ensures it round-trips children that didn't exist in Phase 2.
- New ElevatorChildEntry instances use the locked schema; no migration needed.

### Tests
- Golden coverage: 3 goldens — elevator at progress {0.0, 0.5, 1.0} with one Sensor + one Conveyor child attached.
- Widget tests: tap-during-translation, ValueKey identity preservation across rebuilds, allKeys flat-map, child add/edit/remove flows.
- Integration test: a Sensor riding an Elevator at progress=0.5 receives a tap that opens the Sensor's config dialog (not the Elevator's).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ElevatorChildEntry` (Plan 02-02) — wrapper schema locked: `id`, `offsetX`, `child`.
- `_progress: ValueNotifier<double>` (Plan 02-04) — the existing notifier already drives the platform; reuse for child positioning.
- `Sensor` and `Conveyor` widgets — both registered, both will be valid children.
- `AssetRegistry.parse(json)` — polymorphic deserialisation; already handles `child` field via `_childFromJson`.
- `_ElevatorConfigEditor` (Plan 02-05) — already has positionKey + tweenDurationMs fields; this phase replaces the "Children: 0" placeholder with the full add/edit/remove UI.

### Established Patterns
- `_positionedChildGate` in `conveyor.dart` — closest precedent for parent-positioned-child layout. AVOID its switch-on-child-type anti-pattern (Anti-Pattern 1 in research/ARCHITECTURE.md).
- `LayoutRotatedBox` — children may need rotation, but rotation is the child's responsibility (handled by their own `Coordinates.angle`).
- ValueListenableBuilder rebuild scoping — already used in Elevator widget (Plan 02-04).

### Integration Points
- `ElevatorConfig.allKeys` getter — override here.
- `ElevatorConfig.children` (already typed `List<ElevatorChildEntry>` in Plan 02-02) — list mutation in editor.
- `Elevator.build` — replace existing simple Stack with the multi-child Stack.

</code_context>

<specifics>
## Specific Ideas

- Children are filtered by registered type in the dropdown — only assets where the user wants to allow embedding (Sensor, Conveyor) appear. Implementation: hard-coded list `[SensorConfig, ConveyorConfig]` in editor; can be made configurable later.
- offsetX slider thumbnail shows the child's lateral position visually — small horizontal strip with a marker.
- Removing the last child shows the "Children: 0" placeholder again (graceful empty state).
- Children list rendering: scrollable column inside the dialog; each row = "[icon] [type name] [offsetX slider] [edit] [remove]".

</specifics>

<deferred>
## Deferred Ideas

- Drag-drop child reordering — captured in PROJECT.md "Out of Scope".
- Per-child rotation override — children manage their own rotation via Coordinates.angle.
- Child overflow visualisation when offsetX is near 0 or 1 — defer to Phase 4 polish if useful.

</deferred>
