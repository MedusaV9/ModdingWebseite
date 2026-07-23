#!/usr/bin/env python3
"""Pale Sentinel / Fahler Wächter texture driver (P6-W910).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3): a 2.6-block lanky
tree-revenant of pale-oak — log-grain body `#D8D2C4`/`#B9B2A2` split by dark bark
fissures `#575044`, a twig-antler crown, stilt legs, long thin arms ending in
root-claw finger cubes, and a hollow recessed face whose ONLY light is the pair of
orange-ember eyes `#FF9A3C`.

Emissive (glowmask): NOTHING except the two ember-eye pixel pairs on the head's north
face (custom glow painter — the sentinel must read as a dead tree until you meet its
gaze). No `glow_*` bones exist in this geo on purpose.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/pale_sentinel.py
Writes src/main/resources/assets/eclipse/textures/entity/pale_sentinel.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/pale_sentinel.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/pale_sentinel.png"

SEED = 0x9A1E5E17  # pale sentinel

BARK = hexc("#D8D2C4")
BARK_DIM = hexc("#B9B2A2")
FISSURE = hexc("#575044")
ROOT_CLAW = hexc("#8C8474")
TWIG = hexc("#6E6555")
HOLLOW = hexc("#2A261E")
EYE = hexc("#FF9A3C")
EYE_CORE = hexc("#FFD9A0")


def pale_bark(base, salt=11, fissures=0.06):
    """Pale-oak log grain: long vertical tonal runs between BARK and BARK_DIM plus
    sparse near-black fissure cracks (2px vertical runs so they read as splits)."""
    def fn(px):
        g = px.noise(salt, y=px.gy // 4)
        col = mix(base, BARK_DIM, 0.65) if g < 0.30 else (base if g < 0.74 else mul(base, 1.06))
        if px.noise(salt + 5, y=px.gy // 2) < fissures:
            col = mix(col, FISSURE, 0.85)  # bark split
        return col
    return fn


_body_bark = pale_bark(BARK)
_limb_bark = pale_bark(BARK_DIM, salt=19, fissures=0.045)


def head(px):
    """The hollow face: pale bark shell everywhere except the north face, which caves
    into a dark hollow (rows 1-4, cols 1-3) with the two ember eyes at face (1,2) and
    (3,2). The sockets are the only warm pixels on the whole mob."""
    if px.face == "north":
        if px.fx in (1, 3) and px.fy == 2:
            return EYE_CORE if px.fx == 1 else EYE
        if 1 <= px.fx <= 3 and 1 <= px.fy <= 4:
            return mul(HOLLOW, 0.9 + px.noise(23) * 0.2)  # caved-in hollow
    return _body_bark(px)


def claw(px):
    """Root-claw fingers: weathered grey-brown root wood, darker tips on the lowest
    rows so the long finger cubes read as split talons."""
    col = mul(ROOT_CLAW, 0.88 + px.noise(31) * 0.24)
    if px.face in ("north", "south", "east", "west") and px.fy >= px.fh - 1:
        col = mul(col, 0.55)  # earth-stained tip
    return col


def tendril(px):
    """Root-tendril skirt: dry root fibre with a ragged alpha-cut hem (the roots
    trail off into nothing) and node bands like growth rings."""
    if px.face in ("north", "south", "east", "west"):
        n = px.noise(55, y=0)
        cut = 0 if n < 0.4 else (1 if n < 0.8 else 2)
        if px.fy >= px.fh - cut:
            return None  # ragged root ends
    col = mul(ROOT_CLAW, 0.82 + px.noise(29, y=px.gy // 3) * 0.34)
    if (px.gy + int(px.noise(37, y=0) * 3)) % 4 == 0:
        col = mul(col, 0.72)  # root node ring
    return col


def antler(px):
    """Twig-antler crown: dead branch wood, slightly lighter on the up faces where
    the pale garden's non-light catches it."""
    col = mul(TWIG, 0.9 + px.noise(41) * 0.2)
    if px.face == "up":
        col = mix(col, BARK_DIM, 0.3)
    return col


def eye_glow(px):
    """Glowmask: ONLY the ember eyes burn — bright core left, dimmer right; faint by
    design (the sheet calls them the sentinel's single glow)."""
    if px.face == "north" and px.fx in (1, 3) and px.fy == 2:
        return with_alpha(EYE_CORE if px.fx == 1 else EYE, 235 if px.fx == 1 else 205)
    return None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("torso", _body_bark)
    painter.set_material("pelvis", _body_bark)
    painter.set_material("leg_*", _limb_bark)
    painter.set_material("arm_*", _limb_bark)
    painter.set_material("hand_*", claw)
    painter.set_material("tendril_*", tendril)
    painter.set_material("antler_*", antler)
    painter.set_material("head", head)
    painter.set_glow_painter("head", eye_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
