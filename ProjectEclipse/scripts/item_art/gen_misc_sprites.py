#!/usr/bin/env python3
"""ITEMS-C misc sprites: `respawn_door` item icon + `pale_hanging_moss` repaint.

* respawn_door — custom 16x16 icon replacing the borrowed vanilla
  `minecraft:item/dark_oak_door` sprite (PLAN-ITEMS §3.C4). Dead-door look
  matching the 128x128 block texture's identity (arched double leaf, eclipse
  glyphs, ring handles, glowing seam): pale drowned wood on the bone/parchment
  ramp, split by an ACCENT `#B98CFF` violet seam that leaks light, with an
  eclipse disc in the arch crown.
* pale_hanging_moss — contrast pass (PLAN-ITEMS §3.C5/§2.1): the old sprite was
  57 colors of near-flat pale noise (lum 135-200); repainted as three waving
  strands whose cores darken toward #575044 so the silhouette reads on the
  handbook panel, pale tips kept for the Pale Garden identity.

Flat `put()` fills + the shared `finish()` pass only — deterministic,
byte-identical reruns.

Run from anywhere:
    python3 scripts/item_art/gen_misc_sprites.py
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import (  # noqa: E402
    ACCENT, ACCENT_DEEP, BONE, BONE_DARK, DIM, GLOW_WHITE, PANEL, TEXT,
    canvas, finish, mix, put, save,
)

OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item"
)

# Pale drowned wood (bone/parchment ramp, desaturated toward grave-grey).
WOOD = mix(BONE, BONE_DARK, 0.45)
WOOD_DARK = BONE_DARK
WOOD_LIGHT = BONE

# Pale Garden moss tones; core target #575044 per PLAN-ITEMS §2.1.
MOSS_CORE = (87, 80, 68)
MOSS_MID = (150, 157, 132)
MOSS_PALE = (204, 210, 184)
MOSS_TIP = (222, 227, 200)


def respawn_door():
    """Arched dead-wood double door, violet seam glow + eclipse crown disc."""
    img = canvas()

    # Slab body with an arched crown (stays inside the 1..14 finish() box).
    body = [(x, 1) for x in range(6, 10)]
    body += [(x, 2) for x in range(4, 12)]
    body += [(x, 3) for x in range(3, 13)]
    body += [(x, y) for y in range(4, 15) for x in range(2, 14)]
    put(img, body, WOOD)

    # Vertical strake grain on both leaves (dead, split boards).
    put(img, ((4, 4), (4, 5), (4, 7), (4, 8), (4, 10), (4, 11), (4, 13),
              (11, 4), (11, 5), (11, 7), (11, 8), (11, 10), (11, 11), (11, 13)),
        WOOD_DARK)
    # Bleached top edge of the arch.
    put(img, ((6, 1), (7, 1), (4, 2), (5, 2), (10, 2), (11, 2)), WOOD_LIGHT)

    # Engraved eclipse glyphs (ring diamond + tick ladder) on each leaf.
    put(img, ((4, 5), (3, 6), (5, 6), (4, 7),
              (11, 5), (10, 6), (12, 6), (11, 7)), ACCENT_DEEP)
    put(img, ((4, 10), (4, 12), (11, 10), (11, 12)), ACCENT_DEEP)

    # Tarnished silver ring handles flanking the seam (brighter than the wood
    # so they survive gui scale 2).
    put(img, ((6, 9), (9, 9)), mix(DIM, TEXT, 0.55))
    put(img, ((6, 10), (9, 10)), WOOD_DARK)

    # Void gap between the leaves (the seam itself).
    put(img, [(7, y) for y in range(2, 15)] + [(8, y) for y in range(2, 15)],
        PANEL)

    finish(img)

    # Post-finish glow: the seam leaks eclipse light, hottest at the middle,
    # and the arch crown carries the eclipsed disc.
    put(img, [(7, y) for y in range(3, 14)], ACCENT)
    put(img, ((7, 7), (7, 8)), GLOW_WHITE)
    put(img, ((8, 5), (8, 10)), ACCENT_DEEP)
    put(img, ((7, 1), (8, 1)), ACCENT)
    put(img, ((7, 2), (8, 2)), ACCENT_DEEP)
    return img


# Strand paths, ordered top (attachment) -> bottom (tip).
MOSS_STRANDS = (
    ((5, 0), (5, 1), (5, 2), (6, 3), (6, 4), (6, 5), (5, 6), (5, 7), (5, 8),
     (6, 9), (6, 10), (6, 11), (5, 12), (5, 13), (5, 14)),
    ((11, 0), (11, 1), (10, 2), (10, 3), (10, 4), (11, 5), (11, 6), (11, 7),
     (12, 8), (12, 9), (11, 10), (11, 11)),
    ((8, 0), (8, 1), (8, 2), (8, 3), (8, 4), (8, 5)),
)
# Side leaflets. Every leaflet touches its strand orthogonally so finish()
# outlines one solid silhouette (no floating outlined specks).
MOSS_LEAFLETS = (
    (5, 3), (6, 7), (5, 10),
    (11, 3), (12, 6), (13, 9),
    (9, 2),
)


def depth_tone(y):
    """One shared vertical ramp: #575044 canopy cores paling toward the tips,
    so all strands tell the same light story regardless of length."""
    if y <= 3:
        return MOSS_CORE
    if y <= 8:
        return MOSS_MID
    return MOSS_PALE


def pale_hanging_moss():
    img = canvas()
    for path in MOSS_STRANDS:
        for x, y in path:
            put(img, ((x, y),), depth_tone(y))
        if len(path) > 8:
            put(img, (path[-1],), MOSS_TIP)
    for x, y in MOSS_LEAFLETS:
        put(img, ((x, y),), depth_tone(y))
    return finish(img)


def main():
    for name, painter in (("respawn_door", respawn_door),
                          ("pale_hanging_moss", pale_hanging_moss)):
        img = painter()
        assert img.size == (16, 16) and img.mode == "RGBA"
        colors = {px[:3] for px in img.getdata() if px[3] >= 128}
        assert len(colors) <= 24, f"{name}: {len(colors)} opaque colors"
        save(img, OUT / f"{name}.png")


if __name__ == "__main__":
    main()
