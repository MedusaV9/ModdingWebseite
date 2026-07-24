#!/usr/bin/env python3
"""Zauberstab texture driver (W4-WAND / IDEA-19) — the mod's first GeckoLib ITEM.

One geo ({geo/item/eclipse_wand.geo.json}), FOUR texture variants; the client renderer
(client/wand/EclipseWandRenderer) swaps them by the synced `wand_path` component and the
AutoGlowingGeoLayer lights each variant's `_glowmask`:

    eclipse_wand.png        pathless raw branch (quiet, a faint rune seam is the only glow)
    eclipse_wand_riss.png   Phasenriss  — void-violet char, glitch-bright shard crown
    eclipse_wand_glut.png   Glutherz    — ember-cracked char, flame fins + white-hot core
    eclipse_wand_stern.png  Sternenfall — midnight blue, constellation disc + star points

Every variant paints ALL bones (ornaments of foreign paths are hidden by the renderer,
never unpainted). Also emits the flat 16x16 `wizard_catalyst.png` (Sun-Core Catalyst —
item REGISTERED by the W4-WIZARD sibling; the texture/model asset lives with the wand
recipe that consumes it).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/items/eclipse_wand.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, mix, mul, wood  # noqa: E402

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("Pillow required: pip install Pillow")
    raise

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/item/eclipse_wand.geo.json"
OUT_DIR = ROOT / "src/main/resources/assets/eclipse/textures/item/wand"
CATALYST_OUT = ROOT / "src/main/resources/assets/eclipse/textures/item/wizard_catalyst.png"

SEED = 0x19A9D  # IDEA-19 wand

WHITE = hexc("#FFFFFF")

# Path palettes: (branch wood, ornament core, ornament halo, rune seam glow)
PALETTES = {
    "none": (hexc("#6B4E37"), hexc("#8E7BB8"), hexc("#5C4E80"), hexc("#8E7BB8")),
    "riss": (hexc("#4A3B5E"), hexc("#D9B8FF"), hexc("#7B4FD0"), hexc("#B98CFF")),
    "glut": (hexc("#4A322A"), hexc("#FFE9A8"), hexc("#FF7A2E"), hexc("#FF9A4D")),
    "stern": (hexc("#33405E"), hexc("#EAF9FF"), hexc("#4FB5D0"), hexc("#7FE7FF")),
}


def rune_seam(glow_color, salt):
    """Sparse emissive rune pixels marching up the shaft's front/back faces."""

    def fn(px):
        if px.face not in ("north", "south"):
            return None
        if px.fx != px.fw // 2:
            return None
        if px.noise(salt, x=0) < 0.55:
            return None
        return mix(glow_color, WHITE, 0.25 * px.noise(salt + 1))

    return fn


def plate(base, salt):
    """Dark metal-ish plate with a subtle grain (riss ring / stern disc albedo)."""

    def fn(px):
        return mul(base, 0.75 + px.noise(salt) * 0.4)

    return fn


def disc_constellation(glow_color, salt):
    """Pinpoint star nodes on the disc's up face only — the constellation reads from above."""

    def fn(px):
        if px.face != "up":
            return None
        if px.noise(salt) < 0.82:
            return None
        return mix(glow_color, WHITE, 0.5)

    return fn


def ring_rim(glow_color, salt):
    """Emissive outer rim for the riss shard-crown ring."""

    def fn(px):
        if px.face != "up":
            return None
        if 0 < px.fx < px.fw - 1 and 0 < px.fy < px.fh - 1:
            return None
        if px.noise(salt) < 0.35:
            return None
        return mix(glow_color, WHITE, 0.2)

    return fn


def paint_variant(key):
    branch, core, halo, seam_glow = PALETTES[key]
    painter = GeoPainter(GEO, seed=SEED)

    # Shared branch base — wood grain in the path's tint; tip slightly brightened.
    painter.set_material("handle", wood(branch, salt=11))
    painter.set_material("shaft", wood(mul(branch, 1.08), salt=13))
    painter.set_material("knot", wood(mul(branch, 0.9), salt=15))
    painter.set_material("tip", flame(mix(branch, core, 0.45), halo, salt=17))
    painter.set_glow_painter("shaft", rune_seam(seam_glow, salt=19))

    # Ornaments (glow_* bones auto-copy into the glowmask at full brightness).
    painter.set_material("glow_riss_*", flame(mix(core, PALETTES["riss"][1], 0.5), PALETTES["riss"][2], salt=23))
    painter.set_material("riss_ring", plate(mix(branch, PALETTES["riss"][2], 0.35), salt=25))
    painter.set_glow_painter("riss_ring", ring_rim(PALETTES["riss"][3], salt=27))

    painter.set_material("glow_glut_core", flame(mix(PALETTES["glut"][1], WHITE, 0.35), PALETTES["glut"][2], salt=29))
    painter.set_material("glow_glut_flame_*", flame(PALETTES["glut"][1], PALETTES["glut"][2], salt=31))
    painter.set_material("glut_fin_*", flame(mix(PALETTES["glut"][2], PALETTES["glut"][1], 0.3),
                                             mul(PALETTES["glut"][2], 0.6), salt=33))
    painter.set_glow("glut_fin_*", strength=0.85)

    painter.set_material("glow_stern_*", flame(mix(PALETTES["stern"][1], WHITE, 0.3), PALETTES["stern"][2], salt=37))
    painter.set_material("stern_disc", plate(mix(branch, PALETTES["stern"][2], 0.3), salt=39))
    painter.set_glow_painter("stern_disc", disc_constellation(PALETTES["stern"][3], salt=41))

    suffix = "" if key == "none" else f"_{key}"
    painter.paint(OUT_DIR / f"eclipse_wand{suffix}.png")


# ---------------------------------------------------------------------------
# wizard_catalyst.png — flat 16x16 Sun-Core Catalyst (recipe gate item)
# ---------------------------------------------------------------------------

def _hash01(x, y, salt):
    h = (x * 374_761_393 + y * 668_265_263 + salt * 2_147_483_647 + SEED) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1_274_126_177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def paint_catalyst():
    gold = hexc("#FFE9A8")
    fire = hexc("#FFAE3F")
    umbra = hexc("#5A2E73")
    rim = hexc("#2A1638")
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    cx = cy = 7.5
    for y in range(16):
        for x in range(16):
            r = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            n = _hash01(x, y, 5)
            if r < 2.6:
                col = mix(gold, hexc("#FFFFFF"), 0.35 + 0.25 * n)
            elif r < 4.6:
                col = mix(fire, gold, max(0.0, 0.9 - (r - 2.6) / 2.0) * (0.7 + 0.3 * n))
            elif r < 6.2:
                col = mix(umbra, fire, max(0.0, 0.45 - (r - 4.6) / 3.2) + 0.1 * n)
            elif r < 7.2:
                col = mul(rim, 0.85 + 0.3 * n)
            else:
                continue
            img.putpixel((x, y), col)
    # Four deterministic sparkles on the umbral ring.
    for sx, sy in ((2, 7), (13, 8), (7, 2), (8, 13)):
        img.putpixel((sx, sy), hexc("#FFF7DC"))
    CATALYST_OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(CATALYST_OUT)
    print(f"painted wizard_catalyst (16x16) -> {CATALYST_OUT}")


def main():
    for key in ("none", "riss", "glut", "stern"):
        paint_variant(key)
    paint_catalyst()


if __name__ == "__main__":
    main()
