#!/usr/bin/env python3
"""Ferryman texture driver (MA4 — GeckoLib conversion of the event's FINALE boss).

Carries the frozen MOB-BOSS1/v2 identity (scripts/skin_gen/ferryman_v2.py) onto the new
128x128 GeckoLib canvas (`geo/entity/ferryman.geo.json`): drowned green-black robe
`#202C28` crusted with barnacle `#5E7466` toward the waterline, hood `#141B18` with the
OPEN COWL (transparent north face — the bone skull `#D8D2BE` inside shows through),
hollow sockets + soul-teal eye slit `#8FF2DE`, waterlogged oar `#4A3A28`/`#3C2F20`, wet
iron chain `#626670`, riveted lantern `#3A3E46` with soul-glass panes, and the soul
flame `#A8F7E6`.

Emissive (glowmask): `glow_eyes` (the slit floating in the cowl shadow), `glow_flame`
(the lantern heart), `glow_robe` (the lantern's teal sheen cast on the robe's lantern
side), `glow_gaze` (the translucent soul-shell around the lantern — the renderer only
un-hides it while the entity gazes) — all auto-included via the `glow_` prefix — plus
glow painters for the lantern's glass panes (flame shine-through) and the skull's
socket embers. All emissive pixels are ALSO painted bright in the albedo (conventions
doc §4 — they must still read under Iris shaderpacks).

The `glow_gaze` shell is painted at alpha < 255 on every pane: render the mob with
`EclipseGeoRenderer.withTranslucency()` (see FerrymanGeoRenderer).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/ferryman.py
Writes src/main/resources/assets/eclipse/textures/entity/ferryman.png + _glowmask.png.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, kelp, metal, mix, mul, weave, with_alpha, wood  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/ferryman.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/ferryman.png"

SEED = 0x0FE44174  # ferryman

ROBE = hexc("#202C28")
ROBE_DEEP = hexc("#18221E")
BARNACLE = hexc("#5E7466")
BARNACLE_HI = hexc("#7A9284")
HOOD = hexc("#141B18")
HOOD_RIM = hexc("#243029")
SKULL = hexc("#D8D2BE")
SKULL_SHADOW = hexc("#A8A28C")
SOCKET = hexc("#0E1410")
EYE = hexc("#8FF2DE")
EYE_HOT = hexc("#D9FFF6")
OAR = hexc("#4A3A28")
GRIP = hexc("#2E2418")
BLADE = hexc("#3C2F20")
STAIN = hexc("#33301F")
CHAIN = hexc("#626670")
RUST = hexc("#4A3E36")
IRON = hexc("#3A3E46")
IRON_HI = hexc("#6A707C")
GLASS = hexc("#274441")
FLAME = hexc("#A8F7E6")
FLAME_HOT = hexc("#E8FFF8")
FLAME_RIM = hexc("#7ADCC8")
SHEEN = hexc("#57907F")
GAZE = hexc("#8FF2DE", 96)  # translucent soul shell — withTranslucency()


# ---------------------------------------------------------------------------
# robe / cloth
# ---------------------------------------------------------------------------

def drowned_robe(base, salt=11, crust=True):
    """Green-black weave sinking into a barnacle-crusted waterline: the bottom third of
    every side face silts up with dither-edged barnacle clusters (the Ferryman stands
    hip-deep in Limbo's river), plus rare pale water-bead flecks."""
    base_fn = weave(base, direction=1, amp=0.3, salt=salt)

    def fn(px):
        col = base_fn(px)
        if crust and px.face in ("north", "south", "east", "west"):
            t = (px.fy + 0.5) / px.fh  # 0 top .. 1 hem
            jitter = (px.noise(salt + 31, x=px.gx // 2, y=0) - 0.5) * 0.3
            depth = t + jitter - 0.62
            if depth > 0 and px.noise(salt + 37) < depth * 2.4:
                hi = px.noise(salt + 41) > 0.72
                col = mix(col, BARNACLE_HI if hi else BARNACLE, 0.85)
        if px.noise(salt + 43) > 0.985:
            col = mul(col, 1.28)  # wet bead catching the lantern
        return col

    return fn


def robe_sheen(px):
    """`glow_robe` plate (the robe's lantern-facing flank): the robe weave washed with
    the lantern's teal sheen, brighter toward the lantern (down + south = toward the
    chain side). Shadeless so the sheen stays luminous in the albedo."""
    col = drowned_robe(ROBE, salt=11)(px)
    t = 0.35 + 0.45 * ((px.fy + 0.5) / px.fh)
    col = mix(col, SHEEN, t * 0.75)
    if px.noise(47) > 0.9:
        col = mix(col, EYE, 0.35)  # dancing flame speckle
    return col


robe_sheen.shadeless = True


def robe_sheen_glow(px):
    """Glowmask for `glow_robe`: soft — the sheen is cast light, not a light source."""
    return with_alpha(robe_sheen(px), 120)


# ---------------------------------------------------------------------------
# hood / skull
# ---------------------------------------------------------------------------

def hood_cowl(px):
    """The hood: near-black wet sackcloth; the NORTH face is the open cowl — fully
    transparent except a ragged 1px rim so the skull + eye slit float in shadow."""
    if px.face == "north":
        on_rim = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
        if not on_rim:
            return None  # open cowl
        if px.noise(53) > 0.8:
            return None  # ragged rim bite
        return mix(HOOD, HOOD_RIM, px.noise(54) * 0.8)
    col = weave(HOOD, direction=1, amp=0.26, salt=51)(px)
    if px.face == "down":
        return mul(col, 0.7)  # shadow pooling under the cowl
    return col


def skull_face(px):
    """The skull cube inside the cowl: bone north face with hollow sockets + nasal
    slit; the other faces stay hood-shadow dark (only the face shows through)."""
    if px.face == "north":
        cx = px.fw / 2.0
        # hollow sockets (the glow_eyes slit floats just in front of these)
        if px.fy in (2, 3) and (1 <= px.fx <= 2 or px.fw - 3 <= px.fx <= px.fw - 2):
            return SOCKET
        if px.fy in (4, 5) and abs(px.fx + 0.5 - cx) < 0.8:
            return SOCKET  # nasal slit
        shade = 0.8 if px.fy > px.fh - 2 else 1.0  # jaw shadow
        base = mix(SKULL, SKULL_SHADOW, px.noise(57) * 0.5)
        if px.noise(58) > 0.94:
            base = mul(base, 0.82)  # crack pit
        return mul(base, shade)
    return mul(HOOD, 0.75)


def socket_glow(px):
    """Faint ember inside each socket (under the main glow_eyes slit)."""
    if px.face == "north" and px.fy in (2, 3) and (1 <= px.fx <= 2 or px.fw - 3 <= px.fx <= px.fw - 2):
        return with_alpha(mix(EYE, EYE_HOT, px.noise(59)), 150)
    return None


def eye_slit(px):
    """`glow_eyes` 5x1x2 slit: a hard soul-teal band, hotter in the middle."""
    cx = (px.fw - 1) / 2.0
    t = 1.0 - min(1.0, abs(px.fx - cx) / max(cx, 0.5))
    return mix(EYE, EYE_HOT, t * t)


eye_slit.shadeless = True


# ---------------------------------------------------------------------------
# lantern / chain
# ---------------------------------------------------------------------------

def chain_iron(px):
    """Wet iron chain segments: link-band darkening + rust blooms + drip glints."""
    col = kelp(CHAIN, salt=61, max_cut=0)(px)
    if px.noise(62) < 0.12:
        col = mix(col, RUST, 0.7)
    if px.noise(63) > 0.97:
        col = mul(col, 1.3)  # water drip glint
    return col


def lantern_body(px):
    """The lantern: riveted iron frame on the rect border, soul-glass panes inside
    (teal glass brightening toward the pane center — the flame behind it)."""
    on_frame = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
    if px.face in ("up", "down") or on_frame:
        col = metal(IRON, salt=67)(px)
        if on_frame and px.face not in ("up", "down") and (px.fx + px.fy) % 3 == 0:
            col = mix(col, IRON_HI, 0.5)  # rivet
        return col
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = math.hypot((px.fx - cx) / max(cx, 0.5), (px.fy - cy) / max(cy, 0.5))
    glow = max(0.0, 1.0 - d)
    col = mix(GLASS, FLAME, glow * 0.55 + (px.noise(68) - 0.5) * 0.1)
    return col


def lantern_glass_glow(px):
    """Glowmask for the lantern: only the glass panes (frame stays dark), at the
    flame's shine-through strength."""
    on_frame = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
    if px.face in ("up", "down") or on_frame:
        return None
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = math.hypot((px.fx - cx) / max(cx, 0.5), (px.fy - cy) / max(cy, 0.5))
    if d > 0.95:
        return None
    return with_alpha(mix(FLAME, GLASS, d * 0.7), int(190 * (1.0 - d * 0.5)))


def soul_flame(px):
    """`glow_flame` heart: white-hot core -> teal rim, licking upward."""
    cx = (px.fw - 1) / 2.0
    lick = (px.noise(71, x=px.gx, y=0) - 0.5) * 1.2
    d = math.hypot((px.fx - cx) / max(cx, 0.5), (px.fy + lick) / max(px.fh - 1, 1) - 0.6)
    if d < 0.35:
        return FLAME_HOT
    return mix(FLAME, FLAME_RIM, min(1.0, d))


soul_flame.shadeless = True


def gaze_shell(px):
    """`glow_gaze` translucent soul-shell (hidden except while gazing): drifting teal
    veil, denser at the pane rims, with sparse bright motes."""
    col = GAZE
    on_rim = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
    if on_rim:
        col = with_alpha(col, min(255, col[3] + 60))
    if px.noise(73) > 0.93:
        col = with_alpha(mix(EYE_HOT, EYE, px.noise(74)), 200)  # mote
    return col


gaze_shell.shadeless = True


# ---------------------------------------------------------------------------
# oar
# ---------------------------------------------------------------------------

def oar_shaft(px):
    """Waterlogged shaft: dark wood grain; the grip rows (top ~third, where the hands
    ride) are wrapped darker."""
    col = wood(OAR, salt=77)(px)
    if px.face in ("north", "south", "east", "west") and (px.fy + 0.5) / px.fh < 0.34:
        col = mix(col, GRIP, 0.75)
        if px.gy % 2 == 0:
            col = mul(col, 0.85)  # wrap band
    return col


def oar_blade(px):
    """The blade: darker slab with soul-stain blotches near the tip edge (what it has
    been dipping into) and a chipped kelp hem on the tip rows."""
    if px.face in ("north", "south", "east", "west"):
        n = px.noise(83, x=px.gx, y=0)
        cut = 0 if n < 0.55 else 1
        if px.fy >= px.fh - cut:
            return None  # chipped tip
    col = wood(BLADE, salt=79)(px)
    t = (px.fy + 0.5) / px.fh
    if t > 0.55 and px.noise(81) < (t - 0.55) * 1.6:
        col = mix(col, STAIN, 0.8)
    return col


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("body", drowned_robe(ROBE, salt=11))
    painter.set_material("hem_*", drowned_robe(ROBE_DEEP, salt=13))
    painter.set_material("tatter_*", kelp(ROBE_DEEP, salt=17, max_cut=2))
    painter.set_material("tatter_*_tip", kelp(ROBE_DEEP, salt=19, max_cut=3))
    painter.set_material("arm_*", drowned_robe(ROBE, salt=23, crust=False))
    painter.set_material("head", skull_face)
    painter.set_material("hood", hood_cowl)
    painter.set_material("chain_*", chain_iron)
    painter.set_material("link_*", chain_iron)
    painter.set_material("lantern", lantern_body)
    painter.set_material("cap", metal(IRON, salt=69))
    painter.set_material("oar_shaft", oar_shaft)
    painter.set_material("oar_blade", oar_blade)
    # glow_ bones auto-copy into the glowmask; shadeless keeps them full-bright in the
    # albedo too (Iris rule).
    painter.set_material("glow_eyes", eye_slit)
    painter.set_material("glow_flame", soul_flame)
    painter.set_material("glow_robe", robe_sheen)
    painter.set_material("glow_gaze", gaze_shell)
    # Emissive extras: socket embers + glass shine-through + softened robe sheen.
    painter.set_glow_painter("head", socket_glow)
    painter.set_glow_painter("lantern", lantern_glass_glow)
    painter.set_glow_painter("glow_robe", robe_sheen_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
