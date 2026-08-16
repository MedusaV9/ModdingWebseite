#!/usr/bin/env python3
"""Generate EARLY can label textures (one PNG per flavor).

Deterministic: no randomness, fixed fonts (DejaVu Sans Bold), fixed layout.

The label wraps 360deg around the can:
  u (width)  = circumference (slim can, d=66mm -> ~207mm)
  v (height) = label height  (~136mm of the 168mm can)
Canvas 2048x1344 keeps pixels square in physical space.
Front of the can is centered at x = W/2.

Layout (matching drinkearly.com reference shots):
  - top band text "VITAMINE * ELEKTROLYTE" repeating around the can
  - huge "EARLY" wordmark rotated 90deg CCW (reads bottom-to-top, E at bottom)
  - thin-line fruit icon below the wordmark
  - "SPARKLING / VITAMIN / DRINK" (three lines, letterspaced)
  - thin rule, flavor name, "HYDRATION WITH BENEFITS", magnesium fine print
"""

import os

from PIL import Image, ImageDraw, ImageFont

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_BOOK = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

W, H = 2048, 1344
FRONT_X = W // 2
WHITE = (255, 255, 255, 255)

FLAVORS = {
    "peach": {
        "bg": "#E7B7B7",
        "name": "WEISSER PFIRSICH",  # Doppel-S: kein Eszett in Versalien
        "icon": "peach",
    },
    "grapefruit": {
        "bg": "#F2AC8F",
        "name": "GRAPEFRUIT",
        "icon": "grapefruit",
    },
    "lemonmint": {
        "bg": "#CBD97A",
        "name": "ZITRONE-MINZE",
        "icon": "lemonmint",
    },
}


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4)) + (255,)


def tracked_size(text, font, tracking):
    w = 0.0
    for ch in text:
        w += font.getlength(ch) + tracking
    return w - tracking if text else 0.0


def draw_tracked(draw, cx, y, text, font, tracking, fill=WHITE, anchor_mid=True):
    """Draw letterspaced text; (cx, y) is top-center if anchor_mid else top-left."""
    total = tracked_size(text, font, tracking)
    x = cx - total / 2.0 if anchor_mid else cx
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += font.getlength(ch) + tracking
    return total


def make_wordmark(target_h, target_w):
    """Horizontal 'EARLY', letterspaced, rotated 90deg CCW.

    Returns an RGBA image target_w wide x target_h tall (E at the bottom).
    """
    fs = 400
    font = ImageFont.truetype(FONT_BOLD, fs)
    tracking = fs * 0.06
    text = "EARLY"
    tw = int(tracked_size(text, font, tracking)) + 20
    th = int(fs * 1.3)
    img = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_tracked(d, 10, int(fs * 0.05), text, font, tracking, anchor_mid=False)
    img = img.crop(img.getbbox())
    # fit into (target_h wide x target_w tall) before rotation
    img = img.resize((target_h, target_w), Image.LANCZOS)
    return img.transpose(Image.ROTATE_90)


# ---------------------------------------------------------------- icons ----
# All icons drawn white thin-line at 4x supersample, then downscaled.

SS = 4  # supersample factor


def _icon_canvas(size):
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img), s


def _leaf(d, cx, cy, rx, ry, angle_deg, width):
    """Pointed-oval leaf via two arcs, approximated with line segments."""
    import math

    pts_top = []
    pts_bot = []
    steps = 24
    for i in range(steps + 1):
        t = -1.0 + 2.0 * i / steps  # -1..1 along the leaf axis
        x = t * rx
        bulge = (1.0 - t * t) ** 0.7 * ry
        pts_top.append((x, -bulge))
        pts_bot.append((x, bulge))
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)

    def rot(p):
        return (cx + p[0] * ca - p[1] * sa, cy + p[0] * sa + p[1] * ca)

    d.line([rot(p) for p in pts_top], fill=WHITE, width=width, joint="curve")
    d.line([rot(p) for p in pts_bot], fill=WHITE, width=width, joint="curve")
    # center vein
    d.line([rot((-rx * 0.8, 0)), rot((rx * 0.8, 0))], fill=WHITE, width=max(2, width // 2))


def icon_peach(size):
    img, d, s = _icon_canvas(size)
    lw = int(s * 0.045)
    m = s * 0.16
    # body: circle with a slight top notch (two overlapping arcs)
    d.arc([m, m + s * 0.06, s - m, s - m + s * 0.02], start=-58, end=245, fill=WHITE, width=lw)
    # cleft crease: arc from top notch down the right side
    d.arc([s * 0.42, m + s * 0.02, s * 1.05, s * 0.96], start=140, end=225, fill=WHITE, width=lw)
    # stem
    d.line([(s * 0.5, m + s * 0.08), (s * 0.53, m - s * 0.04)], fill=WHITE, width=lw)
    # leaf
    _leaf(d, s * 0.66, m - s * 0.02, s * 0.14, s * 0.05, -20, lw)
    return img.resize((size, size), Image.LANCZOS)


def icon_grapefruit(size):
    import math

    img, d, s = _icon_canvas(size)
    lw = int(s * 0.045)
    m = s * 0.17
    cx = cy = s * 0.52
    r = (s - 2 * m) / 2
    # whole-fruit outline
    d.arc([cx - r, cy - r, cx + r, cy + r], start=0, end=360, fill=WHITE, width=lw)
    # inner rim (slice cross-section)
    ir = r * 0.78
    d.arc([cx - ir, cy - ir, cx + ir, cy + ir], start=25, end=155, fill=WHITE, width=lw)
    # radiating segment lines in the lower half (fan)
    for ang in (40, 68, 90, 112, 140):
        a = math.radians(ang)
        x1 = cx + math.cos(a) * ir * 0.15
        y1 = cy + math.sin(a) * ir * 0.15
        x2 = cx + math.cos(a) * ir * 0.92
        y2 = cy + math.sin(a) * ir * 0.92
        d.line([(x1, y1), (x2, y2)], fill=WHITE, width=lw)
    # small stem + leaf top right
    d.line([(cx + r * 0.1, cy - r), (cx + r * 0.16, cy - r * 1.22)], fill=WHITE, width=lw)
    _leaf(d, cx + r * 0.52, cy - r * 1.18, s * 0.13, s * 0.045, -18, lw)
    return img.resize((size, size), Image.LANCZOS)


def icon_lemonmint(size):
    import math

    img, d, s = _icon_canvas(size)
    lw = int(s * 0.045)
    # lemon wedge (half slice), tilted
    cx, cy = s * 0.40, s * 0.52
    r = s * 0.34
    tilt = -28
    a0, a1 = tilt, tilt + 180
    d.arc([cx - r, cy - r, cx + r, cy + r], start=a0, end=a1, fill=WHITE, width=lw)
    # flat cut edge
    p0 = (cx + math.cos(math.radians(a0)) * r, cy + math.sin(math.radians(a0)) * r)
    p1 = (cx + math.cos(math.radians(a1)) * r, cy + math.sin(math.radians(a1)) * r)
    d.line([p0, p1], fill=WHITE, width=lw)
    # inner rim
    ir = r * 0.78
    d.arc([cx - ir, cy - ir, cx + ir, cy + ir], start=a0 + 8, end=a1 - 8, fill=WHITE, width=lw)
    # segments
    for f in (0.22, 0.5, 0.78):
        ang = math.radians(a0 + 180 * f)
        d.line(
            [
                (cx + math.cos(ang) * ir * 0.12, cy + math.sin(ang) * ir * 0.12),
                (cx + math.cos(ang) * ir * 0.9, cy + math.sin(ang) * ir * 0.9),
            ],
            fill=WHITE,
            width=lw,
        )
    # mint sprig right: stem + 3 leaves
    sx, sy = s * 0.78, s * 0.30
    d.line([(sx, sy), (sx - s * 0.06, sy + s * 0.42)], fill=WHITE, width=lw)
    _leaf(d, sx + s * 0.02, sy + s * 0.03, s * 0.11, s * 0.045, -55, lw)
    _leaf(d, sx - s * 0.115, sy + s * 0.17, s * 0.10, s * 0.04, 15, lw)
    _leaf(d, sx + s * 0.055, sy + s * 0.24, s * 0.10, s * 0.04, -10, lw)
    return img.resize((size, size), Image.LANCZOS)


ICONS = {"peach": icon_peach, "grapefruit": icon_grapefruit, "lemonmint": icon_lemonmint}


# ---------------------------------------------------------------- label ----

def build_label(flavor_key, spec, out_path):
    img = Image.new("RGBA", (W, H), hex_rgb(spec["bg"]))
    d = ImageDraw.Draw(img)

    # --- top band, repeating around the whole can ---
    f_band = ImageFont.truetype(FONT_BOLD, 30)
    band_unit = "VITAMINE  \u2022  ELEKTROLYTE  \u2022  "
    tracking_band = 7
    unit_w = tracked_size(band_unit, f_band, tracking_band) + tracking_band
    # start so that a unit boundary sits at the front center
    x = FRONT_X - unit_w * ((FRONT_X // unit_w) + 1)
    y_band = 34
    while x < W:
        draw_tracked(d, x, y_band, band_unit, f_band, tracking_band, anchor_mid=False)
        x += unit_w

    # --- huge rotated EARLY wordmark (left-ish on the front) ---
    wm_h, wm_w = 640, 188  # tall x wide on the label
    wm = make_wordmark(wm_h, wm_w)
    wm_cx = FRONT_X - 60
    img.alpha_composite(wm, (int(wm_cx - wm_w / 2), 108))

    # --- fruit icon (center-right on the front, below the wordmark) ---
    icon_size = 170
    icon = ICONS[spec["icon"]](icon_size)
    icon_cx = FRONT_X + 26
    img.alpha_composite(icon, (int(icon_cx - icon_size / 2), 778))

    # --- SPARKLING / VITAMIN / DRINK ---
    f_mid = ImageFont.truetype(FONT_BOLD, 38)
    y = 972
    for line in ("SPARKLING", "VITAMIN", "DRINK"):
        draw_tracked(d, FRONT_X, y, line, f_mid, 13)
        y += 50

    # --- thin rule ---
    d.line([(FRONT_X - 150, 1136), (FRONT_X + 150, 1136)], fill=WHITE, width=2)

    # --- flavor name ---
    f_name = ImageFont.truetype(FONT_BOLD, 43)
    draw_tracked(d, FRONT_X, 1152, spec["name"], f_name, 7)

    # --- HYDRATION WITH BENEFITS ---
    f_sub = ImageFont.truetype(FONT_BOLD, 21)
    draw_tracked(d, FRONT_X, 1216, "HYDRATION WITH BENEFITS", f_sub, 8)

    # --- magnesium fine print (wraps a bit around the curve; fine for print) ---
    f_fine = ImageFont.truetype(FONT_BOOK, 15)
    draw_tracked(
        d, FRONT_X, 1258,
        "MAGNESIUM TR\u00c4GT ZUM ELEKTROLYTGLEICHGEWICHT BEI",
        f_fine, 1,
    )

    img.convert("RGB").save(out_path, "PNG")
    print(f"wrote {out_path}")


def main():
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "labels")
    os.makedirs(out_dir, exist_ok=True)
    for key, spec in FLAVORS.items():
        build_label(key, spec, os.path.join(out_dir, f"early_label_{key}.png"))


if __name__ == "__main__":
    main()
