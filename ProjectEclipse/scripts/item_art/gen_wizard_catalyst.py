#!/usr/bin/env python3
"""W4-WIZARD: `wizard_catalyst` (16x16 item icon) — the Sonnenkern-Katalysator.

Design (docs/plans_v3/ideas_wave4/IDEA-19_wand.md §1.3/§3): a captured sun-core the
wizard Orin distilled from eclipse light — a molten gold orb bitten by a void-purple
eclipse crescent, radiating short flare spikes. Herald-gold ramp + the shared
EclipseUiTheme purples so it sits beside the shard family; `finish()` adds the 2px
black-purple edge and 3-tone shading.

Flattened per PLAN-ITEMS §3.C3: every shape is plotted with `put()` pixel fills —
the previous `ImageDraw` ellipses anti-aliased under older Pillow builds and leaked
101 colors through `finish()`. Now ≤ 20 opaque colors and Pillow-version-proof.
Deterministic — rerun for a byte-identical PNG.

Run from anywhere:
    python3 scripts/item_art/gen_wizard_catalyst.py
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import (  # noqa: E402
    GLOW_MAGENTA, GLOW_WHITE, GOLD, GOLD_DARK, GOLD_LIGHT, PURPLE_DARK,
    PURPLE_MID, canvas, finish, put, save,
)

OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item"
)

MAX_COLORS = 20


def disc_px(cx, cy, radius):
    """Integer pixel-center disc (flat — no AA, unlike ImageDraw.ellipse)."""
    r2 = radius * radius
    return [(x, y) for y in range(16) for x in range(16)
            if (x - cx) ** 2 + (y - cy) ** 2 <= r2]


def wizard_catalyst():
    """Sun-core orb with an eclipse crescent bite and four flare spikes."""
    img = canvas()

    # Flare spikes first (the orb overlaps their roots).
    put(img, ((8, 1), (8, 2), (1, 8), (2, 8), (14, 8), (13, 8), (8, 14), (8, 13)),
        GOLD_DARK)
    put(img, ((3, 3), (12, 3), (3, 12), (12, 12)), GOLD_DARK)

    # Molten gold orb body (radius 4.75 == the old [3,3,12,12] ellipse fill).
    put(img, disc_px(7.5, 7.5, 4.75), GOLD)
    # Hot upper-left quarter catching its own light.
    put(img, disc_px(6.3, 6.3, 2.4), GOLD_LIGHT)

    # Eclipse crescent biting the lower-right limb (void purple).
    orb = set(disc_px(7.5, 7.5, 4.75))
    put(img, [p for p in disc_px(11.5, 11.5, 3.6) if p in orb], PURPLE_MID)
    put(img, [p for p in disc_px(12.0, 12.0, 2.4) if p in orb], PURPLE_DARK)

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
    colors = {px[:3] for px in img.getdata() if px[3] >= 128}
    assert len(colors) <= MAX_COLORS, f"{len(colors)} opaque colors (max {MAX_COLORS})"
    save(img, OUT / "wizard_catalyst.png")


if __name__ == "__main__":
    main()
