#!/usr/bin/env python3
"""W4-HEARTS purple player-hearts HUD set (9x9, vanilla heart proportions).

`PurpleHeartsLayer` replaces the vanilla `PLAYER_HEALTH` renderer, so the full
vanilla sprite family is needed at the manifest's canonical
`textures/gui/hearts/` path:

* ``heart_full.png``       — byte-copy of the committed purple 9x9 heart
  (``textures/gui/heart_full.png``, the handbook StatusTab sprite) so the HUD
  and handbook stay the same art;
* ``heart_half.png``       — the same art cut to vanilla's half-heart footprint
  (left 5 columns; the container shows through on the right);
* ``heart_*_blinking.png`` — damage-flash frames, whitened toward TEXT exactly
  like vanilla whitens ``full`` -> ``full_blinking``;
* ``heart_absorbing_*``    — absorption hearts, shifted violet-white
  (ACCENT + TEXT) so bonus health reads lighter than the ACCENT_DEEP row;
* ``heart_container(_blinking).png`` — the vanilla 9x9 container mask repainted
  on the EclipseUiTheme ramp (VEIL outline, HAIRLINE well; blink outline TEXT).

Masks are hardcoded from the vanilla 1.21.1 ``hud/heart/*`` sprites so the
proportions are pixel-identical to the renderer this set replaces.
Deterministic — rerun for byte-identical PNGs.

Run from anywhere:
    python3 scripts/item_art/gen_purple_hearts.py
"""

from pathlib import Path
import sys

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eclipse_palette import ACCENT, HAIRLINE, TEXT, VEIL, mix, rgba, save  # noqa: E402

ASSETS = Path(__file__).resolve().parents[2] / "src/main/resources/assets/eclipse"
SOURCE_FULL = ASSETS / "textures/gui/heart_full.png"
OUT = ASSETS / "textures/gui/hearts"

# Vanilla hud/heart/container.png alpha mask (9x9): per row (outline xs, fill xs).
CONTAINER_MASK = (
    ((2, 3, 5, 6), ()),
    ((1, 4, 7), (2, 3, 5, 6)),
    ((0, 8), (1, 2, 3, 4, 5, 6, 7)),
    ((0, 8), (1, 2, 3, 4, 5, 6, 7)),
    ((0, 8), (1, 2, 3, 4, 5, 6, 7)),
    ((1, 7), (2, 3, 4, 5, 6)),
    ((2, 6), (3, 4, 5)),
    ((3, 5), (4,)),
    ((4,), ()),
)

# Vanilla half.png == full.png cut to columns 0..4 (right side shows the container).
HALF_MAX_X = 4

# Vanilla full(255,19,19) -> full_blinking(255,161,161): ~0.6 toward white.
BLINK_MIX = 0.58
# Absorption reads violet-white against the ACCENT_DEEP body of the health row.
ABSORB_ACCENT_MIX = 0.50
ABSORB_WHITE_MIX = 0.38


def _mapped(img, mapper):
    """Per-pixel RGB remap preserving alpha (soft sprite: keep sub-128 fringe)."""
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    src, dst = img.load(), out.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            r, g, b, a = src[x, y]
            if a > 0:
                dst[x, y] = rgba(mapper((r, g, b)), a)
    return out


def half_of(img):
    """Vanilla half-heart footprint: keep columns 0..HALF_MAX_X, drop the rest."""
    out = img.copy()
    px = out.load()
    for y in range(out.size[1]):
        for x in range(HALF_MAX_X + 1, out.size[0]):
            px[x, y] = (0, 0, 0, 0)
    return out


def blinking(img):
    return _mapped(img, lambda rgb: mix(rgb, TEXT, BLINK_MIX))


def absorbing(img):
    return _mapped(img, lambda rgb: mix(mix(rgb, ACCENT, ABSORB_ACCENT_MIX),
                                        TEXT, ABSORB_WHITE_MIX))


def container(blink=False):
    img = Image.new("RGBA", (9, 9), (0, 0, 0, 0))
    px = img.load()
    outline = rgba(TEXT if blink else VEIL)
    fill = rgba(HAIRLINE)
    for y, (outline_xs, fill_xs) in enumerate(CONTAINER_MASK):
        for x in outline_xs:
            px[x, y] = outline
        for x in fill_xs:
            px[x, y] = fill
    return img


def main():
    full = Image.open(SOURCE_FULL).convert("RGBA")
    assert full.size == (9, 9), f"expected 9x9 source heart, got {full.size}"
    half = half_of(full)

    sprites = {
        "heart_full": full,
        "heart_half": half,
        "heart_full_blinking": blinking(full),
        "heart_half_blinking": blinking(half),
        "heart_absorbing_full": absorbing(full),
        "heart_absorbing_half": absorbing(half),
        "heart_container": container(),
        "heart_container_blinking": container(blink=True),
    }
    for name, img in sprites.items():
        assert img.size == (9, 9) and img.mode == "RGBA"
        save(img, OUT / f"{name}.png")


if __name__ == "__main__":
    main()
