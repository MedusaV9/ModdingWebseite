#!/usr/bin/env python3
"""Ferryman skin v2 (MOB-BOSS1) — 2x repaint of `textures/entity/ferryman.png`.

256x256 over the frozen 128x128 UV space (`docs/uv/ferryman.md`; vanilla normalizes UVs
by the LayerDefinition size, so the Java model is untouched). Palette identity kept from
the placeholder brief: drowned green-black robe #202C28 + barnacle #5E7466, hood #141B18
with the TRANSPARENT north face (open cowl), bone skull #D8D2BE with hollow sockets,
soul-teal eye slit #8FF2DE, waterlogged oar #4A3A28/#3C2F20, wet iron chain #626670,
lantern #3A3E46, soul flame #A8F7E6. Adds the v2 cubes: 3 cloak tatters (24..48,76),
3 chain-link crosspieces (0..24,76) and the lantern cap (48,76).

Run from the ProjectEclipse root: `python3 scripts/skin_gen/ferryman_v2.py`.
Deterministic (seeded) -> byte-identical output on every run.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from boss_paint import Sheet, flat, hexc, mix, mul  # noqa: E402

ROBE = hexc("#202C28")
ROBE_DEEP = hexc("#18221E")
BARNACLE = hexc("#5E7466")
BARNACLE_HI = hexc("#7A9284")
HOOD = hexc("#141B18")
SKULL = hexc("#D8D2BE")
SKULL_SHADOW = hexc("#A8A28C")
SOCKET = hexc("#0E1410")
EYE = hexc("#8FF2DE")
EYE_HOT = hexc("#D9FFF6")
OAR = hexc("#4A3A28")
OAR_HI = hexc("#5C4A34")
OAR_LO = hexc("#3A2D1E")
GRIP = hexc("#2E2418")
BLADE = hexc("#3C2F20")
STAIN = hexc("#33301F")
CHAIN = hexc("#626670")
CHAIN_HI = hexc("#7E828C")
RUST = hexc("#4A3E36")
IRON = hexc("#2E323A")
IRON_HI = hexc("#6A707C")
LANTERN = hexc("#3A3E46")
GLASS = hexc("#274441")
GLASS_GLOW = hexc("#3F6B62")
FLAME = hexc("#A8F7E6")
FLAME_HOT = hexc("#E8FFF8")
FLAME_RIM = hexc("#7ADCC8")

FACE_SALT = {"up": 11, "down": 23, "north": 37, "east": 53, "west": 71, "south": 89}

sheet = Sheet(seed=0xFE221)


def robe_painter(salt, hem=True, barnacle_bias=1.0):
    """Drowned wool: vertical weave streaks, tide line, barnacle colonies, dark hem."""
    def paint(face, fx, fy, fw, fh):
        t = fy / max(1, fh - 1)
        color = mix(mul(ROBE, 1.06), mul(ROBE, 0.82), t)
        # Vertical weave: per-column tone with a slow row drift.
        weave = sheet.hash01(fx, salt + FACE_SALT[face], 1) * 0.10 - 0.05
        weave += (sheet.hash01(fx, fy // 5, salt) - 0.5) * 0.05
        color = mul(color, 1.0 + weave)
        # Salt tide line ~62% down: one pale, slightly mineral row.
        if fh > 8 and fy == int(fh * 0.62):
            color = mix(color, BARNACLE_HI, 0.22)
        # Barnacle colonies, denser toward the waterline (bottom).
        block = sheet.hash01(fx // 4, fy // 4, salt + FACE_SALT[face] + 5)
        if block < (0.02 + 0.07 * t) * barnacle_bias:
            inner = sheet.hash01(fx, fy, salt + 13)
            color = mix(BARNACLE, BARNACLE_HI, inner)
        # Ragged dark hem.
        if hem and fh > 8 and fy >= fh - 2:
            color = mix(color, ROBE_DEEP, 0.75)
        return color
    return paint


def strip_painter(salt, ragged_rows):
    """Hem strip / tatter: fibrous, with transparent notches torn into the bottom."""
    def paint(face, fx, fy, fw, fh):
        if fy >= fh - ragged_rows and face not in ("up", "down"):
            # Torn bottom: notch columns out (deterministic per strip).
            depth = int(sheet.hash01(fx, salt, 3) * ragged_rows + 0.5)
            if fy >= fh - depth:
                return None
        color = mix(mul(ROBE_DEEP, 1.08), mul(ROBE_DEEP, 0.85), fy / max(1, fh - 1))
        fiber = sheet.hash01(fx, salt + FACE_SALT[face], 9) * 0.12 - 0.06
        color = mul(color, 1.0 + fiber)
        if sheet.hash01(fx // 2, fy // 3, salt + 21) < 0.03:
            color = mix(color, BARNACLE, 0.6)
        return color
    return paint


def skull_painter(face, fx, fy, fw, fh):
    """Old bone: brow shadow, cheek hollows, cracks; face features on the north face."""
    t = fy / max(1, fh - 1)
    color = mix(SKULL, SKULL_SHADOW, t * 0.45)
    grain = sheet.hash01(fx, fy, 31) * 0.08 - 0.04
    color = mul(color, 1.0 + grain)
    # Winding hairline crack (one per face, hash-driven walk).
    crack_x = int(fw * 0.3) + int(sheet.hash01(fy // 2, FACE_SALT[face], 17) * 3) - 1
    if fx == crack_x and sheet.hash01(fy, FACE_SALT[face], 19) < 0.7:
        color = mul(color, 0.72)
    if face == "north":
        # 14x14 px face: sockets at texel (1..2, 2..3) and (4..5, 2..3).
        if 4 <= fy <= 7 and (2 <= fx <= 5 or 8 <= fx <= 11):
            edge = fy == 4 or fx in (2, 5, 8, 11)
            return mix(SOCKET, SKULL_SHADOW, 0.25 if edge else 0.0)
        if 8 <= fy <= 9 and 6 <= fx <= 7:  # nasal notch
            return mix(SOCKET, color, 0.3)
        if fy >= 12:  # teeth row: alternating bone/gap columns
            return mul(color, 0.55) if (fx // 2) % 2 else mix(color, hexc("#E8E2CE"), 0.4)
    return color


def hood_painter(face, fx, fy, fw, fh):
    if face == "north":
        return None  # Open cowl: the skull shows inside.
    t = fy / max(1, fh - 1)
    color = mix(mul(HOOD, 1.1), mul(HOOD, 0.8), t)
    weave = sheet.hash01(fx, FACE_SALT[face], 41) * 0.1 - 0.05
    color = mul(color, 1.0 + weave)
    # Weathered front rim: the columns bordering the opening catch pale light.
    if face in ("east", "west") and (fx <= 1 if face == "west" else fx >= fw - 2):
        color = mix(color, BARNACLE, 0.25)
    if face == "up" and fy <= 1:
        color = mix(color, BARNACLE, 0.15)
    return color


def eye_painter(face, fx, fy, fw, fh):
    cx, cy = abs(fx - (fw - 1) / 2) / max(1, fw / 2), abs(fy - (fh - 1) / 2) / max(1, fh / 2)
    return mix(EYE_HOT, EYE, max(cx, cy) * 0.9)


def arm_painter(salt):
    robe = robe_painter(salt, hem=False, barnacle_bias=0.7)

    def paint(face, fx, fy, fw, fh):
        t = fy / max(1, fh - 1)
        if t < 0.78:
            return robe(face, fx, fy, fw, fh)
        if t < 0.83:  # cuff ring
            return mul(ROBE_DEEP, 0.9)
        # Bony hand: knuckle ridges as alternating column tones.
        color = mix(SKULL, SKULL_SHADOW, 0.3 + 0.3 * (t - 0.83) / 0.17)
        if (fx // 2) % 2:
            color = mul(color, 0.86)
        return color
    return paint


def oar_painter(face, fx, fy, fw, fh):
    t = fy / max(1, fh - 1)
    color = OAR
    # Long wood grain: column streaks broken every few rows.
    streak = sheet.hash01(fx, fy // 6, 47)
    color = mix(color, OAR_HI if streak > 0.6 else OAR_LO, abs(streak - 0.5) * 0.5)
    # Two leather grip wraps around the pivot (hands live mid-shaft).
    if 0.40 <= t <= 0.45 or 0.53 <= t <= 0.58:
        color = mix(GRIP, mul(GRIP, 1.25), sheet.hash01(fx, fy, 3))
    # Waterline stain toward the blade end.
    if t > 0.8:
        color = mix(color, STAIN, (t - 0.8) * 3.0)
    return color


def blade_painter(face, fx, fy, fw, fh):
    color = mix(mul(BLADE, 1.08), mul(BLADE, 0.8), fy / max(1, fh - 1))
    grain = sheet.hash01(fy, FACE_SALT[face], 51) * 0.12 - 0.06
    color = mul(color, 1.0 + grain)
    if fy >= fh - 2:  # chipped, waterlogged edge
        color = mix(color, STAIN, 0.6)
    if sheet.hash01(fx // 3, fy // 3, 55) < 0.03:
        color = mix(color, BARNACLE, 0.5)
    return color


def chain_painter(face, fx, fy, fw, fh):
    color = CHAIN
    if fy <= 0 or fy >= fh - 1:  # joint shadow top/bottom of the segment
        color = mul(color, 0.72)
    elif fy in (fh // 2, fh // 2 - 1):
        color = CHAIN_HI  # wet spec glint mid-link
    if sheet.hash01(fx, fy, 61) < 0.12:
        color = mix(color, RUST, 0.5)
    return color


def link_painter(face, fx, fy, fw, fh):
    color = mul(CHAIN, 0.9)
    if fw >= 4 and fh >= 4 and 1 <= fx <= fw - 2 and 1 <= fy <= fh - 2:
        color = mul(LANTERN, 0.85)  # the eye of the link reads as a hole
    if fx == 0 and fy == 0:
        color = CHAIN_HI
    if sheet.hash01(fx, fy, 67) < 0.15:
        color = mix(color, RUST, 0.4)
    return color


def lantern_painter(face, fx, fy, fw, fh):
    if face in ("up", "down"):
        color = IRON
        if face == "down" and fy % 2 == 0:  # vent slits
            color = mul(color, 0.7)
        return color
    # Side faces: iron frame border, soul-lit glass inside.
    if fx <= 1 or fy <= 1 or fx >= fw - 2 or fy >= fh - 2:
        color = IRON
        if (fx <= 1 or fx >= fw - 2) and (fy <= 1 or fy >= fh - 2):
            color = IRON_HI  # corner rivets
        return color
    cx = abs(fx - (fw - 1) / 2) / max(1, fw / 2)
    cy = abs(fy - (fh - 1) / 2) / max(1, fh / 2)
    return mix(GLASS_GLOW, GLASS, min(1.0, (cx * cx + cy * cy) ** 0.5))


def cap_painter(face, fx, fy, fw, fh):
    color = IRON
    if face == "up":
        cx, cy = abs(fx - (fw - 1) / 2), abs(fy - (fh - 1) / 2)
        if cx <= 1 and cy <= 1:
            color = mul(IRON, 0.6)  # chain seat
        elif fx == 0 or fy == 0:
            color = IRON_HI
    return color


def flame_painter(face, fx, fy, fw, fh):
    cx = abs(fx - (fw - 1) / 2) / max(1, fw / 2)
    cy = abs(fy - (fh - 1) / 2) / max(1, fh / 2)
    d = min(1.0, (cx * cx + cy * cy) ** 0.5)
    color = mix(FLAME_HOT, FLAME, d * 1.4)
    if fy >= fh - 1:
        color = FLAME_RIM
    return color


def main():
    # body 10x26x8 @ (0,0)
    sheet.paint_box(0, 0, 10, 26, 8, robe_painter(101))
    # hood 9x9x9 @ (40,0) — north face transparent
    sheet.paint_box(40, 0, 9, 9, 9, hood_painter)
    # head 7x7x7 @ (80,0)
    sheet.paint_box(80, 0, 7, 7, 7, skull_painter)
    # eyes 5x2x1 @ (108,0) — emissive, shadeless
    sheet.paint_box(108, 0, 5, 2, 1, eye_painter, shadeless=True)
    # arms 3x20x3 @ (0,36) / (16,36)
    sheet.paint_box(0, 36, 3, 20, 3, arm_painter(211))
    sheet.paint_box(16, 36, 3, 20, 3, arm_painter(223))
    # hem strips 2x6x1 @ (32+i*8,36)
    for i in range(4):
        sheet.paint_box(32 + i * 8, 36, 2, 6, 1, strip_painter(301 + i * 7, ragged_rows=2))
    # long tatters 2x8x1 @ (24+i*8,76) — v2 bones
    for i in range(3):
        sheet.paint_box(24 + i * 8, 76, 2, 8, 1, strip_painter(401 + i * 11, ragged_rows=3))
    # oar 2x36x2 @ (64,36) + blade 1x6x5 @ (76,36)
    sheet.paint_box(64, 36, 2, 36, 2, oar_painter)
    sheet.paint_box(76, 36, 1, 6, 5, blade_painter)
    # chain 1x4x1 @ (92+k*6,36); link crosspieces 2x2x1 @ (k*8,76) — v2 bones
    for k in range(3):
        sheet.paint_box(92 + k * 6, 36, 1, 4, 1, chain_painter)
        sheet.paint_box(k * 8, 76, 2, 2, 1, link_painter)
    # lantern 4x5x4 @ (92,44) + cap 3x1x3 @ (48,76) — v2 bone
    sheet.paint_box(92, 44, 4, 5, 4, lantern_painter)
    sheet.paint_box(48, 76, 3, 1, 3, cap_painter)
    # flame 2x2x2 @ (110,36) — emissive, shadeless
    sheet.paint_box(110, 36, 2, 2, 2, flame_painter, shadeless=True)

    out = sheet.save("ferryman.png")
    print(f"ferryman v2 sheet written: {out} ({sheet.size}x{sheet.size})")


if __name__ == "__main__":
    main()
