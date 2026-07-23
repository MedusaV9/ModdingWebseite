#!/usr/bin/env python3
"""WB-ART shared pixel-art palette + finishing pass for the eclipse item/block set.

Purple ramp constants mirror the frozen "Quiet Eclipse" UI tokens in
`client/handbook/EclipseUiTheme.java` (PANEL #120B1E, PANEL_RAISED #1A1128,
HAIRLINE #2E2347, ACCENT #B98CFF, ACCENT_DEEP #7B4FD0, TEXT #EDE7F8, DIM #9A8FB8,
GOOD #9AF0B0, DANGER #E86078, VEIL #060310) so every icon sits on the same palette
as the UI it is drawn into. Secondary ramps (bone/parchment, herald gold, ferryman
soul-teal, glitch magenta/cyan) are lifted from the committed placeholder art they
replace, so item identity is preserved.

Every painter draws flat mid-tone shapes only, then calls :func:`finish`, which
applies the shared shipped-quality finishing pass:

* 2px black-purple edge: 1px OUTLINE grown outward around the silhouette plus a
  1px darkened inner border on the sprite body,
* 3-tone shading: body pixels adjacent to the top/left edge get a rim light,
  pixels adjacent to the bottom/right edge get a shadow tone,
* glow accents (colors registered in GLOW_COLORS) are left untouched at full
  brightness so 1px magenta/cyan sparks stay crisp.

Deterministic: no randomness anywhere — reruns are byte-identical.
"""

from __future__ import annotations

from PIL import Image

# --- EclipseUiTheme ramp (RGB) ---------------------------------------------
VEIL = (6, 3, 16)          # 0x060310 — near black backdrop
PANEL = (18, 11, 30)       # 0x120B1E — panel fill / our sprite outline ink
PANEL_RAISED = (26, 17, 40)  # 0x1A1128
HAIRLINE = (46, 35, 71)    # 0x2E2347 — deep purple shadow tone
ACCENT_DEEP = (123, 79, 208)  # 0x7B4FD0 — THE purple, pressed
ACCENT = (185, 140, 255)   # 0xB98CFF — THE purple, active
TEXT = (237, 231, 248)     # 0xEDE7F8 — near-white lavender highlight
DIM = (154, 143, 184)      # 0x9A8FB8 — secondary grey-lavender
GOOD = (154, 240, 176)     # 0x9AF0B0 — moss / done ticks
DANGER = (232, 96, 120)    # 0xE86078 — hearts lost

# --- mid ramp helpers (between the frozen tokens) ---------------------------
PURPLE_MID = (86, 55, 140)     # HAIRLINE -> ACCENT_DEEP midpoint body tone
PURPLE_DARK = (58, 40, 96)     # deep body tone (reads as shadowed purple)

# --- secondary material ramps (from the placeholder art being replaced) -----
BONE_DARK = (110, 98, 84)      # parchment/bone shadow
BONE = (201, 188, 164)         # parchment/bone body
BONE_LIGHT = (239, 230, 210)   # parchment/bone light
CRIMSON_DARK = (82, 12, 34)    # vitae / heart shadow (gen_b8_items)
CRIMSON = (166, 25, 58)        # vitae / heart body
SCARLET = (231, 55, 83)        # vitae / heart light
GOLD_DARK = (154, 96, 24)      # herald gold shadow
GOLD = (232, 168, 58)          # herald gold body (0xE8A83A)
GOLD_LIGHT = (255, 216, 106)   # herald gold light (0xFFD86A)
TEAL_DARK = (44, 66, 56)       # ferryman verdigris shadow (0x2C4238)
TEAL = (74, 106, 92)           # ferryman verdigris body (0x4A6A5C)
SOUL_TEAL = (143, 242, 222)    # ferryman soul glow (0x8FF2DE)

# --- 1px glow accents (never shaded / outlined-over by finish()) ------------
GLOW_MAGENTA = (255, 91, 228)  # hot magenta spark (gen_b8_items HOT_MAGENTA)
GLOW_CYAN = (94, 224, 255)     # impossible glitch cyan (gen_b8_items GLITCH_BLUE)
GLOW_WHITE = (247, 240, 255)   # specular star

GLOW_COLORS = {GLOW_MAGENTA, GLOW_CYAN, GLOW_WHITE, SOUL_TEAL, GOLD_LIGHT}

OUTLINE = PANEL  # the "black-purple" of the 2px edge


def rgba(rgb, a=255):
    return (rgb[0], rgb[1], rgb[2], a)


def mul(rgb, factor):
    """Scales an RGB tone, clamped."""
    return tuple(max(0, min(255, int(c * factor))) for c in rgb[:3])


def mix(a, b, t):
    """Linear RGB blend a->b by t in [0, 1]."""
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def canvas(size=16):
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def put(img, xy_iterable, color, a=255):
    """Plots a color at every (x, y) that is inside the canvas."""
    w, h = img.size
    px = img.load()
    col = rgba(color, a) if len(color) == 3 else color
    for x, y in xy_iterable:
        if 0 <= x < w and 0 <= y < h:
            px[x, y] = col


def line_px(x0, y0, x1, y1):
    """Integer Bresenham line as a list of (x, y)."""
    pts = []
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    x, y = x0, y0
    while True:
        pts.append((x, y))
        if x == x1 and y == y1:
            return pts
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x += sx
        if e2 <= dx:
            err += dx
            y += sy


def finish(img, *, outline=OUTLINE, shade=0.66, light=0.42, grow=True):
    """Shared finishing pass: grown outline + inner shade/rim-light 3-tone pass.

    ``grow=True`` adds the 1px outer OUTLINE ring around the painted silhouette
    (shapes should therefore stay inside the 1..14 box). Registered GLOW_COLORS
    pixels are skipped by both passes so accents stay at full brightness.
    """
    w, h = img.size
    px = img.load()

    def solid(x, y):
        return 0 <= x < w and 0 <= y < h and px[x, y][3] >= 128

    if grow:
        ring = []
        for y in range(h):
            for x in range(w):
                if px[x, y][3] < 128 and any(
                        solid(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    ring.append((x, y))
        put(img, ring, outline)

    outline_rgba = rgba(outline)
    body = [(x, y) for y in range(h) for x in range(w)
            if px[x, y][3] >= 128 and px[x, y] != outline_rgba
            and px[x, y][:3] not in GLOW_COLORS]

    def is_edge(x, y):
        return not solid(x, y) or px[x, y] == outline_rgba

    shaded = []
    for x, y in body:
        top_left = is_edge(x, y - 1) or is_edge(x - 1, y)
        bottom_right = is_edge(x, y + 1) or is_edge(x + 1, y)
        base = px[x, y]
        if top_left and not bottom_right:
            shaded.append((x, y, rgba(mix(base[:3], TEXT, light), base[3])))
        elif bottom_right and not top_left:
            shaded.append((x, y, rgba(mul(base[:3], shade), base[3])))
    for x, y, col in shaded:
        px[x, y] = col
    return img


def save(img, path, mode="RGBA"):
    from pathlib import Path

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    out = img if mode == "RGBA" else img.convert(mode)
    out.save(path, optimize=False)
    print(f"wrote {path}")
