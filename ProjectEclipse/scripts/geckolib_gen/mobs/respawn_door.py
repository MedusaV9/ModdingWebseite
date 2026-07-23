#!/usr/bin/env python3
"""Respawn Door texture driver (P6-W3, plans_v3 §2.5).

Design sheet: the imposing 3×5 double door in the ghost ship's sterncastle bulkhead —
twin blackened-oak leaves with eclipse-glyph relief, tarnished-silver banding, oversized
ring handles, an arched header with a glowing eclipse disc, and the purple void plane
behind the seam. Palette: blackened oak #241B14/#1A130E, tarnished silver #8C8F9A,
eclipse purple #B98CFF (blaze) / #6E4DA8 (fade) / #16081F (void edge).

Emissive (per §2.5 "seam/glyphs: #B98CFF blaze"): the void plane + eclipse disc bones are
`glow_`-prefixed (albedo auto-copied to the glowmask at full brightness); the leaves get
a custom glow painter — glyph strokes, ring-handle glint and an edge bleed around every
leaf border so light reads as leaking around the slab even at MC's block resolution.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/respawn_door.py
Writes src/main/resources/assets/eclipse/textures/block/respawn_door.png + _glowmask.png.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, metal, mix, mul, with_alpha, wood  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/block/respawn_door.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/block/respawn_door.png"

SEED = 0x0B98CFF  # the purple, as a number

OAK = hexc("#241B14")
OAK_DEEP = hexc("#1A130E")
SILVER = hexc("#8C8F9A")
SILVER_DARK = hexc("#6F7280")
PURPLE = hexc("#B98CFF")
PURPLE_CORE = hexc("#E7D6FF")
PURPLE_DEEP = hexc("#6E4DA8")
VOID_MID = hexc("#43206B")
VOID_EDGE = hexc("#16081F")
DISC_CORE = hexc("#060309")

# Canvas regions (mirror the per-face UV layout in respawn_door.geo.json).
LEAF_FRONT_RECTS = ((0, 0, 19, 62), (19, 0, 38, 62))    # leaf_nx / leaf_px north faces
LEAF_BACK_RECTS = ((38, 0, 57, 62), (57, 0, 76, 62))    # south faces
HANDLE_FRONT_RECT = (104, 41, 110, 49)


def in_rect(px, rect):
    x0, y0, x1, y1 = rect
    return x0 <= px.gx < x1 and y0 <= px.gy < y1


def face_local(px, rect):
    """(fx, fy) inside a canvas rect (glow painters see the CUBE face's fx/fy, which for
    shared rects is identical, but region math is clearer off global coords)."""
    return px.gx - rect[0], px.gy - rect[1]


def glyph_at(fx, fy):
    """Eclipse sigil mask on a 19x62 leaf face: annulus + inner mote up top, a tick
    ladder with two crossbars down the middle, a closing diamond low. 0 = none,
    1 = stroke, 2 = ring."""
    d_ring = math.hypot((fx - 9) / 5.2, (fy - 17) / 5.2)
    if abs(d_ring - 1.0) < 0.16:
        return 2
    if math.hypot(fx - 9, fy - 17) < 1.3:
        return 1  # inner mote (the eclipsed sun)
    if fx == 9 and 27 <= fy <= 50 and fy % 4 != 3:
        return 1  # tick ladder
    if fy in (31, 41) and 6 <= fx <= 12:
        return 1  # crossbars
    if abs(fx - 9) + abs(fy - 55) <= 2:
        return 1  # closing diamond
    return 0


def plank(px, base):
    """Vertical blackened strakes: 5px boards, dark seams, long grain runs, rare pores."""
    if px.fx % 5 == 4:
        return mul(base, 0.55)  # board seam
    g = px.noise(11, y=px.gy // 4)
    col = mul(base, 0.82) if g < 0.33 else (base if g < 0.72 else mul(base, 1.14))
    if px.noise(16) > 0.97:
        col = mul(SILVER, 0.9)  # old nail head
    elif px.noise(5) > 0.965:
        col = mul(col, 0.6)  # pore
    return col


def edge_bleed(fx, fy, fw, fh):
    """0..1 strength of void light leaking around a leaf border (sides + bottom, faint top)."""
    du = min(fx, fw - 1 - fx)
    dv_bottom = fh - 1 - fy
    t = 0.0
    if du <= 2:
        t = max(t, (2.5 - du) / 2.5)
    if dv_bottom <= 2:
        t = max(t, (2.5 - dv_bottom) / 2.5 * 0.9)
    if fy <= 1:
        t = max(t, (1.5 - fy) / 1.5 * 0.5)
    return t


def leaf_material(px):
    """Leaf PANEL faces (bands/handles are cube-overridden): glyph-carved front planks
    with purple edge bleed; back faces bathed in the void's wash."""
    for rect in LEAF_FRONT_RECTS:
        if in_rect(px, rect):
            fx, fy = face_local(px, rect)
            g = glyph_at(fx, fy)
            if g == 2:
                return mix(SILVER, PURPLE, 0.45)  # inlaid ring
            if g == 1:
                return mix(mul(OAK_DEEP, 0.8), PURPLE_DEEP, 0.55)  # carved stroke
            col = plank(px, OAK)
            return mix(col, PURPLE_DEEP, 0.35 * edge_bleed(fx, fy, 19, 62))
    for rect in LEAF_BACK_RECTS:
        if in_rect(px, rect):
            fx, fy = face_local(px, rect)
            col = mix(plank(px, OAK_DEEP), PURPLE_DEEP, 0.18)
            return mix(col, PURPLE, 0.4 * edge_bleed(fx, fy, 19, 62))
    return plank(px, OAK_DEEP)  # panel edge strips + top/bottom


def leaf_glow(px):
    """Leaf glowmask: glyph strokes + border bleed on the fronts, a broad wash on the
    backs, a glint on the ring handles — #B98CFF blaze per §2.5."""
    for rect in LEAF_FRONT_RECTS:
        if in_rect(px, rect):
            fx, fy = face_local(px, rect)
            g = glyph_at(fx, fy)
            if g == 2:
                return with_alpha(PURPLE, 210)
            if g == 1:
                return with_alpha(mix(PURPLE, PURPLE_CORE, 0.3), 160)
            t = edge_bleed(fx, fy, 19, 62)
            return with_alpha(PURPLE, int(190 * t)) if t > 0.05 else None
    for rect in LEAF_BACK_RECTS:
        if in_rect(px, rect):
            fx, fy = face_local(px, rect)
            t = max(0.3, edge_bleed(fx, fy, 19, 62))
            return with_alpha(mix(PURPLE, PURPLE_DEEP, 0.4), int(150 * t))
    if in_rect(px, HANDLE_FRONT_RECT):
        fx, fy = face_local(px, HANDLE_FRONT_RECT)
        if fy >= 4 and _ring_dist(fx, fy) < 0.3:
            return with_alpha(PURPLE, 110)  # void light licking the ring's lower arc
    return None


def _ring_dist(fx, fy):
    """|distance - 1| to the handle ring's centerline on the 6x8 handle face."""
    return abs(math.hypot((fx - 2.5) / 2.2, (fy - 4.5) / 2.6) - 1.0)


def handle_material(px):
    """Oversized ring handle: 2px mount plate up top, hanging annulus below (alpha
    cutout inside/outside the ring)."""
    if px.face in ("north", "south"):
        fx, fy = px.fx, px.fy
        if fy <= 1:
            return metal(SILVER)(px)  # mount plate
        if _ring_dist(fx, fy) < 0.34:
            col = metal(SILVER)(px)
            return mix(col, PURPLE, 0.25) if fy >= 5 else col
        return None  # cutout: see through the ring
    return metal(SILVER_DARK)(px)  # rim faces


def lintel_material(px):
    """Arched header: silver arch line over a recessed tympanum (the glow disc plate
    hangs in front of its center), plank voussoirs above."""
    if px.face == "north":
        u, v = px.fx, px.fy
        arch = 15.0 - 11.0 * math.sqrt(max(0.0, 1.0 - ((u - 19.0) / 18.5) ** 2))
        if abs(v - arch) < 0.75:
            return mix(SILVER, PURPLE, 0.3)  # the arch line itself
        if v > arch:
            return mix(mul(OAK_DEEP, 0.72), PURPLE_DEEP, 0.25)  # recessed tympanum
        seam = (u + int(v)) % 6 == 0  # radial voussoir seams
        return mul(OAK, 0.6) if seam else plank(px, OAK)
    return plank(px, OAK)


def void_material(px):
    """The void beyond the door: radial purple blaze fading to near-black, cloud noise
    swirl. Shadeless — this IS the light source (auto-copied to the glowmask)."""
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = math.hypot((px.fx - cx) / max(cx, 0.5), (px.fy - cy) / max(cy, 0.5))
    t = max(0.0, min(1.0, d * 0.92 + (px.noise(41) - 0.5) * 0.3))
    if t < 0.18:
        return mix(PURPLE_CORE, PURPLE, t / 0.18)
    if t < 0.55:
        return mix(PURPLE, VOID_MID, (t - 0.18) / 0.37)
    return mix(VOID_MID, VOID_EDGE, (t - 0.55) / 0.45)


void_material.shadeless = True


def disc_material(px):
    """The eclipse disc on the header: near-black core ringed by a blazing corona,
    alpha-cut outside. Shadeless (glow bone)."""
    d = math.hypot((px.fx - 6.5) / 6.4, (px.fy - 4.5) / 4.4)
    if d > 1.0:
        return None
    if d > 0.62:
        flare = 0.15 * (px.noise(47) - 0.5)
        return mix(PURPLE_CORE, PURPLE, min(1.0, (d - 0.62) / 0.38 + flare))
    mottle = px.noise(53)
    return mix(DISC_CORE, hexc("#1A0E24"), 0.5 * mottle)


disc_material.shadeless = True


def main():
    painter = GeoPainter(GEO, seed=SEED)
    # frame cube order in the geo: 0/1 jambs, 2 lintel, 3 sill.
    painter.set_material("frame", wood(OAK))
    painter.set_cube_material("frame", 2, lintel_material)
    painter.set_cube_material("frame", 3, wood(OAK_DEEP))
    # leaves: cube 0 panel, 1/2 silver bands, 3 ring handle.
    for leaf in ("leaf_px", "leaf_nx"):
        painter.set_material(leaf, leaf_material)
        painter.set_cube_material(leaf, 1, metal(SILVER_DARK))
        painter.set_cube_material(leaf, 2, metal(SILVER_DARK))
        painter.set_cube_material(leaf, 3, handle_material)
    painter.set_material("glow_void", void_material)
    painter.set_material("glow_disc", disc_material)
    # glow_* bones auto-copy their (shadeless) albedo into the glowmask; the leaves get
    # the custom seam/glyph blaze instead of an albedo copy.
    painter.set_glow_painter("leaf_*", leaf_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
