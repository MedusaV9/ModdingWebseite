#!/usr/bin/env python3
"""Baut ein sauberes Gooby-Referenzmodell in Blender (bpy) aus dem Runtime-Geo.

Das Skript liest geo/gooby.geo.json (oder das Baby-Geo), erzeugt pro Bone
ein benanntes Empty in korrekter Hierarchie, pro Cube ein benanntes Mesh
(inkl. Inflate) und weist jedem Koerperteil ein benanntes Material mit der
Gooby-Fellpalette zu. Ergebnis ist eine .blend-Datei — es wird keine binaere
.blend eingecheckt, die Quelle ist dieses Skript.

Aufruf (headless):

    blender --background --python assets_src/blender/build_gooby_reference.py -- \
        --geo src/main/resources/assets/goobymod/geo/gooby.geo.json \
        --out assets_src/blender/gooby_reference.blend

Ohne --out bleibt die Szene im Speicher (praktisch fuer interaktives
Weiterarbeiten: Blender ohne --background starten und das Skript im
Scripting-Tab ausfuehren).

Koordinaten-Mapping (Bedrock -> Blender, 16 Pixel = 1 m):
    blender_x = -geo_x / 16     (Bedrock spiegelt X)
    blender_y = -geo_z / 16     (Front des Modells zeigt nach -Y)
    blender_z =  geo_y / 16     (Blender ist Z-up)
"""
from __future__ import annotations

import argparse
import json
import os
import sys

try:
    import bpy
except ImportError:  # pragma: no cover - nur innerhalb Blenders verfuegbar
    sys.exit("Dieses Skript muss innerhalb von Blender laufen: "
             "blender --background --python build_gooby_reference.py -- --help")

SCALE = 1.0 / 16.0

# Palette wie in scripts/gen_entity_textures.py (classic coat).
MATERIALS = {
    "fur": ("Gooby_Fur", (0.788, 0.616, 0.435, 1.0)),
    "fur_dark": ("Gooby_FurDark", (0.667, 0.494, 0.333, 1.0)),
    "cream": ("Gooby_Cream", (0.953, 0.886, 0.784, 1.0)),
    "pink": ("Gooby_Pink", (0.969, 0.667, 0.769, 1.0)),
    "eye": ("Gooby_Eye", (0.235, 0.165, 0.125, 1.0)),
}

# Bone -> Material-Rolle (Cube-Index 0; Detail-Cubes siehe DETAIL_ROLES).
BONE_ROLES = {
    "body": "fur", "head": "fur", "earLeft": "fur", "earRight": "fur",
    "pawLeft": "fur", "pawRight": "fur", "footLeft": "fur", "footRight": "fur",
    "tail": "cream", "muzzle": "cream", "cheekLeft": "pink", "cheekRight": "pink",
    "nose": "pink", "eyeLeft": "eye", "eyeRight": "eye",
    "eyelidLeft": "fur_dark", "eyelidRight": "fur_dark",
}

# (bone, cube_index) -> Rolle fuer die Premium-Detail-Cubes.
DETAIL_ROLES = {
    ("body", 1): "cream",       # Brust-Flausch
    ("earLeft", 1): "fur_dark", ("earRight", 1): "fur_dark",   # Ohrspitzen
    ("earLeft", 2): "pink", ("earRight", 2): "pink",           # Innenohr
    ("tail", 1): "cream",
    ("pawLeft", 1): "fur_dark", ("pawRight", 1): "fur_dark",   # Zehen
    ("footLeft", 1): "fur_dark", ("footRight", 1): "fur_dark",
}


def to_blender(point):
    return (-point[0] * SCALE, -point[2] * SCALE, point[1] * SCALE)


def get_material(role):
    name, color = MATERIALS[role]
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = color
            bsdf.inputs["Roughness"].default_value = 0.85
        material.diffuse_color = color
    return material


def make_cube_mesh(name, cube, collection):
    origin = cube["origin"]
    size = cube["size"]
    inflate = cube.get("inflate", 0)
    lo = [origin[i] - inflate for i in range(3)]
    hi = [origin[i] + size[i] + inflate for i in range(3)]
    for axis in range(3):
        if hi[axis] - lo[axis] <= 0:  # UV-Planes als hauchduenne Boxen
            hi[axis] = lo[axis] + 0.02

    corners = [to_blender((x, y, z))
               for x in (lo[0], hi[0])
               for y in (lo[1], hi[1])
               for z in (lo[2], hi[2])]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
             (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(corners, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)

    bevel = obj.modifiers.new("SoftEdge", "BEVEL")
    bevel.width = 0.008
    bevel.segments = 2
    return obj


def build(geo_path):
    with open(geo_path, "r", encoding="utf-8") as handle:
        geometry = json.load(handle)["minecraft:geometry"][0]
    identifier = geometry["description"]["identifier"].removeprefix("geometry.")

    collection = bpy.data.collections.new(identifier)
    bpy.context.scene.collection.children.link(collection)

    empties = {}
    for bone in geometry["bones"]:
        empty = bpy.data.objects.new(bone["name"], None)
        empty.empty_display_type = "PLAIN_AXES"
        empty.empty_display_size = 0.06
        empty.location = to_blender(bone.get("pivot", [0, 0, 0]))
        collection.objects.link(empty)
        empties[bone["name"]] = empty

    for bone in geometry["bones"]:
        name = bone["name"]
        parent = bone.get("parent")
        empty = empties[name]
        if parent is not None:
            empty.parent = empties[parent]
            empty.matrix_parent_inverse = empties[parent].matrix_world.inverted()

        rotation = bone.get("rotation")
        if rotation:
            import math
            # Bedrock-Rotation um den Pivot: X/Y gespiegelt wie die Achsen.
            empty.rotation_euler = (math.radians(rotation[0]),
                                    math.radians(rotation[2]),
                                    math.radians(-rotation[1]))

        for index, cube in enumerate(bone.get("cubes", [])):
            role = DETAIL_ROLES.get((name, index), BONE_ROLES.get(name, "fur"))
            cube_name = name if index == 0 else f"{name}_{index}"
            obj = make_cube_mesh(cube_name, cube, collection)
            obj.data.materials.append(get_material(role))
            obj.parent = empty
            obj.matrix_parent_inverse = empty.matrix_world.inverted()

    return collection


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    default_geo = os.path.normpath(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..",
        "src", "main", "resources", "assets", "goobymod", "geo", "gooby.geo.json"))
    parser.add_argument("--geo", default=default_geo,
                        help="Pfad zum Bedrock-Geo (Default: gooby.geo.json)")
    parser.add_argument("--out", default=None,
                        help="Zielpfad der .blend-Datei (optional)")
    args = parser.parse_args(argv)

    # Frische Szene ohne Default-Wuerfel/-Licht.
    bpy.ops.wm.read_homefile(use_empty=True)
    build(args.geo)

    if args.out:
        out_path = os.path.abspath(args.out)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=out_path)
        print(f"gespeichert: {out_path}")
    else:
        print("Szene aufgebaut (kein --out angegeben, nichts gespeichert).")


if __name__ == "__main__":
    main()
