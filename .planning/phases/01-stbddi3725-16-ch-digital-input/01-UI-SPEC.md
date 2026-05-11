# Phase 1 UI-SPEC: STBDDI3725 (16-Ch Digital Input)

**Source:** Beckhoff parity — `lib/page_creator/assets/beckhoff.dart` BeckhoffEL1008Config + `lib/painter/beckhoff/io8.dart` IO8Painter conventions, scaled to 16 channels and the Schneider Advantys STB form factor.

## Design Contract (locked)

### Tokens — All Inherited from Existing Codebase

| Token | Source | Value |
|-------|--------|-------|
| Body color | `lib/painter/beckhoff/io8.dart` `bodyColor` import | `Color(0xFFF0EDE5)` (Schneider/Beckhoff cream — visually indistinguishable) |
| LED palette | `lib/painter/beckhoff/io8.dart` `IOState` enum mapping | `low` = dim grey · `high` = green · `forcedLow` = red · `forcedHigh` = red+green stripe · `error/unknown` = grey |
| Spacing scale | Existing project `xs=4 sm=8 md=16 lg=24` (UI-SPEC convention from v1.0) | unchanged |
| Typography | `Theme.of(context).textTheme` | unchanged |
| Text-on-body | Schneider dark — `Color(0xFF1A1A1A)` (inherited from `lib/painter/beckhoff/io8.dart`) | unchanged |
| Text-on-surface | `Theme.of(context).colorScheme.onSurface` | unchanged (theme-driven) |

### Layout — STBDDI3725 Module Faceplate

Vertical from top to bottom (matches `.planning/research/photos/DDI3725_front_clean.png`):

1. **Top label strip** — Schneider blue band with "DDI3725" white text + tiny embedded RDY indicator
2. **LED block** — `IO16LedBlockPainter` in 2×8 column-major grid:
   - Left column: channels 1, 2, 3, 4, 5, 6, 7, 8 (top to bottom)
   - Right column: channels 9, 10, 11, 12, 13, 14, 15, 16 (top to bottom)
   - Each LED ≈ 8% body width × 4% body height
   - Numbered labels to the LEFT of each LED (left col) and RIGHT of each LED (right col) — bracketed by the LED
3. **Bottom blue accent strip** — separator before terminal blocks
4. **Dual terminal blocks** — Block A (left) and Block B (right), 18 positions each, per the photo (NOT the inaccurate DXF which shows 2×6)

Aspect ratio: ~107 × 152 mm (from `IO_BASE_DDI3725_DDO3705_mcadid0005033.dxf` bounding box).

### States

| State | Visual |
|-------|--------|
| Normal (some channels lit) | Green LEDs for high bits; dim grey for low |
| All off (rawStateKey = 0) | All LEDs dim grey; RDY green (module alive) |
| All on (rawStateKey = 0xFFFF) | All LEDs green; RDY green |
| Forced mix | Forced channels show red (low) / red+green stripe (high); raw state collapsed |
| Stale (no emission yet) | All LEDs dim grey; RDY dim grey; (no distinct disconnected variant) |

### Detail Dialog

- **Trigger:** Tap on module body (`GestureDetector(HitTestBehavior.opaque)`)
- **Layout:** AlertDialog or Dialog with `SingleChildScrollView` wrapping a `Column` of 8 `RowIOView` instances
- **Per-row content:** Channel pair `(i, i+8)` — two `RowIOView` columns side by side, each showing:
  - Channel index label
  - State indicator (matches main painter LED palette)
  - ON filter ms `TextFormField` (numeric, suffix "ms")
  - OFF filter ms `TextFormField` (numeric, suffix "ms")
  - Description `TextFormField`
  - Force `SegmentedButton` with three options: `auto` · `low` · `high`
- **Force write path:** Tapping `low`/`high` on the SegmentedButton writes to `forceValuesKey` via StateMan. Painter reflects in next frame.
- **Max height:** ~600px (typical EL1008 dialog ergonomics); scroll engages on overflow
- **Force pulse animation:** Red border pulses on rows with non-auto force values (reuse `TriangleBoxPainter` from `lib/page_creator/assets/beckhoff.dart`)

### Operator-Recognizability Targets (golden test acceptance criteria)

- Body silhouette + cream color + Schneider blue accent strip ≈ photo
- 2×8 column-major LED arrangement matches photo
- "DDI3725" label visible top-right (small)
- Dual terminal blocks visible (geometry inherited from photo — not pixel-accurate)
- Forced channels visually distinct from normal high/low (red vs green)
- Stale state visually distinct from all-off (RDY indicator carries this signal)

### Out of Scope (Locked)

- Pixel-perfect Schneider trademark / logo reproduction
- 1×16 single-column LED layout (we use 2×8 — column-major per photo)
- Corner-pip raw-state-under-force indicator (deferred to v2.1)
- Per-LED hover tooltip (not in EL1008 either)
- Theme-driven body color (cream is fixed — Schneider product identity)

---

**Status:** Locked. Design decisions are inherited Beckhoff parity + the user-confirmed photo references. Plan-phase consumes this as the visual contract.
