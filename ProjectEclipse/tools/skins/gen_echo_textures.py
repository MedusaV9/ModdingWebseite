#!/usr/bin/env python3
"""WOAH-05 Echo-Grove texture generator (plan §4.3 / §7.5).

Procedurally renders every Echo-Grove texture — the ``tools/scare/gen_overlays.py``
school (seeded numpy noise + PIL, deterministic per texture, pixel-look, never
AI-generated):

  entity/echo_ghost.png       64x64 player skin: the pale blue-white derivation of
                              ``eclipsed_player.png`` — desaturated, lifted toward
                              moonlight, violet accents cooled to slate. Alpha kept.
  entity/echo_ghost_glow.png  the moonlit-silhouette pass (RenderType.eyes at 0.10):
                              the whole body as a soft pale-blue luminance map.
  entity/echo_ghost_wolf.png  64x32 vanilla-wolf-layout pale fur (procedural — the
                              repo ships no vanilla wolf.png to derive from).
  entity/memory_orb.png       32x32 soft radial orb sprite for MemoryOrbRenderer.
  item/memory_mote.png        16x16 wispy light mote (quest item).
  item/echo_blossom.png       16x16 pale-gold five-petal blossom (finale artifact).

Usage:  python3 tools/skins/gen_echo_textures.py
        (writes into src/main/resources/assets/eclipse/textures/)
"""

from __future__ import annotations

import os

import numpy as np
from PIL import Image

BASE_DIR = os.path.join(os.path.dirname(__file__), "..", "..",
                        "src", "main", "resources", "assets", "eclipse", "textures")


def _save(img: Image.Image, *path: str) -> None:
    out = os.path.join(BASE_DIR, *path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print(f"WROTE {os.path.relpath(out, os.path.join(BASE_DIR, '..', '..', '..', '..', '..'))}")


# ---------------------------------------------------------------- echo ghost skin

def build_echo_ghost() -> None:
    """Pale derivation of the eclipsed uniform skin: luma-driven remap onto a
    slate→moonlight ramp; the violet heart/veins cool to pale ice (the echo has
    no burning heart). Alpha is passed through 1:1 (layer holes stay holes)."""
    src = Image.open(os.path.join(BASE_DIR, "entity", "eclipsed_player.png")).convert("RGBA")
    arr = np.asarray(src).astype(np.float64) / 255.0
    rgb, alpha = arr[..., :3], arr[..., 3:]

    luma = rgb @ np.array([0.299, 0.587, 0.114])
    # Slate shadow → moonlight highlight ramp (kept dim: the renderer adds alpha).
    lo = np.array([0.36, 0.42, 0.52])
    hi = np.array([0.88, 0.93, 1.00])
    ramp = lo + (hi - lo) * luma[..., None] ** 0.85
    # Keep 18% of the original hue so the uniform's paneling still reads.
    pale = np.clip(ramp * 0.82 + rgb * 0.18, 0.0, 1.0)

    out = np.concatenate([pale, alpha], axis=-1)
    _save(Image.fromarray((out * 255).astype(np.uint8), "RGBA"), "entity", "echo_ghost.png")


def build_echo_ghost_glow() -> None:
    """Moonlit silhouette: the body luminance re-tinted pale blue on black-alpha.
    RenderType.eyes additively brightens — dark pixels are near-invisible, so the
    map IS the glow shape (brighter at the face/chest, dim at the extremities)."""
    src = Image.open(os.path.join(BASE_DIR, "entity", "eclipsed_player.png")).convert("RGBA")
    arr = np.asarray(src).astype(np.float64) / 255.0
    rgb, alpha = arr[..., :3], arr[..., 3]

    luma = rgb @ np.array([0.299, 0.587, 0.114])
    glow = np.clip(luma ** 0.7, 0.0, 1.0)
    tint = np.array([0.72, 0.82, 1.00])
    out = np.zeros_like(arr)
    out[..., :3] = glow[..., None] * tint
    out[..., 3] = (alpha > 0.5).astype(np.float64) * np.clip(0.35 + 0.65 * glow, 0.0, 1.0)
    _save(Image.fromarray((out * 255).astype(np.uint8), "RGBA"), "entity", "echo_ghost_glow.png")


# ---------------------------------------------------------------- echo wolf

def build_echo_ghost_wolf() -> None:
    """Pale wolf fur on the vanilla 64x32 wolf UV layout, fully procedural (seeded
    fur noise; the repo ships no vanilla wolf.png to derive from). Detail is
    deliberately soft — the renderer draws this at 0.35 alpha — but the head zone
    gets darker eye/nose pixels so the face reads at close range."""
    rng = np.random.default_rng(0xEC00_501F)
    w, h = 64, 32
    base = np.zeros((h, w, 4), dtype=np.float64)

    # Fur: pale blue-gray value noise, brighter along the spine rows.
    noise = rng.random((h, w)) * 0.5 + rng.random((h // 4, w // 4)).repeat(4, 0).repeat(4, 1) * 0.5
    fur_lo = np.array([0.58, 0.63, 0.72])
    fur_hi = np.array([0.86, 0.90, 0.97])
    base[..., :3] = fur_lo + (fur_hi - fur_lo) * noise[..., None]
    base[..., 3] = 1.0

    # Slightly darker mane/tail block columns (body UV x 18..54) for depth.
    base[16:30, 18:54, :3] *= 0.92

    # Head zone (vanilla head UV occupies roughly x 0..28, y 0..16).
    # Muzzle brighter:
    base[10:16, 3:12, :3] = np.clip(base[10:16, 3:12, :3] * 1.12, 0.0, 1.0)
    # Eyes (two 2x2 dark slate dots on the face front) + nose tip:
    eye = np.array([0.22, 0.26, 0.36])
    base[9:11, 4:6, :3] = eye
    base[9:11, 8:10, :3] = eye
    base[13:15, 6:8, :3] = np.array([0.30, 0.32, 0.40])

    _save(Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8), "RGBA"),
          "entity", "echo_ghost_wolf.png")


# ---------------------------------------------------------------- orb + items

def _radial_orb(size: int, core_rgb, rim_rgb, seed: int, sparkle: int = 0) -> Image.Image:
    """Soft radial orb: bright core → tinted rim → transparent, plus optional
    single-pixel sparkles inside the mid radius."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    c = (size - 1) / 2.0
    d = np.hypot(xs - c, ys - c) / (size / 2.0)

    body = np.clip(1.0 - d, 0.0, 1.0) ** 1.6
    core = np.clip(1.0 - d * 2.2, 0.0, 1.0) ** 1.2
    rgb = (np.asarray(rim_rgb)[None, None, :] * body[..., None]
           + np.asarray(core_rgb)[None, None, :] * core[..., None])
    alpha = np.clip(body * 1.3, 0.0, 1.0) * (d < 0.98)

    out = np.zeros((size, size, 4))
    out[..., :3] = np.clip(rgb, 0.0, 1.0)
    out[..., 3] = alpha
    for _ in range(sparkle):
        sx, sy = rng.integers(size // 4, 3 * size // 4, 2)
        out[sy, sx, :3] = 1.0
        out[sy, sx, 3] = 1.0
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA")


def build_memory_orb() -> None:
    _save(_radial_orb(32, (1.0, 1.0, 1.0), (0.66, 0.78, 0.91), 0x0EC0_0EB5, sparkle=5),
          "entity", "memory_orb.png")


def build_memory_mote() -> None:
    """Quest item: a caught wisp — small warm-white mote with a comet tail."""
    img = _radial_orb(16, (1.0, 0.99, 0.94), (0.72, 0.80, 0.92), 0x0EC0_301E, sparkle=2)
    arr = np.asarray(img).astype(np.float64) / 255.0
    # Tail: three fading pixels curling down-left off the core.
    for i, (dy, dx) in enumerate(((3, -2), (5, -4), (6, -6))):
        y, x = 8 + dy, 8 + dx
        if 0 <= y < 16 and 0 <= x < 16:
            fade = 0.55 - i * 0.15
            arr[y, x, :3] = np.maximum(arr[y, x, :3], np.array([0.80, 0.86, 0.97]) * fade)
            arr[y, x, 3] = max(arr[y, x, 3], fade)
    _save(Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA"),
          "item", "memory_mote.png")


def build_echo_blossom() -> None:
    """Finale artifact: a five-petal pale-gold blossom with a bright core —
    hand-plotted pixel petals (the classic item-sprite look)."""
    size = 16
    out = np.zeros((size, size, 4))
    petal = np.array([0.95, 0.86, 0.62])
    petal_hi = np.array([1.00, 0.95, 0.80])
    core = np.array([1.00, 0.99, 0.90])
    stem = np.array([0.62, 0.68, 0.58])

    cx, cy = 7.5, 6.5
    for angle in np.linspace(0.0, 2.0 * np.pi, 5, endpoint=False):
        px, py = cx + np.cos(angle - np.pi / 2) * 3.4, cy + np.sin(angle - np.pi / 2) * 3.4
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                x, y = int(round(px + dx)), int(round(py + dy))
                if 0 <= x < size and 0 <= y < size and dx * dx + dy * dy <= 4.5:
                    edge = dx * dx + dy * dy > 2.0
                    out[y, x, :3] = petal if edge else petal_hi
                    out[y, x, 3] = 1.0
    # Core.
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            x, y = int(cx + dx + 0.5), int(cy + dy + 0.5)
            out[y, x, :3] = core
            out[y, x, 3] = 1.0
    # Short stem below.
    for y in range(11, 15):
        out[y, 8, :3] = stem
        out[y, 8, 3] = 1.0
    _save(Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA"),
          "item", "echo_blossom.png")


def main() -> None:
    build_echo_ghost()
    build_echo_ghost_glow()
    build_echo_ghost_wolf()
    build_memory_orb()
    build_memory_mote()
    build_echo_blossom()


if __name__ == "__main__":
    main()
