#!/usr/bin/env python3
"""Herald of the Eclipse texture driver (MA3 — GeckoLib conversion, F-098 wave M-A).

Design sheet (old art brief in docs/uv/herald.md, refined for the new 31-bone geo): a
broken godhead of near-black violet glass `#181224` re-ground into diagonal facet cells,
laced with GOLD crack veins `#E8A83A -> #FFD86A` that wander the core; a blazing gold
inner eye (`glow_eye`, void pupil `#100A18`); three quasi-transparent `glow_veins`
plates 0.75px proud of the core whose ONLY opaque pixels are the floating gold vein
paths; obsidian horns with burning gold tips; dark-glass shoulder shields with a gold
crest fin; 8 pale-violet corona shards (`#C88AFF`) with hot tips; a hot-lavender halo
(the volley "ammo"); and dark umbral tentacle chains `#241C36` with joint banding and
ragged kelp hems.

Emissive (glowmask — the Herald's FIRST): `glow_eye` + `glow_veins` auto via the
`glow_` prefix; custom glow painters add the core's gold fissures (same-salt albedo
twin, so mask and albedo can never drift), the crown-spike + horn tips, the shield
crest, the shard TIPS (dimmed ~alpha 180 — `HeraldGeoRenderer.TelegraphGlowLayer`
pulses the whole layer during volley telegraphs) and the full halo. All emissive
pixels are also painted bright in the albedo (conventions doc §4).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/herald.py
Writes src/main/resources/assets/eclipse/textures/entity/herald.png + _glowmask.png
(both 128x128 — GeckoLib's AutoGlowingTexture enforces matching canvases).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, kelp, metal, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/herald.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/herald.png"

SEED = 0x0E8A83A5  # herald gold

GLASS = hexc("#181224")
GLASS_HI = hexc("#2A2140")
GLASS_EDGE = hexc("#3D3158")
GOLD = hexc("#E8A83A")
GOLD_HOT = hexc("#FFD86A")
PUPIL = hexc("#100A18")
CORONA = hexc("#C88AFF")
CORONA_HOT = hexc("#E9DCFF")
CORONA_DEEP = hexc("#4A2E66")
HORN = hexc("#201830")
TENTACLE = hexc("#241C36")

_obsidian = metal(HORN, salt=29)


def _facet(px, salt=71):
    """Black-glass facet id in [0,1): diagonal cells (3-4 texel pitch)."""
    return px.noise(salt, x=(px.gx + px.gy) // 3, y=(px.gx - px.gy) // 4)


def vein_color(px):
    return mix(GOLD, GOLD_HOT, px.noise(57) * 0.7)


def core_vein_at(px, salt=31, spacing=9):
    """Wandering vertical gold hairlines every ~9 texels with breaks — shared by the
    albedo (bright paint) and the glowmask twin (same salt) so they always align."""
    column = px.gx // spacing
    wander = int(px.noise(salt, x=column, y=px.gy // 3) * 7.0) - 3
    if px.gx != column * spacing + 4 + wander:
        return False
    return px.noise(salt + 7, y=px.gy // 2) > 0.4


def core_glass(px):
    """The godhead core: faceted black-violet glass crossed by gold crack veins, with a
    lighter beveled rim row so the cube reads as one carved monolith."""
    if core_vein_at(px):
        return vein_color(px)
    col = mul(GLASS, 0.92 + _facet(px) * 0.28)
    if _facet(px) > 0.87:
        col = mix(col, GLASS_EDGE, 0.4)  # glassy catch-light facet
    if px.face in ("north", "south", "east", "west") and px.fh > 2 and px.fy == 0:
        col = mix(col, GLASS_HI, 0.5)  # bevel highlight along the top
    return col


def brow_sill(px):
    """Proud brow ledge over the eye: dark glass, gold-warmed on the lower row that
    catches the eye's light."""
    col = mul(GLASS_HI, 0.9 + _facet(px, salt=73) * 0.2)
    if px.face in ("north", "south", "east", "west") and px.fy == px.fh - 1:
        col = mix(col, GOLD, 0.45)
    return col


def crown_spike(px):
    """Rear crown spikes (head cubes 2/3, h=5): obsidian shafts, burning gold tip row."""
    if px.face in ("north", "south", "east", "west") and px.fy <= 0:
        return mix(GOLD_HOT, GOLD, px.noise(23) * 0.5)
    if px.face == "up":
        return GOLD_HOT
    return _obsidian(px)


def head_glow(px):
    """Glowmask for the head bone: the core's gold fissures (same-salt twin) plus the
    crown-spike tips. The brow sill stays dark."""
    if px.fh == 12 and core_vein_at(px):
        return with_alpha(vein_color(px), 190)
    if px.fh == 5 and px.face in ("north", "south", "east", "west") and px.fy <= 0:
        return with_alpha(GOLD_HOT, 210)
    if px.fh == 1 and px.fw == 1 and px.face == "up":
        return with_alpha(GOLD_HOT, 210)  # spike up-cap (1x1)
    return None


def eye(px):
    """The inner eye: a gold furnace with a 2x2 void pupil on the protruding front
    face. Shadeless — the whole bone auto-copies into the glowmask."""
    if px.face == "north" and 2 <= px.fx <= 3 and 2 <= px.fy <= 3:
        return PUPIL
    base = flame(GOLD_HOT, GOLD)(px)
    if px.noise(61) > 0.94:
        return mix(base, CORONA_HOT, 0.5)  # stray violet glint in the iris
    return base


eye.shadeless = True


def plate_veins(px):
    """North vein plate (glow_veins cube 0): fully transparent EXCEPT two wandering
    vertical gold paths + one horizontal branch — floating veins 0.75px proud of the
    glass. Auto-glowed via the bone prefix (only the opaque pixels burn)."""
    if px.face != "north" or px.fw < 8:
        return None  # thin edge faces stay empty
    for k, anchor in enumerate((2, 7)):
        cx = anchor + int(px.noise(41 + k, x=0, y=px.gy // 2) * 3.0) - 1
        if px.fx == max(0, min(px.fw - 1, cx)) and px.noise(49 + k) > 0.2:
            return vein_color(px)
    branch_y = 3 + int(px.noise(45, x=0, y=0) * 4.0)
    if px.fy == branch_y and 1 <= px.fx <= px.fw - 2 and px.noise(53) > 0.45:
        return vein_color(px)
    return None


plate_veins.shadeless = True


def column_veins(px):
    """Side vein columns (glow_veins cubes 1/2): dashed gold runs up the 1px faces
    (2-texel dashes, ~half coverage — solid pillars would out-shine the eye)."""
    if px.face in ("up", "down"):
        return None
    if px.noise(43, x=0, y=px.gy // 2) > 0.52:
        return vein_color(px)
    return None


column_veins.shadeless = True


def horn_base(px):
    """Horn base (h=6): obsidian with a warm gradient toward the joint with the tip."""
    col = _obsidian(px)
    if px.face in ("north", "south", "east", "west") and px.fy <= 1:
        col = mix(col, GOLD, 0.3 - px.fy * 0.15)
    return col


def horn_tip(px):
    """Horn tip (h=5): obsidian into a burning gold point (top two rows)."""
    if px.face == "up":
        return GOLD_HOT
    if px.face in ("north", "south", "east", "west") and px.fy <= 1:
        return mix(GOLD_HOT, GOLD, px.fy * 0.5)
    return mix(_obsidian(px), GOLD, 0.15)


def horn_glow(px):
    """Glowmask for the horns: only the tip cube's top rows burn."""
    if px.fh == 5 and px.face in ("north", "south", "east", "west") and px.fy <= 1:
        return with_alpha(mix(GOLD_HOT, GOLD, px.fy * 0.5), 220)
    if px.fh == 1 and px.fw == 1 and px.face == "up":
        return with_alpha(GOLD_HOT, 220)  # tip up-cap (1x1)
    return None


def shield_plate(px):
    """Shoulder-shield plate (h=10): faceted dark glass with a beveled rim."""
    col = mul(GLASS, 0.9 + _facet(px, salt=77) * 0.3)
    if _facet(px, salt=77) > 0.85:
        col = mix(col, GLASS_EDGE, 0.4)
    on_rim = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
    if on_rim and px.fw > 2 and px.fh > 2:
        col = mix(col, GLASS_HI, 0.35)
    return col


def shield_fin(px):
    """Crest fin (h=7): dark glass whose top row + up face burn gold."""
    if px.face == "up":
        return mix(GOLD_HOT, GOLD, px.noise(27) * 0.6)
    if px.face in ("north", "south", "east", "west") and px.fy == 0:
        return mix(GOLD, GOLD_HOT, px.noise(33) * 0.6)
    return mul(GLASS_HI, 0.85 + _facet(px, salt=79) * 0.25)


def shield_material(px):
    """Bone-level dispatch: the fin's side faces are 7 tall, the plate's are 10."""
    if px.face == "up":
        return shield_fin(px) if px.fw <= 1 or px.fh <= 3 else shield_plate(px)
    return shield_fin(px) if px.fh == 7 else shield_plate(px)


def shield_glow(px):
    """Glowmask for the shields: only the fin crest (top row + up face) burns."""
    if px.face == "up" and (px.fw <= 1 or px.fh <= 3):
        return with_alpha(mix(GOLD_HOT, GOLD, px.noise(27) * 0.6), 200)
    if px.fh == 7 and px.face in ("north", "south", "east", "west") and px.fy == 0:
        return with_alpha(mix(GOLD, GOLD_HOT, px.noise(33) * 0.6), 200)
    return None


def shard_glass(px):
    """Corona shard: pale-violet glass fading deep toward the base, hot burning tip
    (top rows) — the telegraph pulse lives in the renderer layer, not the paint."""
    if px.face == "up":
        return mix(CORONA_HOT, CORONA, px.noise(19) * 0.5)
    if px.face == "down":
        return mul(CORONA_DEEP, 0.8)
    t = px.fy / max(1, px.fh - 1)
    col = mix(mix(CORONA_HOT, CORONA, 0.4 + px.noise(21) * 0.3), CORONA_DEEP, min(1.0, t * 1.2))
    if _facet(px, salt=83) > 0.88:
        col = mix(col, CORONA_HOT, 0.3)
    return col


def shard_glow(px):
    """Glowmask for the corona shards: tips only, dimmed — the renderer's telegraph
    layer modulates brightness, the mask stays subtle at rest."""
    if px.face == "up":
        return with_alpha(mix(CORONA_HOT, CORONA, px.noise(19) * 0.5), 170)
    if px.face in ("north", "south", "east", "west") and px.fy <= 1:
        return with_alpha(mix(CORONA_HOT, CORONA, px.fy * 0.4), 180)
    return None


_kelp_upper = kelp(TENTACLE, salt=37)
_kelp_lower = kelp(mul(TENTACLE, 0.85), salt=39, max_cut=2)


def _banded(kelp_fn):
    """Umbral tentacle: kelp weave + a lighter violet joint band every 4th row, so the
    chains read as segmented links instead of a black smear against the dark arena."""
    def fn(px):
        col = kelp_fn(px)
        if col is not None and px.face not in ("up", "down") and px.gy % 4 == 3:
            col = mix(col, GLASS_EDGE, 0.5)
        return col
    return fn


def main():
    painter = GeoPainter(GEO, seed=SEED)
    # head: core / brow sill / two rear crown spikes (cube order in the geo).
    painter.set_cube_material("head", 0, core_glass)
    painter.set_cube_material("head", 1, brow_sill)
    painter.set_cube_material("head", 2, crown_spike)
    painter.set_cube_material("head", 3, crown_spike)
    painter.set_glow_painter("head", head_glow)
    painter.set_material("glow_eye", eye)
    # glow_veins: proud transparent plates, only the vein pixels are opaque (+ auto-glow).
    painter.set_cube_material("glow_veins", 0, plate_veins)
    painter.set_cube_material("glow_veins", 1, column_veins)
    painter.set_cube_material("glow_veins", 2, column_veins)
    painter.set_cube_material("horn_left", 0, horn_base)
    painter.set_cube_material("horn_left", 1, horn_tip)
    painter.set_cube_material("horn_right", 0, horn_base)
    painter.set_cube_material("horn_right", 1, horn_tip)
    painter.set_glow_painter("horn_*", horn_glow)
    painter.set_material("shield_*", shield_material)
    painter.set_glow_painter("shield_*", shield_glow)
    painter.set_material("shard*", shard_glass)
    painter.set_glow_painter("shard*", shard_glow)
    painter.set_material("halo", flame(CORONA_HOT, CORONA))
    painter.set_glow("halo", 1.0)  # the volley ammo burns whole
    painter.set_material("tentacle_*_1", _banded(_kelp_upper))
    painter.set_material("tentacle_*_2", _banded(_kelp_lower))
    painter.paint(OUT)


if __name__ == "__main__":
    main()
