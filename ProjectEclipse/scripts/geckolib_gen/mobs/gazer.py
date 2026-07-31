#!/usr/bin/env python3
"""Gazer texture driver (MC1 — GeckoLib conversion, F-098 wave M-C).

Design sheet (old art brief in docs/uv/gazer.md, refined for the new 19-bone geo): a
ragged void-cloth watcher — deep desaturated indigo cloak `#262040` with vertical fold
weave and a shadowed hem, near-black hood `#1B1730` whose front opening is a pure void
ring around the mask, dusk-violet shoulder mantle `#383159`, six kelp-ragged hem tatters
`#211C38` (two chain segments each), and a proud brow ledge of dark cloth. The identity
piece is the FACE: a pale bone mask `#EFE6CC` (EMISSIVE — the only light this mob owns)
with two hollow void eye slits, behind which two violet-hot iris pips
(`glow_iris_left/right`, `#E8D6FF -> #A87CF0`) float proud and dilate. The cloth lids
(`lid_top/bottom`) are hood fabric with a darkened closing edge; they are NOT emissive
and occlude the mask glow when they scale shut.

Emissive (glowmask — the Gazer's FIRST, it previously used a RenderType.eyes re-render):
`glow_iris_*` auto via the `glow_` prefix; `glow_face` gets a CUSTOM glow painter
(same-salt twin of the albedo mask) so the eye slits and the mask's edge faces stay
dark in the mask — only the pale front burns, dimmed slightly toward the rim so the
glow vignettes into the hood void. All emissive pixels are painted at full brightness
in the albedo too (conventions doc §4 — Iris shaderpacks dim glow layers to albedo).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/gazer.py
Writes src/main/resources/assets/eclipse/textures/entity/gazer.png + _glowmask.png
(both 64x64 — GeckoLib's AutoGlowingTexture enforces matching canvases).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, kelp, mix, mul, weave, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/gazer.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/gazer.png"

SEED = 0x6A2E77CD  # gaze violet

CLOAK = hexc("#262040")
CLOAK_DEEP = hexc("#1A1630")
HOOD = hexc("#1B1730")
HOOD_VOID = hexc("#0A0714")
MANTLE = hexc("#383159")
MANTLE_HI = hexc("#4A4270")
TATTER = hexc("#211C38")
BROW = hexc("#141024")
LID = hexc("#241E3D")
LID_EDGE = hexc("#0F0B1E")
MASK = hexc("#EFE6CC")
MASK_DIM = hexc("#C9BC9E")
SLIT = hexc("#0E0A1C")
IRIS_HOT = hexc("#E8D6FF")
IRIS = hexc("#A87CF0")

_cloak_weave = weave(CLOAK, direction=1, amp=0.30, salt=7)
_hood_weave = weave(HOOD, direction=1, amp=0.26, salt=9)
_mantle_weave = weave(MANTLE, direction=0, amp=0.24, salt=11)
_lid_weave = weave(LID, direction=2, amp=0.22, salt=15)


def cloak_cloth(px):
    """Cloak body: vertical fold weave, a faint center seam on the front, and a
    shadowed bottom hem row so the floating cloth reads as lit from the mask above."""
    col = _cloak_weave(px)
    if px.face == "north" and px.fw > 4 and px.fx == px.fw // 2:
        col = mix(col, CLOAK_DEEP, 0.45)  # center seam
    if px.face in ("north", "south", "east", "west") and px.fy >= px.fh - 2:
        col = mix(col, CLOAK_DEEP, 0.35 + 0.3 * (px.fy - (px.fh - 2)))
    if px.face == "down":
        col = mul(col, 0.55)  # hem underside: near-black (it hovers over its shadow)
    return col


def hood_cloth(px):
    """Hood: near-black weave; the FRONT face's center is a pure void ring around the
    mask plate (the 6x6 glow_face covers rows/cols 1..6 — everything the mask does not
    cover is the hood interior, and the interior is nothing)."""
    if px.face == "north" and 1 <= px.fx <= px.fw - 2 and 1 <= px.fy <= px.fh - 2:
        return mul(HOOD_VOID, 0.9 + px.noise(19) * 0.2)
    col = _hood_weave(px)
    if px.face == "up":
        col = mul(col, 1.12)  # crown catches what little sky there is
    return col


def mantle_cloth(px):
    """Shoulder mantle: dusk-violet weave with a lighter top edge (the one surface
    that faces the sky) and darkened underside."""
    if px.face == "up":
        return mix(_mantle_weave(px), MANTLE_HI, 0.35)
    col = _mantle_weave(px)
    if px.face in ("north", "south", "east", "west") and px.fy == 0:
        col = mix(col, MANTLE_HI, 0.4)
    return col


def brow_cloth(px):
    """Brow ledge: darkest cloth in the sheet — a shadow shelf over the mask."""
    col = mul(BROW, 0.9 + px.noise(23) * 0.2)
    if px.face == "down":
        col = mul(col, 0.7)  # underside faces the glowing mask: keep it void-dark
    return col


def lid_cloth(px):
    """Eyelids: hood cloth with a darkened CLOSING edge (bottom row of lid_top, top row
    of lid_bottom) so a blink reads as a hard shutter line across the glow."""
    closing_edge = (px.gy < 36 and px.fy == px.fh - 1) or (px.gy >= 36 and px.fy == 0)
    if px.face in ("north", "south") and closing_edge:
        return mix(LID_EDGE, LID, px.noise(27) * 0.3)
    return _lid_weave(px)


def _slit(px):
    """The two hollow eye slits on the mask front: face-local columns 1 and 4,
    rows 2..3 (the iris pips float proud exactly behind these holes)."""
    return px.fx in (1, 4) and 2 <= px.fy <= 3


def mask_face(px):
    """The pale mask (north face only; every other face of the plate is dark edge
    material): bone-pale with a soft radial dim toward the rim, void eye slits, one
    chipped corner and a faint etched chin mark. Shadeless — this is the mob's light."""
    if px.face != "north":
        return mul(HOOD_VOID, 1.2)  # plate edges melt into the hood void
    if _slit(px):
        return SLIT
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = max(abs(px.fx - cx) / max(cx, 0.5), abs(px.fy - cy) / max(cy, 0.5))
    col = mix(MASK, MASK_DIM, max(0.0, min(1.0, (d - 0.4) * 1.1)))
    col = mul(col, 0.96 + px.noise(31) * 0.08)  # bone grain
    if (px.fx, px.fy) == (5, 0):
        col = mix(col, SLIT, 0.75)  # chipped corner
    if (px.fx, px.fy) == (5, 1):
        col = mix(col, SLIT, 0.35)
    if px.fy == 5 and px.fx in (2, 3):
        col = mix(col, MASK_DIM, 0.5)  # etched chin mark
    return col


mask_face.shadeless = True


def mask_glow(px):
    """Glowmask twin of the mask (same slit/chip math): only the pale NORTH face burns,
    dimmed toward the rim so the glow vignettes into the hood; slits and edge faces
    stay dark so the iris pips read as separate lights inside the holes."""
    if px.face != "north" or _slit(px):
        return None
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = max(abs(px.fx - cx) / max(cx, 0.5), abs(px.fy - cy) / max(cy, 0.5))
    alpha = 215 - int(max(0.0, min(1.0, (d - 0.4) * 1.1)) * 90)
    if (px.fx, px.fy) == (5, 0):
        alpha = 60  # the chip barely glows
    return with_alpha(mask_face(px), alpha)


def iris_pip(px):
    """Iris pip: violet-hot core fading outward, stray pale glints. Shadeless and
    auto-glowed whole via the glow_ bone prefix (full alpha — the dilation drama is
    animated scale, not paint)."""
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = max(abs(px.fx - cx) / max(cx, 0.5), abs(px.fy - cy) / max(cy, 0.5))
    col = mix(IRIS_HOT, IRIS, max(0.0, min(1.0, d * 0.8)))
    if px.noise(37) > 0.9:
        col = mix(col, hexc("#FFFFFF"), 0.35)
    return col


iris_pip.shadeless = True


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("cloak", cloak_cloth)
    painter.set_material("tatter_*_1", kelp(TATTER, salt=41, max_cut=1))
    painter.set_material("tatter_*_2", kelp(mul(TATTER, 0.85), salt=43, max_cut=2))
    painter.set_material("mantle", mantle_cloth)
    painter.set_material("hood", hood_cloth)
    painter.set_material("brow", brow_cloth)
    painter.set_material("glow_face", mask_face)
    painter.set_glow_painter("glow_face", mask_glow)
    painter.set_material("glow_iris_*", iris_pip)
    painter.set_material("lid_*", lid_cloth)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
