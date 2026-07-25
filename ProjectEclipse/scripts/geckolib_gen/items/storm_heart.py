#!/usr/bin/env python3
"""`storm_heart` GeckoLib ITEM texture driver (PLAN-ITEMS B1).

The Fog Tyrant's condensed tempest as an item-frame showpiece: a wet-slate cage
(MOB-BOSS2 storm ramp, `scripts/geckolib_gen/mobs/fog_tyrant.py` constants) around
a rotating white-hot core (`glow_core`, TEXT-white cooling to ACCENT purple) and
three `glow_arc_*` lightning planes in the Tyrant's electric-seam ramp — the `idle`
anim flickers them via scale 0<->1 so item frames desync nicely.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/items/storm_heart.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, metal, mix, mul  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/item/storm_heart.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/item/stormheart/storm_heart.png"

SEED = 0x570B4  # "STORM"

STORM_DEEP = hexc("#232830")   # fog_tyrant.py storm blue-black
SLATE = hexc("#39414B")        # fog_tyrant.py wet slate
FOG_HEM = hexc("#8496AB")      # fog_tyrant.py fog-bank pale
SEAM_LO = hexc("#9FE8FF")      # electric seam
SEAM_HI = hexc("#CFF3FF")      # electric seam, hot
CORE_HOT = hexc("#F6FEFF")     # caged storm core
ACCENT = hexc("#B98CFF")       # eclipse purple cooling rim

# Hand-authored jagged bolt down each 6x6 arc plane (fx, fy): one main stroke
# with a fork — flickered whole by the anim, so the shape itself stays static.
BOLT = {
    (3, 0), (2, 1), (3, 2), (2, 3), (1, 4), (2, 5),
    (4, 2), (5, 3),  # the fork
}


def slate_rib(salt):
    """Wet-slate cage metal with a fog-pale top light along the rib edges."""
    base = metal(SLATE, salt=salt)

    def fn(px):
        col = base(px)
        if px.fy == 0 and px.face in ("north", "south", "east", "west"):
            col = mix(col, FOG_HEM, 0.3)
        return col

    return fn


def bolt_plane(px):
    """Electric arc strokes only; everything else transparent."""
    if (px.fx, px.fy) not in BOLT:
        return None
    hot = px.noise(3) > 0.55
    return mix(SEAM_HI, CORE_HOT, 0.5) if hot else SEAM_LO


bolt_plane.shadeless = True


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("cage", metal(STORM_DEEP, salt=9))
    painter.set_material("rib_*", slate_rib(salt=11))
    # Rotating core: white-hot center cooling to eclipse purple at the rim.
    painter.set_material("glow_core", flame(CORE_HOT, mix(ACCENT, SEAM_LO, 0.35), salt=17))
    painter.set_material("glow_arc_*", bolt_plane)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
