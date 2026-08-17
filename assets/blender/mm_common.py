"""MONKEY MONEY — gemeinsame Blender-Helfer für die 3 prozeduralen Assets.

Palette "Banana Vault" aus docs/ART-SOUND-VIDEO-PLAN.md §1.1 (verbindlich).
Alle Skripte laufen headless: blender --background --python <skript>
"""

import math

import bpy
from mathutils import Vector


def aim_at(obj, target):
    """Objekt (Kamera/Licht, schaut lokal -Z) auf Zielpunkt ausrichten."""
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

# --- Palette (sRGB-Hex aus dem Plan) ------------------------------------
PALETTE = {
    "jungle_night": "0E2A1F",
    "deep_palm": "14532D",
    "leaf": "22A559",
    "banana_leaf": "8FE04B",
    "bill_green": "85BB65",
    "vault_gold": "F5B301",
    "coin_shine": "FFDE6B",
    "banana": "FFC93C",
    "curtain": "C2183B",
    "spotlight_pink": "FF3E8E",
    "studio_led": "29D9D5",
    "ticket_paper": "FFF6E3",
    "outline": "1A1208",
}


def srgb_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def hex_rgba(hex_str, alpha=1.0):
    """Hex (sRGB) -> linearer RGBA-Tupel für Blender-Sockets."""
    hex_str = hex_str.lstrip("#")
    r = int(hex_str[0:2], 16) / 255.0
    g = int(hex_str[2:4], 16) / 255.0
    b = int(hex_str[4:6], 16) / 255.0
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), alpha)


def pal(name, alpha=1.0):
    return hex_rgba(PALETTE[name], alpha)


# --- Szene-Grundlagen -----------------------------------------------------
def reset_scene():
    """Leere Szene, Standard-View-Transform (Palette-treu, kein AgX)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    return scene


def setup_eevee(scene, samples=48, transparent=False):
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = samples
    scene.eevee.use_gtao = True
    scene.eevee.gtao_distance = 0.6
    scene.eevee.use_ssr = True
    scene.eevee.use_soft_shadows = True
    scene.render.film_transparent = transparent


def set_world(color_key="jungle_night", strength=0.25):
    world = bpy.data.worlds.new("MMWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = pal(color_key)
    bg.inputs["Strength"].default_value = strength
    bpy.context.scene.world = world
    return world


# --- Materialien ----------------------------------------------------------
def make_material(
    name,
    color,
    metallic=0.0,
    roughness=0.5,
    emission=None,
    emission_strength=0.0,
    flat=False,
):
    """Principled-Material; color kann Palette-Key oder RGBA-Tupel sein."""
    if isinstance(color, str):
        color = pal(color)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        if isinstance(emission, str):
            emission = pal(emission)
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if flat:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return mat


def make_gold(name="MMGold", roughness=0.28):
    """Warmes Casino-Gold (Vault Gold #F5B301, metallisch)."""
    mat = make_material(name, "vault_gold", metallic=1.0, roughness=roughness)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    # Coin-Shine als warme Glanzkante über den Schichtglanz
    bsdf.inputs["Coat Weight"].default_value = 0.25
    bsdf.inputs["Coat Roughness"].default_value = 0.15
    return mat


def make_outline_material(name="MMOutline"):
    """Warm-schwarzes Outline-Material (Inverted-Hull, #1A1208)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = pal("outline")
    emit.inputs["Strength"].default_value = 1.0
    mat.node_tree.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    mat.use_backface_culling = True
    return mat


def add_outline(obj, thickness=0.02):
    """Inverted-Hull-Outline (dicke warm-schwarze Kontur, Stilgesetz 1)."""
    mat = make_outline_material(obj.name + "_outline_mat")
    obj.data.materials.append(mat)
    mod = obj.modifiers.new("MMOutline", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1.0
    mod.use_rim = False
    mod.use_flip_normals = True
    mod.material_offset = len(obj.data.materials) - 1
    return mod


# --- Licht: 3-Punkt-Studio-Rig (Licht von oben-mitte, Stilgesetz 5) ------
def three_point_light(
    target=(0.0, 0.0, 1.0),
    key_power=800.0,
    fill_power=250.0,
    rim_power=600.0,
    distance=6.0,
    rim_color="coin_shine",
):
    lights = {}
    aim = aim_at

    # Key: vorne-links-oben, warmweiß
    key = bpy.data.lights.new("Key", "AREA")
    key.energy = key_power
    key.size = 3.0
    key.color = (1.0, 0.95, 0.85)
    key_obj = bpy.data.objects.new("KeyLight", key)
    key_obj.location = (-distance * 0.6, -distance * 0.7, distance * 0.9)
    aim(key_obj, target)
    bpy.context.collection.objects.link(key_obj)
    lights["key"] = key_obj

    # Fill: rechts, weich und schwach
    fill = bpy.data.lights.new("Fill", "AREA")
    fill.energy = fill_power
    fill.size = 4.0
    fill.color = (0.85, 0.92, 1.0)
    fill_obj = bpy.data.objects.new("FillLight", fill)
    fill_obj.location = (distance * 0.8, -distance * 0.55, distance * 0.35)
    aim(fill_obj, target)
    bpy.context.collection.objects.link(fill_obj)
    lights["fill"] = fill_obj

    # Rim: hinten-oben, goldene Kante gegen Jungle Night
    rim = bpy.data.lights.new("Rim", "SPOT")
    rim.energy = rim_power
    rim.spot_size = math.radians(70)
    rim.color = pal(rim_color)[:3]
    rim_obj = bpy.data.objects.new("RimLight", rim)
    rim_obj.location = (distance * 0.2, distance * 0.9, distance * 0.95)
    aim(rim_obj, target)
    bpy.context.collection.objects.link(rim_obj)
    lights["rim"] = rim_obj

    return lights


# --- Backdrop + Kamera ----------------------------------------------------
def add_backdrop(
    size=30.0,
    spot_power=1500.0,
    spot_target=(0, 0, 1.2),
    spot_pos=(0, 1.4, 4.2),
):
    """Jungle-Night-Hohlkehle + Spot dahinter = radialer Studio-Glow."""
    mat = make_material(
        "MMBackdrop", "jungle_night", metallic=0.0, roughness=0.95
    )
    # Boden
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "MMFloor"
    floor.data.materials.append(mat)
    # Rückwand
    bpy.ops.mesh.primitive_plane_add(
        size=size,
        location=(0, size * 0.18, size * 0.5),
        rotation=(math.radians(90), 0, 0),
    )
    wall = bpy.context.active_object
    wall.name = "MMWall"
    wall.data.materials.append(mat)
    # Glow-Spot auf die Rückwand (einer der 2 erlaubten Radial-Verläufe).
    # Neutralweiß + HINTER dem Motiv platziert: die Jungle-Night-Wand färbt
    # den Glow, ohne das Gold vorne grün zu verschmutzen.
    spot = bpy.data.lights.new("Glow", "SPOT")
    spot.energy = spot_power
    spot.spot_size = math.radians(50)
    spot.spot_blend = 1.0
    spot.color = (1.0, 1.0, 1.0)
    spot_obj = bpy.data.objects.new("GlowSpot", spot)
    spot_obj.location = spot_pos
    bpy.context.collection.objects.link(spot_obj)
    aim_at(spot_obj, (0, size * 0.18, spot_target[2]))
    return [floor, wall, spot_obj]


def add_camera(location, look_at=(0, 0, 1.0), lens=60.0):
    cam_data = bpy.data.cameras.new("MMCam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("MMCamera", cam_data)
    cam.location = location
    bpy.context.collection.objects.link(cam)
    aim_at(cam, look_at)
    bpy.context.scene.camera = cam
    return cam


def render_still(scene, filepath, res_x=1024, res_y=1024):
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.filepath = filepath
    bpy.ops.render.render(write_still=True)


def save_blend(filepath):
    bpy.ops.wm.save_as_mainfile(filepath=filepath)
