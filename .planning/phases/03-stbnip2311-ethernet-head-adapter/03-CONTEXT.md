# Phase 3: STBNIP2311 (Ethernet Head Adapter) - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning
**Mode:** Autonomous smart-discuss

<domain>
## Phase Boundary

Ship a `STBNIP2311Config` HMI asset for the Schneider Advantys STB Ethernet Modbus/TCP communications head adapter. The module renders as a smaller (compared to I/O modules) head module with cream body, dual RJ45 ports (reusing `EthernetPortPainter` from `lib/painter/beckhoff/ek1100.dart`), and a row of five decorative status LEDs labeled RUN / PWR / ERR / ST / TEST rendered in fixed "normal" state. There are NO per-LED PLC keys (firmware-driven on real hardware; locked decision). The configure dialog exposes only `nameOrId` + standard `Coordinates`/`Size`.

This phase establishes the head-module visual identity for the milestone and confirms the cross-vendor `EthernetPortPainter` reuse pattern works cleanly.

</domain>

<decisions>
## Implementation Decisions

### Visual Identity
- **Body cream color:** Same `bodyColor` import as Phases 1-2 (Schneider cream).
- **Schneider accent blue:** Reuse `_stbAccentBlue = Color(0xFF003B71)` from `ddi3725.dart` or declare locally in `nip2311.dart` (planner picks; either works).
- **Aspect ratio:** Per NIP2311 DXF bounding box (~58×82 mm — smaller than I/O modules' 107×152). Width-to-height ratio ≈ 0.71.
- **Body layout** (top to bottom, per `.planning/research/photos/momentum_stack_in_panel.png`):
  1. **Top label strip** with "NIP2311" text and small MAC ID display area (purely decorative — no live MAC readout in v2.0)
  2. **Status LED strip** — 5 LEDs in a vertical column labeled RUN / PWR / ERR / ST / TEST. Render in "normal" state: RUN/PWR green, ERR/ST/TEST dim grey.
  3. **Schneider blue band** with "Ethernet Modbus/TCP 10/100T" subtitle text
  4. **Dual RJ45 ports** rendered via `EthernetPortPainter` (reused verbatim from `lib/painter/beckhoff/ek1100.dart`) — two ports stacked vertically
  5. **Bottom power input area** with "24 VDC 0.55A" small text + "Schneider Electric" footer

### Status LEDs — Decorative-Only (LOCKED)
- **No PLC keys per LED.** Status LEDs are firmware-driven on the actual hardware (NIP firmware controls RUN/PWR/ERR/ST/TEST internally; they are NOT addressable Modbus coils). The HMI asset renders them in a fixed "normal" state.
- **Fixed normal state:** RUN = green, PWR = green, ERR = dim grey, ST = dim grey, TEST = dim grey.
- **Rationale:** Operators inspect the physical device for true status. The HMI asset is the visual identity anchor, not a live status surface.

### Ethernet Ports
- **Reuse `EthernetPortPainter`** from `lib/painter/beckhoff/ek1100.dart` verbatim. Cross-vendor reuse is intentional — the RJ45 jack glyph is a Schneider-and-Beckhoff-shared visual.
- **No link/activity LEDs in v2.0.** The painter renders the port outline + pin layout only. Live link/activity is NIP-FUT-02 (deferred to v2.1).
- **Layout:** Two ports stacked vertically (NOT side-by-side as on EK1100) — matches the NIP2311 physical layout where the two RJ45 jacks are one above the other.

### Configure Dialog
- **Exposes only:** `nameOrId` (TextField), `Coordinates`, `Size`. NO state-key fields (no `runKey`, `pwrKey`, etc. — decorative only).
- **No tap-to-open detail dialog** — the runtime widget is purely decorative. Tap could optionally show a help dialog explaining "Status LEDs reflect physical device firmware, not PLC state" but defer to keep scope minimal. Planner picks: either no onTap (silently absorb) or simple info dialog.

### Visual States
- **Single render state.** No stale/disconnected variant since no live keys. The painter ALWAYS renders RUN/PWR green + others dim grey.

### Goldens
- **2 PNGs** (light + dark theme of the single "normal" state) at `test/page_creator/assets/goldens/advantys_stb/nip2311_normal_{light,dark}.png`.

### Claude's Discretion
- Whether to show a help dialog onTap (informational only) or have no onTap at all.
- Exact MAC ID display area treatment — could be a fixed placeholder "MAC ID: XX:XX:XX:XX:XX:XX" or just an empty rectangle. Decorative only.
- Status LED size and spacing within the LED strip — match photo proportions as best as practical.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `EthernetPortPainter` — `lib/painter/beckhoff/ek1100.dart`. Verbatim reuse. Public class.
- `bodyColor` — `lib/painter/advantys_stb/io16.dart` (re-export from beckhoff/io8.dart).
- `_stbAccentBlue` constant — locally declared in `ddi3725.dart` or `ddo3705.dart`.
- `STBNIP2311Config` — NEW; append to `lib/page_creator/assets/advantys_stb.dart`.

### Established Patterns (from Phases 1-2)
- Single config file `lib/page_creator/assets/advantys_stb.dart` — Phase 3 APPENDS.
- Painter file per module: `lib/painter/advantys_stb/nip2311.dart` NEW.
- Codegen: re-run `dart run build_runner build` after schema change.
- Tests: APPEND to `test/page_creator/assets/advantys_stb_test.dart`.
- Goldens: 2 PNGs (single state × 2 themes).

### Integration Points
- `lib/page_creator/assets/registry.dart` — add `STBNIP2311Config` to BOTH maps.

</code_context>

<specifics>
## Specific Ideas

- Status LED label rendering: 5 short uppercase labels ("RUN", "PWR", "ERR", "ST", "TEST") to the right of each LED dot. Use `TextPainter` for crisp text.
- The "Schneider Electric" footer text + "24 VDC 0.55A" small print is purely decorative — keep it small and unobtrusive.
- Operator-recognizability test: golden visually matches the user's photo at `.planning/research/photos/momentum_stack_in_panel.png` (NIP2311 is the white-bodied module to the right of the Eaton breaker).

</specifics>

<deferred>
## Deferred Ideas

- Live status LED bindings to one synthetic "comm OK" key (NIP-FUT-01).
- MAC ID / IP address readout in detail dialog (NIP-FUT-01).
- Per-port Ethernet link/activity LEDs (NIP-FUT-02).

</deferred>
