#!/usr/bin/env python3
"""W4-WIZARD: `wizard_catalyst` (16x16 item icon) — the Sonnenkern-Katalysator.

Design (docs/plans_v3/ideas_wave4/IDEA-19_wand.md §1.3/§3): a captured sun-core the
wizard Orin distilled from eclipse light — a molten gold orb bitten by a void-purple
eclipse crescent, radiating short flare spikes. Herald-gold ramp + the shared
EclipseUiTheme purples so it sits beside the shard family; `finish()` adds the 2px
black-purple edge and 3-tone shading. Deterministic — rerun for a byte-identical PNG.

Run from anywhere:
    python3 scripts/item_art/gen_wizard_catalyst.py
"""

from pathlib import Path
import sys

from PIL import ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import (  # noqa: E402
    GLOW_MAGENTA, GLOW_WHITE, GOLD, GOLD_DARK, GOLD_LIGHT, PURPLE_DARK,
    PURPLE_MID, canvas, finish, put, rgba, save,
)

OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item"
)


def wizard_catalyst():
    """Sun-core orb with an eclipse crescent bite and four flare spikes."""
    img = canvas()
    d = ImageDraw.Draw(img)

    # Flare spikes first (the orb overlaps their roots).
    put(img, ((8, 1), (8, 2), (1, 8), (2, 8), (14, 8), (13, 8), (8, 14), (8, 13)),
        GOLD_DARK)
    put(img, ((3, 3), (12, 3), (3, 12), (12, 12)), GOLD_DARK)

    # Molten gold orb body.
    d.ellipse((3, 3, 12, 12), fill=rgba(GOLD))
    # Hot upper-left half catching its own light.
    d.ellipse((4, 4, 9, 9), fill=rgba(GOLD_LIGHT))

    # Eclipse crescent biting the lower-right limb (void purple).
    d.polygon([(12, 7), (12, 11), (8, 12), (10, 9)], fill=rgba(PURPLE_MID))
    put(img, ((11, 11), (10, 12), (9, 12)), PURPLE_DARK)

    # Blazing core.
    put(img, ((6, 6), (7, 6), (6, 7)), GLOW_WHITE)

    finish(img)
    # Glow accents (post-finish so they stay unshaded): spike tips + crescent spark.
    put(img, ((8, 1), (1, 8), (14, 8), (8, 14)), GLOW_WHITE)
    put(img, ((12, 11),), GLOW_MAGENTA)
    return img


def main():
    img = wizard_catalyst()
    assert img.size == (16, 16) and img.mode == "RGBA"
    save(img, OUT / "wizard_catalyst.png")


if __name__ == "__main__":
    main()
