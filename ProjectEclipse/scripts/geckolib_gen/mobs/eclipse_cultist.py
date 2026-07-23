#!/usr/bin/env python3
"""Eclipse Cultist / Eklipsen-Kultist texture driver (P6-W910).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3): a hunched robed caster in
the same charcoal robe family as eclipsed players — `#26232E` cloth with `#B98CFF`
sigil trim, a deep hood whose opening shows only shadow and two violet eye embers, a
ritual knife on the right wrist, and three floating rune pages (`glow_rune_*`) that
orbit the left hip.

Emissive (glowmask): the three `glow_rune_*` quads (auto-included via the `glow_`
prefix, flame material), the violet eye pair on the head's north face, and the sigil
trim band on the robe hem (faint — the trim smoulders rather than burns).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/eclipse_cultist.py
Writes src/main/resources/assets/eclipse/textures/entity/eclipse_cultist.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, mix, mul, weave, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/eclipse_cultist.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/eclipse_cultist.png"

SEED = 0xEC11C057  # eclipse cultist

ROBE = hexc("#26232E")
ROBE_SLEEVE = hexc("#2C2836")
HOOD = hexc("#1B1922")
TRIM = hexc("#B98CFF")
FACE_SHADOW = hexc("#0E0C14")
EYE = hexc("#B98CFF")
EYE_CORE = hexc("#E7D6FF")
KNIFE_BLADE = hexc("#C8CCD8")
KNIFE_GRIP = hexc("#4A4152")
RUNE = hexc("#B98CFF")
RUNE_CORE = hexc("#EFE3FF")

_robe_weave = weave(ROBE, direction=1, amp=0.28)
_sleeve_weave = weave(ROBE_SLEEVE, direction=1, amp=0.24)


def _is_trim(px):
    """Sigil trim: a dashed violet band on the second-to-last hem row of the robe's
    side faces (dashes every 3 px so it reads as stitched runes, not a stripe)."""
    return (px.face in ("north", "south", "east", "west")
            and px.fy == px.fh - 2 and px.gx % 3 != 2)


def robe_lower(px):
    if _is_trim(px):
        return mix(TRIM, RUNE_CORE, 0.25) if px.gx % 6 == 0 else TRIM
    col = _robe_weave(px)
    if px.face in ("north", "south", "east", "west") and px.fy >= px.fh - 1:
        col = mul(col, 0.72)  # mud-hem shadow under the trim
    return col


def torso(px):
    """Chest cloth with a single dashed trim column down the north face center —
    the cultist's rank stole."""
    if px.face == "north" and px.fx == px.fw // 2 and px.fy % 3 != 2:
        return TRIM
    return _robe_weave(px)


def head(px):
    """Inside the hood: void shadow with two violet ember eyes at face (1,2)/(3,2).
    Cheek planes get the faintest robe reflection so the face isn't a flat hole."""
    if px.face == "north":
        if px.fx in (1, 3) and px.fy == 2:
            return EYE_CORE if px.fx == 1 else EYE
        if px.fy >= 3 and px.noise(23) > 0.7:
            return mix(FACE_SHADOW, ROBE, 0.3)
    return mul(FACE_SHADOW, 0.9 + px.noise(41) * 0.2)


def knife(px):
    """Ritual knife: dark wrapped grip on the top rows, pale steel below with a
    bright honed edge column."""
    if px.face in ("north", "south", "east", "west"):
        if px.fy <= 0:
            return mul(KNIFE_GRIP, 0.9 + px.noise(17) * 0.2)
        col = mul(KNIFE_BLADE, 0.88 + px.noise(13) * 0.22)
        if px.fx == 0:
            col = mul(col, 1.18)  # honed edge glint
        return col
    return KNIFE_GRIP if px.face == "up" else mul(KNIFE_BLADE, 0.8)


def trim_glow(px):
    """Glowmask for the robe hem: only the trim dashes smoulder (faint alpha)."""
    if _is_trim(px):
        return with_alpha(TRIM, 130)
    return None


def eye_glow(px):
    """Glowmask for the head: only the two eye embers."""
    if px.face == "north" and px.fx in (1, 3) and px.fy == 2:
        return with_alpha(EYE_CORE if px.fx == 1 else EYE, 255 if px.fx == 1 else 225)
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("robe_lower", robe_lower)
    painter.set_material("torso", torso)
    painter.set_material("hood", weave(HOOD, direction=0, amp=0.30))
    painter.set_material("head", head)
    painter.set_material("arm_*", _sleeve_weave)
    painter.set_material("knife", knife)
    painter.set_material("glow_rune_*", flame(RUNE_CORE, RUNE))
    painter.set_glow_painter("robe_lower", trim_glow)
    painter.set_glow_painter("head", eye_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
