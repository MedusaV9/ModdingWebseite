# build_mesh.py — Stage 1 der Gooby-Pipeline: erzeugt das komplette Ein-Mesh-
# Modell (Birnenkörper, Kopf, Schlappohren mit rosa Innenseite, Ärmchen,
# Füßchen mit Pfoten-Pads, Puschelschwanz, Hasenzähne, Wangen, Augen, Mund-
# Decals) mit Palette-Textur im Kenney-Stil. Deterministisch, keine bpy-Ops
# für Geometrie — alles rohe Vertex-/Face-Listen aus den gooby.js-Zahlen.
#
# Aufruf:
#   blender --background --factory-startup --python build_mesh.py -- \
#       --out /tmp/gooby_build/stage1_mesh.blend \
#       [--palette-png GOOBY-GODOT/assets/character/gooby_palette.png]

import json
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gooby_params as P  # noqa: E402

TAU = math.pi * 2.0


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


def catmull_rom_centripetal(points, n_samples):
    """Zentripetale Catmull-Rom-Kurve wie three.js CatmullRomCurve3 (Default).

    points: [(x, y)], Rückgabe: n_samples+1 Punkte gleichverteilt in t.
    """
    pts = [(p[0], p[1]) for p in points]
    n = len(pts)

    def get_point(t):
        p = (n - 1) * t
        ip = int(math.floor(p))
        w = p - ip
        if ip >= n - 1:
            ip = n - 2
            w = 1.0
        p0 = pts[ip - 1] if ip > 0 else (2 * pts[0][0] - pts[1][0], 2 * pts[0][1] - pts[1][1])
        p1 = pts[ip]
        p2 = pts[ip + 1]
        p3 = pts[ip + 2] if ip + 2 < n else (2 * pts[n - 1][0] - pts[n - 2][0],
                                             2 * pts[n - 1][1] - pts[n - 2][1])

        def dist_pow(a, b):
            return (((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** 0.5) ** 0.5  # alpha 0.5

        dt0 = max(dist_pow(p0, p1), 1e-4)
        dt1 = max(dist_pow(p1, p2), 1e-4)
        dt2 = max(dist_pow(p2, p3), 1e-4)

        def cubic(x0, x1, x2, x3):
            t1 = ((x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1) * dt1
            t2 = ((x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2) * dt1
            c0 = x1
            c1 = t1
            c2 = -3 * x1 + 3 * x2 - 2 * t1 - t2
            c3 = 2 * x1 - 2 * x2 + t1 + t2
            return c0 + c1 * w + c2 * w * w + c3 * w * w * w

        return (cubic(p0[0], p1[0], p2[0], p3[0]), cubic(p0[1], p1[1], p2[1], p3[1]))

    return [get_point(i / n_samples) for i in range(n_samples + 1)]


# ---------------------------------------------------------------------------
# Mesh-Builder: sammelt Vertices/Faces + Part-Tags (für Rig/Shapekeys/UVs)
# ---------------------------------------------------------------------------
class MeshBuilder:
    def __init__(self):
        self.verts = []          # Blender-Raum
        self.faces = []
        self.vert_part = []      # Part-Tag pro Vertex (Palette-Zelle)
        self.regions = {}        # logischer Name → (start, end) Vertex-Range

    def begin(self, region):
        self._region = region
        self._start = len(self.verts)

    def end(self):
        self.regions[self._region] = (self._start, len(self.verts))

    def add(self, verts_recipe, faces, part):
        """verts im Rezept-Raum; faces mit lokalen Indizes."""
        base = len(self.verts)
        for v in verts_recipe:
            self.verts.append(P.to_blender(v))
            self.vert_part.append(part)
        for f in faces:
            self.faces.append(tuple(base + i for i in f))

    # -- Primitive (alle im Rezept-Raum, Y-up, Gesicht +Z) --------------------
    def lathe(self, profile, segments, part, pos=(0, 0, 0)):
        """Rotationskörper um die Y-Achse aus einem (radius, höhe)-Profil."""
        verts = []
        rings = []
        for (r, y) in profile:
            if r < 1e-5:
                rings.append([len(verts)])
                verts.append(vadd((0.0, y, 0.0), pos))
            else:
                ring = []
                for s in range(segments):
                    a = TAU * s / segments
                    ring.append(len(verts))
                    verts.append(vadd((math.cos(a) * r, y, math.sin(a) * r), pos))
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

    def uvsphere(self, r, segs, rings, part, pos=(0, 0, 0), scale=(1, 1, 1),
                 pre_rot=None):
        """UV-Sphere (Y-up-Pole). pre_rot: fn(p)->p vor Translation."""
        verts = []
        grid = []
        for ri in range(rings + 1):
            phi = math.pi * ri / rings - math.pi / 2  # -90°..90°
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
        """Kapsel entlang Y (wie THREE.CapsuleGeometry(r, cyl_len))."""
        half = cyl_len / 2.0

        def stretch(p):
            x, y, z = p
            y = y + half if y > 1e-9 else (y - half if y < -1e-9 else y)
            return (x, y, z)

        def pre(p):
            p = stretch(p)
            p = vscale(p, scale)
            if pre_rot:
                p = pre_rot(p)
            return p

        # uvsphere mit stretch als Teil des pre_rot-Hooks
        self.uvsphere(r, segs, rings, part, pos=pos, scale=(1, 1, 1), pre_rot=pre)

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

    def flat_disc(self, rx, ry, segments, part, pos=(0, 0, 0), pre_rot=None,
                  thickness=0.004):
        """Flaches Oval (Fan, zwei Seiten minimal versetzt für Normalen)."""
        verts = []
        center_f = (0.0, 0.0, thickness)
        if pre_rot:
            center_f = pre_rot(center_f)
        verts.append(vadd(center_f, pos))
        ring = []
        for s in range(segments):
            a = TAU * s / segments
            p = (math.cos(a) * rx, math.sin(a) * ry, thickness * 0.6)
            if pre_rot:
                p = pre_rot(p)
            ring.append(len(verts))
            verts.append(vadd(p, pos))
        faces = [(0, ring[s], ring[(s + 1) % segments]) for s in range(segments)]
        self.add(verts, faces, part)

    def arc_band(self, R, w, a0, a1, segments, part, pos=(0, 0, 0), pre_rot=None):
        """Flacher Bogenstreifen in der XY-Ebene (Mundwinkel), zentriert."""
        # Bounding-Box-Zentrierung wie centeredShapeGeo im Web
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
# Gooby-Aufbau
# ---------------------------------------------------------------------------
def build(mb):
    # --- Körper: Birnen-Lathe --------------------------------------------
    profile = catmull_rom_centripetal(P.PEAR_PROFILE, P.PEAR_SAMPLES)
    profile = [(max(0.0, x), y) for (x, y) in profile]
    mb.begin("body")
    mb.lathe(profile, P.PEAR_SEGMENTS, "body")
    mb.end()

    # --- Bauchfleck --------------------------------------------------------
    mb.begin("belly")
    mb.uvsphere(P.BELLY["r"], 16, 12, "belly", pos=P.BELLY["pos"],
                scale=P.BELLY["scale"])
    mb.end()

    # --- Puschelschwanz ----------------------------------------------------
    mb.begin("tail")
    mb.uvsphere(P.TAIL["r"], 10, 8, "belly", pos=P.TAIL["pos"])
    mb.end()

    # --- Kopf ---------------------------------------------------------------
    s = P.HEAD_GRP_SCALE
    head_center = (P.HEAD_LOCAL[0] * s,
                   P.HEAD_PIVOT_Y + P.HEAD_LOCAL[1] * s,
                   P.HEAD_LOCAL[2] * s)
    mb.begin("head")
    mb.uvsphere(P.HEAD_R * s, 22, 16, "body", pos=head_center,
                scale=P.HEAD_SCALE)
    mb.end()

    # --- Ohren (lang, floppy, innen rosa) ------------------------------------
    for side, sx in (("L", -1), ("R", 1)):
        pivot = (sx * P.EAR["pivot_local"][0] * s,
                 P.HEAD_PIVOT_Y + P.EAR["pivot_local"][1] * s,
                 P.EAR["pivot_local"][2] * s)
        lean = sx * -P.EAR["tilt"] * 1.25   # nach außen lehnen (Web EAR_TILT)

        def ear_rot(p, _lean=lean):
            p = rot_x(p, -0.03)             # Hauch nach hinten
            return rot_z(p, _lean)

        mb.begin(f"ear{side}_outer")
        mb.capsule(P.EAR["outer_r"] * s, P.EAR["outer_len"] * s, 10, 9,
                   "body", pos=pivot,
                   pre_rot=lambda p: ear_rot(vadd(p, (0, P.EAR["outer_y"] * s, 0))))
        mb.end()
        mb.begin(f"ear{side}_inner")
        mb.capsule(P.EAR["inner_r"] * s, P.EAR["inner_len"] * s, 8, 7,
                   "earInner", pos=pivot,
                   pre_rot=lambda p: ear_rot(vadd(
                       vscale(p, P.EAR["inner_scale"]),
                       (P.EAR["inner_pos"][0] * s,
                        P.EAR["inner_pos"][1] * s,
                        P.EAR["inner_pos"][2] * s))))
        mb.end()

    # --- Gesicht (goobyFace.js-Zahlen über face_local_to_recipe) -------------
    # Augen: Perle + Glanz
    for side, sx in (("L", -1), ("R", 1)):
        pos = P.face_local_to_recipe(sx * P.EYE["pos"][0], P.EYE["pos"][1],
                                     P.EYE["pos"][2])
        mb.begin(f"eye{side}")
        mb.uvsphere(P.EYE["r"] * s, 12, 9, "eye", pos=pos)
        mb.end()
        shine_pos = vadd(pos, (P.EYE["shine_off"][0] * s,
                               P.EYE["shine_off"][1] * s,
                               P.EYE["shine_off"][2] * s))
        mb.begin(f"eyeShine{side}")
        mb.uvsphere(P.EYE["shine_r"] * s, 8, 6, "eyeShine", pos=shine_pos)
        mb.end()

    # Nase
    nose_pos = P.face_local_to_recipe(*P.NOSE["pos"])
    mb.begin("nose")
    mb.uvsphere(P.NOSE["r"] * s, 12, 9, "nose", pos=nose_pos,
                scale=P.NOSE["scale"])
    mb.end()

    # Hasenzähne (2 Boxen)
    tz = P.face_surface_z(0.0, P.TEETH["y"], P.TEETH["z_push"])
    teeth_anchor = P.face_local_to_recipe(0.0, P.TEETH["y"], tz)
    mb.begin("teeth")
    for sx in (-1, 1):
        mb.box(P.TEETH["w"] * s, P.TEETH["h"] * s, P.TEETH["d"] * s, "tooth",
               pos=teeth_anchor,
               pre_rot=lambda p, _sx=sx: rot_x(
                   rot_z(vadd(p, (_sx * P.TEETH["dx"] * s, -P.TEETH["h"] * s * 0.5, 0)),
                         -_sx * P.TEETH["tilt"]),
                   -P.TEETH["rot_x"]))
    mb.end()

    # Wangen (rosa Bäckchen, leicht gewölbte Discs auf der Kopfoberfläche)
    for side, sx in (("L", -1), ("R", 1)):
        cz = P.face_surface_z(sx * P.CHEEK["x"], P.CHEEK["y"], P.CHEEK["push"])
        pos = P.face_local_to_recipe(sx * P.CHEEK["x"], P.CHEEK["y"], cz)
        # Normale des Kopf-Ellipsoids für die Ausrichtung
        h = P.FACE_HEAD
        n = (sx * P.CHEEK["x"] / h["rx"] ** 2,
             (P.CHEEK["y"] - h["cy"]) / h["ry"] ** 2,
             (cz - h["cz"]) / h["rz"] ** 2)
        ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
        n = (n[0] / ln, n[1] / ln, n[2] / ln)
        yaw = math.atan2(n[0], n[2])
        pitch = -math.asin(max(-1, min(1, n[1])))

        # FB1: 16×6 Segmente + flacherer Buckel (0.35→0.22) — die Web-Wange
        # ist ein glattes flaches Decal, die alte 12×5-Kappe las sich eckig.
        mb.begin(f"cheek{side}")
        mb.uvsphere(P.CHEEK["r"] * s, 16, 6, "cheek", pos=pos,
                    scale=(1.0, 1.0, 0.22),
                    pre_rot=lambda p, _y=yaw, _p=pitch: rot_y(rot_x(p, _p), _y))
        mb.end()

    # Mund-Decals: smile sichtbar, open/frown/flat im Kopf versenkt
    mz = P.face_surface_z(0.0, P.MOUTH["y"], P.MOUTH["push"])
    mouth_anchor = P.face_local_to_recipe(0.0, P.MOUTH["y"], mz)
    tilt = P.MOUTH["rot_x"]

    def mouth_rot(p, depth=0.0):
        return rot_x(vadd(p, (0.0, 0.0, -depth)), -tilt + math.pi / 2 - math.pi / 2)

    def mouth_orient(p, depth):
        # Shape liegt in XY → um X drehen, sodass es +Z guckt und dem
        # Gesichtsgefälle folgt (rot.x 0.28 im Web)
        p = rot_x(p, -tilt)
        return vadd(p, (0.0, 0.0, -depth))

    sunk = P.MOUTH["sunk_depth"]
    mb.begin("mouth_smile")
    mb.arc_band(P.MOUTH["smile_R"] * s, P.MOUTH["smile_w"] * s,
                math.pi + P.MOUTH["smile_a0"], TAU - P.MOUTH["smile_a0"],
                12, "mouth", pos=mouth_anchor,
                pre_rot=lambda p: mouth_orient(p, 0.0))
    mb.end()
    mb.begin("mouth_frown")
    mb.arc_band(P.MOUTH["frown_R"] * s, P.MOUTH["frown_w"] * s,
                P.MOUTH["frown_a0"], math.pi - P.MOUTH["frown_a0"],
                12, "mouth", pos=mouth_anchor,
                pre_rot=lambda p: mouth_orient(p, sunk))
    mb.end()
    mb.begin("mouth_flat")
    mb.flat_disc(P.MOUTH["flat_w"] * s / 2, P.MOUTH["flat_h"] * s / 2, 10,
                 "mouth", pos=mouth_anchor,
                 pre_rot=lambda p: mouth_orient(p, sunk))
    mb.end()
    mb.begin("mouth_open")
    mb.flat_disc(P.MOUTH["open_rx"] * s, P.MOUTH["open_ry"] * s, 12,
                 "mouth", pos=mouth_anchor,
                 pre_rot=lambda p: mouth_orient(p, sunk))
    mb.end()

    # --- Ärmchen (Ruhepose eingebacken: auf dem Bauch) ------------------------
    for side, sx in (("L", -1), ("R", 1)):
        pivot = (sx * P.ARM["pivot"][0], P.ARM["pivot"][1], P.ARM["pivot"][2])

        def arm_rot(p, _sx=sx):
            p = vadd(p, (0.0, P.ARM["mesh_y"], 0.0))
            p = rot_x(p, -P.ARM["rest_fwd"])
            return rot_z(p, _sx * P.ARM["rest_out"])   # Pfötchen nach außen

        mb.begin(f"arm{side}")
        mb.capsule(P.ARM["r"], P.ARM["len"], 9, 7, "body", pos=pivot,
                   pre_rot=arm_rot)
        mb.end()

    # --- Füßchen + Pfoten-Pads ------------------------------------------------
    splay = math.radians(P.FOOT["splay_deg"])
    for side, sx in (("L", -1), ("R", 1)):
        pivot = (sx * P.FOOT["pivot"][0], P.FOOT["pivot"][1], P.FOOT["pivot"][2])

        def foot_rot(p, _sx=sx):
            # Kapsel liegt nach vorn (rot.x 90°), abgeflacht, Zehen nach außen
            p = vscale(p, P.FOOT["scale"])
            p = rot_x(p, math.pi / 2)
            p = vadd(p, (0.0, 0.0, P.FOOT["mesh_z"]))
            return rot_y(p, _sx * splay)

        mb.begin(f"foot{side}")
        mb.capsule(P.FOOT["r"], P.FOOT["len"], 10, 8, "body", pos=pivot,
                   pre_rot=foot_rot)
        mb.end()

        def pad_rot(p, _sx=sx):
            p = vscale(p, (P.FOOT["pad_scale"][0], P.FOOT["pad_scale"][1], 1.0))
            p = rot_x(p, -math.pi / 2)      # Fläche nach unten
            p = vadd(p, P.FOOT["pad_pos"])
            return rot_y(p, _sx * splay)

        mb.begin(f"pad{side}")
        mb.flat_disc(P.FOOT["pad_r"], P.FOOT["pad_r"], 12, "pawPad",
                     pos=pivot, pre_rot=pad_rot, thickness=-0.006)
        mb.end()


# ---------------------------------------------------------------------------
# Palette-Textur + Material
# ---------------------------------------------------------------------------
def make_palette_image(png_path=None):
    size = P.PALETTE_SIZE
    grid = P.PALETTE_GRID
    cell = size // grid
    img = bpy.data.images.new("gooby_palette", width=size, height=size,
                              alpha=False)
    px = [0.0] * (size * size * 4)
    default = P.hex_to_rgb(P.PALETTE["body"])
    for yy in range(size):
        for xx in range(size):
            col = xx // cell
            row = yy // cell
            # Bildzeile 0 = unten; PALETTE_ORDER-Zeile 0 = oben
            idx = (grid - 1 - row) * grid + col
            if idx < len(P.PALETTE_ORDER):
                rgb = P.hex_to_rgb(P.PALETTE[P.PALETTE_ORDER[idx]])
            else:
                rgb = default
            o = (yy * size + xx) * 4
            # sRGB-Bytes DIREKT schreiben (kein srgb_to_linear!): der glTF-
            # Export übernimmt image.pixels 1:1 in die PNG, und glTF
            # interpretiert baseColorTexture als sRGB. Mit Linear-Werten in
            # der PNG dekodiert der Renderer doppelt → alle Pinktöne
            # übersättigt (FB1-Befund: Nase (206,66,90) statt (232,139,160)).
            px[o] = rgb[0]
            px[o + 1] = rgb[1]
            px[o + 2] = rgb[2]
            px[o + 3] = 1.0
    img.pixels[:] = px
    if png_path:
        os.makedirs(os.path.dirname(png_path), exist_ok=True)
        img.filepath_raw = png_path
        img.file_format = "PNG"
        img.save()
    img.pack()
    return img


def make_material(img):
    mat = bpy.data.materials.new("GoobyToon")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.15
    return mat


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_blend = "/tmp/gooby_build/stage1_mesh.blend"
    palette_png = None
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out_blend = argv[i + 1]
            i += 2
        elif argv[i] == "--palette-png":
            palette_png = argv[i + 1]
            i += 2
        else:
            i += 1

    # Leere Szene
    bpy.ops.wm.read_factory_settings(use_empty=True)

    mb = MeshBuilder()
    build(mb)

    mesh = bpy.data.meshes.new("GoobyMesh")
    mesh.from_pydata(mb.verts, [], mb.faces)
    mesh.update()

    obj = bpy.data.objects.new("Gooby", mesh)
    bpy.context.scene.collection.objects.link(obj)

    # UVs: Palette-Zellenmitte je Vertex-Part
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            uv_layer.data[li].uv = P.palette_uv(mb.vert_part[vi])

    # Material + Palette
    img = make_palette_image(palette_png)
    mat = make_material(img)
    mesh.materials.append(mat)

    # Weiche Kenney-Silhouette
    for poly in mesh.polygons:
        poly.use_smooth = True
    if hasattr(mesh, "use_auto_smooth"):
        mesh.use_auto_smooth = True
        mesh.auto_smooth_angle = math.radians(60.0)

    # Part-Ranges für Stage 2 (Rig/Shapekeys) persistieren
    obj["gooby_regions"] = json.dumps(mb.regions)

    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    print(f"[build_mesh] verts={len(mb.verts)} tris={tris} "
          f"(budget {P.TRI_BUDGET})")
    if tris > P.TRI_BUDGET:
        raise SystemExit(f"FEHLER: Tri-Budget überschritten: {tris}")

    os.makedirs(os.path.dirname(out_blend), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    print(f"[build_mesh] OK → {out_blend}")


if __name__ == "__main__":
    main()
