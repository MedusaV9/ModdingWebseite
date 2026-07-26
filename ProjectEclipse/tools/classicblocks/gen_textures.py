#!/usr/bin/env python3
"""F-012 — generate the handful of bundled ``eclipse:*/classic/*`` textures.

TUT2 deleted the imported "retro" texture set: the classic blocks resolve VANILLA
textures and the console-era look is a client-side colour grade
(``xboxevent/XboxEraProfile``). What survived were the GEOMETRY SHEETS vanilla ships
no block-atlas texture for at all — chests, ender chests, beds, signs and skulls are
block ENTITIES in vanilla, so their art lives in ``entity/`` at a model-specific UV
layout that a cube model cannot reference.

Those survivors were third-party/hand-painted art with no generator behind them, and
the F-012 audit measured several of them as painterly rather than pixel art (soft
1–6/255 colour steps between neighbouring pixels, 20–40% of the tile, and up to 845
distinct colours in a 64x64 sheet where vanilla uses 29). This script replaces the
whole set with pixel data lifted from — or, for the two composites, drawn with the
palette of — the vanilla client resources, so every bundled classic texture is
reproducible, provably vanilla-derived and period-correct for the Xbox 360 eras.

Outputs (byte-identical on re-run):
  src/main/resources/assets/eclipse/textures/block/classic/*.png
  src/main/resources/assets/eclipse/textures/item/classic/*.png
  tools/classicblocks/provenance.json

Which slots are bundled vs resolved from vanilla is decided in gen_assets.py
(``OWN_BLOCK_TEXTURES`` / ``OWN_ITEM_TEXTURES``); this script asserts it stays in sync.

Requires Pillow and the vanilla client resources jar (same lookup as gen_assets.py).
"""

import io
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_assets  # noqa: E402  (find_vanilla_jar + the OWN_* contract)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEXTURES = os.path.join(ROOT, "src/main/resources/assets/eclipse/textures")
PROVENANCE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "provenance.json")

# Vanilla chest/ender-chest UV layout. Both parts are boxes; for a box of size
# (w, h, d) at sheet offset (u, v) vanilla lays the faces out as
#   top (u+d, v, w x d) | left (u, v+d, d x h) | front (u+d, v+d, w x h).
# lid  = size (14, 5, 14) at (0, 0);  body = size (14, 10, 14) at (0, 19);
# lock = size (2, 4, 1)  at (0, 0)  ->  top (1, 0, 2x1), front (1, 1, 2x4).
CHEST_UV = {
    "lid_top": (14, 0, 28, 14),
    "lid_front": (14, 14, 28, 19),
    "lid_left": (0, 14, 14, 19),
    "body_front": (14, 33, 28, 43),
    "body_left": (0, 33, 14, 43),
    "lock_top": (1, 0, 3, 1),
    "lock_front": (1, 1, 3, 5),
}

# Head layout of a player/mob skin: the 32x16 block the vanilla skull model UV-maps
# into (top/bottom row then right/front/left/back). Same crop for every skull.
HEAD_BOX = (0, 0, 32, 16)

SKULLS = {
    "skull_creeper": "entity/creeper/creeper.png",
    "skull_skeleton": "entity/skeleton/skeleton.png",
    "skull_steve": "entity/player/wide/steve.png",
    "skull_wither_skeleton": "entity/skeleton/wither_skeleton.png",
    "skull_zombie": "entity/zombie/zombie.png",
}

# The sign board: box (24, 12, 1) at (0, 0), so the whole board (top/bottom strips,
# both edges, front and back) lives in the top 14 rows — the wall-sign model reads it
# out of a 64x16 tile.
SIGN_BOX = (0, 0, 64, 16)

PROV = []


def note(texture, source, op, note_text=""):
    PROV.append({"texture": texture, "source": source, "op": op, "note": note_text})


class Vanilla:
    """Read-only view of the vanilla client resources jar."""

    def __init__(self):
        self.zip = gen_assets.Vanilla().zip

    def image(self, path):
        with self.zip.open(f"assets/minecraft/textures/{path}") as f:
            return Image.open(io.BytesIO(f.read())).convert("RGBA")


def pad_to_tile(img, anchor, size=16):
    """Grow a chest face (14 wide, 14-15 tall) to a full tile by EDGE-EXTENDING it.

    Nearest-neighbour rescaling would smear the pixel grid; repeating the outermost
    row/column keeps every output pixel a verbatim vanilla pixel and keeps the hard
    16x16 edges a block face needs. Upright faces anchor to the bottom (the chest
    stands on the floor); the lid seen from above is centred.
    """
    w, h = img.size
    if w > size or h > size:
        raise SystemExit(f"face {img.size} does not fit a {size}x{size} tile")
    left = (size - w) // 2
    top = size - h if anchor == "bottom" else (size - h) // 2
    out = Image.new("RGBA", (size, size))
    out.paste(img, (left, top))
    px = out.load()
    for y in range(size):
        for x in range(size):
            if left <= x < left + w and top <= y < top + h:
                continue
            px[x, y] = img.getpixel((min(max(x, left), left + w - 1) - left,
                                     min(max(y, top), top + h - 1) - top))
    return out


def chest_faces(van, sheet, name, wood_note):
    """front/side/top tiles of the old CUBE chest, assembled from vanilla faces."""
    src = van.image(sheet)
    part = {k: src.crop(box) for k, box in CHEST_UV.items()}

    def stack(lid, body):
        col = Image.new("RGBA", (14, 15))
        col.paste(lid, (0, 0))
        col.paste(body, (0, 5))
        return col

    front = pad_to_tile(stack(part["lid_front"], part["body_front"]), "bottom")
    side = pad_to_tile(stack(part["lid_left"], part["body_left"]), "bottom")
    top = pad_to_tile(part["lid_top"], "center")

    # The latch straddles the lid seam exactly as it does on the 3D model: its top
    # strip sits on the last lid row, the 2x4 face hangs into the body below it.
    front.paste(part["lock_top"], (7, 5))
    front.paste(part["lock_front"], (7, 6))

    for slot, img in (("front", front), ("side", side), ("top", top)):
        yield f"{name}_{slot}", img
        note(f"block/classic/{name}_{slot}.png", f"vanilla {sheet}",
             f"cube-chest {slot} face, verbatim vanilla pixels", wood_note)


def bed_item(van):
    """A 16x16 side-view bed icon — vanilla has no flat bed item texture.

    Hard pixels only, and every colour is sampled from the vanilla bed sheet / oak
    planks, so the icon sits in the vanilla palette instead of next to it. The
    silhouette follows the pre-1.13 flat bed icon the Xbox eras actually shipped.
    """
    sheet = van.image("entity/bed/red.png")
    planks = van.image("block/oak_planks.png")
    # Sheet top face, its shaded side, the pillow and the plank shades — every
    # sample is a coordinate inside the vanilla art, not a hand-picked value.
    red = sheet.getpixel((6, 17))
    red_mid = sheet.getpixel((6, 20))
    red_dark = sheet.getpixel((3, 15))
    white = sheet.getpixel((10, 4))
    white_dark = sheet.getpixel((6, 3))
    wood = planks.getpixel((0, 0))
    wood_dark = planks.getpixel((6, 3))

    # 16x16 icon: '.' transparent, 'P'/'p' pillow, 'R'/'m'/'r' mattress, 'W'/'w' frame.
    art = [
        "................",
        "................",
        "................",
        "................",
        "..PPPPPPRRRRRR..",
        ".PPPPPPPRRRRRRR.",
        ".PPPPPPPRRRRRRR.",
        ".ppppppmmmmmmmm.",
        ".wrrrrrrrrrrrrw.",
        ".wrrrrrrrrrrrrw.",
        ".W............W.",
        "................",
        "................",
        "................",
        "................",
        "................",
    ]
    palette = {"P": white, "p": white_dark, "R": red, "m": red_mid, "r": red_dark,
               "W": wood, "w": wood_dark}
    img = Image.new("RGBA", (16, 16))
    px = img.load()
    for y, row in enumerate(art):
        for x, ch in enumerate(row):
            if ch != ".":
                px[x, y] = palette[ch]
    note("item/classic/red_bed.png",
         "vanilla entity/bed/red.png + block/oak_planks.png",
         "drawn 16x16 side-view icon",
         "vanilla ships no flat bed item texture (the item is entity-rendered); "
         "every colour is sampled from the two vanilla sources")
    return img


def build(van):
    out = {}

    for name, img in chest_faces(van, "entity/chest/normal.png", "chest",
                                 "vanilla renders chests as a block entity, so there "
                                 "is no block-atlas tile to reference"):
        out[f"block/classic/{name}"] = img
    for name, img in chest_faces(van, "entity/chest/ender.png", "ender_chest",
                                 "same as the normal chest — entity-rendered in vanilla"):
        out[f"block/classic/{name}"] = img

    for name, skin in sorted(SKULLS.items()):
        out[f"block/classic/{name}"] = van.image(skin).crop(HEAD_BOX)
        note(f"block/classic/{name}.png", f"vanilla {skin}",
             f"{HEAD_BOX[2]}x{HEAD_BOX[3]} head crop",
             "the skull cube UV-maps into this")

    out["block/classic/sign_oak"] = van.image("entity/signs/oak.png").crop(SIGN_BOX)
    note("block/classic/sign_oak.png", "vanilla entity/signs/oak.png",
         f"{SIGN_BOX[2]}x{SIGN_BOX[3]} board crop", "the wall-sign model UV-maps into this")

    out["block/classic/red_bed_sheet"] = van.image("entity/bed/red.png")
    note("block/classic/red_bed_sheet.png", "vanilla entity/bed/red.png", "copy (64x64)",
         "the bed model UV-maps into the sheet")

    out["item/classic/red_bed"] = bed_item(van)
    return out


def check_contract(out):
    """The bundled set must be exactly what gen_assets.py promises to reference."""
    want = ({f"block/classic/{n}" for n in gen_assets.OWN_BLOCK_TEXTURES}
            | {f"item/classic/{n}" for n in gen_assets.OWN_ITEM_TEXTURES})
    have = set(out)
    if want != have:
        raise SystemExit("bundled texture set drifted from gen_assets.OWN_* — "
                         f"missing {sorted(want - have)}, extra {sorted(have - want)}")


def main():
    van = Vanilla()
    out = build(van)
    check_contract(out)

    for rel, img in sorted(out.items()):
        path = os.path.join(TEXTURES, rel + ".png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img.save(path, "PNG", optimize=True)
        print(f"{rel}.png  {img.size[0]}x{img.size[1]}")

    with open(PROVENANCE, "w", encoding="utf-8") as f:
        json.dump({
            "generator": "tools/classicblocks/gen_textures.py",
            "source": "vanilla 1.21.1 client resources (build/moddev/artifacts/"
                      "*client-extra*.jar) — no third-party art, no generated art",
            "note": "TUT2 deleted the imported classic texture set; the classic blocks "
                    "resolve VANILLA textures and the console-era look comes from the "
                    "per-era screen filter (client/xbox/XboxEraFx). Only the geometry "
                    "sheets below stay bundled: vanilla renders chests, beds, signs and "
                    "skulls as block ENTITIES and ships no block-atlas texture for them. "
                    "F-012 rebuilt all of them from vanilla pixels.",
            "textures": sorted(PROV, key=lambda e: e["texture"]),
        }, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"{len(out)} textures, provenance -> {os.path.relpath(PROVENANCE, ROOT)}")


if __name__ == "__main__":
    main()
