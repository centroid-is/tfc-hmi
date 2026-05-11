# Modicon Momentum CAD References (v2.0 milestone)

User-provided Schneider Electric CAD files (DXF / 2D-front views) for the four module faceplates. Used by painter implementation to capture relative proportions — body widths, terminal block spacing, LED positions, port placement. Not intended for pixel-perfect reproduction (per locked painter-fidelity decision: operator-recognizable, not pixel-accurate).

## Mapping (confirmed by user 2026-05-11)

| File | Module(s) | Bounding box | Source |
|------|-----------|--------------|--------|
| `NIP2311_mcadid0005722.dxf` | NIP2311 (Ethernet Modbus/TCP head adapter) | ~? (large — head module with status LEDs + dual RJ45) | Schneider 3D-simplified 2D-front export |
| `PDT3100_mcadid0005043.dxf` | PDT3100 (24V DC power distribution) | 115 × 162 mm | Schneider 2D-front export |
| `IO_BASE_DDI3725_DDO3705_mcadid0005033.dxf` | DDI3725 + DDO3705 (16-ch DI/DO — share base form factor) | 107 × 152 mm | Schneider 2D-front export |

## Usage during research / planning

- **gsd-project-researcher (architecture / stack lane):** Read the DXF text headers (`$EXTMIN` / `$EXTMAX`) for true bounding box. Cross-reference Schneider datasheets for verified module dimensions.
- **Plan-phase / painter implementation:** Extract relative landmarks (LED grid spacing, port offsets, terminal block geometry). Don't try to ingest the full vector path — the painter is hand-crafted in `CustomPainter`, the DXF just informs proportions.
- **Pattern source of truth (unchanged):** `lib/painter/beckhoff/io8.dart` (8-LED strip, scale up to 16) and `lib/painter/beckhoff/ek1100.dart` (head module body + Ethernet ports).
