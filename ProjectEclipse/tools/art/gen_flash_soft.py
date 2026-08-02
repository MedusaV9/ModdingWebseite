#!/usr/bin/env python3
"""Generate the shared soft light-flash sprite (F-107 emitter audit).

Produces ``assets/eclipse/textures/particle/flash_soft.png`` (128x128) for
the two one-shot ADDITIVE light-flash emitters that stretched the 8x8 house
wisps onto >= 3 block quad radii:

* ``eclipse:impact_light`` — the D12 combat/lightning/wand-restore
  micro-flash (``veil:size`` ramp, formerly 1.2 -> 4.6 blocks radius).
* ``eclipse:wand_soulbind_flash`` — the D11 soulbind ceremony white flash
  (formerly 3.2-3.8 blocks radius).

At those sizes the 8x8 wisp's texels rendered as hard uniform rectangles
under Veil's nearest-neighbor quasar sampling, the transparent corners read
as a PLUS/CROSS and the non-zero border alpha (26/255) drew the quad edge —
the F-107 problem-class anatomy on the brightest quads in the game (alpha
peaks 0.95/1.0, additive).

Style contract inherited from ``gen_limbo_fog_soft.py`` (F-107 part 2):

* Radial bell falloff ``(1 - r^2)^2`` — zero slope at BOTH the core (no
  pinpoint) and the rim (lands on alpha 0 with zero slope, so the llvmpipe
  8-bit additive visibility threshold never cuts a hard iso-alpha rim).
* Border texels exactly 0.
* Deterministic +-3 alpha-step dither (integer (x,y) hash) above h=0.02 —
  breaks the additive quantization contour into grain.
* Near-white core with a cool violet fringe baked in; the JSON tints
  (#FFFFFF -> violet families) multiply on top. Deliberately brighter than
  the fog/dust sprites: a flash is transient (<= 0.5 s) and additive punch
  is its identity — the F-107 risk is the CONTOUR, not the brightness.
* Peak texture alpha 0.60.

Deterministic: re-running reproduces the PNG byte-identically for a given
Pillow version.

Usage (from the repo root):
    python3 tools/art/gen_flash_soft.py
"""

import math
from pathlib import Path

from PIL import Image

PARTICLE_DIR = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/particle"
)
DST = PARTICLE_DIR / "flash_soft.png"

SIZE = (128, 128)

# Near-white core, cool violet fringe (fringe below half luminance).
CORE_RGB = (238, 232, 250)
FRINGE_RGB = (120, 108, 152)

# Peak alpha (0-1) at the flash core.
PEAK_ALPHA = 0.60
# Dither amplitude in 8-bit alpha steps, gated above this falloff height.
DITHER_STEPS = 3
DITHER_GATE = 0.02


def dither(x: int, y: int) -> int:
    """Deterministic integer hash -> [-DITHER_STEPS, +DITHER_STEPS]."""
    h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h ^= h >> 16
    return (h % (2 * DITHER_STEPS + 1)) - DITHER_STEPS


def shade(h: float, alpha_255: int) -> tuple[int, int, int, int]:
    r = FRINGE_RGB[0] + (CORE_RGB[0] - FRINGE_RGB[0]) * h
    g = FRINGE_RGB[1] + (CORE_RGB[1] - FRINGE_RGB[1]) * h
    b = FRINGE_RGB[2] + (CORE_RGB[2] - FRINGE_RGB[2]) * h
    return (int(round(r)), int(round(g)), int(round(b)), alpha_255)


def build() -> Image.Image:
    width, height = SIZE
    img = Image.new("RGBA", (width, height))
    px = img.load()
    for y in range(height):
        ny = (y / (height - 1)) * 2.0 - 1.0
        for x in range(width):
            nx = (x / (width - 1)) * 2.0 - 1.0
            r2 = nx * nx + ny * ny
            # Bell falloff: zero slope at r=0 AND at r=1; exactly 0 for
            # r >= 1, which includes every border texel.
            h = (1.0 - r2) ** 2 if r2 < 1.0 else 0.0
            a255 = int(round(PEAK_ALPHA * h * 255.0))
            if h > DITHER_GATE:
                a255 = max(1, min(255, a255 + dither(x, y)))
            px[x, y] = shade(h, a255)
    return img


def main() -> None:
    build().save(DST, optimize=True)
    print(f"wrote {DST} ({SIZE[0]}x{SIZE[1]})")


if __name__ == "__main__":
    main()
