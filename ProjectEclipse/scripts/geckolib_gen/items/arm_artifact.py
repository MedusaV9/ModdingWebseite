#!/usr/bin/env python3
"""Arm artifact texture driver (PLAN-ITEMS A2, MD2 polish) — GeckoLib ITEM geo upgrade.

Paints `geo/item/arm_artifact.geo.json` (64x64): a severed, mummified forearm in the
frozen bone/parchment ramp (`scripts/item_art/eclipse_palette.py` BONE_* tones), a
crimson stump ring (`glow_stump`, DANGER-crimson emissive) and the floating ledger-light
mote the palm cups (`glow_ledger`, ACCENT `#B98CFF` — the artifact-menu identity color).
A faint ACCENT light-spill is painted into the PALM's glowmask pixels (up face only), so
the mote reads as actually lighting the hand (drift_lantern shine-through convention).

MD2 additions (Welle M-D, Zensus §5 Zeile MD2):

* `glow_page_a..d` — the four ledger-light leaves that fan out of the mote in
  `animation.arm_artifact.open`. Emissive ACCENT parchment with a bright edge frame and
  broken ruled writing lines, deliberately ORIENTATION-SYMMETRIC (edge frame + vertical
  gradient, no left/right spine highlight) because a zero-depth plane's north and south
  face rects mirror each other in the box-UV strip.
* Two extra glowmask accents (the §5-(c) "Glow-Akzente" pass): faint ACCENT rune ticks
  riding the forearm's bandage seams (the ledger writes itself onto the arm) and a
  fingertip light-spill so the fingers that cup the mote catch its light too.

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


def fingertip_spill(px):
    """The mote lights the fingers that cup it: a soft ACCENT wash on the fingertip
    (up) faces plus a single tick on the top row of each side face (glowmask only)."""
    if px.face == "up":
        return (ACCENT[0], ACCENT[1], ACCENT[2], 130)
    if px.face in ("north", "south", "east", "west") and px.fy == 0:
        r, g, b, _ = mix(ACCENT_DEEP, ACCENT, 0.6)
        return (r, g, b, 80)
    return None


def seam_runes(px):
    """Ledger script bleeding through the bandages: sparse ACCENT ticks on the forearm's
    wrap seams (same every-3-rows lattice `mummy()` darkens), glowmask only. Sparse on
    purpose — this must read as writing, not as a glowing sleeve."""
    if px.face not in ("north", "south", "east", "west"):
        return None
    if (px.gy + int(px.noise(14, y=0) * 3)) % 3 != 0:
        return None
    n = px.noise(19)
    if n < 0.72:
        return None
    r, g, b, _ = mix(ACCENT_DEEP, ACCENT, (n - 0.72) / 0.28)
    return (r, g, b, int(70 + 110 * (n - 0.72) / 0.28))


def ledger_page(salt):
    """Emissive ledger leaf: a bright ACCENT edge frame around dimmer parchment with
    broken ruled writing lines. The gradient runs VERTICALLY only — a zero-depth plane's
    north/south box-UV rects mirror horizontally, so a left/right spine highlight would
    land on opposite sides of the same leaf."""
    def fn(px):
        t = px.fy / max(px.fh - 1, 1)
        col = mix(mix(ACCENT, WHITE, 0.42), ACCENT_DEEP, 0.15 + 0.55 * t)
        on_edge = (px.fx == 0 or px.fy == 0
                   or px.fx == px.fw - 1 or px.fy == px.fh - 1)
        if on_edge:
            return mix(col, WHITE, 0.6)
        # Ruled writing: every other interior row, broken into word-runs by noise.
        if px.fy % 2 == 1 and px.noise(salt, x=px.gx // 2) > 0.3:
            col = mix(col, WHITE, 0.4)
        return col
    fn.shadeless = True
    return fn


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("forearm", mummy(BONE, salt=11))
    painter.set_material("hand", knuckled(mul(BONE, 1.06), salt=13))
    painter.set_material("fingers", knuckled(mul(BONE, 1.12), salt=17))
    painter.set_material("glow_stump", stump)
    painter.set_material("glow_ledger",
                         flame(mix(ACCENT, WHITE, 0.55), mix(ACCENT, ACCENT_DEEP, 0.5), salt=23))
    # One salt per leaf so the four fanned pages carry visibly different writing.
    painter.set_material("glow_page_a", ledger_page(salt=31))
    painter.set_material("glow_page_b", ledger_page(salt=37))
    painter.set_material("glow_page_c", ledger_page(salt=41))
    painter.set_material("glow_page_d", ledger_page(salt=43))
    painter.set_glow_painter("hand", palm_spill)
    painter.set_glow_painter("fingers", fingertip_spill)
    painter.set_glow_painter("forearm", seam_runes)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
