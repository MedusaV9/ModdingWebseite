#!/usr/bin/env python3
"""Fog Colossus texture driver (P6-W8).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3 "fog_colossus"): a hulking
round-shouldered brute overgrown by the fog — cracked storm-slate `#3E444D` body with
GLOWING FISSURES (wandering vertical cracks, `#8FD5E8` → `#CFF3FF`), fog-coral shelf
growths on back/shoulders (`#77879B` → `#B7C9DC` vertical gradient), tiny head sunk
between the shoulders with two pale storm-lit eyes, massive flat-knuckle forearms.

Emissive (glowmask): the fissure pixels on body/shoulders/forearms/legs/back slabs +
the two eyes. Fissures are also painted bright in the ALBEDO (conventions doc §4 —
they must still read under Iris shaderpacks, which dim glow layers).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/fog_colossus.py
Writes src/main/resources/assets/eclipse/textures/entity/fog_colossus.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, mix, mul  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/fog_colossus.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/fog_colossus.png"

SEED = 0x0F06C010  # fog colossus

SLATE = hexc("#3E444D")
SLATE_DARK = hexc("#33383F")
SLATE_LEG = hexc("#363C44")
FISSURE_LO = hexc("#8FD5E8")
FISSURE_HI = hexc("#CFF3FF")
CORAL_LO = hexc("#77879B")
CORAL_HI = hexc("#B7C9DC")
HEAD_STONE = hexc("#31363D")
EYE = hexc("#CFF3FF")


def fissure_at(px, salt=61):
    """Wandering vertical crack lines every ~13 texels, with breaks — shared by the
    albedo (bright paint) and the glowmask (emissive copy) so they always align."""
    column = px.gx // 13
    wander = int(px.noise(salt, x=column, y=px.gy // 4) * 7.0) - 3
    if px.gx != column * 13 + 6 + wander:
        return False
    return px.noise(salt + 7) > 0.22


def fissure_color(px):
    return mix(FISSURE_LO, FISSURE_HI, px.noise(97))


def cracked_slate(base, salt=11, fissures=True):
    """Storm-slate: blocky tonal patches, dark pits, sparse pale flecks; optional
    glowing-fissure pixels painted bright (the glow painter re-emits them)."""

    def fn(px):
        if fissures and fissure_at(px):
            return fissure_color(px)
        patch = px.noise(salt, x=px.gx // 3, y=px.gy // 3)
        col = mul(base, 0.82 + patch * 0.34)
        if px.noise(salt + 5) > 0.955:
            col = mul(col, 0.62)  # weather pit
        elif px.noise(salt + 6) < 0.03:
            col = mul(col, 1.28)  # pale mineral fleck
        return col

    return fn


def fissure_glow(px):
    """Glow painter for the slate bones: emissive fissures only."""
    return fissure_color(px) if fissure_at(px) else None


def fog_coral(px):
    """Shelf growths: fog gradient dark base -> pale tips (up = pale), ragged dither."""
    t = 1.0 - (px.fy + 0.5) / px.fh
    if px.face == "up":
        t = 0.95
    elif px.face == "down":
        t = 0.1
    col = mix(CORAL_LO, CORAL_HI, t)
    return mul(col, 0.88 + px.noise(71) * 0.24)


def head_stone(px):
    """Sunken head: darker slate, two pale storm-lit eyes on the north face."""
    if px.face == "north" and px.fy == 3 and px.fx in (1, 5):
        return EYE
    return cracked_slate(HEAD_STONE, salt=13, fissures=False)(px)


def head_glow(px):
    if px.face == "north" and px.fy == 3 and px.fx in (1, 5):
        return EYE
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("body", cracked_slate(SLATE))
    painter.set_material("shoulders", cracked_slate(SLATE))
    painter.set_material("back_slab_*", cracked_slate(SLATE_DARK, salt=17))
    painter.set_material("arm_*", cracked_slate(SLATE, salt=19, fissures=False))
    painter.set_material("forearm_*", cracked_slate(SLATE, salt=23))
    painter.set_material("leg_*", cracked_slate(SLATE_LEG, salt=29))
    painter.set_material("shelf_*", fog_coral)
    painter.set_material("head", head_stone)
    # Emissive: fissures on every cracked-slate bone + the eyes. Shelves stay dark.
    painter.set_glow_painter("body", fissure_glow)
    painter.set_glow_painter("shoulders", fissure_glow)
    painter.set_glow_painter("back_slab_*", fissure_glow)
    painter.set_glow_painter("forearm_*", fissure_glow)
    painter.set_glow_painter("leg_*", fissure_glow)
    painter.set_glow_painter("head", head_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
