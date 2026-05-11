# Phase 4: STBPDT3100 (Power Distribution) - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning
**Mode:** Autonomous smart-discuss (smallest module of the milestone)

<domain>
## Phase Boundary

Ship a `STBPDT3100Config` HMI asset for the Schneider Advantys STB 24V DC power distribution module. The module renders as a slim cream-bodied module with an "IN/OUT" label, a single LED indicator bound to an optional `inputOkKey` bool (green = OK, dim = unknown/disconnected/false), terminal blocks for the 24V DC input wiring, and a "24 VDC 0.55A" label. NO detail dialog (just a single bool — the configure dialog handles `inputOkKey` binding).

</domain>

<decisions>
## Implementation Decisions

### Visual Identity
- **Body cream color:** Same `bodyColor` import (Schneider cream).
- **Schneider accent blue:** Reuse from `_stbAccentBlue` constant (DDI3725 declared it).
- **Aspect ratio:** ~115×162 mm per PDT3100 DXF bounding box (taller and slightly wider than NIP2311).
- **Body layout** (top to bottom):
  1. **Top label strip** with "PDT3100" text
  2. **"IN" / "OUT" label area** (decorative — like the photo shows)
  3. **Single LED** bound to `inputOkKey` — labeled "INPUT" or unlabeled (planner picks; small green LED)
  4. **Schneider blue band**
  5. **Input terminal area** with "INPUT +" / "INPUT -" small labels
  6. **"24 VDC 0.55A" small text** + Schneider Electric footer

### Single LED State Mapping
- `inputOkKey` is optional (nullable) — if not configured, LED renders dim grey.
- If configured AND stream has emitted `true`: LED renders green.
- If configured AND stream has emitted `false` OR errored: LED renders dim grey.
- If configured AND stream has NOT emitted yet (stale): LED renders dim grey.
- **No distinction between fault, stale, and disconnected** — all render dim grey (consistent with Phases 1-2 collapse semantics).

### Configure Dialog
- **Exposes:** `nameOrId` + `inputOkKey` (KeyField, optional) + Coordinates + Size.

### Visual States (goldens)
- **`input_ok_light/dark`** — LED green
- **`fault_light/dark`** — LED dim grey (also serves as the stale/disconnected golden — single semantic class)

### Goldens
- **4 PNGs total** (2 states × 2 themes) at `test/page_creator/assets/goldens/advantys_stb/pdt3100_{input_ok,fault}_{light,dark}.png`.

### No Detail Dialog
- Tap behavior: same as NIP2311 (no detail dialog OR a minimal info dialog showing "Input OK status: green = OK, grey = fault/stale"). Planner picks. Default: no tap action.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `bodyColor`, `IOState` — `lib/painter/advantys_stb/io16.dart`
- `_stbAccentBlue` constant — declared in `lib/painter/advantys_stb/ddi3725.dart` (or local)
- `_combinedStream` pattern — single-key version, see other Phase 1-2 widgets (or use simple StreamBuilder<DynamicValue> since only one key)

### Established Patterns (from Phases 1-3)
- Single config file `lib/page_creator/assets/advantys_stb.dart` — Phase 4 APPENDS.
- Painter file per module: `lib/painter/advantys_stb/pdt3100.dart` NEW.
- Codegen: re-run `dart run build_runner build` after schema change.
- Tests: APPEND to `test/page_creator/assets/advantys_stb_test.dart`.

### Integration Points
- `lib/page_creator/assets/registry.dart` — add `STBPDT3100Config` to BOTH maps.

</code_context>

<specifics>
## Specific Ideas

- Photo reference: `.planning/research/photos/momentum_stack_in_panel.png` shows the PDT3100 (slim cream-bodied module immediately right of the NIP2311 head).
- The PDT3100 is narrower than DDI/DDO but taller than NIP. Aspect ratio matters less than operator recognition.

</specifics>

<deferred>
## Deferred Ideas

- Per-channel current readback (OOS-03).
- Group-of-8 fuse status (OOS-04).

</deferred>
