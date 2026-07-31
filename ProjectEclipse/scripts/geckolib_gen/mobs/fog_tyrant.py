#!/usr/bin/env python3
"""Fog Tyrant texture driver (P6-W11, refined by MOB-BOSS2).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.4 "fog_tyrant" + W11 brief): the
fog-storm apex boss — a 4-block regal storm wraith in deep storm blue-black `#232830` /
wet slate `#2F343C`, with ELECTRIC SEAMS (wandering hairline cracks `#9FE8FF` →
`#CFF3FF`) across robe/torso/shoulders, layered tattered storm-cloaks fading to fog-bank
pale `#8496AB` at the hems, twin condensed-fog lance arms whose blade centerlines burn
electric, a caged storm core in the chest cavity, a floating crown of shard-spikes, and
(MOB-BOSS2) fog-plume shoulder wisps that dissolve upward plus a completed 4-bar core
cage whose inner rows catch the core light.

The robe carries the MOB-BOSS2 LAYERED FOG GRADIENT: four dither-edged fog strata that
lighten toward the hem, so the monarch reads as wading hip-deep in his own storm.

MA1 (mob census wave): the cloak is now a 4-SEGMENT CHAIN (cloak_back → cloak_mid →
cloak_low → cloak_hem, follow-through keyframes in the anim sheet); the cloak gradient
runs across the whole chain via `storm_cloak_chain(seg)` so the plates read as one cape.

Emissive (glowmask): the crown shards (`glow_crown_*` auto-included) + the chest core
(`glow_core` auto-included, white-hot heart + arc-flicker rim) + the two eyes + the
lance edge centerlines + the electric seams + a faint rim on the crown ring + the
core-lit middle rows of the cage bars. All emissive pixels are ALSO painted bright in
the albedo (conventions doc §4 — they must still read under Iris shaderpacks). The
shoulder wisps stay non-emissive on purpose: they are condensed fog, not storm-light.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/fog_tyrant.py
Writes src/main/resources/assets/eclipse/textures/entity/fog_tyrant.png + _glowmask.png.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, kelp, metal, mix, mul, weave, with_alpha  # noqa: E402

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
CORE_HOT = hexc("#F6FEFF")
CROWN_CORE = hexc("#E8FBFF")
CROWN_TIP = hexc("#9FE8FF")
WISP_PALE = hexc("#8E9FB4")


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


def robe_fog(base, salt=11):
    """MOB-BOSS2 layered fog gradient: the storm-slate robe sinks through four
    dither-edged fog strata that lighten toward the hem (down = pale — the monarch
    wades in his own storm). Electric seams stay untouched on top of the layers."""
    slate = storm_slate(base, salt=salt)

    def fn(px):
        col = slate(px)
        if px.face in ("north", "south", "east", "west") and not seam_at(px, salt=salt + 30):
            t = (px.fy + 0.5) / px.fh
            jitter = (px.noise(salt + 77, x=px.gx // 2, y=0) - 0.5) * 0.28
            band = max(0, min(3, int((t + jitter) * 4.0)))  # stratum 0 (top) .. 3 (hem)
            if band:
                col = mix(col, CLOAK_HEM, 0.13 * band)
        return col

    return fn


def fog_wisp(px):
    """Shoulder fog plume: dense cloak-slate at the base dissolving to fog-bank pale
    with a ragged alpha cutout on the TOP rows — the plume dissipates upward (the
    inverse of the kelp-hem rag). Deliberately non-emissive: condensed fog, not light."""
    if px.face in ("north", "south", "east", "west"):
        n = px.noise(83, x=px.gx, y=0)
        cut = 0 if n < 0.3 else (1 if n < 0.7 else 2)
        if px.fy < cut:
            return None  # dissipating crest
    t = 1.0 - (px.fy + 0.5) / px.fh  # up = pale
    col = mix(CLOAK, WISP_PALE, t * 0.9)
    return mul(col, 0.85 + px.noise(89, y=px.gy // 2) * 0.3)


def storm_core(px):
    """The caged chest core: white-hot heart, electric mid falloff, and an arc-flicker
    rim — the fight's brightest pixel cluster (it gutters via CORE_LIT, not paint)."""
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = math.hypot((px.fx - cx) / max(cx, 0.5), (px.fy - cy) / max(cy, 0.5))
    if d < 0.4:
        return CORE_HOT
    if d > 0.95 and px.noise(67) > 0.55:
        return mix(SEAM_LO, CORE, px.noise(69))  # rim arc flicker
    return mix(CORE, CORE_TIP, min(1.0, d * 0.9 + (px.noise(68) - 0.5) * 0.2))


storm_core.shadeless = True


def _cage_lit(px):
    """0..0.5 distance from the bar's long-axis midline (ribs are wide, bars tall)."""
    if px.face not in ("north", "south", "east", "west"):
        return 1.0
    if px.fw > px.fh:
        return abs((px.fx + 0.5) / px.fw - 0.5)
    return abs((px.fy + 0.5) / px.fh - 0.5)


def cage_bar(px):
    """Cage bars/ribs: dark metal whose middle rows face the caged core and catch its
    light (painted bright + faintly emissive — the cage silhouettes against the glow)."""
    col = metal(CAGE, salt=19)(px)
    lit = _cage_lit(px)
    if lit < 0.22:
        col = mix(col, SEAM_LO, 0.5 - lit)
    return col


def cage_glow(px):
    """Glowmask for the cage: only the core-lit midline pixels, at reduced strength."""
    if _cage_lit(px) < 0.22 and px.noise(73) > 0.35:
        return with_alpha(mix(SEAM_LO, CORE, px.noise(75)), 140)
    return None


def storm_cloak_chain(seg, total=4):
    """One segment of the MA1 4-segment cloak chain (cloak_back → mid → low → hem):
    the dark→fog-bank-pale gradient runs across the WHOLE chain — the segment index
    offsets the band, so the four plates read as one cape even when the follow-through
    keyframes fan them apart. Ragged kelp-style alpha hem only on the LAST segment
    (intermediate cut rows would open horizontal slits at every hinge)."""

    def fn(px):
        if seg == total - 1 and px.face in ("north", "south", "east", "west"):
            n = px.noise(97, x=px.gx, y=0)
            cut = 0 if n < 0.3 else (1 if n < 0.7 else 3)
            if px.fy >= px.fh - cut:
                return None  # ragged hem (chain terminus only)
        t = (seg + (px.fy + 0.5) / px.fh) / total  # down THE CHAIN = pale
        col = mix(CLOAK, CLOAK_HEM, t * 0.85)
        return mul(col, 0.86 + px.noise(53, y=px.gy // 3) * 0.28)

    return fn


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
    painter.set_material("robe", robe_fog(ROBE, salt=11))
    painter.set_material("robe_tatter_*", kelp(TATTER, salt=43, max_cut=3))
    painter.set_material("torso", storm_slate(SLATE, salt=13))
    painter.set_material("chest_cage", cage_bar)
    painter.set_material("cloak_back", storm_cloak_chain(0))
    painter.set_material("cloak_mid", storm_cloak_chain(1))
    painter.set_material("cloak_low", storm_cloak_chain(2))
    painter.set_material("cloak_hem", storm_cloak_chain(3))
    painter.set_material("shoulder_*", storm_slate(SLATE, salt=37))
    painter.set_material("wisp_*", fog_wisp)
    painter.set_material("arm_*", storm_slate(ROBE_DARK, salt=47, seams=False))
    painter.set_material("lance_*", lance_blade)
    painter.set_cube_material("lance_left", 0, weave(ROBE_DARK, direction=1, salt=59))
    painter.set_cube_material("lance_right", 0, weave(ROBE_DARK, direction=1, salt=61))
    painter.set_material("head", hooded_head)
    painter.set_material("crown", crown_ring)
    # glow_ bones (core + crown shards) auto-copy into the glowmask; shadeless materials
    # keep them full-bright in the albedo too (Iris rule).
    painter.set_material("glow_core", storm_core)
    painter.set_material("glow_crown_*", flame(CROWN_CORE, CROWN_TIP, salt=71))
    # Emissive extras: electric seams, eyes, lance edges, crown-ring rim, cage midlines.
    painter.set_glow_painter("robe", seam_glow(11))
    painter.set_glow_painter("torso", seam_glow(13))
    painter.set_glow_painter("shoulder_*", seam_glow(37))
    painter.set_glow_painter("head", head_glow)
    painter.set_glow_painter("lance_*", lance_glow)
    painter.set_glow_painter("crown", crown_ring_glow)
    painter.set_glow_painter("chest_cage", cage_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
