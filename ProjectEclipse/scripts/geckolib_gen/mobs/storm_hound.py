#!/usr/bin/env python3
"""Storm Hound / Sturmhund texture driver (P6-W7, reworked by FXTEAM MOB-FOG).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3) + the MOB-FOG palette pass
(docs/plans_v3/plans_v5/fxteams/MOB-FOG.md): a lean charged quadruped — storm-grey hide
(#3A4148 dithered against #2C3238), darker jaw (#1E2126) with a pale sick-green inner
mouth (#E9FFD8), branching charge veins (#A9F07E) crackling along the flanks,
lightning-rod spine shards + horn antenna burning green-to-violet (#9C63E8), a
three-bone STORM MANE at the neck (slate fur streaked with violet charge — flares on
the windup/howl), and a three-segment whip tail with a static-charged tip.

Emissive (glowmask): the `glow_spine_*` shards and `glow_horn` (auto-included), the
flank veins, the mane charge streaks, the two eye dots and a faint charge on the tail
tips (`tail_b`/`tail_c`).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/storm_hound.py
Writes src/main/resources/assets/eclipse/textures/entity/storm_hound.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, mix, mul, weave, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/storm_hound.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/storm_hound.png"

SEED = 0x57084D06  # storm hound

FUR = hexc("#3A4148")
FUR_DARK = hexc("#2C3238")
JAW = hexc("#1E2126")
# MOB-FOG family glow: sick green core -> violet rim.
MOUTH = hexc("#E9FFD8")
VEIN = hexc("#A9F07E")
VEIN_CORE = hexc("#E9FFD8")
SPINE_TIP = hexc("#9C63E8")
SPINE_CORE = hexc("#E9FFD8")
EYE = hexc("#D6FFB8")
MANE_VIOLET = hexc("#8A63D6")

_fur_grain = weave(FUR, direction=2, amp=0.24)


def _fur_px(px, shade=1.0):
    """Two-tone storm fur: horizontal grain streaks hash-dithered between the light and
    dark greys (EntitySkinArtist-style), optionally darkened toward the paws."""
    col = _fur_grain(px)
    if px.noise(61) > 0.55:
        col = mix(col, FUR_DARK, 0.55)
    return mul(col, shade)


def _vein_at(px):
    """True where a branching charge vein crosses this pixel. Deterministic per global
    column: a main horizontal channel wandering around the face midline plus sparse
    vertical forks — the same test paints the albedo and the glowmask."""
    if px.face not in ("east", "west", "north", "south") or px.fw < 6 or px.fh < 5:
        return False
    mid = px.fh * 0.55
    wander = (px.noise(71, x=px.gx // 2, y=0) - 0.5) * px.fh * 0.55
    main = abs(px.fy - (mid + wander)) < 0.8
    fork = px.noise(77, x=px.gx, y=0) > 0.88 and px.fy > 1 and px.fy < px.fh - 1 \
        and abs(px.fy - mid) < px.fh * 0.45
    return main or fork


def body(px):
    """Flank hide with the crackle veins burned in (they also glow at night)."""
    if _vein_at(px):
        core = px.noise(79) > 0.6
        return VEIN_CORE if core else VEIN
    shade = 1.0
    if px.face in ("east", "west", "north", "south") and px.fh > 4 and px.fy >= px.fh - 2:
        shade = 0.82  # shadowed underbelly rows
    return _fur_px(px, shade)


def body_glow(px):
    """Glowmask for the body: only the vein pixels, slightly translucent so the crackle
    reads as charge under the hide rather than neon stripes."""
    if _vein_at(px):
        return with_alpha(VEIN, 170)
    return None


def _mane_streak_at(px):
    """Vertical charge streaks through the mane tufts — every tuft carries one or two
    bright violet strands (deterministic per global column)."""
    if px.face not in ("east", "west", "north", "south"):
        return False
    return px.noise(91, x=px.gx, y=0) > 0.62 and px.fy < px.fh - 1


def mane(px):
    """Storm mane: darker wind-torn fur with violet charge strands and a ragged tip
    row (the tufts dissolve into static)."""
    if px.face in ("east", "west", "north", "south"):
        n = px.noise(93, x=px.gx, y=0)
        if px.fy >= px.fh - (1 if n > 0.45 else 0):
            return None  # ragged tuft tip
    if _mane_streak_at(px):
        return mix(MANE_VIOLET, VEIN_CORE, px.noise(95) * 0.4)
    return _fur_px(px, 0.85)


def mane_glow(px):
    """Only the charge strands glow, at partial alpha — mane reads as fur holding a
    static charge, not as a solid lamp."""
    if px.face in ("east", "west", "north", "south"):
        n = px.noise(93, x=px.gx, y=0)
        if px.fy >= px.fh - (1 if n > 0.45 else 0):
            return None
    if _mane_streak_at(px):
        return with_alpha(MANE_VIOLET, 150)
    return None


def skull(px):
    """Head fur, slightly darker than the body, with one bright eye dot per side of the
    north face (the snout cube covers the center, leaving the eyes at the corners)."""
    if px.face == "north" and px.fy == 1 and px.fx in (0, px.fw - 1):
        return EYE
    return _fur_px(px, 0.92)


def head_glow(px):
    """Glowmask for the head bone: the two eye dots only (the glow painter runs on every
    cube of the bone, so gate on the skull's 5 px-wide north face to skip the snout)."""
    if px.face == "north" and px.fw >= 5 and px.fy == 1 and px.fx in (0, px.fw - 1):
        return with_alpha(EYE, 245)
    return None


def snout(px):
    """Snout: dark bridge stripe on top, bare charcoal nose tip."""
    col = _fur_px(px, 0.9)
    if px.face == "up" and px.fw > 2 and 0 < px.fx < px.fw - 1:
        col = mix(col, JAW, 0.5)  # bridge stripe
    if px.face == "north":
        col = mul(JAW, 0.9 + px.noise(83) * 0.2)  # nose
    return col


def jaw(px):
    """Split lower jaw: near-black chin, pale sick-green inner mouth on the top face."""
    if px.face == "up":
        return mix(MOUTH, VEIN, px.noise(87) * 0.4)
    return mul(JAW, 0.88 + px.noise(89) * 0.24)


def leg_upper(px):
    return _fur_px(px, 0.95)


def leg_lower(px):
    """Lower legs darken toward the paws (storm-soaked)."""
    t = px.fy / max(px.fh - 1.0, 1.0) if px.face in ("north", "south", "east", "west") else 0.5
    return _fur_px(px, 1.0 - 0.28 * t)


def tail(px):
    return _fur_px(px, 0.97)


def tail_tip(px):
    """Whip tail segments: the last rows carry a static charge tint."""
    col = _fur_px(px, 0.95)
    if px.face in ("east", "west", "up", "down") and px.fw > 3 and px.fx >= px.fw - 2:
        col = mix(col, VEIN, 0.55)
    return col


def tail_tip_glow(px):
    """Faint glow on the charged tail tip pixels."""
    if px.face in ("east", "west", "up", "down") and px.fw > 3 and px.fx >= px.fw - 2:
        return with_alpha(VEIN, 110)
    return None


def _whip_t(px):
    """Position along the whip segment's LENGTH in [0, 1], or None off the long faces.
    Box-UV quirk: on a z-long cube the length runs along fx for east/west but along fy
    for up/down (the top view is the one players actually see on a quadruped tail)."""
    if px.face in ("east", "west") and px.fw > 3:
        return px.fx / max(px.fw - 1.0, 1.0)
    if px.face in ("up", "down") and px.fh > 3:
        return px.fy / max(px.fh - 1.0, 1.0)
    return None


def tail_end(px):
    """The whip's last segment: fully charge-soaked toward the very tip, violet at the
    outermost pixels — the crack of the whip."""
    col = _fur_px(px, 0.9)
    t = _whip_t(px)
    if t is not None:
        if t > 0.45:
            col = mix(col, VEIN, (t - 0.45) * 1.4)
        if t > 0.75:
            col = mix(col, SPINE_TIP, 0.6)
    return col


def tail_end_glow(px):
    t = _whip_t(px)
    if t is not None and t > 0.5:
        return with_alpha(VEIN if t <= 0.75 else SPINE_TIP, 140)
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("body", body)
    painter.set_material("mane_*", mane)
    painter.set_material("head", skull)
    painter.set_cube_material("head", 1, snout)
    painter.set_material("jaw", jaw)
    painter.set_material("leg_*", leg_upper)
    painter.set_material("leg_*_lower", leg_lower)
    painter.set_material("tail_a", tail)
    painter.set_material("tail_b", tail_tip)
    painter.set_material("tail_c", tail_end)
    painter.set_material("glow_spine_*", flame(SPINE_CORE, SPINE_TIP))
    painter.set_material("glow_horn", flame(SPINE_CORE, SPINE_TIP))
    # glow_* bones auto-glow; veins, mane strands, eyes and tail tips need custom
    # glow painters.
    painter.set_glow_painter("body", body_glow)
    painter.set_glow_painter("mane_*", mane_glow)
    painter.set_glow_painter("head", head_glow)
    painter.set_glow_painter("tail_b", tail_tip_glow)
    painter.set_glow_painter("tail_c", tail_end_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
