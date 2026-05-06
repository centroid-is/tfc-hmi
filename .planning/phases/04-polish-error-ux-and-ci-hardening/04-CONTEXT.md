# Phase 4: Polish, Error UX & CI Hardening - Context

**Gathered:** 2026-05-06
**Status:** Ready for planning
**Mode:** TDD

<domain>
## Phase Boundary

Close the milestone with three production-quality guards: out-of-range fault outline on the elevator (ELEV-15), multi-elevator smoke test confirming independent state subscriptions (QUAL-06), and a `LeakTesting.enable()` mount/unmount test verifying clean disposal of AnimationControllers / stream subscriptions (QUAL-07).

</domain>

<decisions>
## Implementation Decisions

### ELEV-15: Out-of-Range Outline
- When the position stream emits a value `> 100` or `< 0`, the elevator clamps to [0, 100] AND surfaces an **amber outline** (ISA-101 abnormal state) around the bounding box.
- Outline drawn by `ElevatorPainter` when `isOutOfRange = true`.
- Stale state (no value yet / null / error) remains separate and renders grey — these two states are distinct.
- Widget tests:
  - Stream emits 150 → progress clamped to 1.0 AND `isOutOfRange = true`
  - Stream emits -50 → progress clamped to 0.0 AND `isOutOfRange = true`
  - Stream emits 50 → progress 0.5 AND `isOutOfRange = false`
  - Painter golden for out-of-range state added (1 new golden: `position_50_out_of_range.png`)

### QUAL-06: Multi-Elevator Smoke
- Widget test: place TWO Elevator widgets on a page, each with a different `positionKey`. Drive each independently. Verify their `_progress` notifiers operate independently (no shared state).
- Verify each elevator's own `_hoistedKey` is independent.
- Test passes deterministically across 5 consecutive runs.

### QUAL-07: Leak Testing
- Add a widget test wrapped with `LeakTesting.enable()` from `package:leak_tracker_flutter_testing`.
- Mount → unmount the Sensor and Elevator widgets, assert no leaks reported.
- Covers both AnimationController disposal AND stream subscription cleanup.
- If `package:leak_tracker_flutter_testing` is not in pubspec, add it as a dev_dependency.

</decisions>

<code_context>
## Existing Code Insights

- `Elevator._isStaleEffective` already used for stale detection — extend the pattern with `_isOutOfRange` getter.
- `ElevatorPainter` constructor already takes `progress` and `isStale` — add `isOutOfRange` and a coloured outline path.
- `_progress: ValueNotifier<double>` is currently the source of truth — independent per-Elevator instance, so multi-elevator independence should already work.

</code_context>

<specifics>
## Specific Ideas

- Out-of-range outline: 2px stroke in amber `Color(0xFFFFA500)`, drawn outside the rails as a rectangle hugging the bbox.
- Multi-elevator test pumps a `Column(children: [Elevator1, Elevator2])` and exercises each in turn.
- Leak test: use `testWidgets` with `experimentalEnableLeakTracking: true` if available (package-dependent).

</specifics>

<deferred>
## Deferred Ideas

None — phase 4 closes the milestone.

</deferred>
