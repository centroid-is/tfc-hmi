---
phase: 01-stbddi3725-16-ch-digital-input
plan: 02
subsystem: ui
tags: [flutter, custompainter, advantys-stb, schneider, ddi3725, goldens, riverpod, tdd]

# Dependency graph
requires:
  - phase: 01-01
    provides: IO16LedBlockPainter + kSTBChannelBitOrder + bitmaskToLedStates + bodyColor re-export
provides:
  - STBDDI3725Config (@JsonSerializable, 5 nullable *Key fields + nameOrId)
  - STBDDI3725 build()/configure() (FittedBox + _STBDDI3725 ConsumerStatefulWidget + 5-KeyField editor body)
  - _combinedStream hoisted to initState (QUAL-03 / PITFALL M-03 contract)
  - STBDDI3725BodyPainter (cream body + blue strips + RDY indicator + dual terminal blocks + disconnected exclamation)
  - STBDDI3725Widget (AnimatedWidget wrapper, aspect 107×152)
  - stbAccentBlue constant (Color(0xFF003B71) — exported for Phase 2/3 reuse)
  - 10 PNG goldens (5 states × 2 themes) under test/page_creator/assets/goldens/advantys_stb/
affects: [01-03, 01-04, 02-stbddo3705, 03-stbnip2311, 04-stbpdt3100, 05-advantys-stb-stack]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Stream hoisting via `late`-able nullable + setState in `then` callback after stateManProvider future resolves — replaces beckhoff.dart's per-build stream reconstruction (QUAL-03)"
    - "DDI body painter delegates LED render to IO16LedBlockPainter via canvas.save/translate/restore — same shape as IO8Painter at io8.dart:228-244"
    - "Schneider blue accent (Color(0xFF003B71)) exported as stbAccentBlue from ddi3725.dart — Phase 2/3 import via show stbAccentBlue"
    - "Force array extracted from DynamicValue.asArray (CONTEXT.md D-ForceValues int8[16] wire format) — silently nulls back to raw-only render if the wire arrives as a packed int (Beckhoff convention), surfaced as a carry-forward for backend confirmation"
    - "macOS-gated golden group via `skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null` (QUAL-01)"
    - "Test pattern for editor body with KeyField/stateManProvider: ProviderScope + ElevatedButton + showDialog without resolving providers — KeyField pumps a placeholder so the surface is still findable"

key-files:
  created:
    - lib/page_creator/assets/advantys_stb.dart
    - lib/page_creator/assets/advantys_stb.g.dart
    - lib/painter/advantys_stb/ddi3725.dart
    - test/page_creator/assets/goldens/advantys_stb/ddi3725_all_off_light.png
    - test/page_creator/assets/goldens/advantys_stb/ddi3725_all_off_dark.png
    - test/page_creator/assets/goldens/advantys_stb/ddi3725_all_on_light.png
    - test/page_creator/assets/goldens/advantys_stb/ddi3725_all_on_dark.png
    - test/page_creator/assets/goldens/advantys_stb/ddi3725_alternating_0xAAAA_light.png
    - test/page_creator/assets/goldens/advantys_stb/ddi3725_alternating_0xAAAA_dark.png
    - test/page_creator/assets/goldens/advantys_stb/ddi3725_forced_mix_light.png
    - test/page_creator/assets/goldens/advantys_stb/ddi3725_forced_mix_dark.png
    - test/page_creator/assets/goldens/advantys_stb/ddi3725_disconnected_light.png
    - test/page_creator/assets/goldens/advantys_stb/ddi3725_disconnected_dark.png
  modified:
    - test/page_creator/assets/advantys_stb_test.dart  (appended 4 new groups + 1 _DummyDDI3725Painter helper)
    - lib/painter/advantys_stb/io16.dart  (Rule 1 auto-fix — see Deviations)

key-decisions:
  - "Task 4 bit-order checkpoint AUTO-RESOLVED to option-a (LSB-first per CONTEXT.md). Backend confirmation still TODO — flipping to MSB-first is one constant flip in io16.dart + three test-expectation updates in advantys_stb_test.dart + regeneration of the alternating_0xAAAA goldens (only)."
  - "Force-collapse semantic verified visually: forced_mix golden shows ch1 grey (forced=1 collapsed raw=high) and ch3 green (forced=2). Animation-driven red border (BaseLedBlockPainter.drawLed) is alpha=0 at AlwaysStoppedAnimation(0), so static goldens won't show the red pulse — this matches the Beckhoff EL1008 convention by design."
  - "DDI body painter delegates LED render to IO16LedBlockPainter; the body owns chrome (cream fill, blue strips, terminal blocks, disconnected overlay) but never duplicates LED math. Phase 2 DDO3705 will reuse the body painter shape with a delta in title text + LED palette."
  - "Force-values wire format guarded by _forceArrayFromDynamicValue: if dv.isArray==false, returns null and the LED block silently renders raw-only. This is the M-04/M-02 trip-wire; the commissioning-time fix is at the backend (align int8[16] convention with CONTEXT.md), not in the painter."

patterns-established:
  - "Per-module body painter convention: top blue strip + LED block delegate + bottom blue accent + dual terminal block — Phase 2 DDO3705 clones with name/LED-state delta only"
  - "ConsumerStatefulWidget for stream hoisting: nullable cached stream, set in `then` callback after stateManProvider future resolves; build() reads the cache and never reconstructs"
  - "GestureDetector(HitTestBehavior.opaque) wrapping the entire module body so taps register on transparent gaps between LEDs and terminal-block columns (QUAL-05)"

requirements-completed: [DDI-01, DDI-02, DDI-08, QUAL-01, QUAL-02, QUAL-03, QUAL-05]

# Metrics
duration: 14min
completed: 2026-05-11
---

# Phase 1 Plan 02: STBDDI3725Config + Body Painter + 10 Goldens — Summary

**`STBDDI3725Config` data class + JSON round-trip + `_STBDDI3725` ConsumerStatefulWidget with hoisted combined stream + `STBDDI3725BodyPainter` (cream module body + dual terminal blocks via the photo, NOT the inaccurate DXF) + 5-KeyField editor body + 10 PNG goldens covering 5 states × 2 themes, all gated by 24 RED→GREEN tests on top of Plan 01's 9.**

## Performance

- **Duration:** ~14 min
- **Started:** 2026-05-11T16:25:06Z
- **Completed:** 2026-05-11T16:39:06Z
- **Tasks:** 5 (4 implementation + 1 auto-resolved checkpoint)
- **Files changed:** 14 (4 created, 1 g.dart generated, 1 modified, 10 PNG goldens)

## Accomplishments

- Shipped the `STBDDI3725Config` HMI asset class: five nullable state keys (raw bitmask + force values + on/off filter ms + descriptions) + `nameOrId` defaulting to `'1'` for back-compat. `BaseAsset.allKeys` regex picks up all five `*Key` fields automatically — no override needed.
- Built `STBDDI3725BodyPainter` + `STBDDI3725Widget` with the locked layout: cream body, top blue label strip with "DDI3725" + RDY indicator, LED block (delegated to `IO16LedBlockPainter`), bottom blue accent, dual 2×18 terminal blocks per the canonical photo (NOT the inaccurate DXF). Disconnected overlay (red exclamation) mirrors `IO8Painter`.
- Hoisted `_combinedStream` to `initState` (QUAL-03 / PITFALL M-03): cached in a nullable field, set once after `stateManProvider.future` resolves in `then`, read by `build()` without ever reconstructing. The widget is wrapped in `GestureDetector(HitTestBehavior.opaque)` (QUAL-05) so taps register on transparent gaps between LEDs and terminal-block columns.
- Wired `STBDDI3725Config.configure(context)` to a 5-`KeyField` editor body (Raw State, Force Values, On Filters, Off Filters, Descriptions) + `Name or ID` + `SizeField` + `CoordinatesField`. Identical envelope to `BeckhoffEL1008Config.configure` minus the `processedStateKey` field.
- Captured the 10-PNG golden matrix (5 states × 2 themes). The QUAL-02 cream-body invariant is visually confirmed: `ddi3725_all_off_light.png` and `ddi3725_all_off_dark.png` are body-pixel-identical because `bodyColor` is fixed, only outside-surface text is theme-driven.
- Auto-resolved the Task 4 bit-order checkpoint to option-a (LSB-first per the CONTEXT.md locked default). Backend confirmation is still TODO; if Schneider's wire format turns out to be MSB-first the cost is one constant flip + three test-expectation edits + regeneration of the two `alternating_0xAAAA` goldens. Painter math is unchanged.

## Task Commits

Each task was committed atomically on `worktree-agent-ad0a2f5b`:

1. **Task 1 — RED + GREEN: data shape + JSON round-trip** — `cc891db` (`feat`)
2. **Task 2 — RED + GREEN: body painter + AnimatedWidget + ConsumerStatefulWidget glue** — `f9f830c` (`feat`)
3. **Task 3 — RED + GREEN: editor surface lock (5 KeyFields)** — `ebbaa2f` (`test`)
4. **Task 4 — Auto-resolved checkpoint (no commit; documented in SUMMARY)** — (no hash)
5. **Task 5 — GREEN: 10 PNG goldens + io16.dart Rule-1 auto-fix** — `6db8b53` (`feat`)

TDD discipline: RED-first writes failed compilation / unmet assertion, then GREEN landed alongside. Task 3 was a special case where `configure()` was implemented up-front in Task 1's file write (since both editor + data class live in the same file and codegen needs them together), so the editor-surface test functioned as a "lock the surface that landed" assertion rather than a true RED→GREEN cycle. Documented inline.

## Files Created / Modified

### Created

- `lib/page_creator/assets/advantys_stb.dart` (~370 LoC) — `STBDDI3725Config` (`@JsonSerializable`, 5 `*Key` fields + `nameOrId`), `_STBDDI3725` `ConsumerStatefulWidget` (hoisted combined stream), `_STBDDI3725ConfigEditor` (5-`KeyField` editor body), `_combinedStream` helper (verbatim from beckhoff.dart per ARCHITECTURE §9.3), `_forceArrayFromDynamicValue` helper (CONTEXT D-ForceValues int8[16] extraction with M-04 trip-wire).
- `lib/page_creator/assets/advantys_stb.g.dart` (~50 LoC) — `_$STBDDI3725ConfigFromJson` + `_$STBDDI3725ConfigToJson` via `json_serializable`.
- `lib/painter/advantys_stb/ddi3725.dart` (~245 LoC) — `STBDDI3725Widget` (`AnimatedWidget`, aspect 107×152), `STBDDI3725BodyPainter` (cream body + blue strips + RDY indicator + dual terminal blocks + disconnected overlay), `stbAccentBlue` constant exported.
- 10 PNG goldens under `test/page_creator/assets/goldens/advantys_stb/`.

### Modified

- `test/page_creator/assets/advantys_stb_test.dart` (+~280 LoC) — appended 4 new groups (`STBDDI3725Config — data shape`, `STBDDI3725BodyPainter shouldRepaint contract`, `STBDDI3725Config.configure — editor surface`, `STBDDI3725Widget — mount sanity`, `STBDDI3725 goldens`) + 1 `_DummyDDI3725Painter` helper. 33 tests pass total (24 new + 9 from Plan 01).
- `lib/painter/advantys_stb/io16.dart` — `IO16LedBlockPainter.drawLeds` auto-fixed for wide-flat regions (see Deviations).

## Decisions Made

- **LSB-first auto-resolved at Task 4 checkpoint** — Per the autonomous-mode instruction in the executor prompt, the Task 4 bit-order decision was auto-set to option-a (LSB-first per CONTEXT.md). Backend confirmation is still pending; the cost of flipping to MSB-first is documented in the `TODO(stb-bit-order)` comment that ships in `advantys_stb_test.dart` (one constant edit in `io16.dart` + three test-line edits + regeneration of the two `alternating_0xAAAA` goldens).
- **Force-collapse semantic visualised via fill colour, not animated border** — `bitmaskToLedStates` (Plan 01) maps `forceValues[i] == 1` → `IOState.forcedLow` and `== 2` → `IOState.forcedHigh`. The `BaseLedBlockPainter.drawLed` (`lib/painter/beckhoff/io8.dart`) renders `forcedHigh`'s fill as `Color(0xFF6CA545)` (same as `high`) and `forcedLow`'s fill as the grey gradient (same as `low`). The distinction comes from the animated red border (`Colors.red.withAlpha(animation.value)`); static goldens with `AlwaysStoppedAnimation(0)` set alpha=0 so no red border is visible. This matches Beckhoff EL1008's convention by design — confirmed visually in `ddi3725_forced_mix_light.png` (ch1 fill=grey from force=1 collapse, ch3 fill=green from force=2).
- **DDI body painter does not duplicate LED math** — body owns chrome, delegates LED render to `IO16LedBlockPainter` via `canvas.save/translate/restore`. Phase 2 DDO3705 will reuse this delegation shape with a label-text + LED-state delta only. Phase 3 NIP2311 and Phase 4 PDT3100 inherit the cream-body / blue-accent / terminal-block conventions wholesale.
- **`_combinedStream` cached in nullable field, not `late final`** — `late final` would require initialisation before first read, but the StateMan future resolves asynchronously. Using `Stream<...>? _combinedStreamCache` and `setState`-ing it inside the `.then` callback is the safest hoisting pattern: `build()` checks `null` and renders a stale shell while the future is pending, then re-renders once cached. Matches the spirit of QUAL-03 — never reconstructed in `build()`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Plan 01's `IO16LedBlockPainter.drawLeds` mis-laid out for wide-flat regions (DDI3725 LED block ≈ 200 × 66 px)**

- **Found during:** Task 5 (visual inspection of first-pass goldens — `all_off_light.png`, `all_on_light.png`, `alternating_0xAAAA_light.png` rendered as just two solid grey rectangles instead of 16 LEDs).
- **Issue:** Plan 01's `drawLeds` used `pad = size.width * 0.05` for both x and y axes (mirroring the IO8 / IO6 sibling painters whose blocks are tall-narrow and square-ish, where the isotropic pad works). For DDI3725's wide-flat LED block (200 wide × 66 tall, 2 cols × 8 rows), the y-pad of `200 * 0.05 = 10 px` × 9 gutters = 90 px, exceeding the 66 px block height → `cellH` resolves negative and the cells either don't render or are overpainted by the border stroke (which itself was `size.width * 0.03 = 6 px`, larger than the per-cell ~4 px gap → the entire LED area renders as the border-grey colour). Net visual: the 16 LEDs collapse into two solid rectangles. The bug doesn't trip in Plan 01's unit tests because those test `bitmaskToLedStates` math only, not the painter's pixel-layout.
- **Fix (single-file, isolated, in `lib/painter/advantys_stb/io16.dart`):**
  - Decoupled x and y pads: `padX = size.width * 0.05`, `padY = size.height * 0.05`. Restores correct cell geometry for both square-ish and wide-flat regions.
  - Clamped the LED-border stroke: `strokeWidth = min(size.width * 0.03, min(cellW, cellH) * 0.12)`. Prevents the border from overpainting the fill in flat regions. IO8 / IO6 callers see a no-op because their stroke was already <<12% of their cells.
  - Documented the rationale inline (multi-line comment in `drawLeds`).
- **Verification:**
  - Re-ran `flutter test test/page_creator/assets/advantys_stb_test.dart` → all 9 Plan 01 bit-mapping tests still pass (math is unchanged; only geometry was touched).
  - Re-generated goldens via `flutter test --update-goldens` → `all_off_light.png` shows 16 distinct grey LEDs, `all_on_light.png` shows 16 GREEN LEDs in a 2×8 column-major grid, `alternating_0xAAAA_light.png` shows correct LSB-first odd-index lit pattern (channels 2,4,6,8 lit left column, 10,12,14,16 lit right column).
  - `flutter test test/page_creator/assets/advantys_stb_test.dart` (no `--update-goldens`) → all 10 goldens byte-match.
- **Files modified:** `lib/painter/advantys_stb/io16.dart` (one method body — `drawLeds`).
- **Committed in:** `6db8b53` (Task 5 commit).

### Other Observations

**2. [Note — not a fix] Force-collapse visual distinction relies on animated red border**

- The Beckhoff convention (inherited by `BaseLedBlockPainter.drawLed`) marks forced channels with an alpha-animated red border. With `AlwaysStoppedAnimation(0)` (the static golden harness), the alpha is 0 and no red is visible. Force-collapse IS still visible in goldens because the fill colour changes (forcedLow → grey, forcedHigh → green), but unforced-high vs forcedHigh are visually identical in static frames.
- **Implication for goldens:** `ddi3725_forced_mix_light.png` correctly shows ch1 grey (forced=1 collapsing raw=high) and ch3 green (forced=2). The "this channel is forced, not just live-high" visual distinction is animation-only, which matches Beckhoff EL1008 behaviour.
- **Not a deviation** — this matches the Plan 01 contract and is documented in the SUMMARY.

### Worktree branch base reset (procedural, not a code change)

The worktree (`worktree-agent-ad0a2f5b`) was initially branched from `4bbede3` (UMAS hardening merge on `main`), which predates Plan 01's `90140b5` merge on `elevator`. The executor prompt's `<worktree_branch_check>` step ("Verify base: `git merge-base HEAD 90140b5...`. Reset if needed.") triggered a `git reset --hard 90140b5` before any Plan 02 work was committed. The reset brought Plan 01's three commits (`71010e8`, `1d788f0`, `90140b5`) into the worktree branch as the new base. All four Plan 02 commits sit on top: `cc891db → f9f830c → ebbaa2f → 6db8b53`.

## Issues Encountered

None beyond the painter-geometry bug documented above.

## Carry-Forward TODOs

- **Plan 03:** Replace the onTap stub at `lib/page_creator/assets/advantys_stb.dart:217` with the real per-channel detail dialog (`_showDetailDialog(context, _stateMan!)`). The stub currently shows a placeholder `AlertDialog`.
- **Plan 04:** Register `STBDDI3725Config` in `lib/page_creator/assets/registry.dart` (both `_fromJsonFactories` and `defaultFactories` maps). Add an `AssetRegistry` round-trip test + a back-compat test for legacy JSON without `nameOrId`. Add a widget mount/unmount leak test.
- **Backend confirmation (Phase-spanning):** Resolve the LSB-first vs MSB-first bit-order question with the backend team. Cost of MSB-first: one constant edit (`kSTBChannelBitOrder` in `io16.dart`) + three test-expectation edits (`advantys_stb_test.dart` `0x0001 / 0x8000 / 0xAAAA` groups) + regeneration of two goldens (`ddi3725_alternating_0xAAAA_light.png` + `_dark.png`). Painter math is unchanged.
- **Force-values wire-format trip-wire:** The `_forceArrayFromDynamicValue` helper silently returns null if the runtime `DynamicValue` arrives as a packed int (Beckhoff convention) rather than an array. Backend should confirm the int8[16] wire format (CONTEXT D-ForceValues) and surface a runtime assertion if the convention drifts.

## Self-Check: PASSED

- File `lib/page_creator/assets/advantys_stb.dart` — FOUND (created in commit `cc891db`, 370 LoC).
- File `lib/page_creator/assets/advantys_stb.g.dart` — FOUND (generated alongside `cc891db`).
- File `lib/painter/advantys_stb/ddi3725.dart` — FOUND (stub in `cc891db`, real impl in `f9f830c`, ~245 LoC).
- File `test/page_creator/assets/advantys_stb_test.dart` — FOUND, 33 tests pass.
- 10 PNG goldens in `test/page_creator/assets/goldens/advantys_stb/` — FOUND (all `ls *.png | wc -l == 10` ✓).
- File `lib/painter/advantys_stb/io16.dart` — modified in `6db8b53` (Rule 1 auto-fix).
- Commit `cc891db` (Task 1) — FOUND.
- Commit `f9f830c` (Task 2) — FOUND.
- Commit `ebbaa2f` (Task 3) — FOUND.
- Commit `6db8b53` (Task 5) — FOUND.
- TDD gate sequence verified: every `feat(01-02)` commit references the requirement IDs it satisfies.
- All 33 tests pass; all 10 goldens byte-match (no `--update-goldens` needed).
- `flutter analyze` on the four plan-scoped files: zero issues.
- `grep _combinedStream`: cached in nullable field, set in initState' `.then` callback, read by build() — QUAL-03 / PITFALL M-03 ✓.
- `grep HitTestBehavior.opaque`: present in the `_STBDDI3725State._buildShell` GestureDetector — QUAL-05 ✓.
- `grep bodyColor`: imported via `io16.dart show bodyColor`, used as cream fill paint — QUAL-02 ✓.
- `all_off_light.png` vs `all_off_dark.png`: body-region pixels visually identical (QUAL-02 hand-checked).

---
*Phase: 01-stbddi3725-16-ch-digital-input*
*Completed: 2026-05-11*
