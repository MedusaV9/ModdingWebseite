#!/usr/bin/env python3
"""Umbral Stalker texture driver (MC2, GeckoLib conversion of the old code model).

Design sheet (docs/ideas/04_content.md §1.3) + the old placeholder brief in
docs/uv/umbral_stalker.md: a wrong, shadow-slick night pack hunter. Near-black violet
hide (#221A2E dithered against #16111F) over a bone-ribbed SHOULDER HUMP — the hump IS
the silhouette the player reads across a dark field, so its crest carries a pale keel
that catches what little light there is. Umbral cracks run the flanks (the shadow
leaking out), the muzzle is charcoal with a pale violet inner mouth, two bone sabre
tusks hang past the jaw, and three crystal spine shards burn violet down the spine.

Emissive (glowmask): the `glow_spine_*` shards (auto-included), the flank cracks, the
hump keel, the scapula crests, the two eye pinpricks, the inner mouth and the
shard-charged whip-tail tip. The tusks are deliberately NOT emissive — they are the only
non-glowing bright thing on the mob, so the bite still reads against the shard light.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/umbral_stalker.py
Writes src/main/resources/assets/eclipse/textures/entity/umbral_stalker.png
     + src/main/resources/assets/eclipse/textures/entity/umbral_stalker_glowmask.png
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, mix, mul, weave, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/umbral_stalker.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/umbral_stalker.png"

SEED = 0x0B5A17E4  # umbral stalker

HIDE = hexc("#221A2E")
HIDE_DARK = hexc("#16111F")
HEAD = hexc("#2A2038")
MUZZLE = hexc("#1C1626")
JAW = hexc("#120E19")
# Cold bone (violet-grey, not the usual warm ivory) — the mob owns no warm pixel.
BONE = hexc("#CCC3D6")
BONE_DARK = hexc("#8B8398")
# Umbral family glow: pale violet core -> saturated violet rim (matches the old
# placeholder's #8A5CFF spine shards and the umbral shard item).
SHARD_CORE = hexc("#E4D4FF")
SHARD_TIP = hexc("#8A5CFF")
CRACK = hexc("#6B3FD4")
MOUTH = hexc("#C6A6FF")
EYE = hexc("#C08CFF")

_hide_grain = weave(HIDE, direction=1, amp=0.22)


def _hide_px(px, shade=1.0):
    """Shadow-slick hide: vertical grain streaks hash-dithered toward the darker tone,
    with rare near-black slick patches (the light just stops on them)."""
    col = _hide_grain(px)
    if px.noise(41) > 0.58:
        col = mix(col, HIDE_DARK, 0.6)
    if px.noise(43) > 0.955:
        col = mul(col, 0.55)  # slick patch
    return mul(col, shade)


def _crack_at(px):
    """True where an umbral crack crosses this pixel. One wandering channel low on the
    flank plus sparse vertical splits — the same test paints albedo and glowmask."""
    if px.face not in ("east", "west", "north", "south") or px.fw < 5 or px.fh < 4:
        return False
    if px.noise(49, x=px.gx, y=0) < 0.22:
        return False  # the channel breaks up — hide closes back over it
    mid = px.fh * 0.62
    wander = (px.noise(51, x=px.gx // 2, y=0) - 0.5) * px.fh * 0.5
    main = abs(px.fy - (mid + wander)) < 0.7
    split = px.noise(53, x=px.gx, y=0) > 0.9 and 0 < px.fy < px.fh - 1
    return main or split


def body(px):
    """Flank hide with the umbral cracks burned in (they also bleed light at night)."""
    if _crack_at(px):
        # mostly the dim violet channel; only the odd pixel flares to the shard core, or
        # the flank reads as a painted-on white stripe instead of a crack.
        return SHARD_CORE if px.noise(55) > 0.9 else mul(CRACK, 0.8 + px.noise(56) * 0.4)
    shade = 0.84 if px.face in ("north", "south", "east", "west") and px.fh > 4 \
        and px.fy >= px.fh - 2 else 1.0
    return _hide_px(px, shade)


def body_glow(px):
    """Only the crack pixels glow, at partial alpha — the shadow leaks, it does not
    floodlight the flank."""
    if _crack_at(px):
        return with_alpha(CRACK, 165)
    return None


def _keel_at(px):
    """The hump's bone keel: a 2 px ridge running front-to-back down the middle of the
    crest, wrapping into the top row of the side faces. A ridge, not a slab — this is the
    line that draws the shoulder hump against a black sky without turning it into a hat."""
    if px.face == "up":
        return abs(px.fx - (px.fw - 1) / 2.0) < 1.0
    if px.face not in ("east", "west", "north", "south"):
        return False
    return px.fy == 0


def hump(px):
    """Shoulder hump: bristled hide pulled over bone, one shade lighter than the flank
    so the mass reads, with a pale keel along the crest."""
    if _keel_at(px):
        return mix(BONE_DARK, SHARD_CORE, px.noise(57) * 0.35)
    return _hide_px(px, 1.12)


def hump_glow(px):
    """A faint violet wash on the keel only — enough to trace the hump at light 0. Runs
    on both hump cubes, which is what we want: the keel is one continuous ridge."""
    if _keel_at(px):
        return with_alpha(mix(CRACK, SHARD_CORE, 0.35), 115)
    return None


def hump_crest(px):
    """The small cube capping the hump: the keel ridge continues over it, its flanks stay
    hide so the crest reads as bone pushing THROUGH the hide, not as a bone plate."""
    if px.face == "down":
        return _hide_px(px, 0.8)
    if _keel_at(px):
        return mix(BONE_DARK, SHARD_CORE, px.noise(59) * 0.45)
    return _hide_px(px, 1.18)


def neck(px):
    return _hide_px(px, 0.9)


def skull(px):
    """Head hide, a touch warmer than the flank, with one violet eye pinprick per side
    of the north face (the snout cube covers the middle, leaving the eyes at the
    corners)."""
    if px.face == "north" and px.fy == 1 and px.fx in (0, px.fw - 1):
        return EYE
    col = weave(HEAD, direction=1, amp=0.2, salt=61)(px)
    if px.noise(63) > 0.6:
        col = mix(col, HIDE_DARK, 0.5)
    return col


def head_glow(px):
    """Glowmask for the head bone: the two eye pinpricks only (the painter runs on every
    cube of the bone, so gate on the 6 px-wide skull north face to skip the snout)."""
    if px.face == "north" and px.fw >= 6 and px.fy == 1 and px.fx in (0, px.fw - 1):
        return with_alpha(EYE, 250)
    return None


def snout(px):
    """Charcoal muzzle with a darker bridge stripe and a bare nose tip."""
    col = mul(MUZZLE, 0.9 + px.noise(65) * 0.22)
    if px.face == "up" and px.fw > 2 and 0 < px.fx < px.fw - 1:
        col = mix(col, JAW, 0.55)  # bridge stripe
    if px.face == "north":
        col = mul(JAW, 0.95 + px.noise(67) * 0.15)  # nose
    return col


def jaw(px):
    """Lower jaw: near-black chin, pale violet inner mouth on the top face."""
    if px.face == "up":
        return mix(MOUTH, CRACK, px.noise(69) * 0.45)
    return mul(JAW, 0.9 + px.noise(71) * 0.2)


def jaw_glow(px):
    """The inner mouth glows faintly — a violet slit when the jaw opens on the bite."""
    if px.face == "up":
        return with_alpha(MOUTH, 130)
    return None


def tusk(px):
    """Bone sabre: pale ivory, dirtier toward the root, chipped tip. Not emissive."""
    t = px.fy / max(px.fh - 1.0, 1.0) if px.face in ("north", "south", "east", "west") else 0.0
    col = mix(BONE_DARK, BONE, min(1.0, t * 1.3))
    if px.noise(73) > 0.88:
        col = mul(col, 0.86)
    return col


def _crest_at(px):
    """Bony top edge of the shoulder blade — the line that breaks the hide silhouette
    when the blades ride up in `stalk_low`."""
    if px.face == "up":
        return True
    if px.face not in ("east", "west", "north", "south"):
        return False
    return px.fy == 0


def scapula(px):
    """Shoulder blades: hide pulled tight over bone (darker than the flank, no cracks)
    with a shard-lit crest."""
    if _crest_at(px):
        return mix(CRACK, SHARD_CORE, px.noise(75) * 0.4)
    return _hide_px(px, 0.8)


def scapula_glow(px):
    if _crest_at(px):
        return with_alpha(CRACK, 120)
    return None


def haunch(px):
    return _hide_px(px, 0.95)


def leg_upper(px):
    return _hide_px(px, 0.92)


def leg_lower(px):
    """Lower legs darken toward the paws (they end in shadow, not feet)."""
    t = px.fy / max(px.fh - 1.0, 1.0) if px.face in ("north", "south", "east", "west") else 0.5
    return _hide_px(px, 0.95 - 0.4 * t)


def tail(px):
    return _hide_px(px, 0.9)


def _whip_t(px):
    """Position along a whip segment's LENGTH in [0, 1], or None off the long faces.
    Box-UV quirk: on a z-long cube the length runs along fx for east/west but along fy
    for up/down (the top view is the one players see on a quadruped tail)."""
    if px.face in ("east", "west") and px.fw > 3:
        return px.fx / max(px.fw - 1.0, 1.0)
    if px.face in ("up", "down") and px.fh > 3:
        return px.fy / max(px.fh - 1.0, 1.0)
    return None


def tail_end(px):
    """The whip's last segment: shard charge soaks the outer pixels."""
    col = _hide_px(px, 0.88)
    t = _whip_t(px)
    if t is not None and t > 0.4:
        col = mix(col, CRACK, (t - 0.4) * 1.5)
        if t > 0.78:
            col = mix(col, SHARD_CORE, 0.5)
    return col


def tail_end_glow(px):
    t = _whip_t(px)
    if t is not None and t > 0.5:
        return with_alpha(CRACK if t <= 0.78 else SHARD_CORE, 145)
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("body", body)
    painter.set_material("hump", hump)
    painter.set_cube_material("hump", 1, hump_crest)
    painter.set_material("neck", neck)
    painter.set_material("head", skull)
    painter.set_cube_material("head", 1, snout)
    painter.set_material("jaw", jaw)
    painter.set_material("tusk_*", tusk)
    painter.set_material("scapula_*", scapula)
    painter.set_material("haunch_*", haunch)
    painter.set_material("leg_*", leg_upper)
    painter.set_material("leg_*_lower", leg_lower)
    painter.set_material("tail_a", tail)
    painter.set_material("tail_b", tail)
    painter.set_material("tail_c", tail_end)
    painter.set_material("glow_spine_*", flame(SHARD_CORE, SHARD_TIP))
    # glow_* bones auto-glow; cracks, keel, crests, eyes, mouth and the whip tip need
    # their own glow painters.
    painter.set_glow_painter("body", body_glow)
    painter.set_glow_painter("hump", hump_glow)
    painter.set_glow_painter("head", head_glow)
    painter.set_glow_painter("jaw", jaw_glow)
    painter.set_glow_painter("scapula_*", scapula_glow)
    painter.set_glow_painter("tail_c", tail_end_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
