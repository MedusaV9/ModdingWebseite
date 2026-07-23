#!/usr/bin/env python3
"""Generate the 16x16 purple Display Wand item texture."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "src/main/resources/assets/eclipse/textures/item/display_wand.png"


def main() -> None:
    image = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    pixels = image.load()

    outline = (35, 18, 55, 255)
    shaft_dark = (92, 48, 139, 255)
    shaft = (151, 86, 214, 255)
    highlight = (220, 170, 255, 255)
    crystal = (184, 92, 255, 255)
    crystal_light = (244, 214, 255, 255)

    # Diagonal handle.
    for x, y in ((3, 13), (4, 12), (5, 11), (6, 10), (7, 9), (8, 8), (9, 7), (10, 6)):
        pixels[x - 1, y] = outline
        pixels[x, y + 1] = outline
        pixels[x, y] = shaft
        if x % 2 == 0:
            pixels[x, y] = highlight
        pixels[x + 1, y - 1] = shaft_dark

    # Faceted amethyst display crystal.
    for x, y in ((10, 2), (11, 1), (12, 2), (9, 3), (10, 3), (11, 3),
                 (12, 3), (13, 3), (10, 4), (11, 4), (12, 4), (11, 5)):
        pixels[x, y] = outline
    for x, y in ((11, 2), (10, 3), (11, 3), (12, 3), (11, 4)):
        pixels[x, y] = crystal
    pixels[11, 2] = crystal_light
    pixels[10, 3] = highlight

    # Small animation sparkle.
    for x, y in ((5, 3), (4, 4), (5, 4), (6, 4), (5, 5)):
        pixels[x, y] = crystal_light if (x, y) == (5, 4) else crystal

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT, optimize=True)
    print(OUTPUT)


if __name__ == "__main__":
    main()
