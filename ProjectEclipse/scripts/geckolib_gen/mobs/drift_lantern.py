#!/usr/bin/env python3
"""Drift Lantern / Treiblaterne texture driver (P6-W1 pilot).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3): a soul-lantern "jellyfish" —
iron-framed glass cage with an inner soul flame and four hanging kelp-chain tendrils.
Palette: iron #3B3F46, glass #9FB8C4 @ 40% alpha faces, soul flame #7FE3D2, tendrils
#2E4A44. Emissive: flame + faint cage rim.

Glow-through-a-translucent-shell rule (see docs/plans_v3/handoff/P6_geckolib_conventions.md):
the flame sits INSIDE the 40%-alpha glass cube, so the glow layer's re-render of the inner
flame bone gets depth-rejected under the glass. The shine-through therefore lives in the
CAGE's glowmask pixels (center-weighted soul-tinted blob per glass face + a faint rim),
while the flame cube still carries its own full-bright glowmask for uncovered angles.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/drift_lantern.py
Writes src/main/resources/assets/eclipse/textures/entity/drift_lantern.png + _glowmask.png.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, glass, hexc, kelp, metal, mix, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/drift_lantern.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/drift_lantern.png"

SEED = 0x0D71F7A0  # drift lantern

IRON = hexc("#3B3F46")
GLASS = hexc("#9FB8C4", 102)  # 40% alpha faces (rendered via withTranslucency())
FLAME_CORE = hexc("#E9FFF9")
FLAME = hexc("#7FE3D2")
TENDRIL = hexc("#2E4A44")
GLOW_SOUL = hexc("#7FE3D2")


def cage_glow(px):
    """Glowmask for the glass cage: the soul flame shining through the panes.

    Center-weighted blob (strong core alpha, quick falloff) on the four side faces and
    the top; the faint cage rim reads as the frame catching the glow. Bottom face stays
    dark (the iron base plate sits under it)."""
    if px.face == "down":
        return None
    on_rim = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
    if on_rim:
        return with_alpha(GLOW_SOUL, 60) if px.noise(31) > 0.35 else None  # faint cage rim
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = math.hypot((px.fx - cx) / max(cx, 0.5), (px.fy - cy) / max(cy, 0.5))
    if d > 0.95:
        return None
    core = mix(FLAME_CORE, GLOW_SOUL, min(1.0, d))
    alpha = int(230 * (1.0 - d * 0.75))
    return with_alpha(core, max(0, alpha))


def main():
    painter = GeoPainter(GEO, seed=SEED)
    # body = iron plates + hanger loop; per-cube order in the geo: 0 bottom plate,
    # 1 top plate, 2 hanger — all brushed iron.
    painter.set_material("body", metal(IRON))
    painter.set_material("cage", glass(GLASS))
    painter.set_material("glow_flame", flame(FLAME_CORE, FLAME))
    painter.set_material("tendril_*", kelp(TENDRIL))
    # glow_flame is auto-included in the glowmask (glow_ prefix); the cage gets the
    # custom shine-through painter instead of an albedo copy.
    painter.set_glow_painter("cage", cage_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
