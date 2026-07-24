#!/usr/bin/env python3
"""Rift Warden / Risswächter texture driver (P6-W910).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.4): a 3-block vertically-split
wraith-knight — the LEFT half wears polished obsidian plate `#1B1D26`/`#2E3242`, the
RIGHT half of the torso is simply GONE, replaced by the `glow_rift_core` void-tear
volume shading `#B98CFF -> #5E2EA8` with three drifting `glow_shard_*` fragments.
Single-horned helm with a violet eye slit, split floating pauldrons, twin curved
rift-blades whose cutting edges burn.

Emissive (glowmask): the rift half (`glow_rift_core`, `glow_shard_*`, `glow_under` —
all auto-included via the `glow_` prefix), the helm eye slit, and the honed edge
column of both blades (custom glow painters).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/rift_warden.py
Writes src/main/resources/assets/eclipse/textures/entity/rift_warden.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, metal, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/rift_warden.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/rift_warden.png"

SEED = 0x217F0A2D  # rift warden

ARMOR = hexc("#1B1D26")
ARMOR_HI = hexc("#2E3242")
ARMOR_EDGE = hexc("#4A5068")
HORN = hexc("#3A3648")
RIFT = hexc("#B98CFF")
RIFT_DEEP = hexc("#5E2EA8")
RIFT_CORE = hexc("#E9DCFF")
BLADE = hexc("#232732")
BLADE_EDGE = hexc("#B98CFF")
EYE = hexc("#B98CFF")
EYE_CORE = hexc("#E9DCFF")

_plate = metal(ARMOR)
_plate_hi = metal(ARMOR_HI, salt=19)


def armor_plate(px):
    """Obsidian plate: brushed near-black steel with a lighter beveled rim row so
    every plate reads as a separate forged piece."""
    col = _plate(px)
    if px.face in ("north", "south", "east", "west") and px.fh > 2 and px.fy == 0:
        col = mix(col, ARMOR_EDGE, 0.55)  # bevel highlight along the plate top
    return col


def pauldron(px):
    """Floating pauldrons: brighter polished plate with a violet reflection creeping
    along the inner (down) faces — they hover beside the rift half."""
    col = _plate_hi(px)
    if px.face == "down":
        col = mix(col, RIFT_DEEP, 0.4)
    elif px.face == "up" and px.noise(43) > 0.9:
        col = mix(col, ARMOR_EDGE, 0.6)  # worn rim glint
    return col


def helm(px):
    """Horned helm: polished plate; the north face carries a 1px violet eye slit
    (row 3, cols 1-4) burning out of a recessed shadow band."""
    if px.face == "north":
        if px.fy == 3 and 1 <= px.fx <= 4:
            return EYE_CORE if px.fx in (2, 3) else EYE
        if px.fy in (2, 4) and 1 <= px.fx <= 4:
            return mul(ARMOR, 0.6)  # visor shadow around the slit
    return _plate_hi(px)


def _blade_edge_px(px):
    """The honed edge: front column (fx 0) of every side face of the blade cubes."""
    return px.face in ("north", "south", "east", "west") and px.fx == 0


def blade(px):
    """Curved rift-blade: near-black steel body, violet burning edge column, and a
    faint rift shimmer creeping up from the tip rows."""
    if _blade_edge_px(px):
        return mix(BLADE_EDGE, RIFT_CORE, 0.3) if px.fy % 4 == 0 else BLADE_EDGE
    col = mul(BLADE, 0.88 + px.noise(13) * 0.24)
    if px.face in ("north", "south", "east", "west") and px.fh > 4 and px.fy >= px.fh - 2:
        col = mix(col, RIFT_DEEP, 0.35)  # tip shimmer
    return col


def blade_glow(px):
    """Glowmask for the blades: only the edge column burns."""
    if _blade_edge_px(px):
        return with_alpha(BLADE_EDGE, 235)
    return None


def helm_glow(px):
    """Glowmask for the helm: only the eye slit."""
    if px.face == "north" and px.fy == 3 and 1 <= px.fx <= 4:
        return with_alpha(EYE_CORE if px.fx in (2, 3) else EYE, 255 if px.fx in (2, 3) else 225)
    return None


def rift_core(px):
    """The void tear that replaces the torso's right half: bright core fading to deep
    violet at the rim, with dark reality-static flecks drifting through it."""
    base = flame(RIFT_CORE, RIFT_DEEP)(px)
    if px.noise(61) > 0.92:
        return mul(RIFT_DEEP, 0.55)  # void static
    return base


rift_core.shadeless = True


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("faulds", armor_plate)
    painter.set_material("hips", armor_plate)
    painter.set_material("torso", armor_plate)
    painter.set_material("pauldron_*", pauldron)
    painter.set_material("head", helm)
    painter.set_material("horn", metal(HORN, salt=29))
    painter.set_material("arm_armor", armor_plate)
    painter.set_material("arm_rift", flame(RIFT, RIFT_DEEP))
    painter.set_material("blade_*", blade)
    painter.set_material("glow_rift_core", rift_core)
    painter.set_material("glow_shard_*", flame(RIFT_CORE, RIFT))
    painter.set_material("glow_under", flame(RIFT_DEEP, mul(RIFT_DEEP, 0.5)))
    painter.set_glow("arm_rift", 0.85)  # the rift-side arm is part of the tear
    painter.set_glow_painter("blade_left", blade_glow)
    painter.set_glow_painter("blade_right", blade_glow)
    painter.set_glow_painter("head", helm_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
