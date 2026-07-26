# build_props.py — Statische Gooby-Ranch-Props im Pastell-Look von
# ranch_bau.gd: Turnier-Hindernisse (Sprungständer + Stangen, 3 Varianten),
# Sattel, Bürste, Wassertrog (Tränke) und Heuballen. Kein Rig, keine Clips.
# Vertrag: Boden y=0, "vorne" -Z, Meter.
#
# Aufruf:
#   blender --background --factory-startup --python build_props.py -- \
#       --prop hindernis_a|hindernis_b|hindernis_c|sattel|buerste|trog|heuballen \
#       --out prop.glb
import argparse
import math
import os
import sys

import bpy  # noqa: F401

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ranch_stil import (  # noqa: E402
    MeshBuilder, build_object, export_glb, new_scene, rot_x, rot_z,
)

# Ranch-Pastell (ranch_bau.gd) auf die Palette-Zellen gemappt:
#   fell→Holz hell, maehne→Holz dunkel, nuestern→Scheunenrot, akzent→Teal,
#   fell_hell→Creme, huf→Leder, wange→Rosa, weiss→Weiß
FARBEN = {
    "fell": "#E8C49A",        # HOLZ_HELL
    "maehne": "#B58A5F",      # HOLZ_DUNKEL
    "nuestern": "#D96C57",    # SCHEUNE_ROT
    "akzent": "#5FA8A0",      # DACH_TEAL
    "fell_hell": "#F2E9DC",   # DACH_CREME
    "huf": "#8A5A33",         # Leder
    "wange": "#F9C6CF",
    "weiss": "#FDFDF7",
    "auge": "#3A2E2E",
    "ohr_innen": "#E8C96E",   # HEU_GELB
    "mund": "#4A2B33",
    "auge_glanz": "#FFFFFF",
}


def hindernis(mb, variante):
    """Sprungständer-Paar + gestreifte Stange(n) + Blumenkästen."""
    breite = 3.0
    if variante == "a":            # Kreuz: Stange auf 0.5 m, rot-weiß
        hoehen = [0.55]
        stangen_farben = ("nuestern", "weiss")
        deko = True
    elif variante == "b":          # Steilsprung: 2 Stangen, teal-weiß
        hoehen = [0.45, 0.85]
        stangen_farben = ("akzent", "weiss")
        deko = True
    else:                          # Turnier: 3 Stangen, rot-weiß, hoch
        hoehen = [0.35, 0.7, 1.05]
        stangen_farben = ("nuestern", "fell_hell")
        deko = False

    # Ständer: dicker Fuß + Pfosten + runde Kappe
    for sx in (-1, 1):
        x = sx * breite / 2
        mb.begin(f"staender{sx}")
        mb.box(0.55, 0.10, 0.55, "maehne", pos=(x, 0.05, 0))
        mb.box(0.16, 1.35, 0.16, "fell", pos=(x, 0.72, 0))
        mb.uvsphere(0.115, 10, 8, "akzent", pos=(x, 1.42, 0))
        # Auflage-Zapfen
        for h in hoehen:
            mb.box(0.10, 0.06, 0.28, "maehne", pos=(x - sx * 0.13, h, 0))
        mb.end()

    # Stangen: gestreifte Segmente
    seg = 6
    for hi, h in enumerate(hoehen):
        mb.begin(f"stange{hi}")
        seg_l = (breite - 0.3) / seg
        for i in range(seg):
            part = stangen_farben[i % 2]
            cx = -(breite - 0.3) / 2 + seg_l * (i + 0.5)
            mb.capsule(0.055, seg_l - 0.11, 8, 5, part, pos=(cx, h, 0),
                       pre_rot=lambda p: rot_z(p, math.pi / 2))
        mb.end()

    if deko:
        # Blumenkästen mit Pastell-Tupfern
        for sx in (-1, 1):
            x = sx * (breite / 2 - 0.35)
            mb.begin(f"blumen{sx}")
            mb.box(0.5, 0.24, 0.3, "maehne", pos=(x, 0.12, 0.28))
            for i, part in enumerate(("wange", "ohr_innen", "wange")):
                mb.uvsphere(0.075, 8, 6, part,
                            pos=(x - 0.15 + i * 0.15, 0.30, 0.28))
            mb.end()


def sattel(mb):
    """Gooby-Sattel: Ledersitz + Creme-Pausche + Steigbügel. Liegt bei y=0
    auf (Auflagefläche), Skripte setzen ihn auf RUECKEN_Y."""
    mb.begin("decke")
    mb.box(0.62, 0.035, 0.72, "akzent", pos=(0, 0.02, 0))
    mb.end()
    mb.begin("sitz")
    mb.uvsphere(0.26, 14, 10, "huf", pos=(0, 0.10, 0.02),
                scale=(1.0, 0.55, 1.25))
    mb.uvsphere(0.115, 10, 8, "huf", pos=(0, 0.22, 0.24),
                scale=(1.0, 0.9, 0.6))          # Hinterzwiesel
    mb.uvsphere(0.095, 10, 8, "fell_hell", pos=(0, 0.20, -0.26),
                scale=(1.0, 0.85, 0.7))         # Sattelhorn
    mb.end()
    mb.begin("buegel")
    for sx in (-1, 1):
        mb.box(0.03, 0.30, 0.05, "huf", pos=(sx * 0.30, -0.05, 0.02))
        mb.uvsphere(0.05, 8, 6, "maehne", pos=(sx * 0.31, -0.22, 0.02),
                    scale=(0.5, 1.0, 1.0))
    mb.end()


def buerste(mb):
    """Pflege-Bürste (Handschmeichler): Holzrücken + Borstenfeld."""
    mb.begin("ruecken")
    mb.uvsphere(0.09, 14, 9, "fell", pos=(0, 0.075, 0),
                scale=(1.0, 0.55, 1.7))
    mb.end()
    mb.begin("griff")
    mb.box(0.05, 0.03, 0.22, "huf", pos=(0, 0.115, 0))
    mb.end()
    mb.begin("borsten")
    mb.uvsphere(0.082, 12, 7, "ohr_innen", pos=(0, 0.045, 0),
                scale=(0.95, 0.5, 1.6))
    mb.end()


def trog(mb):
    """Wassertrog/Tränke: Holzwanne + Wasserfläche (wie ranch_bau.baue_trog)."""
    mb.begin("wanne")
    mb.box(1.6, 0.55, 0.8, "maehne", pos=(0, 0.275, 0))
    mb.box(1.44, 0.06, 0.64, "huf", pos=(0, 0.56, 0))
    mb.end()
    mb.begin("wasser")
    mb.box(1.38, 0.02, 0.58, "akzent", pos=(0, 0.52, 0))
    mb.end()
    mb.begin("beine")
    for sx in (-1, 1):
        for sz in (-1, 1):
            mb.box(0.12, 0.12, 0.12, "maehne", pos=(sx * 0.6, 0.0, sz * 0.28))
    mb.end()


def heuballen(mb):
    """Runder Heuballen (liegend) mit Band — Gooby-Heu-Gelb."""
    prof = [(0.0, 0.0), (0.42, 0.01), (0.5, 0.12), (0.5, 0.88),
            (0.42, 0.99), (0.0, 1.0)]
    mb.begin("ballen")
    mb.lathe([(r, (h - 0.5) * 1.0) for (r, h) in prof], 16, "ohr_innen",
             pos=(0, 0.5, 0), pre_rot=lambda p: rot_x(p, math.pi / 2))
    mb.end()
    mb.begin("band")
    for off in (-0.22, 0.22):
        band = [(0.515, off - 0.05), (0.515, off + 0.05)]
        mb.lathe(band, 16, "maehne", pos=(0, 0.5, 0),
                 pre_rot=lambda p: rot_x(p, math.pi / 2))
    mb.end()


PROPS = {
    "hindernis_a": lambda mb: hindernis(mb, "a"),
    "hindernis_b": lambda mb: hindernis(mb, "b"),
    "hindernis_c": lambda mb: hindernis(mb, "c"),
    "sattel": sattel,
    "buerste": buerste,
    "trog": trog,
    "heuballen": heuballen,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--prop", required=True, choices=sorted(PROPS))
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    new_scene()
    mb = MeshBuilder()
    PROPS[args.prop](mb)
    obj = build_object("Ranch" + args.prop.title().replace("_", ""), mb,
                       palette_farben=FARBEN)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"[build_props] {args.prop}: tris={tris}")
    export_glb(args.out, animations=False)


if __name__ == "__main__":
    main()
