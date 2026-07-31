#!/usr/bin/env python3
"""Portal Gate texture driver (FERRYMAN2 F-045, MA5 rune pass).

Design sheet: the finale portal — a ~12-block dark gothic arch conjured out of the
accumulated day-rift debris. Twin basalt pillars built from INTERLOCKING courses
(alternating flush/proud, plinth + capital), an arch of three voussoirs per side into a
proud keystone wedge, and two blackened-oak door wings with tarnished-silver banding.
The emissive set is the MA5 upgrade: EIGHT individually glimmering rune segments
(`glow_rune_l1..l4`/`glow_rune_r1..r4`, one carved glyph each — the 512² canvas finally
carries rune detail instead of two long strips), a keystone eclipse disc, three shimmer
chips around the keystone, and the keyhole the flying key slots into.
Palette: void basalt #17131E/#0E0B14, blackened oak #241B14, tarnished silver #8C8F9A,
finale violet #9C7BE0 (mid) / #D0B3FF (hot) / #4A2E73 (deep), gold seams #FAD173.

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
from paint_lib import GeoPainter, hexc, metal, mix, mul, with_alpha  # noqa: E402

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

# One glyph variant per rune segment (bottom -> top, left pillar then right).
RUNE_VARIANTS = {
    "glow_rune_l1": 0, "glow_rune_l2": 1, "glow_rune_l3": 2, "glow_rune_l4": 3,
    "glow_rune_r1": 4, "glow_rune_r2": 5, "glow_rune_r3": 6, "glow_rune_r4": 7,
}


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


def voussoir(px):
    """Arch wedge stones: basalt plus radial joint lines so the arch reads as CUT
    stones instead of one slab (the census' 'flache Platten' finding)."""
    if px.fw >= 10 and px.fh >= 10 and (px.fx * 2 + px.fy) % 23 < 2:
        return mul(BASALT_DEEP, 0.6)  # slanted joint between wedges
    if px.fw >= 10 and px.fh >= 10 and (px.fx * 2 + px.fy) % 23 == 2:
        return BASALT_EDGE  # lit joint shoulder
    return basalt(px)


def keystone_stone(px):
    """The keystone wedge + crown: basalt with chamfered gold-fleck edges."""
    if px.fw > 4 and px.fh > 4 and (px.fx < 2 or px.fy < 2
                                    or px.fx >= px.fw - 2 or px.fy >= px.fh - 2):
        return mix(BASALT_EDGE, GOLD, 0.18) if px.noise(17) > 0.7 else BASALT_EDGE
    return basalt(px)


def rune_stroke(px, variant):
    """One carved glyph per 24x24 rune-plate face. 0 none, 1 stroke, 2 hot node.
    The 1px side strips (fw/fh < 8) stay dark — only the plate faces carry glyphs."""
    if px.fw < 8 or px.fh < 8:
        return 0
    x, y, fw, fh = px.fx, px.fy, px.fw, px.fh
    cx, cy = fw // 2, fh // 2
    # corner ticks (every glyph is "framed" the same way — the plates read as a set)
    if x in (2, 3, fw - 4, fw - 3) and y in (2, 3, fh - 4, fh - 3) and (x + y) % 2 == 0:
        return 1
    if math.hypot(x - cx, y - cy) < 1.6:
        return 2  # hot center node
    if x == cx and 4 <= y <= fh - 5:
        return 1  # spine
    if (variant & 1) and y == 8 and 5 <= x <= fw - 6:
        return 1  # upper crossbar
    if (variant & 2) and y == fh - 9 and 5 <= x <= fw - 6:
        return 1  # lower crossbar
    if (variant & 4) and 4 <= y <= 10 and abs(x - cx) == (y - 4):
        return 1  # chevron
    if variant % 3 == 0 and abs(math.hypot(x - cx, y - cy) - 5.0) < 0.5:
        return 1  # halo ring
    if variant % 3 == 1 and y == cy and abs(x - cx) <= 6 and (x + y) % 2 == 0:
        return 1  # dotted bar
    if variant % 3 == 2 and abs(x - cx) == 4 and cy - 4 <= y <= cy + 4:
        return 1  # twin verticals
    return 0


def rune_plate(variant):
    """Rune plate albedo: recessed dark fill; the strokes are painted violet so the
    matching glow painter can lift EXACTLY them into the emissive pass."""
    def fn(px):
        s = rune_stroke(px, variant)
        if s == 2:
            return VIOLET_HOT
        if s == 1:
            return VIOLET
        return mul(BASALT_DEEP, 0.85) if px.noise(15) > 0.12 else mul(BASALT, 0.8)
    return fn


def rune_glow(variant):
    def fn(px):
        s = rune_stroke(px, variant)
        if s == 2:
            return with_alpha(VIOLET_HOT, 255)
        if s == 1:
            return with_alpha(VIOLET, 235)
        return None
    return fn


def keystone(px):
    """Keystone disc: an eclipsed sun — violet annulus, void core, hot rim ticks."""
    if px.fw < 8:
        return mul(BASALT_DEEP, 0.85)
    cx, cy = px.fw / 2.0 - 0.5, px.fh / 2.0 - 0.5
    r = math.hypot(px.fx - cx, px.fy - cy)
    if r < 3.6:
        return BASALT_DEEP  # the eclipsed core
    if r < 6.4:
        return mix(VIOLET, VIOLET_HOT, px.noise(21) * 0.5)
    if r < 7.6:
        return VIOLET_DEEP
    if r < 9.0 and int(math.degrees(math.atan2(px.fy - cy, px.fx - cx)) + 360) % 30 < 6:
        return GOLD  # rim ticks
    return mul(BASALT_DEEP, 0.85)


def keystone_glow(px):
    if px.fw < 8:
        return None
    cx, cy = px.fw / 2.0 - 0.5, px.fh / 2.0 - 0.5
    r = math.hypot(px.fx - cx, px.fy - cy)
    if 3.6 <= r < 6.4:
        return with_alpha(VIOLET_HOT, 255)
    if 7.6 <= r < 9.0 and int(math.degrees(math.atan2(px.fy - cy, px.fx - cx)) + 360) % 30 < 6:
        return with_alpha(GOLD, 220)
    return None


def shimmer(px):
    """Keystone shimmer chip: a cut violet gem facet (bright core, deep bevel)."""
    if px.fw < 3 or px.fh < 3:
        return VIOLET_DEEP
    cx, cy = px.fw / 2.0 - 0.5, px.fh / 2.0 - 0.5
    d = abs(px.fx - cx) + abs(px.fy - cy)  # diamond facet
    if d < 1.6:
        return VIOLET_HOT
    if d < 2.8:
        return VIOLET
    return VIOLET_DEEP


def shimmer_glow(px):
    if px.fw < 3 or px.fh < 3:
        return None
    cx, cy = px.fw / 2.0 - 0.5, px.fh / 2.0 - 0.5
    d = abs(px.fx - cx) + abs(px.fy - cy)
    if d < 1.6:
        return with_alpha(VIOLET_HOT, 255)
    if d < 2.8:
        return with_alpha(VIOLET, 220)
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


def door_rail(px):
    """Iron strap rail across a wing: brushed silver with rivet heads."""
    if px.fw >= 8 and px.fh >= 4 and px.fx % 9 == 4 and px.fy in (2, px.fh - 3):
        return mix(SILVER, GOLD, 0.35)  # rivet
    return metal(SILVER_DARK, salt=27)(px)


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
    p.set_material("pillar_*", basalt)
    p.set_material("arch_*", voussoir)
    p.set_material("keystone_block", keystone_stone)
    p.set_material("door_*", door)
    for wing in ("door_l", "door_r"):
        p.set_cube_material(wing, 1, door_rail)
        p.set_cube_material(wing, 2, door_rail)
    for bone_name, variant in RUNE_VARIANTS.items():
        p.set_material(bone_name, rune_plate(variant))
        p.set_glow_painter(bone_name, rune_glow(variant))
    p.set_material("glow_keystone", keystone)
    p.set_material("glow_shimmer_*", shimmer)
    p.set_material("glow_keyhole", keyhole)
    p.set_glow_painter("glow_keystone", keystone_glow)
    p.set_glow_painter("glow_shimmer_*", shimmer_glow)
    p.set_glow_painter("glow_keyhole", keyhole_glow)
    p.paint(OUT)


if __name__ == "__main__":
    main()
