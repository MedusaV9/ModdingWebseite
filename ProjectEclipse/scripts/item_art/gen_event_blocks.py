#!/usr/bin/env python3
"""WB-ART event-block family: `altar_top`, `altar_side`, `altar_bottom`,
`grave`, `grave_side` (16x16 block textures).

Hand-structured pixel art (no noise fills) on the shared EclipseUiTheme ramp:

  * altar — dark ritual dais: rune ring + eclipse disc on top, carved glowing
    glyph panel on the sides, plain seamed slab underneath. RGBA (opaque),
    matching the committed placeholders.
  * grave — "Here a soul ended": packed umber-violet soil ends with bone
    chips and faint soul-teal motes; sides are a carved tombstone face with
    an eclipse glyph and moss at the foot. Saved as RGB to stay byte-mode
    compatible with the placeholders (`grave*.png` have no alpha channel).

`finish(grow=False)` supplies the top-left rim light / bottom-right shade
bevel on the full-canvas sprites (canvas borders count as edges), which is
what makes the blocks read as beveled tiles in-world. Deterministic.

Run from anywhere:
    python3 scripts/item_art/gen_event_blocks.py
"""

import math
from pathlib import Path
import sys

from PIL import ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import (  # noqa: E402
    ACCENT, ACCENT_DEEP, BONE, BONE_DARK, DIM, GLOW_MAGENTA,
    GOOD, HAIRLINE, PANEL, PANEL_RAISED, PURPLE_DARK, SOUL_TEAL,
    canvas, finish, mix, mul, put, rgba, save,
)

OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/block"
)

STONE = mix(DIM, PANEL, 0.62)        # tombstone grey-violet
STONE_DARK = mix(HAIRLINE, PANEL, 0.45)
SOIL = mix(PANEL, BONE_DARK, 0.35)   # packed umber-violet grave soil
SOIL_LIGHT = mix(PANEL, BONE_DARK, 0.52)
SOIL_DARK = mix(PANEL, BONE_DARK, 0.18)
MOSS = mul(GOOD, 0.45)


def fill(img, color):
    ImageDraw.Draw(img).rectangle([0, 0, 15, 15], fill=rgba(color))


def altar_top():
    img = canvas()
    fill(img, PANEL_RAISED)
    # Corner chips where the dais has worn.
    put(img, ((2, 3), (3, 2), (12, 2), (13, 3), (2, 12), (3, 13), (12, 13), (13, 12)),
        HAIRLINE)
    # Structured floor flecks inside the ring.
    put(img, ((4, 6), (11, 9), (6, 11), (10, 4)), PURPLE_DARK)
    # Dashed rune ring (12 marks, cardinals lit).
    ring = []
    for k in range(12):
        a = math.pi * k / 6.0
        ring.append((round(7.5 + 5.0 * math.cos(a)), round(7.5 + 5.0 * math.sin(a))))
    put(img, ring, ACCENT_DEEP)
    put(img, ((12, 8), (8, 12), (2, 8), (8, 2)), ACCENT)
    # Central eclipse disc with an accent crescent.
    put(img, ((7, 7), (8, 7), (7, 8), (8, 8)), PANEL)
    put(img, ((6, 6), (7, 6), (6, 7)), ACCENT)
    finish(img, grow=False)
    put(img, ((9, 6),), GLOW_MAGENTA)
    return img


def altar_side():
    img = canvas()
    fill(img, PANEL_RAISED)
    # Dais lip (connects with the top face) and base plinth.
    put(img, [(x, 0) for x in range(16)], ACCENT_DEEP)
    put(img, [(x, 1) for x in range(16)], PURPLE_DARK)
    put(img, [(x, 12) for x in range(16)], HAIRLINE)
    for y in (13, 14, 15):
        put(img, [(x, y) for x in range(16)], PANEL)
    put(img, ((2, 14), (7, 13), (12, 14), (5, 15), (10, 15)), PURPLE_DARK)
    # Corner pilasters.
    for y in range(2, 12):
        put(img, ((0, y), (15, y)), PURPLE_DARK)
    # Three carved rune recesses, each with a distinct glyph (center one lit).
    runes = {
        3: ((0, 4), (1, 4), (0, 5), (0, 6), (1, 7), (0, 8), (1, 8)),
        7: ((0, 4), (1, 5), (0, 6), (0, 7), (1, 8)),
        11: ((1, 4), (0, 5), (1, 5), (1, 6), (0, 7), (1, 8)),
    }
    for gx, lit in ((3, False), (7, True), (11, False)):
        for y in range(4, 10):
            put(img, ((gx, y), (gx + 1, y)), PANEL)
        glyph = ACCENT if lit else ACCENT_DEEP
        put(img, [(gx + dx, y) for dx, y in runes[gx]], glyph)
    finish(img, grow=False)
    put(img, ((8, 5),), GLOW_MAGENTA)
    return img


def altar_bottom():
    img = canvas()
    fill(img, mix(PANEL_RAISED, PANEL, 0.45))
    # Offset slab seams.
    put(img, [(x, 7) for x in range(16)], PANEL)
    put(img, [(7, y) for y in range(0, 7)], PANEL)
    put(img, [(3, y) for y in range(8, 16)], PANEL)
    put(img, [(11, y) for y in range(8, 16)], PANEL)
    # Worn chips.
    put(img, ((2, 2), (12, 4), (5, 11), (13, 13), (9, 9)), PURPLE_DARK)
    finish(img, grow=False)
    return img


def grave_end():
    img = canvas()
    fill(img, SOIL)
    # Structured soil clods (offset L-shaped clusters).
    clods = (
        (2, 2), (3, 2), (2, 3),
        (9, 1), (10, 1), (10, 2),
        (14, 4), (13, 5), (14, 5),
        (5, 6), (6, 6), (5, 7),
        (11, 8), (12, 8), (12, 9),
        (1, 10), (2, 10), (1, 11),
        (7, 12), (8, 12), (7, 13),
        (13, 13), (14, 13), (14, 14),
        (3, 14), (4, 15),
    )
    put(img, clods, SOIL_LIGHT)
    shadows = ((3, 3), (11, 2), (13, 6), (6, 7), (11, 9), (2, 11), (8, 13), (13, 14))
    put(img, shadows, SOIL_DARK)
    # Bone chips surfacing from below.
    put(img, ((4, 5), (5, 5)), BONE_DARK)
    put(img, ((4, 4),), BONE)
    put(img, ((11, 11), (12, 11)), BONE_DARK)
    put(img, ((12, 10),), BONE)
    finish(img, grow=False)
    # Faint soul residue.
    put(img, ((10, 4), (5, 12)), SOUL_TEAL)
    return img


def grave_side():
    img = canvas()
    fill(img, STONE)
    # Soil overhang connecting to the end faces.
    put(img, [(x, 0) for x in range(16)], SOIL)
    put(img, ((1, 0), (6, 0), (12, 0), (3, 1), (9, 1), (14, 1)), SOIL_DARK)
    put(img, ((3, 0), (9, 0), (14, 0)), SOIL_LIGHT)
    for x in range(16):
        if x not in (3, 9, 14):
            put(img, ((x, 1),), STONE_DARK if x % 5 == 2 else STONE)
    # Carved eclipse glyph: recessed disc + crescent shadow.
    d = ImageDraw.Draw(img)
    d.ellipse([5, 4, 10, 9], fill=rgba(STONE_DARK))
    d.ellipse([6, 5, 9, 8], fill=rgba(PANEL))
    put(img, ((6, 5), (7, 5), (6, 6)), ACCENT_DEEP)
    # Weathering cracks.
    put(img, ((2, 6), (3, 7), (3, 8), (12, 3), (13, 4), (12, 10), (11, 11)), STONE_DARK)
    # Moss creeping up from the foot.
    put(img, ((0, 12), (1, 13), (0, 13), (2, 14), (14, 13), (15, 12), (13, 14), (15, 14)),
        MOSS)
    # Foundation course.
    put(img, [(x, 15) for x in range(16)], PANEL)
    put(img, ((4, 15), (10, 15)), STONE_DARK)
    finish(img, grow=False)
    put(img, ((8, 6),), SOUL_TEAL)
    return img


def main():
    jobs = (
        ("altar_top.png", altar_top, "RGBA"),
        ("altar_side.png", altar_side, "RGBA"),
        ("altar_bottom.png", altar_bottom, "RGBA"),
        ("grave.png", grave_end, "RGB"),
        ("grave_side.png", grave_side, "RGB"),
    )
    for name, painter, mode in jobs:
        img = painter()
        assert img.size == (16, 16)
        save(img, OUT / name, mode=mode)


if __name__ == "__main__":
    main()
