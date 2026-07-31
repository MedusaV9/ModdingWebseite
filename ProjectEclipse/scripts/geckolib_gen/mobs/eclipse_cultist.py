#!/usr/bin/env python3
"""Eclipse Cultist / Eklipsen-Kultist texture driver (P6-W910, MB3 polish).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3): a hunched robed caster in
the same charcoal robe family as eclipsed players — `#26232E` cloth with `#B98CFF`
sigil trim, a deep hood whose opening shows only shadow and two violet eye embers, a
ritual knife on the right wrist, and three floating rune pages (`glow_rune_*`) that
orbit the left hip.

MB3 added the four-piece robe (`robe_lower` waist → `robe_mid` → `robe_hem`, plus the
`robe_train` back drape), the two bell sleeve cuffs (`cuff_left`/`cuff_right`, which
flare open during `cast`) and the hood ember ring (`glow_hood`). The sigil trim moved
from the old single-cube skirt down to `robe_hem` — that is the piece that now carries
the hem — and the cuff rims picked up the same dashed trim so the flare reads as the
robe's sigil work opening up rather than a bare cloth tube.

Emissive (glowmask): the three `glow_rune_*` quads (auto-included via the `glow_`
prefix, flame material), the `glow_hood` ember ring around the cowl's mouth (a custom
rim painter — its middle stays transparent so the eyes read through it, and its alpha
is capped below the eyes' so the two pinpricks stay the focal point), the violet eye
pair on the head's north face, the sigil trim band on `robe_hem` and the cuff rims (all
faint — the trim smoulders rather than burns).

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
ROBE_TRAIN = hexc("#1F1C27")
ROBE_SLEEVE = hexc("#2C2836")
HOOD = hexc("#1B1922")
TRIM = hexc("#B98CFF")
FACE_SHADOW = hexc("#0E0C14")
EYE = hexc("#B98CFF")
EYE_CORE = hexc("#E7D6FF")
EMBER = hexc("#B98CFF")
EMBER_TIP = hexc("#6D4AA8")
KNIFE_BLADE = hexc("#C8CCD8")
KNIFE_GRIP = hexc("#4A4152")
RUNE = hexc("#B98CFF")
RUNE_CORE = hexc("#EFE3FF")

_robe_weave = weave(ROBE, direction=1, amp=0.28)
_train_weave = weave(ROBE_TRAIN, direction=1, amp=0.26)
_sleeve_weave = weave(ROBE_SLEEVE, direction=1, amp=0.24)


def _is_side(px):
    return px.face in ("north", "south", "east", "west")


def _is_trim(px):
    """Sigil trim: a dashed violet band on the second-to-last row of the hem's side
    faces (dashes every 3 px so it reads as stitched runes, not a stripe)."""
    return _is_side(px) and px.fy == px.fh - 2 and px.gx % 3 != 2


def _is_cuff_rim(px):
    """Cuff opening: the bottom row of the bell's side faces — the lip that swings wide
    when the `cast` sleeve flare peaks."""
    return _is_side(px) and px.fy == px.fh - 1


def robe_plain(px):
    """Skirt cloth (waist + mid links): the plain vertical weave with a faint crease on
    the top row of each side face, where the layer above it overlaps."""
    col = _robe_weave(px)
    if _is_side(px) and px.fh > 2 and px.fy == 0:
        col = mul(col, 0.8)
    return col


def robe_hem(px):
    """The floor-length hem: the sigil trim band plus a mud-dark bottom row."""
    if _is_trim(px):
        return mix(TRIM, RUNE_CORE, 0.25) if px.gx % 6 == 0 else TRIM
    col = _robe_weave(px)
    if _is_side(px) and px.fy >= px.fh - 1:
        col = mul(col, 0.72)  # mud-hem shadow under the trim
    return col


def _is_spine(px):
    """Spine sigil: one dashed trim column down the middle of the train's two flat
    faces (the drape is 1px thin, so only north/south are worth marking)."""
    return px.face in ("north", "south") and px.fx == px.fw // 2 and px.fy % 3 != 2


def robe_train(px):
    """Back drape: darker than the skirt (it hangs in its own shadow) with one dashed
    trim column down the spine."""
    if _is_spine(px):
        return mul(TRIM, 0.8)
    return _train_weave(px)


def torso(px):
    """Chest cloth with a single dashed trim column down the north face center —
    the cultist's rank stole."""
    if px.face == "north" and px.fx == px.fw // 2 and px.fy % 3 != 2:
        return TRIM
    return _robe_weave(px)


def cuff(px):
    """Bell sleeve cuff: sleeve weave, a fold shadow above the lip and the same dashed
    trim on the rim itself."""
    if _is_cuff_rim(px):
        return mix(TRIM, RUNE_CORE, 0.2) if px.gx % 4 == 0 else TRIM
    col = _sleeve_weave(px)
    if _is_side(px) and px.fy == px.fh - 2:
        col = mul(col, 0.7)
    return col


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
    if _is_side(px):
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


def train_glow(px):
    """Glowmask for the back drape: the spine dashes, dimmest of the three trim runs —
    it is the piece furthest from the caster's own light."""
    if _is_spine(px):
        return with_alpha(mul(TRIM, 0.8), 100)
    return None


def cuff_glow(px):
    """Glowmask for the sleeves: only the cuff rim, fainter than the hem — the flare
    should read as a widening ring of embers, not a lamp."""
    if _is_cuff_rim(px):
        return with_alpha(TRIM, 120)
    return None


def _hood_rim_heat(px):
    """Ember strength around the hood mouth: 0 at the brow, 1 at the bottom lip, and
    None everywhere off the 1px rim.

    `glow_hood` is a flat 6x6 quad hung 0.05px in front of the hood's open north face,
    so the middle of it MUST stay transparent — anything painted there would curtain
    over the eye embers and turn the hood into a lit visor. The `fy -> -Y` direction is
    measured, not assumed (harness section 4 dumps it per face), which is what makes
    `fy == fh - 1` the bottom row rather than the top.
    """
    if not (px.fx in (0, px.fw - 1) or px.fy in (0, px.fh - 1)):
        return None
    t = px.fy / (px.fh - 1.0)
    return 0.18 + 0.82 * t * t


def hood_rim(px):
    """Albedo for the hood ember ring: cold violet at the brow, white-hot where the
    coals pool in the bottom of the cowl. Bottom-weighted on purpose — a ring of even
    brightness reads as a visor, a ring that burns at the chin reads as firelight
    inside a hood."""
    heat = _hood_rim_heat(px)
    if heat is None:
        return None
    col = mix(EMBER_TIP, EMBER, heat)
    if heat > 0.6:
        col = mix(col, RUNE_CORE, (heat - 0.6) / 0.4 * 0.55)
    return mul(col, 0.9 + px.noise(19) * 0.2)


hood_rim.shadeless = True


def hood_rim_glow(px):
    """Glowmask for the ring: the same bottom-weighted ramp in alpha, capped below the
    eye embers' 255/225 so the two pinpricks stay the brightest thing on the mob."""
    heat = _hood_rim_heat(px)
    if heat is None:
        return None
    return with_alpha(mix(EMBER_TIP, EMBER, heat), int(60 + heat * 150))


def eye_glow(px):
    """Glowmask for the head: only the two eye embers."""
    if px.face == "north" and px.fx in (1, 3) and px.fy == 2:
        return with_alpha(EYE_CORE if px.fx == 1 else EYE, 255 if px.fx == 1 else 225)
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    # Broad patterns first: `_material_for` walks the list in reverse, so the exact
    # names declared below override the `robe_*` / `arm_*` catch-alls.
    painter.set_material("robe_*", robe_plain)
    painter.set_material("robe_hem", robe_hem)
    painter.set_material("robe_train", robe_train)
    painter.set_material("torso", torso)
    painter.set_material("hood", weave(HOOD, direction=0, amp=0.30))
    painter.set_material("glow_hood", hood_rim)
    painter.set_material("head", head)
    painter.set_material("arm_*", _sleeve_weave)
    painter.set_material("cuff_*", cuff)
    painter.set_material("knife", knife)
    painter.set_material("glow_rune_*", flame(RUNE_CORE, RUNE))
    painter.set_glow_painter("robe_hem", trim_glow)
    painter.set_glow_painter("robe_train", train_glow)
    painter.set_glow_painter("cuff_*", cuff_glow)
    painter.set_glow_painter("glow_hood", hood_rim_glow)
    painter.set_glow_painter("head", eye_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
