#!/usr/bin/env python3
"""Erzeugt die 16x16-Textur der Gooby-Pfeife (goldene Hundepfeife mit
Kordel und rosa Fussel-Anhaenger).

Aufruf:  python3 scripts/gen_whistle_texture.py
"""
import os

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "src", "main", "resources", "assets", "goobymod",
                   "textures", "item", "gooby_whistle.png")

GOLD = (246, 200, 74, 255)
GOLD_DARK = (196, 148, 38, 255)
GOLD_LIGHT = (255, 236, 150, 255)
STRING = (129, 88, 54, 255)
PINK = (245, 169, 196, 255)
PINK_DARK = (219, 130, 164, 255)
HOLE = (74, 52, 18, 255)


def px(img, x, y, c):
    if 0 <= x < 16 and 0 <= y < 16:
        img.putpixel((x, y), c)


def main():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))

    # Kordel (diagonal, oben links)
    for i, (x, y) in enumerate([(2, 2), (3, 3), (3, 4), (4, 5)]):
        px(img, x, y, STRING)
    # Fussel-Pompon am Kordel-Ende
    for x, y in [(1, 1), (2, 1), (1, 2)]:
        px(img, x, y, PINK)
    px(img, 2, 2, PINK_DARK)

    # Pfeifen-Koerper (rundlicher Block unten rechts)
    for y in range(6, 12):
        for x in range(4, 13):
            px(img, x, y, GOLD)
    # Mundstueck (schmaler Fortsatz oben rechts am Koerper)
    for x in range(10, 14):
        px(img, x, 5, GOLD)
    px(img, 13, 6, GOLD)
    # Kugel-Kammer unten
    for y in range(11, 14):
        for x in range(6, 11):
            px(img, x, y, GOLD)

    # Schattierung: untere/rechte Kanten dunkler
    for x in range(4, 13):
        px(img, x, 11, GOLD_DARK)
    for y in range(6, 12):
        px(img, 12, y, GOLD_DARK)
    for x in range(6, 11):
        px(img, x, 13, GOLD_DARK)
    # Highlights oben links
    for x in range(4, 9):
        px(img, x, 6, GOLD_LIGHT)
    for y in range(6, 10):
        px(img, 4, y, GOLD_LIGHT)

    # Pfeifen-Loch
    px(img, 8, 8, HOLE)
    px(img, 9, 8, HOLE)
    px(img, 8, 9, HOLE)
    px(img, 9, 9, HOLE)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print("Textur geschrieben:", OUT)


if __name__ == "__main__":
    main()
