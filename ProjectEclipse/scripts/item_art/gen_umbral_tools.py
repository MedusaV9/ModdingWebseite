#!/usr/bin/env python3
"""WB-ART tool family: `umbral_pick` and `umbral_blade` (16x16 item icons).

Obsidian-violet tools on the shared EclipseUiTheme ramp with bone grips
(`eclipse_palette.py`), authored in the vanilla diagonal tool orientation so
they feel native in hand. Flat fills first, then the shared `finish()` pass
(2px black-purple edge, 3-tone shading, top-left rim light). Deterministic.

Run from anywhere:
    python3 scripts/item_art/gen_umbral_tools.py
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import (  # noqa: E402
    ACCENT, ACCENT_DEEP, BONE, BONE_DARK, GLOW_MAGENTA, GLOW_WHITE, HAIRLINE,
    PANEL, PURPLE_DARK, PURPLE_MID,
    canvas, finish, line_px, put, save,
)

OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item"
)


def umbral_pick():
    """Obsidian war-pick: crescent head sweeping top-left to bottom-right,
    bone handle running to the bottom-left corner."""
    img = canvas()

    # Head crescent, outer arc first (mid tone).
    put(img, ((5, 1), (6, 1), (7, 1), (8, 1),
              (3, 2), (4, 2), (5, 2), (6, 2), (7, 2), (8, 2), (9, 2), (10, 2),
              (2, 3), (3, 3), (4, 3), (9, 3), (10, 3), (11, 3),
              (1, 4), (2, 4), (10, 4), (11, 4), (12, 4),
              (1, 5), (2, 5), (11, 5), (12, 5),
              (12, 6), (13, 6),
              (12, 7), (13, 7),
              (13, 8),
              (13, 9),
              (13, 10)), ACCENT_DEEP)
    # Obsidian gleam along the top-left of the arc.
    put(img, ((5, 1), (6, 1), (3, 2), (4, 2), (2, 3), (1, 4)), ACCENT)
    # Underside of the crescent falls into shadow.
    put(img, ((9, 3), (10, 4), (11, 5), (12, 7), (13, 9), (13, 10),
              (2, 5), (1, 5)), PURPLE_DARK)
    put(img, ((7, 2), (8, 2)), PURPLE_MID)

    # Bone handle from the head boss to the bottom-left corner.
    handle = line_px(7, 3, 2, 13)
    put(img, handle, BONE)
    put(img, [(x + 1, y) for x, y in handle], BONE_DARK)
    # Leather wrap + pommel cap.
    put(img, ((4, 9), (5, 9), (4, 10), (5, 10)), HAIRLINE)
    put(img, ((4, 9),), PURPLE_MID)
    put(img, ((2, 13), (3, 13), (2, 14), (3, 14)), PANEL)

    finish(img)
    put(img, ((7, 1),), GLOW_WHITE)      # apex glint
    put(img, ((13, 11),), GLOW_MAGENTA)  # void charge dripping off the tine
    return img


def umbral_blade():
    """Obsidian short-sword: 2px diagonal blade, bone guard, wrapped grip."""
    img = canvas()

    # Blade: light edge (upper-left line) + dark back (lower-right line).
    edge = line_px(12, 1, 4, 9)
    back = line_px(13, 2, 5, 10)
    put(img, back, PURPLE_DARK)
    put(img, edge, ACCENT_DEEP)
    put(img, ((12, 1), (11, 2), (10, 3), (9, 4), (8, 5)), ACCENT)  # edge gleam
    put(img, ((13, 1),), ACCENT_DEEP)                 # square off the point
    put(img, ((8, 5), (7, 6)), PURPLE_MID)            # fuller catching light

    # Bone crossguard, perpendicular to the blade.
    put(img, ((2, 8), (3, 9), (4, 10), (5, 11), (6, 12)), BONE)
    put(img, ((3, 8), (4, 9), (5, 10), (6, 11)), BONE_DARK)

    # Wrapped grip + pommel gem.
    put(img, ((3, 11), (2, 12), (1, 13)), HAIRLINE)
    put(img, ((2, 11), (1, 12)), PURPLE_MID)
    put(img, ((1, 14), (2, 14), (1, 13), (2, 13)), PANEL)
    put(img, ((2, 13),), ACCENT_DEEP)

    finish(img)
    put(img, ((12, 0),), GLOW_WHITE)     # star glint off the point
    put(img, ((2, 13),), GLOW_MAGENTA)   # pommel gem
    return img


def main():
    for name, painter in (("umbral_pick", umbral_pick), ("umbral_blade", umbral_blade)):
        img = painter()
        assert img.size == (16, 16) and img.mode == "RGBA"
        save(img, OUT / f"{name}.png")


if __name__ == "__main__":
    main()
