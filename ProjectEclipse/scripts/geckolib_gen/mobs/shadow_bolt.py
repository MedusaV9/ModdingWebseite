#!/usr/bin/env python3
"""Shadow Bolt texture driver (P6-W910).

The Eclipse Cultist's (and Rift Warden's) projectile: a tiny spike-orb — a 3px
violet-white flame core (`glow_core`) skewered by three dark obsidian spike shafts
whose tips pick up the core's light. Canvas 32x32; the whole entity renders
fullbright + glow-layered (`ShadowBoltRenderer`), so the albedo IS the look.

Emissive (glowmask): the core (auto via `glow_` prefix) + the spike tip pixels
(custom glow painter).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/shadow_bolt.py
Writes src/main/resources/assets/eclipse/textures/entity/shadow_bolt.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/shadow_bolt.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/shadow_bolt.png"

SEED = 0x5AD00B17  # shadow bolt

CORE = hexc("#EFE3FF")
CORE_TIP = hexc("#B98CFF")
SPIKE = hexc("#232030")
SPIKE_TIP = hexc("#B98CFF")


def _is_tip(px):
    """Tip pixels: the extreme cells along each spike's long axis (fw==6 rects run
    along the shaft; 1x1 end caps are tips outright)."""
    if px.fw >= 6:
        return px.fx == 0 or px.fx == px.fw - 1
    if px.fh >= 6:
        return px.fy == 0 or px.fy == px.fh - 1
    return px.fw <= 1 and px.fh <= 1


def spike(px):
    """Obsidian spike shaft: near-black with a violet-lit tip on both ends."""
    if _is_tip(px):
        return mix(SPIKE_TIP, CORE, 0.3)
    col = mul(SPIKE, 0.85 + px.noise(13) * 0.3)
    return col


def spike_glow(px):
    """Glowmask: only the spike tips catch the core light."""
    if _is_tip(px):
        return with_alpha(SPIKE_TIP, 210)
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("glow_core", flame(CORE, CORE_TIP))
    painter.set_material("spikes", spike)
    painter.set_glow_painter("spikes", spike_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
