#!/usr/bin/env python3
"""P5-W8 — import classic block textures from the MIT-licensed
"Minecraft: Classic Edition" resource pack (Modrinth project
``minecraft-classic-edition``, author JS03, License: MIT).

The pack is a community-made *recreation* of the old look (16x16, author-made
pixel art) — verified MIT via the Modrinth API; this is the source the P5 plan
(docs/plans_v3/P5_devtools_xbox_bundling.md §2.14, risk R11) approves. No
Mojang assets are copied: the handful of textures the pack does not provide
(water, cube-chest faces, redstone dot) are drawn procedurally here or derived
from the pack's own MIT art.

Usage:
    python3 import_textures.py [--pack /path/to/pack.zip]

Downloads the pinned pack version (sha512-verified) to .cache/ when --pack is
not given, then writes only the textures the manifest needs to
    src/main/resources/assets/eclipse/textures/block/classic/
    src/main/resources/assets/eclipse/textures/item/classic/
plus a provenance table (provenance.json) next to this script.
"""

import argparse
import hashlib
import io
import json
import math
import os
import sys
import urllib.request
import zipfile

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import manifest
import texplan

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLOCK_OUT = os.path.join(ROOT, "src/main/resources/assets/eclipse/textures/block/classic")
ITEM_OUT = os.path.join(ROOT, "src/main/resources/assets/eclipse/textures/item/classic")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")

# Pinned pack build (Modrinth CDN, version 1.2.3, published 2024-07-11).
PACK_URL = ("https://cdn.modrinth.com/data/6r6dKiPb/versions/ZM5qM5Ks/"
            "Minecraft%20Classic%20Edition.zip")
PACK_SHA512 = (
    "b504783667df83649d055c0f999e510a46f9e9caa16b67c0883771ca24fbd091"
    "18a316ba4a3d7573ce9c19dad090cca75a4d1a26512c364a75fa8dd6c460875e")
PACK_LICENSE = "MIT (verified via https://api.modrinth.com/v2/project/minecraft-classic-edition)"
PACK_CREDIT = 'Resource pack "Minecraft: Classic Edition" by JS03 — https://modrinth.com/resourcepack/minecraft-classic-edition'


def fetch_pack(explicit):
    if explicit:
        return explicit
    os.makedirs(CACHE, exist_ok=True)
    dest = os.path.join(CACHE, "minecraft-classic-edition-1.2.3.zip")
    if not os.path.exists(dest):
        print(f"downloading pack -> {dest}")
        urllib.request.urlretrieve(PACK_URL, dest)
    digest = hashlib.sha512(open(dest, "rb").read()).hexdigest()
    if digest != PACK_SHA512:
        raise SystemExit(f"pack sha512 mismatch: {digest}")
    return dest


class Pack:
    def __init__(self, path):
        self.zip = zipfile.ZipFile(path)
        self.names = set(self.zip.namelist())

    def open_tex(self, rel):
        """rel like 'block/stone' or 'item/redstone'."""
        name = f"assets/minecraft/textures/{rel}.png"
        if name not in self.names:
            return None
        return Image.open(io.BytesIO(self.zip.read(name))).convert("RGBA")


def tint(im, rgb):
    """Grayscale-multiply colorization (keeps alpha)."""
    r, g, b = rgb
    px = im.load()
    out = Image.new("RGBA", im.size)
    po = out.load()
    for y in range(im.height):
        for x in range(im.width):
            pr, pg, pb, pa = px[x, y]
            po[x, y] = (pr * r // 255, pg * g // 255, pb * b // 255, pa)
    return out


def is_grayish(im):
    px = [p for p in im.convert("RGBA").getdata() if p[3] > 40]
    if not px:
        return False
    n = len(px)
    r = sum(p[0] for p in px) // n
    g = sum(p[1] for p in px) // n
    b = sum(p[2] for p in px) // n
    return abs(r - g) < 12 and abs(g - b) < 12


def alpha_over(base, top):
    out = base.copy()
    out.alpha_composite(top)
    return out


def darken(rgba, f):
    return (int(rgba[0] * f), int(rgba[1] * f), int(rgba[2] * f), rgba[3])


def make_chest(planks, face, latch=(60, 60, 60, 255), glint=(140, 140, 140, 255)):
    """Old-school full-cube chest faces, drawn over the pack's MIT planks art."""
    im = planks.copy()
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            edge = x == 0 or y == 0 or x == w - 1 or y == h - 1
            inner = x == 1 or y == 1 or x == w - 2 or y == h - 2
            if edge:
                px[x, y] = darken(px[x, y], 0.45)
            elif inner:
                px[x, y] = darken(px[x, y], 0.7)
    if face == "front":
        # latch: small clasp centered on the upper third
        for y in range(6, 10):
            for x in range(7, 9):
                px[x, y] = latch
        px[7, 7] = glint
    if face == "top":
        # subtle cross seam
        for x in range(2, w - 2):
            px[x, h // 2] = darken(px[x, h // 2], 0.75)
    return im


def make_end_stone(cobble):
    """Classic-technique end stone: color-inverted cobblestone, pale-yellow tone
    (this is famously how the original end stone was produced)."""
    im = Image.new("RGBA", cobble.size)
    px, po = cobble.load(), im.load()
    for y in range(cobble.height):
        for x in range(cobble.width):
            r, g, b, a = px[x, y]
            inv = 255 - (r + g + b) // 3
            # colorize toward pale yellow-green
            po[x, y] = (min(255, inv * 230 // 255 + 40), min(255, inv * 230 // 255 + 42),
                        min(255, inv * 170 // 255 + 30), a)
    return im


def make_end_frame(end_stone, face):
    """End portal frame side/top derived from the recreated end stone."""
    im = end_stone.copy()
    px = im.load()
    w, h = im.size
    if face == "side":
        # greenish frame band across the top 5 rows
        for y in range(5):
            for x in range(w):
                r, g, b, a = px[x, y]
                px[x, y] = (r * 90 // 255, min(255, g * 160 // 255 + 30), b * 110 // 255, a)
    else:  # top
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                px[x, y] = (r * 100 // 255, min(255, g * 170 // 255 + 25), b * 120 // 255, a)
        # darker recess ring where the eye sits
        for y in range(4, 12):
            for x in range(4, 12):
                if x in (4, 11) or y in (4, 11):
                    px[x, y] = darken(px[x, y], 0.55)
    return im


def make_water():
    """Procedural classic-style still water tile (16x16, slightly translucent).

    Drawn from scratch (deterministic sine ripples) — the pack does not skin
    water (vanilla tints it live) and we never copy Mojang art.
    """
    im = Image.new("RGBA", (16, 16))
    px = im.load()
    base = (47, 93, 217)
    for y in range(16):
        for x in range(16):
            wave = math.sin((x * 2.1 + y * 3.3) * 0.55) + math.sin((x - y) * 0.9)
            k = 1.0 + 0.10 * wave
            r = max(0, min(255, int(base[0] * k)))
            g = max(0, min(255, int(base[1] * k)))
            b = max(0, min(255, int(base[2] * k)))
            px[x, y] = (r, g, b, 235)
    return im


def make_dot(line):
    """Redstone dot blob derived from the tinted line texture's palette."""
    colored = [p for p in line.getdata() if p[3] > 40]
    n = max(1, len(colored))
    c = (sum(p[0] for p in colored) // n, sum(p[1] for p in colored) // n,
         sum(p[2] for p in colored) // n, 255)
    im = Image.new("RGBA", (16, 16))
    px = im.load()
    cx = cy = 7.5
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - cx, y - cy)
            if d <= 2.6:
                px[x, y] = c
            elif d <= 3.4:
                px[x, y] = (c[0] * 3 // 4, c[1] * 3 // 4, c[2] * 3 // 4, 255)
    return im


def optimize_save(im, path):
    """Save PNG as small as losslessly possible (palette if it fits)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    best = None
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    best = buf.getvalue()
    # palette attempt (exact only: <=256 distinct RGBA values)
    colors = set(im.getdata())
    if len(colors) <= 256:
        alphas = {c[3] for c in colors}
        if alphas <= {0, 255}:  # binary alpha quantizes losslessly
            p = im.convert("P", palette=Image.ADAPTIVE, colors=min(256, len(colors)))
            if p.convert("RGBA").tobytes() == im.tobytes():
                buf2 = io.BytesIO()
                transparent = [i for i, c in enumerate(colors) if c[3] == 0]
                p.save(buf2, "PNG", optimize=True, transparency=0 if transparent else None)
                if len(buf2.getvalue()) < len(best) and Image.open(io.BytesIO(buf2.getvalue())).convert("RGBA").tobytes() == im.tobytes():
                    best = buf2.getvalue()
    with open(path, "wb") as f:
        f.write(best)
    return len(best)


def build(pack, out_name, spec, provenance, item=False):
    outdir = ITEM_OUT if item else BLOCK_OUT
    path = os.path.join(outdir, out_name + ".png")

    def rec(source, op, note=""):
        provenance.append({
            "texture": ("item/" if item else "block/") + "classic/" + out_name + ".png",
            "source": source, "op": op, "note": note,
        })

    if spec is None:
        spec = f"copy:{out_name}"

    kind, _, rest = spec.partition(":")
    if kind == "copy":
        im = pack.open_tex(f"block/{rest}")
        if im is None:
            raise SystemExit(f"pack texture missing for {out_name}: block/{rest}")
        rec(f"pack block/{rest}.png", "copy")
    elif kind == "item":
        im = pack.open_tex(f"item/{rest}")
        if im is None:
            raise SystemExit(f"pack texture missing for {out_name}: item/{rest}")
        if out_name == "redstone" and is_grayish(im):
            im = tint(im, manifest.COLORS["RED_DUST"])
            rec(f"pack item/{rest}.png", "copy+tint RED_DUST", "pack ships it grayscale for live tinting")
        else:
            rec(f"pack item/{rest}.png", "copy")
    elif kind == "tint":
        src, color = rest.rsplit(":", 1)
        im = pack.open_tex(f"block/{src}")
        if im is None:
            raise SystemExit(f"pack texture missing for {out_name}: block/{src}")
        im = tint(im, manifest.COLORS[color])
        rec(f"pack block/{src}.png", f"tint {color}",
            "pack ships grayscale for live biome tinting; fixed classic tone baked in")
    elif kind == "grass_side":
        side = pack.open_tex("block/grass_block_side")
        overlay = pack.open_tex("block/grass_block_side_overlay")
        if side is None:
            raise SystemExit("pack grass_block_side missing")
        if overlay is not None:
            im = alpha_over(side, tint(overlay, manifest.COLORS["GRASS"]))
            rec("pack block/grass_block_side.png + grass_block_side_overlay.png",
                "composite overlay x GRASS", "classic baked-in green rim")
        else:
            im = side
            rec("pack block/grass_block_side.png", "copy")
    elif kind == "water":
        im = make_water()
        rec("procedural", "drawn from scratch (sine ripple tile)",
            "pack does not skin water; nothing copied")
    elif kind == "lava_frame0":
        strip = pack.open_tex("block/lava_still")
        if strip is None:
            raise SystemExit("pack lava_still missing")
        im = strip.crop((0, 0, 16, 16))
        rec("pack block/lava_still.png", "first 16x16 frame of animation strip",
            "static frame keeps the jar small; deco block needs no animation")
    elif kind == "redstone_dot":
        line = pack.open_tex("block/redstone_dust_line0")
        if line is None:
            raise SystemExit("pack redstone_dust_line0 missing")
        im = make_dot(tint(line, manifest.COLORS["RED_DUST"]))
        rec("derived from pack block/redstone_dust_line0.png", "palette-sampled dot blob",
            "modern packs have no dot; drawn using the pack's own dust color")
    elif kind in ("chest_front", "chest_side", "chest_top"):
        planks = pack.open_tex("block/oak_planks")
        if planks is None:
            raise SystemExit("pack oak_planks missing")
        im = make_chest(planks, kind.split("_")[1])
        rec("derived from pack block/oak_planks.png", f"drawn cube-chest {kind.split('_')[1]}",
            "old cube-chest faces recreated over the pack's MIT planks art")
    elif kind == "frame":
        src, idx = rest.rsplit(":", 1)
        strip = pack.open_tex(f"block/{src}")
        if strip is None:
            raise SystemExit(f"pack texture missing for {out_name}: block/{src}")
        i = int(idx)
        im = strip.crop((0, 16 * i, 16, 16 * (i + 1)))
        rec(f"pack block/{src}.png", f"16x16 frame {i} of animation strip",
            "static frame keeps the jar small; deco block needs no animation")
    elif kind == "end_stone":
        cobble = pack.open_tex("block/cobblestone")
        if cobble is None:
            raise SystemExit("pack cobblestone missing")
        im = make_end_stone(cobble)
        rec("derived from pack block/cobblestone.png", "color-inverted + pale tint",
            "pack has no end textures; recreated with the classic invert-cobble trick")
    elif kind in ("end_frame_top", "end_frame_side"):
        cobble = pack.open_tex("block/cobblestone")
        if cobble is None:
            raise SystemExit("pack cobblestone missing")
        im = make_end_frame(make_end_stone(cobble), kind.rsplit("_", 1)[1])
        rec("derived from pack block/cobblestone.png", f"end frame {kind.rsplit('_', 1)[1]} recolor",
            "pack has no end textures; drawn over the recreated end stone")
    elif kind == "echest":
        obsidian = pack.open_tex("block/obsidian")
        if obsidian is None:
            raise SystemExit("pack obsidian missing")
        im = make_chest(obsidian, rest, latch=(18, 94, 82, 255), glint=(60, 200, 160, 255))
        rec("derived from pack block/obsidian.png", f"drawn cube-chest {rest}",
            "old cube-chest faces over the pack's obsidian, teal latch")
    elif kind == "skin":
        skin = pack.open_tex(f"entity/{rest}")
        if skin is None:
            raise SystemExit(f"pack skin missing for {out_name}: entity/{rest}")
        im = skin.crop((0, 0, 32, 16))  # head area, no hat layer (old look)
        rec(f"pack entity/{rest}.png", "32x16 head crop", "skull cube UV-maps into this")
    elif kind == "entity64":
        src = pack.open_tex(f"entity/{rest}")
        if src is None:
            raise SystemExit(f"pack entity texture missing for {out_name}: entity/{rest}")
        im = src
        rec(f"pack entity/{rest}.png", "copy (64x64)", "bed model UV-maps into the sheet")
    elif kind == "sign_board":
        src = pack.open_tex("entity/sign")
        if src is None:
            raise SystemExit("pack entity/sign.png missing")
        im = src.crop((0, 0, 64, 16))  # board faces only, power-of-two size
        rec("pack entity/sign.png", "64x16 board crop", "wall-sign model UV-maps into this")
    else:
        raise SystemExit(f"unknown texture op {spec} for {out_name}")

    size = optimize_save(im, path)
    return size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", help="path to Minecraft Classic Edition.zip (skips download)")
    args = ap.parse_args()

    pack = Pack(fetch_pack(args.pack))
    provenance = []

    # wipe output dirs so the bundle only ever contains referenced textures
    for d in (BLOCK_OUT, ITEM_OUT):
        if os.path.isdir(d):
            for f in os.listdir(d):
                os.remove(os.path.join(d, f))

    total = 0
    blocks = texplan.needed_block_textures()
    for name in blocks:
        total += build(pack, name, manifest.TEXTURE_OPS.get(name), provenance, item=False)
    items = texplan.needed_item_textures()
    for name in items:
        spec = manifest.ITEM_TEXTURE_OPS.get(name)
        if spec is None:
            raise SystemExit(f"no ITEM_TEXTURE_OPS entry for item texture {name}")
        total += build(pack, name, spec, provenance, item=True)

    prov = {
        "pack": PACK_CREDIT,
        "license": PACK_LICENSE,
        "pack_version": "1.2.3",
        "pack_sha512": PACK_SHA512,
        "textures": provenance,
    }
    provpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "provenance.json")
    with open(provpath, "w") as f:
        json.dump(prov, f, indent=2)
        f.write("\n")

    print(f"wrote {len(blocks)} block + {len(items)} item textures, {total} bytes total")
    print(f"provenance -> {provpath}")


if __name__ == "__main__":
    main()
