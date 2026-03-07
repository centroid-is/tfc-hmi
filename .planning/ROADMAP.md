# Roadmap: ConveyorGate Asset

## Overview

Build a configurable ConveyorGate HMI asset in three phases: first deliver a working standalone gate with the pneumatic diverter painter (the most complex variant and primary use case), then complete all remaining features (force controls, slider/pusher painters, color pickers), and finally integrate gates as children of existing Conveyor assets. Each phase delivers a coherent, independently testable capability. Child-of-conveyor is last because it modifies existing production code and carries the highest risk (hit-testing outside parent bounds).

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Standalone Diverter Gate** - Config, registry, pneumatic diverter painter, animated transitions, OPC UA state binding, standalone placement
- [ ] **Phase 2: Full Feature Set** - Force controls with dialog, slider and pusher painter variants, color pickers, forced-state theming
- [ ] **Phase 3: Child-of-Conveyor Integration** - Gates as conveyor children with belt positioning, auto-scaling, overflow rendering, and hit-test fix

## Phase Details

### Phase 1: Standalone Diverter Gate
**Goal**: Operators can place a pneumatic diverter gate on any page and see it animate open/closed in real-time from OPC UA data
**Depends on**: Nothing (first phase)
**Requirements**: PAINT-01, PAINT-02, PAINT-03, PAINT-06, ANIM-01, ANIM-02, ANIM-03, ANIM-04, DATA-01, DATA-06, VIS-01, VIS-02, SOLO-01, SOLO-02, SOLO-03, SOLO-04
**Success Criteria** (what must be TRUE):
  1. User can add a ConveyorGate from the page editor asset list and it appears on the page with a pneumatic diverter visual
  2. Gate animates smoothly between open and closed states when the bound OPC UA boolean key changes, with configurable timing
  3. Gate displays green when open, configurable closed color when closed, and grey when OPC UA data is unavailable
  4. User can open a configuration dialog to set OPC UA state key, opening angle, open/close timing, side selection, and colors
  5. Gate renders correctly at any page position, size, and rotation angle
  6. Golden image tests verify gate visual appearance in both open and closed states
**Plans:** 3 plans

Plans:
- [x] 01-01-PLAN.md -- Config model, pneumatic diverter painter, unit tests, golden tests
- [x] 01-02-PLAN.md -- Config dialog with live preview, color pickers, angle slider
- [x] 01-03-PLAN.md -- Widget with animation + OPC UA binding, registry integration

### Phase 2: Full Feature Set
**Goal**: Operators can force gates open/closed via tap interaction, see forced-state feedback, and choose between three gate visual variants
**Depends on**: Phase 1
**Requirements**: PAINT-04, PAINT-05, DATA-02, DATA-03, DATA-04, DATA-05, VIS-03, VIS-04, INT-01, INT-02, INT-03
**Success Criteria** (what must be TRUE):
  1. User can tap a gate (when force keys are configured) and use a dialog to force it open or closed, with active feedback state displayed
  2. Gate displays a distinct forced-state color from the Flutter theme (yellow/amber) when force-active feedback is true, adapting to dark/light mode
  3. User can switch gate variant to slider or pusher in the config dialog, and each renders with its own distinct visual (sliding plate or extending blade)
  4. User can pick custom colors for active and closed states using color picker controls in the config dialog
  5. Gate with no force keys configured is display-only and not clickable
**Plans**: TBD

Plans:
- [ ] 02-01: TBD
- [ ] 02-02: TBD

### Phase 3: Child-of-Conveyor Integration
**Goal**: Integrators can attach gates to conveyor assets so they render at specific belt positions with correct scaling and independent interaction
**Depends on**: Phase 2
**Requirements**: CHILD-01, CHILD-02, CHILD-03, CHILD-04, CHILD-05, CHILD-06
**Success Criteria** (what must be TRUE):
  1. User can add and manage child gates from the conveyor configuration dialog using the subdevice pattern
  2. Child gate renders at the correct fractional position along the conveyor belt, on the selected side (left/right)
  3. Child gate flap spans the belt width and pneumatic cylinder extends visually outside the conveyor bounding box
  4. User can click a child gate to open its own config/force dialog independently of the parent conveyor
**Plans**: TBD

Plans:
- [ ] 03-01: TBD
- [ ] 03-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Standalone Diverter Gate | 3/3 | Complete | 2026-03-07 |
| 2. Full Feature Set | 0/0 | Not started | - |
| 3. Child-of-Conveyor Integration | 0/0 | Not started | - |
