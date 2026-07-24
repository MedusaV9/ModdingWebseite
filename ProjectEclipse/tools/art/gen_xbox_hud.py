#!/usr/bin/env python3
"""C17 — procedurally generate the classic (console-era) HUD skin textures.

Outputs (deterministic; re-runs are byte-identical):
  src/main/resources/assets/eclipse/textures/gui/xbox/hotbar_classic.png (182x22)
  src/main/resources/assets/eclipse/textures/gui/xbox/hotbar_selection_classic.png (24x23)
  src/main/resources/assets/eclipse/textures/gui/xbox/heart_container_classic.png (9x9)
  src/main/resources/assets/eclipse/textures/gui/xbox/heart_full_classic.png (9x9)
  src/main/resources/assets/eclipse/textures/gui/xbox/heart_half_classic.png (9x9)

Consumed by client/xbox/XboxHudSkin.java (dimension-gated HUD swap). All art is an
ORIGINAL procedural recreation of the era LOOK (gray translucent hotbar, chunky
red hearts) — no Mojang texture bytes are copied (docs/XBOX_WORLDS.md provenance).
"""

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(
    HERE, "..", "..", "src/main/resources/assets/eclipse/textures/gui/xbox"))

# Classic gray hotbar palette (era look: dark translucent body, light gray bevel).
EDGE_DARK = (0, 0, 0, 220)
BEVEL_LIGHT = (140, 140, 140, 255)
BEVEL_DIM = (85, 85, 85, 255)
BODY = (30, 30, 30, 175)
SLOT_SEP = (60, 60, 60, 200)

SEL_WHITE = (255, 255, 255, 255)
SEL_SHADOW = (120, 120, 120, 255)

# Chunky classic heart palette.
H_RED = (255, 48, 48, 255)
H_RED_DARK = (168, 8, 8, 255)
H_RED_LIGHT = (255, 120, 120, 255)
H_OUTLINE = (25, 0, 0, 255)
C_BG = (55, 55, 55, 255)
C_BEVEL = (110, 110, 110, 255)
C_OUTLINE = (0, 0, 0, 255)
CLEAR = (0, 0, 0, 0)


def px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c)


def hotbar() -> Image.Image:
    w, h = 182, 22
    im = Image.new("RGBA", (w, h), BODY)
    # outer 1px dark edge
    for x in range(w):
        px(im, x, 0, EDGE_DARK)
        px(im, x, h - 1, EDGE_DARK)
    for y in range(h):
        px(im, 0, y, EDGE_DARK)
        px(im, w - 1, y, EDGE_DARK)
    # inner bevel: light on top/left, dim on bottom/right (classic inset look)
    for x in range(1, w - 1):
        px(im, x, 1, BEVEL_DIM)
        px(im, x, h - 2, BEVEL_LIGHT)
    for y in range(1, h - 1):
        px(im, 1, y, BEVEL_DIM)
        px(im, w - 2, y, BEVEL_LIGHT)
    # slot separators every 20px (9 slots of 20px + 1px borders)
    for slot in range(1, 9):
        x = slot * 20
        for y in range(1, h - 1):
            px(im, x, y, SLOT_SEP)
    return im


def selection() -> Image.Image:
    w, h = 24, 23
    im = Image.new("RGBA", (w, h), CLEAR)
    # 2px white frame with a 1px gray drop shadow inside-bottom (classic pop)
    for t in (0, 1):
        for x in range(w):
            px(im, x, t, SEL_WHITE)
            px(im, x, h - 1 - t, SEL_WHITE)
        for y in range(h):
            px(im, t, y, SEL_WHITE)
            px(im, w - 1 - t, y, SEL_WHITE)
    for x in range(2, w - 2):
        px(im, x, h - 3, SEL_SHADOW)
    for y in range(2, h - 2):
        px(im, w - 3, y, SEL_SHADOW)
    return im


# 9x9 heart shape mask (the chunky pre-flattening silhouette).
HEART_MASK = [
    "..XX.XX..",
    ".XXXXXXX.",
    ".XXXXXXX.",
    ".XXXXXXX.",
    "..XXXXX..",
    "...XXX...",
    "....X....",
    ".........",
    ".........",
]


def heart_base(fill, dark, light) -> Image.Image:
    im = Image.new("RGBA", (9, 9), CLEAR)
    for y, row in enumerate(HEART_MASK):
        for x, c in enumerate(row):
            if c != "X":
                continue
            im.putpixel((x, y), fill)
    # outline: any filled pixel adjacent to empty becomes outline
    out = im.copy()
    for y in range(9):
        for x in range(9):
            if im.getpixel((x, y))[3] == 0:
                continue
            edge = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx > 8 or ny > 8 or im.getpixel((nx, ny))[3] == 0:
                    edge = True
            if edge:
                out.putpixel((x, y), H_OUTLINE if fill == H_RED else C_OUTLINE)
    # shading: darker lower-right, light glint upper-left
    for y in range(9):
        for x in range(9):
            c = out.getpixel((x, y))
            if c == fill:
                if y >= 4 or (x >= 6 and y >= 3):
                    out.putpixel((x, y), dark)
    if fill == H_RED:
        out.putpixel((3, 2), light)
        out.putpixel((2, 2), light)
    return out


def half_heart(full: Image.Image, container: Image.Image) -> Image.Image:
    im = container.copy()
    for y in range(9):
        for x in range(0, 5):
            c = full.getpixel((x, y))
            if c[3] != 0:
                im.putpixel((x, y), c)
    return im


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    files = {
        "hotbar_classic.png": hotbar(),
        "hotbar_selection_classic.png": selection(),
    }
    container = heart_base(C_BG, C_BG, C_BEVEL)
    # container bevel glint
    container.putpixel((3, 2), C_BEVEL)
    full = heart_base(H_RED, H_RED_DARK, H_RED_LIGHT)
    files["heart_container_classic.png"] = container
    files["heart_full_classic.png"] = full
    files["heart_half_classic.png"] = half_heart(full, container)
    for name, im in sorted(files.items()):
        path = os.path.join(OUT, name)
        im.save(path, optimize=True)
        print("wrote", path, im.size)


if __name__ == "__main__":
    main()
