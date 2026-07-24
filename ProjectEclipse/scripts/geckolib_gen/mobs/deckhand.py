#!/usr/bin/env python3
"""Deckhand texture driver (P6-W2 GeckoLib remodel).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3 "deckhand v2"): keep the
drowned-ferryman-crew read of the old 7-cube model — murky waterlogged gray-greens, the
head pure shadow under the hood with two faint pale eyes — and extend the palette to the
new bones: a proper two-handed oar (dark wood loom/shaft, blade with a kelp-slimed
trailing edge) and two rope-belt tatters. NO emissive layer (the sheet is explicit); the
glowmask this run writes is intentionally empty and `DeckhandRenderer` never installs an
`AutoGlowingGeoLayer`.

Palette carried over from the retired `docs/uv/deckhand.md` v1 brief: robe #3A4038,
torso #2E3430, arms #343A32, hood #262B24, head shadow #141612 (+ pale eyes), oar wood
#5A452E, blade-edge kelp #22301F.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/deckhand.py
Writes src/main/resources/assets/eclipse/textures/entity/deckhand.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, kelp, mix, mul, weave, wood  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/deckhand.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/deckhand.png"

SEED = 0x0DECC4A2  # deckhand crew

ROBE = hexc("#3A4038")
TORSO = hexc("#2E3430")
ARM = hexc("#343A32")
HOOD = hexc("#262B24")
HEAD_SHADOW = hexc("#141612")
EYE = hexc("#7A8578")
OAR_WOOD = hexc("#5A452E")
KELP_EDGE = hexc("#22301F")
ROPE = hexc("#4A4232")


def head_shadow(px):
    """The face is a void under the hood: near-black with a wet sheen, plus two faint
    pale eyes on the north (front) face — same read as the v1 placeholder skin."""
    if px.face == "north" and px.fy == 3 and px.fx in (2, 5):
        return EYE
    col = mul(HEAD_SHADOW, 0.92 + px.noise(41) * 0.16)
    return col


_blade_wood = wood(OAR_WOOD, salt=19)


def blade(px):
    """Oar blade: waterlogged plank with a kelp-slimed trailing edge (the bottom rows of
    the east/west flats — the edge that drags through the water every stroke)."""
    col = _blade_wood(px)
    if px.face in ("east", "west"):
        if px.fy >= px.fh - 1 or (px.fy >= px.fh - 2 and px.noise(23) > 0.45):
            return mix(KELP_EDGE, col, 0.2)
        if px.noise(27) > 0.93:
            return mix(KELP_EDGE, col, 0.45)  # slime flecks up the face
    return col


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("robe", weave(ROBE, direction=1))
    painter.set_material("torso", weave(TORSO, direction=1))
    painter.set_material("arm_*", weave(ARM, direction=1, amp=0.28))
    painter.set_material("hood", weave(HOOD, direction=0, amp=0.30))
    painter.set_material("head", head_shadow)
    painter.set_material("oar_loom", wood(OAR_WOOD))
    painter.set_material("oar_shaft", wood(OAR_WOOD))
    painter.set_material("oar_blade", blade)
    painter.set_material("tatter_*", kelp(ROPE, max_cut=1))
    # No set_glow / set_glow_painter calls: the deckhand ships NO emissive regions, so
    # the _glowmask.png is written fully transparent (and stays unused at runtime).
    painter.paint(OUT)


if __name__ == "__main__":
    main()
