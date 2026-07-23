#!/usr/bin/env python3
"""Generate P4-B8's three 16x16 dark-gothic item sprites.

The shapes are hand-authored pixel art (no noise/random fill):
  * heart_extractor: violet claw-and-syringe/talon device (repainted in the
    WB-ART pass on the shared `eclipse_palette` ramp + finish pass — the
    original claw tangle did not read at 16px)
  * glitch_shard: fractured magenta crystal with a hot glitch seam
  * heart_fragment: a jagged quarter of a crimson heart

Run from anywhere:
    python3 scripts/item_art/gen_b8_items.py
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eclipse_palette as ep  # noqa: E402

SIZE = 16
OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item"
)

TRANSPARENT = (0, 0, 0, 0)
INK = (22, 9, 31, 255)
DEEP_PURPLE = (52, 20, 73, 255)
PURPLE = (104, 42, 134, 255)
LILAC = (194, 119, 232, 255)
PALE = (229, 194, 244, 255)
CRIMSON_DARK = (82, 12, 34, 255)
CRIMSON = (166, 25, 58, 255)
SCARLET = (231, 55, 83, 255)
PINK = (255, 126, 167, 255)
MAGENTA = (215, 33, 193, 255)
HOT_MAGENTA = (255, 91, 228, 255)
GLITCH_BLUE = (94, 224, 255, 255)
STEEL = (114, 112, 132, 255)
STEEL_LIGHT = (201, 195, 219, 255)


def blank() -> Image.Image:
    return Image.new("RGBA", (SIZE, SIZE), TRANSPARENT)


def heart_extractor() -> Image.Image:
    """WB-ART repaint: syringe barrel on the diagonal, three distinct claw
    prongs at the head (1px gaps so the outline pass separates them), crimson
    blood chamber, steel T-plunger at the foot."""
    img = ep.canvas()

    # Claw head joint.
    ep.put(img, ((4, 4), (5, 4), (4, 5), (5, 5)), ep.PURPLE_MID)
    # Three grasping prongs with hooked tips.
    ep.put(img, ((3, 3), (2, 2), (1, 1), (1, 2)), ep.PURPLE_MID)      # upper-left
    ep.put(img, ((3, 5), (2, 5), (1, 4), (1, 3)), ep.PURPLE_DARK)     # left
    ep.put(img, ((5, 3), (5, 2), (6, 1), (7, 1)), ep.PURPLE_DARK)     # up
    ep.put(img, ((1, 1), (6, 1), (1, 3)), ep.ACCENT_DEEP)             # lit tips

    # Barrel: 3px diagonal band from the claw joint to the plunger.
    for i in range(7):
        ep.put(img, ((6 + i, 4 + i),), ep.ACCENT_DEEP)    # lit upper edge
        ep.put(img, ((5 + i, 5 + i),), ep.PURPLE_MID)     # core
        ep.put(img, ((4 + i, 6 + i),), ep.PURPLE_DARK)    # shadowed lower edge

    # Blood chamber riding the barrel core.
    ep.put(img, ((7, 7), (8, 7), (7, 8), (8, 8), (9, 8), (8, 9), (9, 9)), ep.CRIMSON)
    ep.put(img, ((8, 8), (9, 9)), ep.SCARLET)

    # Steel T-plunger.
    ep.put(img, ((11, 14), (12, 13), (13, 12), (14, 11)), ep.DIM)
    ep.put(img, ((12, 14), (13, 13), (14, 12)), ep.HAIRLINE)
    ep.put(img, ((14, 14),), ep.DIM)

    ep.finish(img)
    ep.put(img, ((7, 7),), ep.GLOW_WHITE)     # chamber glint
    ep.put(img, ((2, 4),), ep.GLOW_MAGENTA)   # charge between the claws
    return img


def glitch_shard() -> Image.Image:
    img = blank()
    d = ImageDraw.Draw(img)

    # Violet aura pixels deliberately offset like a broken sprite.
    for x, y in ((2, 4), (13, 3), (1, 10), (14, 9), (4, 14), (12, 13)):
        d.point((x, y), fill=PURPLE)
    for x, y in ((1, 5), (14, 4), (2, 11), (13, 10)):
        d.point((x, y), fill=HOT_MAGENTA)

    # Main faceted crystal and two splinters.
    d.polygon([(7, 1), (12, 4), (13, 9), (8, 15), (3, 11), (4, 5)], fill=INK)
    d.polygon([(7, 2), (10, 4), (8, 8), (5, 5)], fill=MAGENTA)
    d.polygon([(10, 4), (12, 5), (12, 8), (8, 8)], fill=DEEP_PURPLE)
    d.polygon([(5, 5), (8, 8), (7, 13), (4, 10)], fill=PURPLE)
    d.polygon([(8, 8), (12, 8), (8, 14), (7, 13)], fill=CRIMSON)

    # Fracture seam: hot pink core with one impossible cyan glitch pixel.
    d.line([(8, 2), (7, 6), (9, 8), (7, 11), (8, 14)], fill=HOT_MAGENTA, width=1)
    d.point((8, 7), fill=PALE)
    d.point((9, 8), fill=GLITCH_BLUE)
    d.point((6, 5), fill=PINK)

    d.polygon([(2, 7), (4, 6), (3, 9)], fill=INK)
    d.polygon([(3, 7), (4, 7), (3, 8)], fill=HOT_MAGENTA)
    d.polygon([(12, 11), (15, 12), (12, 13)], fill=INK)
    d.line([(12, 12), (14, 12)], fill=GLITCH_BLUE, width=1)
    return img


def heart_fragment() -> Image.Image:
    img = blank()
    d = ImageDraw.Draw(img)

    # A single rounded heart lobe tapering to a point, with a torn zig-zag right edge.
    outline = [
        (3, 3), (5, 1), (8, 1), (10, 3), (10, 5),
        (8, 6), (10, 8), (7, 9), (8, 11), (5, 14),
        (2, 10), (1, 6), (2, 4),
    ]
    d.polygon(outline, fill=INK)
    fill = [
        (4, 3), (5, 2), (8, 2), (9, 3), (9, 4),
        (7, 6), (9, 8), (6, 9), (7, 11), (5, 13),
        (3, 10), (2, 6), (3, 4),
    ]
    d.polygon(fill, fill=CRIMSON)

    # Lobe light, deep lower volume, and exposed violet fracture.
    d.polygon([(4, 3), (6, 2), (8, 3), (7, 5), (4, 6), (3, 5)], fill=SCARLET)
    d.line([(3, 8), (5, 12)], fill=CRIMSON_DARK, width=2)
    d.point((4, 3), fill=PINK)
    d.line([(9, 4), (7, 6), (9, 8), (6, 9), (7, 11)], fill=LILAC, width=1)
    d.point((10, 4), fill=HOT_MAGENTA)
    d.point((10, 8), fill=HOT_MAGENTA)
    d.point((8, 11), fill=PURPLE)

    # Two suspended blood/glitch motes sell the freshly torn silhouette.
    d.point((11, 6), fill=SCARLET)
    d.point((12, 7), fill=CRIMSON_DARK)
    d.point((10, 12), fill=PURPLE)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    sprites = {
        "heart_extractor.png": heart_extractor(),
        "glitch_shard.png": glitch_shard(),
        "heart_fragment.png": heart_fragment(),
    }
    for name, image in sprites.items():
        assert image.mode == "RGBA" and image.size == (SIZE, SIZE)
        assert image.getbbox() is not None
        path = OUT / name
        image.save(path, optimize=False)
        print(f"wrote {path.relative_to(Path(__file__).resolve().parents[2])}")


if __name__ == "__main__":
    main()
