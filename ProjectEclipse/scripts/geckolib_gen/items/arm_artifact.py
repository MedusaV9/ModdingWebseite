#!/usr/bin/env python3
"""Arm artifact texture driver (PLAN-ITEMS A2) — GeckoLib ITEM geo upgrade.

Paints `geo/item/arm_artifact.geo.json` (64x64): a severed, mummified forearm in the
frozen bone/parchment ramp (`scripts/item_art/eclipse_palette.py` BONE_* tones), a
crimson stump ring (`glow_stump`, DANGER-crimson emissive) and the floating ledger-light
mote the palm cups (`glow_ledger`, ACCENT `#B98CFF` — the artifact-menu identity color).
A faint ACCENT light-spill is painted into the PALM's glowmask pixels (up face only), so
the mote reads as actually lighting the hand (drift_lantern shine-through convention).

Writes `textures/item/artifact/arm_artifact.png` + `_glowmask.png`.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/items/arm_artifact.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, mix, mul, weave  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/item/arm_artifact.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/item/artifact/arm_artifact.png"

SEED = 0xA53A97  # "arm" — fixed, never change (byte-identical reruns)

WHITE = hexc("#FFFFFF")
# eclipse_palette.py bone/parchment ramp + crimson/vitae + UI accent (frozen tokens).
BONE_DARK = hexc("#6E6254")
BONE = hexc("#C9BCA4")
BONE_LIGHT = hexc("#EFE6D2")
CRIMSON_DARK = hexc("#520C22")
CRIMSON = hexc("#A6193A")
SCARLET = hexc("#E73753")
ACCENT = hexc("#B98CFF")
ACCENT_DEEP = hexc("#7B4FD0")


def mummy(base, salt):
    """Parchment-wrapped flesh: vertical bandage striations + dry cracks."""
    base_fn = weave(base, direction=1, amp=0.3, salt=salt)

    def fn(px):
        col = base_fn(px)
        # Bandage seams: a dark wrap line every 3 rows, offset per column.
        if (px.gy + int(px.noise(salt + 3, y=0) * 3)) % 3 == 0:
            col = mul(col, 0.8)
        # Rare dried-blood speck near the wrap seams.
        if px.noise(salt + 7) > 0.965:
            col = mix(col, CRIMSON_DARK, 0.6)
        return col

    return fn


def knuckled(base, salt):
    """Hand/finger parchment with pale knuckle highlights on the top rows."""
    base_fn = mummy(base, salt)

    def fn(px):
        col = base_fn(px)
        if px.face in ("north", "south", "east", "west") and px.fy == 0:
            col = mix(col, BONE_LIGHT, 0.5)
        return col

    return fn


def stump(px):
    """Severed cross-section: crimson ring, near-black clot center on the down face."""
    if px.face == "down":
        cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
        d = max(abs(px.fx - cx), abs(px.fy - cy)) / max(cx, 0.5)
        if d < 0.55:
            return mix(CRIMSON_DARK, hexc("#2A0511"), 0.5 + 0.3 * px.noise(31))
        return mix(CRIMSON, SCARLET, 0.35 * px.noise(33))
    return mix(CRIMSON, SCARLET, 0.25 + 0.35 * px.noise(35))


stump.shadeless = True


def palm_spill(px):
    """Faint ACCENT ledger-light pooling on the palm's up face (glowmask only)."""
    if px.face != "up":
        return None
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = max(abs(px.fx - cx) / max(cx, 0.5), abs(px.fy - cy) / max(cy, 0.5))
    if d > 0.7:
        return None
    alpha = int(150 * (1.0 - d))
    r, g, b, _ = mix(ACCENT_DEEP, ACCENT, 1.0 - d)
    return (r, g, b, alpha)


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("forearm", mummy(BONE, salt=11))
    painter.set_material("hand", knuckled(mul(BONE, 1.06), salt=13))
    painter.set_material("fingers", knuckled(mul(BONE, 1.12), salt=17))
    painter.set_material("glow_stump", stump)
    painter.set_material("glow_ledger",
                         flame(mix(ACCENT, WHITE, 0.55), mix(ACCENT, ACCENT_DEEP, 0.5), salt=23))
    painter.set_glow_painter("hand", palm_spill)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
