#!/usr/bin/env python3
"""C17 — procedurally recreate the three "most-wrong" classic textures in the
X360-era look: grass_block_side, cobblestone, oak_planks (plan C17 fix 7).

The imported MIT pack ("Minecraft: Classic Edition" by JS03) targets the 2009
Classic look; the Xbox-360 tutorial worlds shipped the pre-1.14 era art. These
three read most wrong in the baked worlds, so they are replaced with ORIGINAL
deterministic procedural recreations of the era LOOK (no Mojang texture bytes
are copied — the era palette is described numerically below). Everything else
stays from the MIT pack; a true 1:1 needs the user's own legacy pack (see
docs/XBOX_WORLDS.md).

Outputs (seeded, byte-identical on re-run):
  src/main/resources/assets/eclipse/textures/block/classic/grass_block_side.png
  src/main/resources/assets/eclipse/textures/block/classic/cobblestone.png
  src/main/resources/assets/eclipse/textures/block/classic/oak_planks.png
and updates tools/classicblocks/provenance.json (op: "procedural era recreation").
"""

import json
import os
import random

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(
    HERE, "..", "..", "src/main/resources/assets/eclipse/textures/block/classic"))
PROVENANCE = os.path.join(HERE, "provenance.json")

SEED = 0xC17


def clamp(v):
    return max(0, min(255, int(v)))


def shade(color, mul):
    return tuple(clamp(c * mul) for c in color[:3]) + (255,)


def grass_block_side() -> Image.Image:
    """Era look: warm dirt body, irregular 2-4px bright green fringe hanging
    over the top edge (the pre-1.14 side had a hard, uneven grass lip)."""
    rng = random.Random(SEED + 1)
    dirt = (134, 96, 67)
    grass = (94, 157, 52)
    im = Image.new("RGBA", (16, 16))
    for y in range(16):
        for x in range(16):
            n = rng.random()
            if n < 0.18:
                c = shade(dirt, 0.72)   # dark pebbles
            elif n < 0.40:
                c = shade(dirt, 0.88)
            elif n < 0.55:
                c = shade(dirt, 1.12)   # light sand specks
            else:
                c = shade(dirt, 1.0)
            im.putpixel((x, y), c)
    # irregular grass lip: per-column depth 2..4, brighter at the very top
    rng2 = random.Random(SEED + 2)
    for x in range(16):
        depth = 2 + (0 if rng2.random() < 0.45 else 1) + (1 if rng2.random() < 0.25 else 0)
        for y in range(depth):
            mul = 1.12 if y == 0 else (1.0 if y == 1 else 0.86)
            im.putpixel((x, y), shade(grass, mul * (0.92 + rng2.random() * 0.16)))
        # occasional single-pixel grass drip one deeper
        if rng2.random() < 0.2 and depth < 5:
            im.putpixel((x, depth), shade(grass, 0.78))
    return im


def cobblestone() -> Image.Image:
    """Era look: big rounded gray stones separated by near-black mortar seams
    (the pre-1.14 cobble had strong value contrast and chunky stones)."""
    rng = random.Random(SEED + 3)
    stone = (127, 127, 127)
    im = Image.new("RGBA", (16, 16))
    # stone cell centers on a jittered 4x4-ish grid (wrapping for tileability);
    # sub-pixel jitter keeps Voronoi seams from collapsing into straight bands
    centers = []
    for gy in range(4):
        for gx in range(4):
            cx = gx * 4 + 0.5 + rng.random() * 3.0
            cy = gy * 4 + 0.5 + rng.random() * 3.0
            centers.append((cx, cy, 0.82 + rng.random() * 0.42))
    for y in range(16):
        for x in range(16):
            # nearest center under torus distance (tileable)
            best, second = None, None
            for cx, cy, lum in centers:
                dx = min(abs(x - cx), 16 - abs(x - cx))
                dy = min(abs(y - cy), 16 - abs(y - cy))
                d = (dx * dx + dy * dy) ** 0.5
                if best is None or d < best[0]:
                    second = best
                    best = (d, lum)
                elif second is None or d < second[0]:
                    second = (d, lum)
            gap = second[0] - best[0]
            if gap < 0.45:  # near-equidistant = 1px mortar seam
                im.putpixel((x, y), shade(stone, 0.55 + rng.random() * 0.06))
            elif gap < 0.95:  # soft shadow ring hugging the seam
                im.putpixel((x, y), shade(stone, best[1] * 0.8))
            else:
                jitter = 0.94 + rng.random() * 0.12
                im.putpixel((x, y), shade(stone, best[1] * jitter))
    return im


def oak_planks() -> Image.Image:
    """Era look: warm golden oak, four 4px plank rows with dark seams and the
    staggered vertical butt-joints (pre-1.14 planks were flat and saturated)."""
    rng = random.Random(SEED + 4)
    wood = (156, 127, 78)
    seam = shade(wood, 0.55)
    im = Image.new("RGBA", (16, 16))
    joint_cols = [12, 4, 8, 0]  # staggered butt joints per row (era layout habit)
    for y in range(16):
        row = y // 4
        for x in range(16):
            if y % 4 == 3:
                c = seam  # horizontal seam line
            elif x == joint_cols[row] and y % 4 != 3:
                c = shade(wood, 0.62)  # vertical butt joint
            else:
                # subtle horizontal grain: per-row banding + light noise
                band = (1.06, 1.0, 0.94)[y % 4 % 3]
                c = shade(wood, band * (0.97 + rng.random() * 0.07))
            im.putpixel((x, y), c)
    return im


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    generated = {
        "grass_block_side.png": grass_block_side(),
        "cobblestone.png": cobblestone(),
        "oak_planks.png": oak_planks(),
    }
    for name, im in sorted(generated.items()):
        path = os.path.join(OUT, name)
        im.save(path, optimize=True)
        print("wrote", path)

    prov = json.load(open(PROVENANCE))
    note = ("X360-era look re-authored procedurally (tools/classicblocks/"
            "procedural_era.py, C17); MIT-pack original replaced — see docs/XBOX_WORLDS.md")
    for entry in prov["textures"]:
        base = os.path.basename(entry["texture"])
        if base in generated:
            entry["op"] = "procedural era recreation"
            entry["source"] = "tools/classicblocks/procedural_era.py"
            entry["note"] = note
    with open(PROVENANCE, "w") as f:
        json.dump(prov, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("provenance updated:", PROVENANCE)


if __name__ == "__main__":
    main()
