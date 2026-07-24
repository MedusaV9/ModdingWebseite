#!/usr/bin/env python3
"""P3-W1 — Quiet Eclipse handbook rail glyphs + slot-17 padlock badge.

Generates, deterministically (pure math, no noise):
  assets/eclipse/textures/gui/handbook/rail_<id>.png   16x16, pure white + hard alpha;
      the rail tints them at runtime (ACCENT active / DIM idle / TEXT hover), so the
      files stay monochrome. Ids: status, timeline, rules, rewards, bestiary, map,
      revival (W2), settings (W3) — the last two ship early so those tabs get glyphs
      the moment they land (HandbookScreen falls back to a letter until then).
  assets/eclipse/textures/gui/handbook/slot_lock.png   8x8 padlock badge in FINAL
      palette colors (ACCENT lock + PANEL-dark drop shadow), blitted untinted by
      InventorySlotDecor over inventory slot 17.

Run from the repo root:  python3 scripts/placeholder_gen/rail_icons_gen.py
"""

from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "src/main/resources/assets/eclipse/textures/gui/handbook"

WHITE = (255, 255, 255, 255)
ACCENT = (185, 140, 255, 255)   # EclipseUiTheme.ACCENT 0xB98CFF
SHADOW = (18, 11, 30, 235)      # EclipseUiTheme.PANEL body 0x120B1E


def dist2(x, y, cx, cy):
    """Squared distance from the CENTER of pixel (x, y) to point (cx, cy)."""
    return (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2


def in_circle(x, y, cx, cy, r):
    return dist2(x, y, cx, cy) <= r * r


# --- 16x16 glyph predicates (True = white pixel) ------------------------------------


def g_status(x, y):
    """The eclipse itself: a disc with a slim crescent bite out of the upper right."""
    return in_circle(x, y, 8, 8, 6.2) and not in_circle(x, y, 12.6, 3.4, 4.9)


def g_timeline(x, y):
    """Three day-nodes on a horizontal spine."""
    if y == 8 and (4 <= x <= 6 or 10 <= x <= 12):         # spine between the nodes
        return True
    for left in (1, 7, 13):                                # 3x3 square nodes
        if left <= x <= left + 2 and 7 <= y <= 9:
            return True
    return False


def g_rules(x, y):
    """A list: three 2px rule lines with square bullets."""
    for top in (3, 7, 11):
        if top <= y <= top + 1 and (2 <= x <= 3 or 6 <= x <= 13):
            return True
    return False


def g_rewards(x, y):
    """A gift: lid band, box outline, ribbon and bow."""
    if 4 <= y <= 5 and 2 <= x <= 13:                      # lid band
        return True
    if 7 <= y <= 13 and 3 <= x <= 12:                     # box: outline + ribbon
        if y == 13 or x == 3 or x == 12 or 7 <= x <= 8:
            return True
    if 2 <= y <= 3 and (4 <= x <= 5 or 10 <= x <= 11):    # bow loops
        return True
    return False


def g_bestiary(x, y):
    """A skull: cranium, hollow eyes, jaw with tooth gaps."""
    if in_circle(x, y, 8, 7, 5.4):
        if 5 <= x <= 6 and 6 <= y <= 8 or 9 <= x <= 10 and 6 <= y <= 8:
            return False                                   # 2x3 eye sockets
        return True
    if 12 <= y <= 13 and 5 <= x <= 10:
        return not (y == 13 and x in (6, 9))               # jaw, tooth gaps
    return False


def g_map(x, y):
    """A compass: thin ring with a filled diamond needle."""
    d2 = dist2(x, y, 8, 8)
    if 5.1 * 5.1 <= d2 <= 6.4 * 6.4:
        return True
    return abs(x + 0.5 - 8) + abs(y + 0.5 - 8) <= 3.2      # needle


def g_revival(x, y):
    """A heart with a small revival cross at the upper right."""
    if in_circle(x, y, 5.4, 6.0, 2.9) or in_circle(x, y, 10.6, 6.0, 2.9):
        return True
    if 6 <= y <= 13 and abs(x + 0.5 - 8) <= (13.6 - y) * 0.82:
        return True
    if x == 14 and 1 <= y <= 3 or y == 2 and 13 <= x <= 15:
        return True
    return False


def g_settings(x, y):
    """A gear: annulus plus eight short teeth."""
    d2 = dist2(x, y, 8, 8)
    if 2.1 * 2.1 <= d2 <= 4.8 * 4.8:
        return True
    axis = ((8, 2.8), (8, 13.2), (2.8, 8), (13.2, 8))
    diag = ((4.2, 4.2), (11.8, 4.2), (4.2, 11.8), (11.8, 11.8))
    for cx, cy in axis + diag:
        if abs(x + 0.5 - cx) <= 1.1 and abs(y + 0.5 - cy) <= 1.1:
            return True
    return False


GLYPHS = {
    "status": g_status,
    "timeline": g_timeline,
    "rules": g_rules,
    "rewards": g_rewards,
    "bestiary": g_bestiary,
    "map": g_map,
    "revival": g_revival,
    "settings": g_settings,
}


# --- slot_lock.png: 8x8 padlock, final colors ('A' accent; shadow derived) -----------

PADLOCK = [
    ".####...",
    "#....#..",
    "#....#..",
    "######..",
    "######..",
    "##..##..",
    "######..",
    "........",
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    for name, pred in GLYPHS.items():
        img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        px = img.load()
        for y in range(16):
            for x in range(16):
                if pred(x, y):
                    px[x, y] = WHITE
        img.save(OUT / f"rail_{name}.png")
        print(f"rail_{name}.png")

    lock = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    px = lock.load()
    for y, row in enumerate(PADLOCK):               # +1,+1 drop shadow first
        for x, ch in enumerate(row):
            if ch == "#" and x + 1 < 8 and y + 1 < 8:
                px[x + 1, y + 1] = SHADOW
    for y, row in enumerate(PADLOCK):
        for x, ch in enumerate(row):
            if ch == "#":
                px[x, y] = ACCENT
    lock.save(OUT / "slot_lock.png")
    print("slot_lock.png")


if __name__ == "__main__":
    main()
