#!/usr/bin/env python3
"""Soul Wisp texture driver (FERRYMAN2 F-045b/F-046b).

Design sheet: the violet gate ghost — a small vex-like shade that pours out of the
opened portal and answers the Ferryman's summon. Hooded shroud in translucent violet
(alpha ~150, renderer runs entityTranslucent), a ragged tail fading to near-nothing,
thin shroud arms, and the emissive set: the inner soul core and the eye slit. Palette:
shroud #4A2E73 / #2E1C4A (deep), rim #9C7BE0, core #E8DAFF, eyes #D0B3FF.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/soul_wisp.py
Writes src/main/resources/assets/eclipse/textures/entity/soul_wisp.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, mix, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/soul_wisp.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/soul_wisp.png"

SEED = 0x0F045B15

SHROUD = hexc("#4A2E73")
SHROUD_DEEP = hexc("#2E1C4A")
RIM = hexc("#9C7BE0")
CORE = hexc("#E8DAFF")
EYES = hexc("#D0B3FF")


def shroud(px):
    """Hooded shroud: translucent violet weave with a brighter rim edge."""
    edge = px.fx in (0, px.fw - 1) or px.fy == 0
    base = mix(SHROUD, SHROUD_DEEP, px.noise(3) * 0.7)
    if edge:
        return with_alpha(mix(base, RIM, 0.55), 170)
    if px.noise(5) > 0.92:
        return with_alpha(RIM, 150)  # drifting mote fleck in the cloth
    return with_alpha(base, 150)


def tail(px):
    """Ragged tail: alpha bleeds out toward the tip (fy grows downward)."""
    fade = 1.0 - (px.fy / max(1, px.fh - 1)) * 0.8
    if px.fy == px.fh - 1 and px.noise(7) > 0.4:
        return None  # torn hem holes
    base = mix(SHROUD_DEEP, SHROUD, px.noise(9) * 0.5)
    return with_alpha(base, int(150 * fade))


def arm(px):
    base = mix(SHROUD, SHROUD_DEEP, px.noise(11) * 0.6)
    if px.fy == px.fh - 1:
        return with_alpha(mix(base, RIM, 0.4), 120)  # wispy hand tip
    return with_alpha(base, 140)


def core(px):
    return with_alpha(CORE if px.noise(13) > 0.35 else mix(CORE, RIM, 0.5), 235)


def eyes(px):
    if px.fw >= 4 and px.fx in (0, px.fw - 1):
        return None  # keep the slit narrow — dead corners
    return with_alpha(EYES, 255)


def main():
    p = GeoPainter(GEO, seed=SEED)
    p.set_material("body", shroud)
    p.set_material("tail", tail)
    p.set_material("arm_*", arm)
    p.set_material("glow_core", core)
    p.set_material("glow_eyes", eyes)
    p.paint(OUT)


if __name__ == "__main__":
    main()
