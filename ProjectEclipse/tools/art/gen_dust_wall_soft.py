#!/usr/bin/env python3
"""Generate the dedicated soft dust-curtain sprite (F-107 emitter audit).

Produces ``assets/eclipse/textures/particle/dust_wall_soft.png`` (128x128)
for ``eclipse:growth_dust_wall`` — the expansion-wave dust curtain
(``ExpansionSequence``, ``EndShatterSequence``, the ``rim_recede`` cue).

Replaces the 8x8 ``purple_wisp.png`` on this emitter only: growth_dust_wall
stretches its sprite onto 0.6-8.2 block quad edges (base 2.2 +- 1.9) and the
curtain spawns ON the player's feet when the wave front crosses them — at
those sizes every wisp texel is a hard uniform rectangle under Veil's
nearest-neighbor quasar sampling, the wisp's transparent corners read as a
PLUS/CROSS silhouette and its non-zero border alpha (26/255) draws the quad
edge itself (the F-107 "hard purple wall" anatomy; this emitter was flagged
by the class audit, quad >= 4 on a <= 16 px texture).

Style contract inherited from ``gen_limbo_fog_soft.py`` (F-107 part 2):

* Gaussian falloff with a smoothstep edge kill forced to exactly 0 on every
  border texel — the quad border can never draw a visible sheet edge.
* Two-band angular waviness (5-lobe + 3-lobe, radius-gated) so a dust puff
  never reads as a perfect ball — it is debris haze, not a bokeh disc.
* Deterministic +-3 alpha-step dither (integer (x,y) hash, no randomness)
  above h=0.02: the emitter is NON-additive, but llvmpipe still bands large
  smooth alpha gradients — the grain breaks the contour.
* PRE-DARKENED violet-grey baked into RGB (both ends below half luminance);
  the JSON tint (#9D86C9 -> #241C38) multiplies on top.
* Peak texture alpha 0.66, below the old wisp core (189/255): with the JSON
  alpha peak 0.38 one puff tops out around 0.25 opacity and falls off
  radially instead of plateauing.

Deterministic: re-running reproduces the PNG byte-identically for a given
Pillow version.

Usage (from the repo root):
    python3 tools/art/gen_dust_wall_soft.py
"""

import math
from pathlib import Path

from PIL import Image

PARTICLE_DIR = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/particle"
)
DST = PARTICLE_DIR / "dust_wall_soft.png"

SIZE = (128, 128)

# Pre-darkened violet-grey ramp (sRGB 0-255), both ends below half luminance.
CORE_RGB = (132, 118, 160)
FRINGE_RGB = (82, 72, 105)

# Gaussian sigma in normalized radius units.
SIGMA = 0.46
# Peak alpha (0-1) at the puff core.
PEAK_ALPHA = 0.66
# Dither amplitude in 8-bit alpha steps, gated above this falloff height.
DITHER_STEPS = 3
DITHER_GATE = 0.02


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


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
            r = math.hypot(nx, ny)
            h = math.exp(-((r / SIGMA) ** 2))
            # Force exact zero on every border texel (r >= 1 there).
            h *= smoothstep(0.0, 0.15, 1.0 - r)
            # Irregular dust silhouette: 5-lobe + 3-lobe waviness, gated so
            # the core stays clean (stronger than the fog puff's 3-lobe —
            # this is debris haze, not a soft bokeh ball).
            theta = math.atan2(ny, nx)
            wave = 1.0 \
                - 0.12 * (0.5 + 0.5 * math.sin(5.0 * theta + 0.9)) \
                * smoothstep(0.15, 0.6, r) \
                - 0.07 * (0.5 + 0.5 * math.sin(3.0 * theta + 2.3)) \
                * smoothstep(0.25, 0.7, r)
            hh = h * wave
            a255 = int(round(PEAK_ALPHA * hh * 255.0))
            if hh > DITHER_GATE:
                a255 = max(1, min(255, a255 + dither(x, y)))
            px[x, y] = shade(hh, a255)
    return img


def main() -> None:
    build().save(DST, optimize=True)
    print(f"wrote {DST} ({SIZE[0]}x{SIZE[1]})")


if __name__ == "__main__":
    main()
