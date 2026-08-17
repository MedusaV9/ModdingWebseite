# build_pferd.py — Das Gooby-Ranch-Pferd als Blender-Build: rund, pastellig,
# große Glanzaugen, dicke rosa Wangen — dieselbe Formensprache wie das
# Gooby-Modell (tools/blender/gooby_build/**). Ersetzt/ergänzt das
# prozedurale ranch_pferd.gd-Pferd und erfüllt dessen Maß-Vertrag:
# Boden y=0, Blick -Z, Rücken-Oberkante ≈ 1.42 m (RUECKEN_Y).
#
# Clips (NLA-Tracks, "-loop" = Godot-Loop): idle, schritt, trab, galopp,
# sprung, fressen, kopfschuetteln, schlafen, blinzeln.
# Shapekey "augen_zu" (Augen zu) wird in schlafen/blinzeln mitanimiert.
#
# Aufruf:
#   blender --background --factory-startup --python build_pferd.py -- \
#       --out pferd.glb [--variante pferd|fohlen]
import argparse
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ranch_stil import (  # noqa: E402
    ANIM_FPS, TAU, MeshBuilder, attach, bake_clip, build_armature,
    build_object, export_glb, new_scene, rot_x, rot_y, rot_z, ss, vadd,
)


# ---------------------------------------------------------------------------
# Proportionen (Rezept-Raum = Godot-Raum: Y-up, Blick -Z, Meter)
# ---------------------------------------------------------------------------
def params(variante):
    if variante == "fohlen":
        # Baby-Schema: kleiner Körper, RIESIGER Kopf, Stummelbeine.
        g = 0.62
        return {
            "body":   {"r": 0.52 * g, "scale": (1.0, 0.92, 1.28), "pos": (0, 0.66, 0.05 * g)},
            "chest":  {"r": 0.40 * g, "scale": (0.95, 0.92, 0.95), "pos": (0, 0.70, -0.30)},
            "belly":  {"r": 0.44 * g, "scale": (0.92, 0.74, 1.05), "pos": (0, 0.55, 0.07)},
            "neck":   {"r": 0.155, "len": 0.16, "pos": (0, 0.86, -0.44), "tilt": -0.55},
            "head":   {"r": 0.275, "scale": (1.0, 0.96, 1.0), "pos": (0, 1.06, -0.56)},
            "muzzle": {"r": 0.145, "scale": (1.12, 0.76, 1.05), "pos": (0, 0.97, -0.77)},
            "nuest":  {"r": 0.019, "pos": (0.055, 1.005, -0.912)},
            "mouth":  {"R": 0.040, "w": 0.012, "pos": (0, 0.935, -0.910), "tilt": -0.35},
            "eye":    {"r": 0.092, "pos": (0.15, 1.14, -0.76)},
            "shine":  {"r": 0.032, "off": (0.020, 0.028, -0.050)},
            "cheek":  {"r": 0.098, "pos": (0.215, 1.01, -0.60), "yaw": 0.85},
            "ear":    {"base": (0.115, 1.29, -0.48), "len": 0.21, "r": 0.068,
                       "tilt_out": 0.34, "tilt_back": 0.14},
            "mane":   [((0, 1.315, -0.66), 0.095, (1.1, 0.68, 1.0)),
                       ((0, 1.29, -0.42), 0.10, (1, 1, 1)),
                       ((0, 1.16, -0.30), 0.10, (1, 1, 1)),
                       ((0, 1.02, -0.19), 0.095, (1, 1, 1))],
            "tail":   [((0, 0.80, 0.52), 0.10), ((0, 0.66, 0.62), 0.082),
                       ((0, 0.53, 0.67), 0.065)],
            "leg":    {"r": 0.082, "len": 0.28, "y": 0.30,
                       "front": (0.165, -0.26), "back": (0.18, 0.32)},
            "huf":    {"r": 0.098, "y": 0.062},
            "hip_y":  0.60,
        }
    # Erwachsenes Pferd
    return {
        "body":   {"r": 0.52, "scale": (1.0, 0.90, 1.42), "pos": (0, 0.95, 0.08)},
        "chest":  {"r": 0.42, "scale": (0.95, 0.92, 0.95), "pos": (0, 1.00, -0.52)},
        "belly":  {"r": 0.44, "scale": (0.92, 0.72, 1.10), "pos": (0, 0.78, 0.12)},
        "neck":   {"r": 0.21, "len": 0.42, "pos": (0, 1.28, -0.70), "tilt": -0.62},
        "head":   {"r": 0.34, "scale": (1.0, 0.95, 1.0), "pos": (0, 1.60, -0.92)},
        "muzzle": {"r": 0.19, "scale": (1.10, 0.78, 1.05), "pos": (0, 1.48, -1.18)},
        "nuest":  {"r": 0.026, "pos": (0.072, 1.525, -1.372)},
        "mouth":  {"R": 0.055, "w": 0.016, "pos": (0, 1.435, -1.368), "tilt": -0.35},
        "eye":    {"r": 0.098, "pos": (0.175, 1.70, -1.16)},
        "shine":  {"r": 0.034, "off": (0.022, 0.030, -0.055)},
        "cheek":  {"r": 0.115, "pos": (0.27, 1.53, -1.05), "yaw": 0.85},
        "ear":    {"base": (0.15, 1.885, -0.82), "len": 0.27, "r": 0.085,
                   "tilt_out": 0.30, "tilt_back": 0.14},
        "mane":   [((0, 1.90, -1.04), 0.125, (1.1, 0.68, 1.0)),   # Stirnschopf
                   ((0, 1.88, -0.72), 0.135, (1, 1, 1)),
                   ((0, 1.73, -0.54), 0.14, (1, 1, 1)),
                   ((0, 1.56, -0.38), 0.135, (1, 1, 1)),
                   ((0, 1.43, -0.24), 0.125, (1, 1, 1))],
        "tail":   [((0, 1.18, 0.82), 0.15), ((0, 0.96, 0.94), 0.12),
                   ((0, 0.76, 1.01), 0.095)],
        "leg":    {"r": 0.115, "len": 0.52, "y": 0.44,
                   "front": (0.26, -0.42), "back": (0.28, 0.50)},
        "huf":    {"r": 0.135, "y": 0.085},
        "hip_y":  0.88,
    }


# ---------------------------------------------------------------------------
# Mesh
# ---------------------------------------------------------------------------
def build_mesh(mb, P):
    mb.begin("body")
    mb.uvsphere(P["body"]["r"], 20, 14, "fell", pos=P["body"]["pos"],
                scale=P["body"]["scale"])
    mb.end()
    mb.begin("chest")
    mb.uvsphere(P["chest"]["r"], 16, 12, "fell", pos=P["chest"]["pos"],
                scale=P["chest"]["scale"])
    mb.end()
    mb.begin("belly")
    mb.uvsphere(P["belly"]["r"], 16, 12, "fell_hell", pos=P["belly"]["pos"],
                scale=P["belly"]["scale"])
    mb.end()

    n = P["neck"]
    mb.begin("neck")
    mb.capsule(n["r"], n["len"], 12, 9, "fell", pos=n["pos"],
               pre_rot=lambda p: rot_x(p, n["tilt"]))
    mb.end()

    mb.begin("head")
    mb.uvsphere(P["head"]["r"], 20, 14, "fell", pos=P["head"]["pos"],
                scale=P["head"]["scale"])
    mb.end()
    mb.begin("muzzle")
    mb.uvsphere(P["muzzle"]["r"], 14, 10, "fell_hell", pos=P["muzzle"]["pos"],
                scale=P["muzzle"]["scale"])
    mb.end()
    mb.begin("nuestern")
    for sx in (-1, 1):
        px, py, pz = P["nuest"]["pos"]
        mb.uvsphere(P["nuest"]["r"], 8, 6, "nuestern", pos=(sx * px, py, pz),
                    scale=(1.0, 1.3, 0.6))
    mb.end()

    m = P["mouth"]
    mb.begin("mouth")
    mb.arc_band(m["R"], m["w"], math.pi + 0.55, TAU - 0.55, 12, "mund",
                pos=m["pos"],
                pre_rot=lambda p: rot_x(rot_y(p, math.pi), m["tilt"]))
    mb.end()

    for side, sx in (("L", -1), ("R", 1)):
        e = P["eye"]
        pos = (sx * e["pos"][0], e["pos"][1], e["pos"][2])
        mb.begin(f"eye{side}")
        mb.uvsphere(e["r"], 12, 9, "auge", pos=pos)
        mb.end()
        so = P["shine"]["off"]
        mb.begin(f"shine{side}")
        mb.uvsphere(P["shine"]["r"], 8, 6, "auge_glanz",
                    pos=vadd(pos, (sx * so[0], so[1], so[2])))
        mb.end()
        c = P["cheek"]
        mb.begin(f"cheek{side}")
        mb.uvsphere(c["r"], 12, 6, "wange",
                    pos=(sx * c["pos"][0], c["pos"][1], c["pos"][2]),
                    scale=(1.0, 0.85, 0.5),
                    pre_rot=lambda p, _sx=sx: rot_y(p, -_sx * c["yaw"]))
        mb.end()

    # Ohren: weiche Kegel-Lathes, außen geneigt, innen rosa
    ear = P["ear"]
    prof_out = [(0.0, 0.0), (ear["r"] * 0.88, 0.02), (ear["r"], ear["len"] * 0.35),
                (ear["r"] * 0.55, ear["len"] * 0.75), (0.0, ear["len"])]
    prof_in = [(0.0, 0.0), (ear["r"] * 0.5, 0.02), (ear["r"] * 0.55, ear["len"] * 0.32),
               (ear["r"] * 0.3, ear["len"] * 0.62), (0.0, ear["len"] * 0.80)]
    for side, sx in (("L", -1), ("R", 1)):
        base = (sx * ear["base"][0], ear["base"][1], ear["base"][2])

        def ear_rot(p, _sx=sx):
            p = rot_x(p, ear["tilt_back"])
            return rot_z(p, _sx * ear["tilt_out"])

        mb.begin(f"ear{side}")
        mb.lathe(prof_out, 10, "fell", pos=base, pre_rot=ear_rot)
        mb.lathe(prof_in, 8, "ohr_innen", pos=base,
                 pre_rot=lambda p, _sx=sx: ear_rot(
                     vadd(p, (0, 0.012, -ear["r"] * 0.42)), _sx))
        mb.end()

    # Mähne: dicke runde Tupfer entlang des Halskamms + Stirnschopf
    for i, (pos, r, scale) in enumerate(P["mane"]):
        mb.begin(f"mane{i}")
        mb.uvsphere(r, 12, 8, "maehne", pos=pos, scale=scale)
        mb.end()

    # Schweif: Blob-Kette
    for i, (pos, r) in enumerate(P["tail"]):
        mb.begin(f"tail{i}")
        mb.uvsphere(r, 10, 8, "maehne", pos=pos)
        mb.end()

    # Beine + Hufe
    leg = P["leg"]
    for name, (lx, lz) in (("FL", (-leg["front"][0], leg["front"][1])),
                           ("FR", (leg["front"][0], leg["front"][1])),
                           ("BL", (-leg["back"][0], leg["back"][1])),
                           ("BR", (leg["back"][0], leg["back"][1]))):
        mb.begin(f"leg{name}")
        mb.capsule(leg["r"], leg["len"], 10, 8, "fell", pos=(lx, leg["y"], lz))
        mb.uvsphere(P["huf"]["r"], 10, 7, "huf", pos=(lx, P["huf"]["y"], lz),
                    scale=(1.0, 0.55, 1.0))
        mb.end()


# ---------------------------------------------------------------------------
# Rig
# ---------------------------------------------------------------------------
def bones(P):
    hip = P["hip_y"]
    leg = P["leg"]
    head = P["head"]["pos"]
    ear = P["ear"]
    tail = P["tail"]
    neck = P["neck"]["pos"]
    return [
        ("root", None, (0, 0, 0), (0, hip * 0.45, 0)),
        ("body", "root", (0, hip + 0.08, P["body"]["pos"][2] + 0.35),
         (0, hip + 0.08, P["body"]["pos"][2] - 0.15)),
        ("chest", "body", (0, hip + 0.12, P["chest"]["pos"][2] + 0.28),
         (0, hip + 0.15, P["chest"]["pos"][2] - 0.1)),
        ("neck", "chest", (0, neck[1] - 0.16, neck[2] + 0.12),
         (0, head[1] - 0.06, head[2] + 0.05)),
        ("head", "neck", (0, head[1] - 0.05, head[2] + 0.04),
         (0, head[1] + P["head"]["r"], head[2] - 0.06)),
        ("ear.L", "head", (-ear["base"][0], ear["base"][1], ear["base"][2]),
         (-ear["base"][0] - 0.08, ear["base"][1] + ear["len"], ear["base"][2])),
        ("ear.R", "head", (ear["base"][0], ear["base"][1], ear["base"][2]),
         (ear["base"][0] + 0.08, ear["base"][1] + ear["len"], ear["base"][2])),
        ("tail.01", "body", tail[0][0], tail[1][0]),
        ("tail.02", "tail.01", tail[1][0], tail[2][0]),
        ("leg.FL", "chest", (-leg["front"][0], hip, leg["front"][1]),
         (-leg["front"][0], 0.04, leg["front"][1])),
        ("leg.FR", "chest", (leg["front"][0], hip, leg["front"][1]),
         (leg["front"][0], 0.04, leg["front"][1])),
        ("leg.BL", "body", (-leg["back"][0], hip, leg["back"][1]),
         (-leg["back"][0], 0.04, leg["back"][1])),
        ("leg.BR", "body", (leg["back"][0], hip, leg["back"][1]),
         (leg["back"][0], 0.04, leg["back"][1])),
    ]


def assign_weights(obj, regions, P):
    mesh = obj.data
    names = ["root", "body", "chest", "neck", "head", "ear.L", "ear.R",
             "tail.01", "tail.02", "leg.FL", "leg.FR", "leg.BL", "leg.BR"]
    groups = {n: obj.vertex_groups.new(name=n) for n in names}

    def add(vi, name, w):
        if w > 1e-4:
            groups[name].add([vi], w, "REPLACE")

    def verts(rname):
        a, b = regions[rname]
        return range(a, b)

    z_split = P["chest"]["pos"][2] + 0.32      # vor dieser Linie → chest

    for rname in ("body", "belly", "chest"):
        for vi in verts(rname):
            co = mesh.vertices[vi].co             # Blender: (x, -z, y)
            rz = -co.y
            w_chest = ss((z_split - rz) / 0.5)
            add(vi, "chest", w_chest)
            add(vi, "body", 1 - w_chest)

    neck_y0 = P["neck"]["pos"][1] - 0.20
    for vi in verts("neck"):
        co = mesh.vertices[vi].co
        ry = co.z
        t = ss((ry - neck_y0) / 0.35)
        add(vi, "neck", t)
        add(vi, "chest", 1 - t)

    for rname in ("head", "muzzle", "nuestern", "mouth",
                  "eyeL", "eyeR", "shineL", "shineR", "cheekL", "cheekR"):
        for vi in verts(rname):
            add(vi, "head", 1.0)

    for side in ("L", "R"):
        for vi in verts(f"ear{side}"):
            add(vi, f"ear.{side}", 1.0)

    # Mähne: Stirnschopf → head; Kamm-Tupfer folgen der Halskapsel mit
    # DERSELBEN Höhenformel (sonst reißen die Tupfer beim Fressen ab).
    for i in range(len(P["mane"])):
        for vi in verts(f"mane{i}"):
            if i == 0:
                add(vi, "head", 1.0)
                continue
            co = mesh.vertices[vi].co
            t = ss((co.z - neck_y0) / 0.35)
            add(vi, "neck", t)
            add(vi, "chest", 1 - t)

    tail_w = [{"tail.01": 1.0}, {"tail.01": 0.4, "tail.02": 0.6},
              {"tail.02": 1.0}]
    for i in range(len(P["tail"])):
        for vi in verts(f"tail{i}"):
            for bn, w in tail_w[i].items():
                add(vi, bn, w)

    for lname in ("FL", "FR", "BL", "BR"):
        for vi in verts(f"leg{lname}"):
            add(vi, f"leg.{lname}", 1.0)


def build_shapekey_augen_zu(obj, regions, P):
    """Shapekey 'augen_zu': Augen + Glanz vertikal zur Schlaf-Linie plätten."""
    obj.shape_key_add(name="Basis", from_mix=False)
    sk = obj.shape_key_add(name="augen_zu", from_mix=False)
    ey = P["eye"]["pos"][1] - P["eye"]["r"] * 0.35    # Lidlinie leicht unter Mitte
    for rname in ("eyeL", "eyeR", "shineL", "shineR"):
        a, b = regions[rname]
        for vi in range(a, b):
            co = obj.data.vertices[vi].co             # Blender (x, -z, y)
            ry = co.z
            new_y = ey + (ry - ey) * 0.06
            sk.data[vi].co = (co.x, co.y, new_y)
    return sk


# ---------------------------------------------------------------------------
# Animationen — Pose-Funktionen t → {(bone, prop): (x, y, z)}
# Bone-Lokalachsen (roll=0): vertikale Beine (nach unten) → rot.x schwingt
# das Bein (positiv = nach vorn/-Z), horizontale Wirbelbones → rot.x nickt.
# ---------------------------------------------------------------------------
def leg_swing(pose, amp, ph, offsets):
    for lname, off in offsets.items():
        pose[(f"leg.{lname}", "rotation_euler")] = (math.sin(ph + off) * amp, 0, 0)


def pose_idle(t):
    d = 2.8
    ph = t / d * TAU
    breathe = math.sin(ph - math.pi / 2) * 0.5 + 0.5
    return {
        ("body", "scale"): (1 + breathe * 0.018, 1 + breathe * 0.012, 1),
        ("neck", "rotation_euler"): (math.sin(ph) * 0.03, 0, 0),
        ("head", "rotation_euler"): (math.sin(ph + 0.6) * 0.04, 0,
                                     math.sin(ph * 0.5) * 0.02),
        ("tail.01", "rotation_euler"): (0, 0, math.sin(ph * 1.4) * 0.30),
        ("tail.02", "rotation_euler"): (0, 0, math.sin(ph * 1.4 + 0.8) * 0.35),
        ("ear.L", "rotation_euler"): (math.sin(ph * 0.9) * 0.10, 0, 0),
        ("ear.R", "rotation_euler"): (math.sin(ph * 0.9 + math.pi) * 0.10, 0, 0),
    }


def pose_schritt(t):
    d = 1.15
    ph = t / d * TAU
    pose = {
        ("root", "location"): (0, 0, abs(math.sin(ph * 2)) * 0.015),
        ("body", "rotation_euler"): (math.sin(ph * 2) * 0.015, 0,
                                     math.sin(ph) * 0.025),
        ("neck", "rotation_euler"): (math.sin(ph * 2 + 0.5) * 0.05, 0, 0),
        ("head", "rotation_euler"): (math.sin(ph * 2 + 1.0) * 0.06, 0, 0),
        ("tail.01", "rotation_euler"): (0, 0, math.sin(ph) * 0.22),
        ("tail.02", "rotation_euler"): (0, 0, math.sin(ph + 0.7) * 0.26),
        ("ear.L", "rotation_euler"): (math.sin(ph + 0.4) * 0.06, 0, 0),
        ("ear.R", "rotation_euler"): (math.sin(ph + 2.4) * 0.06, 0, 0),
    }
    leg_swing(pose, 0.38, ph,
              {"FL": 0.0, "BR": math.pi * 0.5, "FR": math.pi, "BL": math.pi * 1.5})
    return pose


def pose_trab(t):
    d = 0.7
    ph = t / d * TAU
    pose = {
        ("root", "location"): (0, 0, abs(math.sin(ph)) * 0.05),
        ("body", "rotation_euler"): (math.sin(ph) * 0.03, 0, 0),
        ("neck", "rotation_euler"): (math.sin(ph + 0.5) * 0.07, 0, 0),
        ("head", "rotation_euler"): (math.sin(ph + 1.0) * 0.09, 0, 0),
        ("tail.01", "rotation_euler"): (0.15, 0, math.sin(ph) * 0.18),
        ("tail.02", "rotation_euler"): (0.1, 0, math.sin(ph + 0.6) * 0.22),
    }
    leg_swing(pose, 0.55, ph, {"FL": 0.0, "BR": 0.0, "FR": math.pi, "BL": math.pi})
    return pose


def pose_galopp(t):
    d = 0.55
    ph = t / d * TAU
    pose = {
        ("root", "location"): (0, 0, max(0.0, math.sin(ph)) * 0.10),
        ("body", "rotation_euler"): (math.sin(ph + 0.3) * 0.10, 0, 0),
        ("neck", "rotation_euler"): (math.sin(ph + 0.9) * 0.13, 0, 0),
        ("head", "rotation_euler"): (math.sin(ph + 1.4) * 0.12, 0, 0),
        ("tail.01", "rotation_euler"): (0.35 + math.sin(ph) * 0.15, 0, 0),
        ("tail.02", "rotation_euler"): (0.25 + math.sin(ph + 0.5) * 0.18, 0, 0),
        ("ear.L", "rotation_euler"): (0.18, 0, 0),
        ("ear.R", "rotation_euler"): (0.18, 0, 0),
    }
    leg_swing(pose, 0.85, ph,
              {"FL": 0.0, "FR": 0.45, "BL": math.pi * 0.62, "BR": math.pi * 0.62 + 0.45})
    return pose


def pose_sprung(t):
    d = 1.0
    x = t / d
    if x < 0.22:                       # Anhocken
        k = ss(x / 0.22)
        return {
            ("root", "location"): (0, 0, -0.09 * k),
            ("body", "rotation_euler"): (-0.06 * k, 0, 0),
            ("neck", "rotation_euler"): (-0.12 * k, 0, 0),
            ("leg.BL", "rotation_euler"): (0.4 * k, 0, 0),
            ("leg.BR", "rotation_euler"): (0.4 * k, 0, 0),
            ("leg.FL", "rotation_euler"): (-0.2 * k, 0, 0),
            ("leg.FR", "rotation_euler"): (-0.2 * k, 0, 0),
        }
    if x < 0.62:                       # Flugbogen
        k = (x - 0.22) / 0.40
        h = math.sin(k * math.pi) * 0.42
        return {
            ("root", "location"): (0, 0, h),
            ("body", "rotation_euler"): (0.16 - 0.30 * k, 0, 0),
            ("neck", "rotation_euler"): (0.14, 0, 0),
            ("head", "rotation_euler"): (0.08, 0, 0),
            ("leg.FL", "rotation_euler"): (0.9 - 0.5 * k, 0, 0),
            ("leg.FR", "rotation_euler"): (0.9 - 0.5 * k, 0, 0),
            ("leg.BL", "rotation_euler"): (-0.75 + 0.3 * k, 0, 0),
            ("leg.BR", "rotation_euler"): (-0.75 + 0.3 * k, 0, 0),
            ("tail.01", "rotation_euler"): (0.5, 0, 0),
            ("tail.02", "rotation_euler"): (0.35, 0, 0),
        }
    if x < 0.82:                       # Landung
        k = ss((x - 0.62) / 0.20)
        return {
            ("root", "location"): (0, 0, (1 - k) * 0.06 - k * 0.05),
            ("body", "rotation_euler"): (-0.14 * (1 - k), 0, 0),
            ("neck", "rotation_euler"): ((1 - k) * 0.1 - 0.05 * k, 0, 0),
            ("leg.FL", "rotation_euler"): (0.25 * (1 - k), 0, 0),
            ("leg.FR", "rotation_euler"): (0.25 * (1 - k), 0, 0),
            ("leg.BL", "rotation_euler"): (-0.35 * (1 - k), 0, 0),
            ("leg.BR", "rotation_euler"): (-0.35 * (1 - k), 0, 0),
        }
    k = ss((x - 0.82) / 0.18)          # Ausfedern
    return {("root", "location"): (0, 0, -0.05 * (1 - k))}


def pose_fressen(t):
    d = 2.4
    ph = t / d * TAU
    dip = ss(min(t / 0.5, 1.0)) if t < d - 0.5 else ss((d - t) / 0.5)
    nibble = math.sin(t * TAU * 2.2) * 0.05 * dip
    return {
        ("neck", "rotation_euler"): (-0.85 * dip, 0, 0),
        ("head", "rotation_euler"): (-0.50 * dip + nibble, 0, 0),
        ("tail.01", "rotation_euler"): (0, 0, math.sin(ph) * 0.22),
        ("tail.02", "rotation_euler"): (0, 0, math.sin(ph + 0.7) * 0.28),
        ("ear.L", "rotation_euler"): (math.sin(ph * 1.7) * 0.08, 0, 0),
        ("ear.R", "rotation_euler"): (math.sin(ph * 1.7 + 2.0) * 0.08, 0, 0),
    }


def pose_kopfschuetteln(t):
    d = 0.8
    x = t / d
    damp = math.sin(x * math.pi)
    shake = math.sin(x * TAU * 3.0) * 0.42 * damp
    return {
        ("head", "rotation_euler"): (0.05 * damp, shake, shake * 0.25),
        ("neck", "rotation_euler"): (0, shake * 0.3, 0),
        ("ear.L", "rotation_euler"): (-shake * 0.5, 0, -0.1 * damp),
        ("ear.R", "rotation_euler"): (shake * 0.5, 0, 0.1 * damp),
    }


def pose_schlafen(t):
    d = 3.2
    ph = t / d * TAU
    breathe = math.sin(ph - math.pi / 2) * 0.5 + 0.5
    return {
        ("body", "scale"): (1 + breathe * 0.022, 1 + breathe * 0.015, 1),
        ("neck", "rotation_euler"): (-0.55, 0, 0),
        ("head", "rotation_euler"): (-0.35 + breathe * 0.02, 0, 0),
        ("ear.L", "rotation_euler"): (0.12, 0, -0.22),
        ("ear.R", "rotation_euler"): (0.12, 0, 0.22),
        ("tail.01", "rotation_euler"): (0, 0, math.sin(ph * 0.5) * 0.06),
    }


def pose_blinzeln(_t):
    return {}


CLIPS = [
    ("idle", 2.8, True, pose_idle),
    ("schritt", 1.15, True, pose_schritt),
    ("trab", 0.7, True, pose_trab),
    ("galopp", 0.55, True, pose_galopp),
    ("sprung", 1.0, False, pose_sprung),
    ("fressen", 2.4, True, pose_fressen),
    ("kopfschuetteln", 0.8, False, pose_kopfschuetteln),
    ("schlafen", 3.2, True, pose_schlafen),
    ("blinzeln", 0.3, False, pose_blinzeln),
]


# Shapekey-Kurve "augen_zu" je Clip: t → Wert 0..1
def sk_value(clip, t, duration):
    if clip == "schlafen":
        return 1.0 if t > 0.45 else ss(t / 0.45)
    if clip == "blinzeln":
        x = t / duration
        return ss(min(x / 0.35, 1.0)) * ss(min((1 - x) / 0.35, 1.0)) * 1.0
    return 0.0


def bake_shapekey_track(obj, clip, duration, loop):
    """Shapekey-Action mit demselben NLA-Track-Namen wie der Bone-Clip —
    der glTF-Export fasst gleichnamige Tracks zu EINER Animation zusammen."""
    shape_keys = obj.data.shape_keys
    if shape_keys.animation_data is None:
        shape_keys.animation_data_create()
    track_name = f"{clip}-loop" if loop else clip
    action = bpy.data.actions.new(track_name + "_sk")
    action.use_fake_user = True
    shape_keys.animation_data.action = action
    kb = shape_keys.key_blocks["augen_zu"]
    frames = max(2, int(round(duration * ANIM_FPS)))
    for fi in range(frames + 1):
        t = duration * fi / frames
        kb.value = sk_value(clip, t, duration)
        kb.keyframe_insert("value", frame=fi)
    track = shape_keys.animation_data.nla_tracks.new()
    track.name = track_name
    strip = track.strips.new(track_name, 0, action)
    strip.name = track_name
    shape_keys.animation_data.action = None
    kb.value = 0.0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--variante", default="pferd", choices=["pferd", "fohlen"])
    args = ap.parse_args(argv)

    P = params(args.variante)
    new_scene()

    mb = MeshBuilder()
    build_mesh(mb, P)
    name = "RanchPferd" if args.variante == "pferd" else "RanchFohlen"
    obj = build_object(name, mb)

    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"[build_pferd] {args.variante}: verts={len(mb.verts)} tris={tris}")
    if tris > 8000:
        raise SystemExit(f"FEHLER: Tri-Budget überschritten: {tris}")

    arm = build_armature(name, bones(P))
    attach(obj, arm)
    assign_weights(obj, mb.regions, P)
    build_shapekey_augen_zu(obj, mb.regions, P)

    for clip, dur, loop, fn in CLIPS:
        bake_clip(arm, clip, dur, loop, fn)
        bake_shapekey_track(obj, clip, dur, loop)

    export_glb(args.out)


if __name__ == "__main__":
    main()
