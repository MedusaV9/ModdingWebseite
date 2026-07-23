#!/usr/bin/env python3
"""Procedural pale-oak / pale-moss textures for the Pale Garden port (P1-W1.4).

Generates every texture referenced by the eclipse:pale_* block/item models into
src/main/resources/assets/eclipse/textures/. Deterministic (fixed seed) 16x16
RGBA PNGs in a pale, desaturated palette: grey bark, bone-white stripped wood,
grey-green foliage and sage moss. Re-run after tweaking; output is idempotent.

    python3 tools/palegarden/gen_textures.py
"""

from __future__ import annotations

import random
from pathlib import Path

from PIL import Image

SIZE = 16
ROOT = Path(__file__).resolve().parents[2] / "src/main/resources/assets/eclipse/textures"

# --- palette (pale, desaturated) -------------------------------------------------
BARK_BASE = (92, 87, 82)          # grey-brown bark
BARK_DARK = (74, 70, 66)          # furrows
BARK_LIGHT = (110, 105, 99)       # ridge highlights
STRIP_BASE = (227, 219, 209)      # stripped pale wood
STRIP_DARK = (206, 197, 186)      # grain lines
STRIP_LIGHT = (238, 231, 222)     # sheen
PLANK_BASE = (223, 214, 203)      # planks a hair darker than stripped log
PLANK_DARK = (198, 189, 177)      # plank seams
PLANK_GRAIN = (211, 202, 190)     # in-plank grain
RING_DARK = (196, 186, 174)       # log-top growth rings
LEAF_BASE = (144, 151, 141)       # grey-green foliage (untinted!)
LEAF_DARK = (121, 128, 119)
LEAF_LIGHT = (166, 173, 162)
MOSS_BASE = (158, 164, 150)       # pale sage moss
MOSS_DARK = (135, 141, 128)
MOSS_LIGHT = (178, 184, 169)
MOSS_SPROUT = (196, 202, 186)     # pale sprout dots


def canvas(color=None) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    if color is not None:
        img.paste(color + (255,), (0, 0, SIZE, SIZE))
    return img


def jitter(rng: random.Random, color, amount: int):
    return tuple(max(0, min(255, c + rng.randint(-amount, amount))) for c in color)


def mottle(img: Image.Image, rng: random.Random, base, dark, light, dark_n=40, light_n=28):
    """Organic per-pixel speckle over a solid base."""
    px = img.load()
    for _ in range(dark_n):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        px[x, y] = jitter(rng, dark, 6) + (255,)
    for _ in range(light_n):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        px[x, y] = jitter(rng, light, 6) + (255,)
    for x in range(SIZE):
        for y in range(SIZE):
            if px[x, y][:3] == base:
                px[x, y] = jitter(rng, base, 4) + (255,)


def bark_side() -> Image.Image:
    rng = random.Random(0xEC11_0001)
    img = canvas(BARK_BASE)
    px = img.load()
    # vertical furrow strips of varying shade, broken by ridge highlights
    col_shift = [rng.choice((-1, 0, 0, 1)) for _ in range(SIZE)]
    for x in range(SIZE):
        tone = BARK_DARK if (x + col_shift[x]) % 4 == 0 else (
            BARK_LIGHT if (x + col_shift[x]) % 7 == 3 else BARK_BASE)
        for y in range(SIZE):
            c = jitter(rng, tone, 5)
            # occasional horizontal bark crack
            if rng.random() < 0.04:
                c = jitter(rng, BARK_DARK, 4)
            px[x, y] = c + (255,)
    return img


def log_top(stripped: bool) -> Image.Image:
    rng = random.Random(0xEC11_0002 if stripped else 0xEC11_0003)
    img = canvas(STRIP_BASE)
    px = img.load()
    cx = cy = (SIZE - 1) / 2.0
    for x in range(SIZE):
        for y in range(SIZE):
            d = max(abs(x - cx), abs(y - cy))  # square rings like vanilla log tops
            if not stripped and d >= 6.5:
                tone = BARK_DARK if (x + y) % 3 == 0 else BARK_BASE
            elif d >= 6.5:
                tone = STRIP_DARK  # stripped keeps a thin darker rim
            elif 4.5 <= d < 5.5 or 2.0 <= d < 2.9:
                tone = RING_DARK  # growth rings
            elif d < 1.0:
                tone = STRIP_DARK  # heartwood dot
            else:
                tone = STRIP_LIGHT if rng.random() < 0.18 else STRIP_BASE
            px[x, y] = jitter(rng, tone, 4) + (255,)
    return img


def stripped_side() -> Image.Image:
    rng = random.Random(0xEC11_0004)
    img = canvas(STRIP_BASE)
    px = img.load()
    grain_cols = {2, 6, 9, 13}
    for x in range(SIZE):
        for y in range(SIZE):
            if x in grain_cols and rng.random() < 0.82:
                tone = STRIP_DARK
            elif rng.random() < 0.10:
                tone = STRIP_LIGHT
            else:
                tone = STRIP_BASE
            px[x, y] = jitter(rng, tone, 4) + (255,)
    return img


def planks() -> Image.Image:
    rng = random.Random(0xEC11_0005)
    img = canvas(PLANK_BASE)
    px = img.load()
    # four 4px plank rows with offset vertical joints, vanilla-style
    joints = {0: 11, 1: 3, 2: 13, 3: 6}
    for y in range(SIZE):
        row = y // 4
        for x in range(SIZE):
            if y % 4 == 3:
                tone = PLANK_DARK  # horizontal seam
            elif x == joints[row] and y % 4 != 3:
                tone = PLANK_DARK  # vertical joint
            elif rng.random() < 0.16:
                tone = PLANK_GRAIN
            elif rng.random() < 0.06:
                tone = STRIP_LIGHT
            else:
                tone = PLANK_BASE
            px[x, y] = jitter(rng, tone, 4) + (255,)
    return img


def leaves() -> Image.Image:
    rng = random.Random(0xEC11_0006)
    img = canvas()
    px = img.load()
    for x in range(SIZE):
        for y in range(SIZE):
            if rng.random() < 0.24:
                continue  # transparent hole
            r = rng.random()
            tone = LEAF_DARK if r < 0.30 else (LEAF_LIGHT if r > 0.82 else LEAF_BASE)
            px[x, y] = jitter(rng, tone, 6) + (255,)
    # a few pale highlight clusters so the canopy reads "pale" from afar
    for _ in range(5):
        x, y = rng.randrange(1, SIZE - 1), rng.randrange(1, SIZE - 1)
        for dx, dy in ((0, 0), (1, 0), (0, 1)):
            px[x + dx, y + dy] = jitter(rng, LEAF_LIGHT, 5) + (255,)
    return img


def moss_block() -> Image.Image:
    rng = random.Random(0xEC11_0007)
    img = canvas(MOSS_BASE)
    mottle(img, rng, MOSS_BASE, MOSS_DARK, MOSS_LIGHT, dark_n=46, light_n=30)
    px = img.load()
    for _ in range(9):  # pale sprout dots
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        px[x, y] = jitter(rng, MOSS_SPROUT, 5) + (255,)
    return img


def hanging_strands(seed: int, strand_xs: tuple[int, ...]) -> Image.Image:
    """Vertical pale moss strands with wisps; transparent background."""
    rng = random.Random(seed)
    img = canvas()
    px = img.load()
    for sx in strand_xs:
        x = sx
        length = rng.randint(12, 16)
        for y in range(length):
            if rng.random() < 0.22 and 0 < x < SIZE - 1:
                x += rng.choice((-1, 1))  # gentle waver
            tone = MOSS_SPROUT if y > length - 3 else (
                MOSS_LIGHT if rng.random() < 0.35 else MOSS_BASE)
            px[x, y] = jitter(rng, tone, 5) + (255,)
            if rng.random() < 0.18 and 0 < x < SIZE - 1:  # side wisp
                wx = x + rng.choice((-1, 1))
                px[wx, y] = jitter(rng, MOSS_DARK, 5) + (255,)
    return img


def main() -> None:
    block = ROOT / "block"
    item = ROOT / "item"
    block.mkdir(parents=True, exist_ok=True)
    item.mkdir(parents=True, exist_ok=True)

    out = {
        block / "pale_oak_log.png": bark_side(),
        block / "pale_oak_log_top.png": log_top(stripped=False),
        block / "stripped_pale_oak_log.png": stripped_side(),
        block / "stripped_pale_oak_log_top.png": log_top(stripped=True),
        block / "pale_oak_planks.png": planks(),
        block / "pale_oak_leaves.png": leaves(),
        block / "pale_moss_block.png": moss_block(),
        block / "pale_hanging_moss.png": hanging_strands(0xEC11_0008, (3, 7, 12)),
        item / "pale_hanging_moss.png": hanging_strands(0xEC11_0009, (4, 8, 11)),
    }
    for path, img in out.items():
        img.save(path)
        print(f"wrote {path.relative_to(ROOT.parents[3])}")


if __name__ == "__main__":
    main()
