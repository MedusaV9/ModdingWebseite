# preview.py — Review-Renders für jede Pipeline-Stage (Cycles CPU, headless-
# fähig ohne GPU/X). Rendert Front-/Dreiviertel-/Seitenansicht; optional eine
# Pose aus einer Action und Shapekey-Werte.
#
# Aufruf:
#   blender --background --factory-startup --python preview.py -- \
#       --blend /tmp/gooby_build/stage1_mesh.blend \
#       --out /tmp/gooby_build/previews --prefix mesh \
#       [--action idle --frame 12] [--shapekey emotion_happy=1.0 ...] \
#       [--views front,three_quarter,side]   (Default: alle drei)

import math
import os
import sys

import bpy


def look_at(cam_obj, target):
    d = (target[0] - cam_obj.location.x,
         target[1] - cam_obj.location.y,
         target[2] - cam_obj.location.z)
    dist = math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2)
    pitch = math.acos(max(-1, min(1, -d[2] / dist)))
    yaw = math.atan2(-d[0], d[1])
    cam_obj.rotation_euler = (pitch, 0.0, yaw)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    blend = "/tmp/gooby_build/stage1_mesh.blend"
    out_dir = "/tmp/gooby_build/previews"
    prefix = "preview"
    action = None
    frame = 1
    shapekeys = {}
    views_filter = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--blend":
            blend = argv[i + 1]; i += 2
        elif a == "--out":
            out_dir = argv[i + 1]; i += 2
        elif a == "--prefix":
            prefix = argv[i + 1]; i += 2
        elif a == "--action":
            action = argv[i + 1]; i += 2
        elif a == "--frame":
            frame = int(argv[i + 1]); i += 2
        elif a == "--shapekey":
            k, v = argv[i + 1].split("=")
            shapekeys[k] = float(v); i += 2
        elif a == "--views":
            views_filter = [v for v in argv[i + 1].split(",") if v]; i += 2
        else:
            i += 1

    bpy.ops.wm.open_mainfile(filepath=blend)
    scene = bpy.context.scene

    obj = bpy.data.objects.get("Gooby")
    if obj is None:
        raise SystemExit("FEHLER: Objekt 'Gooby' nicht gefunden")

    # Pose/Action anwenden
    if action:
        arm = bpy.data.objects.get("GoobyArmature")
        act = bpy.data.actions.get(action)
        if arm is None or act is None:
            raise SystemExit(f"FEHLER: Armature/Action '{action}' fehlt")
        arm.animation_data_create()
        arm.animation_data.action = act
        scene.frame_set(frame)
    if shapekeys and obj.data.shape_keys:
        for k, v in shapekeys.items():
            kb = obj.data.shape_keys.key_blocks.get(k)
            if kb is None:
                raise SystemExit(f"FEHLER: Shapekey '{k}' fehlt")
            kb.value = v

    # Licht + Welt (weich, pastellig)
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (1.0, 0.96, 0.92, 1.0)
    bg.inputs[1].default_value = 0.8
    scene.world = world

    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.data.angle = math.radians(35)
    sun.rotation_euler = (math.radians(50), 0.0, math.radians(30))
    scene.collection.objects.link(sun)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 60
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.film_transparent = False

    target = (0.0, 0.0, 0.52)
    views = {
        "front": (0.0, -2.1, 0.62),
        "three_quarter": (1.4, -1.6, 0.75),
        "side": (2.1, 0.0, 0.62),
    }
    if views_filter:
        unbekannt = [v for v in views_filter if v not in views]
        if unbekannt:
            raise SystemExit(f"FEHLER: unbekannte Views: {unbekannt}")
        views = {k: views[k] for k in views_filter}
    os.makedirs(out_dir, exist_ok=True)
    for name, loc in views.items():
        cam.location = loc
        look_at(cam, target)
        scene.render.filepath = os.path.join(out_dir, f"{prefix}_{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[preview] {scene.render.filepath}")


if __name__ == "__main__":
    main()
