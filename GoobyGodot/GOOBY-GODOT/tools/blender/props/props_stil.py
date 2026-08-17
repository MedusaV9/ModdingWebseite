# props_stil.py — gemeinsames Stil- und Werkzeug-Modul der WELT2-Home-Props-
# Blender-Pipeline (Muster: tools/blender/ranch/ranch_stil.py; Stilreferenz
# ist das Gooby-Modell: rund, pastellig, weiche Kanten, matte Materialien).
#
# Koordinaten: "Rezept-Raum" = Godot-Raum (Y-up, Blickrichtung -Z, Boden
# y=0, 1 Unit = 1 m). to_blender() konvertiert nach Blender (Z-up); der
# glTF-Export (+Y-up) macht daraus wieder Godot-Konvention mit Blick -Z.
#
# Alle Builder sind deterministisch (rohe Vertex-Listen, keine bpy-Ops für
# Geometrie) — identischer Input ⇒ identisches GLB.

import math
import os

import bpy

TAU = math.pi * 2.0

# ---------------------------------------------------------------------------
# Home-Pastellpalette — 1:1 aus themes/tokens.gd (AcTokens) bzw. der
# HomeProps-PALETTE abgeleitet. KEINE eigenen Farben erfinden.
# ---------------------------------------------------------------------------
PALETTE = {
    "holz":        "#B98D62",   # HomeProps "holz"
    "holz_dunkel": "#8A6642",   # HomeProps "holz_dunkel"
    "rahmen":      "#FFF6EC",   # AcTokens.BG_CREAM (Fenster-/Türrahmen)
    "creme":       "#F6EAD8",   # AcTokens.PAPER_SHADE
    "teal":        "#59C9B9",   # AcTokens.TEAL (Dächer)
    "pink":        "#FF7BA9",   # AcTokens.PINK (Akzent)
    "blatt":       "#8FD06C",   # AcTokens.LEAF
    "blatt_dkl":   "#6DB54E",   # AcTokens.LEAF_DARK
    "gold":        "#FFD34D",   # AcTokens.GOLD (Klinken, Deko)
    "metall":      "#8D7F77",   # AcTokens.INK_SOFT auf Weiß geflacht
    "himmel":      "#CFE9F5",   # AcTokens.SKY_SOFT (Glas-Ton)
    "terra":       "#D96C57",   # Terrakotta (Schornstein, Töpfe)
    "rot":         "#E0655F",   # AcTokens.DANGER (Chili, Wetterhahn)
    "gelb":        "#FFD166",   # AcTokens.YELLOW (Ananas)
    "weiss":       "#FFFFFF",   # AcTokens.WHITE
    "ink":         "#4A3B36",   # AcTokens.INK (kleine Details)
}
PALETTE_ORDER = [
    "holz", "holz_dunkel", "rahmen", "creme",
    "teal", "pink", "blatt", "blatt_dkl",
    "gold", "metall", "himmel", "terra",
    "rot", "gelb", "weiss", "ink",
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


def make_palette_image(name):
    """Palette-Textur (4×4-Zellen) aus PALETTE."""
    size, grid = PALETTE_SIZE, PALETTE_GRID
    cell = size // grid
    img = bpy.data.images.new(name, width=size, height=size, alpha=False)
    px = [0.0] * (size * size * 4)
    for yy in range(size):
        for xx in range(size):
            idx = (grid - 1 - yy // cell) * grid + xx // cell
            rgb = hex_to_rgb(PALETTE[PALETTE_ORDER[idx]])
            o = (yy * size + xx) * 4
            px[o] = srgb_to_linear(rgb[0])
            px[o + 1] = srgb_to_linear(rgb[1])
            px[o + 2] = srgb_to_linear(rgb[2])
            px[o + 3] = 1.0
    img.pixels[:] = px
    img.pack()
    return img


def make_material(img, name="HomePropToon"):
    """Mattes Palette-Material (keine Plastikspiegelung)."""
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


def make_alpha_material(part, alpha, name="HomePropGlas"):
    """Halbtransparentes Flach-Material (Glas, Vorhang) in einer
    Paletten-Farbe — Blend-Alpha, doppelseitig (Godot: cull_disabled)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.blend_method = "BLEND"
    mat.use_backface_culling = False
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    rgb = hex_to_rgb(PALETTE[part])
    bsdf.inputs["Base Color"].default_value = (
        srgb_to_linear(rgb[0]), srgb_to_linear(rgb[1]), srgb_to_linear(rgb[2]), 1.0,
    )
    bsdf.inputs["Alpha"].default_value = alpha
    bsdf.inputs["Roughness"].default_value = 0.6
    bsdf.inputs["Metallic"].default_value = 0.0
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


def to_blender(p):
    """Rezept-Raum (Godot: Y-up, Blick -Z) → Blender (Z-up, Blick +Y)."""
    x, y, z = p
    return (x, -z, y)


# ---------------------------------------------------------------------------
# MeshBuilder (Port aus ranch_stil.py, ohne Regionen/Armature)
# ---------------------------------------------------------------------------
class MeshBuilder:
    def __init__(self):
        self.verts = []
        self.faces = []
        self.vert_part = []

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
        """Kapsel entlang Y (Zylinder-Länge cyl_len) — weiche Kanten."""
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

    def tri_prisma(self, breite, first_h, tiefe, part, pos=(0, 0, 0),
                   quer=False):
        """Giebel-Dreieck: Grundlinie `tiefe` (Z), Spitze `first_h` hoch,
        Dicke `breite` (X). Grundlinie liegt auf y=0, zentriert.
        `quer=True` dreht den First auf die Z-Achse (Dicke wird Z)."""
        hx, hz = breite / 2.0, tiefe / 2.0
        verts = [
            (-hx, 0.0, -hz), (-hx, 0.0, hz), (-hx, first_h, 0.0),
            (hx, 0.0, -hz), (hx, 0.0, hz), (hx, first_h, 0.0),
        ]
        if quer:
            verts = [(z, y, x) for (x, y, z) in verts]
        verts = [vadd(v, pos) for v in verts]
        faces = [
            (0, 1, 2), (5, 4, 3),
            (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3),
        ]
        self.add(verts, faces, part)

    def flaeche(self, punkte_fn, nx, ny, part, pos=(0, 0, 0)):
        """Parametrische Fläche (z. B. Wellen-Vorhang): punkte_fn(u, v) →
        (x, y, z) im Rezept-Raum, u/v in [0, 1], nx×ny Quads."""
        verts = []
        for iy in range(ny + 1):
            for ix in range(nx + 1):
                p = punkte_fn(ix / nx, iy / ny)
                verts.append(vadd(p, pos))
        faces = []
        for iy in range(ny):
            for ix in range(nx):
                a = iy * (nx + 1) + ix
                b = a + 1
                c = a + nx + 2
                d = a + nx + 1
                faces.append((a, b, c, d))
        self.add(verts, faces, part)


# ---------------------------------------------------------------------------
# Szene / Objekt / Export
# ---------------------------------------------------------------------------
def new_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_object(name, mb):
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
    img = make_palette_image(name.lower() + "_palette")
    mat = make_material(img, name + "Toon")
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def build_alpha_object(name, mb, part, alpha):
    """Wie build_object, aber mit halbtransparentem Material (Glas/Vorhang)."""
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(mb.verts, [], mb.faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(make_alpha_material(part, alpha, name + "Glas"))
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def export_glb(path):
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
        export_skins=False,
        export_morph=False,
        export_animations=False,
    )
    print(f"[props_stil] GLB -> {out} ({os.path.getsize(out) / 1024:.0f} KiB)")
