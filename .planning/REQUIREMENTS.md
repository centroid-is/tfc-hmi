# Requirements: ConveyorGate Asset

**Defined:** 2026-03-07
**Core Value:** Operators can see at a glance whether each gate along a conveyor line is open, closed, or being forced — with realistic animated visuals matching physical equipment

## v1 Requirements

### Painter Variants

- [x] **PAINT-01**: ConveyorGateConfig with variant enum (pneumatic, slider, pusher) and JSON serialization
- [x] **PAINT-02**: Pneumatic diverter painter showing cylinder body, extending rod, and hinged flap
- [x] **PAINT-03**: Configurable opening angle for diverter flap (default 45 degrees)
- [x] **PAINT-04**: Slider painter showing horizontal plate sliding sideways to reveal opening
- [x] **PAINT-05**: Pusher painter showing cylinder with flat blade extending perpendicular to flow
- [x] **PAINT-06**: Left/right side selection for gate orientation

### Animation

- [x] **ANIM-01**: Animated open/close transition using AnimationController with repaint listenable
- [x] **ANIM-02**: Configurable open time (default 0.8 seconds)
- [x] **ANIM-03**: Optional close time (defaults to open time if not set)
- [x] **ANIM-04**: Performance-optimized painting (no setState per frame, shouldRepaint comparing only state fields)

### Data Binding

- [x] **DATA-01**: Required OPC UA key for open/close state (bool subscription via StateManager)
- [x] **DATA-02**: Optional force open key (write command)
- [x] **DATA-03**: Optional force open active feedback key (read subscription)
- [x] **DATA-04**: Optional force close key (write command)
- [x] **DATA-05**: Optional force close active feedback key (read subscription)
- [x] **DATA-06**: Grey color when no data/disconnected

### Visual Config

- [x] **VIS-01**: Configurable active/open color with color picker (default green)
- [x] **VIS-02**: Configurable closed color with color picker (default white)
- [x] **VIS-03**: Forced state color from Flutter theme colorScheme (dark/light mode compatible)
- [x] **VIS-04**: Color picker UI reusing flutter_colorpicker pattern from GraphAsset

### Interaction

- [x] **INT-01**: Gate clickable only when force open/close keys are configured; otherwise display-only
- [x] **INT-02**: Click opens dialog with force open and force close buttons (reusing ButtonConfig asset)
- [x] **INT-03**: Dialog buttons show active feedback state from OPC UA subscriptions

### Standalone Mode

- [x] **SOLO-01**: Asset placed directly on page with normal RelativeSize and Coordinates
- [x] **SOLO-02**: Rotation support via LayoutRotatedBox and coordinates angle
- [x] **SOLO-03**: Asset registry integration (fromJson factory and preview factory)
- [x] **SOLO-04**: Configuration dialog for all gate properties (keys, variant, side, angle, timing, colors)

### Child-of-Conveyor Mode

- [x] **CHILD-01**: ConveyorConfig updated with gates list (subdevices pattern from EK1100)
- [x] **CHILD-02**: Gate position as fraction (0.0-1.0) along conveyor belt length
- [ ] **CHILD-03**: Gate scales from conveyor dimensions (flap spans belt width)
- [ ] **CHILD-04**: Pneumatic cylinder extends outside conveyor bounding box visually
- [ ] **CHILD-05**: Gate has own click target opening its own config dialog (separate from conveyor click)
- [ ] **CHILD-06**: Conveyor config dialog supports adding/removing/managing child gates

## v2 Requirements

### Enhanced Interaction

- **ENH-01**: Sidebar config panel as alternative to dialog
- **ENH-02**: Partial/proportional gate opening (metered position, not just binary)

### Diagnostics

- **DIAG-01**: Gate cycle count display
- **DIAG-02**: Gate fault/error state visualization

## Out of Scope

| Feature | Reason |
|---------|--------|
| 3D visualization | 2D CustomPainter only, consistent with all other assets |
| Partial/proportional opening | Gates are binary (open/closed) for v1; metered position is v2 |
| Sidebar config panel | Start with dialog; sidebar is a later discussion |
| Gate-to-gate interaction | No chain reactions or batch handoff between gates |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PAINT-01 | Phase 1 | Complete |
| PAINT-02 | Phase 1 | Complete |
| PAINT-03 | Phase 1 | Complete |
| PAINT-04 | Phase 2 | Complete |
| PAINT-05 | Phase 2 | Complete |
| PAINT-06 | Phase 1 | Complete |
| ANIM-01 | Phase 1 | Complete |
| ANIM-02 | Phase 1 | Complete |
| ANIM-03 | Phase 1 | Complete |
| ANIM-04 | Phase 1 | Complete |
| DATA-01 | Phase 1 | Complete |
| DATA-02 | Phase 2 | Complete |
| DATA-03 | Phase 2 | Complete |
| DATA-04 | Phase 2 | Complete |
| DATA-05 | Phase 2 | Complete |
| DATA-06 | Phase 1 | Complete |
| VIS-01 | Phase 1 | Complete |
| VIS-02 | Phase 1 | Complete |
| VIS-03 | Phase 2 | Complete |
| VIS-04 | Phase 2 | Complete |
| INT-01 | Phase 2 | Complete |
| INT-02 | Phase 2 | Complete |
| INT-03 | Phase 2 | Complete |
| SOLO-01 | Phase 1 | Complete |
| SOLO-02 | Phase 1 | Complete |
| SOLO-03 | Phase 1 | Complete |
| SOLO-04 | Phase 1 | Complete |
| CHILD-01 | Phase 3 | Complete |
| CHILD-02 | Phase 3 | Complete |
| CHILD-03 | Phase 3 | Pending |
| CHILD-04 | Phase 3 | Pending |
| CHILD-05 | Phase 3 | Pending |
| CHILD-06 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 33 total
- Mapped to phases: 33
- Unmapped: 0

---
*Requirements defined: 2026-03-07*
*Last updated: 2026-03-07 after roadmap phase mapping*
