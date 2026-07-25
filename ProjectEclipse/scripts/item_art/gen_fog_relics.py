#!/usr/bin/env python3
"""PLAN-ITEMS B4: the two Fog Tyrant trophy relics that never had painter scripts.

`fog_core.png` (was 158 off-palette gradient colors — the worst icon in the set) and
`fog_cloak_trim.png` (25 colors, soft contrast) redrawn on the shared
`eclipse_palette` ramp, silhouette-first, <= 20 opaque colors each:

  * fog_core       — a condensed storm knot: DIM/HAIRLINE fog-grey swirl body wound
                     around a dark eye, one SOUL_TEAL lightning glint stitched across
                     it (the Tyrant's electric-seam language), `finish()` applied.
  * fog_cloak_trim — a folded mantle cut: three layered grey-purple drape folds
                     falling to a ragged hem, pinned by a 1px TEXT clasp.

Deterministic (no randomness) — reruns are byte-identical.

Run from anywhere:
    python3 scripts/item_art/gen_fog_relics.py
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import (  # noqa: E402
    DIM, GLOW_WHITE, HAIRLINE, PURPLE_DARK, SOUL_TEAL, TEXT,
    canvas, finish, mix, put, save,
)

OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item"
)

# Fog-grey ramp between the frozen tokens (mirrors the tyrant's slate-in-purple look).
FOG_DARK = mix(HAIRLINE, DIM, 0.18)    # deep fog shadow
FOG = mix(HAIRLINE, DIM, 0.52)         # fog body
FOG_LIGHT = mix(DIM, TEXT, 0.22)       # lit fog crest


def fog_core():
    """Condensed storm knot: spiral fog bands wound around a dark eye."""
    img = canvas()
    cx = cy = 7.5
    for y in range(16):
        for x in range(16):
            r = math.hypot(x - cx, y - cy)
            if r > 5.7:
                continue
            if r < 1.4:
                col = PURPLE_DARK  # the knot's dark eye
            else:
                # Two-armed spiral: band index from angle + radius (deterministic).
                a = math.atan2(y - cy, x - cx)
                band = int((a / math.pi + r * 0.42) * 2.0) % 3
                col = (FOG_DARK, FOG, FOG_LIGHT)[band]
            put(img, ((x, y),), col)
    # Wisp tails escaping the knot (silhouette interest at 16px).
    put(img, ((13, 5), (14, 4)), FOG)
    put(img, ((2, 11), (1, 12)), FOG_DARK)

    finish(img)
    # Single SOUL_TEAL lightning glint stitched across the knot (glow color —
    # untouched by finish, the one hot accent the verdict asks for).
    put(img, ((8, 4), (7, 5), (8, 6), (7, 7), (8, 8)), SOUL_TEAL)
    put(img, ((8, 6),), GLOW_WHITE)  # the flash at the kink
    return img


def fog_cloak_trim():
    """Folded mantle cut: three layered drape folds under a 1px TEXT clasp."""
    img = canvas()

    # Back fold (darkest, widest) — falls from the clasp to the lower right.
    for i in range(10):
        y = 3 + i
        put(img, ((6 + i // 2 + dx, y) for dx in range(4)), FOG_DARK)
    # Middle fold — the main drape body.
    for i in range(11):
        y = 2 + i
        put(img, ((4 + i // 3 + dx, y) for dx in range(3)), FOG)
    # Front fold (lit crest) — narrow, catches the fog light.
    for i in range(9):
        y = 2 + i
        put(img, ((3 + i // 4, y),), FOG_LIGHT)
    # Purple lining flashes where the mantle turns open.
    put(img, ((7, 6), (8, 7), (8, 8), (9, 9)), PURPLE_DARK)
    # Ragged hem: staggered tips so the outline pass cuts separate points.
    put(img, ((5, 13), (6, 13), (9, 13), (10, 13), (6, 14), (10, 14)), FOG_DARK)
    put(img, ((5, 12), (9, 12)), FOG)

    finish(img)
    # 1px TEXT clasp pinning the cut (post-finish so it stays exact), plus a
    # cold SOUL_TEAL residue drop still clinging to the hem.
    put(img, ((4, 2),), TEXT)
    put(img, ((5, 2),), GLOW_WHITE)
    put(img, ((11, 14),), SOUL_TEAL)
    return img


def main():
    painters = {
        "fog_core": fog_core,
        "fog_cloak_trim": fog_cloak_trim,
    }
    for name, painter in painters.items():
        img = painter()
        assert img.size == (16, 16) and img.mode == "RGBA"
        colors = {p for p in img.convert("RGBA").getdata() if p[3] >= 128}
        assert len(colors) <= 20, f"{name}: {len(colors)} colors (budget 20)"
        save(img, OUT / f"{name}.png")


if __name__ == "__main__":
    main()
