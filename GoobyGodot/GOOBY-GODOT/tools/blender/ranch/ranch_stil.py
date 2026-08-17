# ranch_stil.py — gemeinsames Stil- und Werkzeug-Modul der Gooby-Ranch-
# Blender-Pipeline (Muster: tools/blender/gooby_build/**, das Gooby-Modell
# ist die Stilreferenz: rund, pastellig, große Glanzaugen, dicke Wangen).
#
# Koordinaten: "Rezept-Raum" = Godot-Raum (Y-up, Blickrichtung -Z, Boden
# y=0, 1 Unit = 1 m). to_blender() konvertiert nach Blender (Z-up); der
# glTF-Export (+Y-up) macht daraus wieder Godot-Konvention mit Blick -Z —
# derselbe Vertrag wie das prozedurale Pferd (ranch_pferd.gd / RANCH-2).
#
# Alle Builder hier sind deterministisch (rohe Vertex-Listen, keine
# bpy-Ops für Geometrie) — identischer Input ⇒ identisches GLB.

import math
import os

import bpy

TAU = math.pi * 2.0
ANIM_FPS = 24

# ---------------------------------------------------------------------------
# Gooby-Ranch-Pastellpalette (Fellfarben aus ranch_pferd.gd FELL "palomino",
# Gesichts-/Detailfarben aus gooby_params.PALETTE übernommen).
# ---------------------------------------------------------------------------
PALETTE = {
    "fell":       "#D9A066",   # Palomino-Pastell (ranch_pferd.gd)
    "fell_hell":  "#F2E0C4",   # Schnauze/Bauchfleck
    "maehne":     "#8A5A33",   # Mähne/Schweif (ranch_pferd.gd)
    "huf":        "#6B5A52",
    "wange":      "#F9C6CF",   # dicke rosa Bäckchen (gooby_params CHEEK)
    "auge":       "#3A2E2E",   # große dunkle Kulleraugen (gooby_params EYE)
    "auge_glanz": "#FFFFFF",
    "nuestern":   "#B87A5A",
    "mund":       "#4A2B33",
    "ohr_innen":  "#F6A8B8",   # rosa Ohr-Innenseite (gooby_params EAR)
    "weiss":      "#FDFDF7",
    "akzent":     "#5FA8A0",   # Ranch-Teal (ranch_bau.gd DACH_TEAL)
}
PALETTE_ORDER = [
    "fell", "fell_hell", "maehne", "huf",
    "wange", "auge", "auge_glanz", "nuestern",
    "mund", "ohr_innen", "weiss", "akzent",
]
PALETTE_GRID = 4
PALETTE_SIZE = 256


def hex_to_rgb(hex_str):
    h = hex_str.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def palette_uv(part):
    idx = PALETTE_ORDER.index(part)
    col = idx % PALETTE_GRID
    row = idx // PALETTE_GRID
    return ((col + 0.5) / PALETTE_GRID, 1.0 - (row + 0.5) / PALETTE_GRID)


def make_palette_image(name, farben=None):
    """Palette-Textur (4×4-Zellen) — farben überschreibt PALETTE-Einträge."""
    pal = dict(PALETTE)
    if farben:
        pal.update(farben)
    size, grid = PALETTE_SIZE, PALETTE_GRID
    cell = size // grid
    img = bpy.data.images.new(name, width=size, height=size, alpha=False)
    px = [0.0] * (size * size * 4)
    default = hex_to_rgb(pal["fell"])
    for yy in range(size):
        for xx in range(size):
            idx = (grid - 1 - yy // cell) * grid + xx // cell
            rgb = hex_to_rgb(pal[PALETTE_ORDER[idx]]) if idx < len(PALETTE_ORDER) else default
            o = (yy * size + xx) * 4
            px[o] = srgb_to_linear(rgb[0])
            px[o + 1] = srgb_to_linear(rgb[1])
            px[o + 2] = srgb_to_linear(rgb[2])
            px[o + 3] = 1.0
    img.pixels[:] = px
    img.pack()
    return img


def make_material(img, name="RanchToon"):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes["Principled BSDF"]
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.15
    return mat


# ---------------------------------------------------------------------------
# Mathe-Helfer (rein, deterministisch)
# ---------------------------------------------------------------------------
def rot_x(p, a):
    x, y, z = p
    c, s = math.cos(a), math.sin(a)
    return (x, y * c - z * s, y * s + z * c)


def rot_y(p, a):
    x, y, z = p
    c, s = math.cos(a), math.sin(a)
    return (x * c + z * s, y, -x * s + z * c)


def rot_z(p, a):
    x, y, z = p
    c, s = math.cos(a), math.sin(a)
    return (x * c - y * s, x * s + y * c, z)


def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vscale(p, s):
    return (p[0] * s[0], p[1] * s[1], p[2] * s[2])


def ss(t):
    """Smoothstep 0..1."""
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def to_blender(p):
    """Rezept-Raum (Godot: Y-up, Blick -Z) → Blender (Z-up, Blick +Y).

    Der glTF-Export (+Y-up) macht daraus wieder Y-up mit Blick -Z.
    """
    x, y, z = p
    return (x, -z, y)


# ---------------------------------------------------------------------------
# MeshBuilder (Port aus gooby_build/build_mesh.py, Rezept-Raum wie oben)
# ---------------------------------------------------------------------------
class MeshBuilder:
    def __init__(self):
        self.verts = []
        self.faces = []
        self.vert_part = []
        self.regions = {}
        self._region = None
        self._start = 0

    def begin(self, region):
        self._region = region
        self._start = len(self.verts)

    def end(self):
        self.regions[self._region] = (self._start, len(self.verts))

    def add(self, verts_recipe, faces, part):
        base = len(self.verts)
        for v in verts_recipe:
            self.verts.append(to_blender(v))
            self.vert_part.append(part)
        for f in faces:
            self.faces.append(tuple(base + i for i in f))

    def uvsphere(self, r, segs, rings, part, pos=(0, 0, 0), scale=(1, 1, 1),
                 pre_rot=None):
        verts = []
        grid = []
        for ri in range(rings + 1):
            phi = math.pi * ri / rings - math.pi / 2
            y = math.sin(phi) * r
            rad = math.cos(phi) * r
            if ri == 0 or ri == rings:
                grid.append([len(verts)])
                p = vscale((0.0, y, 0.0), scale)
                if pre_rot:
                    p = pre_rot(p)
                verts.append(vadd(p, pos))
            else:
                ring = []
                for s in range(segs):
                    a = TAU * s / segs
                    p = vscale((math.cos(a) * rad, y, math.sin(a) * rad), scale)
                    if pre_rot:
                        p = pre_rot(p)
                    ring.append(len(verts))
                    verts.append(vadd(p, pos))
                grid.append(ring)
        faces = []
        for i in range(rings):
            a, b = grid[i], grid[i + 1]
            if len(a) == 1:
                for s in range(len(b)):
                    faces.append((a[0], b[(s + 1) % len(b)], b[s]))
            elif len(b) == 1:
                for s in range(len(a)):
                    faces.append((a[s], a[(s + 1) % len(a)], b[0]))
            else:
                for s in range(len(a)):
                    s2 = (s + 1) % len(a)
                    faces.append((a[s], a[s2], b[s2], b[s]))
        self.add(verts, faces, part)

    def capsule(self, r, cyl_len, segs, rings, part, pos=(0, 0, 0),
                scale=(1, 1, 1), pre_rot=None):
        """Kapsel entlang Y (Zylinder-Länge cyl_len)."""
        half = cyl_len / 2.0

        def pre(p):
            x, y, z = p
            y = y + half if y > 1e-9 else (y - half if y < -1e-9 else y)
            p = vscale((x, y, z), scale)
            if pre_rot:
                p = pre_rot(p)
            return p

        self.uvsphere(r, segs, rings, part, pos=pos, scale=(1, 1, 1), pre_rot=pre)

    def lathe(self, profile, segments, part, pos=(0, 0, 0), pre_rot=None):
        """Rotationskörper um die Y-Achse aus (radius, höhe)-Profil."""
        verts = []
        rings = []
        for (r, y) in profile:
            if r < 1e-5:
                rings.append([len(verts)])
                p = (0.0, y, 0.0)
                if pre_rot:
                    p = pre_rot(p)
                verts.append(vadd(p, pos))
            else:
                ring = []
                for s in range(segments):
                    a = TAU * s / segments
                    p = (math.cos(a) * r, y, math.sin(a) * r)
                    if pre_rot:
                        p = pre_rot(p)
                    ring.append(len(verts))
                    verts.append(vadd(p, pos))
                rings.append(ring)
        faces = []
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            if len(a) == 1 and len(b) > 1:
                for s in range(len(b)):
                    faces.append((a[0], b[s], b[(s + 1) % len(b)]))
            elif len(b) == 1 and len(a) > 1:
                for s in range(len(a)):
                    faces.append((a[(s + 1) % len(a)], a[s], b[0]))
            elif len(a) > 1 and len(b) > 1:
                for s in range(len(a)):
                    s2 = (s + 1) % len(a)
                    faces.append((a[s], b[s], b[s2], a[s2]))
        self.add(verts, faces, part)

    def box(self, w, h, d, part, pos=(0, 0, 0), pre_rot=None):
        hw, hh, hd = w / 2, h / 2, d / 2
        corners = [(sx * hw, sy * hh, sz * hd)
                   for sy in (-1, 1) for sz in (-1, 1) for sx in (-1, 1)]
        if pre_rot:
            corners = [pre_rot(c) for c in corners]
        verts = [vadd(c, pos) for c in corners]
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
                 (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        self.add(verts, faces, part)

    def arc_band(self, R, w, a0, a1, segments, part, pos=(0, 0, 0), pre_rot=None):
        """Flacher Bogenstreifen in der XY-Ebene (Lächel-Mund), zentriert."""
        pts_in, pts_out = [], []
        for s in range(segments + 1):
            a = a0 + (a1 - a0) * s / segments
            pts_out.append((math.cos(a) * (R + w / 2), math.sin(a) * (R + w / 2)))
            pts_in.append((math.cos(a) * (R - w / 2), math.sin(a) * (R - w / 2)))
        xs = [p[0] for p in pts_in + pts_out]
        ys = [p[1] for p in pts_in + pts_out]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        verts = []
        for (ox, oy), (ix, iy) in zip(pts_out, pts_in):
            for (x, y) in ((ox - cx, oy - cy), (ix - cx, iy - cy)):
                p = (x, y, 0.0)
                if pre_rot:
                    p = pre_rot(p)
                verts.append(vadd(p, pos))
        faces = []
        for s in range(segments):
            i = s * 2
            faces.append((i, i + 1, i + 3, i + 2))
        self.add(verts, faces, part)


# ---------------------------------------------------------------------------
# Szene / Objekt / Armature
# ---------------------------------------------------------------------------
def new_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = ANIM_FPS


def build_object(name, mb, palette_farben=None):
    """Mesh-Objekt aus dem MeshBuilder + Palette-Material + Zellen-UVs."""
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
    img = make_palette_image(name.lower() + "_palette", palette_farben)
    mat = make_material(img, name + "Toon")
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def build_armature(name, bones):
    """bones: [(name, parent, head_recipe, tail_recipe)] im Rezept-Raum."""
    arm_data = bpy.data.armatures.new(name + "ArmatureData")
    arm_obj = bpy.data.objects.new(name + "Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    ebones = {}
    for bname, parent, head, tail in bones:
        eb = arm_data.edit_bones.new(bname)
        eb.head = to_blender(head)
        eb.tail = to_blender(tail)
        eb.roll = 0.0
        if parent:
            eb.parent = ebones[parent]
            eb.use_connect = False
        ebones[bname] = eb
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def attach(obj, arm_obj):
    obj.parent = arm_obj
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj


# ---------------------------------------------------------------------------
# Animation: Pose-Funktionen samplen → Action → eigener NLA-Track
# ("-loop"-Suffix = Loop-Flag für den Godot-Importer, wie gooby.glb)
# ---------------------------------------------------------------------------
def bake_clip(arm, name, duration, loop, pose_fn):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    if arm.animation_data is None:
        arm.animation_data_create()
    track_name = f"{name}-loop" if loop else name
    action = bpy.data.actions.new(track_name)
    action.use_fake_user = True
    arm.animation_data.action = action

    frames = max(2, int(round(duration * ANIM_FPS)))
    for fi in range(frames + 1):
        t = duration * fi / frames
        pose = pose_fn(t)
        for pb in arm.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = (0, 0, 0)
            pb.scale = (1, 1, 1)
        for (bone, prop), val in pose.items():
            pb = arm.pose.bones.get(bone)
            if pb is None:
                continue
            setattr(pb, prop, val)
        for pb in arm.pose.bones:
            for prop in ("location", "rotation_euler", "scale"):
                pb.keyframe_insert(prop, frame=fi)
    for fc in action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    track = arm.animation_data.nla_tracks.new()
    track.name = track_name
    strip = track.strips.new(track_name, 0, action)
    strip.name = track_name
    arm.animation_data.action = None
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------------------
# GLB-Export (identische Flags wie gooby_build/export_glb.py)
# ---------------------------------------------------------------------------
def export_glb(path, animations=True):
    out = os.path.abspath(path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    for obj in bpy.data.objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        export_yup=True,
        export_apply=False,
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
        export_animations=animations,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=False,
        export_force_sampling=True,
        export_optimize_animation_size=True,
        export_rest_position_armature=True,
    )
    print(f"[ranch_stil] GLB -> {out} ({os.path.getsize(out) / 1024:.0f} KiB)")
