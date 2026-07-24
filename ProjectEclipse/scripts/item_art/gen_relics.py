#!/usr/bin/env python3
"""WB-ART relic family: `herald_core`, `heralds_lure`, `ferryman_toll`,
`revive_sigil`, `arm_artifact` (16x16 item icons).

Boss/economy relics on the shared EclipseUiTheme ramp (`eclipse_palette.py`).
Each keeps the color identity of the placeholder it replaces (herald gold,
ferryman verdigris + soul-teal, vitae crimson) so nothing changes meaning in
the handbook or shop rows. Flat fills first, then the shared `finish()` pass
(2px black-purple edge, 3-tone shading, top-left rim light). Deterministic.

Run from anywhere:
    python3 scripts/item_art/gen_relics.py
"""

from pathlib import Path
import sys

from PIL import ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import (  # noqa: E402
    ACCENT, ACCENT_DEEP, BONE, BONE_DARK, CRIMSON, DIM,
    GLOW_MAGENTA, GLOW_WHITE, GOLD, GOLD_DARK, GOLD_LIGHT, HAIRLINE, PANEL,
    PANEL_RAISED, PURPLE_DARK, PURPLE_MID, SCARLET, SOUL_TEAL, TEAL,
    TEAL_DARK, TEXT,
    canvas, finish, mix, put, rgba, save,
)

OUT = (
    Path(__file__).resolve().parents[2]
    / "src/main/resources/assets/eclipse/textures/item"
)


def herald_core():
    """Caged black sun orb: black glass, gold crack veins, gold cage bars."""
    img = canvas()
    d = ImageDraw.Draw(img)

    # Black-glass orb.
    d.ellipse([3, 3, 12, 12], fill=rgba(PANEL_RAISED))
    d.ellipse([5, 5, 10, 10], fill=rgba(PANEL))
    # Crack veins radiating from the blazing center.
    put(img, ((7, 4), (6, 5), (9, 5), (10, 7), (5, 9), (9, 10), (7, 11)), GOLD_DARK)
    put(img, ((7, 5), (6, 6), (9, 6), (6, 9), (9, 9)), GOLD)
    # Cage: two meridian bars + top clasp with a hanging loop.
    put(img, ((4, 5), (4, 6), (4, 7), (4, 8), (4, 9), (4, 10)), GOLD_DARK)
    put(img, ((11, 5), (11, 6), (11, 7), (11, 8), (11, 9), (11, 10)), GOLD_DARK)
    put(img, ((4, 5), (11, 5)), GOLD)
    put(img, ((6, 2), (7, 2), (8, 2), (9, 2), (5, 3), (10, 3)), GOLD_DARK)
    put(img, ((6, 2), (7, 2)), GOLD)
    put(img, ((7, 0), (8, 0), (7, 1), (8, 1)), GOLD)
    put(img, ((6, 13), (7, 13), (8, 13), (9, 13)), GOLD_DARK)

    finish(img)
    # Blazing center (glow tones stay unshaded).
    put(img, ((7, 7), (8, 7), (7, 8), (8, 8)), GOLD_LIGHT)
    put(img, ((8, 6),), GLOW_WHITE)
    return img


def heralds_lure():
    """Shard bundle bound with sinew: 3 distinct spikes, cord waist, heart knot.

    The three shard tips keep a 1px transparent gap above the cord so the
    `finish()` outline pass draws ink separators between them — otherwise
    they merge into a single mass at 16px.
    """
    img = canvas()

    # Left spike (darkest, behind).
    put(img, ((3, 1),
              (3, 2),
              (2, 3), (3, 3), (4, 3),
              (2, 4), (3, 4), (4, 4),
              (3, 5), (4, 5),
              (3, 6), (4, 6)), PURPLE_DARK)
    put(img, ((3, 2), (3, 3)), PURPLE_MID)
    # Center spike (front, brightest).
    put(img, ((7, 1), (8, 1),
              (6, 2), (7, 2), (8, 2),
              (6, 3), (7, 3), (8, 3), (9, 3),
              (6, 4), (7, 4), (8, 4), (9, 4),
              (6, 5), (7, 5), (8, 5), (9, 5),
              (6, 6), (7, 6), (8, 6), (9, 6)), ACCENT_DEEP)
    put(img, ((7, 2), (7, 3), (7, 4), (7, 5)), ACCENT)
    # Right spike (mid tone).
    put(img, ((12, 1),
              (12, 2), (13, 2),
              (11, 3), (12, 3), (13, 3),
              (11, 4), (12, 4), (13, 4),
              (11, 5), (12, 5),
              (11, 6), (12, 6)), PURPLE_MID)
    put(img, ((12, 2), (12, 3)), ACCENT_DEEP)

    # Sinew cord lashed around the waist.
    put(img, ((3, 7), (5, 7), (7, 7), (9, 7), (11, 7)), BONE)
    put(img, ((4, 7), (6, 7), (8, 7), (10, 7), (12, 7)), BONE_DARK)
    put(img, ((3, 8), (4, 8), (5, 8), (6, 8), (7, 8), (8, 8), (9, 8), (10, 8),
              (11, 8), (12, 8)), BONE_DARK)
    put(img, ((5, 8), (9, 8)), BONE)

    # Converging bundle below the cord.
    put(img, ((5, 9), (6, 9), (9, 9), (10, 9),
              (5, 10), (6, 10), (9, 10), (10, 10),
              (6, 11), (9, 11),
              (6, 12), (7, 12), (8, 12),
              (7, 13), (8, 13)), PURPLE_MID)
    put(img, ((6, 11), (7, 12), (7, 13)), ACCENT_DEEP)
    put(img, ((10, 9), (10, 10), (9, 11)), PURPLE_DARK)

    # Heart-fragment knot at the crossing (the recipe made visible).
    put(img, ((7, 9), (8, 9), (7, 10), (8, 10)), CRIMSON)
    put(img, ((7, 9),), SCARLET)

    finish(img)
    put(img, ((8, 0),), GLOW_WHITE)
    put(img, ((13, 1),), GLOW_MAGENTA)
    return img


def ferryman_toll():
    """A drowned obolus: verdigris coin, soul-teal skull stamp, worn rim."""
    img = canvas()
    d = ImageDraw.Draw(img)

    # Coin body + stamped inner ring.
    d.ellipse([2, 2, 13, 13], fill=rgba(TEAL))
    d.ellipse([4, 4, 11, 11], fill=rgba(TEAL_DARK))
    d.ellipse([5, 5, 10, 10], fill=rgba(TEAL))

    # Skull stamp: cranium, sockets, jaw.
    put(img, ((6, 5), (7, 5), (8, 5), (9, 5),
              (6, 6), (7, 6), (8, 6), (9, 6),
              (6, 7), (7, 7), (8, 7), (9, 7)), SOUL_TEAL)
    put(img, ((6, 6), (9, 6)), PANEL)          # eye sockets
    put(img, ((7, 8), (8, 8)), SOUL_TEAL)       # nasal/jaw bridge
    put(img, ((6, 9), (8, 9)), SOUL_TEAL)       # teeth
    put(img, ((7, 9), (9, 9)), TEAL_DARK)

    # Wear notch: the toll has changed many cold hands.
    put(img, ((12, 4), (13, 4)), (0, 0, 0), a=0)

    finish(img)
    put(img, ((5, 4),), GLOW_WHITE)             # cold glint on the rim
    put(img, ((10, 12),), SOUL_TEAL)            # soul residue drip
    return img


def revive_sigil():
    """Ritual sigil: broken rune annulus, a soul spark rising through the gap."""
    img = canvas()
    d = ImageDraw.Draw(img)

    # Stone talisman disc.
    d.ellipse([2, 2, 13, 13], fill=rgba(PANEL_RAISED))
    # Thick rune annulus, broken open at the top (the way out for the soul).
    d.ellipse([3, 3, 12, 12], outline=rgba(ACCENT_DEEP), width=2)
    d.ellipse([4, 4, 11, 11], outline=rgba(PURPLE_MID), width=1)
    put(img, ((6, 3), (7, 3), (8, 3), (9, 3), (6, 4), (7, 4), (8, 4), (9, 4)),
        PANEL_RAISED)
    # Rune ticks around the ring.
    put(img, ((3, 7), (12, 7), (7, 12)), ACCENT)
    # Center: a heart taking root...
    put(img, ((7, 8), (8, 8), (7, 9), (8, 9)), CRIMSON)
    put(img, ((7, 8),), SCARLET)
    # ...and the soul spark rising through the gap.
    put(img, ((7, 5), (8, 6)), ACCENT)

    finish(img)
    put(img, ((8, 2),), GLOW_WHITE)
    put(img, ((7, 4),), GLOW_MAGENTA)
    return img


def arm_artifact():
    """The Arm: a pale severed arm reaching up, cloth-wrapped, torn at the stump."""
    img = canvas()
    d = ImageDraw.Draw(img)

    pale = mix(DIM, TEXT, 0.35)

    # Forearm rising diagonally from the bottom-left stump.
    d.polygon([(4, 14), (7, 14), (10, 7), (10, 5), (7, 5), (4, 11)], fill=rgba(DIM))
    d.line([(5, 12), (8, 6)], fill=rgba(pale), width=1)
    # Cloth wraps around the forearm.
    put(img, ((5, 11), (6, 11), (7, 11), (6, 10)), HAIRLINE)
    put(img, ((7, 8), (8, 8), (9, 8)), HAIRLINE)
    put(img, ((7, 8),), PURPLE_MID)
    # Open hand: palm + three grasping fingers and a thumb.
    d.rectangle([7, 3, 10, 5], fill=rgba(pale))
    put(img, ((7, 1), (7, 2)), pale)      # index
    put(img, ((9, 1), (9, 2)), pale)      # middle
    put(img, ((11, 2), (11, 3)), DIM)     # ring finger, shaded
    put(img, ((5, 4), (6, 5)), DIM)       # thumb
    # Torn stump.
    put(img, ((5, 14), (6, 14)), CRIMSON)
    put(img, ((5, 15), (6, 15)), PANEL)

    finish(img)
    put(img, ((5, 14), (6, 14)), SCARLET)  # raw stump stays bright
    put(img, ((8, 3),), GLOW_WHITE)        # the ledger-light in the palm
    put(img, ((8, 4),), GLOW_MAGENTA)
    return img


def main():
    painters = {
        "herald_core": herald_core,
        "heralds_lure": heralds_lure,
        "ferryman_toll": ferryman_toll,
        "revive_sigil": revive_sigil,
        "arm_artifact": arm_artifact,
    }
    for name, painter in painters.items():
        img = painter()
        assert img.size == (16, 16) and img.mode == "RGBA"
        save(img, OUT / f"{name}.png")


if __name__ == "__main__":
    main()
