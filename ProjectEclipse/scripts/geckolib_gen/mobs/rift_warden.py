#!/usr/bin/env python3
"""Rift Warden / Risswächter texture driver (P6-W910, refined by MOB-BOSS2).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.4): a 3-block vertically-split
wraith-knight — the LEFT half wears polished obsidian plate `#1B1D26`/`#2E3242`, the
RIGHT half of the torso is simply GONE, replaced by the `glow_rift_core` void-tear
volume shading `#B98CFF -> #5E2EA8` with four drifting `glow_shard_*` fragments.
Single-horned helm with a violet eye slit, split floating pauldrons, twin curved
rift-blades whose cutting edges burn.

MOB-BOSS2 refinement: every armor plate is re-ground as OBSIDIAN GLASS — diagonal
facet cells with glassy catch-light edges — and VIOLET FISSURES (wandering hairline
cracks `#B98CFF` → `#E9DCFF`, ~14-texel spacing with breaks) creep across plate,
pauldrons and arm; the two proud `crack_plate_*` shards each carry a guaranteed
burning crack path down their face. Fissures reuse the exact albedo pixel test in the
glowmask (same salt), so mask and albedo can never drift apart.

Emissive (glowmask): the rift half (`glow_rift_core`, `glow_shard_*`, `glow_under` —
all auto-included via the `glow_` prefix), the helm eye slit, the honed edge column of
both blades, and (MOB-BOSS2) the violet fissures + crack-plate crack paths (custom
glow painters). All emissive pixels are ALSO painted bright in the albedo (conventions
doc §4 — they must still read under Iris shaderpacks).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/rift_warden.py
Writes src/main/resources/assets/eclipse/textures/entity/rift_warden.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, metal, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/rift_warden.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/rift_warden.png"

SEED = 0x217F0A2D  # rift warden

ARMOR = hexc("#1B1D26")
ARMOR_HI = hexc("#2E3242")
ARMOR_EDGE = hexc("#4A5068")
HORN = hexc("#3A3648")
RIFT = hexc("#B98CFF")
RIFT_DEEP = hexc("#5E2EA8")
RIFT_CORE = hexc("#E9DCFF")
BLADE = hexc("#232732")
BLADE_EDGE = hexc("#B98CFF")
EYE = hexc("#B98CFF")
EYE_CORE = hexc("#E9DCFF")

_plate = metal(ARMOR)
_plate_hi = metal(ARMOR_HI, salt=19)


def _facet(px, salt=71):
    """Obsidian-glass facet id in [0,1): diagonal cells (3–4 texel pitch) so every
    plate reads as fractured volcanic glass instead of flat brushed steel."""
    return px.noise(salt, x=(px.gx + px.gy) // 3, y=(px.gx - px.gy) // 4)


def fissure_at(px, salt=51, spacing=14):
    """Wandering violet fissure hairlines every ~14 texels with breaks — shared by the
    albedo (bright paint) and the glowmask (emissive copy) so they always align."""
    column = px.gx // spacing
    wander = int(px.noise(salt, x=column, y=px.gy // 4) * 9.0) - 4
    if px.gx != column * spacing + 7 + wander:
        return False
    return px.noise(salt + 7) > 0.45


def fissure_color(px):
    return mix(RIFT, RIFT_CORE, px.noise(57) * 0.6)


def fissure_glow(px):
    """Glowmask twin of `fissure_at` (same salt): only the fissure pixels burn."""
    return with_alpha(fissure_color(px), 200) if fissure_at(px) else None


def armor_plate(px):
    """Obsidian-glass plate: near-black steel base re-ground into diagonal facet
    cells with glassy catch-light edges, violet fissures creeping across, and a
    lighter beveled rim row so every plate reads as a separate forged piece."""
    if fissure_at(px):
        return fissure_color(px)
    col = _plate(px)
    facet = _facet(px)
    col = mul(col, 0.9 + facet * 0.24)  # per-facet tone step
    if facet > 0.86:
        col = mix(col, ARMOR_EDGE, 0.35)  # glassy catch-light facet
    if px.face in ("north", "south", "east", "west") and px.fh > 2 and px.fy == 0:
        col = mix(col, ARMOR_EDGE, 0.55)  # bevel highlight along the plate top
    return col


def pauldron(px):
    """Floating pauldrons: brighter polished glass with a violet reflection creeping
    along the inner (down) faces — they hover beside the rift half."""
    if fissure_at(px):
        return fissure_color(px)
    col = _plate_hi(px)
    facet = _facet(px, salt=73)
    col = mul(col, 0.92 + facet * 0.18)
    if px.face == "down":
        col = mix(col, RIFT_DEEP, 0.4)
    elif px.face == "up" and px.noise(43) > 0.9:
        col = mix(col, ARMOR_EDGE, 0.6)  # worn rim glint
    return col


def crack_plate(px):
    """Crack-line plates: proud obsidian-glass shards whose central crack path ALWAYS
    burns — the armor half is visibly held together by rift light. The path wanders
    ±1 texel per 2 rows (front/back faces only; the 1px rims stay dark glass)."""
    if px.face in ("north", "south"):
        cx = px.fw // 2 + int((px.noise(63, x=0, y=px.gy // 2) - 0.5) * 3.0)
        if px.fx == max(0, min(px.fw - 1, cx)):
            return mix(fissure_color(px), RIFT_CORE, 0.25)
    if fissure_at(px):
        return fissure_color(px)
    col = _plate_hi(px)
    facet = _facet(px, salt=77)
    col = mul(col, 0.88 + facet * 0.3)
    if facet > 0.85:
        col = mix(col, ARMOR_EDGE, 0.4)
    return col


def crack_plate_glow(px):
    """Glowmask for the crack plates: the guaranteed crack path + stray fissures."""
    if px.face in ("north", "south"):
        cx = px.fw // 2 + int((px.noise(63, x=0, y=px.gy // 2) - 0.5) * 3.0)
        if px.fx == max(0, min(px.fw - 1, cx)):
            return with_alpha(mix(fissure_color(px), RIFT_CORE, 0.25), 230)
    return fissure_glow(px)


def helm(px):
    """Horned helm: polished plate; the north face carries a 1px violet eye slit
    (row 3, cols 1-4) burning out of a recessed shadow band."""
    if px.face == "north":
        if px.fy == 3 and 1 <= px.fx <= 4:
            return EYE_CORE if px.fx in (2, 3) else EYE
        if px.fy in (2, 4) and 1 <= px.fx <= 4:
            return mul(ARMOR, 0.6)  # visor shadow around the slit
    return _plate_hi(px)


def _blade_edge_px(px):
    """The honed edge: front column (fx 0) of every side face of the blade cubes."""
    return px.face in ("north", "south", "east", "west") and px.fx == 0


def blade(px):
    """Curved rift-blade: near-black steel body, violet burning edge column, and a
    faint rift shimmer creeping up from the tip rows."""
    if _blade_edge_px(px):
        return mix(BLADE_EDGE, RIFT_CORE, 0.3) if px.fy % 4 == 0 else BLADE_EDGE
    col = mul(BLADE, 0.88 + px.noise(13) * 0.24)
    if px.face in ("north", "south", "east", "west") and px.fh > 4 and px.fy >= px.fh - 2:
        col = mix(col, RIFT_DEEP, 0.35)  # tip shimmer
    return col


def blade_glow(px):
    """Glowmask for the blades: only the edge column burns."""
    if _blade_edge_px(px):
        return with_alpha(BLADE_EDGE, 235)
    return None


def helm_glow(px):
    """Glowmask for the helm: only the eye slit."""
    if px.face == "north" and px.fy == 3 and 1 <= px.fx <= 4:
        return with_alpha(EYE_CORE if px.fx in (2, 3) else EYE, 255 if px.fx in (2, 3) else 225)
    return None


def rift_core(px):
    """The void tear that replaces the torso's right half: bright core fading to deep
    violet at the rim, with dark reality-static flecks drifting through it."""
    base = flame(RIFT_CORE, RIFT_DEEP)(px)
    if px.noise(61) > 0.92:
        return mul(RIFT_DEEP, 0.55)  # void static
    return base


rift_core.shadeless = True


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("faulds", armor_plate)
    painter.set_material("hips", armor_plate)
    painter.set_material("torso", armor_plate)
    painter.set_material("pauldron_*", pauldron)
    painter.set_material("crack_plate_*", crack_plate)
    painter.set_material("head", helm)
    painter.set_material("horn", metal(HORN, salt=29))
    painter.set_material("arm_armor", armor_plate)
    painter.set_material("arm_rift", flame(RIFT, RIFT_DEEP))
    painter.set_material("blade_*", blade)
    painter.set_material("glow_rift_core", rift_core)
    painter.set_material("glow_shard_*", flame(RIFT_CORE, RIFT))
    painter.set_material("glow_under", flame(RIFT_DEEP, mul(RIFT_DEEP, 0.5)))
    painter.set_glow("arm_rift", 0.85)  # the rift-side arm is part of the tear
    painter.set_glow_painter("blade_left", blade_glow)
    painter.set_glow_painter("blade_right", blade_glow)
    painter.set_glow_painter("head", helm_glow)
    # MOB-BOSS2 emissive extras: the violet fissures burn on every armor bone, and
    # the crack plates' guaranteed crack paths burn brightest (same-salt albedo twin).
    painter.set_glow_painter("faulds", fissure_glow)
    painter.set_glow_painter("hips", fissure_glow)
    painter.set_glow_painter("torso", fissure_glow)
    painter.set_glow_painter("arm_armor", fissure_glow)
    painter.set_glow_painter("pauldron_*", fissure_glow)
    painter.set_glow_painter("crack_plate_*", crack_plate_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
