#!/usr/bin/env python3
"""Skin v2 "Purple Mythic" generator (P6-W12, plans_v3 P6 §2.7).

Writes three 64x64 RGBA canvases (vanilla WIDE player-skin layout, base + overlay
layers) with byte-for-byte deterministic pixels:

  assets/eclipse/textures/entity/eclipsed_player.png      the uniform player skin
  assets/eclipse/textures/entity/the_other.png            doppelganger derivative
  assets/eclipse/textures/entity/eclipsed_player_glow.png emissive mask (heart+veins+eyes)

Design (frozen palette from the plan sheet): near-black charcoal-violet bodysuit
#1C1826/#241E31 with woven dither; a glowing purple HEART dead-center chest (8x6
rounded diamond, core #E7D6FF, halo #B98CFF); lightning/energy VEINS branching from
the heart across torso -> arms -> legs -> spine (1px mains #B98CFF, forks fading
#6E4DA8, asymmetric left/right); faint glyph collar; hood-like head shading with two
soft glowing eyes #CBB2F2; overlay layer used for the hood rim + floating ember
pixels (alpha). Emissive pixels are ALSO painted bright in the albedo so the skin
reads even without the glow layer (Iris/shaderpack fallback per plan §5).

`the_other.png` applies EXACTLY the two frozen doppelganger deltas over the same
base (spec §1.1, same coordinates as scripts/placeholder_gen/EntitySkinArtist):
pure-black 2x2 eyes (face cols 1-2 / 5-6, rows 11-12) and a faint #8367A8 seam down
face column 3 (rows 8-15), applied to the base face always and to the hat face only
where the hat is opaque.

The glow mask carries alpha-graded pixels for `RenderType.eyes` (translucent-capable):
heart core 255 / halo ~190, vein mains ~235, forks ~140, eyes 255 top / ~110 under-glow.
Everything else fully transparent. AI art may replace any PNG at the same path/size.

Run from the ProjectEclipse root:
    python3 scripts/skin_gen/eclipsed_player_v2.py [--preview <dir>]

--preview additionally writes a scaled mock-render sheet (front/back/side composites,
the_other close-up, glow + simulated night view) to <dir>/skin_v2_preview.png.
"""

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "src/main/resources/assets/eclipse/textures/entity"

SEED = 0x0EC15C1E  # fixed -> byte-identical output every run

# ---------------------------------------------------------------- palette
SUIT_A = 0x1C1826
SUIT_B = 0x241E31
SUIT_DEEP = 0x141020
HOOD_EDGE = 0x34284A
COLLAR = 0x2E2540
GLYPH = 0x6E4DA8
GLYPH_HI = 0x8367A8
HEART_CORE = 0xE7D6FF
HEART_RING = 0xD9BEFF
HEART_HALO = 0xB98CFF
HEART_EDGE = 0x8E63D6
VEIN_MAIN = 0xB98CFF
VEIN_FORK = 0x6E4DA8
VEIN_END = 0x4A3570
VEIN_NODE = 0xE7D6FF
EYE_SOFT = 0xCBB2F2
EYE_HOT = 0xE7D6FF
EYE_UNDER = 0x6E4DA8
SEAM = 0x8367A8  # the_other face seam (frozen)


# ---------------------------------------------------------------- helpers
def hash32(x: int, y: int, salt: int) -> int:
    h = (SEED ^ (x * 0x27D4EB2D) ^ (y * 0x9E3779B9) ^ (salt * 0x85EBCA6B)) & 0xFFFFFFFF
    h ^= h >> 15
    h = (h * 0x2C1B3C6D) & 0xFFFFFFFF
    h ^= h >> 12
    h = (h * 0x297A2D39) & 0xFFFFFFFF
    h ^= h >> 15
    return h


def noise(x: int, y: int, salt: int) -> float:
    return (hash32(x, y, salt) >> 8) / float(1 << 24)


def rgb(c: int):
    return ((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)


def mul(c, f: float):
    r, g, b = c if isinstance(c, tuple) else rgb(c)
    clamp = lambda v: max(0, min(255, int(v)))
    return (clamp(r * f), clamp(g * f), clamp(b * f))


def mix(a, b, t: float):
    ar, ag, ab = a if isinstance(a, tuple) else rgb(a)
    br, bg, bb = b if isinstance(b, tuple) else rgb(b)
    return (int(ar + (br - ar) * t), int(ag + (bg - ag) * t), int(ab + (bb - ab) * t))


class Canvas:
    def __init__(self):
        self.img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        self.px = self.img.load()

    def put(self, x: int, y: int, c, a: int = 255):
        r, g, b = c if isinstance(c, tuple) else rgb(c)
        self.px[x, y] = (r, g, b, a)

    def get(self, x: int, y: int):
        return self.px[x, y]


# Emissive registry: (x, y) -> (color, alpha). Written into the glow mask.
GLOW: dict = {}


def glow(x: int, y: int, c, a: int):
    GLOW[(x, y)] = (c if isinstance(c, tuple) else rgb(c), a)


# ---------------------------------------------------------------- box UV
# Vanilla WIDE-layout boxes: name -> (u, v, w, h, d). Face rects derive exactly like
# the EntitySkinArtist cube() helper (top, bottom, right, front, left, back).
BOXES = {
    "head": (0, 0, 8, 8, 8),
    "hat": (32, 0, 8, 8, 8),
    "body": (16, 16, 8, 12, 4),
    "jacket": (16, 32, 8, 12, 4),
    "arm_r": (40, 16, 4, 12, 4),
    "sleeve_r": (40, 32, 4, 12, 4),
    "arm_l": (32, 48, 4, 12, 4),
    "sleeve_l": (48, 48, 4, 12, 4),
    "leg_r": (0, 16, 4, 12, 4),
    "pant_r": (0, 32, 4, 12, 4),
    "leg_l": (16, 48, 4, 12, 4),
    "pant_l": (0, 48, 4, 12, 4),
}

FACES = ("top", "bottom", "right", "front", "left", "back")


def face_rect(box: str, face: str):
    """(x0, y0, w, h) of a box face on the 64x64 canvas."""
    u, v, w, h, d = BOXES[box]
    return {
        "top": (u + d, v, w, d),
        "bottom": (u + d + w, v, w, d),
        "right": (u, v + d, d, h),
        "front": (u + d, v + d, w, h),
        "left": (u + d + w, v + d, d, h),
        "back": (u + d + w + d, v + d, w, h),
    }[face]


# Mild baked directional light (game lighting still dominates on players).
FACE_SHADE = {"top": 1.14, "bottom": 0.62, "right": 0.92, "front": 1.0, "left": 0.92, "back": 0.86}


def suit_pixel(gx: int, gy: int, salt: int):
    """Charcoal-violet woven bodysuit: two-tone weave + fine dither + rare flecks."""
    band = noise(gx, gy // 2, salt)
    base = SUIT_B if band > 0.55 else SUIT_A
    fine = (noise(gx, gy, salt + 7) - 0.5) * 0.16
    c = mul(base, 1.0 + fine)
    if noise(gx, gy, salt + 13) > 0.965:
        c = mix(c, COLLAR, 0.7)  # mythic weave fleck
    return c


def fill_suit(cv: Canvas, box: str, salt: int, feet_fade: bool = False):
    for f in FACES:
        x0, y0, w, h = face_rect(box, f)
        k = FACE_SHADE[f]
        for fy in range(h):
            for fx in range(w):
                gx, gy = x0 + fx, y0 + fy
                c = mul(suit_pixel(gx, gy, salt), k)
                if feet_fade and f not in ("top", "bottom") and fy >= h - 3:
                    c = mul(c, 0.94 - 0.05 * (fy - (h - 3)))
                cv.put(gx, gy, c)


# ---------------------------------------------------------------- body details
def paint_base_suit(cv: Canvas):
    fill_suit(cv, "head", 21)
    fill_suit(cv, "body", 22)
    fill_suit(cv, "arm_r", 23)
    fill_suit(cv, "arm_l", 24)
    fill_suit(cv, "leg_r", 25, feet_fade=True)
    fill_suit(cv, "leg_l", 26, feet_fade=True)

    # Hood-like head shading: crown/back deepened, brow shadow over the face rows.
    for f in ("top", "right", "left", "back"):
        x0, y0, w, h = face_rect("head", f)
        for fy in range(h):
            for fx in range(w):
                gx, gy = x0 + fx, y0 + fy
                depth = 0.55 if f == "top" else 0.45
                cv.put(gx, gy, mix(cv.get(gx, gy)[:3], SUIT_DEEP, depth))
    fx0, fy0, fw, fh = face_rect("head", "front")  # (8, 8, 8, 8)
    for fy in range(fh):
        for fx in range(fw):
            gx, gy = fx0 + fx, fy0 + fy
            if fy <= 2:  # brow shadow band under the hood
                cv.put(gx, gy, mix(cv.get(gx, gy)[:3], (5, 3, 9), 0.75 - 0.18 * fy))
            elif fy >= 5:  # jaw kept near-black, the merest lift
                cv.put(gx, gy, mix(cv.get(gx, gy)[:3], SUIT_DEEP, 0.35))

    # Faint glyph collar: torso front/back top row, alternating rune dashes.
    for f, phase in (("front", 0), ("back", 1)):
        x0, y0, w, h = face_rect("body", f)
        for fx in range(w):
            gy = y0
            gx = x0 + fx
            m = (fx + phase) % 4
            if m == 0:
                cv.put(gx, gy, rgb(GLYPH))
            elif m == 2:
                cv.put(gx, gy, mix(COLLAR, GLYPH_HI, 0.35))
            else:
                cv.put(gx, gy, mul(COLLAR, 0.9))

    # Neck ring on the body top face.
    x0, y0, w, h = face_rect("body", "top")
    for fx in range(w):
        for fy in range(h):
            if fx in (0, w - 1) or fy in (0, h - 1):
                cv.put(x0 + fx, y0 + fy, mul(COLLAR, 0.8))

    # Gloves: hands (arm bottom faces) slightly lifted violet + dim palm glyph.
    for box in ("arm_r", "arm_l"):
        x0, y0, w, h = face_rect(box, "bottom")
        for fy in range(h):
            for fx in range(w):
                gx, gy = x0 + fx, y0 + fy
                cv.put(gx, gy, mix(cv.get(gx, gy)[:3], COLLAR, 0.4))
        cv.put(x0 + 1, y0 + 1, rgb(VEIN_FORK))
        cv.put(x0 + 2, y0 + 2, rgb(VEIN_END))
        # cuff row above the wrist
        for f in ("front", "back", "right", "left"):
            cx0, cy0, cw, ch = face_rect(box, f)
            for fx in range(cw):
                cv.put(cx0 + fx, cy0 + ch - 3, mix(cv.get(cx0 + fx, cy0 + ch - 3)[:3], HOOD_EDGE, 0.5))

    # Boots: dark trim row + deepened lowest rows on both legs.
    for box in ("leg_r", "leg_l"):
        for f in ("front", "back", "right", "left"):
            x0, y0, w, h = face_rect(box, f)
            for fx in range(w):
                cv.put(x0 + fx, y0 + h - 3, rgb(HOOD_EDGE))
                for fy in (h - 2, h - 1):
                    gx, gy = x0 + fx, y0 + fy
                    cv.put(gx, gy, mix(cv.get(gx, gy)[:3], SUIT_DEEP, 0.6))
        x0, y0, w, h = face_rect(box, "bottom")  # sole tread
        for fy in range(h):
            for fx in range(w):
                if (fx + fy) % 2 == 0:
                    cv.put(x0 + fx, y0 + fy, mul(SUIT_DEEP, 0.8))


# ---------------------------------------------------------------- heart + veins
# Rounded-diamond widths per row (8x6, plan sheet), centered on chest cols 20..27.
HEART_ROWS = (22, 23, 24, 25, 26, 27)
HEART_WIDTHS = (3, 6, 8, 8, 6, 3)


def paint_heart(cv: Canvas):
    cx = 23.5
    for row, width in zip(HEART_ROWS, HEART_WIDTHS):
        x_start = int(round(cx - width / 2 + 0.01))
        for i in range(width):
            gx = x_start + i
            dx = abs(gx + 0.5 - 24.0) / 4.0
            dy = abs(row + 0.5 - 25.0) / 3.0
            d = max(dx, dy) * 0.55 + (dx + dy) * 0.45
            if d < 0.30:
                c, a = HEART_CORE, 255
            elif d < 0.62:
                c, a = HEART_RING, 220
            elif d < 0.92:
                c, a = HEART_HALO, 190
            else:
                c, a = HEART_EDGE, 150
            cv.put(gx, row, c)
            glow(gx, row, c, a)
    # 1px soft halo bleeding into the suit around the diamond (albedo only + low glow).
    halo = []
    for row, width in zip(HEART_ROWS, HEART_WIDTHS):
        x_start = int(round(cx - width / 2 + 0.01))
        halo += [(x_start - 1, row), (x_start + width, row)]
    halo += [(23, 21), (24, 21), (23, 28), (24, 28)]
    for gx, gy in halo:
        if 20 <= gx <= 27 and 20 <= gy <= 31:
            cv.put(gx, gy, mix(cv.get(gx, gy)[:3], HEART_EDGE, 0.55))
            glow(gx, gy, HEART_EDGE, 90)


# Vein path tables: (global_x, global_y) pixel runs. MAIN channels are 1px #B98CFF,
# FORKS #6E4DA8, ENDS #4A3570, NODES #E7D6FF. Deliberately asymmetric left/right.
VEIN_MAINS = [
    # torso front, player-left side: heart -> shoulder (exits top col 27)
    [(26, 23), (27, 22), (27, 21), (27, 20)],
    # continues on LEFT arm front (inner edge col 36) down to the wrist
    [(36, 53), (37, 54), (37, 55), (36, 56), (37, 57), (37, 58), (36, 59), (37, 60)],
    # torso front, player-right side: heart -> exits side col 20 low
    [(21, 26), (20, 27), (20, 28)],
    # player-right up-branch: heart -> shoulder col 20
    [(22, 22), (21, 21), (20, 20)],
    # RIGHT arm front (inner edge col 47), jagged descent
    [(47, 21), (46, 22), (46, 23), (47, 24), (46, 25), (46, 26), (45, 27)],
    # RIGHT arm outer face hint
    [(41, 22), (41, 23), (42, 24), (42, 25)],
    # LEFT arm back face hint (asymmetry: no outer-face vein on the left arm)
    [(45, 55), (46, 56), (46, 57), (45, 58)],
    # torso front, heart -> waist
    [(23, 28), (23, 29), (24, 30), (24, 31)],
    # RIGHT leg front from the hip (torso col 23 maps onto leg col 7)
    [(7, 20), (6, 21), (6, 22), (5, 23)],
    # LEFT leg front, shorter (asymmetry)
    [(20, 52), (21, 53), (21, 54)],
    # SPINE: torso back center col, collar -> waist
    [(35, 20), (35, 21), (36, 22), (36, 23), (35, 24), (35, 25), (36, 26), (35, 27), (35, 28), (36, 29)],
    # nape: head back, neck -> skull
    [(27, 15), (27, 14), (28, 13)],
]
VEIN_FORKS = [
    [(25, 22), (26, 21)],                # heart top-left flick
    [(20, 24), (19, 24)],                # wraps onto torso right side face
    [(27, 25), (28, 25), (29, 26)],      # wraps onto torso left side face
    [(37, 23), (38, 24), (38, 25)],      # spine fork right
    [(34, 22), (33, 23)],                # spine fork left
    [(34, 29), (34, 30)],                # spine tail fork
    [(45, 23), (44, 24)],                # right arm inner fork
    [(38, 56), (38, 57)],                # left arm front fork
    [(22, 29), (21, 30)],                # waist fork
    [(5, 24), (4, 25)],                  # right leg fade tail
    [(22, 55), (22, 56)],                # left leg fade tail
]
VEIN_NODES = [(27, 20), (35, 24), (37, 57), (46, 24), (23, 28)]


def paint_veins(cv: Canvas):
    for run in VEIN_MAINS:
        for i, (gx, gy) in enumerate(run):
            tail = i >= len(run) - 1 and len(run) > 3
            c = VEIN_FORK if tail else VEIN_MAIN
            a = 170 if tail else 235
            cv.put(gx, gy, rgb(c))
            glow(gx, gy, c, a)
    for run in VEIN_FORKS:
        for i, (gx, gy) in enumerate(run):
            c = VEIN_END if i == len(run) - 1 else VEIN_FORK
            cv.put(gx, gy, rgb(c))
            glow(gx, gy, c, 140 if i < len(run) - 1 else 100)
    for gx, gy in VEIN_NODES:
        cv.put(gx, gy, rgb(VEIN_NODE))
        glow(gx, gy, VEIN_NODE, 255)


def paint_eyes(cv: Canvas):
    """Two soft 2x2 glowing eyes on the face rows 11-12 (cols 1-2 and 5-6 — the same
    pixels the_other blacks out, so the doppelganger delta swallows them exactly)."""
    for outer, inner in ((9, 10), (14, 13)):
        cv.put(outer, 11, rgb(EYE_SOFT))
        glow(outer, 11, EYE_SOFT, 230)
        cv.put(inner, 11, rgb(EYE_HOT))
        glow(inner, 11, EYE_HOT, 255)
        for gx in (outer, inner):
            cv.put(gx, 12, mix(EYE_UNDER, SUIT_DEEP, 0.35))
            glow(gx, 12, EYE_UNDER, 110)


# ---------------------------------------------------------------- overlay layer
EMBERS_JACKET = [  # (x, y, color, alpha) floating around the torso
    (21, 38, HEART_HALO, 210), (26, 40, HEART_EDGE, 170), (23, 43, EYE_HOT, 230),
    (25, 37, VEIN_FORK, 150), (34, 38, HEART_HALO, 200), (37, 42, HEART_EDGE, 160),
    (33, 44, VEIN_FORK, 140), (18, 39, HEART_EDGE, 150), (30, 41, HEART_HALO, 180),
]
EMBERS_SLEEVE_R = [(45, 37, HEART_HALO, 200), (46, 41, HEART_EDGE, 150), (42, 39, VEIN_FORK, 140)]
EMBERS_SLEEVE_L = [(53, 53, HEART_HALO, 200), (54, 57, HEART_EDGE, 150), (61, 55, VEIN_FORK, 140)]
EMBERS_PANTS = [(5, 37, HEART_EDGE, 150), (13, 40, VEIN_FORK, 130), (5, 53, VEIN_FORK, 130), (9, 55, HEART_EDGE, 140)]


def paint_overlay(cv: Canvas):
    # HOOD (hat box): opaque crown/sides/back cloth shell; front is a rim ring only so
    # the face stays inset; bottom face stays open.
    for f in ("top", "right", "left", "back"):
        x0, y0, w, h = face_rect("hat", f)
        for fy in range(h):
            for fx in range(w):
                gx, gy = x0 + fx, y0 + fy
                c = mix(suit_pixel(gx, gy, 31), SUIT_DEEP, 0.5)
                if f != "top" and fy == h - 1:
                    c = mix(c, HOOD_EDGE, 0.5)  # hem catch-light
                cv.put(gx, gy, c)
    x0, y0, w, h = face_rect("hat", "back")  # hood tail crease
    for fy in range(1, h - 1):
        cv.put(x0 + w // 2, y0 + fy, mul(SUIT_DEEP, 0.75))
    x0, y0, w, h = face_rect("hat", "front")  # rim ring
    for fy in range(h):
        for fx in range(w):
            if fx in (0, w - 1) or fy == 0:
                gx, gy = x0 + fx, y0 + fy
                c = mix(suit_pixel(gx, gy, 32), HOOD_EDGE, 0.45 if fy == 0 else 0.25)
                cv.put(gx, gy, c)

    # MANTLE (jacket): 2-row hood cape over the shoulders with a ragged alpha hem.
    x0, y0, w, h = face_rect("jacket", "top")
    for fy in range(h):
        for fx in range(w):
            cv.put(x0 + fx, y0 + fy, mix(suit_pixel(x0 + fx, y0 + fy, 33), SUIT_DEEP, 0.4))
    for f in ("front", "back", "right", "left"):
        x0, y0, w, h = face_rect("jacket", f)
        for fx in range(w):
            cv.put(x0 + fx, y0, mix(suit_pixel(x0 + fx, y0, 34), SUIT_DEEP, 0.45))
            if noise(fx, 1, 35 + (0 if f == "front" else 4)) < 0.72:  # ragged 2nd row
                cv.put(x0 + fx, y0 + 1, mul(suit_pixel(x0 + fx, y0 + 1, 34), 0.9), 235)

    # FLOATING EMBERS: semi-alpha sparks on otherwise-transparent overlay faces.
    for gx, gy, c, a in EMBERS_JACKET + EMBERS_SLEEVE_R + EMBERS_SLEEVE_L + EMBERS_PANTS:
        cv.put(gx, gy, rgb(c), a)


# ---------------------------------------------------------------- outputs
def build_player() -> Canvas:
    GLOW.clear()
    cv = Canvas()
    paint_base_suit(cv)
    paint_heart(cv)
    paint_veins(cv)
    paint_eyes(cv)
    paint_overlay(cv)
    return cv


def build_the_other(player: Canvas) -> Canvas:
    cv = Canvas()
    cv.img = player.img.copy()
    cv.px = cv.img.load()
    # Delta 1: pure-black 2x2 eyes (face cols 1-2 / 5-6, rows 11-12).
    for y in (11, 12):
        for x in (9, 10, 13, 14):
            cv.px[x, y] = (0, 0, 0, 255)
        for x in (41, 42, 45, 46):  # hat face: only where the hood rim is opaque
            if cv.px[x, y][3] > 0:
                cv.px[x, y] = (0, 0, 0, 255)
    # Delta 2: faint purple seam down face column 3, rows 8-15.
    for y in range(8, 16):
        cv.px[11, y] = rgb(SEAM) + (255,)
        if cv.px[43, y][3] > 0:
            cv.px[43, y] = rgb(SEAM) + (255,)
    return cv


def build_glow() -> Canvas:
    cv = Canvas()
    for (x, y), (c, a) in GLOW.items():
        cv.put(x, y, c, a)
    return cv


# ---------------------------------------------------------------- preview sheet
def composite_front(img: Image.Image) -> Image.Image:
    """16x32 front composite (base + overlay alpha-blended)."""
    out = Image.new("RGBA", (16, 32), (0, 0, 0, 0))

    def blit(box, overlay_box, dest):
        x0, y0, w, h = face_rect(box, "front")
        part = img.crop((x0, y0, x0 + w, y0 + h)).convert("RGBA")
        ox0, oy0, ow, oh = face_rect(overlay_box, "front")
        over = img.crop((ox0, oy0, ox0 + ow, oy0 + oh)).convert("RGBA")
        part.alpha_composite(over)
        out.alpha_composite(part, dest)

    blit("head", "hat", (4, 0))
    blit("body", "jacket", (4, 8))
    blit("arm_r", "sleeve_r", (0, 8))
    blit("arm_l", "sleeve_l", (12, 8))
    blit("leg_r", "pant_r", (4, 20))
    blit("leg_l", "pant_l", (8, 20))
    return out


def composite_back(img: Image.Image) -> Image.Image:
    out = Image.new("RGBA", (16, 32), (0, 0, 0, 0))

    def blit(box, overlay_box, dest):
        x0, y0, w, h = face_rect(box, "back")
        part = img.crop((x0, y0, x0 + w, y0 + h)).convert("RGBA")
        ox0, oy0, ow, oh = face_rect(overlay_box, "back")
        over = img.crop((ox0, oy0, ox0 + ow, oy0 + oh)).convert("RGBA")
        part.alpha_composite(over)
        out.alpha_composite(part, dest)

    blit("head", "hat", (4, 0))
    blit("body", "jacket", (4, 8))
    blit("arm_l", "sleeve_l", (0, 8))
    blit("arm_r", "sleeve_r", (12, 8))
    blit("leg_l", "pant_l", (4, 20))
    blit("leg_r", "pant_r", (8, 20))
    return out


def composite_side(img: Image.Image) -> Image.Image:
    out = Image.new("RGBA", (8, 32), (0, 0, 0, 0))

    def blit(box, overlay_box, dest, face="right"):
        x0, y0, w, h = face_rect(box, face)
        part = img.crop((x0, y0, x0 + w, y0 + h)).convert("RGBA")
        ox0, oy0, ow, oh = face_rect(overlay_box, face)
        over = img.crop((ox0, oy0, ox0 + ow, oy0 + oh)).convert("RGBA")
        part.alpha_composite(over)
        out.alpha_composite(part, dest)

    blit("head", "hat", (0, 0))
    blit("arm_r", "sleeve_r", (2, 8))
    blit("leg_r", "pant_r", (2, 20))
    return out


def night_sim(front: Image.Image, glow_front: Image.Image) -> Image.Image:
    """Albedo dimmed to night levels + additive glow — previews the emissive read."""
    out = Image.new("RGBA", front.size, (0, 0, 0, 0))
    fp, gp, op = front.load(), glow_front.load(), out.load()
    for y in range(front.size[1]):
        for x in range(front.size[0]):
            r, g, b, a = fp[x, y]
            if a == 0:
                continue
            r, g, b = int(r * 0.20), int(g * 0.20), int(b * 0.24)
            gr, gg, gb, ga = gp[x, y]
            if ga > 0:
                f = ga / 255.0
                r = min(255, r + int(gr * f))
                g = min(255, g + int(gg * f))
                b = min(255, b + int(gb * f))
            op[x, y] = (r, g, b, 255)
    return out


def write_preview(player: Canvas, other: Canvas, glow_cv: Canvas, dest: Path):
    scale = 10
    panels = []
    front = composite_front(player.img)
    panels.append(("player front", front))
    panels.append(("player back", composite_back(player.img)))
    panels.append(("player side", composite_side(player.img)))
    panels.append(("the_other front", composite_front(other.img)))
    panels.append(("glow mask", composite_front(glow_cv.img)))
    panels.append(("night sim", night_sim(front, composite_front(glow_cv.img))))

    pad, label_h = 14, 16
    widths = [p.size[0] * scale for _, p in panels]
    height = max(p.size[1] for _, p in panels) * scale
    sheet = Image.new("RGBA", (sum(widths) + pad * (len(panels) + 1), height + label_h + 2 * pad), (14, 11, 20, 255))
    draw = ImageDraw.Draw(sheet)
    x = pad
    for (label, panel), w in zip(panels, widths):
        big = panel.resize((panel.size[0] * scale, panel.size[1] * scale), Image.NEAREST)
        sheet.alpha_composite(big, (x, pad + label_h))
        draw.text((x, pad), label, fill=(203, 178, 242, 255))
        x += w + pad
    dest.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(dest)
    print(f"preview  -> {dest}")


# ---------------------------------------------------------------- main
def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", metavar="DIR", help="also write skin_v2_preview.png to DIR")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    player = build_player()
    other = build_the_other(player)
    glow_cv = build_glow()

    player.img.save(OUT_DIR / "eclipsed_player.png")
    other.img.save(OUT_DIR / "the_other.png")
    glow_cv.img.save(OUT_DIR / "eclipsed_player_glow.png")
    print(f"skins    -> {OUT_DIR}/eclipsed_player.png, the_other.png, eclipsed_player_glow.png")
    print(f"emissive -> {len(GLOW)} glow pixels")

    if args.preview:
        write_preview(player, other, glow_cv, Path(args.preview) / "skin_v2_preview.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
