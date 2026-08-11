#!/usr/bin/env python3
"""Generate the custom pallet glyphs and merge them into assets/fonts/TfcIcons.ttf.

TfcIcons.ttf was originally produced by Fontello, but no Fontello config was kept
in the repo. Rather than round-trip the whole font through Fontello again (which
would risk shifting the existing code points that lib/converter/icon.dart hard
codes), this script appends new glyphs to the existing font in place.

The icons are built out of axis-aligned rectangles only, so the glyph outlines
are described directly in font units and the matching SVG sources are written
out for reference / future re-generation.

Design space: the usual Fontello 1000x1000 viewBox with y pointing down and the
baseline at ascent = 850 font units, i.e. fontY = 850 - svgY.

Usage:  python3 tools/build_tfc_icons.py
"""

from __future__ import annotations

import os

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_PATH = os.path.join(REPO, "assets", "fonts", "TfcIcons.ttf")
SVG_DIR = os.path.join(REPO, "tools", "icon-sources")

ASCENT = 850  # font units above the baseline; svgY 0 maps here
EM = 1000
ADVANCE = 1000

# --------------------------------------------------------------------------
# Icon geometry (SVG coordinates: 0..1000, y down)
# --------------------------------------------------------------------------


def pallet_top_rects() -> list[tuple[float, float, float, float]]:
    """Pallet seen from above: five deck boards over three stringers."""
    left, right = 70, 930
    top, bottom = 210, 790

    board_h = 88
    gap = 35
    rects = []
    for i in range(5):
        y0 = top + i * (board_h + gap)
        rects.append((left, y0, right, y0 + board_h))

    # Stringers running under the deck boards; they only show in the gaps but
    # drawing them full height is what unions the shape together.
    stringer_w = 76
    for cx in (left + stringer_w / 2, (left + right) / 2, right - stringer_w / 2):
        rects.append((cx - stringer_w / 2, top, cx + stringer_w / 2, bottom))

    return rects


def pallet_stack_rects() -> list[tuple[float, float, float, float]]:
    """Pallet from the side carrying ten rows of boxes."""
    left, right = 60, 940
    rects = []

    # --- pallet ---------------------------------------------------------
    deck_top, deck_bottom = 880, 912
    foot_bottom = 958
    base_bottom = 990
    rects.append((left, deck_top, right, deck_bottom))  # top deck board
    foot_w = 112
    for x0 in (left, (left + right) / 2 - foot_w / 2, right - foot_w):
        rects.append((x0, deck_bottom, x0 + foot_w, foot_bottom))  # blocks
    rects.append((left, foot_bottom, right, base_bottom))  # bottom board

    # --- ten rows of boxes ----------------------------------------------
    box_left, box_right = 95, 905
    row_h = 58
    row_gap = 13
    seam = 14  # vertical gap between boxes in the same row
    # Leave a hairline above the deck board so the pallet does not merge into
    # the bottom row of boxes at small sizes.
    stack_bottom = deck_top - 16
    for i in range(10):
        y1 = stack_bottom - i * (row_h + row_gap)
        y0 = y1 - row_h
        # Alternate the seam position so the rows read as boxes, not stripes.
        seam_x = 500 if i % 2 == 0 else 365
        rects.append((box_left, y0, seam_x - seam / 2, y1))
        rects.append((seam_x + seam / 2, y0, box_right, y1))

    return rects


ICONS = {
    "pallet_top": (0xE806, pallet_top_rects),
    "pallet_stack": (0xE807, pallet_stack_rects),
}


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------


def write_svg(name: str, rects) -> None:
    os.makedirs(SVG_DIR, exist_ok=True)
    body = "\n".join(
        '  <rect x="{:g}" y="{:g}" width="{:g}" height="{:g}"/>'.format(
            x0, y0, x1 - x0, y1 - y0
        )
        for x0, y0, x1, y1 in rects
    )
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {em} {em}" '
        'width="{em}" height="{em}">\n{body}\n</svg>\n'
    ).format(em=EM, body=body)
    path = os.path.join(SVG_DIR, name + ".svg")
    with open(path, "w") as fh:
        fh.write(svg)
    print("wrote", os.path.relpath(path, REPO))


def draw_glyph(rects):
    """Rectangles -> a TrueType glyph.

    Every contour is wound clockwise in font (y-up) space, so overlapping
    rectangles union under the non-zero fill rule and no boolean op is needed.
    """
    pen = TTGlyphPen(None)
    for x0, y0, x1, y1 in rects:
        # svg y down -> font y up
        fy0, fy1 = ASCENT - y1, ASCENT - y0
        pen.moveTo((x0, fy0))
        pen.lineTo((x0, fy1))
        pen.lineTo((x1, fy1))
        pen.lineTo((x1, fy0))
        pen.closePath()
    return pen.glyph()


def main() -> None:
    font = TTFont(FONT_PATH)
    glyf = font["glyf"]
    hmtx = font["hmtx"]
    order = font.getGlyphOrder()

    for name, (codepoint, builder) in ICONS.items():
        rects = builder()
        write_svg(name, rects)

        if name not in order:
            order = list(order) + [name]
        glyf[name] = draw_glyph(rects)
        hmtx[name] = (ADVANCE, 0)

        for table in font["cmap"].tables:
            if table.isUnicode():
                table.cmap[codepoint] = name
        print("glyph {} at U+{:04X}".format(name, codepoint))

    font.setGlyphOrder(order)
    font["maxp"].numGlyphs = len(order)
    font.save(FONT_PATH)
    print("updated", os.path.relpath(FONT_PATH, REPO))


if __name__ == "__main__":
    main()
