#!/usr/bin/env python3
"""Sunmote inner-core v2 (MOB-AMBIENT) — in-place refinement of `textures/entity/sunmote.png`.

`SunmoteModel` v2 nests a 1.4x1.4x1.4 `core_inner` kernel inside the 2x2x2 core; its
box-UV rects live at texOffs (16,0) on the frozen 32x32 sheet (`docs/uv/sunmote.md`).
The kernel's fractional cube samples sub-pixel UVs, so the whole (16,0)-(22,3) block is
painted UNIFORM kernel-white `#FFFBE8` (one step hotter than the `#FFF2C0` core) — any
fractional rect inside it reads identically, and under the additive `RenderType.eyes`
pass the pulsing kernel flares white through the shell. Everything else on the sheet is
left byte-identical.

Run from the ProjectEclipse root: `python3 scripts/skin_gen/sunmote_v2.py`.
Deterministic -> byte-identical output on every rerun.
"""

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from boss_paint import hexc  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PNG = ROOT / "src/main/resources/assets/eclipse/textures/entity/sunmote.png"

KERNEL = hexc("#FFFBE8")


def main():
    img = Image.open(PNG).convert("RGBA")
    px = img.load()
    for gy in range(0, 3):
        for gx in range(16, 22):
            px[gx, gy] = KERNEL
    img.save(PNG)
    print(f"sunmote v2 inner-core kernel painted into {PNG} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    main()
