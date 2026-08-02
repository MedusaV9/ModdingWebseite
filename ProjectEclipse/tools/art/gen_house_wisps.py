#!/usr/bin/env python3
"""Regenerate the house wisp sprites with an exact alpha-0 border ring (E3).

Problem (F-107 class, EMITTER_AUDIT_F107_CLASS.md §6/E3): the shipped 8x8
wisps ``purple_wisp.png`` / ``wisp_white.png`` carry alpha up to 26/255 on
their outermost pixel ring. Every stretched quad therefore draws its own
geometric edge as a faint box contour — on llvmpipe (nearest sampling, no
mipmaps) this reads as a hard rectangle around each of the ~90 emitters
that use these sprites.

Fix: re-emit both wisps at 16x16 with
  * interior (inner 6x6 of the original 8x8) reproduced EXACTLY as flat
    2x2 blocks — same hues, same peak alpha 189, zero interior delta;
  * the outermost 16x16 ring at EXACTLY alpha 0, so the quad edge never
    draws;
  * the ring in between (the footprint of the old 8x8 border ring) filled
    with a radial piecewise-linear falloff sampled from the original wisp
    profile, globally scaled so the border-zone alpha mass matches the
    original border ring — overall brightness is conserved and the old
    plus-shaped corner clipping becomes a circular fade.

The original 8x8 pixel data is baked in below (measured from the shipped
PNGs before this fix) so the script is a pure function: double runs are
byte-identical and independent of the current on-disk textures.

Usage (from the repo root):
    python3 tools/art/gen_house_wisps.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image

PARTICLE_DIR = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/particle"
)

SRC_SIZE = 8
DST_SIZE = 16

# Shipped 8x8 alpha plane (identical for both wisps): radially symmetric,
# rings 189/139/108/83/62/26/11, corners 0, border-ring max 26.
ORIG_ALPHA = [
    [0, 0, 11, 26, 26, 11, 0, 0],
    [0, 26, 62, 83, 83, 62, 26, 0],
    [11, 62, 108, 139, 139, 108, 62, 11],
    [26, 83, 139, 189, 189, 139, 83, 26],
    [26, 83, 139, 189, 189, 139, 83, 26],
    [11, 62, 108, 139, 139, 108, 62, 11],
    [0, 26, 62, 83, 83, 62, 26, 0],
    [0, 0, 11, 26, 26, 11, 0, 0],
]

# Shipped RGB per alpha level (7-step radial ramp, core -> fringe).
PURPLE_RGB = {
    189: (231, 190, 255),
    139: (223, 173, 255),
    108: (217, 162, 255),
    83: (213, 154, 255),
    62: (209, 146, 255),
    26: (203, 134, 255),
    11: (200, 128, 255),
}
WHITE_RGB = {
    189: (255, 255, 255),
    139: (246, 246, 246),
    108: (239, 239, 239),
    83: (235, 235, 235),
    62: (230, 230, 230),
    26: (223, 223, 223),
    11: (220, 220, 220),
}

TEXTURES = [
    ("purple_wisp.png", PURPLE_RGB),
    ("wisp_white.png", WHITE_RGB),
]


def radial_profile() -> list[tuple[float, int]]:
    """(distance-from-center, alpha) knots measured from ORIG_ALPHA."""
    knots: dict[float, int] = {}
    for j in range(SRC_SIZE):
        for i in range(SRC_SIZE):
            d = math.hypot(i + 0.5 - SRC_SIZE / 2, j + 0.5 - SRC_SIZE / 2)
            d = round(d, 6)
            a = ORIG_ALPHA[j][i]
            if d in knots and knots[d] != a:
                raise AssertionError(f"non-radial source data at d={d}")
            knots[d] = a
    return sorted(knots.items())


def interp(knots: list[tuple[float, float]], d: float) -> float:
    """Piecewise-linear lookup, clamped flat at both ends."""
    if d <= knots[0][0]:
        return knots[0][1]
    for (d0, v0), (d1, v1) in zip(knots, knots[1:]):
        if d <= d1:
            return v0 + (v1 - v0) * (d - d0) / (d1 - d0)
    return knots[-1][1]


def build_alpha_plane() -> list[list[int]]:
    """16x16 alpha plane shared by both wisps."""
    alpha_knots = [(d, float(a)) for d, a in radial_profile()]

    raw = [[0.0] * DST_SIZE for _ in range(DST_SIZE)]
    for y in range(DST_SIZE):
        for x in range(DST_SIZE):
            d = math.hypot(
                (x + 0.5) / 2 - SRC_SIZE / 2, (y + 0.5) / 2 - SRC_SIZE / 2
            )
            raw[y][x] = interp(alpha_knots, d)

    def ring(x: int, y: int) -> int:
        return min(x, y, DST_SIZE - 1 - x, DST_SIZE - 1 - y)

    # Conserve the original border-ring alpha mass in the m==1 fringe ring
    # (m==0 is forced to exactly 0). Factor is capped at 1.0.
    orig_border_mass = sum(
        ORIG_ALPHA[j][i]
        for j in range(SRC_SIZE)
        for i in range(SRC_SIZE)
        if min(i, j, SRC_SIZE - 1 - i, SRC_SIZE - 1 - j) == 0
    )
    fringe_raw_mass = sum(
        raw[y][x]
        for y in range(DST_SIZE)
        for x in range(DST_SIZE)
        if ring(x, y) == 1
    )
    # x4: one 8x8 texel covers four 16x16 texels.
    k = min(1.0, orig_border_mass * 4 / fringe_raw_mass)

    plane = [[0] * DST_SIZE for _ in range(DST_SIZE)]
    for y in range(DST_SIZE):
        for x in range(DST_SIZE):
            m = ring(x, y)
            if m == 0:
                plane[y][x] = 0
            elif m == 1:
                plane[y][x] = round(raw[y][x] * k)
            else:
                # Interior: exact 2x2 replication of the original texel.
                plane[y][x] = ORIG_ALPHA[y // 2][x // 2]
    return plane


def build_texture(alpha: list[list[int]], ramp: dict[int, tuple[int, int, int]]) -> Image.Image:
    rgb_knots: dict[int, list[tuple[float, float]]] = {0: [], 1: [], 2: []}
    for d, a in radial_profile():
        if a > 0:
            for c in range(3):
                rgb_knots[c].append((d, float(ramp[a][c])))
    for c in range(3):
        rgb_knots[c].sort()

    img = Image.new("RGBA", (DST_SIZE, DST_SIZE), (0, 0, 0, 0))
    for y in range(DST_SIZE):
        for x in range(DST_SIZE):
            m = min(x, y, DST_SIZE - 1 - x, DST_SIZE - 1 - y)
            if m >= 2:
                pa = ORIG_ALPHA[y // 2][x // 2]
                rgb = ramp[pa] if pa > 0 else ramp[11]
            else:
                d = math.hypot(
                    (x + 0.5) / 2 - SRC_SIZE / 2, (y + 0.5) / 2 - SRC_SIZE / 2
                )
                rgb = tuple(round(interp(rgb_knots[c], d)) for c in range(3))
            img.putpixel((x, y), (*rgb, alpha[y][x]))
    return img


def measure(img: Image.Image, label: str) -> None:
    px = img.load()
    w, h = img.size
    ring = [
        px[x, y][3]
        for y in range(h)
        for x in range(w)
        if min(x, y, w - 1 - x, h - 1 - y) == 0
    ]
    interior_peak = max(
        px[x, y][3]
        for y in range(h)
        for x in range(w)
        if min(x, y, w - 1 - x, h - 1 - y) > 0
    )
    total = sum(px[x, y][3] for y in range(h) for x in range(w))
    # Normalize alpha mass to 8x8-texel units for before/after comparison.
    norm = total / ((w // SRC_SIZE) ** 2)
    print(
        f"  {label}: {w}x{h}  border-ring alpha min/max {min(ring)}/{max(ring)}"
        f"  interior peak {interior_peak}  alpha mass {norm:.1f} (8x8 units)"
    )


def interior_delta(img: Image.Image, ramp: dict[int, tuple[int, int, int]]) -> int:
    """Max channel delta of 2x2 means vs the baked original interior."""
    px = img.load()
    worst = 0.0
    for j in range(1, SRC_SIZE - 1):
        for i in range(1, SRC_SIZE - 1):
            quads = [px[i * 2 + dx, j * 2 + dy] for dy in (0, 1) for dx in (0, 1)]
            mean_a = sum(q[3] for q in quads) / 4
            worst = max(worst, abs(mean_a - ORIG_ALPHA[j][i]))
            if ORIG_ALPHA[j][i] > 0:
                for c in range(3):
                    mean_c = sum(q[c] for q in quads) / 4
                    worst = max(worst, abs(mean_c - ramp[ORIG_ALPHA[j][i]][c]))
    return math.ceil(worst)


def main() -> None:
    alpha = build_alpha_plane()
    for name, ramp in TEXTURES:
        dst = PARTICLE_DIR / name
        before = Image.new("RGBA", (SRC_SIZE, SRC_SIZE), (0, 0, 0, 0))
        for j in range(SRC_SIZE):
            for i in range(SRC_SIZE):
                a = ORIG_ALPHA[j][i]
                rgb = ramp[a] if a > 0 else (0, 0, 0)
                before.putpixel((i, j), (*rgb, a))

        img = build_texture(alpha, ramp)
        img.save(dst)

        print(f"{name}:")
        measure(before, "before (baked original)")
        measure(img, "after ")
        print(f"  interior max channel delta vs original: {interior_delta(img, ramp)}")


if __name__ == "__main__":
    main()
