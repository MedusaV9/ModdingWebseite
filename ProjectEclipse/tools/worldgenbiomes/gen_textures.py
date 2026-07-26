#!/usr/bin/env python3
"""Procedural block textures for the WG3 biome expansion (F-059, 10 -> 20 biomes).

Generates every texture referenced by the WG3 eclipse:* block/item models into
src/main/resources/assets/eclipse/textures/block/. Deterministic (fixed seeds)
16x16 RGBA PNGs, 3-5 tones per texture, vanilla-style structured pixel art (no
noise-soup): facetted crystals, mottled soils, cross-sprite plants. Same tool
pattern as tools/palegarden/gen_textures.py; re-run after tweaking; output is
idempotent.

    python3 tools/worldgenbiomes/gen_textures.py
"""

from __future__ import annotations

import random
from pathlib import Path

from PIL import Image

SIZE = 16
ROOT = Path(__file__).resolve().parents[2] / "src/main/resources/assets/eclipse/textures/block"


def canvas(color=None) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    if color is not None:
        img.paste(color + (255,), (0, 0, SIZE, SIZE))
    return img


def jitter(rng: random.Random, color, amount: int):
    return tuple(max(0, min(255, ch + rng.randint(-amount, amount))) for ch in color)


def put(px, x, y, rng, color, amount=4):
    if 0 <= x < SIZE and 0 <= y < SIZE:
        px[x, y] = jitter(rng, color, amount) + (255,)


# --- solid blocks ----------------------------------------------------------------

def mottled(seed, base, dark, light, speck=None, dark_n=42, light_n=26, speck_n=0):
    """Organic soil/stone mottle: base tone with dark/light speckle (+ rare accents)."""
    rng = random.Random(seed)
    img = canvas(base)
    px = img.load()
    for x in range(SIZE):
        for y in range(SIZE):
            px[x, y] = jitter(rng, base, 4) + (255,)
    for _ in range(dark_n):
        put(px, rng.randrange(SIZE), rng.randrange(SIZE), rng, dark, 6)
    for _ in range(light_n):
        put(px, rng.randrange(SIZE), rng.randrange(SIZE), rng, light, 6)
    for _ in range(speck_n):
        put(px, rng.randrange(SIZE), rng.randrange(SIZE), rng, speck, 5)
    return img


def facets(seed, base, dark, light, glint, band=5):
    """Crystal block: diagonal facet bands with edge shading and rare glint pixels."""
    rng = random.Random(seed)
    img = canvas(base)
    px = img.load()
    offsets = [rng.choice((-1, 0, 0, 1)) for _ in range(2 * SIZE)]
    for x in range(SIZE):
        for y in range(SIZE):
            d = (x + y + offsets[x + y]) % (2 * band)
            if d < 1:
                tone = light  # facet ridge
            elif d < band:
                tone = base
            elif d < band + 1:
                tone = dark  # facet seam
            else:
                tone = jitter(rng, base, 3) if rng.random() < 0.5 else dark
            px[x, y] = jitter(rng, tone, 4) + (255,)
    for _ in range(5):
        put(px, rng.randrange(SIZE), rng.randrange(SIZE), rng, glint, 3)
    return img


def runestone() -> Image.Image:
    """Grey rubble stone with carved, faintly glowing glyph strokes."""
    rng = random.Random(0xEC59_0001)
    img = mottled(0xEC59_0002, (108, 108, 112), (86, 86, 92), (128, 128, 130))
    px = img.load()
    glyph = (150, 196, 176)   # faint glowing groove
    groove = (70, 70, 78)     # carved shadow beside each stroke
    strokes = [
        [(3, 3), (3, 4), (3, 5), (4, 5), (5, 5)],          # corner hook
        [(9, 2), (10, 3), (11, 4), (10, 5)],               # zigzag
        [(12, 9), (12, 10), (12, 11), (11, 11)],           # short L
        [(4, 10), (5, 10), (6, 10), (5, 11), (5, 12)],     # cross
    ]
    for stroke in strokes:
        for (x, y) in stroke:
            put(px, x, y, rng, glyph, 5)
            put(px, x + 1, y + 1, rng, groove, 4)
    return img


def voidglass() -> Image.Image:
    """Near-black glassy rock, violet sheen streaks along the fracture planes."""
    rng = random.Random(0xEC59_0003)
    base = (26, 22, 34)
    dark = (16, 13, 22)
    sheen = (74, 56, 104)
    glint = (134, 108, 178)
    img = canvas(base)
    px = img.load()
    for x in range(SIZE):
        for y in range(SIZE):
            tone = dark if (x + 2 * y) % 7 == 0 else base
            px[x, y] = jitter(rng, tone, 3) + (255,)
    for sx, sy, ln in ((2, 12, 5), (7, 5, 6), (12, 14, 4)):  # diagonal sheen streaks
        x, y = sx, sy
        for i in range(ln):
            put(px, x + i, y - i, rng, sheen, 6)
    for _ in range(4):
        put(px, rng.randrange(SIZE), rng.randrange(SIZE), rng, glint, 4)
    return img


def peat_block() -> Image.Image:
    """Dark waterlogged peat with paler dried-fiber flecks."""
    rng = random.Random(0xEC59_0004)
    img = mottled(0xEC59_0005, (74, 58, 42), (56, 44, 32), (94, 76, 54),
                  speck=(122, 104, 70), speck_n=8)
    px = img.load()
    for _ in range(6):  # short horizontal fiber strands
        x, y = rng.randrange(SIZE - 3), rng.randrange(SIZE)
        for i in range(rng.randint(2, 3)):
            put(px, x + i, y, rng, (108, 90, 60), 5)
    return img


def scoria() -> Image.Image:
    """Porous slag: dark crust, sunken pores, a few ember-lit pore mouths."""
    rng = random.Random(0xEC59_0006)
    img = mottled(0xEC59_0007, (58, 44, 40), (40, 30, 28), (76, 60, 52), dark_n=36, light_n=20)
    px = img.load()
    for _ in range(7):  # cold pores
        x, y = rng.randrange(1, SIZE - 1), rng.randrange(1, SIZE - 1)
        put(px, x, y, rng, (30, 22, 20), 3)
        put(px, x + 1, y, rng, (40, 30, 28), 3)
    for x, y in ((3, 5), (10, 2), (7, 11), (13, 13)):  # ember pores (the light 4 source)
        put(px, x, y, rng, (232, 120, 44), 6)
        put(px, x + 1, y, rng, (150, 70, 34), 6)
    return img


def sculk_gleam() -> Image.Image:
    """Sculk-toned accent stone with bright soul speckles and a swirl vein."""
    rng = random.Random(0xEC59_0008)
    img = mottled(0xEC59_0009, (13, 38, 44), (8, 26, 32), (22, 56, 62), dark_n=40, light_n=22)
    px = img.load()
    swirl = [(2, 9), (3, 8), (4, 7), (5, 7), (6, 8), (7, 9), (8, 10), (9, 10), (10, 9),
             (11, 8), (12, 7)]
    for (x, y) in swirl:
        put(px, x, y, rng, (34, 82, 90), 5)
    for x, y in ((4, 3), (11, 4), (7, 8), (13, 11), (3, 13)):  # soul gleam dots
        put(px, x, y, rng, (108, 226, 218), 6)
    return img


# --- plants (cross sprites, transparent background) --------------------------------

def withered_sunflower() -> Image.Image:
    """Dried sunflower husk: bent brown stem, drooping dark head, sagging petals."""
    rng = random.Random(0xEC59_0010)
    img = canvas()
    px = img.load()
    stem = (94, 82, 44)
    stem_dark = (72, 62, 34)
    head = (52, 40, 26)
    petal = (168, 142, 66)
    petal_dark = (128, 106, 50)
    for y in range(6, 16):  # stem, slightly bent
        x = 8 if y > 9 else 9
        put(px, x, y, rng, stem if y % 3 else stem_dark, 4)
    put(px, 7, 13, rng, stem_dark, 4)  # dry leaf stubs
    put(px, 10, 11, rng, stem_dark, 4)
    for dx in range(-1, 2):  # drooping head (faces down-left)
        for dy in range(-1, 2):
            put(px, 8 + dx, 5 + dy, rng, head, 4)
    for (x, y) in ((6, 4), (10, 4), (6, 6), (10, 6), (8, 3)):  # sagging petals
        put(px, x, y, rng, petal, 6)
    for (x, y) in ((5, 5), (11, 5), (7, 7), (9, 7)):
        put(px, x, y, rng, petal_dark, 6)
    return img


def glow_plant(seed, stem, stem_dark, cap, cap_light, cap_core, mushroom=True):
    """Small glowing mushroom/flower: 2px-wide cap dome or petal ring over a thin stem."""
    rng = random.Random(seed)
    img = canvas()
    px = img.load()
    for y in range(9, 16):
        put(px, 8, y, rng, stem if y % 2 else stem_dark, 4)
    if mushroom:
        for dx in range(-3, 4):  # cap rim
            put(px, 8 + dx, 8, rng, cap if abs(dx) < 3 else cap_light, 5)
        for dx in range(-2, 3):  # cap dome
            put(px, 8 + dx, 7, rng, cap, 5)
        for dx in range(-1, 2):
            put(px, 8 + dx, 6, rng, cap_light, 5)
        put(px, 8, 7, rng, cap_core, 4)  # glowing core
        put(px, 7, 8, rng, cap_core, 4)
    else:
        # Solid allium-style bloom head: rounded cluster, lit rim, glowing heart.
        for dx in range(-1, 2):        # top rim row
            put(px, 8 + dx, 4, rng, cap_light, 5)
        for dx in range(-2, 3):        # two full body rows
            put(px, 8 + dx, 5, rng, cap_light if abs(dx) == 2 else cap, 5)
            put(px, 8 + dx, 6, rng, cap, 5)
        for dx in range(-1, 2):        # bottom row closing the dome
            put(px, 8 + dx, 7, rng, cap, 5)
        put(px, 8, 5, rng, cap_core, 3)   # glowing heart
        put(px, 7, 6, rng, cap_core, 3)
    return img


def blades(seed, dark, base, light, tip):
    """Grass-like sprout tuft: 4-5 blades fanning out, light tips."""
    rng = random.Random(seed)
    img = canvas()
    px = img.load()
    blades_def = [(4, 15, 6, 7), (7, 15, 7, 4), (9, 15, 9, 5), (12, 15, 10, 7), (6, 15, 5, 9)]
    for (x0, y0, x1, y1) in blades_def:
        steps = y0 - y1
        for i in range(steps + 1):
            t = i / steps
            x = round(x0 + (x1 - x0) * t)
            y = y0 - i
            if i == steps:
                tone = tip
            elif t > 0.6:
                tone = light
            elif t > 0.25:
                tone = base
            else:
                tone = dark
            put(px, x, y, rng, tone, 5)
    return img


def amber_tendril() -> Image.Image:
    """Curling root strand with glowing amber nodules."""
    rng = random.Random(0xEC59_0011)
    img = canvas()
    px = img.load()
    root = (104, 78, 52)
    root_dark = (80, 60, 40)
    amber = (240, 166, 50)
    amber_deep = (196, 122, 34)
    path = [(8, 15), (8, 14), (7, 13), (7, 12), (8, 11), (9, 10), (9, 9), (8, 8), (7, 7),
            (7, 6), (8, 5), (9, 4)]
    for i, (x, y) in enumerate(path):
        put(px, x, y, rng, root if i % 3 else root_dark, 5)
    put(px, 6, 12, rng, root_dark, 5)  # side rootlets
    put(px, 10, 8, rng, root_dark, 5)
    for (x, y) in ((7, 11), (9, 6), (8, 4)):  # amber nodules
        put(px, x, y, rng, amber, 5)
    for (x, y) in ((8, 12), (8, 6)):
        put(px, x, y, rng, amber_deep, 5)
    return img


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    out = {
        # solids
        "runestone.png": runestone(),
        "voidglass.png": voidglass(),
        "luster_crystal.png": facets(0xEC59_0020, (74, 196, 178), (48, 148, 134),
                                     (150, 240, 226), (222, 255, 248)),
        "peat_block.png": peat_block(),
        "scoria.png": scoria(),
        "frost_crystal.png": facets(0xEC59_0021, (168, 214, 240), (122, 172, 210),
                                    (214, 240, 252), (245, 252, 255)),
        "echo_crystal.png": facets(0xEC59_0022, (24, 38, 66), (14, 24, 44),
                                   (52, 84, 118), (96, 208, 200), band=4),
        "sculk_gleam.png": sculk_gleam(),
        # plants
        "withered_sunflower.png": withered_sunflower(),
        "voidbloom.png": glow_plant(0xEC59_0030, (52, 44, 66), (38, 32, 50),
                                    (128, 74, 178), (170, 118, 216), (230, 196, 255),
                                    mushroom=False),
        "prism_sprouts.png": blades(0xEC59_0031, (44, 128, 116), (86, 196, 178),
                                    (140, 232, 216), (216, 255, 246)),
        "wisp_cap.png": glow_plant(0xEC59_0032, (140, 148, 152), (112, 120, 126),
                                   (172, 208, 224), (208, 234, 244), (246, 254, 255)),
        "lumishroom.png": glow_plant(0xEC59_0033, (96, 130, 96), (74, 104, 76),
                                     (94, 226, 148), (150, 248, 190), (226, 255, 236)),
        "amber_tendril.png": amber_tendril(),
        "emberbloom.png": glow_plant(0xEC59_0034, (72, 46, 34), (54, 34, 26),
                                     (226, 96, 34), (248, 152, 56), (255, 224, 130),
                                     mushroom=False),
    }
    for name, img in out.items():
        path = ROOT / name
        img.save(path)
        print(f"wrote {path.relative_to(ROOT.parents[4])}")


if __name__ == "__main__":
    main()
