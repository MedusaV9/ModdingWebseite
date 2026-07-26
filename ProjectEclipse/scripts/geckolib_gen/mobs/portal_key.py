#!/usr/bin/env python3
"""Portal Key texture driver (FERRYMAN2 F-045b).

Design sheet: the giant golden-violet finale key (~3 blocks) hovering over the altar.
Worn ceremonial gold with hammered facets and violet filigree inlay down the shaft;
the head ring carries etched notches; the bit teeth are darker, work-scarred gold; the
gem in the head ring is the emissive heart (violet-white, auto-glow bone). Palette:
gold #FAD173 / #C89A4B / #8A6A2E (shadow), violet inlay #9C7BE0, gem #E8DAFF core.

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


def head_ring(px):
    """Head ring bars: gold with etched notch ticks along the length."""
    if px.fw >= 6 and px.fx % 4 == 2 and px.fy in (0, px.fh - 1):
        return GOLD_DEEP  # notch tick
    if px.fh >= 6 and px.fy % 4 == 2 and px.fx in (0, px.fw - 1):
        return GOLD_DEEP
    return gold_metal(px)


def teeth(px):
    """Bit teeth: darker, work-scarred gold."""
    base = mix(GOLD_MID, GOLD_DEEP, 0.4 + px.noise(7) * 0.3)
    if px.noise(9) > 0.88:
        return mul(base, 0.7)  # scar
    return base


def gem(px):
    """The heart gem (auto-glow bone): white-violet core with a violet skin."""
    edge = px.fx in (0, px.fw - 1) or px.fy in (0, px.fh - 1)
    if edge:
        return VIOLET
    return GEM_CORE if px.noise(11) > 0.3 else GEM_MID


def shaft_glow(px):
    """Only the filigree inlay line joins the emissive pass on the shaft."""
    if (px.fy + px.fx * 2) % 9 == 0 and 0 < px.fx < px.fw - 1:
        return with_alpha(VIOLET, 220)
    return None


def main():
    p = GeoPainter(GEO, seed=SEED)
    p.set_material("body", shaft)
    p.set_material("head", head_ring)
    p.set_material("teeth", teeth)
    p.set_material("glow_gem", gem)
    p.set_glow_painter("body", shaft_glow)
    p.paint(OUT)


if __name__ == "__main__":
    main()
