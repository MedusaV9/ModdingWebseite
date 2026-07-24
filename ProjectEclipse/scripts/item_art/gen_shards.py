#!/usr/bin/env python3
"""WB-ART shard family: `umbral_shard` and `vitae_shard` (16x16 item icons).

Hand-authored faceted crystals on the shared EclipseUiTheme ramp
(`eclipse_palette.py`): flat facet fills first, then the shared `finish()`
pass adds the 2px black-purple edge, bottom-right shade and top-left rim
light. Deterministic — rerun for byte-identical PNGs.

Run from anywhere:
    python3 scripts/item_art/gen_shards.py
"""

from pathlib import Path
import sys

from PIL import ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import (  # noqa: E402
    ACCENT, ACCENT_DEEP, CRIMSON, CRIMSON_DARK, GLOW_MAGENTA, GLOW_WHITE,
    HAIRLINE, PURPLE_DARK, PURPLE_MID, SCARLET, TEXT,
    canvas, finish, mix, put, rgba, save,
)

OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item"
)


def umbral_shard():
    """Jagged violet crystal: one tall faceted spike + a splinter at its foot."""
    img = canvas()
    d = ImageDraw.Draw(img)

    # Silhouette: elongated diagonal shard, tip top-right, foot bottom-left.
    d.polygon([(10, 1), (12, 5), (11, 9), (8, 14), (5, 10), (7, 5)],
              fill=rgba(PURPLE_MID))
    # Light facet (catches the top-left rim light).
    d.polygon([(10, 1), (7, 5), (6, 9), (8, 12)], fill=rgba(ACCENT_DEEP))
    # Dark facet (turned away).
    d.polygon([(11, 6), (11, 9), (9, 13), (9, 8)], fill=rgba(PURPLE_DARK))
    # Core ridge catching the void light.
    put(img, ((9, 3), (9, 4), (8, 5), (8, 6), (8, 7), (8, 8), (8, 9), (8, 10)), ACCENT)
    put(img, ((10, 2),), TEXT)

    # Splinter broken off at the foot.
    d.polygon([(3, 10), (5, 12), (3, 14)], fill=rgba(PURPLE_DARK))
    put(img, ((4, 12),), ACCENT_DEEP)

    finish(img)
    # Selective glow accents (post-finish so they stay unshaded).
    put(img, ((12, 3),), GLOW_MAGENTA)
    put(img, ((9, 4),), GLOW_WHITE)
    return img


def vitae_shard():
    """Pulsing red-violet heart crystal: faceted heart tapering to a point."""
    img = canvas()
    d = ImageDraw.Draw(img)

    red_violet = mix(CRIMSON, ACCENT_DEEP, 0.45)

    # Heart silhouette: two lobes, faceted taper.
    d.polygon([(5, 2), (7, 4), (10, 2), (13, 4), (13, 8), (8, 14), (3, 8), (3, 4)],
              fill=rgba(CRIMSON))
    # Left lobe light facet.
    d.polygon([(5, 2), (7, 4), (6, 8), (4, 7), (3, 4)], fill=rgba(SCARLET))
    # Right lobe turned into the void (red-violet facet).
    d.polygon([(10, 3), (13, 5), (13, 8), (10, 10)], fill=rgba(red_violet))
    # Lower shadow facet toward the point.
    d.polygon([(6, 9), (10, 10), (8, 13)], fill=rgba(CRIMSON_DARK))
    # Beating inner core.
    put(img, ((7, 5), (8, 6), (7, 6)), SCARLET)
    put(img, ((8, 5),), TEXT)
    # Cleft between the lobes.
    put(img, ((8, 2), (8, 3)), rgba(HAIRLINE))

    finish(img)
    put(img, ((7, 4),), GLOW_WHITE)
    put(img, ((13, 3),), GLOW_MAGENTA)
    put(img, ((2, 9),), GLOW_MAGENTA)
    return img


def main():
    for name, painter in (("umbral_shard", umbral_shard), ("vitae_shard", vitae_shard)):
        img = painter()
        assert img.size == (16, 16) and img.mode == "RGBA"
        save(img, OUT / f"{name}.png")


if __name__ == "__main__":
    main()
