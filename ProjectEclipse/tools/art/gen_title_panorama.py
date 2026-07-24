#!/usr/bin/env python3
"""Procedural Eclipse title-screen panorama generator (PLAN-A wave 5, package A3).

Renders the six cube-map faces used by the custom title screen
(``assets/eclipse/textures/gui/title/panorama_0..5.png``) as a clean night sky:

* dark indigo vertical gradient (near-black zenith -> muted indigo horizon),
* subtle static star field (upper hemisphere, violet-white motes),
* thin violet horizon glow line,
* eclipsed sun disc with a tight corona ring + soft halo on the front face,
* mild azimuthal falloff so the back/side faces read darker than the front,
* NO cloud/fog plates — the previous "weird fog" look is gone by design.

Every color component is a pure function of the normalized 3D view direction,
so all shared cube edges match exactly (no seams). Stars are the only per-face
stamps; any star landing within a few pixels of a face border is skipped, which
is invisible at this density but sidesteps cross-face stamping entirely.

Usage: python3 tools/art/gen_title_panorama.py  (requires Pillow + numpy)
Deterministic: fixed RNG seed, same output every run.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 512  # face resolution (kept <= 512 per A3 spec)
OUT_DIR = Path(__file__).resolve().parents[2] / (
    "src/main/resources/assets/eclipse/textures/gui/title")
SEED = 20260724

# --- palette (linear-ish 0..255 floats) -------------------------------------
ZENITH = np.array([7.0, 5.0, 18.0])          # near-black indigo straight up
HORIZON_SKY = np.array([34.0, 26.0, 70.0])   # muted indigo at the horizon
GROUND_NEAR = np.array([10.0, 7.0, 20.0])    # just below the horizon
GROUND_DEEP = np.array([3.0, 2.0, 7.0])      # straight down
GLOW_WIDE = np.array([88.0, 58.0, 158.0])    # broad violet horizon bloom
GLOW_LINE = np.array([150.0, 108.0, 226.0])  # thin bright horizon line
DISC_FILL = np.array([6.0, 4.0, 12.0])       # eclipsed disc (darker than sky)
CORONA = np.array([214.0, 178.0, 255.0])     # tight corona ring
HALO = np.array([120.0, 78.0, 200.0])        # soft halo around the disc

# --- eclipse placement (front face = yaw 0) ----------------------------------
DISC_ELEVATION = 0.30   # radians above the horizon
DISC_RADIUS = 0.155     # angular radius of the disc (radians)
CORONA_SIGMA = 0.012    # ring thickness
HALO_FALLOFF = 0.11     # exponential halo reach

STAR_COUNT = 1400
STAR_EDGE_MARGIN_PX = 4

# Self-consistent cube basis: forward/right per face, +Y up, image-top = up.
# 0=front, 1=right, 2=back, 3=left, 4=top, 5=bottom (title-screen convention).
FACE_BASES = [
    ((0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),    # 0 front
    ((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)),   # 1 right
    ((0.0, 0.0, -1.0), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),  # 2 back
    ((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)),   # 3 left
    ((0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, -1.0)),   # 4 top
    ((0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)),   # 5 bottom
]

DISC_DIR = np.array([0.0, math.sin(DISC_ELEVATION), math.cos(DISC_ELEVATION)])


def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def face_directions(face: int) -> np.ndarray:
    """(SIZE, SIZE, 3) array of unit view directions for every pixel."""
    forward, right, up = (np.array(v) for v in FACE_BASES[face])
    px = (np.arange(SIZE) + 0.5) / SIZE * 2.0 - 1.0
    u, v = np.meshgrid(px, px)  # v grows downward (image rows)
    d = (u[..., None] * right) + (-v[..., None] * up) + forward
    return d / np.linalg.norm(d, axis=-1, keepdims=True)


def shade(dirs: np.ndarray) -> np.ndarray:
    """Pure direction -> RGB float image. Seamless across faces by construction."""
    e = dirs[..., 1]  # elevation component (-1 down .. +1 up)

    # Sky gradient above the horizon, quick fade to deep ground below it.
    sky_t = smoothstep(np.clip(e, 0.0, 1.0) ** 0.72)
    sky = HORIZON_SKY + (ZENITH - HORIZON_SKY) * sky_t[..., None]
    gnd_t = smoothstep(np.clip(-e / 0.45, 0.0, 1.0))
    ground = GROUND_NEAR + (GROUND_DEEP - GROUND_NEAR) * gnd_t[..., None]
    base = np.where((e >= 0.0)[..., None], sky, ground)

    # Mild azimuthal modulation: front (eclipse side) brightest, back darkest.
    flat = np.linalg.norm(dirs[..., [0, 2]], axis=-1)
    cos_az = np.divide(dirs[..., 2], flat, out=np.ones_like(flat), where=flat > 1e-6)
    base = base * (0.84 + 0.16 * (cos_az * 0.5 + 0.5))[..., None]

    # Thin violet horizon glow (asymmetric: mostly above the line, no blotches).
    side = np.where(e >= 0.0, 1.0, 0.38)
    wide = np.exp(-((e / 0.055) ** 2)) * 0.42 * side
    line = np.exp(-((e / 0.014) ** 2)) * 0.55 * side
    color = base + GLOW_WIDE * wide[..., None] + GLOW_LINE * line[..., None]

    # Eclipse disc + corona + halo (function of angular distance -> seamless).
    ang = np.arccos(np.clip(dirs @ DISC_DIR, -1.0, 1.0))
    inside = smoothstep((DISC_RADIUS - ang) / 0.010)
    ring = np.exp(-(((ang - DISC_RADIUS) / CORONA_SIGMA) ** 2))
    ring = np.where(ang < DISC_RADIUS, ring * 0.35, ring)  # dark limb stays dark
    halo = np.exp(-np.clip(ang - DISC_RADIUS, 0.0, None) / HALO_FALLOFF) * 0.30
    halo = halo * (1.0 - inside)
    color = color * (1.0 - inside[..., None]) + DISC_FILL * inside[..., None]
    color = color + CORONA * ring[..., None] * 0.85 + HALO * halo[..., None]
    return color


def scatter_stars(images: list[np.ndarray], rng: np.random.Generator) -> None:
    """Stamp small gaussian stars per face; skip near-edge/near-disc stars."""
    bases = [tuple(np.array(v) for v in FACE_BASES[i]) for i in range(6)]
    made = 0
    while made < STAR_COUNT:
        d = rng.normal(size=3)
        d /= np.linalg.norm(d)
        if d[1] < 0.015:  # stars only above the horizon line
            continue
        if math.acos(float(np.clip(d @ DISC_DIR, -1, 1))) < DISC_RADIUS + 0.05:
            continue  # the eclipsed disc occludes stars
        made += 1
        # fewer/fainter stars near the horizon, denser towards the zenith
        fade = smoothstep(np.clip((d[1] - 0.015) / 0.25, 0.0, 1.0)) * 0.75 + 0.25
        peak = rng.uniform(30.0, 185.0) * fade
        sigma = rng.uniform(0.55, 1.15)
        tint = np.array([rng.uniform(0.86, 1.0), rng.uniform(0.80, 0.92), 1.0])
        for face, (forward, right, up) in enumerate(bases):
            t = float(d @ forward)
            if t <= 0.35:
                continue
            p = d / t
            u, v = float(p @ right), -float(p @ up)
            if abs(u) > 1.0 or abs(v) > 1.0:
                continue
            cx, cy = (u + 1.0) * 0.5 * SIZE, (v + 1.0) * 0.5 * SIZE
            m = STAR_EDGE_MARGIN_PX
            if not (m < cx < SIZE - m and m < cy < SIZE - m):
                continue
            r = 3
            x0, y0 = int(cx) - r, int(cy) - r
            xs = np.arange(x0, x0 + 2 * r + 1)
            ys = np.arange(y0, y0 + 2 * r + 1)
            gx, gy = np.meshgrid(xs, ys)
            g = np.exp(-(((gx + 0.5 - cx) ** 2 + (gy + 0.5 - cy) ** 2)
                         / (2.0 * sigma * sigma)))
            images[face][y0:y0 + 2 * r + 1, x0:x0 + 2 * r + 1] += (
                g[..., None] * tint * peak)
            break  # each star lives fully inside exactly one face


def main() -> None:
    rng = np.random.default_rng(SEED)
    images = [shade(face_directions(face)) for face in range(6)]
    scatter_stars(images, rng)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for face, img in enumerate(images):
        img = img + rng.uniform(-1.2, 1.2, size=img.shape)  # de-banding dither
        out = np.clip(img, 0.0, 255.0).astype(np.uint8)
        path = OUT_DIR / f"panorama_{face}.png"
        Image.fromarray(out, "RGB").save(path, optimize=True)
        print(f"wrote {path} ({path.stat().st_size / 1024:.0f} KiB)")


if __name__ == "__main__":
    main()
