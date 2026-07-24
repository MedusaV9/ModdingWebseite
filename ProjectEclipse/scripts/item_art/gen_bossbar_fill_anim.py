#!/usr/bin/env python3
"""Generates textures/gui/bossbar/fill_anim.png — 512x128, four stacked 512x32
frames of slowly drifting purple energy for the v3 bossbar animated fill.
Deterministic; rerun-safe."""
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "src/main/resources/assets/eclipse/textures/gui/bossbar/fill_anim.png"

W, FRAME_H, FRAMES = 512, 32, 4

BASE = (46, 35, 71)       # deep violet
MID = (123, 79, 208)      # accent purple
HI = (185, 140, 255)      # light accent
GLOW = (237, 231, 248)    # near-white highlight


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main() -> None:
    img = Image.new("RGBA", (W, FRAME_H * FRAMES))
    px = img.load()
    for frame in range(FRAMES):
        phase = frame / FRAMES * math.tau
        for x in range(W):
            fx = x / W * math.tau
            # Two drifting sine bands + a fine ripple make a flowing energy read.
            band = 0.5 + 0.5 * math.sin(fx * 3.0 + phase)
            band2 = 0.5 + 0.5 * math.sin(fx * 7.0 - phase * 2.0 + 1.7)
            ripple = 0.5 + 0.5 * math.sin(fx * 23.0 + phase * 3.0)
            for y in range(FRAME_H):
                fy = y / (FRAME_H - 1)
                # Vertical shading: darker edges, bright core line.
                core = 1.0 - abs(fy - 0.5) * 2.0
                energy = 0.45 * band + 0.35 * band2 + 0.20 * ripple
                t = max(0.0, min(1.0, energy * (0.35 + 0.65 * core)))
                if t > 0.82:
                    color = lerp(HI, GLOW, (t - 0.82) / 0.18)
                elif t > 0.45:
                    color = lerp(MID, HI, (t - 0.45) / 0.37)
                else:
                    color = lerp(BASE, MID, t / 0.45)
                px[x, frame * FRAME_H + y] = (*color, 255)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"wrote {OUT} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    main()
