"""MONKEY MONEY — Trophäe "Die Goldene Banane" (prozedural).

Baut: gebogene Gold-Banane (NURBS-Spine + 5-eckiges Profil + Taper) auf
rundem Marmorsockel mit graviertem "MM" (Boolean + Gold-Inlay).
Rendert: Hero 1024² (Jungle Night), Hero transparent, 25-Frame-Turntable
(Frame 25 = Frame 1, füllt das 5x5-Grid; Browser nutzt Zelle 0–23).

Aufruf: blender --background --python assets/blender/build_trophy.py
"""

import math
import os
import sys
import time

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import mm_common as mm  # noqa: E402

REPO = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
)
OUT = os.path.join(REPO, "assets", "img", "rendered")
FONT = os.path.join(REPO, "assets", "fonts", "bungee.ttf")
TURN_DIR = os.path.join(OUT, "trophae_turntable")

BASE_TOP = 0.50  # Oberkante Sockel


def build_banana():
    """Gold-Banane: Kreisbogen-Spine, 5-eck-Profil (Riffen), Taper."""
    # Spine: Kreisbogen ("Smile"-Crescent, liest sofort als Banane)
    radius = 0.95
    theta0, theta1 = math.radians(197), math.radians(343)
    z_center = BASE_TOP + 0.06 + radius
    points = []
    steps = 24
    for i in range(steps + 1):
        theta = theta0 + (theta1 - theta0) * i / steps
        points.append(
            (radius * math.cos(theta), 0.0, z_center + radius * math.sin(theta))
        )

    curve = bpy.data.curves.new("BananaSpine", "CURVE")
    curve.dimensions = "3D"
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for pt, (x, y, z) in zip(spline.points, points):
        pt.co = (x, y, z, 1.0)
    spline.use_endpoint_u = True
    spline.order_u = 4

    # Profil: abgerundetes Fünfeck = Bananen-Riffen
    bpy.ops.curve.primitive_nurbs_circle_add()
    profile = bpy.context.active_object
    profile.name = "BananaProfile"
    # NURBS-Kreis hat 8 Punkte -> auf 5 reduzieren für Pentagon-Charakter
    prof_curve = bpy.data.curves.new("BananaProfile5", "CURVE")
    prof_curve.dimensions = "2D"
    prof_spline = prof_curve.splines.new("NURBS")
    prof_spline.points.add(4)
    for i, pt in enumerate(prof_spline.points):
        ang = math.pi / 2 + i * 2 * math.pi / 5
        pt.co = (0.16 * math.cos(ang), 0.16 * math.sin(ang), 0.0, 1.0)
    prof_spline.use_cyclic_u = True
    prof_spline.order_u = 3
    profile.data = prof_curve
    profile.hide_render = True
    profile.hide_viewport = True

    # Taper: dick in der Mitte, Stiel-Ende stämmig, Blüten-Ende schlanker
    taper_curve = bpy.data.curves.new("BananaTaper", "CURVE")
    taper_curve.dimensions = "2D"
    taper_spline = taper_curve.splines.new("NURBS")
    taper_pts = [
        (0.0, 0.32),
        (0.12, 0.72),
        (0.35, 1.0),
        (0.65, 1.0),
        (0.90, 0.60),
        (1.0, 0.22),
    ]
    taper_spline.points.add(len(taper_pts) - 1)
    for pt, (x, y) in zip(taper_spline.points, taper_pts):
        pt.co = (x, y, 0.0, 1.0)
    taper_spline.use_endpoint_u = True
    taper_obj = bpy.data.objects.new("BananaTaperObj", taper_curve)
    bpy.context.collection.objects.link(taper_obj)
    taper_obj.hide_render = True
    taper_obj.hide_viewport = True

    curve.bevel_mode = "OBJECT"
    curve.bevel_object = profile
    curve.taper_object = taper_obj
    curve.use_fill_caps = True
    banana = bpy.data.objects.new("Banana", curve)
    bpy.context.collection.objects.link(banana)

    # Zu Mesh wandeln + glätten (Auto-Smooth erhält die Riffen-Kanten)
    bpy.context.view_layer.objects.active = banana
    banana.select_set(True)
    bpy.ops.object.convert(target="MESH")
    banana = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    banana.data.use_auto_smooth = True
    banana.data.auto_smooth_angle = math.radians(48)

    # Stiel-Stummel am linken Ende: entlang der Bogen-Tangente angesetzt
    tip0 = (
        radius * math.cos(theta0),
        0.0,
        z_center + radius * math.sin(theta0),
    )
    out0 = (math.sin(theta0), 0.0, -math.cos(theta0))  # auswärts (oben-links)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=12,
        radius=0.052,
        depth=0.20,
        location=(
            tip0[0] + out0[0] * 0.04,
            0.0,
            tip0[2] + out0[2] * 0.04,
        ),
        rotation=(0.0, math.atan2(out0[0], out0[2]), 0.0),
    )
    stem = bpy.context.active_object
    stem.name = "BananaStem"
    bpy.ops.object.shade_smooth()
    stem.data.use_auto_smooth = True
    stem.data.auto_smooth_angle = math.radians(35)

    # Blüten-Nub am rechten Ende, in die Spitze eingesenkt
    tip1 = (
        radius * math.cos(theta1),
        0.0,
        z_center + radius * math.sin(theta1),
    )
    out1 = (-math.sin(theta1), 0.0, math.cos(theta1))
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=16,
        ring_count=8,
        radius=0.052,
        location=(
            tip1[0] + out1[0] * 0.01,
            0.0,
            tip1[2] + out1[2] * 0.01,
        ),
    )
    nub = bpy.context.active_object
    nub.name = "BananaNub"
    bpy.ops.object.shade_smooth()

    # Stiel/Nub an die Banane hängen, dann Wonky-Kippung NUR am Parent
    stem.parent = banana
    nub.parent = banana
    banana.rotation_euler.rotate_axis("Z", math.radians(6))

    return [banana, stem, nub]


def build_base():
    """Zweistufiger Marmorsockel + Gold-Ring + Gold-Deckplatte."""
    objs = []
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=72, radius=0.92, depth=0.24, location=(0, 0, 0.12)
    )
    tier1 = bpy.context.active_object
    tier1.name = "BaseTier1"
    objs.append(tier1)

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=72, radius=0.66, depth=0.26, location=(0, 0, 0.37)
    )
    tier2 = bpy.context.active_object
    tier2.name = "BaseTier2"
    objs.append(tier2)

    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.68,
        minor_radius=0.035,
        major_segments=72,
        minor_segments=16,
        location=(0, 0, 0.25),
    )
    ring = bpy.context.active_object
    ring.name = "BaseGoldRing"
    objs.append(ring)

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=72, radius=0.50, depth=0.05, location=(0, 0, BASE_TOP + 0.02)
    )
    plate = bpy.context.active_object
    plate.name = "BaseGoldPlate"
    objs.append(plate)

    for obj in objs:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.shade_smooth()
        obj.data.use_auto_smooth = True
        obj.data.auto_smooth_angle = math.radians(30)
    return tier1, tier2, ring, plate


def make_marble():
    """Dunkelgrüner Polier-Marmor (Deep Palm) mit hellen Adern."""
    mat = bpy.data.materials.new("MMMarble")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.12
    bsdf.inputs["Metallic"].default_value = 0.0

    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 4.5
    noise.inputs["Detail"].default_value = 4.0
    noise.inputs["Distortion"].default_value = 1.1

    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.30
    ramp.color_ramp.elements[0].color = mm.hex_rgba("071710")
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = mm.hex_rgba("134A2B")

    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def build_mm_engraving(tier2):
    """'MM' in Bungee, per Boolean in Tier 2 graviert + Gold-Inlay."""
    font = bpy.data.fonts.load(FONT)

    def make_text(name, size, extrude, y_offset):
        txt_curve = bpy.data.curves.new(name, "FONT")
        txt_curve.body = "MM"
        txt_curve.font = font
        txt_curve.size = size
        txt_curve.extrude = extrude
        txt_curve.align_x = "CENTER"
        txt_curve.align_y = "CENTER"
        txt = bpy.data.objects.new(name, txt_curve)
        bpy.context.collection.objects.link(txt)
        # Front des Sockels zeigt zur Kamera (-Y); Wonky-Tilt 2°
        txt.location = (0.0, y_offset, 0.37)
        txt.rotation_euler = (
            math.radians(90),
            math.radians(2),
            0.0,
        )
        bpy.context.view_layer.objects.active = txt
        txt.select_set(True)
        bpy.ops.object.convert(target="MESH")
        return bpy.context.active_object

    # Schneidkörper: ragt durch die Zylinderwand
    cutter = make_text("MMCutText", 0.72, 0.10, -0.62)
    cutter.hide_render = True
    cutter.hide_viewport = True

    boolean = tier2.modifiers.new("MMEngrave", "BOOLEAN")
    boolean.operation = "DIFFERENCE"
    boolean.object = cutter
    boolean.solver = "EXACT"

    # Gold-Inlay: etwas kleiner, in der Kavität versenkt (Front bei y=-0.65,
    # also 0.01 HINTER der Zylinderwand bei r=0.66 -> graviert, nicht erhaben)
    inlay = make_text("MMInlay", 0.69, 0.05, -0.60)
    return cutter, inlay


def main():
    t_start = time.time()
    scene = mm.reset_scene()
    mm.setup_eevee(scene, samples=48)
    mm.set_world("jungle_night", strength=0.35)

    gold = mm.make_gold("TrophyGold", roughness=0.24)
    dark_gold = mm.make_material(
        "TrophyDarkGold", "vault_gold", metallic=1.0, roughness=0.45
    )
    plate_gold = mm.make_material(
        "TrophyPlateGold", "vault_gold", metallic=1.0, roughness=0.5
    )
    marble = make_marble()

    banana_objs = build_banana()
    banana_objs[0].data.materials.append(gold)
    banana_objs[1].data.materials.append(dark_gold)  # Stiel
    banana_objs[2].data.materials.append(dark_gold)  # Nub

    tier1, tier2, ring, plate = build_base()
    tier1.data.materials.append(marble)
    tier2.data.materials.append(marble)
    ring.data.materials.append(gold)
    plate.data.materials.append(plate_gold)

    cutter, inlay = build_mm_engraving(tier2)
    inlay.data.materials.append(gold)

    # Turntable-Anker (Stiel/Nub sind bereits Kinder der Banane!)
    pivot = bpy.data.objects.new("TrophyPivot", None)
    bpy.context.collection.objects.link(pivot)
    trophy_parts = [banana_objs[0], tier1, tier2, ring, plate, inlay, cutter]
    for obj in trophy_parts:
        obj.parent = pivot

    backdrop = mm.add_backdrop(spot_target=(0, 0, 1.1), spot_power=2000)
    mm.three_point_light(
        target=(0, 0, 1.0), key_power=1000, fill_power=300, rim_power=700
    )
    mm.add_camera((0.12, -3.7, 1.30), look_at=(0, 0, 0.92), lens=55)

    os.makedirs(OUT, exist_ok=True)
    os.makedirs(TURN_DIR, exist_ok=True)
    mm.save_blend(os.path.join(REPO, "assets", "blender", "trophy_banana.blend"))

    # (a) Hero-Shot auf Jungle Night
    t0 = time.time()
    mm.render_still(scene, os.path.join(OUT, "trophae_hero_1024.png"))
    print("TIMING hero_bg %.1fs" % (time.time() - t0))

    # (b) Transparente Overlay-Variante
    for obj in backdrop:
        obj.hide_render = True
    scene.render.film_transparent = True
    t0 = time.time()
    mm.render_still(scene, os.path.join(OUT, "trophae_hero_transparent.png"))
    print("TIMING hero_alpha %.1fs" % (time.time() - t0))

    # (c) Turntable: 25 Frames à 256² (Frame 25 = Frame 1 fürs volle 5x5)
    t0 = time.time()
    for frame in range(25):
        pivot.rotation_euler = (0, 0, math.radians(frame * 360.0 / 24.0))
        mm.render_still(
            scene,
            os.path.join(TURN_DIR, "frame_%02d.png" % (frame + 1)),
            res_x=256,
            res_y=256,
        )
    print("TIMING turntable %.1fs" % (time.time() - t0))
    print("TIMING total %.1fs" % (time.time() - t_start))


if __name__ == "__main__":
    main()
