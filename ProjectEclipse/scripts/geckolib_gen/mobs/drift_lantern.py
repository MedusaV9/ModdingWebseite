#!/usr/bin/env python3
"""Drift Lantern / Treiblaterne texture driver (P6-W1 pilot, MC3 suspension pass).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3): a soul-lantern "jellyfish" —
iron-framed glass cage with an inner soul flame and four hanging kelp-chain tendrils.
Palette: iron #3B3F46, glass #9FB8C4 @ 40% alpha faces, soul flame #7FE3D2, tendrils
#2E4A44. Emissive: flame + faint cage rim.

MC3 (F-098 wave M-C) hung the lantern on a two-segment SUSPENSION CHAIN (`chain_upper` ->
`chain_lower` -> `body`), so this driver gained a chain material (#5A626D, two shades
lighter than the frame iron so the links read against the limbo fog instead of merging
with the cage) and a catch-light glow painter for the lowest links.

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
from paint_lib import GeoPainter, flame, glass, hexc, kelp, metal, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/drift_lantern.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/drift_lantern.png"

SEED = 0x0D71F7A0  # drift lantern

IRON = hexc("#3B3F46")
CHAIN = hexc("#5A626D")  # two shades lighter than the frame — links must read against fog
GLASS = hexc("#9FB8C4", 102)  # 40% alpha faces (rendered via withTranslucency())
FLAME_CORE = hexc("#E9FFF9")
FLAME = hexc("#7FE3D2")
TENDRIL = hexc("#2E4A44")
GLOW_SOUL = hexc("#7FE3D2")


def chain_link(fade_top=False, salt=61):
    """Suspension-chain segment as real LINKS, not a rod.

    A 2x2 column can never read as a chain through shading alone, so every third texel
    row along the segment is dropped to alpha 0: the holes between the links are actual
    holes (the cube is hollow and back-face-culled, so you see the fog through them).
    Box-UV side faces run top-down, i.e. `fy == 0` is the upper end of the cube — the row
    index therefore doubles as the link phase.

    `fade_top` is for the segment whose upper end has NO anchor: the lantern hangs from
    the limbo fog, so the top two rows ramp out in alpha and the up-face cap is dropped
    entirely. Partial alpha is safe here — the renderer already runs
    `withTranslucency()` for the 40 % glass cage.
    """
    def fn(px):
        if px.face in ("up", "down"):
            return None if (fade_top and px.face == "up") else mul(CHAIN, 0.92)
        if px.fy % 3 == 2:
            return None  # gap between two links
        col = mul(CHAIN, 1.15 if px.fy % 3 == 0 else 0.88)  # lit top edge / shaded belly
        col = mul(col, 0.92 + px.noise(salt, y=px.gy) * 0.2)
        if fade_top and px.fy < 2:
            col = with_alpha(col, 70 if px.fy == 0 else 170)
        return col
    return fn


def chain_glow(px):
    """Catch-light on the lowest links: the flame hangs right under them.

    Only the long column of `chain_lower` qualifies — its side faces are 4 texels tall,
    while the shackle ring's are 1 and the caps are 2, so `fh >= 4` selects the column
    without hard-coding UV coordinates. Alpha fades out over three rows upward; texels
    the material dropped (the link gaps) stay dark because `paint_lib` only offers the
    glow painter pixels the albedo actually painted.
    """
    if px.face in ("up", "down") or px.fh < 4:
        return None
    from_bottom = px.fh - 1 - px.fy
    if from_bottom > 2:
        return None
    return with_alpha(GLOW_SOUL, 75 - from_bottom * 22) if px.noise(37) > 0.4 else None


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
    # Suspension chain (MC3): upper segment dissolves into the fog, lower segment ends in
    # a solid shackle ring (cube[1]) that hides the joint the two segments pivot around.
    painter.set_material("chain_upper", chain_link(fade_top=True))
    painter.set_material("chain_lower", chain_link())
    painter.set_cube_material("chain_lower", 1, metal(IRON))
    painter.set_glow_painter("chain_lower", chain_glow)
    # body = iron plates + hanger loop; per-cube order in the geo: 0 bottom plate,
    # 1 top plate, 2 hanger — all brushed iron.
    painter.set_material("body", metal(IRON))
    painter.set_material("cage", glass(GLASS))
    painter.set_material("glow_flame", flame(FLAME_CORE, FLAME))
    # Inner heartbeat kernel (MOB-AMBIENT): hotter-than-core white so the double-thump
    # pulse reads through the flame cube when the kernel scales past its faces.
    painter.set_material("glow_flame_core", flame(hexc("#FFFFFF"), FLAME_CORE))
    painter.set_material("tendril_*", kelp(TENDRIL))
    # glow_flame is auto-included in the glowmask (glow_ prefix); the cage gets the
    # custom shine-through painter instead of an albedo copy.
    painter.set_glow_painter("cage", cage_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
