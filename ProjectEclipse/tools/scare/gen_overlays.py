#!/usr/bin/env python3
"""Procedural horror-overlay generator for the Scare framework (F-064).

Renders the 12 ``assets/eclipse/textures/scare/*.png`` overlay sheets consumed by
``client.scare.ScareOverlay``. Everything is built from seeded value noise, gradients
and PIL filter passes — abstract, high-contrast, deliberately NOT photographic and NOT
AI-generated. All sheets are 512x512 RGBA with meaningful alpha (the overlay layer
draws them straight onto the HUD, so transparent = screen shows through).

Usage:  python3 tools/scare/gen_overlays.py
        (writes into src/main/resources/assets/eclipse/textures/scare/)

Deterministic per texture: every sheet uses its own fixed seed, so re-running the
script reproduces byte-stable art (the repo convention for generated assets).
"""

from __future__ import annotations

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..",
                       "src", "main", "resources", "assets", "eclipse", "textures", "scare")


# ---------------------------------------------------------------- noise helpers

def value_noise(rng: np.random.Generator, size: int, octaves: int = 5,
                persistence: float = 0.55) -> np.ndarray:
    """Multi-octave value noise in [0,1] (bilinear-upscaled random lattices)."""
    total = np.zeros((size, size), dtype=np.float64)
    amplitude, norm = 1.0, 0.0
    for octave in range(octaves):
        cells = 4 * (2 ** octave)
        lattice = rng.random((cells, cells))
        layer = np.array(Image.fromarray((lattice * 255).astype(np.uint8), "L")
                         .resize((size, size), Image.BILINEAR), dtype=np.float64) / 255.0
        total += layer * amplitude
        norm += amplitude
        amplitude *= persistence
    return total / norm


def radial(size: int, cx: float, cy: float, radius: float) -> np.ndarray:
    """Distance-normalized radial field: 0 at the center, 1 at ``radius``."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    return np.clip(np.hypot(xs - cx * size, ys - cy * size) / (radius * size), 0.0, 1.0)


def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def scanlines(size: int, period: int = 4, depth: float = 0.5) -> np.ndarray:
    """Horizontal CRT line mask in [1-depth, 1]."""
    row = (np.arange(size) % period) / max(1, period - 1)
    mask = 1.0 - depth * (0.5 + 0.5 * np.cos(row * 2.0 * np.pi))
    return np.repeat(mask[:, None], size, axis=1)


def displace_rows(field: np.ndarray, rng: np.random.Generator, max_shift: int,
                  band: int = 6) -> np.ndarray:
    """VHS-style horizontal tearing: whole row bands shifted by random offsets."""
    out = field.copy()
    for y0 in range(0, field.shape[0], band):
        shift = int((rng.random() - 0.5) * 2 * max_shift)
        out[y0:y0 + band] = np.roll(field[y0:y0 + band], shift, axis=1)
    return out


def to_image(rgb: np.ndarray, alpha: np.ndarray) -> Image.Image:
    """Stack float [0,1] rgb (3,h,w or h,w) + alpha (h,w) into an RGBA image."""
    if rgb.ndim == 2:
        rgb = np.stack([rgb, rgb, rgb])
    data = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    for i in range(3):
        data[:, :, i] = (np.clip(rgb[i], 0.0, 1.0) * 255).astype(np.uint8)
    data[:, :, 3] = (np.clip(alpha, 0.0, 1.0) * 255).astype(np.uint8)
    return Image.fromarray(data, "RGBA")


def eye_socket(draw: ImageDraw.ImageDraw, cx: float, cy: float, rx: float, ry: float,
               glow: int) -> None:
    """One hollow eye: dark socket ellipse with a small bright core."""
    draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(0, 0, 0, 255))
    core = min(rx, ry) * 0.28
    draw.ellipse([cx - core, cy - core * 0.7, cx + core, cy + core * 0.7],
                 fill=(glow, glow, int(glow * 0.85), 235))


# ---------------------------------------------------------------- textures

def tex_face_static(rng: np.random.Generator) -> Image.Image:
    """A face suggested purely by noise: dark sockets and a mouth torn into static."""
    noise = value_noise(rng, SIZE, octaves=7, persistence=0.72)
    noise = displace_rows(noise, rng, max_shift=34, band=4)
    contrast = smoothstep((noise - 0.48) * 5.5 + 0.5)  # harsh posterized static
    contrast *= scanlines(SIZE, period=5, depth=0.55)
    head = 1.0 - smoothstep(radial(SIZE, 0.5, 0.48, 0.42) * 1.15 - 0.1)
    rgb = contrast * 0.9 * head
    alpha = head * (0.3 + 0.7 * contrast)
    img = to_image(rgb, alpha)
    draw = ImageDraw.Draw(img)
    eye_socket(draw, 0.36 * SIZE, 0.40 * SIZE, 46, 30, 200)
    eye_socket(draw, 0.64 * SIZE, 0.41 * SIZE, 44, 32, 200)
    draw.ellipse([0.40 * SIZE, 0.62 * SIZE, 0.60 * SIZE, 0.80 * SIZE], fill=(0, 0, 0, 255))
    return img.filter(ImageFilter.GaussianBlur(1.2))


def tex_face_hollow(rng: np.random.Generator) -> Image.Image:
    """Long pale face, empty sockets, vertically smeared — the corridor watcher."""
    noise = value_noise(rng, SIZE, octaves=5)
    ys = np.mgrid[0:SIZE, 0:SIZE][0] / SIZE
    face = 1.0 - smoothstep(radial(SIZE, 0.5, 0.5, 0.30) * (1.0 + 0.8 * np.abs(ys - 0.5)))
    pale = (0.55 + 0.30 * noise) * face
    img = to_image(np.stack([pale * 0.92, pale * 0.95, pale * 0.88]), face * 0.9)
    img = img.resize((SIZE, int(SIZE * 1.6)), Image.BILINEAR).crop(
        (0, int(SIZE * 0.3), SIZE, int(SIZE * 1.3)))
    img = img.resize((SIZE, SIZE), Image.BILINEAR)
    draw = ImageDraw.Draw(img)
    eye_socket(draw, 0.38 * SIZE, 0.38 * SIZE, 40, 52, 30)
    eye_socket(draw, 0.62 * SIZE, 0.38 * SIZE, 40, 52, 30)
    draw.ellipse([0.44 * SIZE, 0.66 * SIZE, 0.56 * SIZE, 0.88 * SIZE], fill=(5, 3, 6, 255))
    return img.filter(ImageFilter.GaussianBlur(2.2))


def tex_face_scream(rng: np.random.Generator) -> Image.Image:
    """The bang face: wide-open mouth, radial shock streaks, hard contrast."""
    noise = value_noise(rng, SIZE, octaves=6)
    ys, xs = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    angle = np.arctan2(ys - SIZE * 0.52, xs - SIZE * 0.5)
    streaks = 0.5 + 0.5 * np.sin(angle * 34.0 + noise * 9.0)
    head = 1.0 - smoothstep(radial(SIZE, 0.5, 0.5, 0.44) * 1.1 - 0.05)
    rgb = smoothstep((noise * 0.6 + streaks * 0.4 - 0.35) * 2.6) * head
    img = to_image(np.stack([rgb, rgb * 0.82, rgb * 0.78]), head * (0.4 + 0.6 * rgb))
    draw = ImageDraw.Draw(img)
    eye_socket(draw, 0.35 * SIZE, 0.34 * SIZE, 52, 40, 240)
    eye_socket(draw, 0.65 * SIZE, 0.34 * SIZE, 52, 40, 240)
    draw.ellipse([0.34 * SIZE, 0.52 * SIZE, 0.66 * SIZE, 0.94 * SIZE], fill=(0, 0, 0, 255))
    draw.ellipse([0.40 * SIZE, 0.56 * SIZE, 0.60 * SIZE, 0.66 * SIZE],
                 fill=(140, 120, 115, 200))  # upper teeth ridge
    return img.filter(ImageFilter.GaussianBlur(1.0))


def tex_eyes_pair(rng: np.random.Generator) -> Image.Image:
    """Nothing but two asymmetric glowing eyes floating in soft darkness."""
    haze = value_noise(rng, SIZE, octaves=4)
    dark = (1.0 - smoothstep(radial(SIZE, 0.5, 0.45, 0.55))) * (0.35 + 0.25 * haze)
    img = to_image(dark * 0.12, dark)
    draw = ImageDraw.Draw(img)
    for cx, cy, rx, ry in ((0.37, 0.45, 34, 20), (0.66, 0.43, 30, 24)):
        for r in range(5, 0, -1):  # layered glow
            a = int(30 * (6 - r))
            draw.ellipse([cx * SIZE - rx * r / 2.4, cy * SIZE - ry * r / 2.4,
                          cx * SIZE + rx * r / 2.4, cy * SIZE + ry * r / 2.4],
                         fill=(220, 214, 176, a))
        draw.ellipse([cx * SIZE - rx * 0.5, cy * SIZE - ry * 0.5,
                      cx * SIZE + rx * 0.5, cy * SIZE + ry * 0.5], fill=(250, 246, 210, 255))
        draw.ellipse([cx * SIZE - 4, cy * SIZE - ry * 0.5, cx * SIZE + 4, cy * SIZE + ry * 0.5],
                     fill=(10, 4, 8, 255))  # slit pupil
    return img.filter(ImageFilter.GaussianBlur(1.6))


def tex_eye_single(rng: np.random.Generator) -> Image.Image:
    """One huge iris filling the sheet — veins from noise, slit pupil."""
    noise = value_noise(rng, SIZE, octaves=6)
    dist = radial(SIZE, 0.5, 0.5, 0.46)
    ys, xs = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    angle = np.arctan2(ys - SIZE * 0.5, xs - SIZE * 0.5)
    veins = 0.5 + 0.5 * np.sin(angle * 22.0 + noise * 14.0)
    iris = np.clip((1.0 - dist) * (0.35 + 0.4 * veins + 0.25 * noise), 0.0, 1.0)
    ring = np.exp(-((dist - 0.62) ** 2) / 0.004)
    rgb = np.stack([iris * 0.75 + ring * 0.2, iris * 0.16, iris * 0.10])
    alpha = smoothstep((1.0 - dist) * 1.6)
    img = to_image(rgb, alpha)
    draw = ImageDraw.Draw(img)
    draw.ellipse([0.46 * SIZE, 0.22 * SIZE, 0.54 * SIZE, 0.78 * SIZE], fill=(0, 0, 0, 255))
    return img.filter(ImageFilter.GaussianBlur(1.4))


def tex_silhouette(rng: np.random.Generator) -> Image.Image:
    """A standing figure, slightly wrong proportions, edges eaten by noise."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx = SIZE * 0.5
    draw.ellipse([cx - 42, 40, cx + 42, 150], fill=(3, 2, 5, 255))  # head
    draw.polygon([(cx - 26, 140), (cx + 26, 140), (cx + 74, 470), (cx - 74, 470)],
                 fill=(3, 2, 5, 255))  # torso, too long
    draw.polygon([(cx - 26, 170), (cx - 96, 400), (cx - 78, 404), (cx - 16, 220)],
                 fill=(3, 2, 5, 255))  # arms, too thin
    draw.polygon([(cx + 26, 170), (cx + 96, 400), (cx + 78, 404), (cx + 16, 220)],
                 fill=(3, 2, 5, 255))
    noise = value_noise(rng, SIZE, octaves=5)
    data = np.array(img, dtype=np.float64)
    data[:, :, 3] *= 0.55 + 0.45 * noise  # edge rot
    img = Image.fromarray(data.astype(np.uint8), "RGBA")
    return img.filter(ImageFilter.GaussianBlur(2.5))


def tex_mask_pale(rng: np.random.Generator) -> Image.Image:
    """Porcelain mask: featureless bone-white oval, hairline noise cracks."""
    noise = value_noise(rng, SIZE, octaves=6)
    dist = radial(SIZE, 0.5, 0.5, 0.34)
    ys = np.mgrid[0:SIZE, 0:SIZE][0] / SIZE
    oval = 1.0 - smoothstep(dist * (1.0 + 0.65 * np.abs(ys - 0.48) * 2.0))
    cracks = smoothstep((np.abs(noise - 0.5) < 0.012).astype(np.float64))
    tone = (0.88 - 0.12 * noise) * oval * (1.0 - cracks * 0.8)
    img = to_image(np.stack([tone, tone * 0.98, tone * 0.94]), oval * 0.95)
    draw = ImageDraw.Draw(img)
    eye_socket(draw, 0.40 * SIZE, 0.42 * SIZE, 30, 38, 12)
    eye_socket(draw, 0.60 * SIZE, 0.42 * SIZE, 30, 38, 12)
    draw.line([(0.5 * SIZE, 0.60 * SIZE), (0.5 * SIZE, 0.72 * SIZE)], fill=(20, 14, 16, 220),
              width=3)  # sewn mouth seam
    for x in range(int(0.44 * SIZE), int(0.57 * SIZE), 12):
        draw.line([(x, 0.685 * SIZE), (x + 6, 0.655 * SIZE)], fill=(20, 14, 16, 200), width=2)
    return img.filter(ImageFilter.GaussianBlur(1.2))


def tex_maw(rng: np.random.Generator) -> Image.Image:
    """A dark maw ringed by irregular teeth, red gullet falling to black."""
    noise = value_noise(rng, SIZE, octaves=5)
    dist = radial(SIZE, 0.5, 0.55, 0.5)
    gullet = np.clip(1.0 - dist * 1.25, 0.0, 1.0)
    rgb = np.stack([gullet * 0.5 * (0.6 + 0.4 * noise), gullet * 0.06, gullet * 0.05])
    img = to_image(rgb, smoothstep(gullet * 2.2))
    draw = ImageDraw.Draw(img)
    rng2 = np.random.default_rng(4242)
    for i in range(26):  # tooth ring
        a = i / 26.0 * 2 * np.pi
        r0, r1 = SIZE * 0.36, SIZE * (0.20 + 0.07 * rng2.random())
        cx, cy = SIZE * 0.5, SIZE * 0.55
        x0, y0 = cx + np.cos(a) * r0, cy + np.sin(a) * r0
        x1, y1 = cx + np.cos(a + 0.05) * r0, cy + np.sin(a + 0.05) * r0
        xt, yt = cx + np.cos(a + 0.025) * r1, cy + np.sin(a + 0.025) * r1
        draw.polygon([(x0, y0), (x1, y1), (xt, yt)], fill=(214, 202, 178, 250))
    return img.filter(ImageFilter.GaussianBlur(1.5))


def tex_smear_ghost(rng: np.random.Generator) -> Image.Image:
    """A vertically smeared translucent apparition — barely a body at all."""
    noise = value_noise(rng, SIZE, octaves=4)
    body = 1.0 - smoothstep(radial(SIZE, 0.5, 0.42, 0.30) * 1.2)
    glow = body * (0.5 + 0.5 * noise)
    img = to_image(np.stack([glow * 0.75, glow * 0.82, glow * 0.9]), body * 0.7)
    img = img.resize((SIZE, SIZE * 2), Image.BILINEAR).crop((0, 0, SIZE, SIZE))
    img = img.filter(ImageFilter.GaussianBlur(6.0))
    draw = ImageDraw.Draw(img)
    eye_socket(draw, 0.42 * SIZE, 0.30 * SIZE, 22, 26, 20)
    eye_socket(draw, 0.58 * SIZE, 0.30 * SIZE, 22, 26, 20)
    return img.filter(ImageFilter.GaussianBlur(2.0))


def tex_scanline_veil(rng: np.random.Generator) -> Image.Image:
    """Fullscreen CRT veil: static + scanlines + torn row bands, mid alpha."""
    noise = value_noise(rng, SIZE, octaves=7, persistence=0.7)
    noise = displace_rows(noise, rng, max_shift=40, band=4)
    lines = scanlines(SIZE, period=4, depth=0.7)
    field = np.clip(noise * lines, 0.0, 1.0)
    rgb = np.stack([field * 0.85, field * 0.9, field * 0.95])
    alpha = 0.25 + 0.5 * smoothstep((field - 0.45) * 3.0 + 0.5)
    return to_image(rgb, alpha)


def tex_hands(rng: np.random.Generator) -> Image.Image:
    """Too-long fingers reaching in from both sides of the frame."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng2 = np.random.default_rng(1717)
    for side in (-1, 1):
        base_x = 0 if side < 0 else SIZE
        palm_y = SIZE * (0.45 if side < 0 else 0.55)
        draw.ellipse([base_x - 70, palm_y - 60, base_x + 70, palm_y + 90],
                     fill=(4, 3, 6, 255))  # palm mass at the frame edge
        for i in range(5):
            y = SIZE * (0.18 + 0.15 * i) + rng2.random() * 14
            length = SIZE * (0.40 + 0.16 * rng2.random())
            tip_x = base_x + side * -length
            width = 26 - 2 * i
            draw.line([(base_x, palm_y), (base_x + side * -length * 0.55, y + 10),
                       (tip_x, y)], fill=(4, 3, 6, 255), width=width)
            draw.ellipse([tip_x - 9, y - 9, tip_x + 9, y + 9], fill=(4, 3, 6, 255))
    noise = value_noise(rng, SIZE, octaves=5)
    data = np.array(img, dtype=np.float64)
    data[:, :, 3] *= 0.85 + 0.15 * noise
    img = Image.fromarray(data.astype(np.uint8), "RGBA")
    return img.filter(ImageFilter.GaussianBlur(2.2))


def tex_figure_crawl(rng: np.random.Generator) -> Image.Image:
    """A low crawling shape seen head-on: skewed head, splayed limb stubs."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse([SIZE * 0.36, SIZE * 0.42, SIZE * 0.64, SIZE * 0.72],
                 fill=(4, 3, 6, 255))  # skull, tilted low
    draw.polygon([(SIZE * 0.40, SIZE * 0.66), (SIZE * 0.60, SIZE * 0.66),
                  (SIZE * 0.72, SIZE * 0.92), (SIZE * 0.28, SIZE * 0.92)],
                 fill=(4, 3, 6, 255))  # hunched mass
    for sx, ex in ((0.36, 0.10), (0.64, 0.90)):  # splayed arms
        draw.line([(SIZE * sx, SIZE * 0.74), (SIZE * ex, SIZE * 0.88)],
                  fill=(4, 3, 6, 255), width=22)
        draw.ellipse([SIZE * ex - 16, SIZE * 0.86, SIZE * ex + 16, SIZE * 0.94],
                     fill=(4, 3, 6, 255))
    noise = value_noise(rng, SIZE, octaves=5)
    data = np.array(img, dtype=np.float64)
    data[:, :, 3] *= 0.6 + 0.4 * noise
    img = Image.fromarray(data.astype(np.uint8), "RGBA")
    img = img.filter(ImageFilter.GaussianBlur(2.0))
    draw = ImageDraw.Draw(img)
    eye_socket(draw, 0.44 * SIZE, 0.52 * SIZE, 18, 22, 210)
    eye_socket(draw, 0.57 * SIZE, 0.54 * SIZE, 18, 20, 210)
    return img


TEXTURES = {
    "face_static": (tex_face_static, 101),
    "face_hollow": (tex_face_hollow, 102),
    "face_scream": (tex_face_scream, 103),
    "eyes_pair": (tex_eyes_pair, 104),
    "eye_single": (tex_eye_single, 105),
    "silhouette": (tex_silhouette, 106),
    "mask_pale": (tex_mask_pale, 107),
    "maw": (tex_maw, 108),
    "smear_ghost": (tex_smear_ghost, 109),
    "scanline_veil": (tex_scanline_veil, 110),
    "hands": (tex_hands, 111),
    "figure_crawl": (tex_figure_crawl, 112),
}


def main() -> None:
    out = os.path.abspath(OUT_DIR)
    os.makedirs(out, exist_ok=True)
    for name, (builder, seed) in TEXTURES.items():
        image = builder(np.random.default_rng(seed))
        path = os.path.join(out, f"{name}.png")
        image.save(path, optimize=True)
        print(f"wrote {path} ({os.path.getsize(path)} bytes)")


if __name__ == "__main__":
    main()
