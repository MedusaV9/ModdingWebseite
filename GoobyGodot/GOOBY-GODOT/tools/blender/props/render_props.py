# render_props.py — Vorschau-Renderings der selbstgebauten WELT2-Props
# (DoD-Artefakt: "Renderings der selbstgebauten Modelle"). Lädt ein GLB in
# eine leere Szene, rahmt es mit einer Kamera ein und rendert per Cycles
# (CPU — läuft headless ohne GPU/GL-Kontext).
#
# Aufruf:
#   blender --background --factory-startup --python render_props.py -- \
#       --glb ../../assets/props/tuer_blatt.glb --out /tmp/tuer_blatt.png

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(args.glb))

    # Bounding-Box über alle Meshes.
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    mitte = (lo + hi) / 2.0
    radius = max((hi - lo).length / 2.0, 0.05)

    # Kamera: leicht erhöht, 30° seitlich — wie die Godot-Raumkamera.
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    dist = radius * 2.6
    richtung = Vector((math.sin(0.5), -math.cos(0.5), 0.45)).normalized()
    cam.location = mitte + richtung * dist
    blick = mitte - cam.location
    cam.rotation_euler = blick.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam

    sonne = bpy.data.lights.new("Sonne", type="SUN")
    sonne.energy = 4.0
    sonne_obj = bpy.data.objects.new("Sonne", sonne)
    sonne_obj.rotation_euler = (math.radians(50), math.radians(-15), math.radians(30))
    bpy.context.scene.collection.objects.link(sonne_obj)
    welt = bpy.data.worlds.new("Welt")
    welt.use_nodes = True
    bg = welt.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.93, 0.9, 0.85, 1.0)
    bg.inputs[1].default_value = 0.9
    bpy.context.scene.world = welt

    szene = bpy.context.scene
    szene.render.engine = "CYCLES"
    szene.cycles.device = "CPU"
    szene.cycles.samples = 48
    # Head­less-Build ohne OpenImageDenoiser — Denoising abschalten.
    szene.cycles.use_denoising = False
    szene.render.resolution_x = 640
    szene.render.resolution_y = 640
    szene.render.film_transparent = False
    szene.render.filepath = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(szene.render.filepath), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print(f"[render_props] {args.out}")


if __name__ == "__main__":
    main()
