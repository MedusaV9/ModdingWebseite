#!/usr/bin/env python3
"""Shared painter for the VANILLA-model bosses (MOB-BOSS1) — Ferryman + Herald.

These two bosses are `HierarchicalModel`s authored in Java (`client/entity/
FerrymanModel` / `HeraldModel`), not GeckoLib, so `geckolib_gen/paint_lib.py` (which is
driven by a `.geo.json`) cannot paint them. This module ports the same conventions —
vanilla box-UV face rects, per-face directional shading, 1px inner outlines, hash
dithering, shadeless emissive regions — onto a hand-declared cube list that MUST stay in
sync with the Java `createBodyLayer()` (the UV tables live in `docs/uv/ferryman.md` /
`docs/uv/herald.md`).

Sheets are painted at SCALE=2 (256x256 png over the frozen 128x128 UV space): vanilla
normalizes cube UVs by the LayerDefinition texture size, so a 2x sheet simply gives every
texel a 2x2 pixel budget — no Java-side UV change needed. Deterministic seed ->
byte-identical output on every run.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ENT = ROOT / "src/main/resources/assets/eclipse/textures/entity"

UV_SPACE = 128   # frozen LayerDefinition texture size (do not change)
SCALE = 2        # painted pixels per UV texel -> 256x256 png

# Same directional light as paint_lib / EntitySkinArtist: top lit, bottom shadowed.
FACE_SHADE = {"up": 1.18, "down": 0.62, "north": 1.0, "east": 0.86, "west": 0.86, "south": 0.74}
OUTLINE = 0.76  # 1px (image px) inner border multiplier — faces bigger than 4x4 img px only


def hexc(spec, alpha=255):
    spec = spec.lstrip("#")
    return (int(spec[0:2], 16), int(spec[2:4], 16), int(spec[4:6], 16), alpha)


def mul(color, factor):
    r, g, b, a = color
    return (max(0, min(255, int(r * factor))),
            max(0, min(255, int(g * factor))),
            max(0, min(255, int(b * factor))), a)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


def face_rects(u, v, w, h, d):
    """Vanilla box-UV face rects (texel space), matching the docs/uv tables."""
    return {
        "up":    (u + d, v, u + d + w, v + d),
        "down":  (u + d + w, v, u + d + 2 * w, v + d),
        "east":  (u, v + d, u + d, v + d + h),
        "north": (u + d, v + d, u + d + w, v + d + h),
        "west":  (u + d + w, v + d, u + d + w + d, v + d + h),
        "south": (u + d + w + d, v + d, u + 2 * d + 2 * w, v + d + h),
    }


class Sheet:
    """One 256x256 RGBA sheet with the shared paint conventions."""

    def __init__(self, seed):
        self.size = UV_SPACE * SCALE
        self.img = Image.new("RGBA", (self.size, self.size), (0, 0, 0, 0))
        self.px = self.img.load()
        self.seed = seed

    def hash01(self, x, y, salt=0):
        """Deterministic per-pixel hash in [0,1) (dither/noise)."""
        n = (x * 374761393 + y * 668265263 + salt * 2246822519 + self.seed) & 0xFFFFFFFF
        n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65536.0

    def paint_box(self, u, v, w, h, d, painter, shadeless=False, faces=None):
        """Paints every face of a box-UV cube. `painter(face, fx, fy, fw, fh)` runs in
        face-local IMAGE pixels and returns RGBA or None (transparent). Directional
        shading + inner outline are applied unless `shadeless` (emissive regions)."""
        for face, (x0, y0, x1, y1) in face_rects(u, v, w, h, d).items():
            if faces is not None and face not in faces:
                continue
            fw, fh = (x1 - x0) * SCALE, (y1 - y0) * SCALE
            for fy in range(fh):
                for fx in range(fw):
                    color = painter(face, fx, fy, fw, fh)
                    if color is None:
                        continue
                    if not shadeless:
                        color = mul(color, FACE_SHADE[face])
                        if fw > 4 and fh > 4 and (fx == 0 or fy == 0 or fx == fw - 1 or fy == fh - 1):
                            color = mul(color, OUTLINE)
                        # +-1 LSB-ish hash dither so flat fields never band.
                        dither = 0.96 + 0.08 * self.hash01(x0 * SCALE + fx, y0 * SCALE + fy, 7)
                        color = mul(color, dither)
                    self.px[x0 * SCALE + fx, y0 * SCALE + fy] = color

    def save(self, name):
        out = ENT / name
        self.img.save(out)
        return out


def flat(color):
    return lambda face, fx, fy, fw, fh: color


def vgrad(top, bottom):
    """Vertical gradient painter top->bottom."""
    return lambda face, fx, fy, fw, fh: mix(top, bottom, fy / max(1, fh - 1))
