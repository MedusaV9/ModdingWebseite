#!/usr/bin/env python3
"""EARLY sparkling vitamin drink -- photoreal product renders.

Blender 4.0 (headless):
  blender -b -P build_can.py -- --shot still     --flavor peach --res 1080x1920 --out hero.png
  blender -b -P build_can.py -- --shot trio      --res 1920x1080 --out trio.png
  blender -b -P build_can.py -- --shot turntable --flavor peach --res 900x1600  --frames 72 --outdir /tmp/tt
  blender -b -P build_can.py -- --shot dolly     --flavor peach --res 1600x900  --frames 48 --outdir /tmp/dl

Builds a parametric slim can (d=66mm, h=168mm): domed lid with stay-tab,
inset bottom, top seam. Brushed-aluminium body (anisotropic), printed label
(image texture + noise bump), condensation droplets (two icosphere sizes,
label area only, water shader). Studio: seamless backdrop in brand color,
3-point softbox lighting + rim, 85mm camera. Cycles CPU, adaptive sampling,
OpenImageDenoise, Filmic.
"""

import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Vector

# ------------------------------------------------------------------ config --

HERE = os.path.dirname(os.path.abspath(__file__))
LABEL_DIR = os.path.join(HERE, "labels")

R = 0.033           # can radius (66 mm dia)
CAN_H = 0.168       # can height
WALL_Z0 = 0.0125    # straight wall bottom (label start)
WALL_Z1 = 0.1495    # straight wall top (label end)
SEG = 160           # radial segments

FLAVORS = {
    "peach":      {"bg": (0xE7, 0xB7, 0xB7)},
    "grapefruit": {"bg": (0xF2, 0xAC, 0x8F)},
    "lemonmint":  {"bg": (0xCB, 0xD9, 0x7A)},
}


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def brand_rgb(flavor, mul=1.0):
    r, g, b = FLAVORS[flavor]["bg"]
    return tuple(min(1.0, srgb_to_linear(v) * mul) for v in (r, g, b)) + (1.0,)


# ------------------------------------------------------------------- utils --

def set_in(node, name, value):
    """Set a node input by name, ignore if this Blender build lacks it."""
    if name in node.inputs:
        node.inputs[name].default_value = value


def new_mesh_obj(name, verts, faces, collection=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def smooth(obj, auto_angle=math.radians(40)):
    me = obj.data
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    if hasattr(me, "use_auto_smooth"):
        me.use_auto_smooth = True
        me.auto_smooth_angle = auto_angle
    me.update()


def revolve(name, profile, seg=SEG):
    """Revolve an (r, z) polyline around Z. Duplicated seam not needed
    (no UVs). Rings with r ~ 0 collapse to a single pole vertex."""
    verts = []
    ring_index = []  # per profile point: (start_vertex, is_pole)
    for (r, z) in profile:
        if r < 1e-6:
            ring_index.append((len(verts), True))
            verts.append((0.0, 0.0, z))
        else:
            ring_index.append((len(verts), False))
            for i in range(seg):
                a = 2.0 * math.pi * i / seg
                verts.append((r * math.sin(a), -r * math.cos(a), z))
    faces = []
    for p in range(len(profile) - 1):
        s0, pole0 = ring_index[p]
        s1, pole1 = ring_index[p + 1]
        for i in range(seg):
            j = (i + 1) % seg
            if pole0 and not pole1:
                faces.append((s0, s1 + j, s1 + i))
            elif pole1 and not pole0:
                faces.append((s0 + i, s0 + j, s1))
            elif not pole0 and not pole1:
                faces.append((s0 + i, s0 + j, s1 + j, s1 + i))
    obj = new_mesh_obj(name, verts, faces)
    smooth(obj)
    return obj


# -------------------------------------------------------------- materials --

def mat_aluminium(name="aluminium", rough=0.28):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    set_in(bsdf, "Base Color", (0.82, 0.835, 0.845, 1.0))
    set_in(bsdf, "Metallic", 1.0)
    set_in(bsdf, "Roughness", rough)
    set_in(bsdf, "Anisotropic", 0.75)

    # spun/brushed: tangent runs around the circumference
    tan = nt.nodes.new("ShaderNodeTangent")
    tan.direction_type = "RADIAL"
    tan.axis = "Z"
    nt.links.new(tan.outputs["Tangent"], bsdf.inputs["Tangent"])

    # fine roughness variation (brushing streaks)
    texco = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (60.0, 60.0, 900.0)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 4.0
    noise.inputs["Detail"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = 0.0
    ramp.inputs["From Max"].default_value = 1.0
    ramp.inputs["To Min"].default_value = rough - 0.06
    ramp.inputs["To Max"].default_value = rough + 0.08
    nt.links.new(texco.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Value"])
    nt.links.new(ramp.outputs["Result"], bsdf.inputs["Roughness"])
    return m


def mat_label(flavor):
    path = os.path.join(LABEL_DIR, f"early_label_{flavor}.png")
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = "sRGB"

    m = bpy.data.materials.new(f"label_{flavor}")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    set_in(bsdf, "Roughness", 0.42)
    set_in(bsdf, "Metallic", 0.0)
    set_in(bsdf, "Specular IOR Level", 0.45)

    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Cubic"
    tex.extension = "EXTEND"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    # light print/orange-peel texture
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2600.0
    noise.inputs["Detail"].default_value = 3.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.06
    bump.inputs["Distance"].default_value = 0.0004
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def mat_water():
    """Glass water; shadow rays pass through (caustics are disabled, so raw
    glass would cast opaque black micro-shadows on the label)."""
    m = bpy.data.materials.new("water_drops")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    glass = nt.nodes.new("ShaderNodeBsdfGlass")
    glass.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    glass.inputs["Roughness"].default_value = 0.005
    glass.inputs["IOR"].default_value = 1.33
    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Shadow Ray"], mix.inputs["Fac"])
    nt.links.new(glass.outputs["BSDF"], mix.inputs[1])
    nt.links.new(transp.outputs["BSDF"], mix.inputs[2])
    out = nt.nodes["Material Output"]
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return m


def mat_backdrop(rgba, rough=0.5):
    m = bpy.data.materials.new("backdrop")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    set_in(bsdf, "Base Color", rgba)
    set_in(bsdf, "Roughness", rough)
    set_in(bsdf, "Specular IOR Level", 0.25)
    return m


# --------------------------------------------------------------- geometry --

def can_body_profile():
    """(r, z) silhouette: inset domed bottom -> chime -> wall -> neck -> seam
    -> down inside to the lid panel."""
    p = []
    # inset dome (concave, rises into the can)
    p += [(0.0008, 0.0075), (0.008, 0.0062), (0.015, 0.0035), (0.0205, 0.0012)]
    # bottom contact ring + chime
    p += [(0.0235, 0.0), (0.0262, 0.0), (0.0288, 0.0022), (0.0316, 0.0068)]
    # straight wall
    p += [(R, WALL_Z0), (R, WALL_Z1)]
    # neck-in
    p += [(0.0322, 0.1548), (0.0305, 0.159), (0.0288, 0.1618)]
    # top seam (Falz): small bulge, rounded top edge
    p += [(0.0292, 0.1638), (0.0296, 0.1655), (0.0293, 0.1672), (0.0284, 0.168),
          (0.0272, 0.1678), (0.0264, 0.1665)]
    # down inside to lid panel
    p += [(0.0258, 0.1638), (0.0252, 0.1615), (0.0244, 0.1602)]
    # lid panel, slightly domed toward the rivet
    p += [(0.018, 0.1598), (0.010, 0.1602), (0.0008, 0.1607)]
    return p


def build_label_tube(flavor, seg=SEG):
    verts, faces = [], []
    rr = R + 0.00009
    z0, z1 = WALL_Z0 + 0.0004, WALL_Z1 - 0.0004
    for ring, z in enumerate((z0, z1)):
        for i in range(seg + 1):
            a = 2.0 * math.pi * (i / seg - 0.5)
            verts.append((rr * math.sin(a), -rr * math.cos(a), z))
    n = seg + 1
    for i in range(seg):
        faces.append((i, i + 1, n + i + 1, n + i))
    obj = new_mesh_obj(f"label_{flavor}", verts, faces)
    uv = obj.data.uv_layers.new(name="UVMap")
    for loop in obj.data.loops:
        vi = loop.vertex_index
        ring, i = divmod(vi, n)
        uv.data[loop.index].uv = (i / seg, float(ring))
    smooth(obj)
    obj.data.materials.append(mat_label(flavor))
    return obj


def build_tab():
    """Stay-tab from tori + rivet, sitting on the lid panel."""
    objs = []
    z = 0.1612
    # main ring
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.0068, minor_radius=0.0011,
        major_segments=48, minor_segments=12,
        location=(0.0, 0.0045, z))
    ring = bpy.context.object
    ring.scale = (1.0, 1.15, 0.55)
    objs.append(ring)
    # finger hole ring
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.0036, minor_radius=0.0009,
        major_segments=36, minor_segments=10,
        location=(0.0, 0.0078, z))
    hole = bpy.context.object
    hole.scale = (1.0, 1.0, 0.5)
    objs.append(hole)
    # rivet
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.0021, depth=0.0016, vertices=24,
        location=(0.0, -0.0008, z + 0.0002))
    objs.append(bpy.context.object)
    for o in objs:
        smooth(o)
    return objs


def build_droplets(flavor_seed=7, seg_small=1, n_small=2600, n_med=130):
    """Condensation on the label area only: two icosphere sizes, squashed
    against the wall, seeded RNG for determinism."""
    rng = random.Random(flavor_seed)

    def template(subdiv):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=1.0)
        o = bpy.context.object
        vs = [v.co.copy() for v in o.data.vertices]
        fs = [tuple(p.vertices) for p in o.data.polygons]
        bpy.data.objects.remove(o, do_unlink=True)
        return vs, fs

    tpl_small = template(1)
    tpl_med = template(2)

    verts, faces = [], []
    z_lo, z_hi = WALL_Z0 + 0.004, WALL_Z1 - 0.004

    def scatter(tpl, count, r_min, r_max, sag, dome_min, dome_max):
        tvs, tfs = tpl
        for _ in range(count):
            a = rng.uniform(-math.pi, math.pi)
            z = rng.uniform(z_lo, z_hi)
            dr = rng.uniform(r_min, r_max)
            # local frame: n = radial out, t = tangent, up = z
            n = Vector((math.sin(a), -math.cos(a), 0.0))
            t = Vector((math.cos(a), math.sin(a), 0.0))
            up = Vector((0.0, 0.0, 1.0))
            center = n * (R - dr * 0.35) + Vector((0.0, 0.0, z))
            s_t = dr * rng.uniform(0.85, 1.15)
            s_up = dr * rng.uniform(0.9, 1.0 + sag)
            s_n = dr * rng.uniform(dome_min, dome_max)
            base = len(verts)
            for v in tvs:
                p = center + t * (v.x * s_t) + up * (v.y * s_up) + n * (v.z * s_n)
                verts.append(tuple(p))
            for f in tfs:
                faces.append(tuple(base + i for i in f))

    scatter(tpl_small, n_small, 0.00025, 0.0006, 0.05, 0.6, 0.8)
    scatter(tpl_med, n_med, 0.0007, 0.00115, 0.5, 0.85, 1.05)

    obj = new_mesh_obj("droplets", verts, faces)
    smooth(obj)
    obj.data.materials.append(mat_water())
    return obj


def build_can(flavor, x=0.0, seed=7):
    """Full can assembly parented to an empty at (x, 0, 0)."""
    root = bpy.data.objects.new(f"can_root_{flavor}_{x:+.3f}", None)
    bpy.context.scene.collection.objects.link(root)
    root.location = (x, 0.0, 0.0)

    alu = mat_aluminium()
    body = revolve(f"can_body_{flavor}", can_body_profile())
    body.data.materials.append(alu)

    parts = [body, build_label_tube(flavor)]
    parts += build_tab()
    parts.append(build_droplets(seed))
    for o in parts:
        o.parent = root
    return root


def build_backdrop(rgba):
    """Seamless cyclorama: floor -> quarter-arc -> wall, extruded in X."""
    prof = [(-1.6, 0.0)]
    arc_r = 0.35
    cy, cz = 0.30, arc_r  # arc center
    steps = 24
    for i in range(steps + 1):
        ang = math.radians(90.0) * i / steps
        prof.append((cy + arc_r * math.sin(ang), cz - arc_r * math.cos(ang)))
    prof.append((cy + arc_r, 1.6))
    verts, faces = [], []
    xw = 1.8
    for (y, z) in prof:
        verts += [(-xw, y, z), (xw, y, z)]
    for i in range(len(prof) - 1):
        a = 2 * i
        faces.append((a, a + 1, a + 3, a + 2))
    obj = new_mesh_obj("backdrop", verts, faces)
    smooth(obj)
    obj.data.materials.append(mat_backdrop(rgba))
    return obj


# ------------------------------------------------------------ studio setup --

def add_area(name, loc, rot, size, size_y, power, color=(1, 1, 1)):
    data = bpy.data.lights.new(name, "AREA")
    data.shape = "RECTANGLE"
    data.size = size
    data.size_y = size_y
    data.energy = power
    data.color = color
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    obj.rotation_euler = Euler(rot)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def build_lights():
    c = (0.0, 0.0, 0.09)
    # key: big softbox, camera-left, slightly above
    key = add_area("key", (-0.45, -0.42, 0.42), (0, 0, 0), 0.9, 1.1, 9.5,
                   (1.0, 0.985, 0.96))
    look_at(key, c)
    # fill: camera-right, weak and broad
    fill = add_area("fill", (0.55, -0.38, 0.22), (0, 0, 0), 0.9, 0.9, 3.0)
    look_at(fill, c)
    # rim: behind right, narrow strip for the edge highlight
    rim = add_area("rim", (0.34, 0.42, 0.30), (0, 0, 0), 0.12, 0.7, 12,
                   (1.0, 1.0, 1.0))
    look_at(rim, c)
    # top: soft gradient on backdrop + lid
    top = add_area("top", (0.0, 0.05, 1.0), (0, 0, 0), 1.4, 1.4, 4.0)
    look_at(top, (0.0, 0.1, 0.0))
    # strip: crisp vertical specular streak on the metal/label
    strip = add_area("strip", (-0.18, -0.6, 0.16), (0, 0, 0), 0.06, 0.8, 2.0)
    look_at(strip, c)


def build_camera(res_x, res_y, fill_frac, subject_w=None):
    """85mm camera on -Y, tracking a target at can mid-height."""
    target = bpy.data.objects.new("cam_target", None)
    target.location = (0.0, 0.0, 0.084)
    bpy.context.scene.collection.objects.link(target)

    # focus on the label surface (front of the can), not the can axis
    focus = bpy.data.objects.new("cam_focus", None)
    focus.location = (0.0, -R, 0.084)
    bpy.context.scene.collection.objects.link(focus)

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 85.0
    cam_data.sensor_fit = "AUTO"
    cam_data.sensor_width = 36.0
    cam_data.dof.use_dof = True
    cam_data.dof.focus_object = focus
    cam_data.dof.aperture_fstop = 5.6

    # vertical FOV (AUTO fit: 36mm on the larger output dimension)
    if res_x >= res_y:
        v_sensor = 36.0 * res_y / res_x
        h_sensor = 36.0
    else:
        v_sensor = 36.0
        h_sensor = 36.0 * res_x / res_y
    vfov = 2.0 * math.atan(v_sensor / (2.0 * 85.0))
    d = CAN_H / fill_frac / (2.0 * math.tan(vfov / 2.0))
    if subject_w:  # ensure horizontal fit too (trio)
        hfov = 2.0 * math.atan(h_sensor / (2.0 * 85.0))
        d = max(d, subject_w / 0.62 / (2.0 * math.tan(hfov / 2.0)))

    cam = bpy.data.objects.new("camera", cam_data)
    cam.location = (0.0, -d, 0.084)
    bpy.context.scene.collection.objects.link(cam)
    con = cam.constraints.new("DAMPED_TRACK")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    bpy.context.scene.camera = cam
    return cam, target, d


def setup_render(res_x, res_y, samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.04
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.cycles.denoising_input_passes = "RGB_ALBEDO_NORMAL"
    sc.cycles.max_bounces = 8
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 4
    sc.cycles.transmission_bounces = 8
    sc.cycles.transparent_max_bounces = 8
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.sample_clamp_indirect = 8.0
    sc.cycles.blur_glossy = 1.0
    sc.cycles.use_persistent_data = True
    sc.render.resolution_x = res_x
    sc.render.resolution_y = res_y
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.use_motion_blur = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "Filmic"
    sc.view_settings.look = "Medium High Contrast"
    sc.view_settings.exposure = 0.0

    world = bpy.data.worlds.new("studio_world")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.5, 0.5, 0.52, 1.0)
    bg.inputs["Strength"].default_value = 0.08
    sc.world = world


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


# ------------------------------------------------------------------ shots --

def shot_still(args):
    flavor = args.flavor
    build_backdrop(brand_rgb(flavor, 0.92))
    build_can(flavor)
    build_lights()
    fill = 0.60 if args.res_y > args.res_x else 0.80
    build_camera(args.res_x, args.res_y, fill)
    setup_render(args.res_x, args.res_y, args.samples)
    bpy.context.scene.render.filepath = args.out
    bpy.ops.render.render(write_still=True)


def shot_trio(args):
    build_backdrop((0.845, 0.822, 0.800, 1.0))
    spacing = 0.078
    for i, fl in enumerate(("grapefruit", "peach", "lemonmint")):
        build_can(fl, x=(i - 1) * spacing, seed=7 + i)
    build_lights()
    build_camera(args.res_x, args.res_y, 0.80, subject_w=2 * spacing + 2 * R)
    setup_render(args.res_x, args.res_y, args.samples)
    bpy.context.scene.render.filepath = args.out
    bpy.ops.render.render(write_still=True)


def shot_turntable(args):
    flavor = args.flavor
    build_backdrop(brand_rgb(flavor, 0.92))
    root = build_can(flavor)
    build_lights()
    build_camera(args.res_x, args.res_y, 0.60)
    setup_render(args.res_x, args.res_y, args.samples)

    n = args.frames
    root.rotation_euler = (0, 0, 0)
    root.keyframe_insert("rotation_euler", frame=1)
    root.rotation_euler = (0, 0, 2.0 * math.pi)
    root.keyframe_insert("rotation_euler", frame=n + 1)
    for fc in root.animation_data.action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"

    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, n
    sc.render.fps = 24
    sc.render.filepath = os.path.join(args.outdir, "frame_")
    bpy.ops.render.render(animation=True)


def shot_dolly(args):
    flavor = args.flavor
    build_backdrop(brand_rgb(flavor, 0.92))
    build_can(flavor)
    build_lights()
    cam, target, d = build_camera(args.res_x, args.res_y, 0.72)
    setup_render(args.res_x, args.res_y, args.samples)

    n = args.frames
    # slow push-in with a slight lateral drift (camera keeps tracking the can)
    cam.location = (-0.045, -d * 1.10, 0.092)
    cam.keyframe_insert("location", frame=1)
    cam.location = (0.035, -d * 0.94, 0.080)
    cam.keyframe_insert("location", frame=n)
    for fc in cam.animation_data.action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.easing = "EASE_IN_OUT"

    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, n
    sc.render.fps = 24
    sc.render.filepath = os.path.join(args.outdir, "frame_")
    bpy.ops.render.render(animation=True)


# ------------------------------------------------------------------- main --

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot", required=True,
                    choices=["still", "trio", "turntable", "dolly"])
    ap.add_argument("--flavor", default="peach", choices=list(FLAVORS))
    ap.add_argument("--res", default="1080x1920")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--frames", type=int, default=72)
    ap.add_argument("--out", default="/tmp/render.png")
    ap.add_argument("--outdir", default="/tmp/frames")
    args = ap.parse_args(argv)
    args.res_x, args.res_y = (int(v) for v in args.res.split("x"))

    clear_scene()
    if args.shot == "still":
        shot_still(args)
    elif args.shot == "trio":
        shot_trio(args)
    elif args.shot == "turntable":
        os.makedirs(args.outdir, exist_ok=True)
        shot_turntable(args)
    elif args.shot == "dolly":
        os.makedirs(args.outdir, exist_ok=True)
        shot_dolly(args)


if __name__ == "__main__":
    main()
