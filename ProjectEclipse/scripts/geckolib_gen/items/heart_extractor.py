#!/usr/bin/env python3
"""Heart extractor texture driver (PLAN-ITEMS A3) — GeckoLib ITEM geo upgrade.

Paints `geo/item/heart_extractor.geo.json` (64x64): a brass-and-glass heart-tap —
tarnished-silver needle, herald-brass collars and thumb-ring plunger
(`eclipse_palette.py` GOLD ramp), a translucent glass chamber (partial alpha — the
renderer uses a translucent render type) and the crimson vitae fill (`glow_vitae`,
DANGER-crimson emissive). Per the drift_lantern shine-through convention the vitae
glow is ALSO painted into the CHAMBER's glowmask pixels (side-face centers, low
alpha) so the fill reads through the glass.

Writes `textures/item/extractor/heart_extractor.png` + `_glowmask.png`.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/items/heart_extractor.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, glass, hexc, metal, mix, mul  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/item/heart_extractor.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/item/extractor/heart_extractor.png"

SEED = 0x4EA127  # "heart-tap" — fixed, never change (byte-identical reruns)

WHITE = hexc("#FFFFFF")
# eclipse_palette.py ramps: herald brass/gold, crimson/vitae, cold needle steel.
BRASS_DARK = hexc("#9A6018")
BRASS = hexc("#E8A83A")
BRASS_LIGHT = hexc("#FFD86A")
STEEL = hexc("#B9BFC8")
GLASS_TINT = hexc("#9FB8C4", 88)
CRIMSON_DARK = hexc("#520C22")
CRIMSON = hexc("#A6193A")
SCARLET = hexc("#E73753")


def brass(base, salt):
    """Brushed brass with a 1px lathe-line highlight on the top edge of side faces."""
    base_fn = metal(base, salt=salt)

    def fn(px):
        col = base_fn(px)
        if px.face in ("north", "south", "east", "west") and px.fy == 0:
            col = mix(col, BRASS_LIGHT, 0.5)
        return col

    return fn


def needle_steel(px):
    """Cold steel needle, darkening toward the point (down end)."""
    shade = 1.0 - 0.35 * (px.fy / max(px.fh - 1, 1)) if px.fh > 1 else 1.0
    col = mul(STEEL, shade * (0.9 + px.noise(9) * 0.2))
    return col


def ring_plate(px):
    """Thumb-ring plate (zero-depth plane): brass staple with the center-bottom texel
    dropped, so the plate silhouettes as a ring instead of a paddle."""
    if px.fx == px.fw // 2 and px.fy == px.fh - 1:
        return None
    col = mul(BRASS, 0.9 + px.noise(15) * 0.25)
    if px.fy == 0:
        col = mix(col, BRASS_LIGHT, 0.5)
    return col


def chamber_shine(px):
    """Vitae shine-through on the chamber glass (glowmask only): the two center
    columns of each side face, fading upward — the fill glows through the glass."""
    if px.face not in ("north", "south", "east", "west"):
        return None
    mid = px.fw // 2
    if px.fx not in (mid - 1, mid):
        return None
    t = px.fy / max(px.fh - 1, 1)
    alpha = int(40 + 90 * t)  # brighter toward the bottom (where the fill sits)
    r, g, b, _ = mix(SCARLET, CRIMSON, t)
    return (r, g, b, alpha)


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("needle", needle_steel)
    painter.set_material("frame", brass(BRASS, salt=11))
    painter.set_material("plunger", brass(mul(BRASS, 0.92), salt=13))
    painter.set_cube_material("plunger", 1, ring_plate)
    painter.set_material("glow_vitae", flame(mix(SCARLET, WHITE, 0.25), CRIMSON, salt=17))
    painter.set_material("chamber", glass(GLASS_TINT, salt=19))
    painter.set_glow_painter("chamber", chamber_shine)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
