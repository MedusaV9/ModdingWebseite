# build_garage.py — W13C/GARAGE (Doc D §7): Garagen-Baukörper im Stil der
# Shed-/Werkstatt-GLBs (Muster: build_home_props.py) mit dem ROLLTOR als
# SEPARATEM Mesh-Objekt für die Auf/Zu-Animation in Godot.
#
# Aufruf (headless):
#   blender --background --factory-startup \
#       --python tools/blender/props/build_garage.py -- \
#       --out assets/furniture/garage.glb
#
# WICHTIG: Alle Maße MÜSSEN zu scripts/home/garage/garage_prop.gd passen
# (2×3-Footprint im GardenGrid, Tor zeigt nach +Z). Das Rolltor-Objekt hat
# seinen URSPRUNG an der OBERKANTE der Toröffnung (Blatt hängt nach -Y):
# Godot animiert scale.y 1 → 0.08 und das Tor rollt sichtbar nach oben auf.

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

from props_stil import (  # noqa: E402
    MeshBuilder,
    export_glb,
    make_material,
    make_palette_image,
    new_scene,
    palette_uv,
    rot_x,
    rot_z,
    to_blender,
)

# Hüllmaße (= garage_prop.gd; Footprint 2×3 m, 1-m-Garten-Zellen).
BREITE = 1.9
TIEFE = 2.9
WAND_H = 1.9
FIRST_H = 0.4
TOR_BREITE = 1.5
TOR_HOEHE = 1.5
TOR_Z = 1.42


def kapsel_x(mb, r, laenge, part, pos):
    """Liegende Kapsel entlang X (weiche Leiste)."""
    mb.capsule(r, max(laenge - 2 * r, 0.001), 10, 6, part, pos=pos,
               pre_rot=lambda p: rot_z(p, math.pi / 2))


def kapsel_y(mb, r, laenge, part, pos):
    """Stehende Kapsel entlang Y (weicher Pfosten)."""
    mb.capsule(r, max(laenge - 2 * r, 0.001), 10, 6, part, pos=pos)


def kapsel_z(mb, r, laenge, part, pos):
    """Kapsel entlang Z (First, Achsen)."""
    mb.capsule(r, max(laenge - 2 * r, 0.001), 10, 6, part, pos=pos,
               pre_rot=lambda p: rot_x(p, math.pi / 2))


def satteldach_z(mb, breite_x, tiefe_z, first_h, wand_y, part, ueber=0.3):
    """Zwei geneigte Dachplatten + First — Firstlinie entlang Z (das Tor
    liegt auf der +Z-Giebelseite, anders als beim Shed-satteldach)."""
    halb = breite_x / 2.0
    ang = math.atan2(first_h, halb)
    slope = math.hypot(first_h, halb)
    for seite in (-1.0, 1.0):
        a = -seite * ang
        # Normale der gedrehten Platte (0,1,0) → (-sin a, cos a, 0):
        # 3,5 cm anheben, damit die Platte auf dem Giebel aufliegt.
        nx, ny = -math.sin(a), math.cos(a)
        mb.box(slope + ueber * 0.8, 0.07, tiefe_z + ueber, part,
               pos=(seite * halb / 2.0 + nx * 0.035,
                    wand_y + first_h / 2.0 + ny * 0.035, 0.0),
               pre_rot=lambda p, aa=a: rot_z(p, aa))
    kapsel_z(mb, 0.045, tiefe_z + ueber, part,
             pos=(0.0, wand_y + first_h + 0.02, 0.0))


def korpus(mb):
    """Baukörper: Bodenplatte, Wände mit Toröffnung (+Z), Giebel, Dach,
    Laufschienen und Wickelkasten — das Tor selbst ist ein eigenes Objekt."""
    pfosten_b = (BREITE - TOR_BREITE) / 2.0
    mb.box(BREITE, 0.1, TIEFE, "holz_dunkel", pos=(0.0, 0.05, 0.0))
    mb.box(BREITE, WAND_H, 0.12, "creme",
           pos=(0.0, WAND_H * 0.5, -TIEFE / 2.0 + 0.06))
    for seite in (-1.0, 1.0):
        mb.box(0.12, WAND_H, TIEFE, "creme",
               pos=(seite * (BREITE / 2.0 - 0.06), WAND_H * 0.5, 0.0))
        mb.box(pfosten_b, WAND_H, 0.12, "creme",
               pos=(seite * (BREITE - pfosten_b) / 2.0, WAND_H * 0.5,
                    TIEFE / 2.0 - 0.06))
        for z in (-TIEFE / 2.0, TIEFE / 2.0):
            kapsel_y(mb, 0.04, WAND_H + 0.04, "holz_dunkel",
                     pos=(seite * BREITE / 2.0, WAND_H * 0.5, z))
    # Sturz über der Toröffnung (Tor 1.5 m hoch, Wand 1.9 m).
    mb.box(BREITE, WAND_H - TOR_HOEHE, 0.12, "creme",
           pos=(0.0, (WAND_H + TOR_HOEHE) * 0.5, TIEFE / 2.0 - 0.06))
    mb.tri_prisma(TIEFE, FIRST_H, BREITE, "creme",
                  pos=(0.0, WAND_H, 0.0), quer=True)
    satteldach_z(mb, BREITE, TIEFE, FIRST_H, WAND_H, "teal", ueber=0.3)
    # Laufschienen + Wickelkasten des Rolltors (Tor-Ebene z = TOR_Z).
    for seite in (-1.0, 1.0):
        mb.box(0.06, TOR_HOEHE + 0.06, 0.06, "metall",
               pos=(seite * (TOR_BREITE / 2.0 + 0.05),
                    (TOR_HOEHE + 0.06) * 0.5, TOR_Z))
    mb.box(TOR_BREITE + 0.24, 0.2, 0.2, "metall",
           pos=(0.0, TOR_HOEHE + 0.13, TOR_Z - 0.12))
    # Gold-Lampe überm Tor (Gooby-Deko-Akzent wie die Shed-Knäufe).
    mb.uvsphere(0.05, 10, 8, "gold",
                pos=(0.0, WAND_H + 0.16, TIEFE / 2.0 + 0.02))


def rolltor(mb):
    """Rolltor-Blatt mit Lamellen, Bodenleiste + Griff. Ursprung = MITTE
    der Tor-OBERKANTE (Blatt hängt nach -Y) — Godot skaliert scale.y."""
    mb.box(TOR_BREITE, TOR_HOEHE, 0.05, "metall",
           pos=(0.0, -TOR_HOEHE * 0.5, 0.0))
    for i in range(7):
        kapsel_x(mb, 0.016, TOR_BREITE - 0.06, "rahmen",
                 pos=(0.0, -TOR_HOEHE * (i + 1) / 8.0, 0.032))
    mb.box(TOR_BREITE, 0.08, 0.08, "holz_dunkel",
           pos=(0.0, -TOR_HOEHE + 0.04, 0.0))
    mb.uvsphere(0.03, 10, 8, "gold", pos=(0.0, -TOR_HOEHE + 0.13, 0.06))


def build_object_mit(name, mb, mat):
    """Wie props_stil.build_object, aber mit GETEILTEM Palette-Material —
    Korpus + Rolltor teilen sich eine Textur (ein extrahiertes PNG)."""
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(mb.verts, [], mb.faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            uv_layer.data[li].uv = palette_uv(mb.vert_part[vi])
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    new_scene()
    mat = make_material(make_palette_image("garage_palette"), "GarageToon")
    tris = 0
    for name, bauen in (("GarageKorpus", korpus), ("GarageRolltor", rolltor)):
        mb = MeshBuilder()
        bauen(mb)
        obj = build_object_mit(name, mb, mat)
        if name == "GarageRolltor":
            # Pivot an die Tor-Oberkante hängen (Godot: scale.y-Animation).
            obj.location = to_blender((0.0, TOR_HOEHE, TOR_Z))
        tris += sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"[build_garage] tris={tris}")
    export_glb(args.out)


if __name__ == "__main__":
    main()
