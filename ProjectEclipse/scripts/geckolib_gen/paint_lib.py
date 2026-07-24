#!/usr/bin/env python3
"""Shared GeckoLib texture painter (P6-W1) — python/Pillow port of the technique in
`scripts/placeholder_gen/EntitySkinArtist.java` (hash-dithered materials, per-face
directional shading, 1px inner outlines, unshaded emissive regions), driven by the
`.geo.json` itself instead of a hand-written UV doc: the painter parses the geometry,
computes every cube's box-UV (or per-face) rects via `validate_geo.box_uv_rects`, and
paints them through material callbacks.

Per-mob driver scripts live in `scripts/geckolib_gen/mobs/<id>.py` and declare the
palette + per-bone materials + emissive regions; running one writes BOTH
`<id>.png` and `<id>_glowmask.png` (same canvas — GeckoLib's `AutoGlowingTexture`
enforces matching dimensions). Deterministic seed -> byte-identical output on every run,
so final AI art can replace the PNGs at identical paths/sizes later.

Usage inside a driver (run from the ProjectEclipse root):

    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from paint_lib import GeoPainter, hexc, metal, glass, flame, kelp

    p = GeoPainter("src/main/resources/assets/eclipse/geo/entity/foo.geo.json", seed=0x123)
    p.set_material("body", metal(hexc("#3B3F46")))          # exact bone name
    p.set_material("tendril_*", kelp(hexc("#2E4A44")))      # fnmatch pattern
    p.set_cube_material("body", 0, glass(hexc("#9FB8C4", 102)))  # per-cube override
    p.set_glow("glow_*")                                     # full-bright glowmask copy
    p.set_glow_painter("cage", my_rim_fn)                    # custom glowmask pixels
    p.paint("src/main/resources/assets/eclipse/textures/entity/foo.png")

Material callbacks receive a `Px` context and return an RGBA tuple or None
(transparent). Factories below set `.shadeless = True` on emissive materials so the
painter skips directional shading/outline for them (they must stay at full painted
brightness — same rule as EntitySkinArtist).
"""

from __future__ import annotations

import math
import sys
from dataclasses import dataclass
from fnmatch import fnmatch
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_geo import cube_face_rects, load_geo  # noqa: E402

DEFAULT_SEED = 0x0EC11B5E  # EntitySkinArtist's fixed dither seed
# Directional light (EntitySkinArtist.dirShade): top lit, bottom shadowed, sides mid.
FACE_SHADE = {"up": 1.18, "down": 0.62, "north": 1.0, "east": 0.86, "west": 0.86, "south": 0.74}
OUTLINE = 0.76  # 1px inner border multiplier (faces > 2x2 only)


# ---------------------------------------------------------------------------
# color helpers
# ---------------------------------------------------------------------------

def hexc(spec, alpha=255):
    """`"#RRGGBB"` -> (r, g, b, alpha)."""
    spec = spec.lstrip("#")
    return (int(spec[0:2], 16), int(spec[2:4], 16), int(spec[4:6], 16), alpha)


def mul(color, factor):
    """Scales RGB by `factor`, clamped; alpha unchanged."""
    r, g, b, a = color
    return (max(0, min(255, int(r * factor))),
            max(0, min(255, int(g * factor))),
            max(0, min(255, int(b * factor))), a)


def mix(a, b, t):
    """Linear RGBA blend a->b by t in [0, 1]."""
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


def with_alpha(color, alpha):
    return (color[0], color[1], color[2], alpha)


# ---------------------------------------------------------------------------
# deterministic noise (port of EntitySkinArtist.hash/noise)
# ---------------------------------------------------------------------------

def _hash(seed, x, y, salt):
    h = (seed ^ (x * 0x27D4EB2D) ^ (y * 0x9E3779B9) ^ (salt * 0x85EBCA6B)) & 0xFFFFFFFF
    h ^= h >> 15
    h = (h * 0x2C1B3C6D) & 0xFFFFFFFF
    h ^= h >> 12
    h = (h * 0x297A2D39) & 0xFFFFFFFF
    h ^= h >> 15
    return h


@dataclass
class Px:
    """Per-pixel material context: face name, face-local (fx, fy) in a (fw, fh) rect,
    global canvas (gx, gy), and deterministic `noise(salt)` in [0, 1) keyed off the
    GLOBAL pixel so patterns stay stable when rects move."""
    face: str
    fx: int
    fy: int
    fw: int
    fh: int
    gx: int
    gy: int
    seed: int

    def noise(self, salt=0, x=None, y=None):
        return (_hash(self.seed, self.gx if x is None else x,
                      self.gy if y is None else y, salt) >> 8) / float(1 << 24)


# ---------------------------------------------------------------------------
# material factories (all deterministic; return RGBA or None per pixel)
# ---------------------------------------------------------------------------

def flat(base):
    """Uniform color (programmer-art baseline)."""
    return lambda px: base


def weave(base, direction=0, amp=0.34, salt=7):
    """Cloth/fur dither. direction 0 = fine grain, 1 = vertical streaks, 2 = horizontal."""
    def fn(px):
        if direction == 1:
            streak = px.noise(salt, y=px.gy // 3)
        elif direction == 2:
            streak = px.noise(salt, x=px.gx // 3)
        else:
            streak = px.noise(salt)
        fine = px.noise(salt + 101)
        v = 0.72 * streak + 0.28 * fine - 0.5
        return mul(base, 1.0 + v * amp)
    return fn


def wood(base, salt=11):
    """Vertical wood grain: long tonal runs plus rare dark pores."""
    def fn(px):
        g = px.noise(salt, y=px.gy // 4)
        col = mul(base, 0.82) if g < 0.33 else (base if g < 0.72 else mul(base, 1.16))
        if px.noise(salt + 5) > 0.96:
            col = mul(col, 0.6)
        return col
    return fn


def metal(base, salt=13):
    """Brushed iron: faint horizontal banding, sparse bright specks, darker seams."""
    def fn(px):
        band = px.noise(salt, x=px.gx // 2)
        col = mul(base, 0.9 + band * 0.2)
        if px.noise(salt + 3) > 0.965:
            col = mul(col, 1.35)  # rivet/scratch glint
        if px.noise(salt + 9) < 0.05:
            col = mul(col, 0.68)  # tarnish pit
        return col
    return fn


def glass(base, salt=17, edge_alpha_boost=70):
    """Translucent pane: base alpha everywhere, diagonal sheen streaks, and a slightly
    more opaque rim so panes read as framed. KEEP base alpha < 255 and render the mob
    with a translucent render type (`EclipseGeoRenderer.withTranslucency()`)."""
    def fn(px):
        col = base
        diag = (px.gx + px.gy) % 7
        if diag in (0, 1) and px.noise(salt) > 0.35:
            col = mul(col, 1.22)  # sheen streak
        elif px.noise(salt + 21) > 0.93:
            col = mul(col, 0.85)  # dull smudge
        on_rim = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
        if on_rim:
            col = with_alpha(mul(col, 0.92), min(255, col[3] + edge_alpha_boost))
        return col
    return fn


def flame(core, tip, salt=23):
    """Emissive flame: bright core fading to `tip` towards the rect edges, faint licks.
    Shadeless — painted at full brightness (re-rendered additively by the glow layer)."""
    def fn(px):
        cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
        d = math.hypot((px.fx - cx) / max(cx, 0.5), (px.fy - cy) / max(cy, 0.5))
        t = max(0.0, min(1.0, d * 0.85 + (px.noise(salt) - 0.5) * 0.25))
        return mix(core, tip, t)
    fn.shadeless = True
    return fn


def kelp(base, salt=29, max_cut=2):
    """Hanging kelp/chain tendril: vertical streak weave, dark nodes every few px, and a
    ragged alpha-cutout hem on the bottom rows (EntitySkinArtist raggedCuts port)."""
    def fn(px):
        if px.face in ("north", "south", "east", "west") and max_cut > 0:
            n = px.noise(salt + 55, x=px.gx, y=0)
            cut = 0 if n < 0.35 else (1 if n < 0.75 else max_cut)
            if px.fy >= px.fh - cut:
                return None  # ragged hem
        streak = px.noise(salt, y=px.gy // 3)
        col = mul(base, 0.84 + streak * 0.36)
        if (px.gy + int(px.noise(salt + 2, y=0) * 4)) % 4 == 0:
            col = mul(col, 0.7)  # chain-link / kelp node band
        return col
    return fn


# ---------------------------------------------------------------------------
# painter core
# ---------------------------------------------------------------------------

def _rect_px(rect):
    """Outward-rounded integer bounds of a float rect."""
    x0, y0, x1, y1 = rect
    return int(math.floor(x0)), int(math.floor(y0)), int(math.ceil(x1)), int(math.ceil(y1))


class GeoPainter:
    """Paints one geo model's albedo + glowmask. See module docstring for usage."""

    def __init__(self, geo_path, seed=DEFAULT_SEED):
        self.geo_path = str(geo_path)
        self.identifier, self.tex_w, self.tex_h, self.bones = load_geo(geo_path)
        self.seed = seed
        self._materials = []       # (bone_pattern, fn)
        self._cube_materials = {}  # (bone_name, cube_index) -> fn
        self._glow_bones = []      # (bone_pattern, strength)
        self._glow_painters = []   # (bone_pattern, fn)

    # -- configuration ------------------------------------------------------

    def set_material(self, bone_pattern, fn):
        """Material for every cube of bones matching `bone_pattern` (fnmatch)."""
        self._materials.append((bone_pattern, fn))
        return self

    def set_cube_material(self, bone_name, cube_index, fn):
        """Override for one cube (declaration order in the geo file)."""
        self._cube_materials[(bone_name, cube_index)] = fn
        return self

    def set_glow(self, bone_pattern, strength=1.0):
        """Copies matching bones' albedo into the glowmask at full painted brightness
        (alpha scaled by `strength`). `glow_*` bones are auto-included at 1.0 — call
        this only for extra bones or custom strengths."""
        self._glow_bones.append((bone_pattern, strength))
        return self

    def set_glow_painter(self, bone_pattern, fn):
        """Custom glowmask pixels for matching bones (e.g. a faint rim or a
        shine-through blob on a translucent shell). Runs INSTEAD of the albedo copy."""
        self._glow_painters.append((bone_pattern, fn))
        return self

    # -- painting -----------------------------------------------------------

    def _material_for(self, bone_name, cube_index):
        override = self._cube_materials.get((bone_name, cube_index))
        if override is not None:
            return override
        for pattern, fn in reversed(self._materials):  # later declarations win
            if fnmatch(bone_name, pattern):
                return fn
        return None

    def _glow_strength(self, bone_name):
        if bone_name.startswith("glow_"):
            return 1.0
        for pattern, strength in self._glow_bones:
            if fnmatch(bone_name, pattern):
                return strength
        return 0.0

    def _glow_painter_for(self, bone_name):
        for pattern, fn in self._glow_painters:
            if fnmatch(bone_name, pattern):
                return fn
        return None

    def paint(self, out_png):
        out_png = Path(out_png)
        albedo = Image.new("RGBA", (self.tex_w, self.tex_h), (0, 0, 0, 0))
        glowmask = Image.new("RGBA", (self.tex_w, self.tex_h), (0, 0, 0, 0))
        painted = missing = glow_px = 0

        for bone in self.bones:
            bone_name = bone.get("name", "?")
            glow_strength = self._glow_strength(bone_name)
            glow_fn = self._glow_painter_for(bone_name)
            for cube_index, cube in enumerate(bone.get("cubes", [])):
                fn = self._material_for(bone_name, cube_index)
                if fn is None:
                    missing += 1
                    print(f"  !! no material for bone '{bone_name}' cube[{cube_index}] — left transparent")
                    continue
                shadeless = getattr(fn, "shadeless", False)
                for face, rect in cube_face_rects(cube).items():
                    x0, y0, x1, y1 = _rect_px(rect)
                    fw, fh = x1 - x0, y1 - y0
                    for fy in range(fh):
                        for fx in range(fw):
                            gx, gy = x0 + fx, y0 + fy
                            if not (0 <= gx < self.tex_w and 0 <= gy < self.tex_h):
                                continue
                            px = Px(face, fx, fy, fw, fh, gx, gy, self.seed)
                            col = fn(px)
                            if col is not None:
                                k = 1.0 if shadeless else FACE_SHADE.get(face, 1.0)
                                if (not shadeless and fw > 2 and fh > 2
                                        and (fx == 0 or fx == fw - 1 or fy == 0 or fy == fh - 1)):
                                    k *= OUTLINE
                                albedo.putpixel((gx, gy), mul(col, k))
                                painted += 1
                                if glow_strength > 0 and glow_fn is None:
                                    glowmask.putpixel((gx, gy),
                                                      with_alpha(col, int(col[3] * glow_strength)))
                                    glow_px += 1
                            if glow_fn is not None:
                                glow = glow_fn(px)
                                if glow is not None:
                                    glowmask.putpixel((gx, gy), glow)
                                    glow_px += 1

        out_png.parent.mkdir(parents=True, exist_ok=True)
        albedo.save(out_png)
        glow_path = out_png.with_name(out_png.stem + "_glowmask.png")
        glowmask.save(glow_path)
        print(f"painted {self.identifier} ({self.tex_w}x{self.tex_h}) -> {out_png}")
        print(f"  {painted} albedo px, {glow_px} glowmask px -> {glow_path}")
        if missing:
            print(f"  !! {missing} cube(s) had NO material — fix the driver before committing")
        return albedo, glowmask
