#!/usr/bin/env python3
"""Glitched Hound texture driver (P6-W8 — see glitch_lib.py for the family language).

A lean quadruped with a FRAGMENTED FLOATING NECK: storm-desaturated hide `#45464E`,
near-black split jaw with a white-hot inner mouth, corrupted tints on the detached
neck fragment / hip shard / askew ear, emissive seam slivers in the neck gap, cyan
pinpoint eyes, and the family heart-core glowing through the ribcage.

One run writes FOUR files (renderer flickers between the pairs):
    glitched_hound.png + glitched_hound_glowmask.png
    glitched_hound_alt.png + glitched_hound_alt_glowmask.png  (datamosh frame)

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/glitched_hound.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glitch_lib import CYAN, MAGENTA, WHITE, glitch_body, glow_eyes, heart_glow, seam  # noqa: E402
from paint_lib import GeoPainter, hexc, mix, mul  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/glitched_hound.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/glitched_hound.png"
OUT_ALT = ROOT / "src/main/resources/assets/eclipse/textures/entity/glitched_hound_alt.png"

SEED = 0x0611D064  # glitch hound

HIDE = hexc("#45464E")
HIDE_DARK = hexc("#393A41")
JAW = hexc("#26272C")
MOUTH = hexc("#D9F6FF")
EYE_PX = [("north", 1, 1), ("north", 4, 1)]  # 6x5 head face


def hound_jaw(alt):
    base = glitch_body(JAW, salt=57, alt=alt)

    def fn(px):
        if px.face == "up":
            return mix(MOUTH, WHITE, px.noise(59) * 0.4)  # inner mouth, glow-echoed
        return base(px)

    return fn


def jaw_glow(px):
    if px.face == "up":
        return mix(MOUTH, WHITE, px.noise(59) * 0.4)
    return None


def hound_head(alt):
    base = glitch_body(HIDE, salt=51, alt=alt)

    def fn(px):
        if (px.face, px.fx, px.fy) in EYE_PX:
            return mix(CYAN, WHITE, 0.3)
        col = base(px)
        if px.face in ("north", "east", "west") and px.fy >= px.fh - 1:
            col = mul(col, 0.7)  # upper-muzzle shadow over the split jaw
        return col

    return fn


def paint(alt):
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("body", glitch_body(HIDE, salt=31, alt=alt))
    painter.set_material("leg_*", glitch_body(HIDE_DARK, salt=33, alt=alt))
    painter.set_material("tail", glitch_body(HIDE_DARK, salt=35, alt=alt))
    painter.set_material("head", hound_head(alt))
    painter.set_material("jaw", hound_jaw(alt))
    # Corrupted tints on every displaced fragment (they read broken on both frames).
    painter.set_material("neck_shard", glitch_body(HIDE, salt=39, alt=alt, tint=CYAN))
    painter.set_material("hips_shard", glitch_body(HIDE, salt=43, alt=alt, tint=MAGENTA))
    painter.set_material("ear_shard", glitch_body(HIDE_DARK, salt=47, alt=alt, tint=MAGENTA))
    painter.set_material("glow_seam", seam(alt=alt))  # auto-included in the glowmask
    painter.set_glow_painter("body", heart_glow(cy_frac=0.5, radius=0.28, alt=alt))
    painter.set_glow_painter("head", glow_eyes(EYE_PX, color=CYAN))
    painter.set_glow_painter("jaw", jaw_glow)
    painter.paint(OUT_ALT if alt else OUT)


def main():
    paint(alt=False)
    paint(alt=True)


if __name__ == "__main__":
    main()
