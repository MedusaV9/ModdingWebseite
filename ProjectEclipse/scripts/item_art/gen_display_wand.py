#!/usr/bin/env python3
"""Generate the 16x16 purple Display Wand item texture.

WB-ART pass: same concept as the original placeholder (diagonal wand, faceted
display crystal, animation sparkle) repainted on the shared EclipseUiTheme
ramp in `eclipse_palette.py`, finished with the shared 2px black-purple edge
+ 3-tone shading pass. Deterministic.

Run from anywhere:
    python3 scripts/item_art/gen_display_wand.py
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import (  # noqa: E402
    ACCENT, ACCENT_DEEP, GLOW_MAGENTA, GLOW_WHITE, HAIRLINE, PURPLE_DARK,
    PURPLE_MID, TEXT,
    canvas, finish, line_px, put, save,
)

OUTPUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item/display_wand.png"
)


def display_wand():
    img = canvas()

    # Diagonal shaft: lit upper-left line + shadowed lower-right line.
    shaft = line_px(3, 13, 9, 7)
    put(img, shaft, PURPLE_MID)
    put(img, [(x + 1, y) for x, y in shaft], PURPLE_DARK)
    put(img, ((4, 12), (6, 10), (8, 8)), ACCENT_DEEP)   # facet glints
    # Grip wrap at the base.
    put(img, ((3, 13), (4, 13), (3, 14), (4, 14)), HAIRLINE)

    # Faceted amethyst display crystal held in a small claw.
    put(img, ((10, 6), (9, 6), (10, 5)), HAIRLINE)      # claw mount
    put(img, ((11, 4),
              (10, 3), (11, 3), (12, 3),
              (10, 2), (11, 2), (12, 2),
              (11, 1)), ACCENT_DEEP)
    put(img, ((10, 2), (11, 2), (10, 3)), ACCENT)
    put(img, ((11, 2),), TEXT)

    finish(img)
    # Animation sparkle (unshaded glow star).
    put(img, ((4, 3), (6, 3), (5, 2), (5, 4)), GLOW_MAGENTA)
    put(img, ((5, 3),), GLOW_WHITE)
    put(img, ((11, 1),), GLOW_WHITE)
    return img


def main() -> None:
    img = display_wand()
    assert img.size == (16, 16) and img.mode == "RGBA"
    save(img, OUTPUT)


if __name__ == "__main__":
    main()
