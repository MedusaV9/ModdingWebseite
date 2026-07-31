#!/usr/bin/env python3
"""`revive_sigil` GeckoLib ITEM texture driver (PLAN-ITEMS B3, MD3 glyph-ring pass).

Octagonal rune tablet in the bone/parchment ramp (eclipse_palette secondary ramp)
with an ACCENT-purple engraved glyph carried by the two `glow_glyph` planes hovering
0.3px off both faces — the AutoGlowingGeoLayer lights them, the `idle` anim pulses
them. Faint engraved rim ticks sit in the slab albedo only (no glow) so the tablet
still reads as carved stoneware when the glow layer is dimmed by shaderpacks.

MD3 added the orbiting glyph ring: four 2x3 `glow_rune_*` planes, one per rune of the
"returning soul" phrase. Each carries its OWN stroke set so the ring reads as a
sentence circling the core rather than four copies of one mark — `ritual_charge_*`
spins them up, `shatter` blasts them off.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/items/revive_sigil.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, mix, mul, weave  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/item/revive_sigil.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/item/sigil/revive_sigil.png"

SEED = 0x51611  # "SIGIL"

BONE_DARK = hexc("#6E6254")
BONE = hexc("#C9BCA4")
BONE_LIGHT = hexc("#EFE6D2")
ACCENT = hexc("#B98CFF")
ACCENT_DEEP = hexc("#7B4FD0")
GLOW_WHITE = hexc("#F7F0FF")

# Angular "returning soul" glyph on the 6x6 glow planes: a broken ring with a
# rising spark — hand-authored pixel set (fx, fy), same on both faces.
GLYPH = {
    (1, 1), (2, 1), (3, 1), (4, 1),
    (1, 2), (4, 2),
    (0, 3), (5, 3),
    (1, 4), (4, 4),
    (2, 5), (3, 5),
    (2, 3), (3, 2),  # the spark rising through the ring
}

# One 2x3 stroke set per ring rune (fx, fy) — four marks of the same phrase, so the
# orbit reads as a sentence. Kept deliberately sparse: at r = 7px these are ~2 texels
# wide on screen, and a filled plate would just look like a smear.
RUNES = {
    "glow_rune_a": {(0, 0), (1, 0), (0, 1), (0, 2), (1, 2)},   # bracket "["
    "glow_rune_b": {(0, 0), (1, 1), (0, 2), (1, 2)},           # angled tick
    "glow_rune_c": {(0, 0), (1, 0), (1, 1), (0, 2), (1, 2)},   # "S" fold
    "glow_rune_d": {(1, 0), (0, 1), (1, 1), (1, 2)},           # crossed stem
}


def rune_plane(strokes):
    """One ring rune: ACCENT strokes only, everything else transparent."""

    def fn(px):
        if (px.fx, px.fy) not in strokes:
            return None
        hot = px.noise(23) > 0.5
        return mix(ACCENT, GLOW_WHITE, 0.55) if hot else ACCENT

    fn.shadeless = True
    return fn


def parchment(base, salt):
    """Bone/parchment weave with rare darker pores (carved stoneware)."""
    grain = weave(base, direction=0, amp=0.22, salt=salt)

    def fn(px):
        col = grain(px)
        if px.noise(salt + 5) > 0.97:
            col = mul(col, 0.72)
        return col

    return fn


def glyph_plane(px):
    """ACCENT glyph strokes only; everything else transparent (holes stay dark)."""
    if (px.fx, px.fy) not in GLYPH:
        return None
    hot = px.noise(3) > 0.62
    return mix(ACCENT, GLOW_WHITE, 0.45) if hot else mix(ACCENT_DEEP, ACCENT, 0.65)


glyph_plane.shadeless = True


def rim_ticks(salt):
    """Faint engraved ticks on the slab's front/back rims (albedo-only accents
    live in the material, not the glowmask — this is the carved, unlit detail)."""
    base = parchment(BONE, salt)

    def fn(px):
        col = base(px)
        if px.face in ("north", "south") and px.fw >= 8:
            on_rim = px.fx in (1, px.fw - 2) and px.fy % 3 == 1
            if on_rim:
                col = mix(col, ACCENT_DEEP, 0.55)
        return col

    return fn


def main():
    painter = GeoPainter(GEO, seed=SEED)
    # MD3 split the old three-cube `tablet` bone into slab + the two caps so the
    # shatter can blow them apart individually; the materials are unchanged.
    painter.set_material("slab", rim_ticks(salt=11))
    painter.set_material("cap_top", parchment(mix(BONE, BONE_LIGHT, 0.35), salt=13))
    painter.set_material("cap_bottom", parchment(mix(BONE, BONE_DARK, 0.4), salt=15))
    painter.set_material("glow_glyph", glyph_plane)
    for bone, strokes in RUNES.items():
        painter.set_material(bone, rune_plane(strokes))
    painter.paint(OUT)


if __name__ == "__main__":
    main()
