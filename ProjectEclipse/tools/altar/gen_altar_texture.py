#!/usr/bin/env python3
"""Altar GeckoLib texture driver (F-076 "Altar als richtiges Model").

Design sheet: the ritual altar as a monument — two deepslate base steps, an obsidian
body wearing four floating rune plates (the engraving), a polished crown plate with a
gold-violet inlay ring and four obsidian corner horns, a floating eclipse core (dark
crystal shell around a blazing near-black disc heart), three slowly counter-rotating
rune rings and four orbiting debris chips. Palette is the house gold-violet:
#B98CFF / #E7D6FF (violet blaze), #FFE9B0 / #C9A24D (gold), deepslate #2B2B33,
obsidian #171320.

Emissive: `glow_runes` / `glow_core` bones auto-copy their (shadeless) albedo into the
glowmask (paint_lib convention); the crown inlay, ring ticks, horn tips, core cracks
and debris cracks get custom glow painters so the stone itself stays dark while its
engravings blaze — GeckoLib's `AutoGlowingGeoLayer` reads `altar_glowmask.png`.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 tools/altar/gen_altar_texture.py
Writes src/main/resources/assets/eclipse/textures/block/altar.png + _glowmask.png.
"""

import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/geckolib_gen"))
from paint_lib import GeoPainter, hexc, mix, mul, with_alpha  # noqa: E402

GEO = ROOT / "src/main/resources/assets/eclipse/geo/block/altar.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/block/altar.png"

SEED = 0x0A17A2  # "ALTAR", roughly

DEEPSLATE = hexc("#2B2B33")
DEEPSLATE_DARK = hexc("#1F1F26")
OBSIDIAN = hexc("#171320")
OBSIDIAN_DEEP = hexc("#0F0C16")
CROWN = hexc("#37323F")
PURPLE = hexc("#B98CFF")
PURPLE_CORE = hexc("#E7D6FF")
PURPLE_DEEP = hexc("#6E4DA8")
GOLD = hexc("#FFE9B0")
GOLD_DEEP = hexc("#C9A24D")
VOID = hexc("#0A0510")
DISC_CORE = hexc("#060309")


# ---------------------------------------------------------------------------
# stone materials
# ---------------------------------------------------------------------------

def deepslate(base, salt=31):
    """Coarse deepslate: vertical striations, mortar cracks, rare pale flecks."""
    def fn(px):
        streak = px.noise(salt, x=px.gx // 2)
        col = mul(base, 0.85 + streak * 0.3)
        if px.noise(salt + 7) > 0.965:
            col = mix(col, hexc("#4A4A55"), 0.7)  # pale fleck
        if px.noise(salt + 13, y=px.gy // 3) < 0.06:
            col = mul(col, 0.62)  # crack shadow
        return col
    return fn


def obsidian(base, salt=37):
    """Glassy obsidian: broad dark flows with faint violet sheen bands."""
    def fn(px):
        flow = px.noise(salt, y=px.gy // 5)
        col = mul(base, 0.8 + flow * 0.3)
        if (px.gx + px.gy) % 9 in (0, 1) and px.noise(salt + 3) > 0.4:
            col = mix(col, PURPLE_DEEP, 0.28)  # sheen band
        if px.noise(salt + 11) > 0.975:
            col = mix(col, PURPLE, 0.35)  # glint
        return col
    return fn


# ---------------------------------------------------------------------------
# crown plate (cube 3 of `plinth`): inlay ring on the up face
# ---------------------------------------------------------------------------

def _inlay(px):
    """0 none / 1 gold channel / 2 violet ring on the 22x22 crown up face."""
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = math.hypot(px.fx - cx, px.fy - cy)
    if abs(d - 7.5) < 0.9:
        return 2  # the main ring
    if abs(d - 5.0) < 0.6:
        return 1  # inner channel
    # four radial spokes between the rings
    ang = math.atan2(px.fy - cy, px.fx - cx) % (math.pi / 2.0)
    if 5.0 < d < 7.5 and abs(ang - math.pi / 4.0) < 0.09:
        return 1
    return 0


def crown_material(px):
    if px.face == "up":
        g = _inlay(px)
        if g == 2:
            return mix(CROWN, PURPLE, 0.55)
        if g == 1:
            return mix(CROWN, GOLD_DEEP, 0.5)
    return deepslate(CROWN, salt=41)(px)


def crown_glow(px):
    # Bone-level painter: only the crown plate's box lives at canvas v >= 29
    # (base steps / body pack into the v 0..28 row) — gate off the other cubes.
    if px.gy >= 29 and px.face == "up":
        g = _inlay(px)
        if g == 2:
            return with_alpha(PURPLE, 190)
        if g == 1:
            return with_alpha(GOLD, 150)
    return None


# ---------------------------------------------------------------------------
# rune plates (`glow_runes`, shadeless auto-glow): strokes only, rest transparent
# ---------------------------------------------------------------------------

def _rune_stroke(fx, fy):
    """Rune band mask on a 14x5 plate: a repeating sigil alphabet (ladder, gate,
    eye, chevron) — 1 = stroke, 0 = empty."""
    col = fx % 5
    glyph = (fx // 5) % 3
    if glyph == 0:  # ladder
        if col == 1 and fy in (0, 1, 2, 3, 4):
            return 1
        if fy == 2 and col in (2, 3):
            return 1
    elif glyph == 1:  # gate
        if col in (1, 3) and fy >= 1:
            return 1
        if fy == 0 and col in (1, 2, 3):
            return 1
    else:  # eye
        if fy == 2 and col in (1, 3):
            return 1
        if col == 2 and fy in (1, 2, 3):
            return 1
    return 0


def rune_material(px):
    # Every visible plate face is 14 px along x, 5 px along y (thickness-0 planes).
    if _rune_stroke(px.fx, px.fy):
        flicker = px.noise(43)
        return mix(PURPLE, GOLD, 0.25 + 0.2 * flicker)
    return None  # empty plate — the strokes float over the stone


rune_material.shadeless = True


# ---------------------------------------------------------------------------
# core: dark crystal shell + blazing disc heart
# ---------------------------------------------------------------------------

def core_material(px):
    """Faceted dark crystal: diagonal facet fields with violet edge light."""
    facet = px.noise(47, x=(px.gx + px.gy) // 3, y=(px.gx - px.gy) // 3)
    col = mul(hexc("#241B2E"), 0.8 + facet * 0.45)
    on_edge = px.fx in (0, px.fw - 1) or px.fy in (0, px.fh - 1)
    if on_edge:
        col = mix(col, PURPLE_DEEP, 0.5)
    return col


def core_glow(px):
    """Thin gold fissures across the shell — the heart shining through the stone."""
    if (px.gx * 3 + px.gy * 5) % 11 == 0 and px.noise(53) > 0.55:
        return with_alpha(mix(GOLD, PURPLE, 0.3), 120)
    return None


def heart_material(px):
    """The eclipse heart (`glow_core`, shadeless auto-glow): near-black core ringed
    by a blazing violet-gold corona — the respawn-door disc read, per face."""
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = math.hypot((px.fx - cx) / max(cx, 0.5), (px.fy - cy) / max(cy, 0.5))
    if d > 0.62:
        flare = 0.2 * (px.noise(59) - 0.5)
        t = min(1.0, (d - 0.62) / 0.5 + flare)
        return mix(mix(PURPLE_CORE, GOLD, 0.35), PURPLE, t)
    mottle = px.noise(61)
    return mix(DISC_CORE, hexc("#1A0E24"), 0.5 * mottle)


heart_material.shadeless = True


# ---------------------------------------------------------------------------
# rings: dark stone frames with glowing ticks on the up faces
# ---------------------------------------------------------------------------

def ring_material(px):
    col = obsidian(hexc("#26222E"), salt=67)(px)
    if px.face == "up" and _ring_tick(px):
        return mix(col, GOLD_DEEP, 0.6)
    return col


def _ring_tick(px):
    """Tick runes every 4 px along the long axis of a ring segment's up face."""
    along = px.fx if px.fw >= px.fh else px.fy
    return along % 4 == 1


def ring_glow(px):
    if px.face == "up" and _ring_tick(px):
        return with_alpha(mix(GOLD, PURPLE, 0.35), 170)
    if px.face in ("north", "south", "east", "west") and px.noise(71) > 0.9:
        return with_alpha(PURPLE, 70)  # faint side shimmer
    return None


# ---------------------------------------------------------------------------
# horns + debris
# ---------------------------------------------------------------------------

def horn_material(px):
    col = obsidian(OBSIDIAN, salt=73)(px)
    if px.fy <= 1 and px.face in ("north", "south", "east", "west"):
        col = mix(col, PURPLE_DEEP, 0.45)  # lit tip
    return col


def horn_glow(px):
    if px.fy == 0 and px.face in ("north", "south", "east", "west"):
        return with_alpha(PURPLE, 140)
    if px.face == "up":
        return with_alpha(PURPLE, 110)
    return None


def debris_material(px):
    return deepslate(DEEPSLATE_DARK, salt=79)(px)


def debris_glow(px):
    if (px.gx + px.gy * 2) % 7 == 0 and px.noise(83) > 0.5:
        return with_alpha(PURPLE, 100)  # violet crack light
    return None


# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------

def main():
    painter = GeoPainter(GEO, seed=SEED)
    # plinth cube order: 0 base step, 1 second step, 2 body, 3 crown plate.
    painter.set_material("plinth", deepslate(DEEPSLATE))
    painter.set_cube_material("plinth", 1, deepslate(DEEPSLATE_DARK, salt=33))
    painter.set_cube_material("plinth", 2, obsidian(OBSIDIAN))
    painter.set_cube_material("plinth", 3, crown_material)
    painter.set_material("horns", horn_material)
    painter.set_material("glow_runes", rune_material)
    painter.set_material("core", core_material)
    painter.set_material("glow_core", heart_material)
    painter.set_material("ring_*", ring_material)
    painter.set_material("debris_*", debris_material)
    # Custom glow: engraved light on otherwise-dark stone. glow_* bones auto-copy.
    painter.set_glow_painter("plinth", crown_glow)
    painter.set_glow_painter("horns", horn_glow)
    painter.set_glow_painter("core", core_glow)
    painter.set_glow_painter("ring_*", ring_glow)
    painter.set_glow_painter("debris_*", debris_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
