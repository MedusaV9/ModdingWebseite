#!/usr/bin/env python3
"""Fog Revenant / Nebel-Wiedergänger texture driver (P6-W7).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3): a tall thin wraith consumed
by the fog storm — torn near-black robe cone (#23262E) with a ragged alpha-cutout hem,
fog-coral growths on one shoulder shading #5E6B7A -> #9DB3C9 toward the tips, long bone
claws (#C9C4B4), a skull face lost in shadow under the hood with two glowing cyan eye
slits, and three orbiting soul wisps (#8FD5E8).

Emissive (glowmask): the three `glow_wisp_*` cubes (auto-included, flame material stays
full-bright in the albedo too) + the two eye slits painted into the head bone's north
face via a custom glow painter. Everything else stays transparent in the glowmask.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/fog_revenant.py
Writes src/main/resources/assets/eclipse/textures/entity/fog_revenant.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, mix, mul, weave, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/fog_revenant.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/fog_revenant.png"

SEED = 0x0F06E7A2  # fog revenant

ROBE = hexc("#23262E")
ROBE_SLEEVE = hexc("#2A2E38")
HOOD = hexc("#1B1D24")
SKULL_SHADOW = hexc("#15171C")
SKULL_BONE = hexc("#8A8578")
EYE = hexc("#8FD5E8")
EYE_CORE = hexc("#DFFBFF")
CLAW = hexc("#C9C4B4")
GROWTH_BASE = hexc("#5E6B7A")
GROWTH_TIP = hexc("#9DB3C9")
WISP = hexc("#8FD5E8")
WISP_CORE = hexc("#DFFBFF")

_robe_weave = weave(ROBE, direction=1, amp=0.30)
_sleeve_weave = weave(ROBE_SLEEVE, direction=1, amp=0.26)


def skirt(px):
    """Torn robe cone: vertical cloth weave, a faint mist-silver sheen creeping up from
    the hem, and a ragged alpha-cutout bottom edge on the side faces (the robe dissolves
    into the fog it hovers over)."""
    if px.face in ("north", "south", "east", "west"):
        n = px.noise(55, y=0)
        cut = 0 if n < 0.30 else (1 if n < 0.72 else 2)
        if px.fy >= px.fh - cut:
            return None  # ragged, torn hem
    col = _robe_weave(px)
    if px.face in ("north", "south", "east", "west") and px.fh > 3:
        # Fog creep: the lowest intact rows pick up a pale mist tint.
        creep = (px.fy / (px.fh - 1.0)) ** 3
        col = mix(col, GROWTH_BASE, creep * 0.35)
    return col


def sleeve(px):
    """Arm sleeves: slightly lighter cloth so the long arms read against the robe."""
    return _sleeve_weave(px)


def claw(px):
    """Bone claws: pale weathered bone, knuckle shadow band, darker talon tips on the
    bottom rows so the hands read as split fingers rather than mitts."""
    col = mul(CLAW, 0.9 + px.noise(13) * 0.2)
    if px.face in ("north", "south", "east", "west"):
        if px.fy == 0:
            col = mul(col, 0.78)  # wrist/knuckle shadow against the sleeve
        if px.fy >= px.fh - 1:
            # Talon tips: alternating dark separations = individual claws.
            col = mul(col, 0.5) if px.gx % 2 == 0 else mul(col, 1.12)
    return col


def head(px):
    """The face under the hood: near-black shadow with faint skull planes and two
    vertical cyan eye slits (1 px wide, 2 px tall, mirrored) on the north face. The hood
    cube leaves the north face open, so this is what stares out."""
    if px.face == "north":
        if px.fx in (1, 4) and px.fy in (2, 3):
            return EYE_CORE if px.fy == 2 else EYE
        # Faint jaw/cheek bone hints below the eyes.
        if px.fy >= 4 and px.noise(23) > 0.62:
            return mix(SKULL_SHADOW, SKULL_BONE, 0.35)
    col = mul(SKULL_SHADOW, 0.9 + px.noise(41) * 0.2)
    return col


def growth(px):
    """Fog-coral shelf on the shoulder: base slate blue shading to pale mist toward the
    top of every face (tips catch the storm light), with darker pore pits."""
    t = 1.0 - (px.fy / max(px.fh - 1.0, 1.0)) if px.fh > 1 else 0.7
    col = mix(GROWTH_BASE, GROWTH_TIP, t * t)
    col = mul(col, 0.9 + px.noise(31) * 0.22)
    if px.noise(37) > 0.93:
        col = mul(col, 0.62)  # coral pore
    return col


def head_glow(px):
    """Glowmask for the head bone: ONLY the two eye slits burn (bright upper pixel,
    cooler lower) — the skull shadow stays dark at night."""
    if px.face == "north" and px.fx in (1, 4) and px.fy in (2, 3):
        return with_alpha(EYE_CORE if px.fy == 2 else EYE, 255 if px.fy == 2 else 220)
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("torso", weave(ROBE, direction=1, amp=0.26))
    painter.set_material("skirt_*", skirt)
    painter.set_material("hood", weave(HOOD, direction=0, amp=0.32))
    painter.set_material("head", head)
    painter.set_material("arm_*", sleeve)
    painter.set_material("claw_*", claw)
    painter.set_material("growth", growth)
    painter.set_material("glow_wisp_*", flame(WISP_CORE, WISP))
    # glow_wisp_* bones are auto-included in the glowmask; the eye slits need a custom
    # glow painter because the head bone is otherwise non-emissive.
    painter.set_glow_painter("head", head_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
