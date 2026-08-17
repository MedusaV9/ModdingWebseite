"""MONKEY MONEY — Logo-3D-Stinger (prozedural, 45 Frames, 1280x720).

"MONKEY" über "MONEY" als extrudierter Bungee-3D-Text in Gold mit
Bevel-Kante, beide O als drehende Goldmünzen mit MM-Prägung
(Münzen-O aus dem Logo-Design §1.4). Buchstaben fliegen gestaffelt mit
Overshoot zusammen, Kamera fährt einen leichten Orbit, Gold-Lichtblitz
bei Frame ~33. Wonky-Regel: Zeilen ±2.5° verkippt.

Ausgabe: PNG-Sequenz (Alpha) nach assets/img/rendered/logo_stinger/
+ Jungle-Night-Backdrop-Still für die mp4-Komposition (ffmpeg, s. u.).

Aufruf: blender --background --python assets/blender/build_logo_stinger.py
"""

import math
import os
import random
import sys
import time

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import mm_common as mm  # noqa: E402

REPO = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
)
OUT_DIR = os.path.join(REPO, "assets", "img", "rendered", "logo_stinger")
BG_STILL = os.path.join(
    REPO, "assets", "img", "rendered", "logo_stinger_backdrop.png"
)
FONT_PATH = os.path.join(REPO, "assets", "fonts", "bungee.ttf")

FRAMES = 45
FPS = 24
LETTER_GAP = 0.09
RNG = random.Random(42)  # injizierter Zufall — reproduzierbar


def make_letter(name, char, font, gold):
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = char
    curve.font = font
    curve.size = 1.0
    curve.extrude = 0.12
    curve.bevel_depth = 0.02
    curve.bevel_resolution = 2
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(gold)
    return obj


def measure(char, font):
    curve = bpy.data.curves.new("Measure", "FONT")
    curve.body = char
    curve.font = font
    curve.size = 1.0
    obj = bpy.data.objects.new("Measure", curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.update()
    dims = (obj.dimensions.x, obj.dimensions.y)
    bpy.data.objects.remove(obj)
    bpy.data.curves.remove(curve)
    return dims


def make_coin(name, radius, gold, dark_gold, bronze, font):
    """Goldmünze als O-Ersatz: Scheibe + Randwulst + MM-Prägung."""
    rig = bpy.data.objects.new(name + "_rig", None)
    bpy.context.collection.objects.link(rig)

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=40, radius=radius, depth=0.16, rotation=(math.pi / 2, 0, 0)
    )
    disc = bpy.context.active_object
    disc.name = name + "_disc"
    bpy.ops.object.shade_smooth()
    disc.data.use_auto_smooth = True
    disc.data.auto_smooth_angle = math.radians(30)
    disc.data.materials.append(dark_gold)
    disc.parent = rig

    bpy.ops.mesh.primitive_torus_add(
        major_radius=radius * 0.94,
        minor_radius=radius * 0.14,
        major_segments=40,
        minor_segments=12,
        rotation=(math.pi / 2, 0, 0),
    )
    rim = bpy.context.active_object
    rim.name = name + "_rim"
    bpy.ops.object.shade_smooth()
    rim.data.materials.append(gold)
    rim.parent = rig

    emboss = make_letter(name + "_mm", "MM", font, bronze)
    emboss.data.size = radius * 0.85
    emboss.data.extrude = 0.06
    emboss.data.bevel_depth = 0.0
    emboss.data.align_x = "CENTER"
    emboss.data.align_y = "CENTER"
    emboss.rotation_euler = (math.pi / 2, 0, 0)
    emboss.location = (0, -0.11, 0)
    emboss.parent = rig
    return rig


def keyframe_flyin(obj, final_loc, final_rot, start_frame, end_frame):
    """Buchstabe fliegt von zufälliger Streuposition ein (Overshoot)."""
    scatter = (
        final_loc[0] * 2.2 + RNG.uniform(-3.5, 3.5),
        final_loc[1] + RNG.uniform(4.0, 7.0),
        final_loc[2] * 1.5 + RNG.uniform(-2.5, 2.5),
    )
    rot_start = (
        final_rot[0] + RNG.uniform(-0.7, 0.7),
        final_rot[1] + RNG.uniform(-0.7, 0.7),
        final_rot[2] + RNG.uniform(-0.7, 0.7),
    )
    obj.location = scatter
    obj.rotation_euler = rot_start
    obj.keyframe_insert("location", frame=start_frame)
    obj.keyframe_insert("rotation_euler", frame=start_frame)
    obj.location = final_loc
    obj.rotation_euler = final_rot
    obj.keyframe_insert("location", frame=end_frame)
    obj.keyframe_insert("rotation_euler", frame=end_frame)
    for fcurve in obj.animation_data.action.fcurves:
        for kp in fcurve.keyframe_points:
            if kp.co.x <= start_frame + 0.5:
                kp.interpolation = "BACK"
                kp.easing = "EASE_OUT"


def build_line(text, font, gold, dark_gold, bronze, tilt_deg, letter_offset):
    """Eine Logo-Zeile (Baseline z=0); O wird zur Münze in Versalhöhe.

    Gibt (Empty, Breite, Versalhöhe) zurück; Platzierung macht main().
    """
    line = bpy.data.objects.new("Line_" + text, None)
    bpy.context.collection.objects.link(line)

    cap_h = measure("M", font)[1]
    coin_radius = cap_h * 0.5
    widths = [
        coin_radius * 2.0 if ch == "O" else measure(ch, font)[0] for ch in text
    ]
    total = sum(widths) + LETTER_GAP * (len(text) - 1)
    cursor = -total / 2.0

    for idx, (char, width) in enumerate(zip(text, widths)):
        stagger = letter_offset + idx
        start_f = 2 + stagger * 1.4
        end_f = 22 + stagger * 1.1
        if char == "O":
            coin = make_coin(
                "Coin_%s_%d" % (text, idx),
                coin_radius,
                gold,
                dark_gold,
                bronze,
                font,
            )
            coin.parent = line
            final_loc = (cursor + coin_radius, 0, cap_h / 2.0)
            keyframe_flyin(coin, final_loc, (0, 0, 0), start_f, end_f + 4)
            # Münze dreht zusätzlich um die Hochachse ein
            coin.rotation_euler = (0, 0, math.radians(720))
            coin.keyframe_insert("rotation_euler", frame=start_f)
            coin.rotation_euler = (0, 0, 0)
            coin.keyframe_insert("rotation_euler", frame=end_f + 8)
        else:
            letter = make_letter("L_%s_%d" % (text, idx), char, font, gold)
            letter.parent = line
            final_loc = (cursor, 0, 0)
            keyframe_flyin(
                letter, final_loc, (math.pi / 2, 0, 0), start_f, end_f
            )
        cursor += width + LETTER_GAP

    line.rotation_euler = (0, math.radians(tilt_deg), 0)
    return line, total, cap_h


def main():
    t_start = time.time()
    scene = mm.reset_scene()
    mm.setup_eevee(scene, samples=32)
    scene.eevee.use_bloom = True
    scene.eevee.bloom_intensity = 0.08
    scene.render.fps = FPS
    scene.frame_start = 1
    scene.frame_end = FRAMES
    mm.set_world("jungle_night", strength=0.3)

    font = bpy.data.fonts.load(FONT_PATH)
    gold = mm.make_gold("LogoGold", roughness=0.3)
    dark_gold = mm.make_material(
        "LogoDarkGold", "vault_gold", metallic=1.0, roughness=0.5
    )
    bronze = mm.make_material(
        "LogoBronze", mm.hex_rgba("7A5900"), metallic=1.0, roughness=0.6
    )

    line_top, w_top, cap_h = build_line(
        "MONKEY", font, gold, dark_gold, bronze, -2.5, 0
    )
    line_bot, w_bot, _ = build_line(
        "MONEY", font, gold, dark_gold, bronze, 2.0, 6
    )
    # MONEY auf MONKEY-Breite skalieren (klassischer Logo-Stack)
    scale = w_top / w_bot
    line_bot.scale = (scale, scale, scale)
    line_top.location = (0, 0, 0)
    line_bot.location = (0, 0, -(0.30 + cap_h * scale))

    # Logo-Bounding-Box -> Kamera-Framing berechnet statt geraten
    z_max = cap_h
    z_min = -(0.30 + cap_h * scale)
    mid_z = (z_max + z_min) / 2.0
    span_v = z_max - z_min
    lens = 42.0
    dist_w = (w_top / 2.0) * lens / (18.0 * 0.72)  # Logo = 72 % Bildbreite
    dist_v = (span_v / 2.0) * lens / (10.125 * 0.80)
    dist = max(dist_w, dist_v)

    # Kamera-Orbit-Rig
    rig = bpy.data.objects.new("CamRig", None)
    bpy.context.collection.objects.link(rig)
    cam = mm.add_camera(
        (0, -dist * 1.12, mid_z + 0.15), look_at=(0, 0, mid_z), lens=lens
    )
    cam.parent = rig
    rig.rotation_euler = (0, 0, math.radians(-4))
    rig.keyframe_insert("rotation_euler", frame=1)
    rig.rotation_euler = (0, 0, math.radians(4))
    rig.keyframe_insert("rotation_euler", frame=FRAMES)
    cam.keyframe_insert("location", frame=1)
    cam.location = (0, -dist, mid_z + 0.12)
    cam.keyframe_insert("location", frame=FRAMES)
    for fcurve in rig.animation_data.action.fcurves:
        for kp in fcurve.keyframe_points:
            kp.interpolation = "SINE"
            kp.easing = "EASE_IN_OUT"

    lights = mm.three_point_light(
        target=(0, 0, mid_z), key_power=950, fill_power=400, rim_power=1000,
        distance=8.0,
    )

    # Gold-Lichtblitz, wenn das Logo steht
    flash = bpy.data.lights.new("Flash", "AREA")
    flash.size = 6.0
    flash.color = mm.pal("coin_shine")[:3]
    flash_obj = bpy.data.objects.new("FlashLight", flash)
    flash_obj.location = (0, -5.0, mid_z + 2.2)
    bpy.context.collection.objects.link(flash_obj)
    mm.aim_at(flash_obj, (0, 0, mid_z))
    flash.energy = 0.0
    flash.keyframe_insert("energy", frame=26)
    flash.energy = 1300.0
    flash.keyframe_insert("energy", frame=33)
    flash.energy = 550.0
    flash.keyframe_insert("energy", frame=40)

    # Backdrop-Still für die mp4-Komposition: NUR Wand + Glow-Spot,
    # ohne Boden und ohne Studio-Lichter (sonst graue Waschung)
    backdrop = mm.add_backdrop(
        spot_target=(0, 0, mid_z + 0.2),
        spot_power=6000,
        spot_pos=(0, -1.5, mid_z + 1.2),
    )
    backdrop[0].hide_render = True  # Boden weg — Logo schwebt im Studio-Dunkel
    # Wand nach unten ziehen, damit sie ohne Boden das ganze Bild füllt
    backdrop[1].location.z = 0.0
    for obj in bpy.data.objects:
        if obj.name.startswith(("L_", "Coin_", "Line_")):
            obj.hide_render = True
    for light_obj in list(lights.values()) + [flash_obj]:
        light_obj.hide_render = True
    scene.frame_set(1)
    mm.render_still(scene, BG_STILL, res_x=1280, res_y=720)
    print("TIMING backdrop_still %.1fs" % (time.time() - t_start))
    for light_obj in list(lights.values()) + [flash_obj]:
        light_obj.hide_render = False

    # Alpha-Animationspass: Buchstaben an, Backdrop aus
    for obj in bpy.data.objects:
        if obj.name.startswith(("L_", "Coin_", "Line_")):
            obj.hide_render = False
    for obj in backdrop:
        obj.hide_render = True
    scene.render.film_transparent = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    os.makedirs(OUT_DIR, exist_ok=True)
    scene.render.filepath = os.path.join(OUT_DIR, "frame_")

    mm.save_blend(os.path.join(REPO, "assets", "blender", "logo_stinger.blend"))

    t0 = time.time()
    bpy.ops.render.render(animation=True)
    print("TIMING animation %.1fs (%.1fs/Frame)" % (
        time.time() - t0, (time.time() - t0) / FRAMES
    ))
    print("TIMING total %.1fs" % (time.time() - t_start))


if __name__ == "__main__":
    main()
