#!/usr/bin/env python3
"""Glitched Husk texture driver (P6-W8 — see glitch_lib.py for the family language).

A humanoid shambler gone WRONG: desaturated corpse-gray flesh `#4A5248`, darker rag
band, cyan-tinted displaced shards (the off-axis torso chunk + half-face cluster),
magenta/cyan seam slivers (emissive), a magenta heart-core glowing through the chest
cracks, and two dead sockets with pinpoint magenta pupils.

One run writes FOUR files (renderer flickers between the pairs):
    glitched_husk.png + glitched_husk_glowmask.png
    glitched_husk_alt.png + glitched_husk_alt_glowmask.png  (datamosh frame)

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/glitched_husk.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glitch_lib import CYAN, MAGENTA, glitch_body, glow_eyes, heart_glow, seam  # noqa: E402
from paint_lib import GeoPainter, hexc, mix, mul  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/glitched_husk.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/glitched_husk.png"
OUT_ALT = ROOT / "src/main/resources/assets/eclipse/textures/entity/glitched_husk_alt.png"

SEED = 0x061174C4  # glitch husk

FLESH = hexc("#4A5248")
RAGS = hexc("#3E4440")
HEAD = hexc("#454B47")
LIMB = hexc("#444A46")
LEG = hexc("#3C4240")
SOCKET = hexc("#181B1A")
EYE_PX = [("north", 2, 4), ("north", 5, 4)]  # 8x8 face: pinpoint pupils


def husk_head(alt):
    base = glitch_body(HEAD, salt=37, alt=alt)

    def fn(px):
        if px.face == "north" and px.fy in (3, 4) and px.fx in (1, 2, 5, 6):
            col = SOCKET  # sunken dead sockets
            if (px.fx, px.fy) in ((2, 4), (5, 4)):
                col = mix(MAGENTA, col, 0.25)  # pupil (echoed in the glowmask)
            return col
        return fn_base(px)

    fn_base = base
    return fn


def paint(alt):
    painter = GeoPainter(GEO, seed=SEED)
    body_fn = glitch_body(FLESH, salt=31, alt=alt)
    # Torso wears a rag band across the hips (bottom rows of the side faces).
    painter.set_material("body", _with_rag_band(body_fn))
    painter.set_material("leg_*", glitch_body(LEG, salt=33, alt=alt))
    painter.set_material("arm_*", glitch_body(LIMB, salt=35, alt=alt))
    painter.set_material("head", husk_head(alt))
    # Displaced geometry reads corrupted even on the calm frame (cyan pre-tint).
    painter.set_material("shard_torso", glitch_body(FLESH, salt=39, alt=alt, tint=CYAN))
    painter.set_material("head_shard", glitch_body(HEAD, salt=43, alt=alt, tint=MAGENTA))
    painter.set_material("glow_seam", seam(alt=alt))  # auto-included in the glowmask
    painter.set_glow_painter("body", heart_glow(cy_frac=0.4, alt=alt))
    painter.set_glow_painter("head", glow_eyes(EYE_PX, color=MAGENTA))
    painter.paint(OUT_ALT if alt else OUT)


def _with_rag_band(fn):
    def wrapped(px):
        col = fn(px)
        if px.face in ("north", "south", "east", "west") and px.fy >= px.fh - 3 and col is not None:
            col = mix(col, mul(RAGS, 0.9), 0.75)
        return col

    return wrapped


def main():
    paint(alt=False)
    paint(alt=True)


if __name__ == "__main__":
    main()
