---
quick_id: 260512-stb-painter-defects-batch2
slug: stb-painter-defects-batch2
date: 2026-05-12
status: in-progress
---

# STB Painter Defects — Batch 2

Six user-reported defects across the four Schneider Advantys STB painters
(NIP2311, PDT3100, DDI3725, DDO3705). All defects apply to commit `40c224b`
(post-batch-1 fixes).

## Defects

- **A — Chamfer leak.** Blue header/footer still leaks outside body chamfer
  on some modules. Add per-corner pixel-sample regression for ALL four
  corners on all four modules (existing tests only sample top-left at 1×1
  which already passes).
- **B — Corner radii too aggressive.** Reduce `size.width * 0.06` → use
  smaller absolute radius matching Beckhoff's subtle chamfer. Beckhoff IO8
  uses `size.width * 0.06` but its modules are 1:6 slim so the radius is
  tiny in absolute pixels. We mirror the *visual* subtlety, not the formula.
- **C — PDT3100 wrong topology.** Replace single +/− pins with INPUT/OUTPUT
  plug terminals, DC label between them, IN/OUT LED viewport at top, spring
  clip levers per terminal.
- **D — Remove "24 VDC 0.55A" text** from NIP2311 and PDT3100.
- **E — Aspect ratio.** Change Schneider intrinsic SizedBox dimensions to
  match Beckhoff slim DIN-rail style. EL1008 uses 1:6 (height/6 : height).
  Apply 1:6 to DDI3725 + DDO3705 (I/O peers of EL1008/EL2008). Apply 1:3 to
  NIP2311 + PDT3100 (head/power; roughly 2× the width of I/O modules per
  the panel reference photo at `.planning/research/photos/momentum_stack_in_panel.png`).
- **F — Remove "Schneider Electric" branding** from NIP2311 + PDT3100.

## Atomic Commits

1. `test(stb): RED — chamfer-leak (4 corners) + radii + PDT topology + stray text + aspect-ratio` — add failing tests
2. `fix(stb): reduce corner radii to subtle chamfer (Beckhoff parity)` — radius constant change
3. `fix(stb): tighten chamfer-clip so blue never escapes body RRect` — audit + tighten clip if needed
4. `fix(stb): match Beckhoff aspect ratio (slim DIN-rail modules)` — SizedBox dims
5. `fix(stb-pdt): replace single +/− pins with INPUT/OUTPUT plug terminals + DC label + IN/OUT LED + spring clips` — PDT rewrite
6. `fix(stb): remove stray "24 VDC 0.55A" text from NIP and PDT` — voltage strip removal
7. `fix(stb): remove "Schneider Electric" branding text from NIP and PDT` — brand removal
8. `test(stb): regenerate goldens (visually verified)` — regenerate + commit goldens

## Validation Gates

- `flutter analyze` on every touched .dart file — clean
- `flutter test test/page_creator/` — full directory passes
- Visually inspect every regenerated PNG against checklist
- Update `.planning/phases/05-advantysstbstack-composite-parent/05-VISUAL-QUALITY-CHECKLIST.md`
  with chamfer-corner-pixel-sample and aspect-ratio + no-vendor-branding items

## Files In Scope

- `lib/painter/advantys_stb/ddi3725.dart`
- `lib/painter/advantys_stb/ddo3705.dart`
- `lib/painter/advantys_stb/nip2311.dart`
- `lib/painter/advantys_stb/pdt3100.dart` (BIG rewrite for defect C)
- `test/page_creator/assets/advantys_stb_test.dart`
- `test/page_creator/assets/goldens/advantys_stb/*.png` (regenerate all 28)
- `.planning/phases/05-advantysstbstack-composite-parent/05-VISUAL-QUALITY-CHECKLIST.md`
