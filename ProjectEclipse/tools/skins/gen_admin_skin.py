#!/usr/bin/env python3
"""Generates the bundled admin skin (F-051): assets/eclipse/textures/skins/admin_purple.png.

Hand-placed pixel art on the vanilla 64x64 skin UV layout (Steve/classic, 4 px arms):

    head   0,0  - 31,15   (top 8,0 | bottom 16,0 | right 0,8 | front 8,8 | left 16,8 | back 24,8)
    hat    32,0 - 63,15   (the hood shell; the face opening stays transparent)
    body   16,16- 39,31   (front 20,20, 8x12)
    r.arm  40,16- 55,31   (4 px wide)   r.leg  0,16 - 15,31
    l.arm  32,48- 47,63   (mirror)      l.leg  16,48- 31,63
    overlay layers: body 16,32 | r.arm 40,32 | r.leg 0,32 | l.leg 0,48 | l.arm 48,48

Style rules kept deliberately strict so this reads as MINECRAFT pixel art and not as an
upscaled render: flat fields, at most three tones per material, shading always from the
upper left, no dithering, no gradients. Gold stays an ACCENT (collar, cuffs, pauldrons,
chest rune) — the robe itself carries the silhouette.

The left limbs are built the way vanilla builds them from a legacy sheet: face by face,
mirrored in X — mirroring the whole 16x16 box would swap the front/back faces.

Run:  python3 tools/skins/gen_admin_skin.py
"""

from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "src/main/resources/assets/eclipse/textures/skins/admin_purple.png"

# --- palette -------------------------------------------------------------------
T = (0, 0, 0, 0)

ROBE = (42, 17, 64, 255)          # dark violet robe
ROBE_LIGHT = (59, 26, 87, 255)    # lit edge (upper left)
ROBE_DARK = (28, 10, 45, 255)     # shaded edge (lower right)

HOOD = (52, 21, 79, 255)          # the hood sits a shade above the robe
HOOD_LIGHT = (72, 32, 106, 255)
HOOD_DARK = (33, 12, 51, 255)

VOID = (10, 6, 20, 255)           # the shadow inside the hood
VOID_SOFT = (18, 11, 33, 255)

EYE = (199, 125, 255, 255)        # glowing eyes
EYE_CORE = (233, 198, 255, 255)
EYE_GLOW = (124, 62, 178, 255)

GOLD = (224, 166, 40, 255)
GOLD_LIGHT = (255, 216, 107, 255)
GOLD_DARK = (140, 94, 16, 255)

LEATHER = (21, 10, 34, 255)       # gloves + boots
LEATHER_LIGHT = (36, 16, 51, 255)

KEY = {
    ".": T,
    "R": ROBE, "L": ROBE_LIGHT, "D": ROBE_DARK,
    "H": HOOD, "h": HOOD_LIGHT, "d": HOOD_DARK,
    "V": VOID, "v": VOID_SOFT,
    "E": EYE, "C": EYE_CORE, "G": EYE_GLOW,
    "y": GOLD, "Y": GOLD_LIGHT, "o": GOLD_DARK,
    "B": LEATHER, "b": LEATHER_LIGHT,
}

img = Image.new("RGBA", (64, 64), T)
px = img.load()


def fill(x, y, w, h, color):
    for i in range(w):
        for j in range(h):
            px[x + i, y + j] = color


def clear(x, y, w, h):
    fill(x, y, w, h, T)


def art(x, y, rows):
    """Stamps an ASCII sprite; ' ' means 'leave whatever is already there'."""
    for j, row in enumerate(rows):
        for i, char in enumerate(row):
            if char == " ":
                continue
            px[x + i, y + j] = KEY[char]


def panel(x, y, w, h, base, light, dark):
    """Flat field with a 1 px lit top/left edge and a 1 px shaded bottom/right edge."""
    fill(x, y, w, h, base)
    for i in range(w):
        px[x + i, y] = light
        px[x + i, y + h - 1] = dark
    for j in range(h):
        px[x, y + j] = light if j < h - 1 else dark
        px[x + w - 1, y + j] = dark


def mirror_face(src_x, src_y, dst_x, dst_y, w, h):
    for i in range(w):
        for j in range(h):
            px[dst_x + i, dst_y + j] = px[src_x + w - 1 - i, src_y + j]


def mirror_limb(src_x, src_y, dst_x, dst_y):
    """Right limb box -> left limb box, face by face (vanilla legacy-conversion mapping)."""
    mirror_face(src_x + 4, src_y, dst_x + 4, dst_y, 4, 4)              # top
    mirror_face(src_x + 8, src_y, dst_x + 8, dst_y, 4, 4)              # bottom
    mirror_face(src_x, src_y + 4, dst_x + 8, dst_y + 4, 4, 12)         # right -> left
    mirror_face(src_x + 4, src_y + 4, dst_x + 4, dst_y + 4, 4, 12)     # front
    mirror_face(src_x + 8, src_y + 4, dst_x, dst_y + 4, 4, 12)         # left -> right
    mirror_face(src_x + 12, src_y + 4, dst_x + 12, dst_y + 4, 4, 12)   # back


# --- head: hood fabric everywhere, a void face with two glowing eyes -------------
panel(8, 0, 8, 8, HOOD, HOOD_LIGHT, HOOD_DARK)          # top
fill(16, 0, 8, 8, VOID)                                 # bottom (under the hood)
panel(0, 8, 8, 8, HOOD, HOOD_LIGHT, HOOD_DARK)          # right
panel(16, 8, 8, 8, HOOD, HOOD_LIGHT, HOOD_DARK)         # left

art(8, 8, [                                             # front: face in hood shadow
    "dddddddd",
    "dvvvvvvd",
    "vVVVVVVv",
    "vVVVVVVv",
    "vGEEVEEG",
    "vGCEVECG",
    "vVVVVVVv",
    "dvVVVVvd",
])
art(24, 8, [                                            # back of the head: hood seam
    "dddddddd",
    "dhhhhhhd",
    "dHHHHHHd",
    "dHHyyHHd",
    "dHHyyHHd",
    "dHHHHHHd",
    "dhhhhhhd",
    "dddddddd",
])

# --- hat layer: the hood shell (face opening stays transparent) ------------------
panel(40, 0, 8, 8, HOOD, HOOD_LIGHT, HOOD_DARK)         # crown
clear(48, 0, 8, 8)                                      # underside: open
art(32, 8, [                                            # right side
    "dhhhhhhd",
    "dHHHHHHd",
    "dHHHHHHd",
    "dHHHHHHd",
    "dHHHHHHd",
    "ddHHHHdd",
    "..dHHd..",
    "...dd...",
])
art(48, 8, [                                            # left side
    "dhhhhhhd",
    "dHHHHHHd",
    "dHHHHHHd",
    "dHHHHHHd",
    "dHHHHHHd",
    "ddHHHHdd",
    "..dHHd..",
    "...dd...",
])
art(56, 8, [                                            # back + rune
    "dhhhhhhd",
    "dHHHHHHd",
    "dHHyyHHd",
    "dHyYYyHd",
    "dHHyyHHd",
    "dHHHHHHd",
    "dhhhhhhd",
    "dddddddd",
])
art(40, 8, [                                            # brim: overhang + cheek guards
    "dhhhhhhd",
    "dHHHHHHd",
    "dd....dd",
    "d......d",
    "d......d",
    "d......d",
    "dd....dd",
    ".dd..dd.",
])

# --- body: robe with a golden rune on the chest ----------------------------------
panel(20, 16, 8, 4, HOOD, HOOD_LIGHT, HOOD_DARK)        # shoulders (top)
fill(28, 16, 8, 4, ROBE_DARK)                           # underside
panel(16, 20, 4, 12, ROBE, ROBE_LIGHT, ROBE_DARK)       # right side
panel(28, 20, 4, 12, ROBE, ROBE_LIGHT, ROBE_DARK)       # left side

art(20, 20, [                                           # chest: collar, rune, hem
    "ooyyyyoo",
    "DRRRRRRD",
    "DRRRRRRD",
    "DRRyyRRD",
    "DRyRRyRD",
    "DyRCCRyD",
    "DyRCCRyD",
    "DRyRRyRD",
    "DRRyyRRD",
    "DRRRRRRD",
    "DRRRRRRD",
    "DoRRRRoD",
])
art(32, 20, [                                           # back
    "ooyyyyoo",
    "DRRRRRRD",
    "DRRRRRRD",
    "DRRRRRRD",
    "DRRyyRRD",
    "DRRyyRRD",
    "DRRRRRRD",
    "DRRRRRRD",
    "DRRRRRRD",
    "DRRRRRRD",
    "DRRRRRRD",
    "DoRRRRoD",
])

# --- right arm: sleeve, golden cuff, dark glove ----------------------------------
panel(44, 16, 4, 4, HOOD, HOOD_LIGHT, HOOD_DARK)        # top
fill(48, 16, 4, 4, LEATHER)                             # bottom (the hand)
for face_x in (40, 44, 48, 52):
    art(face_x, 20, [
        "LRRD",
        "LRRD",
        "LRRD",
        "LRRD",
        "LRRD",
        "LRRD",
        "LRRD",
        "LRoD",
        "oyyo",
        "bBBB",
        "BBBB",
        "BBBB",
    ])

# --- right leg: robe hem into a dark boot ----------------------------------------
panel(4, 16, 4, 4, ROBE, ROBE_LIGHT, ROBE_DARK)         # top
fill(8, 16, 4, 4, LEATHER)                              # sole
for face_x in (0, 4, 8, 12):
    art(face_x, 20, [
        "LRRD",
        "LRRD",
        "LRRD",
        "LRRD",
        "LRRD",
        "LRoD",
        "oyyo",
        "bBBB",
        "BBBB",
        "BBBB",
        "BBBB",
        "bBBB",
    ])

# --- overlay layers: a cloak over the robe, gold only at the collar ---------------
art(20, 36, [                                           # cloak front: open, thin edges
    "yooooooy",
    "D......D",
    "D......D",
    "D......D",
    "D......D",
    "D......D",
    "D......D",
    "D......D",
    "D......D",
    "D......D",
    "D......D",
    "o......o",
])
fill(32, 36, 8, 12, ROBE_DARK)                          # cloak back: full cape
for x in range(32, 40):
    px[x, 36] = GOLD_DARK
    px[x, 47] = ROBE_DARK
panel(16, 36, 4, 12, ROBE, ROBE_LIGHT, ROBE_DARK)       # cloak right side
panel(28, 36, 4, 12, ROBE, ROBE_LIGHT, ROBE_DARK)       # cloak left side
panel(20, 32, 8, 4, ROBE_DARK, ROBE, ROBE_DARK)         # cloak top

panel(44, 32, 4, 4, GOLD_DARK, GOLD, GOLD_DARK)         # pauldron cap
for face_x in (40, 44, 48, 52):                         # sleeve overlay: pauldron only
    art(face_x, 36, [
        "yYYy",
        "oyyo",
        "oRRo",
        "D..D",
        "....",
        "....",
        "....",
        "....",
        "....",
        "....",
        "....",
        "....",
    ])

# --- mirrored left limbs (arm/leg boxes and the sleeve overlay) -------------------
mirror_limb(40, 16, 32, 48)   # right arm  -> left arm
mirror_limb(0, 16, 16, 48)    # right leg  -> left leg
mirror_limb(40, 32, 48, 48)   # right sleeve overlay -> left sleeve overlay

img.save(OUT)
print(f"wrote {OUT} ({OUT.stat().st_size} bytes, {img.size[0]}x{img.size[1]})")
