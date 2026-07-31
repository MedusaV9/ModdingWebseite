#!/usr/bin/env python3
"""Heart extractor texture driver (PLAN-ITEMS A3) — GeckoLib ITEM geo upgrade.

Paints `geo/item/heart_extractor.geo.json` (64x64): a brass-and-glass heart-tap —
tarnished-silver needle, herald-brass collars and thumb-ring plunger
(`eclipse_palette.py` GOLD ramp), a translucent glass chamber (partial alpha — the
renderer uses a translucent render type) and the crimson vitae fill (`glow_vitae`,
DANGER-crimson emissive). Per the drift_lantern shine-through convention the vitae
glow is ALSO painted into the CHAMBER's glowmask pixels (side-face centers, low
alpha) so the fill reads through the glass.

MD2 additions (Welle M-D, Zensus §5 Zeile MD2):

* `chamber` is now a carrier bone; its glass is split into `chamber_body` (unchanged
  tint) and the hinged `chamber_lid` that snaps shut in `animation.heart_extractor.extract`.
  The lid gets a brass cap + hinge line so the snap reads as a moving PART, not as the
  chamber wobbling.
* `clamp_n`/`clamp_s` — brass jaws on the frame that pinch in behind the lid snap.
* `glow_gauge` — an emissive vitae dial on the lower collar (bezel brow + crimson fill
  bar) that swells while channeling and collapses on extract.
* Frame collars get a faint brass glow filament (the §5-(c) "Glow-Akzente" pass).

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


def lid_glass(px):
    """Chamber lid: the same glass as the body, but with a brass-capped up face and a
    brass hinge line on the north rim, so the lid reads as a separate hinged part
    instead of melting into the body when `chamber_lid` swings open."""
    if px.face == "up":
        col = mul(BRASS, 0.9 + px.noise(27) * 0.22)
        return mix(col, BRASS_LIGHT, 0.35) if px.fy == 0 else col
    col = glass(GLASS_TINT, salt=25)(px)
    if px.face == "north" and px.fy == 0:
        col = mix(col, BRASS_DARK, 0.75)  # hinge barrel
    return col


def _gauge_bar(px):
    """True on the dial's readable fill bar (bottom row of the two tall faces)."""
    return px.face not in ("up", "down") and px.fw >= 2 and px.fy > 0


def gauge_dial(px):
    """Vitae gauge on the lower collar: a brass bezel around a crimson fill bar that burns
    brightest in the center column. Deliberately NOT shadeless — only the bar is emissive
    (see `gauge_glow`), so the bezel stays a piece of metal instead of a lamp."""
    if not _gauge_bar(px):
        return mul(BRASS_DARK, 0.9)           # bezel cap / brow / side cheeks
    centered = abs(px.fx - (px.fw - 1) / 2.0) <= 0.5
    col = mix(CRIMSON, SCARLET, 0.55 if centered else 0.15)
    return mix(col, WHITE, 0.35) if centered else col


def gauge_glow(px):
    """Glowmask for `glow_gauge`. Runs INSTEAD of the automatic albedo copy every `glow_*`
    bone gets — without it the brass bezel would be re-added additively by
    AutoGlowingGeoLayer and the whole dial would read as one orange slab."""
    if not _gauge_bar(px):
        return None
    centered = abs(px.fx - (px.fw - 1) / 2.0) <= 0.5
    r, g, b, _ = mix(CRIMSON, SCARLET, 0.7 if centered else 0.2)
    return (r, g, b, 210 if centered else 130)


def chamber_shine(px):
    """Vitae shine-through on the chamber glass (glowmask only): the center column(s) of
    each side face, fading upward — the fill glows through the glass. Symmetric about the
    face center for odd AND even widths (the body is 3 wide, the lid strip 1 tall)."""
    if px.face not in ("north", "south", "east", "west"):
        return None
    if abs(px.fx - (px.fw - 1) / 2.0) > 0.5:
        return None
    t = px.fy / max(px.fh - 1, 1)
    alpha = int(40 + 90 * t)  # brighter toward the bottom (where the fill sits)
    r, g, b, _ = mix(SCARLET, CRIMSON, t)
    return (r, g, b, alpha)


def collar_filament(px):
    """Faint brass filament catching the vitae light on the frame collars' up faces
    (glowmask only) — a 1px rim ring, dim enough to stay a highlight, not a lamp."""
    if px.face != "up":
        return None
    on_rim = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
    if not on_rim:
        return None
    r, g, b, _ = mix(BRASS, SCARLET, 0.3)
    return (r, g, b, 60)


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("needle", needle_steel)
    painter.set_material("frame", brass(BRASS, salt=11))
    painter.set_material("clamp_*", brass(mul(BRASS, 1.05), salt=29))
    painter.set_material("plunger", brass(mul(BRASS, 0.92), salt=13))
    painter.set_cube_material("plunger", 1, ring_plate)
    painter.set_material("glow_vitae", flame(mix(SCARLET, WHITE, 0.25), CRIMSON, salt=17))
    painter.set_material("glow_gauge", gauge_dial)
    painter.set_material("chamber_body", glass(GLASS_TINT, salt=19))
    painter.set_material("chamber_lid", lid_glass)
    painter.set_glow_painter("chamber_*", chamber_shine)
    painter.set_glow_painter("frame", collar_filament)
    painter.set_glow_painter("glow_gauge", gauge_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
