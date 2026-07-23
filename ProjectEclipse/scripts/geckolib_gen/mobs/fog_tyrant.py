#!/usr/bin/env python3
"""Fog Tyrant texture driver (P6-W11).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.4 "fog_tyrant" + W11 brief): the
fog-storm apex boss — a 4-block regal storm wraith in deep storm blue-black `#232830` /
wet slate `#2F343C`, with ELECTRIC SEAMS (wandering hairline cracks `#9FE8FF` →
`#CFF3FF`) across robe/torso/shoulders, layered tattered storm-cloaks fading to fog-bank
pale `#8496AB` at the hems, twin condensed-fog lance arms whose blade centerlines burn
electric, a caged storm core in the chest cavity, and a floating crown of shard-spikes.

Emissive (glowmask): the crown shards (`glow_crown_*` auto-included) + the chest core
(`glow_core` auto-included) + the two eyes + the lance edge centerlines + the electric
seams + a faint rim on the crown ring. All emissive pixels are ALSO painted bright in
the albedo (conventions doc §4 — they must still read under Iris shaderpacks).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/fog_tyrant.py
Writes src/main/resources/assets/eclipse/textures/entity/fog_tyrant.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, kelp, metal, mix, mul, weave  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/fog_tyrant.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/fog_tyrant.png"

SEED = 0x0F067154  # fog tyrant

ROBE = hexc("#232830")
ROBE_DARK = hexc("#1C2027")
SLATE = hexc("#2F343C")
CLOAK = hexc("#39414B")
CLOAK_HEM = hexc("#8496AB")
TATTER = hexc("#2A313A")
HEAD = hexc("#20242B")
CROWN_RING = hexc("#4A525E")
CAGE = hexc("#262B32")
LANCE = hexc("#5E6B7A")
SEAM_LO = hexc("#9FE8FF")
SEAM_HI = hexc("#CFF3FF")
EYE = hexc("#CFF3FF")
CORE = hexc("#E8FBFF")
CORE_TIP = hexc("#9FE8FF")
CROWN_CORE = hexc("#E8FBFF")
CROWN_TIP = hexc("#9FE8FF")


def seam_at(px, salt=41, spacing=11):
    """Wandering vertical electric seams every ~11 texels with breaks — shared by the
    albedo (bright paint) and the glowmask (emissive copy) so they always align."""
    column = px.gx // spacing
    wander = int(px.noise(salt, x=column, y=px.gy // 5) * 7.0) - 3
    if px.gx != column * spacing + 5 + wander:
        return False
    return px.noise(salt + 7) > 0.3


def seam_color(px):
    return mix(SEAM_LO, SEAM_HI, px.noise(93))


def storm_slate(base, salt=11, seams=True):
    """Wet storm slate: blocky tonal patches, rain-streak darkening, sparse pale
    flecks; optional electric-seam pixels painted bright (glow painter re-emits)."""

    def fn(px):
        if seams and seam_at(px, salt=salt + 30):
            return seam_color(px)
        patch = px.noise(salt, x=px.gx // 3, y=px.gy // 3)
        col = mul(base, 0.84 + patch * 0.3)
        streak = px.noise(salt + 4, x=px.gx // 2, y=0)
        if streak > 0.8:
            col = mul(col, 0.8)  # rain streak
        if px.noise(salt + 6) < 0.025:
            col = mul(col, 1.3)  # pale mineral fleck
        return col

    return fn


def seam_glow(salt=11):
    """Glow painter for the slate bones: emissive seams only (same salt as albedo)."""

    def fn(px):
        return seam_color(px) if seam_at(px, salt=salt + 30) else None

    return fn


def storm_cloak(px):
    """Layered storm-cloak: dark shoulders fading to fog-bank pale toward the hem,
    with a ragged alpha-cutout hem on the bottom rows (kelp-style)."""
    if px.face in ("north", "south", "east", "west"):
        n = px.noise(97, x=px.gx, y=0)
        cut = 0 if n < 0.3 else (1 if n < 0.7 else 3)
        if px.fy >= px.fh - cut:
            return None  # ragged hem
    t = (px.fy + 0.5) / px.fh  # down = pale (fog gathering at the hem)
    col = mix(CLOAK, CLOAK_HEM, t * 0.85)
    return mul(col, 0.86 + px.noise(53, y=px.gy // 3) * 0.28)


def hooded_head(px):
    """Hooded skull: near-black cowl, two hard electric eyes on the north face."""
    if px.face == "north" and px.fy == 3 and px.fx in (2, 5):
        return EYE
    if px.face == "north" and 2 <= px.fx <= 5 and 2 <= px.fy <= 5:
        return mul(HEAD, 0.72)  # shadowed face pit under the cowl
    return storm_slate(HEAD, salt=17, seams=False)(px)


def head_glow(px):
    if px.face == "north" and px.fy == 3 and px.fx in (2, 5):
        return EYE
    return None


def lance_blade(px):
    """Condensed-fog cleaver blade: slate metal with an electric centerline that
    brightens toward the tip (cube bottom = tip; blades hang point-down at rest)."""
    center = px.fw // 2
    if px.face in ("north", "south", "east", "west") and px.fx == center:
        t = (px.fy + 0.5) / px.fh
        return mix(SEAM_LO, SEAM_HI, t)
    return metal(LANCE, salt=23)(px)


def lance_glow(px):
    center = px.fw // 2
    if px.face in ("north", "south", "east", "west") and px.fx == center and px.fh > 4:
        t = (px.fy + 0.5) / px.fh
        return mix(SEAM_LO, SEAM_HI, t)
    return None


def crown_ring(px):
    """Tarnished storm-silver ring; the upper rim catches the crown light."""
    if px.face in ("north", "south", "east", "west") and px.fy == 0:
        return mix(CROWN_RING, SEAM_LO, 0.55)
    return metal(CROWN_RING, salt=29)(px)


def crown_ring_glow(px):
    if px.face in ("north", "south", "east", "west") and px.fy == 0:
        return mix(SEAM_LO, SEAM_HI, px.noise(31)) if px.noise(37) > 0.35 else None
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("robe", storm_slate(ROBE, salt=11))
    painter.set_material("robe_tatter_*", kelp(TATTER, salt=43, max_cut=3))
    painter.set_material("torso", storm_slate(SLATE, salt=13))
    painter.set_material("chest_cage", metal(CAGE, salt=19))
    painter.set_material("cloak_back", storm_cloak)
    painter.set_material("cloak_mid", storm_cloak)
    painter.set_material("shoulder_*", storm_slate(SLATE, salt=37))
    painter.set_material("arm_*", storm_slate(ROBE_DARK, salt=47, seams=False))
    painter.set_material("lance_*", lance_blade)
    painter.set_cube_material("lance_left", 0, weave(ROBE_DARK, direction=1, salt=59))
    painter.set_cube_material("lance_right", 0, weave(ROBE_DARK, direction=1, salt=61))
    painter.set_material("head", hooded_head)
    painter.set_material("crown", crown_ring)
    # glow_ bones (core + crown shards) auto-copy into the glowmask; flame material
    # keeps them shadeless so they stay full-bright in the albedo too (Iris rule).
    painter.set_material("glow_core", flame(CORE, CORE_TIP, salt=67))
    painter.set_material("glow_crown_*", flame(CROWN_CORE, CROWN_TIP, salt=71))
    # Emissive extras: electric seams, eyes, lance edges, crown-ring rim.
    painter.set_glow_painter("robe", seam_glow(11))
    painter.set_glow_painter("torso", seam_glow(13))
    painter.set_glow_painter("shoulder_*", seam_glow(37))
    painter.set_glow_painter("head", head_glow)
    painter.set_glow_painter("lance_*", lance_glow)
    painter.set_glow_painter("crown", crown_ring_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
