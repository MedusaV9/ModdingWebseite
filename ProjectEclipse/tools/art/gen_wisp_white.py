#!/usr/bin/env python3
"""Generate the white/grayscale wisp particle sprite (EVAL-POL-F #2).

The shipped ``purple_wisp.png`` is lavender (mean RGB ~211/150/255, G ~= 0.61*B).
Quasar color-module gradients MULTIPLY against the sprite, so every recolored
wand family converged back toward violet: GLUT's fire-oranges rendered
salmon/brick and STERN's golds rendered pink. This script derives
``wisp_white.png`` from the shipped sprite: identical alpha falloff, hue
removed (per-pixel mean), normalized so the brightest core pixel stays at 255
— gradients then render hue-true at full punch. RISS keeps the lavender
original on purpose (violet IS its identity).

Usage (from the repo root):
    python3 tools/art/gen_wisp_white.py
"""

from pathlib import Path

from PIL import Image

PARTICLE_DIR = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/particle"
)
SRC = PARTICLE_DIR / "purple_wisp.png"
DST = PARTICLE_DIR / "wisp_white.png"


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    width, height = src.size

    # Per-pixel mean removes the hue but keeps the subtle radial value ramp
    # (edge ~194 -> core ~225 in the shipped sprite).
    grays = {}
    peak = 0
    for y in range(height):
        for x in range(width):
            r, g, b, a = src.getpixel((x, y))
            if a == 0:
                continue
            gray = (r + g + b) / 3.0
            grays[(x, y)] = gray
            peak = max(peak, gray)

    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    scale = 255.0 / peak if peak > 0 else 1.0
    for (x, y), gray in grays.items():
        v = min(255, round(gray * scale))
        a = src.getpixel((x, y))[3]
        out.putpixel((x, y), (v, v, v, a))

    out.save(DST)
    print(f"wrote {DST} ({width}x{height}, peak gray {peak:.1f} -> 255)")


if __name__ == "__main__":
    main()
