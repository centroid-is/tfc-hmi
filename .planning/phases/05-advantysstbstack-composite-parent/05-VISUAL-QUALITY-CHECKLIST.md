# 05 — Visual Quality Checklist (Goldens Regen Gate)

## Why this exists

Goldens verify pixel **stability**, not pixel **quality**. The `matchesGoldenFile`
matcher tells you "this render is identical to the captured PNG"; it does **not**
tell you "this render looks right." Bad output captured once gets locked in as
"expected" forever.

Phase 5 shipped four user-visible visual defects (Schneider header overshooting
the body chamfer, bottom footer bleed below the rounded outline, DDI/DDO LED
grid rendered as venetian-blind bars instead of round dots, PDT3100 "INPUT +" /
"INPUT −" labels overflowing the terminal block) because the agents who
regenerated the goldens treated "pixel match" and "task complete" as
equivalent — they ran `flutter test --update-goldens`, the test went green,
and the work was called done. **No human looked at the captured PNG.**

This file closes that gap: any agent (human or AI) that runs `--update-goldens`
in this milestone MUST apply the six-item checklist below to every regenerated
PNG before considering the work done.

## When this applies

Whenever you run:

```
flutter test --update-goldens test/page_creator/assets/advantys_stb_test.dart
```

(or any other `--update-goldens` invocation on an STB/Advantys/Beckhoff/Schneider
asset golden) you MUST go through the per-asset checklist below before
committing the regenerated PNGs.

## Per-asset visual quality checklist

For **every** regenerated PNG, read the file inline (the Claude `Read` tool
renders PNGs visually) and verify each of the following:

- [ ] **Chamfer / rounded corners are visible cleanly on all four corners** —
      no header bar overshoot, no body fill spilling past the rounded outline.
      Pixel-sample at (1, 1), (w-2, 1), (1, h-2), (w-2, h-2) on each module
      to assert the deeply-inside-chamfer pixel is the background colour and
      not Schneider blue (BATCH2 Defect A).
- [ ] **Chamfer radius is subtle, not aggressive** — Beckhoff parity. The
      shared `kStbCornerRadiusFraction = 0.03` formula applied to the
      shorter body dimension keeps the chamfer barely-visible on slim DIN-
      rail modules (BATCH2 Defect B).
- [ ] **No stray pixels below the bottom outline** — the footer (if any) is
      clipped inside the body RRect; the bottommost row of the canvas is the
      background colour, not a leaked accent band.
- [ ] **LED block matches real hardware** — DDI/DDO 16-channel modules render
      a dark inset panel with: a small "RDY" status row at the top, followed
      by a 2-column × 8-row grid of small squared (rounded-rect) channel LEDs
      with numeric labels "1".."16" to the LEFT of each LED. Active state is
      saturated green, inactive is muted dark grey. Single-LED variants
      (PDT3100 IN/OUT viewport) sit on their own dark inset window with a
      caption (BATCH2 Defect G).
- [ ] **PDT3100 device topology matches real hardware** — model name at top,
      IN/OUT LED viewport, INPUT plug terminal (with internal +/− polarity
      holes and a spring-clip lever on the right edge), DC inter-block label,
      OUTPUT plug terminal mirror (BATCH2 Defect C).
- [ ] **All text labels fit inside the module body** — no glyph rect crosses
      the body outline; INPUT / OUTPUT / DDI / DDO / NIP / PDT model labels
      are fully inside the cream area.
- [ ] **No clipping at any edge** — the module's intended visual footprint is
      fully visible; no edge of the painter is cut off by an outer SizedBox or
      RepaintBoundary.
- [ ] **Module aspect ratio matches Beckhoff slim DIN-rail equivalent** —
      DDI3725 + DDO3705 use `width: height / 6` (EL1008 / EL2008 1:6 parity);
      NIP2311 + PDT3100 use `kNIP/PDTAspectRatio = 1/3` (Schneider head/
      power modules are roughly 2× the I/O width per the panel reference
      photo). Goldens for the individual modules must pump them inside a
      `SizedBox` with the canonical slim dimensions (e.g. 50×300 for DDI/DDO,
      93×280 for NIP/PDT) so the painter renders at its intrinsic aspect
      (BATCH2 Defect E).
- [ ] **No vendor / brand text painted on the module faceplate** — no
      "Schneider Electric", no "24 VDC 0.55A". The faceplate chrome is
      device-class-specific only: model number, terminal labels, port
      markings, and the subtitle band ("24 VDC POWER" / "Ethernet
      Modbus/TCP 10/100T") which is hardware-rated descriptive text, not
      vendor branding (BATCH2 Defects D + F).

## Failure protocol

If any item fails for any regenerated PNG, do NOT commit the goldens. Iterate
on the painter fix until all six items pass for every regenerated PNG, then
commit the goldens with a message body that explicitly notes the visual
checklist passed for every PNG.

## See also

- `05-RETROFIT.md` — the Phase 5 retrofit plan (the visual quality checklist
  is the post-fix verification step that was retroactively added).
- `~/.claude/projects/-Users-jonb-Projects-tfc-hmi2/memory/feedback_golden_quality_gap.md`
  — the persistent agent memory entry that reinforces this rule across
  future sessions and other milestones.
