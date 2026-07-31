#!/usr/bin/env python3
"""Portal Key texture driver (FERRYMAN2 F-045b, MA5 ward-glyph pass).

Design sheet: the giant golden-violet finale key (~3 blocks) hovering over the altar.
Worn ceremonial gold with hammered facets and violet filigree inlay down the shaft, a
ferrule collar under the bow, etched notches on the head ring, and — the MA5 upgrade —
THREE separate ward bits (`bit_1..3`) climbing the shaft, each carrying its own emissive
Bart-Glyphe (`glow_glyph_1..3`) that flashes when its tumbler clicks home in
`unlock_turn`. The gem in the head ring stays the emissive heart.
Palette: gold #FAD173 / #C89A4B / #8A6A2E (shadow), violet inlay #9C7BE0,
gem #E8DAFF core, glyph #D0B3FF.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/portal_key.py
Writes src/main/resources/assets/eclipse/textures/entity/portal_key.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/portal_key.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/portal_key.png"

SEED = 0x0F045B0E

GOLD = hexc("#FAD173")
GOLD_MID = hexc("#C89A4B")
GOLD_DEEP = hexc("#8A6A2E")
VIOLET = hexc("#9C7BE0")
GEM_CORE = hexc("#E8DAFF")
GEM_MID = hexc("#C9A9FF")
GLYPH = hexc("#D0B3FF")

# One ward pattern per bit (bottom -> top); the third is the "master" ward.
GLYPH_VARIANTS = {"glow_glyph_1": 0, "glow_glyph_2": 1, "glow_glyph_3": 2}


def gold_metal(px):
    """Hammered ceremonial gold: facet dither + edge wear."""
    n = px.noise(3)
    base = GOLD if n > 0.45 else GOLD_MID
    if n > 0.93:
        return mix(GOLD, hexc("#FFF3C4"), 0.6)  # glint facet
    if px.noise(5) > 0.9:
        return GOLD_DEEP  # tarnish pit
    return base


def shaft(px):
    """Shaft: gold with a violet filigree inlay line spiraling down."""
    if (px.fy + px.fx * 2) % 9 == 0 and 0 < px.fx < px.fw - 1:
        return VIOLET
    return gold_metal(px)


def collar(px):
    """Ferrule under the bow: banded gold with a violet seam ring."""
    if px.fh >= 4 and px.fy in (1, px.fh - 2):
        return VIOLET
    if px.fx % 3 == 0:
        return mul(gold_metal(px), 0.82)  # flute
    return gold_metal(px)


def body_glow(px):
    """Emissive pass for BOTH body cubes (glow painters bind per bone): the shaft's
    filigree inlay line and the collar's two seam rings — nothing else on the gold."""
    if (px.fy + px.fx * 2) % 9 == 0 and 0 < px.fx < px.fw - 1:
        return with_alpha(VIOLET, 220)
    if px.fw >= 6 and px.fh >= 4 and px.fy in (1, px.fh - 2):
        return with_alpha(VIOLET, 210)  # collar faces only (the shaft is 4px wide)
    return None


def head_ring(px):
    """Head ring bars: gold with etched notch ticks along the length."""
    if px.fw >= 6 and px.fx % 4 == 2 and px.fy in (0, px.fh - 1):
        return GOLD_DEEP  # notch tick
    if px.fh >= 6 and px.fy % 4 == 2 and px.fx in (0, px.fw - 1):
        return GOLD_DEEP
    return gold_metal(px)


def teeth(px):
    """Ward bits: darker, work-scarred gold with a chamfered leading edge."""
    if px.fw >= 4 and px.fx == px.fw - 1:
        return mix(GOLD, GOLD_MID, 0.4)  # lit wear on the turning edge
    base = mix(GOLD_MID, GOLD_DEEP, 0.4 + px.noise(7) * 0.3)
    if px.noise(9) > 0.88:
        return mul(base, 0.7)  # scar
    return base


def ward_glyph(variant):
    """Bart-Glyphe plate on a bit (emissive bone — albedo IS the glow source)."""
    def fn(px):
        if px.fw < 2 or px.fh < 2:
            return VIOLET
        edge = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
        if edge:
            return VIOLET
        if variant == 0 and (px.fx + px.fy) % 2 == 0:
            return GEM_CORE
        if variant == 1 and px.fy % 2 == 1:
            return GEM_CORE
        if variant == 2 and px.fx == px.fw // 2:
            return GEM_CORE
        return GLYPH
    return fn


def gem(px):
    """The heart gem (auto-glow bone): white-violet core with a violet skin."""
    edge = px.fx in (0, px.fw - 1) or px.fy in (0, px.fh - 1)
    if edge:
        return VIOLET
    return GEM_CORE if px.noise(11) > 0.3 else GEM_MID


def main():
    p = GeoPainter(GEO, seed=SEED)
    p.set_material("body", shaft)
    p.set_cube_material("body", 1, collar)
    p.set_material("head", head_ring)
    p.set_material("bit_*", teeth)
    p.set_material("glow_gem", gem)
    for bone_name, variant in GLYPH_VARIANTS.items():
        p.set_material(bone_name, ward_glyph(variant))
    p.set_glow_painter("body", body_glow)
    p.paint(OUT)


if __name__ == "__main__":
    main()
