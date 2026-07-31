#!/usr/bin/env python3
"""Fog Revenant / Nebel-Wiedergänger texture driver (P6-W7, reworked by FXTEAM MOB-FOG).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3) + the MOB-FOG palette pass
(docs/plans_v3/plans_v5/fxteams/MOB-FOG.md): a tall thin wraith consumed by the fog
storm — torn near-black robe cone (#23262E) with a ragged alpha-cutout hem and four
trailing TATTER strips, each a 2-segment chain since MB6 (`tatter_*` root +
`tatter_*_tip` free end — the rag cut lives on the tips), long grasp arms with a new forearm
segment reaching almost to the ground, bone claws (#C9C4B4), a skull face lost in
shadow under the hood with two sick-green eye slits (#A9F07E -> #E9FFD8 core), fog-coral
growths shading toward pale violet (#B9B3DC), three orbiting soul wisps (pale green core
-> violet #9C63E8 tips) and a faint violet rim (#6F52B8) grazing the hood crown.

Emissive (glowmask): the three `glow_wisp_*` cubes (auto-included), the two eye slits,
and the low-alpha hood rim. Everything else stays transparent in the glowmask.

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
CLAW = hexc("#C9C4B4")
GROWTH_BASE = hexc("#5E6B7A")
GROWTH_TIP = hexc("#B9B3DC")
# MOB-FOG family glow: sick green core -> violet rim.
EYE = hexc("#A9F07E")
EYE_CORE = hexc("#E9FFD8")
WISP = hexc("#9C63E8")
WISP_CORE = hexc("#E9FFD8")
RIM_VIOLET = hexc("#6F52B8")
MIST_VIOLET = hexc("#6B5F8C")

_robe_weave = weave(ROBE, direction=1, amp=0.30)
_sleeve_weave = weave(ROBE_SLEEVE, direction=1, amp=0.26)


def skirt(px):
    """Torn robe cone: vertical cloth weave, a violet fog-mist sheen creeping up from
    the hem, and a ragged alpha-cutout bottom edge on the side faces (the robe dissolves
    into the fog it hovers over)."""
    if px.face in ("north", "south", "east", "west"):
        n = px.noise(55, y=0)
        cut = 0 if n < 0.30 else (1 if n < 0.72 else 2)
        if px.fy >= px.fh - cut:
            return None  # ragged, torn hem
    col = _robe_weave(px)
    if px.face in ("north", "south", "east", "west") and px.fh > 3:
        # Mist creep: the lowest intact rows pick up the storm's violet tint.
        creep = (px.fy / (px.fh - 1.0)) ** 3
        col = mix(col, MIST_VIOLET, creep * 0.4)
    return col


def _tatter_col(px, row, total_rows):
    """Rag cloth for one row of the 2-segment tatter chains: `row` counts from the
    skirt hem down the FULL chain (both segments), so the violet mist wash runs
    continuously across the root/tip joint instead of restarting per cube."""
    col = _robe_weave(px)
    t = row / max(total_rows - 1.0, 1.0)
    return mix(col, MIST_VIOLET, 0.2 + t * 0.4)


def tatter_root(px):
    """Upper tatter segment (MB6 chain split): mid-strip cloth — NO rag cut here, the
    torn edge lives on the free-swinging tip segment below."""
    if px.face in ("up", "down"):
        return _tatter_col(px, 1, 4)
    return _tatter_col(px, px.fy, 4)


def tatter_tip(px):
    """Free end of the tatter chain: the raggedest cloth on the mob (these are the
    pieces the storm is actively eating — the same hem the `revenant_fog_ribbons`
    streamers tear at) with the strongest mist wash. The cut is capped at 1 of the
    tip's 2 rows so no chain ever loses its whole end cube."""
    if px.face in ("north", "south", "east", "west"):
        if px.noise(59, x=px.gx, y=0) >= 0.55 and px.fy >= px.fh - 1:
            return None  # ragged free end
    if px.face in ("up", "down"):
        return _tatter_col(px, 3, 4)
    return _tatter_col(px, px.fy + 2, 4)


def sleeve(px):
    """Arm sleeves: slightly lighter cloth so the long arms read against the robe."""
    return _sleeve_weave(px)


def forearm(px):
    """Forearm wraps: sleeve cloth rotting toward the wrist — darker, mist-tinged."""
    col = _sleeve_weave(px)
    t = px.fy / max(px.fh - 1.0, 1.0) if px.face in ("north", "south", "east", "west") else 0.5
    return mix(mul(col, 0.9), MIST_VIOLET, t * 0.25)


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
    vertical sick-green eye slits (1 px wide, 2 px tall, mirrored) on the north face.
    The hood cube leaves the north face open, so this is what stares out."""
    if px.face == "north":
        if px.fx in (1, 4) and px.fy in (2, 3):
            return EYE_CORE if px.fy == 2 else EYE
        # Faint jaw/cheek bone hints below the eyes.
        if px.fy >= 4 and px.noise(23) > 0.62:
            return mix(SKULL_SHADOW, SKULL_BONE, 0.35)
    col = mul(SKULL_SHADOW, 0.9 + px.noise(41) * 0.2)
    return col


def hood(px):
    """Hood cloth with a violet rim graze on the crown rows (storm light from above)."""
    col = weave(HOOD, direction=0, amp=0.32)(px)
    if px.face == "up" or (px.face in ("east", "west", "south") and px.fy == 0):
        col = mix(col, RIM_VIOLET, 0.45)
    return col


def growth(px):
    """Fog-coral shelf on the shoulder: base slate blue shading to pale violet toward
    the top of every face (tips catch the storm light), with darker pore pits."""
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


def hood_glow(px):
    """Faint violet rim on the hood crown — grazing light, not neon piping."""
    if px.face == "up" or (px.face in ("east", "west", "south") and px.fy == 0):
        return with_alpha(RIM_VIOLET, 80)
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("torso", weave(ROBE, direction=1, amp=0.26))
    painter.set_material("skirt_*", skirt)
    painter.set_material("tatter_*", tatter_root)
    painter.set_material("tatter_*_tip", tatter_tip)  # later declaration wins on tips
    painter.set_material("hood", hood)
    painter.set_material("head", head)
    painter.set_material("arm_*", sleeve)
    painter.set_material("forearm_*", forearm)
    painter.set_material("claw_*", claw)
    painter.set_material("growth", growth)
    painter.set_material("glow_wisp_*", flame(WISP_CORE, WISP))
    # glow_wisp_* bones are auto-included in the glowmask; the eye slits and hood rim
    # need custom glow painters because those bones are otherwise non-emissive.
    painter.set_glow_painter("head", head_glow)
    painter.set_glow_painter("hood", hood_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
