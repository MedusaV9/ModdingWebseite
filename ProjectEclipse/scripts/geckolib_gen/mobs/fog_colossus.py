#!/usr/bin/env python3
"""Fog Colossus texture driver (P6-W8, reworked by FXTEAM MOB-FOG).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3 "fog_colossus") + the MOB-FOG
palette pass (docs/plans_v3/plans_v5/fxteams/MOB-FOG.md): a hulking round-shouldered
brute overgrown by the fog — cracked storm-slate `#3E444D` body with GLOWING FISSURES
(wandering vertical cracks, sick green `#A9F07E` -> pale `#E9FFD8` with violet
`#9C63E8` flecks), fog-coral shelf growths on back/shoulders (`#77879B` -> pale-violet
`#B9B3DC` vertical gradient), a CHEST MAW (jagged glowing split across the sternum —
the `maw` bone breathes/gapes in the anims), three back spines with glowing tips, and
one massively over-built right arm (inflate asymmetry in the geo). A faint violet RIM
GLOW rides the top edge of the silhouette bones (shoulders/slabs/shelves).

Emissive (glowmask): fissures on body/shoulders/forearms/legs/slabs, both eyes, the maw
gap pixels, the spine tips, and the low-alpha violet rim. Fissures/maw are also painted
bright in the ALBEDO (conventions doc §4 — they must still read under Iris shaderpacks,
which dim glow layers).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/fog_colossus.py
Writes src/main/resources/assets/eclipse/textures/entity/fog_colossus.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/fog_colossus.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/fog_colossus.png"

SEED = 0x0F06C010  # fog colossus

SLATE = hexc("#3E444D")
SLATE_DARK = hexc("#33383F")
SLATE_LEG = hexc("#363C44")
HEAD_STONE = hexc("#31363D")
# MOB-FOG family glow: sick green core -> violet rim.
GLOW_PALE = hexc("#E9FFD8")
GLOW_GREEN = hexc("#A9F07E")
GLOW_VIOLET = hexc("#9C63E8")
RIM_VIOLET = hexc("#6F52B8")
CORAL_LO = hexc("#77879B")
CORAL_HI = hexc("#B9B3DC")
MAW_PIT = hexc("#14161B")
EYE = hexc("#D6FFB8")


def fissure_at(px, salt=61):
    """Wandering vertical crack lines every ~13 texels, with breaks — shared by the
    albedo (bright paint) and the glowmask (emissive copy) so they always align."""
    column = px.gx // 13
    wander = int(px.noise(salt, x=column, y=px.gy // 4) * 7.0) - 3
    if px.gx != column * 13 + 6 + wander:
        return False
    return px.noise(salt + 7) > 0.22


def fissure_color(px):
    """Sick green light with pale hot spots and sparse violet flecks."""
    n = px.noise(97)
    if n < 0.18:
        return GLOW_VIOLET
    return mix(GLOW_GREEN, GLOW_PALE, (n - 0.18) / 0.82)


def rim_at(px):
    """Violet rim light: the top pixel row of the vertical faces (storm light grazing
    the silhouette from above)."""
    return px.face in ("north", "south", "east", "west") and px.fy == 0 and px.fh > 3


def cracked_slate(base, salt=11, fissures=True, rim=False):
    """Storm-slate: blocky tonal patches, dark pits, sparse pale flecks; optional
    glowing-fissure pixels painted bright (the glow painter re-emits them) and an
    optional violet rim tint on the top edge."""

    def fn(px):
        if fissures and fissure_at(px):
            return fissure_color(px)
        patch = px.noise(salt, x=px.gx // 3, y=px.gy // 3)
        col = mul(base, 0.82 + patch * 0.34)
        if px.noise(salt + 5) > 0.955:
            col = mul(col, 0.62)  # weather pit
        elif px.noise(salt + 6) < 0.03:
            col = mul(col, 1.28)  # pale mineral fleck
        if rim and rim_at(px):
            col = mix(col, RIM_VIOLET, 0.55)
        return col

    return fn


def slate_glow(rim=False):
    """Glow painter for the slate bones: emissive fissures, plus the faint violet rim
    (low alpha so it reads as grazing light, not neon piping)."""

    def fn(px):
        if fissure_at(px):
            return fissure_color(px)
        if rim and rim_at(px):
            return with_alpha(RIM_VIOLET, 90)
        return None

    return fn


def fog_coral(px):
    """Shelf growths: fog gradient dark base -> pale-violet tips (up = pale), dither."""
    t = 1.0 - (px.fy + 0.5) / px.fh
    if px.face == "up":
        t = 0.95
    elif px.face == "down":
        t = 0.1
    col = mix(CORAL_LO, CORAL_HI, t)
    return mul(col, 0.88 + px.noise(71) * 0.24)


def head_stone(px):
    """Sunken head: darker slate, two sick-green storm-lit eyes on the north face."""
    if px.face == "north" and px.fy == 3 and px.fx in (1, 5):
        return EYE
    return cracked_slate(HEAD_STONE, salt=13, fissures=False)(px)


def head_glow(px):
    if px.face == "north" and px.fy == 3 and px.fx in (1, 5):
        return EYE
    return None


def maw_gap_at(px):
    """The glowing split of the chest maw (12x10 north face): a jagged horizontal gash
    across rows 3-6 whose lips wander per column, with tooth columns bridging it."""
    if px.face != "north":
        return False
    lip = 3 + int(px.noise(103, x=px.gx, y=0) * 2.0)        # top lip row: 3..4
    depth = 2 + int(px.noise(107, x=px.gx, y=1) * 2.0)      # gap height: 2..3
    if not (lip <= px.fy < lip + depth):
        return False
    tooth = px.noise(109, x=px.gx, y=0) > 0.72              # slate teeth bridge the gap
    return not (tooth and px.fy == lip)


def maw(px):
    """Chest maw albedo: cracked dark pit with the glowing gash burned in bright."""
    if maw_gap_at(px):
        edge = px.noise(113)
        if edge < 0.22:
            return GLOW_VIOLET  # violet at the lips
        return mix(GLOW_GREEN, GLOW_PALE, (edge - 0.22) / 0.78)
    col = mul(MAW_PIT, 0.85 + px.noise(117) * 0.3)
    if px.fy in (2, 7) and px.noise(119) > 0.5:
        col = mul(col, 1.35)  # bruised rock lips around the gash
    return col


# Emissive-dominant overlay plate: skip directional shading + the 1px outline so the
# albedo gash stays as bright as its glowmask copy (Iris parity, conventions §4).
maw.shadeless = True


def maw_glow(px):
    return maw(px) if maw_gap_at(px) else None


def spine(px):
    """Back spines: dark slate shard with a glowing tip — the top 2 rows of every side
    face plus the whole up face burn green->violet."""
    if spine_tip_at(px):
        return mix(GLOW_GREEN, GLOW_VIOLET, px.noise(127))
    return cracked_slate(SLATE_DARK, salt=31, fissures=False)(px)


# Small mostly-emissive shards: shadeless keeps the burning tips at full brightness
# (the 2px-wide faces get no outline anyway; the flat slate base is unnoticeable).
spine.shadeless = True


def spine_tip_at(px):
    if px.face == "up":
        return True
    return px.face in ("north", "south", "east", "west") and px.fy <= 1


def spine_glow(px):
    if spine_tip_at(px):
        return mix(GLOW_GREEN, GLOW_VIOLET, px.noise(127))
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("body", cracked_slate(SLATE))
    painter.set_material("maw", maw)
    painter.set_material("shoulders", cracked_slate(SLATE, rim=True))
    painter.set_material("back_slab_*", cracked_slate(SLATE_DARK, salt=17, rim=True))
    painter.set_material("spine_*", spine)
    painter.set_material("arm_*", cracked_slate(SLATE, salt=19, fissures=False))
    painter.set_material("forearm_*", cracked_slate(SLATE, salt=23))
    painter.set_material("leg_*", cracked_slate(SLATE_LEG, salt=29))
    painter.set_material("shelf_*", fog_coral)
    painter.set_material("head", head_stone)
    # Emissive: fissures + rim on the silhouette bones, maw gash, spine tips, eyes.
    painter.set_glow_painter("body", slate_glow())
    painter.set_glow_painter("maw", maw_glow)
    painter.set_glow_painter("shoulders", slate_glow(rim=True))
    painter.set_glow_painter("back_slab_*", slate_glow(rim=True))
    painter.set_glow_painter("spine_*", spine_glow)
    painter.set_glow_painter("forearm_*", slate_glow())
    painter.set_glow_painter("leg_*", slate_glow())
    painter.set_glow_painter("head", head_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
