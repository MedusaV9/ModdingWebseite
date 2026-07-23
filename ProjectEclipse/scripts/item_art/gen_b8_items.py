#!/usr/bin/env python3
"""Generate P4-B8's three 16x16 dark-gothic item sprites.

The shapes are hand-authored pixel art (no noise/random fill):
  * heart_extractor: violet claw-and-syringe/talon device
  * glitch_shard: fractured magenta crystal with a hot glitch seam
  * heart_fragment: a jagged quarter of a crimson heart

Run from anywhere:
    python3 scripts/item_art/gen_b8_items.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

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
    img = blank()
    d = ImageDraw.Draw(img)

    # Three hooked extraction claws, each inked then highlighted.
    claws = [
        [(5, 6), (2, 5), (1, 2), (2, 1)],
        [(6, 5), (5, 2), (6, 0), (7, 1)],
        [(7, 6), (9, 3), (10, 2), (10, 4)],
    ]
    for points in claws:
        d.line(points, fill=INK, width=3, joint="curve")
        d.line(points, fill=PURPLE, width=1)
    d.point((2, 1), fill=PALE)
    d.point((6, 0), fill=PALE)
    d.point((10, 2), fill=PALE)

    # Heavy diagonal body.
    body = [(4, 5), (6, 3), (13, 10), (11, 13)]
    d.polygon(body, fill=INK)
    d.polygon([(5, 5), (6, 4), (12, 10), (11, 12)], fill=DEEP_PURPLE)
    d.line([(6, 5), (11, 10)], fill=LILAC, width=1)

    # Blood chamber and metal braces.
    d.polygon([(6, 7), (7, 6), (10, 9), (9, 10)], fill=CRIMSON_DARK)
    d.line([(7, 7), (9, 9)], fill=SCARLET, width=2)
    d.point((7, 7), fill=PINK)
    d.line([(4, 7), (7, 4)], fill=STEEL_LIGHT, width=1)
    d.line([(10, 13), (13, 10)], fill=STEEL, width=2)

    # Plunger pommel and a long hooked syringe/talon tip.
    d.polygon([(10, 12), (12, 10), (15, 13), (13, 15)], fill=INK)
    d.polygon([(12, 11), (14, 13), (13, 14), (11, 12)], fill=PURPLE)
    d.line([(11, 9), (14, 6), (15, 3)], fill=INK, width=2)
    d.line([(12, 9), (14, 7), (15, 3)], fill=STEEL_LIGHT, width=1)
    d.point((15, 3), fill=PALE)

    # Tiny gothic rivets.
    d.point((5, 5), fill=PALE)
    d.point((11, 11), fill=LILAC)
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
