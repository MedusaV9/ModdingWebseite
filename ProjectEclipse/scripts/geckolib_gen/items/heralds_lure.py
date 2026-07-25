#!/usr/bin/env python3
"""`heralds_lure` GeckoLib ITEM texture driver (PLAN-ITEMS B2).

Four obsidian shard prongs (corona-glass black-purple, faint ACCENT_DEEP sheen on
the facet edges) caging a floating heart-fragment core: the `glow_core` bone burns
CRIMSON at the heart and cools to herald GOLD at the rim — the recipe (heart
fragment) and the summoned boss (herald gold) in one emissive. The spark cube on
top is the offering's rising ember.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/items/heralds_lure.py
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, mix  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/item/heralds_lure.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/item/lure/heralds_lure.png"

SEED = 0x10BE  # "LURE"

OBSIDIAN = hexc("#1A1128")
OBSIDIAN_LIT = hexc("#2E2347")
ACCENT_DEEP = hexc("#7B4FD0")
CRIMSON = hexc("#A6193A")
SCARLET = hexc("#E73753")
GOLD = hexc("#E8A83A")
GOLD_LIGHT = hexc("#FFD86A")


def obsidian_facet(salt):
    """Corona-glass shard: near-black purple with diagonal sheen streaks and a
    1px ACCENT_DEEP facet edge so the prongs read against dark backgrounds."""

    def fn(px):
        col = OBSIDIAN
        if (px.gx + px.gy) % 5 in (0, 1) and px.noise(salt) > 0.4:
            col = OBSIDIAN_LIT
        if px.noise(salt + 7) > 0.965:
            col = mix(OBSIDIAN_LIT, ACCENT_DEEP, 0.5)  # glassy glint
        on_edge = px.fx == 0 or px.fx == px.fw - 1
        if on_edge and px.face in ("north", "south", "east", "west"):
            col = mix(col, ACCENT_DEEP, 0.35)
        return col

    return fn


def heart_core(px):
    """Heart-fragment core: a wide CRIMSON heart that only gilds at the very rim —
    plain `flame()` turned the 3x3 faces mostly gold; this keeps the recipe's heart
    readable. Shadeless + auto-glowmasked by the glow_ bone prefix."""
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = math.hypot((px.fx - cx) / max(cx, 0.5), (px.fy - cy) / max(cy, 0.5))
    t = max(0.0, min(1.0, (d - 0.85) * 2.2 + (px.noise(17) - 0.5) * 0.2))
    return mix(mix(SCARLET, CRIMSON, 0.4), GOLD, t)


heart_core.shadeless = True


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("prong_*", obsidian_facet(salt=11))
    painter.set_material("glow_core", heart_core)
    # The rising ember spark above the heart stays herald gold.
    painter.set_cube_material("glow_core", 1, flame(GOLD_LIGHT, GOLD, salt=19))
    painter.paint(OUT)


if __name__ == "__main__":
    main()
