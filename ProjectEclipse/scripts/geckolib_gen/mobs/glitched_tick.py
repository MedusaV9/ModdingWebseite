#!/usr/bin/env python3
"""Glitched Tick texture driver (P6-W8 — see glitch_lib.py for the family language).

A half-block shard-mite: pale under-body `#5A5B66`, near-black SPLIT CARAPACE plates
with heavy RGB-split edge tearing, the emissive magenta `glow_core` blazing in the
gap between the plates (flame-style gradient), dark stub legs and a mandibled head
with cyan pinpoint eyes.

One run writes FOUR files (renderer flickers between the pairs):
    glitched_tick.png + glitched_tick_glowmask.png
    glitched_tick_alt.png + glitched_tick_alt_glowmask.png  (datamosh frame)

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/glitched_tick.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glitch_lib import CYAN, HEART_CORE, HEART_HALO, WHITE, glitch_body, glow_eyes, seam  # noqa: E402
from paint_lib import GeoPainter, flame, hexc, mix  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/glitched_tick.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/glitched_tick.png"
OUT_ALT = ROOT / "src/main/resources/assets/eclipse/textures/entity/glitched_tick_alt.png"

SEED = 0x061171CC  # glitch tick

BODY = hexc("#5A5B66")
PLATE = hexc("#3A3B44")
LEG = hexc("#2E2F36")
EYE_PX = [("north", 0, 0), ("north", 3, 0)]  # 4x3 head face


def tick_head(alt):
    base = glitch_body(BODY, salt=51, alt=alt)

    def fn(px):
        if (px.face, px.fx, px.fy) in EYE_PX:
            return mix(CYAN, WHITE, 0.3)
        return base(px)

    return fn


def core_flame(alt):
    """The heart-core in the carapace split: shadeless magenta flame gradient; the
    alt frame runs it white-hot (the flicker makes the core 'surge')."""
    core = mix(HEART_CORE, WHITE, 0.45) if alt else HEART_CORE
    return flame(core, HEART_HALO, salt=23)


def paint(alt):
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("body", glitch_body(BODY, salt=31, alt=alt))
    painter.set_material("carapace_*", glitch_body(PLATE, salt=33, alt=alt))
    painter.set_material("legs_*", glitch_body(LEG, salt=35, alt=alt))
    painter.set_material("head", tick_head(alt))
    painter.set_material("glow_core", core_flame(alt))  # glow_ bone: auto glowmask copy
    # Seam glow along the split: stamp the plates' INNER edges into the glowmask so
    # the gap reads molten even when the core bone is hidden by the closed plates.
    painter.set_glow_painter("carapace_right", _plate_rim_glow(inner_is_max_fx=True, alt=alt))
    painter.set_glow_painter("carapace_left", _plate_rim_glow(inner_is_max_fx=False, alt=alt))
    painter.set_glow_painter("head", glow_eyes(EYE_PX, color=CYAN))
    painter.paint(OUT_ALT if alt else OUT)


def _plate_rim_glow(inner_is_max_fx, alt):
    rim = seam(alt=alt, salt=61)

    def fn(px):
        if px.face != "up":
            return None
        inner = px.fx == px.fw - 1 if inner_is_max_fx else px.fx == 0
        return rim(px) if inner else None

    return fn


def main():
    paint(alt=False)
    paint(alt=True)


if __name__ == "__main__":
    main()
