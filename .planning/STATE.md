---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Advantys STB I/O Assets
status: planning
last_updated: "2026-05-11T14:55:43.929Z"
last_activity: 2026-05-11
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-05)

**Core value (v2.0):** Operators can drop a Modicon Momentum stack onto an HMI page and see the physical control panel (NIP2311 head + PDT3100 power + DDI3725 16-ch DI + DDO3705 16-ch DO) mirrored with live PLC state — channel LEDs, force overrides, filters, detail dialogs — visually recognizable as Momentum modules.
**Current focus:** Defining requirements (v2.0 milestone setup)

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-05-11 — Milestone v2.0 started

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Sensor first (simpler; establishes painter conventions before elevator visuals)
- Roadmap: Elevator child embedding deferred to Phase 3 — animation pipeline validated standalone in Phase 2 to keep child-identity risk isolated
- Roadmap: `ElevatorChildEntry` wrapper schema (UUID + offsetX + child) locked in Phase 2 from day one to avoid wrapper-promotion migration trap

### Pending Todos

None yet.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260511-dxa | Elevator travel range equals tallest child height (remove clamp that pins child to top=0) | 2026-05-11 | 212dce1 | [260511-dxa-elevator-travel-range-equals-tallest-chi](./quick/260511-dxa-elevator-travel-range-equals-tallest-chi/) |
| 260511-ehy | Elevator child Y-axis anchor offset (offsetY raises/lowers child relative to platform top) | 2026-05-11 | 8e4fd8c | [260511-ehy-elevator-child-y-axis-anchor-offset-offs](./quick/260511-ehy-elevator-child-y-axis-anchor-offset-offs/) |
| 260511-fd6 | Elevator travel range as configurable fraction of bbox height (replace auto-deduce from child sizes) | 2026-05-11 | 1d5dce4 | [260511-fd6-elevator-travel-range-as-configurable-fr](./quick/260511-fd6-elevator-travel-range-as-configurable-fr/) |
| 260512-stb | STB painter defects batch 2 — chamfer-leak, subtle radii, PDT INPUT/OUTPUT plug topology, "24 VDC 0.55A" + "Schneider Electric" removal, slim Beckhoff DIN-rail aspect (1:6 / 1:3), real-hardware LED block (dark panel + RDY + numbered 1..16 squared LEDs) | 2026-05-12 | d00e984 | [20260512-stb-painter-defects-batch2](./quick/20260512-stb-painter-defects-batch2/) |

### Blockers/Concerns

Five codebase lookups flagged before Phase 1 planning (per research SUMMARY):

- Does `BaseAsset`/`Coordinates` already carry a rotation field? (affects SENS-15)
- What colour does `led.dart` use for active state? (affects SENS-08 default)
- Is there a shared stale-stream painter helper convention? (affects SENS-14, ELEV-14)
- Active-polarity inversion ships in v1 (already locked: SENS-12 — confirmed in scope)
- Beam-line broken-state colour polarity (dark-on-through-beam vs light-on-diffuse) — affects SENS-06 default

These are 5-minute `Read` calls during plan-phase, not blockers to the roadmap.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-05-05
Stopped at: Roadmap created — 4 phases, 42 v1 requirements mapped, success criteria defined
Resume file: None
