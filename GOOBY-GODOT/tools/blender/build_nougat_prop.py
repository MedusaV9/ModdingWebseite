# build_nougat_prop.py — W13/FOOD: die NOUGATSCHLEUSE (Küchen-Easter-Egg,
# Web §C6.2 nougatMesh.js) als Wand-Möbel im Gooby-Stil: Rückenplatte,
# Schoko-Tank mit Sichtfenster, Trichter, Auslauf-Rohr mit goldenem Ring,
# hängender Nougat-Tropfen und seitlicher Kurbel (Web: „crank 720°").
#
# Aufruf (headless, aus dem Repo-Root GOOBY-GODOT/):
#   blender --background --factory-startup \
#       --python tools/blender/build_nougat_prop.py -- \
#       --out assets/furniture/nougatschleuse.glb
#
# Stil/Werkzeuge kommen 1:1 aus tools/blender/props/props_stil.py (Palette,
# MeshBuilder, GLB-Export) — KEINE neuen Farben: Schoko = "ink" (nächster
# Paletten-Ton zum Web-Nougat #5C3A21), Gehäuse "creme"/"rahmen", Rohr
# "metall", Kurbel "gold", Akzent "pink". Maße passen zur Wand-Def
# footprint 2×1 / wall_size 2 (FurnitureNode fittet ohnehin per AABB).

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "props"))

from props_stil import (  # noqa: E402
    MeshBuilder,
    build_alpha_object,
    build_object,
    export_glb,
    new_scene,
    rot_x,
    rot_z,
)


def kapsel_x(mb, r, laenge, part, pos):
    """Liegende Kapsel entlang X (Kurbelachse)."""
    mb.capsule(r, max(laenge - 2 * r, 0.001), 10, 6, part,
               pos=pos, pre_rot=lambda p: rot_z(p, math.pi / 2))


def kapsel_z(mb, r, laenge, part, pos):
    """Kapsel entlang Z (Rohrstück in den Raum)."""
    mb.capsule(r, max(laenge - 2 * r, 0.001), 10, 6, part,
               pre_rot=lambda p: rot_x(p, math.pi / 2), pos=pos)


def schleuse_korpus(mb):
    """Rückenplatte + Tank + Trichter + Rohr + Tropfen + Kurbel + Deko."""
    # Rückenplatte (sitzt an der Wand, weiche Leisten oben/unten).
    mb.box(0.78, 0.72, 0.05, "creme", pos=(0.0, 0.92, -0.055))
    kapsel_x(mb, 0.03, 0.8, "rahmen", pos=(0.0, 1.29, -0.055))
    kapsel_x(mb, 0.03, 0.8, "rahmen", pos=(0.0, 0.55, -0.055))

    # Schoko-Tank: runder Rotationskörper voller Nougat.
    mb.lathe(
        [(0.0, 0.92), (0.14, 0.94), (0.19, 1.02), (0.19, 1.2),
         (0.14, 1.3), (0.0, 1.32)],
        14, "ink", pos=(0.0, 0.0, 0.06),
    )
    # Deckelchen mit Knauf.
    mb.lathe([(0.1, 1.3), (0.07, 1.35), (0.0, 1.36)], 12, "rahmen",
             pos=(0.0, 0.0, 0.06))
    mb.uvsphere(0.028, 8, 6, "gold", pos=(0.0, 1.37, 0.06))

    # Trichter unterm Tank → sammelt in den Auslauf.
    mb.lathe([(0.17, 0.92), (0.05, 0.76), (0.045, 0.7)], 12, "metall",
             pos=(0.0, 0.0, 0.06))

    # Rohr: kurzer Bogen in den Raum + senkrechter Auslauf mit Goldring.
    kapsel_z(mb, 0.042, 0.18, "metall", pos=(0.0, 0.72, 0.13))
    mb.lathe([(0.045, 0.58), (0.045, 0.72)], 12, "metall", pos=(0.0, 0.0, 0.2))
    mb.lathe([(0.055, 0.6), (0.055, 0.64)], 12, "gold", pos=(0.0, 0.0, 0.2))

    # Der verheißungsvolle Nougat-Tropfen unter dem Auslauf.
    mb.uvsphere(0.035, 10, 8, "ink", pos=(0.0, 0.545, 0.2),
                scale=(1.0, 1.45, 1.0))

    # Kurbel rechts: Achse, Arm, Knauf (Web: Kurbel-Sequenz ≈ 2,8 s).
    kapsel_x(mb, 0.022, 0.14, "gold", pos=(0.24, 1.05, 0.06))
    mb.box(0.04, 0.16, 0.04, "gold", pos=(0.31, 1.12, 0.06))
    mb.uvsphere(0.035, 10, 8, "pink", pos=(0.31, 1.21, 0.06))

    # Herzchen-Deko auf der Rückenplatte (zwei Bäckchen + Spitze).
    for seite in (-1.0, 1.0):
        mb.uvsphere(0.03, 8, 6, "pink", pos=(seite * 0.026, 0.665, -0.02))
    mb.uvsphere(0.036, 8, 6, "pink", pos=(0.0, 0.64, -0.02),
                scale=(1.15, 1.0, 1.0))

    # Drei Nietenknöpfe unten (kleine Werkstatt-Details).
    for i in range(3):
        mb.uvsphere(0.016, 8, 6, "metall", pos=(-0.28 + i * 0.28, 0.6, -0.02))


def schleuse_fenster(mb):
    """Gläsernes Sichtfenster vorn am Tank (Alpha-Material): parametrische
    Fläche, die sich der Tank-Rundung anschmiegt (Bogen ±35° um +Z)."""

    def punkt(u, v):
        a = (u - 0.5) * 1.22  # ±35° Bogen
        return (math.sin(a) * 0.198, 1.02 + v * 0.2,
                math.cos(a) * 0.198 + 0.06)

    mb.flaeche(punkt, 8, 4, "himmel")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    new_scene()
    tris = 0
    mb = MeshBuilder()
    schleuse_korpus(mb)
    obj = build_object("Nougatschleuse", mb)
    tris += sum(len(p.vertices) - 2 for p in obj.data.polygons)

    mb_glas = MeshBuilder()
    schleuse_fenster(mb_glas)
    glas = build_alpha_object("NougatFenster", mb_glas, "himmel", 0.55)
    tris += sum(len(p.vertices) - 2 for p in glas.data.polygons)

    print(f"[build_nougat_prop] nougatschleuse: tris={tris}")
    export_glb(args.out)


if __name__ == "__main__":
    main()
