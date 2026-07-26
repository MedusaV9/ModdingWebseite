#!/usr/bin/env python3
"""Portal Gate texture driver (FERRYMAN2 F-045).

Design sheet: the finale portal — a ~12-block dark gothic arch conjured out of the
accumulated day-rift debris. Twin basalt pillars with purple-veined cracks, a keystone
arch, two blackened-oak door wings with tarnished-silver banding, and the emissive set:
rune plates running up both pillar fronts, a keystone eclipse disc, and the keyhole the
flying key slots into. Palette: void basalt #17131E/#0E0B14, blackened oak #241B14,
tarnished silver #8C8F9A, finale violet #9C7BE0 (mid) / #D0B3FF (hot) / #4A2E73 (deep),
gold seam accents #FAD173 (the key's metal answered in the door).

Emissive law: `glow_*` bones get CUSTOM glow painters (strokes only — the plates' dark
fill must NOT glow), so the runes read as light carved INTO dark stone.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/portal_gate.py
Writes src/main/resources/assets/eclipse/textures/entity/portal_gate.png + _glowmask.png.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, metal, mix, mul, with_alpha, wood  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/portal_gate.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/portal_gate.png"

SEED = 0x0F045A7E

BASALT = hexc("#17131E")
BASALT_DEEP = hexc("#0E0B14")
BASALT_EDGE = hexc("#241E30")
OAK = hexc("#241B14")
OAK_DEEP = hexc("#1A130E")
SILVER = hexc("#8C8F9A")
SILVER_DARK = hexc("#6F7280")
VIOLET = hexc("#9C7BE0")
VIOLET_HOT = hexc("#D0B3FF")
VIOLET_DEEP = hexc("#4A2E73")
GOLD = hexc("#FAD173")


def basalt(px):
    """Void basalt: near-black courses with mortar seams and rare violet vein cracks."""
    course = (px.gy // 10 + (7 if (px.gx // 14) % 2 else 0)) % 20
    base = BASALT if px.noise(3) > 0.22 else BASALT_DEEP
    if px.gy % 10 == 9 or (px.gx + course) % 14 == 13:
        return mul(BASALT_DEEP, 0.72)  # mortar seam
    if px.noise(5) > 0.965:
        return BASALT_EDGE  # chipped highlight grain
    # Violet vein cracks: sparse wandering hairlines keyed off column noise.
    wander = int(px.noise(9, x=px.gx // 3, y=0) * 6) - 3
    if (px.gx * 7 + px.gy + wander) % 61 == 0 and px.noise(11) > 0.35:
        return mix(VIOLET_DEEP, VIOLET, px.noise(13) * 0.5)
    return base


def rune_plate(px):
    """Rune plate albedo: recessed dark fill; the strokes are painted violet so the
    matching glow painter can lift EXACTLY them into the emissive pass."""
    s = rune_stroke(px)
    if s == 2:
        return VIOLET_HOT
    if s == 1:
        return VIOLET
    return mul(BASALT_DEEP, 0.85) if px.noise(15) > 0.12 else mul(BASALT, 0.8)


def rune_stroke(px):
    """Rune glyph mask on any plate face (works in face-local coords; the plates are
    24x112, side strips 1px — strips return 0). 0 none, 1 stroke, 2 hot node."""
    if px.fw < 8 or px.fh < 24:
        return 0
    cx = px.fw // 2
    row = px.fy % 16  # one glyph per 16px cell down the plate
    cell = px.fy // 16
    lit = (cell * 5 + 3) % 7  # which glyph variant this cell carries
    if row in (1, 14):
        return 0  # cell gap
    if px.fx == cx and 2 <= row <= 13:
        return 1  # spine
    if lit % 2 == 0 and row in (4, 10) and abs(px.fx - cx) <= 3:
        return 1  # crossbars
    if lit % 3 == 0 and row == 7 and abs(px.fx - cx) <= 5 and (px.fx + row) % 2 == 0:
        return 1  # dotted wide bar
    if lit % 2 == 1 and abs(px.fx - cx) == (row - 2) // 3 and 2 <= row <= 11:
        return 1  # chevron
    if row == 7 and abs(px.fx - cx) <= 1:
        return 2  # hot center node
    return 0


def rune_glow(px):
    s = rune_stroke(px)
    if s == 2:
        return with_alpha(VIOLET_HOT, 255)
    if s == 1:
        return with_alpha(VIOLET, 235)
    return None


def keystone(px):
    """Keystone disc: an eclipsed sun — violet annulus, void core, hot rim ticks."""
    if px.fw < 8:
        return mul(BASALT_DEEP, 0.85)
    cx, cy = px.fw / 2.0 - 0.5, px.fh / 2.0 - 0.5
    r = math.hypot(px.fx - cx, px.fy - cy)
    if r < 4.2:
        return BASALT_DEEP  # the eclipsed core
    if r < 7.5:
        return mix(VIOLET, VIOLET_HOT, px.noise(21) * 0.5)
    if r < 9.0:
        return VIOLET_DEEP
    if r < 10.5 and int(math.degrees(math.atan2(px.fy - cy, px.fx - cx)) + 360) % 30 < 6:
        return GOLD  # rim ticks
    return mul(BASALT_DEEP, 0.85)


def keystone_glow(px):
    if px.fw < 8:
        return None
    cx, cy = px.fw / 2.0 - 0.5, px.fh / 2.0 - 0.5
    r = math.hypot(px.fx - cx, px.fy - cy)
    if 4.2 <= r < 7.5:
        return with_alpha(VIOLET_HOT, 255)
    if r < 10.5 and r >= 9.0 and int(math.degrees(math.atan2(px.fy - cy, px.fx - cx)) + 360) % 30 < 6:
        return with_alpha(GOLD, 220)
    return None


def door(px):
    """Blackened-oak door wing: vertical strakes, silver bands, carved seam glyphs."""
    if px.fh > 100:  # tall faces = the wing front/back
        if px.fy % 38 in (6, 7) or px.fy % 38 in (30, 31):
            return SILVER if (px.gx + px.gy) % 7 else SILVER_DARK  # banding
        board = px.fx // 5
        base = OAK if (board + px.gy // 40) % 2 == 0 else OAK_DEEP
        if px.fx % 5 == 4:
            return mul(OAK_DEEP, 0.7)  # board seam
        if px.noise(31) > 0.96:
            return mul(base, 1.25)  # worn highlight
        grain = px.noise(33, x=px.gx, y=px.gy // 6)
        return mul(base, 0.9 + grain * 0.2)
    return metal(SILVER_DARK)(px)  # edges read as the banding wrap


def keyhole(px):
    """Keyhole plate: gold escutcheon ring around a void slot."""
    if px.fw < 4:
        return mul(SILVER_DARK, 0.8)
    cx = px.fw / 2.0 - 0.5
    cy = px.fh * 0.34
    r = math.hypot(px.fx - cx, px.fy - cy)
    if r < 1.6 or (abs(px.fx - cx) < 1.1 and cy <= px.fy <= px.fh - 3):
        return BASALT_DEEP  # the slot itself
    if r < 3.2 or (abs(px.fx - cx) < 2.2 and cy <= px.fy <= px.fh - 2):
        return GOLD
    return mix(SILVER_DARK, GOLD, 0.25)


def keyhole_glow(px):
    if px.fw < 4:
        return None
    cx = px.fw / 2.0 - 0.5
    cy = px.fh * 0.34
    r = math.hypot(px.fx - cx, px.fy - cy)
    if r < 1.6 or (abs(px.fx - cx) < 1.1 and cy <= px.fy <= px.fh - 3):
        return with_alpha(VIOLET, 235)  # violet light leaks out of the slot
    return None


def main():
    p = GeoPainter(GEO, seed=SEED)
    p.set_material("frame", basalt)
    p.set_material("door_*", door)
    p.set_material("glow_runes_*", rune_plate)
    p.set_material("glow_keystone", keystone)
    p.set_material("glow_keyhole", keyhole)
    p.set_glow_painter("glow_runes_*", rune_glow)
    p.set_glow_painter("glow_keystone", keystone_glow)
    p.set_glow_painter("glow_keyhole", keyhole_glow)
    p.paint(OUT)


if __name__ == "__main__":
    main()
