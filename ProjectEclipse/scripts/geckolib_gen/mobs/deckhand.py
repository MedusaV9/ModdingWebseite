#!/usr/bin/env python3
"""Deckhand texture driver (P6-W2 GeckoLib remodel).

Design sheet (docs/plans_v3/P6_mobs_models_builds.md §2.3 "deckhand v2"): keep the
drowned-ferryman-crew read of the old 7-cube model — murky waterlogged gray-greens, the
head pure shadow under the hood — and extend the palette to the new bones: a proper
two-handed oar (dark wood loom/shaft, blade with a kelp-slimed trailing edge) and two
rope-belt tatters.

MB1 (F-098 wave M-B) added the ONE emissive region this mob carries: the face. The hood
is an open cowl now, so the shadow void behind it is actually visible, and each rower
burns its own soul-light pattern in it (`glow_face_0..7`, one 6x4 card per bench, only
the rower's own card is rendered — `DeckhandRenderer.faceVariant`) plus the shared
`glow_face_wrath` brand that only lights while the crew is risen. Palette stays inside
the FX crew colours so the cards match the Photon soul-flame above the hood
(`tools/photon/backlog_fx.py`: SOUL_BLUE #66CCFF, flare core SAC_HOT #F6EFFF).

Palette carried over from the retired `docs/uv/deckhand.md` v1 brief: robe #3A4038,
torso #2E3430, arms #343A32, hood #262B24, head shadow #141612, oar wood #5A452E,
blade-edge kelp #22301F.

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/deckhand.py
Writes src/main/resources/assets/eclipse/textures/entity/deckhand.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, kelp, mix, mul, weave, wood  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/deckhand.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/deckhand.png"

SEED = 0x0DECC4A2  # deckhand crew

ROBE = hexc("#3A4038")
TORSO = hexc("#2E3430")
ARM = hexc("#343A32")
HOOD = hexc("#262B24")
HEAD_SHADOW = hexc("#141612")
OAR_WOOD = hexc("#5A452E")
KELP_EDGE = hexc("#22301F")
ROPE = hexc("#4A4232")
LANTERN_IRON = hexc("#3B3F46")      # drift-lantern frame iron (shared limbo palette)
LANTERN_GLASS = hexc("#57706B")     # DEAD soul-glass — the crew's lights went out


def head_shadow(px):
    """The face is a void: near-black with a wet sheen. The cowl (MB1) leaves the north
    face open from y 18–23.75 (= face rows fy 3–7), so that strip gets a top-down
    gradient — deepest right under the brim, opening up towards the jaw. The v1 pale
    eye texels are GONE: the eyes are emissive cards now (`glow_face_*`), which is what
    makes one rower tellable from the next."""
    col = mul(HEAD_SHADOW, 0.92 + px.noise(41) * 0.16)
    if px.face == "north":
        depth = 1.0 - 0.30 * max(0.0, min(1.0, (5.0 - px.fy) / 4.0))
        col = mul(col, depth)
    return col


_blade_wood = wood(OAR_WOOD, salt=19)


def blade(px):
    """Oar blade: waterlogged plank with a kelp-slimed trailing edge (the bottom rows of
    the east/west flats — the edge that drags through the water every stroke)."""
    col = _blade_wood(px)
    if px.face in ("east", "west"):
        if px.fy >= px.fh - 1 or (px.fy >= px.fh - 2 and px.noise(23) > 0.45):
            return mix(KELP_EDGE, col, 0.2)
        if px.noise(27) > 0.93:
            return mix(KELP_EDGE, col, 0.45)  # slime flecks up the face
    return col


def belt_lantern(px):
    """MOB-AMBIENT v2 belt lantern: iron frame everywhere; the four side faces carry a
    DEAD pane of soul-glass (dim, cold — the crew's lights went out when they drowned).
    Cube 0 is the iron cap, cube 1 the body — the cap never matches a glass center
    (its faces are 1–2px, all rim). NO glowmask pixels: the deckhand sheet stays
    explicitly non-emissive."""
    on_rim = px.fx == 0 or px.fy == 0 or px.fx == px.fw - 1 or px.fy == px.fh - 1
    if px.face in ("north", "south", "east", "west") and not on_rim:
        return mul(LANTERN_GLASS, 0.8 + px.noise(47) * 0.3)
    return mul(LANTERN_IRON, 0.86 + px.noise(43) * 0.24)


# ---------------------------------------------------------------------------
# face cards — the per-rower soul-light (MB1)
# ---------------------------------------------------------------------------
# One 6x4 card per bench (geo bones `glow_face_0..7`, all stacked on the same spot;
# the renderer shows exactly one). Grid rows run TOP -> BOTTOM of the card
# (fy 0 = model y 21.5–22.5 = eye line, fy 3 = y 18.5–19.5 = jaw line) and columns
# LEFT -> RIGHT in texture space, which is model -X -> +X on a north face (verified
# against the vanilla skin convention: a face texture reads as you see the face).
# The eye line sits below the lowest reach of the hood brim over the whole animation set
# (tightest: head-local y 22.97 during `death`, 23.05 during `attack`) — at the original
# y 22.5–23.5 the brim clipped the inboard half of every socket and the eyes rendered as
# L-shaped hooks.
#   'O' = core texel, 'o' = ember texel (core * 0.5, the halo/afterglow)
#   '.' = transparent
# Design rule: the pairs differ in COUNT, HEIGHT and SYMMETRY, not just colour, so the
# crew is tellable apart both up close (pattern) and across the deck (lit-texel mass).
FACE_CARDS = (
    # bench 0 — "even pair": the textbook rower, both lamps steady.
    ("#6FD8E8", (".O..O.",
                 "......",
                 "......",
                 "......")),
    # bench 1 — "wide burn": double-width sockets, the brightest of the crew.
    ("#8FE8C8", ("OO..OO",
                 ".o..o.",
                 "......",
                 "......")),
    # bench 2 — "half-lit": port socket drowned out, one long tear down the cheek.
    ("#66CCFF", ("....O.",
                 "....o.",
                 "...o..",
                 "...o..")),
    # bench 3 — "narrow-set": the pair sits pinched together over the bridge, chin tally.
    ("#9FD8A8", ("..OO..",
                 "......",
                 "......",
                 "o....o")),
    # bench 4 — "crooked": the sockets do not sit level, one lamp hangs.
    ("#7FC0E8", (".O....",
                 "....O.",
                 "....o.",
                 "......")),
    # bench 5 — "off-centre": both lights shoved to port, plus a jaw ember.
    ("#B8E4E0", ("O..OO.",
                 "......",
                 "...o..",
                 "......")),
    # bench 6 — "four marks": eyes plus a branded pair on the cheekbones.
    ("#5FA8C8", (".O..O.",
                 "......",
                 ".O..O.",
                 "......")),
    # bench 7 — "guttering": dim wide pair with a halo, the oldest hand aboard.
    ("#C8E8A0", ("oO..Oo",
                 "......",
                 "..oo..",
                 "......")),
)

# The risen-crew brand: a second card 0.2 px in FRONT of the bench card (geo z −4.45),
# shown only while `isHostile()`. Row 0 is deliberately EMPTY: every bench card keeps
# its sockets on that row (that is the rule the eight patterns are built to), so a
# risen rower still shows its OWN lamps and the crew stays tellable apart — the crew
# turns hostile, it does not turn identical. Rows 1–3 are the overflow: the light bleeds
# out of the sockets sideways, runs two texels down each cheek and drips off the chin.
# Core = the flare's hot core SAC_HOT, ember = SOUL_BLUE, i.e. exactly the
# `deckhand_soul_flare` gradient (white -> soul).
WRATH_CARD = ("#EAF4FF", ("......",
                          "oO..Oo",
                          ".O..O.",
                          "..oo.."), "#66CCFF")


def face_card(spec):
    """Builds a shadeless emissive material from a (core hex, rows[, ember hex]) spec."""
    core = hexc(spec[0])
    ember = hexc(spec[2]) if len(spec) > 2 else mul(core, 0.5)
    rows = spec[1]

    def fn(px):
        if px.face != "north" or px.fy >= len(rows) or px.fx >= len(rows[px.fy]):
            return None
        cell = rows[px.fy][px.fx]
        if cell == "O":
            # A one-texel flicker keeps the lit pixels from reading as flat plastic;
            # deterministic (global-pixel keyed), so reruns stay byte-identical.
            return mul(core, 0.92 + px.noise(61) * 0.16)
        if cell == "o":
            return mul(ember, 0.88 + px.noise(67) * 0.24)
        return None

    fn.shadeless = True  # emissive: no directional shading, no 1px outline
    return fn


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("robe", weave(ROBE, direction=1))
    painter.set_material("torso", weave(TORSO, direction=1))
    painter.set_material("arm_*", weave(ARM, direction=1, amp=0.28))
    painter.set_material("hood", weave(HOOD, direction=0, amp=0.30))
    painter.set_material("hood_point", weave(HOOD, direction=0, amp=0.34))
    painter.set_material("head", head_shadow)
    painter.set_material("oar_loom", wood(OAR_WOOD))
    painter.set_material("oar_shaft", wood(OAR_WOOD))
    painter.set_material("oar_blade", blade)
    painter.set_material("tatter_*", kelp(ROPE, max_cut=1))
    painter.set_material("belt", kelp(ROPE, max_cut=0))  # rope band, no ragged hem
    painter.set_material("lantern", belt_lantern)
    # The face cards are the mob's only emissive geometry. `glow_`-prefixed bones are
    # picked up by the painter's automatic glowmask copy at full strength, so the same
    # texels land in deckhand.png (shadeless = full brightness) and in
    # deckhand_glowmask.png — `DeckhandRenderer.withGlowmask()` re-renders them
    # fullbright. Everything else stays transparent in the glowmask.
    for index, spec in enumerate(FACE_CARDS):
        painter.set_material(f"glow_face_{index}", face_card(spec))
    painter.set_material("glow_face_wrath", face_card(WRATH_CARD))
    painter.paint(OUT)


if __name__ == "__main__":
    main()
