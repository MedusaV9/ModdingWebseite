#!/usr/bin/env python3
"""Orin the Sun-Reader / Orin der Sonnenleser texture driver (W4-WIZARD).

Design sheet (docs/plans_v3/ideas_wave4/IDEA-19_wand.md §3): a hermit astronomer NPC —
midnight-blue robe embroidered with constellations (tiny glow stitches), long silver
beard, pointed hat with a star charm, warm lantern-lit face, brass telescope details,
short wooden staff with a starlit tip. Palette: robe #1E2748 / #161C36, stitches
#F5E6B8→#9FC4FF, beard silver #C9CCD4, skin #E8B98A, brass #B08D42, staff oak #6B4A2E.
Emissive: constellation stitches + hat star + staff tip (auto via `glow_` bones and
custom stitch glow painters).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/wizard_orin.py
Writes src/main/resources/assets/eclipse/textures/entity/wizard_orin.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import (  # noqa: E402
    GeoPainter, flame, hexc, metal, mix, mul, weave, with_alpha, wood,
)

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/wizard_orin.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/wizard_orin.png"

SEED = 0x0517A2D1  # wizard orin

MIDNIGHT = hexc("#1E2748")        # robe body blue
MIDNIGHT_DEEP = hexc("#161C36")   # hood/hat shadow blue
STITCH_GOLD = hexc("#F5E6B8")     # constellation embroidery, warm
STITCH_BLUE = hexc("#9FC4FF")     # constellation embroidery, cold
BRASS = hexc("#B08D42")
SCARF = hexc("#3D3A66")
BEARD = hexc("#C9CCD4")
SKIN = hexc("#E8B98A")            # warm lantern-lit face
EYE = hexc("#2B2118")
STAFF_OAK = hexc("#6B4A2E")
STAR_CORE = hexc("#FFF7DC")
STAR_GOLD = hexc("#FFE9A6")
TIP_CORE = hexc("#EAF6FF")
TIP_BLUE = hexc("#BFE2FF")

STITCH_SALT = 41   # one shared salt keeps albedo stitches + glowmask in lockstep


def _stitch_at(px, rate):
    """Deterministic constellation stitch predicate (never on up/down faces —
    embroidery reads on the visible robe sides only)."""
    if px.face in ("up", "down"):
        return False
    return px.noise(STITCH_SALT) > rate


def _stitch_color(px):
    return mix(STITCH_GOLD, STITCH_BLUE, px.noise(STITCH_SALT + 1))


def robe(base, rate=0.955, belt_row=None):
    """Midnight cloth weave with embroidered constellation stitches; optional
    brass belt band at face-local row `belt_row` (side faces only)."""
    cloth = weave(base, direction=1, amp=0.28)

    def fn(px):
        if (belt_row is not None and px.face in ("north", "south", "east", "west")
                and px.fy == belt_row):
            return mul(BRASS, 0.9 + px.noise(9) * 0.2)
        if _stitch_at(px, rate):
            return _stitch_color(px)
        return cloth(px)
    return fn


def stitch_glow(rate=0.955):
    """Glowmask: ONLY the constellation stitches, softly emissive."""
    def fn(px):
        if _stitch_at(px, rate):
            return with_alpha(_stitch_color(px), 190)
        return None
    return fn


def head_material(px):
    """Front face = warm lantern-lit skin with eyes + brows; the rest hood-blue."""
    if px.face == "north":
        if px.fy == 2 and px.fx in (1, 3):
            return EYE                      # deep-set eyes
        if px.fy == 1 and px.fx in (1, 3):
            return mul(BEARD, 0.82)         # bushy silver brows
        warm = 0.9 + (1.0 - abs(px.fx - 2) / 2.0) * 0.14  # lantern falloff to center
        return mul(SKIN, warm + (px.noise(3) - 0.5) * 0.08)
    return weave(MIDNIGHT_DEEP, 1, 0.22)(px)


def beard_material(px):
    """Long silver beard: vertical strand streaks + a few dark partings."""
    streak = px.noise(17, y=px.gy // 2)
    col = mul(BEARD, 0.8 + streak * 0.34)
    if px.noise(19, x=px.gx, y=0) > 0.9:
        col = mul(col, 0.72)  # parting shadow strand
    return col


def main():
    painter = GeoPainter(GEO, seed=SEED)

    painter.set_material("robe_lower", robe(MIDNIGHT, rate=0.945))
    painter.set_material("torso", robe(MIDNIGHT, rate=0.955, belt_row=7))
    painter.set_material("arm_*", robe(MIDNIGHT_DEEP, rate=0.965))
    painter.set_material("scarf", weave(SCARF, direction=2, amp=0.3))
    painter.set_material("head", head_material)
    painter.set_material("beard", beard_material)
    # hat: brim + cone + tip all carry sparse stitches (same predicate as the
    # glow painter below, so albedo stitches and glowmask stay in lockstep)
    painter.set_material("hat", robe(MIDNIGHT_DEEP, rate=0.94))
    painter.set_material("spyglass", metal(BRASS))
    painter.set_material("staff", wood(STAFF_OAK))
    painter.set_material("glow_hat_star", flame(STAR_CORE, STAR_GOLD))
    painter.set_material("glow_staff_tip", flame(TIP_CORE, TIP_BLUE))

    # Emissive constellation stitches (glow_ bones are auto-included full-bright).
    painter.set_glow_painter("robe_lower", stitch_glow(rate=0.945))
    painter.set_glow_painter("torso", stitch_glow(rate=0.955))
    painter.set_glow_painter("arm_*", stitch_glow(rate=0.965))
    painter.set_glow_painter("hat", stitch_glow(rate=0.94))

    painter.paint(OUT)


if __name__ == "__main__":
    main()
