#!/usr/bin/env python3
"""WB-ART tracker family: `compass_of_watcher_00..31` and `grave_dowser_00..31`
(16x16 item icons, 32 needle angles each).

Frame semantics match the committed placeholders (and the `angle` override
chains in `models/item/compass_of_watcher.json` / `grave_dowser.json`):
frame 00 points DOWN, 08 LEFT, 16 UP, 24 RIGHT — i.e. needle direction
``(-sin, cos)`` of ``2*pi*frame/32`` in screen coordinates.

Two skins over one dial painter:
  * compass_of_watcher — aubergine casing, rune ticks, a watcher-eye pivot
    (accent iris ring + black pupil) and a hot-magenta needle.
  * grave_dowser — bone circlet over mossy grave stone, a forked bone
    dowsing-rod needle with a soul-teal tip.

The dial goes through the shared `finish()` pass; the needle and pivot are
painted after it so they stay crisp and unshaded. Deterministic.

Run from anywhere:
    python3 scripts/item_art/gen_trackers.py
"""

import math
from pathlib import Path
import sys

from PIL import ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import (  # noqa: E402
    ACCENT, ACCENT_DEEP, BONE, BONE_DARK, BONE_LIGHT, DIM, GLOW_MAGENTA,
    GLOW_WHITE, GOOD, HAIRLINE, PANEL, PANEL_RAISED, PURPLE_DARK, SOUL_TEAL,
    canvas, finish, mix, mul, put, rgba, save,
)

OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item"
)

FRAMES = 32
CENTER = 7.5


def direction(frame):
    """Needle unit vector in screen coords: 00 down, 08 left, 16 up, 24 right."""
    a = 2.0 * math.pi * frame / FRAMES
    return -math.sin(a), math.cos(a)


def radial_px(dx, dy, r0, r1, steps=24):
    """Deduped pixel chain along direction (dx, dy) between radii r0..r1."""
    pts = []
    for i in range(steps + 1):
        r = r0 + (r1 - r0) * i / steps
        pts.append((round(CENTER + dx * r), round(CENTER + dy * r)))
    return list(dict.fromkeys(pts))


def dial(casing, casing_dark, face, tick, tick_major):
    """Round tracker dial: casing ring, face, cardinal + diagonal ticks."""
    img = canvas()
    d = ImageDraw.Draw(img)
    d.ellipse([1, 1, 14, 14], fill=rgba(casing))
    put(img, ((2, 11), (2, 12), (3, 12), (3, 13), (4, 13),
              (11, 13), (12, 13), (12, 12), (13, 12), (13, 11)), casing_dark)
    d.ellipse([3, 3, 12, 12], fill=rgba(face))
    # Cardinal ticks (north is the brighter, watched direction).
    put(img, ((7, 3), (8, 3)), tick_major)
    put(img, ((7, 12), (8, 12), (3, 7), (3, 8), (12, 7), (12, 8)), tick)
    # Diagonal minor ticks.
    put(img, ((4, 4), (11, 4), (4, 11), (11, 11)), casing_dark)
    return finish(img)


def compass_frame(base, frame):
    img = base.copy()
    dx, dy = direction(frame)
    # Tail (counterweight) and hot needle, painted unshaded over the finish.
    put(img, radial_px(-dx, -dy, 1.9, 3.4), DIM)
    put(img, radial_px(dx, dy, 1.9, 4.4), GLOW_MAGENTA)
    put(img, radial_px(dx, dy, 4.7, 4.8, steps=1), GLOW_WHITE)
    # Watcher-eye pivot: accent iris ring around a black 2x2 pupil.
    put(img, ((7, 6), (8, 6), (6, 7), (9, 7), (6, 8), (9, 8), (7, 9), (8, 9)),
        ACCENT_DEEP)
    put(img, ((7, 6), (6, 7)), ACCENT)
    put(img, ((7, 7), (8, 7), (7, 8), (8, 8)), PANEL)
    return img


def dowser_frame(base, frame):
    img = base.copy()
    dx, dy = direction(frame)
    a = math.atan2(dy, dx)
    # Forked tail: two bone prongs splayed off the back of the rod.
    for da in (math.pi - 0.55, math.pi + 0.55):
        pdx, pdy = math.cos(a + da), math.sin(a + da)
        put(img, radial_px(pdx, pdy, 1.6, 3.6), BONE_DARK)
    # Bone rod with a soul-teal seeking tip.
    put(img, radial_px(dx, dy, 1.2, 3.4), BONE)
    put(img, radial_px(dx, dy, 3.4, 4.6), SOUL_TEAL)
    put(img, radial_px(dx, dy, 4.7, 4.8, steps=1), GLOW_WHITE)
    # Bone-socket pivot.
    put(img, ((7, 7), (8, 7), (7, 8), (8, 8)), BONE_DARK)
    put(img, ((7, 7),), BONE_LIGHT)
    return img


def main():
    compass_base = dial(
        casing=ACCENT_DEEP, casing_dark=PURPLE_DARK, face=PANEL_RAISED,
        tick=HAIRLINE, tick_major=ACCENT)
    stone = mix(HAIRLINE, PANEL, 0.35)
    dowser_base = dial(
        casing=BONE_DARK, casing_dark=mul(BONE_DARK, 0.72), face=stone,
        tick=mul(GOOD, 0.55), tick_major=GOOD)

    for frame in range(FRAMES):
        img = compass_frame(compass_base, frame)
        assert img.size == (16, 16) and img.mode == "RGBA"
        save(img, OUT / f"compass_of_watcher_{frame:02d}.png")
    for frame in range(FRAMES):
        img = dowser_frame(dowser_base, frame)
        assert img.size == (16, 16) and img.mode == "RGBA"
        save(img, OUT / f"grave_dowser_{frame:02d}.png")


if __name__ == "__main__":
    main()
