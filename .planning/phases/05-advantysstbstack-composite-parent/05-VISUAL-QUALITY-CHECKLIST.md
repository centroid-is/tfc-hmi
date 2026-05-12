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
- [ ] **No stray pixels below the bottom outline** — the footer (if any) is
      clipped inside the body RRect; the bottommost row of the canvas is the
      background colour, not a leaked accent band.
- [ ] **LEDs (if applicable) are round, evenly spaced, and the active vs
      inactive states are visually distinct** — single-LED variants show clear
      active-green vs dim-grey contrast; grid variants (DDI/DDO 16-channel) show
      individual circular indicators, not horizontal bars.
- [ ] **All text labels fit inside the module body** — no glyph rect crosses
      the body outline; "INPUT +" / "INPUT −" / DDI / DDO / NIP labels are
      fully inside the cream area.
- [ ] **No clipping at any edge** — the module's intended visual footprint is
      fully visible; no edge of the painter is cut off by an outer SizedBox or
      RepaintBoundary.
- [ ] **Aspect ratio looks correct for the module type** — NIP is narrow,
      PDT is slim, DDI/DDO are wider than they are tall by the DXF bounding box.

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
