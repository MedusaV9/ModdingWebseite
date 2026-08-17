# export_glb.py — Stufe 4 der Gooby-Pipeline: GLB-Export für Godot.
#
# Lädt stage3_anims.blend und exportiert EIN gooby.glb:
#   - Mesh + Palette-Textur (eingebettet)
#   - Armature/Skin
#   - Shapekeys (Morph Targets, Namen bleiben erhalten)
#   - alle NLA-Tracks als getrennte glTF-Animationen (Track-Name = Clip-Name;
#     "-loop"-Suffix wird vom Godot-Importer als Loop-Flag interpretiert)
#
# Aufruf:
#   blender --background --factory-startup --python export_glb.py -- \
#       --in /tmp/gooby_build/stage3_anims.blend \
#       --out GOOBY-GODOT/assets/character/gooby.glb

import argparse
import os
import sys

import bpy


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="blend_in", required=True)
    ap.add_argument("--out", dest="glb_out", required=True)
    return ap.parse_args(argv)


def main():
    args = parse_args()
    bpy.ops.wm.open_mainfile(filepath=args.blend_in)

    out = os.path.abspath(args.glb_out)
    os.makedirs(os.path.dirname(out), exist_ok=True)

    # Alles selektieren (Mesh + Armature), damit nichts verloren geht.
    for obj in bpy.data.objects:
        obj.select_set(True)

    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        export_yup=True,
        export_apply=False,          # nicht anwenden: würde Shapekeys zerstören
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_cameras=False,
        export_lights=False,
        export_extras=True,
        export_skins=True,
        export_morph=True,
        export_morph_normal=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",  # 1 Track = 1 glTF-Animation
        export_frame_range=False,
        export_force_sampling=True,
        export_optimize_animation_size=True,
        export_rest_position_armature=True,
    )

    size = os.path.getsize(out)
    print(f"[export_glb] OK -> {out} ({size / 1024:.0f} KiB)")


if __name__ == "__main__":
    main()
