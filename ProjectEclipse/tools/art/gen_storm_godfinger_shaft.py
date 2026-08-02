#!/usr/bin/env python3
"""Generate the dedicated soft god-finger shaft sprite (F-107 emitter audit).

Produces ``assets/eclipse/textures/particle/storm_godfinger_shaft.png``
(64x256) for ``eclipse:storm_godfinger`` — the pale sick-green light shafts
falling through a sphere-storm's apex eye (``StormInteriorFx.tickGodFingers``).

Replaces the 8x8 ``purple_wisp.png``: at the emitter's 6-14 block quad edges
every wisp texel rendered as a hard uniform rectangle under Veil's
nearest-neighbor quasar sampling (blur=false), and the wisp's non-zero border
alpha (26/255) drew the quad edge itself — the F-107 "hard purple wall"
anatomy, in green.

Style contract inherited from the F-107 part-3 shaft (see
``F107_UMBRAL_QUAD_REPORT.md`` §4.3, generator since removed in part 4) and
``gen_limbo_fog_soft.py``:

* Horizontal power-law falloff ``(1 - |nx|)^1.5`` — lands on alpha 0 WITH
  zero slope at the quad edge, so the llvmpipe/8-bit additive visibility
  threshold never cuts a straight iso-alpha contour ("pill rim").
* Vertical smoothstep fade over the outer 34% at both ends (kills the
  "waist" step where two shaft quads overlap and the round end caps).
* Deterministic +-3 alpha-step dither (integer (x,y) hash, no randomness),
  applied only above h=0.02 — breaks the remaining quantization contour into
  fine grain instead of a line. Border texels stay exactly 0.
* PRE-DARKENED green family baked into RGB (core below half luminance); the
  JSON tint (#D9FFE8 -> #6FA98C) multiplies on top, so llvmpipe and real
  GPUs agree and the shaft can never wash pale.
* Peak texture alpha 0.55 — with the JSON tint alpha peak 0.1 a single
  shaft core sits around 2% luminance: a quiet schimmer, not a pill.
* Long-wave brightness variation along the shaft so it does not read as a
  uniform capsule.

Deterministic: re-running reproduces the PNG byte-identically for a given
Pillow version.

Usage (from the repo root):
    python3 tools/art/gen_storm_godfinger_shaft.py
"""

import math
from pathlib import Path

from PIL import Image

PARTICLE_DIR = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/particle"
)
DST = PARTICLE_DIR / "storm_godfinger_shaft.png"

SIZE = (64, 256)

# Pre-darkened sick-green ramp (sRGB 0-255), both ends BELOW half luminance —
# the C8 sphere-interior palette family (SPH_FOG/SPH_FLASH greens).
CORE_RGB = (108, 158, 128)
FRINGE_RGB = (58, 96, 76)

# Horizontal power-law exponent (zero-slope foot at |nx| = 1).
FALLOFF_POWER = 1.5
# Vertical fade fraction at each end (part-3 V_FADE value that killed the
# waist step of overlapping shaft quads).
V_FADE = 0.34
# Peak alpha (0-1) at the shaft core.
PEAK_ALPHA = 0.55
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
        # Vertical fade: 1 in the middle band, easing to exactly 0 at both
        # row ends (|ny| = 1 -> smoothstep arg 0).
        fv = smoothstep(0.0, V_FADE, 1.0 - abs(ny))
        for x in range(width):
            nx = (x / (width - 1)) * 2.0 - 1.0
            # Power-law horizontal falloff: 0 with zero slope at |nx| = 1.
            fh = (1.0 - abs(nx)) ** FALLOFF_POWER
            # Long-wave variation along the shaft (never a uniform capsule);
            # core-gated so the bright spine stays clean.
            wave = 1.0 - 0.07 * (0.5 + 0.5 * math.sin(ny * math.pi * 1.3 + 0.6)) \
                * smoothstep(0.1, 0.5, abs(nx))
            h = fh * fv * wave
            a = PEAK_ALPHA * h
            a255 = int(round(a * 255.0))
            # Deterministic dither above the gate; border texels stay 0
            # (h is exactly 0 there by construction, gate keeps it so).
            if h > DITHER_GATE:
                a255 = max(1, min(255, a255 + dither(x, y)))
            px[x, y] = shade(h, a255)
    return img


def main() -> None:
    build().save(DST, optimize=True)
    print(f"wrote {DST} ({SIZE[0]}x{SIZE[1]})")


if __name__ == "__main__":
    main()
