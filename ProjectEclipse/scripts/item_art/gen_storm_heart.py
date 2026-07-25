#!/usr/bin/env python3
"""`storm_heart` — the Fog Tyrant's EPIC drop (16x16 item icon, EVAL-V6-COMPLETE A#1).

Faceted heart on the Tyrant's MOB-BOSS2 storm ramp (`scripts/geckolib_gen/mobs/
fog_tyrant.py`): storm blue-black `#232830` / wet-slate `#39414B` body lightening
toward the fog-bank hem tone `#8496AB`, split by a jagged electric-seam fissure
(`#9FE8FF` -> `#CFF3FF`) with the white-hot caged-core texel `#F6FEFF` still beating
at its center — "The Fog Tyrant's tempest, still beating" (`item.eclipse.storm_heart
.lore`). Flat facets first, then the shared `finish()` edge/shade pass; the seam and
core go on post-finish so they stay unshaded like every Tyrant emissive.
Deterministic — rerun for a byte-identical PNG.

Run from anywhere:
    python3 scripts/item_art/gen_storm_heart.py
"""

from pathlib import Path
import sys

from PIL import ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import canvas, finish, mix, mul, put, rgba, save  # noqa: E402

OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item"
)

# Fog Tyrant storm ramp (mobs/fog_tyrant.py constants).
STORM_DEEP = (35, 40, 48)     # #232830 storm blue-black
SLATE = (57, 65, 75)          # #39414B CLOAK wet slate
FOG_HEM = (132, 150, 171)     # #8496AB CLOAK_HEM fog-bank pale
SEAM_LO = (159, 232, 255)     # #9FE8FF electric seam
SEAM_HI = (207, 243, 255)     # #CFF3FF electric seam, hot
CORE_HOT = (246, 254, 255)    # #F6FEFF caged storm core


def storm_heart():
    """Storm-slate faceted heart, torn by one live electric fissure."""
    img = canvas()
    d = ImageDraw.Draw(img)

    # Heart silhouette: two lobes, faceted taper (vitae_shard's cut, storm re-ground).
    d.polygon([(5, 2), (7, 4), (10, 2), (13, 4), (13, 8), (8, 14), (3, 8), (3, 4)],
              fill=rgba(SLATE))
    # Left lobe catches the fog-bank light.
    d.polygon([(5, 2), (7, 4), (6, 8), (4, 7), (3, 4)], fill=rgba(mix(SLATE, FOG_HEM, 0.5)))
    # Right lobe turned into the storm (blue-black facet).
    d.polygon([(10, 3), (13, 5), (13, 8), (10, 10)], fill=rgba(STORM_DEEP))
    # Lower shadow facet toward the point.
    d.polygon([(6, 9), (10, 10), (8, 13)], fill=rgba(mul(SLATE, 0.78)))
    # Cleft between the lobes.
    put(img, ((8, 2), (8, 3)), mul(STORM_DEEP, 0.72))

    finish(img)
    # Electric-seam fissure (post-finish, unshaded — the Tyrant seam language): a
    # jagged 1px crack from the cleft to just above the point.
    put(img, ((8, 4), (7, 5), (7, 6), (8, 7), (9, 8), (8, 9), (8, 10), (7, 11)), SEAM_LO)
    put(img, ((7, 5), (9, 8)), SEAM_HI)  # kink flashes
    # The still-beating white-hot core at the fissure's heart.
    put(img, ((8, 7),), CORE_HOT)
    # Arc sparks jumping off the silhouette.
    put(img, ((13, 3),), SEAM_HI)
    put(img, ((2, 9),), SEAM_LO)
    return img


def main():
    img = storm_heart()
    assert img.size == (16, 16) and img.mode == "RGBA"
    save(img, OUT / "storm_heart.png")


if __name__ == "__main__":
    main()
