"""MONKEY MONEY — Riesen-Affenhand (prozedural, Low-Poly-Cartoon).

Baut eine stilisierte Affenhand aus Primitiven: Handteller-Block, 4 Finger
à 3 Segmente mit Knöchelkugeln, opponierter Daumen, Unterarm-Stummel.
Braunes Fell flat-shaded, helle Handfläche, dicke Inverted-Hull-Outline
in Warm-Schwarz (#1A1208, Stilgesetz 1).

Posen: 'greif' (offene Greif-Pose, 4 Winkel) und 'faust' (Bestrafung).
Alle Renders 1024² transparent für die Klau-Animation im Browser.

Aufruf: blender --background --python assets/blender/build_hand.py
"""

import math
import os
import sys
import time

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import mm_common as mm  # noqa: E402

REPO = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
)
OUT = os.path.join(REPO, "assets", "img", "rendered")

FUR_HEX = "6E4A2A"  # warmes Schoko-Braun (Palette-Clamp folgt in der Pipeline)
PALM_HEX = "EDC9A3"  # helle Handfläche

POSES = {
    # Basiswinkel + 3 Curl-Winkel pro Fingerglied (Grad), Daumen-Curl
    "greif": {"base": 15, "curls": (28, 42, 48), "thumb": (18, 30)},
    "faust": {"base": 50, "curls": (70, 100, 94), "thumb": (70, 95)},
}


def add_segment(name, radius, length, base, direction, material):
    """Zylinder-Fingerglied entlang 'direction', gibt Endpunkt zurück."""
    direction = direction.normalized()
    center = base + direction * (length / 2.0)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=8, radius=radius, depth=length, location=center
    )
    seg = bpy.context.active_object
    seg.name = name
    seg.rotation_mode = "QUATERNION"
    seg.rotation_quaternion = direction.to_track_quat("Z", "Y")
    seg.data.materials.append(material)
    return seg, base + direction * length


def add_knuckle(name, radius, location, material):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=10, ring_count=6, radius=radius, location=location
    )
    knuckle = bpy.context.active_object
    knuckle.name = name
    knuckle.data.materials.append(material)
    return knuckle


def curl_dir(phi_deg):
    """Fingerrichtung: aufrecht (+Z), gekrümmt zur Handfläche (-Y)."""
    phi = math.radians(phi_deg)
    return Vector((0.0, -math.sin(phi), math.cos(phi)))


def build_hand(pose_name):
    pose = POSES[pose_name]
    fur = mm.make_material("HandFur", mm.hex_rgba(FUR_HEX), roughness=0.95, flat=True)
    palm_mat = mm.make_material(
        "HandPalm", mm.hex_rgba(PALM_HEX), roughness=0.9, flat=True
    )
    parts = []

    # Handteller: bevelter Block
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    palm = bpy.context.active_object
    palm.name = "Palm"
    palm.scale = (0.92, 0.34, 1.0)
    bevel = palm.modifiers.new("Bevel", "BEVEL")
    bevel.width = 0.10
    bevel.segments = 2
    palm.data.materials.append(fur)
    parts.append(palm)

    # Helle Handfläche: gequetschtes Kugel-Oval vor dem Handteller (-Y)
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=14, ring_count=9, radius=0.5, location=(0, -0.14, -0.04)
    )
    pad = bpy.context.active_object
    pad.name = "PalmPad"
    pad.scale = (0.76, 0.15, 0.82)
    pad.data.materials.append(palm_mat)
    parts.append(pad)

    # 4 Finger: (x-Position, Längen-Skala, Radius) — chunky Cartoon-Finger
    fingers = [
        (-0.36, 0.82, 0.115),  # Zeigefinger
        (-0.12, 0.95, 0.122),  # Mittelfinger
        (0.12, 0.88, 0.118),  # Ringfinger
        (0.36, 0.66, 0.100),  # kleiner Finger
    ]
    seg_lengths = (0.34, 0.28, 0.24)
    for f_idx, (x_pos, f_scale, radius) in enumerate(fingers):
        base = Vector((x_pos, -0.02, 0.48))
        phi = pose["base"]
        add_knuckle("F%d_K0" % f_idx, radius * 1.12, base, fur)
        for s_idx, (seg_len, curl) in enumerate(zip(seg_lengths, pose["curls"])):
            phi += curl if s_idx > 0 else 0
            seg, base = add_segment(
                "F%d_S%d" % (f_idx, s_idx),
                radius * (1.0 - 0.07 * s_idx),
                seg_len * f_scale,
                base,
                curl_dir(phi),
                fur,
            )
            parts.append(seg)
            # Nur die Fingerkuppe bekommt ein helles Pad
            knuckle_mat = palm_mat if s_idx == 2 else fur
            parts.append(
                add_knuckle(
                    "F%d_K%d" % (f_idx, s_idx + 1),
                    radius * (1.06 - 0.07 * s_idx),
                    base,
                    knuckle_mat,
                )
            )

    # Daumen: von der linken Handkante, opponiert zur Handfläche
    thumb_base = Vector((-0.52, -0.05, -0.18))
    thumb_dirs = [
        Vector((-0.55, -0.35, 0.75)),
        Vector((0.05, -0.75, 0.66)),
    ]
    thumb_radius = 0.125
    parts.append(add_knuckle("T_K0", thumb_radius * 1.15, thumb_base, fur))
    base = thumb_base
    for s_idx, (t_dir, t_len) in enumerate(zip(thumb_dirs, (0.34, 0.30))):
        curl = math.radians(pose["thumb"][s_idx])
        # Curl kippt den Daumen weiter Richtung Handfläche (-Y)
        direction = Vector(
            (
                t_dir.x * math.cos(curl * 0.4),
                t_dir.y - math.sin(curl),
                t_dir.z * math.cos(curl),
            )
        )
        seg, base = add_segment(
            "T_S%d" % s_idx,
            thumb_radius * (1.0 - 0.1 * s_idx),
            t_len,
            base,
            direction,
            fur,
        )
        parts.append(seg)
        parts.append(
            add_knuckle(
                "T_K%d" % (s_idx + 1),
                thumb_radius * (1.02 - 0.1 * s_idx),
                base,
                palm_mat if s_idx == 1 else fur,
            )
        )

    # Unterarm-Stummel (damit die Hand vom Bildrand hereinragen kann)
    bpy.ops.mesh.primitive_cone_add(
        vertices=10,
        radius1=0.48,
        radius2=0.36,
        depth=1.1,
        location=(0, 0, -1.0),
    )
    arm = bpy.context.active_object
    arm.name = "Forearm"
    arm.data.materials.append(fur)
    parts.append(arm)

    # Fell-Manschette am Handgelenk
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=10, radius=0.46, depth=0.28, location=(0, 0, -0.52)
    )
    cuff = bpy.context.active_object
    cuff.name = "FurCuff"
    cuff.data.materials.append(fur)
    parts.append(cuff)

    # Alles vereinen -> eine Outline über die gesamte Silhouette
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    hand = bpy.context.active_object
    hand.name = "MonkeyHand"
    mm.add_outline(hand, thickness=0.028)

    # Wonky-Regel: 2.5° aus der Achse
    hand.rotation_euler = (0, math.radians(2.5), 0)
    return hand


def render_pose(pose_name, views, blend_name=None):
    scene = mm.reset_scene()
    mm.setup_eevee(scene, samples=48, transparent=True)
    mm.set_world("jungle_night", strength=0.35)
    build_hand(pose_name)
    mm.three_point_light(
        target=(0, 0, 0.2),
        key_power=1400,
        fill_power=500,
        rim_power=900,
        distance=7.0,
    )
    cam = mm.add_camera((0, -4.6, 0.5), look_at=(0, 0, 0.1), lens=50)
    if blend_name:
        mm.save_blend(os.path.join(REPO, "assets", "blender", blend_name))
    for view_name, cam_loc, look_at in views:
        cam.location = cam_loc
        mm.aim_at(cam, look_at)
        t0 = time.time()
        mm.render_still(
            scene, os.path.join(OUT, "hand_%s_%s.png" % (pose_name, view_name))
        )
        print("TIMING hand_%s_%s %.1fs" % (pose_name, view_name, time.time() - t0))


def main():
    t_start = time.time()
    os.makedirs(OUT, exist_ok=True)

    grip_views = [
        ("front", (0, -4.6, 0.5), (0, 0, 0.1)),
        ("dreiviertel", (3.0, -3.4, 1.5), (0, 0, 0.1)),
        ("seite", (4.5, -0.6, 0.6), (0, 0, 0.1)),
        ("ruecken", (0.6, 4.2, 1.8), (0, 0, 0.1)),
    ]
    render_pose("greif", grip_views, blend_name="monkey_hand.blend")

    fist_views = [("front", (0.8, -4.2, 0.4), (0, 0, -0.05))]
    render_pose("faust", fist_views, blend_name="monkey_hand_faust.blend")

    print("TIMING total %.1fs" % (time.time() - t_start))


if __name__ == "__main__":
    main()
