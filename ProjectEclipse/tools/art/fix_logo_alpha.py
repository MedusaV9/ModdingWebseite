#!/usr/bin/env python3
"""Re-export the title logo with true 8-bit alpha (PLAN-A wave 5, package A3).

The shipped ``assets/eclipse/textures/gui/title/logo.png`` had a *binary* alpha
channel: an opaque white 240x160 box behind the "PROJECT: ECLIPSE" glyph. This
script keeps the glyph and unmixes the white matte:

1. Whiteness key: distance-from-white ``d = max(255-R, 255-G, 255-B)`` maps to
   alpha through a smoothstep ramp (LO..HI), so antialiased glyph borders that
   were blended against white become feathered partial alpha instead of a hard
   cutout. Enclosed white counters (inside P/R/O) key out the same way.
2. Un-premultiply: partially transparent pixels have the white contribution
   removed (``F = (C - (1-a)*255) / a``) so the recovered fringe keeps the
   glyph's own color instead of a bright white halo.
3. The original fully transparent border is preserved (alpha = min(orig, key)).
4. Despeckle: faint alpha islands (paper-grain noise baked into the old white
   box) that sit nowhere near a strong glyph pixel are dropped entirely;
   feathered borders survive because they always touch strong pixels.

Usage: python3 tools/art/fix_logo_alpha.py [src] [dst]
Defaults to rewriting the shipped texture in place. Requires Pillow + numpy.
Idempotent: on an already-keyed logo the white box is gone, alpha only shrinks.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

DEFAULT = Path(__file__).resolve().parents[2] / (
    "src/main/resources/assets/eclipse/textures/gui/title/logo.png")
KEY_LO = 10.0   # d below this = pure background (alpha 0)
KEY_HI = 48.0   # d above this = pure glyph (alpha 255); ramp between
SPECK_MAX_ALPHA = 90.0   # despeckle: only pixels fainter than this can be dropped
STRONG_ALPHA = 120.0     # ...and only when no pixel this strong is within 2 px


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src
    img = np.array(Image.open(src).convert("RGBA")).astype(np.float64)
    rgb, orig_a = img[..., :3], img[..., 3]

    d = 255.0 - rgb.min(axis=-1)
    t = np.clip((d - KEY_LO) / (KEY_HI - KEY_LO), 0.0, 1.0)
    key_a = (t * t * (3.0 - 2.0 * t)) * 255.0
    alpha = np.minimum(orig_a, key_a)

    strong = Image.fromarray(((alpha >= STRONG_ALPHA) * 255).astype(np.uint8))
    near_strong = np.array(strong.filter(ImageFilter.MaxFilter(5))) > 0
    alpha = np.where((alpha < SPECK_MAX_ALPHA) & ~near_strong, 0.0, alpha)

    a = alpha / 255.0
    unmixed = np.where(
        (a > 0.0)[..., None] & (a < 1.0)[..., None],
        (rgb - (1.0 - a[..., None]) * 255.0) / np.maximum(a[..., None], 1e-6),
        rgb)
    out = np.dstack([np.clip(unmixed, 0.0, 255.0), alpha]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(dst, optimize=True)

    hist = np.bincount(out[..., 3].reshape(-1), minlength=256)
    print(f"wrote {dst} ({dst.stat().st_size / 1024:.0f} KiB); alpha: "
          f"{hist[0]} transparent, {hist[255]} opaque, "
          f"{int(hist[1:255].sum())} feathered px")


if __name__ == "__main__":
    main()
