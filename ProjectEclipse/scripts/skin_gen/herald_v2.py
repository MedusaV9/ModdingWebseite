#!/usr/bin/env python3
"""Herald skin v2 (MOB-BOSS1) — 2x repaint of `textures/entity/herald.png`.

256x256 over the frozen 128x128 UV space (`docs/uv/herald.md`; vanilla normalizes UVs by
the LayerDefinition size, so the Java model is untouched). Palette identity kept from the
placeholder brief: near-black violet glass core #181224 laced with gold crack veins
#E8A83A (north face — v2 extends dimmer hairlines onto east/west/up), blazing gold inner
eye #FFD86A with the 2x2 void pupil #100A18, pale-violet corona shards #C88AFF, dark
umbral tentacles #241C36. Adds the v2 cubes: 4 crown spikes (72..88,0) with gold-lit tips
(they join the emissive pass during the roar) and 3 halo shards (72..84,8).

Run from the ProjectEclipse root: `python3 scripts/skin_gen/herald_v2.py`.
Deterministic (seeded) -> byte-identical output on every run.
"""

import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from boss_paint import Sheet, hexc, mix, mul  # noqa: E402

CORE = hexc("#181224")
FACET_A = hexc("#1C1530")
FACET_B = hexc("#150F20")
RIM = hexc("#2A2140")
DUST = hexc("#4A3C6E")
GOLD = hexc("#E8A83A")
GOLD_HOT = hexc("#FFD86A")
GOLD_DIM = hexc("#B07E2C")
EYE_HOT = hexc("#FFEDB0")
EYE = hexc("#FFD86A")
IRIS = hexc("#C89040")
PUPIL = hexc("#100A18")
SHARD = hexc("#C88AFF")
SHARD_HI = hexc("#E0C8FF")
SHARD_TIP = hexc("#F2E6FF")
SHARD_LO = hexc("#8E5BC8")
HALO = hexc("#D8B2FF")
HALO_TIP = hexc("#F6ECFF")
TENT = hexc("#241C36")
TENT_HI = hexc("#322852")
TENT_DOT = hexc("#150F20")
OBSIDIAN = hexc("#1C1530")

FACE_SALT = {"up": 11, "down": 23, "north": 37, "east": 53, "west": 71, "south": 89}

sheet = Sheet(seed=0x0EC1A5)

# --- gold crack veins on the core: random walks, precomputed per face -------------
# north keeps the loud placeholder veining; east/west/up get dim hairline spill-over.
VEINS = {}


def _walk_veins(face, count, size, rng, branch=0.18):
    pts = set()
    for _ in range(count):
        x = rng.randrange(size // 4, size * 3 // 4)
        y = rng.randrange(0, size // 3)
        while y < size:
            pts.add((x, y))
            if rng.random() < branch:
                bx = x
                for by in range(y, min(size, y + rng.randrange(2, 6))):
                    bx += rng.choice((-1, 0, 1))
                    if 0 <= bx < size:
                        pts.add((bx, by))
            x += rng.choice((-1, -1, 0, 1, 1))
            x = max(0, min(size - 1, x))
            y += 1
    VEINS[face] = pts


_rng = random.Random(0xC0FE)
_walk_veins("north", 3, 24, _rng)
_walk_veins("east", 1, 24, _rng)
_walk_veins("west", 1, 24, _rng)
_walk_veins("up", 1, 24, _rng)


def core_painter(face, fx, fy, fw, fh):
    # Faceted black glass: coarse tonal patches + sparse star dust + rim sheen.
    block = sheet.hash01(fx // 6, fy // 6, FACE_SALT[face])
    color = FACET_A if block < 0.35 else FACET_B if block < 0.65 else CORE
    if sheet.hash01(fx, fy, FACE_SALT[face] + 3) < 0.015:
        color = mix(color, DUST, 0.7)
    if fx <= 0 or fy <= 0 or fx >= fw - 1 or fy >= fh - 1:
        color = mix(color, RIM, 0.5)
    pts = VEINS.get(face)
    if pts and (fx, fy) in pts:
        hot = sheet.hash01(fx, fy, 91)
        if face == "north":
            color = mix(GOLD, GOLD_HOT, hot)
        else:
            color = mix(color, GOLD_DIM, 0.55 + 0.25 * hot)
    return color


def eye_painter(face, fx, fy, fw, fh):
    cx = (fx - (fw - 1) / 2) / max(1, fw / 2)
    cy = (fy - (fh - 1) / 2) / max(1, fh / 2)
    d = min(1.0, (cx * cx + cy * cy) ** 0.5)
    if face == "north":
        # 12x12 px face: 4x4 px void pupil dead center, iris ring around it.
        if abs(fx - (fw - 1) / 2) <= 1.5 and abs(fy - (fh - 1) / 2) <= 1.5:
            return PUPIL
        if abs(fx - (fw - 1) / 2) <= 2.5 and abs(fy - (fh - 1) / 2) <= 2.5:
            return IRIS
        return mix(EYE_HOT, EYE, d)
    return mix(mix(EYE, IRIS, 0.35), IRIS, d)  # dimmer molten sides


def crown_painter(face, fx, fy, fw, fh):
    t = fy / max(1, fh - 1)
    if face in ("up", "down"):
        return GOLD_HOT if face == "up" else OBSIDIAN
    if t < 0.55:
        # Gold-lit tip half (top of the spike): hot at the point, ember below.
        color = mix(GOLD_HOT, GOLD, t / 0.55)
    else:
        color = mix(GOLD_DIM, OBSIDIAN, (t - 0.55) / 0.45)
        if fx == 0:  # thin vein running down the shaded flank
            color = mix(color, GOLD_DIM, 0.5)
    return color


def shard_painter(face, fx, fy, fw, fh):
    t = fy / max(1, fh - 1)
    if face == "up":
        return SHARD_TIP
    if face == "down":
        return SHARD_LO
    color = mix(SHARD_TIP, mix(SHARD, SHARD_LO, 0.5), t)
    # Facet split: the right half of every side face runs one step brighter.
    if fx >= fw // 2:
        color = mix(color, SHARD_HI, 0.35)
    if fy <= 1:
        color = SHARD_TIP
    return color


def halo_painter(face, fx, fy, fw, fh):
    t = fy / max(1, fh - 1)
    if face == "up":
        return HALO_TIP
    return mix(HALO_TIP, HALO, min(1.0, t * 1.3))


def tentacle_painter(seg, salt):
    tip = seg % 4 == 3  # last segment of each chain fades out

    def paint(face, fx, fy, fw, fh):
        t = fy / max(1, fh - 1)
        # Muscle bulge: darker joint rows, lighter mid-band.
        band = 1.0 - abs(t - 0.5) * 2.0
        color = mix(TENT, TENT_HI, band * 0.55)
        if fy <= 0 or fy >= fh - 1:
            color = mul(color, 0.75)
        # One violet sheen column (wet chitin read).
        if fx == fw // 3:
            color = mul(color, 1.18)
        # Sucker dots down the north (inner) face.
        if face == "north" and fw > 2 and fy % 4 == 2 and fx == fw // 2:
            color = TENT_DOT
        if tip:
            color = mix(color, hexc("#0E0A15"), t * 0.6)
        noise = sheet.hash01(fx, fy, salt) * 0.08 - 0.04
        return mul(color, 1.0 + noise)
    return paint


def main():
    # core 12x12x12 @ (0,0)
    sheet.paint_box(0, 0, 12, 12, 12, core_painter)
    # inner eye 6x6x6 @ (48,0) — emissive, shadeless
    sheet.paint_box(48, 0, 6, 6, 6, eye_painter, shadeless=True)
    # crown spikes 1x5x1 @ (72+i*4,0) — v2 bones (emissive during the roar)
    for i in range(4):
        sheet.paint_box(72 + i * 4, 0, 1, 5, 1, crown_painter, shadeless=True)
    # halo shards 1x3x1 @ (72+i*4,8) — v2 bones (glow with the telegraph)
    for i in range(3):
        sheet.paint_box(72 + i * 4, 8, 1, 3, 1, halo_painter, shadeless=True)
    # corona shards 2x6x2 @ (i*8,32) — luminous crystal, shadeless like the placeholder
    for i in range(8):
        sheet.paint_box(i * 8, 32, 2, 6, 2, shard_painter, shadeless=True)
    # tentacle segments 2x6x2 @ (s*8,44)
    for s in range(16):
        sheet.paint_box(s * 8, 44, 2, 6, 2, tentacle_painter(s, 501 + s * 13))

    out = sheet.save("herald.png")
    print(f"herald v2 sheet written: {out} ({sheet.size}x{sheet.size})")


if __name__ == "__main__":
    main()
