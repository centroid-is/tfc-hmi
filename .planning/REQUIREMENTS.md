# Requirements: v2.0 Advantys STB I/O Assets

**Milestone:** v2.0
**Defined:** 2026-05-11
**Sources:** `.planning/research/SUMMARY.md` (synthesizing STACK / FEATURES / ARCHITECTURE / PITFALLS) + user-locked decisions from milestone kickoff.

> **Naming note**: Centroid operators call these "Modicon Momentum" but Schneider's catalog uses the **Advantys STB** family name. All requirements use the catalog-correct `STB...` prefix. Asset-picker label is at the planner's discretion.

## v1 Requirements (Active scope)

Grouped by module. Every requirement maps to an existing Beckhoff parity surface (per the FEATURES research lane).

### Stack Composition (5 reqs)

- [ ] **STACK-01** — `AdvantysSTBStackConfig` extends `BaseAsset`, registered in `AssetRegistry` (both `_fromJsonFactories` and `defaultFactories`)
- [ ] **STACK-02** — Holds polymorphic `List<Asset> subdevices` via `@AssetListConverter()` (mirror CX5010 verbatim)
- [ ] **STACK-03** — `allKeys` override flat-maps each subdevice's `allKeys` + recursive subdevices' keys; preserves de-duplication and empty-filter semantics
- [ ] **STACK-04** — Reorderable subdevice list in the configure dialog with filtered "Add" dropdown — only the 4 STB module types selectable
- [ ] **STACK-05** — Post-`fromJson` sanitiser rejects foreign child types (whitelist enforcement); permissive renderer, restrictive add

### NIP2311 Head (4 reqs)

- [ ] **NIP-01** — `STBNIP2311Config` extends `BaseAsset` + registered in registry
- [ ] **NIP-02** — Painter: body + dual RJ45 ports (reuse `EthernetPortPainter` from `lib/painter/beckhoff/ek1100.dart`) + decorative status LED strip
- [ ] **NIP-03** — Status LEDs (RUN/PWR/ERR/ST/TEST) render decoratively in fixed "normal" state. **No PLC keys configurable per LED** (firmware-driven on real hardware — locked decision)
- [ ] **NIP-04** — JSON round-trip + JSON back-compat (legacy page without this asset still loads)

### PDT3100 Power (3 reqs)

- [ ] **PDT-01** — `STBPDT3100Config` extends `BaseAsset` + registered
- [ ] **PDT-02** — Painter: body + single LED bound to optional `inputOkKey` bool (green = OK, dim = unknown/disconnected)
- [ ] **PDT-03** — JSON round-trip + back-compat

### DDI3725 16-Ch Digital Input (10 reqs)

- [ ] **DDI-01** — `STBDDI3725Config` extends `BaseAsset` + registered
- [ ] **DDI-02** — Painter: body + 16-LED grid in **2×8 column-major layout** (channels 1–8 LEFT column top-to-bottom, channels 9–16 RIGHT column top-to-bottom) + RDY indicator + dual terminal blocks (A/B, 18 pos each — per photo, NOT the inaccurate DXF)
- [ ] **DDI-03** — `IO16LedBlockPainter extends BaseLedBlockPainter` at `lib/painter/advantys_stb/io16.dart` (sibling to `io8.dart`, NOT parameterised)
- [ ] **DDI-04** — Bitmask-driven channel state from `rawStateKey` (uint16; bit i = channel i+1). Bit-ordering convention LOCKED before goldens with a unit test (research-flagged: confirm LSB-first vs MSB-first with backend during Plan 01)
- [ ] **DDI-05** — Per-channel force-override via `forceValuesKey` (auto / forcedLow / forcedHigh). **Force collapses raw state** in display (matches EL1008 behavior — locked decision; NO corner pip for raw-under-force in v2.0)
- [ ] **DDI-06** — Per-channel ON filter ms via `onFiltersKey` (uint16[16])
- [ ] **DDI-07** — Per-channel OFF filter ms via `offFiltersKey` (uint16[16])
- [ ] **DDI-08** — Per-channel descriptions via `descriptionsKey` (string[16])
- [ ] **DDI-09** — Tap-to-open detail dialog: 8 rows of 2-column `RowIOView` (vs 4 rows × 2 in EL1008); each row shows channel state, force segmented-button, filter inputs, description text field
- [ ] **DDI-10** — JSON round-trip + back-compat + leak test (mount/unmount = clean disposal of `AnimationController`, `ValueNotifier`, stream subscription)

### DDO3705 16-Ch Digital Output (9 reqs)

- [ ] **DDO-01** — `STBDDO3705Config` extends `BaseAsset` + registered
- [ ] **DDO-02** — Painter reuses `IO16LedBlockPainter` from DDI; module body has its own painter at `lib/painter/advantys_stb/ddo3705.dart` with output-style LED legend
- [ ] **DDO-03** — Bitmask state from `rawStateKey` (uint16; bit-ordering MUST match the constant locked in DDI-04)
- [ ] **DDO-04** — Per-channel force-override via `forceValuesKey` (same encoding as DDI). Operator can manually write forced state via the SegmentedButton in detail dialog (existing EL2008 path)
- [ ] **DDO-05** — Per-channel descriptions via `descriptionsKey`
- [ ] **DDO-06** — Tap-to-open detail dialog mirrors DDI's structure but omits filter rows (outputs don't have filters)
- [ ] **DDO-07** — JSON round-trip + back-compat + leak test
- [ ] **DDO-08** — Visual differentiates output from input (LED legend strip + label color) but shares the base body painter — golden tests confirm visual distinction
- [ ] **DDO-09** — Manual force-write path verified end-to-end (operator drag-to-force in dialog → StateMan write → painter reflects)

### Cross-cutting / Quality (7 reqs)

- [ ] **QUAL-01** — Golden tests verify painters against DXF + photo references. References at `.planning/research/dxf/` + `.planning/research/photos/`. macOS-gated. Light + dark theme pair per module = ~14 PNGs minimum
- [ ] **QUAL-02** — Schneider cream body color fixed (NOT theme-driven); text outside the body uses `Theme.of(context).colorScheme.onSurface`
- [ ] **QUAL-03** — `_combinedStream` hoisted to `initState` (no per-rebuild resubscribe storm); cancelled in `dispose` (Pitfall M-03 prevention)
- [ ] **QUAL-04** — All new configs use `@JsonKey(defaultValue: ...)` or nullable fields so legacy saved pages round-trip (Pitfall M-06 prevention)
- [ ] **QUAL-05** — Each module wrapped in `GestureDetector(HitTestBehavior.opaque)` so taps register on the body, not transparent gaps in the painter
- [ ] **QUAL-06** — `flutter analyze` clean across all new files
- [ ] **QUAL-07** — Integration test: page with 1× AdvantysSTBStack containing 1× NIP + 1× PDT + 1× DDI + 1× DDO loads cleanly, all child keys discoverable via `stack.allKeys`, every painter renders, taps register

---

**v1 total: 38 requirements** (5 STACK + 4 NIP + 3 PDT + 10 DDI + 9 DDO + 7 QUAL)

## Future Requirements (Deferred to v2.1+)

- **NIP-FUT-01** — NIP MAC ID / IP address readout in detail dialog (string keys, read-only)
- **NIP-FUT-02** — Per-port Ethernet link/activity dot on RJ45 painter (bool key per port)
- **DDI-FUT-01** — Corner-pip raw-state-under-force indicator (3× more goldens per module; commissioning win)
- **STACK-FUT-01** — Multi-stack composition on a single page (multiple AdvantysSTBStack instances) + cross-stack alarm rollup
- **PAINTER-FUT-01** — Generalised `IONLedBlockPainter` parameterised by channel count; cover 4/8/16/32-channel modules uniformly
- **STACK-FUT-02** — Stack-level "disconnected" rollup state (any subdevice disconnected → stack frame goes amber)
- **STACK-FUT-03** — Canonical-layout enforcement (NIP must be first, PDT next to NIP, I/O modules in any order after) — currently free-form

## Out of Scope (explicit)

- **OOS-01** — Backend Modbus key plumbing. Assets consume opaque StateMan keys. The PLC-side address-to-key mapping is owned by whoever configures the Advantys STB device — NOT the HMI asset code
- **OOS-02** — Pixel-perfect Schneider trademark replication. Painter fidelity is "operator-recognizable" not photorealistic
- **OOS-03** — Per-channel current readback / wire-break diagnostics. Beckhoff doesn't have it either; would require a new state-key category and dialog row
- **OOS-04** — Group-of-8 fuse status. Schneider STB doesn't expose this as a standard surface
- **OOS-05** — Five separately-keyed NIP status LEDs. Real hardware doesn't expose RUN/PWR/ERR/ST/TEST individually over Modbus — they're firmware-internal indicators
- **OOS-06** — Three-LED-per-channel diagnostic rendering (force + raw + output-state pip). Defer to v2.1 if user demand surfaces
- **OOS-07** — Cross-cutting `BaseLedBlockPainter` refactor / promotion to `lib/painter/common/`. Brownfield refactor while shipping additive features is the anti-pattern; defer to a dedicated cleanup milestone

## Traceability

Every v1 requirement is mapped to exactly one phase. Plans are assigned during `/gsd-plan-phase`.

| REQ-ID | Phase | Plan | Status |
|--------|-------|------|--------|
| DDI-01 | Phase 1 | TBD | Pending |
| DDI-02 | Phase 1 | TBD | Pending |
| DDI-03 | Phase 1 | TBD | Pending |
| DDI-04 | Phase 1 | TBD | Pending |
| DDI-05 | Phase 1 | TBD | Pending |
| DDI-06 | Phase 1 | TBD | Pending |
| DDI-07 | Phase 1 | TBD | Pending |
| DDI-08 | Phase 1 | TBD | Pending |
| DDI-09 | Phase 1 | TBD | Pending |
| DDI-10 | Phase 1 | TBD | Pending |
| QUAL-01 | Phase 1 | TBD | Pending |
| QUAL-02 | Phase 1 | TBD | Pending |
| QUAL-03 | Phase 1 | TBD | Pending |
| QUAL-04 | Phase 1 | TBD | Pending |
| QUAL-05 | Phase 1 | TBD | Pending |
| DDO-01 | Phase 2 | TBD | Pending |
| DDO-02 | Phase 2 | TBD | Pending |
| DDO-03 | Phase 2 | TBD | Pending |
| DDO-04 | Phase 2 | TBD | Pending |
| DDO-05 | Phase 2 | TBD | Pending |
| DDO-06 | Phase 2 | TBD | Pending |
| DDO-07 | Phase 2 | TBD | Pending |
| DDO-08 | Phase 2 | TBD | Pending |
| DDO-09 | Phase 2 | TBD | Pending |
| NIP-01 | Phase 3 | TBD | Pending |
| NIP-02 | Phase 3 | TBD | Pending |
| NIP-03 | Phase 3 | TBD | Pending |
| NIP-04 | Phase 3 | TBD | Pending |
| PDT-01 | Phase 4 | TBD | Pending |
| PDT-02 | Phase 4 | TBD | Pending |
| PDT-03 | Phase 4 | TBD | Pending |
| STACK-01 | Phase 5 | TBD | Pending |
| STACK-02 | Phase 5 | TBD | Pending |
| STACK-03 | Phase 5 | TBD | Pending |
| STACK-04 | Phase 5 | TBD | Pending |
| STACK-05 | Phase 5 | TBD | Pending |
| QUAL-06 | Phase 5 | TBD | Pending |
| QUAL-07 | Phase 5 | TBD | Pending |

**Coverage: 38 / 38 v1 requirements mapped (100%). No orphans, no duplicates.**

### Coverage by Phase

| Phase | Requirement Count | REQ-IDs |
|-------|-------------------|---------|
| Phase 1 (STBDDI3725) | 15 | DDI-01..10, QUAL-01..05 |
| Phase 2 (STBDDO3705) | 9 | DDO-01..09 |
| Phase 3 (STBNIP2311) | 4 | NIP-01..04 |
| Phase 4 (STBPDT3100) | 3 | PDT-01..03 |
| Phase 5 (AdvantysSTBStack) | 7 | STACK-01..05, QUAL-06, QUAL-07 |
| **Total** | **38** | |

**Rationale for QUAL allocation:** QUAL-01 through QUAL-05 land in Phase 1 because Phase 1 is the convention-locking phase — golden harness, cream-body discipline, combined-stream hoisting, @JsonKey defaults, and GestureDetector wrapping are all established there and inherited by Phases 2–4 automatically. QUAL-06 (`flutter analyze` clean) and QUAL-07 (full-stack integration test) land in Phase 5 because that is the final integration verifier — the integration test requires all four module types to exist, and the analyze gate is enforced once across the complete milestone footprint.

---

*Generated 2026-05-11 from research SUMMARY.md + 3 user-locked decisions (naming → STB; force LED → collapse; NIP LEDs → decorative-only). Traceability filled 2026-05-11 during roadmapping.*
