# build_tier.py — Die Gooby-Ranch-Nachbarschaftstiere (Reh, Fuchs, Ente,
# Katze) in derselben Formensprache wie Gooby und das Ranch-Pferd: rund,
# pastellig, große Glanzaugen, dicke rosa Wangen. Kleines Rig (root/body/
# head/ears/tail/legs) mit idle- und schritt-Loop.
# Vertrag wie das Pferd: Boden y=0, Blick -Z, Meter.
#
# Aufruf:
#   blender --background --factory-startup --python build_tier.py -- \
#       --tier reh|fuchs|ente|katze --out tier.glb
import argparse
import math
import os
import sys

import bpy  # noqa: F401

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ranch_stil import (  # noqa: E402
    TAU, MeshBuilder, attach, bake_clip, build_armature, build_object,
    export_glb, new_scene, rot_x, rot_y, rot_z, ss, vadd,
)


# ---------------------------------------------------------------------------
# Tier-Definitionen (Rezept-Raum, Meter). Palette-Zellen wie ranch_stil:
# fell/fell_hell/maehne(=Zweitfarbe)/huf(=Pfoten)/wange/auge/auge_glanz/
# nuestern(=Nase)/mund/ohr_innen/weiss/akzent.
# ---------------------------------------------------------------------------
def tier_params(tier):
    if tier == "reh":
        return {
            "farben": {"fell": "#D9B08C", "fell_hell": "#F4E6D0",
                       "maehne": "#B98A5E", "huf": "#6B5A52",
                       "nuestern": "#4A3A35"},
            "body": {"r": 0.30, "scale": (0.95, 0.92, 1.30), "pos": (0, 0.56, 0.03)},
            "belly": {"r": 0.26, "scale": (0.9, 0.75, 1.05), "pos": (0, 0.46, 0.05)},
            "head": {"r": 0.23, "scale": (1.0, 0.97, 1.0), "pos": (0, 0.94, -0.34)},
            "muzzle": {"r": 0.115, "scale": (1.05, 0.75, 1.0), "pos": (0, 0.87, -0.50)},
            "nase": {"r": 0.030, "pos": (0, 0.905, -0.615)},
            "mouth": {"R": 0.034, "w": 0.011, "pos": (0, 0.845, -0.605)},
            "eye": {"r": 0.075, "pos": (0.115, 1.005, -0.50)},
            "shine": {"r": 0.026, "off": (0.016, 0.022, -0.040)},
            "cheek": {"r": 0.075, "pos": (0.175, 0.90, -0.44), "yaw": 0.85},
            "ohren": {"art": "oval", "base": (0.135, 1.13, -0.28), "r": 0.085,
                      "len": 0.20, "tilt_out": 0.55, "tilt_back": 0.10},
            "schwanz": [((0, 0.62, 0.44), 0.075, "weiss")],
            "extras": "rehflecken",
            "beine": {"r": 0.062, "len": 0.24, "y": 0.26,
                      "front": (0.14, -0.20), "back": (0.15, 0.22),
                      "pfote": ("huf", 0.070, 0.05)},
            "hip_y": 0.40,
        }
    if tier == "fuchs":
        return {
            "farben": {"fell": "#E8925A", "fell_hell": "#FBF3E4",
                       "maehne": "#E8925A", "huf": "#5C4638",
                       "nuestern": "#4A3A35", "ohr_innen": "#F6C8B8"},
            "body": {"r": 0.28, "scale": (0.95, 0.9, 1.25), "pos": (0, 0.42, 0.02)},
            "belly": {"r": 0.24, "scale": (0.9, 0.78, 1.0), "pos": (0, 0.34, -0.08)},
            "head": {"r": 0.22, "scale": (1.05, 0.95, 1.0), "pos": (0, 0.76, -0.30)},
            "muzzle": {"r": 0.105, "scale": (1.0, 0.72, 1.05), "pos": (0, 0.69, -0.46)},
            "nase": {"r": 0.032, "pos": (0, 0.715, -0.565)},
            "mouth": {"R": 0.032, "w": 0.010, "pos": (0, 0.655, -0.545)},
            "eye": {"r": 0.070, "pos": (0.11, 0.825, -0.45)},
            "shine": {"r": 0.024, "off": (0.015, 0.021, -0.038)},
            "cheek": {"r": 0.072, "pos": (0.175, 0.72, -0.38), "yaw": 0.85},
            "ohren": {"art": "spitz", "base": (0.125, 0.93, -0.26), "r": 0.075,
                      "len": 0.20, "tilt_out": 0.35, "tilt_back": 0.08},
            "schwanz": [((0, 0.42, 0.38), 0.115, "fell"),
                        ((0, 0.47, 0.55), 0.105, "fell"),
                        ((0, 0.54, 0.68), 0.085, "weiss")],
            "extras": None,
            "beine": {"r": 0.060, "len": 0.14, "y": 0.19,
                      "front": (0.13, -0.16), "back": (0.14, 0.18),
                      "pfote": ("huf", 0.068, 0.045)},
            "hip_y": 0.30,
        }
    if tier == "katze":
        return {
            "farben": {"fell": "#B9A8C9", "fell_hell": "#F2EAF6",
                       "maehne": "#8F7BA6", "huf": "#8F7BA6",
                       "nuestern": "#E88BA0"},
            "body": {"r": 0.26, "scale": (0.95, 0.92, 1.18), "pos": (0, 0.38, 0.02)},
            "belly": {"r": 0.22, "scale": (0.9, 0.78, 1.0), "pos": (0, 0.30, -0.05)},
            "head": {"r": 0.21, "scale": (1.08, 0.95, 1.0), "pos": (0, 0.70, -0.26)},
            "muzzle": {"r": 0.095, "scale": (1.15, 0.68, 0.95), "pos": (0, 0.63, -0.40)},
            "nase": {"r": 0.024, "pos": (0, 0.665, -0.495)},
            "mouth": {"R": 0.030, "w": 0.010, "pos": (0, 0.605, -0.475)},
            "eye": {"r": 0.068, "pos": (0.105, 0.765, -0.40)},
            "shine": {"r": 0.024, "off": (0.014, 0.020, -0.036)},
            "cheek": {"r": 0.068, "pos": (0.165, 0.655, -0.335), "yaw": 0.85},
            "ohren": {"art": "spitz", "base": (0.115, 0.87, -0.22), "r": 0.070,
                      "len": 0.17, "tilt_out": 0.38, "tilt_back": 0.06},
            "schwanz": [((0, 0.42, 0.32), 0.062, "fell"),
                        ((0, 0.50, 0.40), 0.058, "fell"),
                        ((0, 0.585, 0.445), 0.050, "maehne")],
            "extras": None,
            "beine": {"r": 0.055, "len": 0.12, "y": 0.17,
                      "front": (0.12, -0.14), "back": (0.13, 0.16),
                      "pfote": ("fell_hell", 0.062, 0.042)},
            "hip_y": 0.27,
        }
    # Ente
    return {
        "farben": {"fell": "#FBF0D8", "fell_hell": "#FFFDF4",
                   "maehne": "#F2B24C", "huf": "#F2B24C",
                   "nuestern": "#E8963C"},
        "body": {"r": 0.24, "scale": (0.95, 0.85, 1.20), "pos": (0, 0.30, 0.03)},
        "belly": {"r": 0.20, "scale": (0.9, 0.72, 1.0), "pos": (0, 0.24, 0.0)},
        "head": {"r": 0.17, "scale": (1.0, 1.0, 1.0), "pos": (0, 0.62, -0.19)},
        "muzzle": None,
        "nase": None,
        "mouth": None,
        "eye": {"r": 0.058, "pos": (0.085, 0.665, -0.30)},
        "shine": {"r": 0.020, "off": (0.012, 0.018, -0.030)},
        "cheek": {"r": 0.058, "pos": (0.135, 0.575, -0.25), "yaw": 0.85},
        "ohren": None,
        "schwanz": [((0, 0.36, 0.28), 0.075, "fell")],
        "extras": "ente",
        "beine": {"r": 0.028, "len": 0.10, "y": 0.11,
                  "front": (0.085, 0.02), "back": None,
                  "pfote": ("huf", 0.0, 0.0)},
        "hip_y": 0.20,
    }


# ---------------------------------------------------------------------------
# Mesh
# ---------------------------------------------------------------------------
def build_mesh(mb, P):
    mb.begin("body")
    mb.uvsphere(P["body"]["r"], 18, 13, "fell", pos=P["body"]["pos"],
                scale=P["body"]["scale"])
    mb.end()
    mb.begin("belly")
    mb.uvsphere(P["belly"]["r"], 14, 10, "fell_hell", pos=P["belly"]["pos"],
                scale=P["belly"]["scale"])
    mb.end()
    mb.begin("head")
    mb.uvsphere(P["head"]["r"], 18, 13, "fell", pos=P["head"]["pos"],
                scale=P["head"]["scale"])
    mb.end()

    if P["muzzle"]:
        mb.begin("muzzle")
        mb.uvsphere(P["muzzle"]["r"], 12, 9, "fell_hell", pos=P["muzzle"]["pos"],
                    scale=P["muzzle"]["scale"])
        mb.end()
    if P["nase"]:
        mb.begin("nase")
        mb.uvsphere(P["nase"]["r"], 8, 6, "nuestern", pos=P["nase"]["pos"],
                    scale=(1.2, 0.85, 0.7))
        mb.end()
    if P["mouth"]:
        m = P["mouth"]
        mb.begin("mouth")
        mb.arc_band(m["R"], m["w"], math.pi + 0.55, TAU - 0.55, 10, "mund",
                    pos=m["pos"], pre_rot=lambda p: rot_x(rot_y(p, math.pi), -0.3))
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
        mb.uvsphere(c["r"], 10, 6, "wange",
                    pos=(sx * c["pos"][0], c["pos"][1], c["pos"][2]),
                    scale=(1.0, 0.85, 0.5),
                    pre_rot=lambda p, _sx=sx: rot_y(p, -_sx * c["yaw"]))
        mb.end()

    if P["ohren"]:
        ear = P["ohren"]
        if ear["art"] == "oval":
            prof_out = [(0.0, 0.0), (ear["r"], 0.03), (ear["r"] * 0.95, ear["len"] * 0.55),
                        (ear["r"] * 0.5, ear["len"] * 0.85), (0.0, ear["len"])]
            prof_in = [(0.0, 0.0), (ear["r"] * 0.55, 0.03),
                       (ear["r"] * 0.5, ear["len"] * 0.5),
                       (ear["r"] * 0.28, ear["len"] * 0.7), (0.0, ear["len"] * 0.8)]
        else:
            prof_out = [(0.0, 0.0), (ear["r"] * 0.9, 0.02), (ear["r"], ear["len"] * 0.3),
                        (ear["r"] * 0.5, ear["len"] * 0.7), (0.0, ear["len"])]
            prof_in = [(0.0, 0.0), (ear["r"] * 0.5, 0.02),
                       (ear["r"] * 0.55, ear["len"] * 0.28),
                       (ear["r"] * 0.28, ear["len"] * 0.6), (0.0, ear["len"] * 0.78)]
        for side, sx in (("L", -1), ("R", 1)):
            base = (sx * ear["base"][0], ear["base"][1], ear["base"][2])

            def ear_rot(p, _sx=sx):
                p = rot_x(p, ear["tilt_back"])
                return rot_z(p, _sx * ear["tilt_out"])

            mb.begin(f"ear{side}")
            mb.lathe(prof_out, 9, "fell", pos=base, pre_rot=ear_rot)
            mb.lathe(prof_in, 7, "ohr_innen", pos=base,
                     pre_rot=lambda p, _sx=sx: ear_rot(
                         vadd(p, (0, 0.010, -ear["r"] * 0.40)), _sx))
            mb.end()

    for i, (pos, r, part) in enumerate(P["schwanz"]):
        mb.begin(f"tail{i}")
        mb.uvsphere(r, 10, 8, part, pos=pos)
        mb.end()

    if P["extras"] == "rehflecken":
        # Bambi-Flecken: exakt auf der Rücken-Ellipsoid-Oberfläche platziert
        mb.begin("flecken")
        bp = P["body"]["pos"]
        rx = P["body"]["r"] * P["body"]["scale"][0]
        ry = P["body"]["r"] * P["body"]["scale"][1]
        rz = P["body"]["r"] * P["body"]["scale"][2]
        for (fx, fz) in ((-0.12, 0.10), (0.13, 0.02), (-0.05, 0.28),
                         (0.10, 0.30), (-0.15, -0.10), (0.05, -0.16)):
            k = 1.0 - (fx / rx) ** 2 - ((fz - bp[2]) / rz) ** 2
            fy = bp[1] + ry * math.sqrt(max(0.05, k)) - 0.004
            mb.uvsphere(0.030, 6, 4, "weiss", pos=(fx, fy, fz),
                        scale=(1.0, 0.25, 1.0))
        mb.end()
    if P["extras"] == "ente":
        # Schnabel: zwei flache Ovale
        mb.begin("schnabel")
        mb.uvsphere(0.075, 12, 8, "nuestern", pos=(0, 0.585, -0.335),
                    scale=(1.05, 0.35, 1.25))
        mb.uvsphere(0.058, 10, 7, "nuestern", pos=(0, 0.552, -0.315),
                    scale=(0.95, 0.30, 1.05))
        mb.end()
        # Flügelchen: flache Ovale an den Seiten
        mb.begin("fluegel")
        for sx in (-1, 1):
            mb.uvsphere(0.115, 12, 8, "fell",
                        pos=(sx * 0.21, 0.32, 0.05),
                        scale=(0.35, 0.75, 1.0),
                        pre_rot=lambda p, _sx=sx: rot_z(p, _sx * 0.25))
        mb.end()
        # Kopftuft
        mb.begin("tuft")
        mb.uvsphere(0.045, 8, 6, "maehne", pos=(0, 0.79, -0.19))
        mb.end()

    # Beine + Pfoten/Füße
    leg = P["beine"]
    paare = [("FL", (-leg["front"][0], leg["front"][1])),
             ("FR", (leg["front"][0], leg["front"][1]))]
    if leg["back"]:
        paare += [("BL", (-leg["back"][0], leg["back"][1])),
                  ("BR", (leg["back"][0], leg["back"][1]))]
    part_pfote, r_pfote, y_pfote = leg["pfote"]
    for name, (lx, lz) in paare:
        mb.begin(f"leg{name}")
        mb.capsule(leg["r"], leg["len"], 9, 7, "fell" if P["extras"] != "ente" else "huf",
                   pos=(lx, leg["y"], lz))
        if r_pfote > 0:
            mb.uvsphere(r_pfote, 9, 6, part_pfote, pos=(lx, y_pfote, lz),
                        scale=(1.0, 0.6, 1.1))
        mb.end()
    if P["extras"] == "ente":
        # Schwimmfüße: flache Ovale vor den Beinen
        mb.begin("fuesse")
        for sx in (-1, 1):
            mb.uvsphere(0.065, 10, 6, "huf",
                        pos=(sx * leg["front"][0], 0.022, leg["front"][1] - 0.03),
                        scale=(1.0, 0.28, 1.5))
        mb.end()


# ---------------------------------------------------------------------------
# Rig
# ---------------------------------------------------------------------------
def bones(P):
    hip = P["hip_y"]
    head = P["head"]["pos"]
    leg = P["beine"]
    out = [
        ("root", None, (0, 0, 0), (0, max(hip * 0.5, 0.1), 0)),
        ("body", "root", (0, hip + 0.05, P["body"]["pos"][2] + 0.2),
         (0, hip + 0.05, P["body"]["pos"][2] - 0.15)),
        ("head", "body", (0, head[1] - P["head"]["r"] * 0.7, head[2] + 0.10),
         (0, head[1] + P["head"]["r"], head[2] + 0.02)),
    ]
    if P["ohren"]:
        eb = P["ohren"]["base"]
        elen = P["ohren"]["len"]
        out += [
            ("ear.L", "head", (-eb[0], eb[1], eb[2]), (-eb[0] - 0.05, eb[1] + elen, eb[2])),
            ("ear.R", "head", (eb[0], eb[1], eb[2]), (eb[0] + 0.05, eb[1] + elen, eb[2])),
        ]
    tail = P["schwanz"]
    t0 = tail[0][0]
    t_end = tail[-1][0]
    out.append(("tail", "body", t0, (t_end[0], t_end[1] + 0.02, t_end[2] + 0.08)))
    paare = [("FL", (-leg["front"][0], leg["front"][1])),
             ("FR", (leg["front"][0], leg["front"][1]))]
    if leg["back"]:
        paare += [("BL", (-leg["back"][0], leg["back"][1])),
                  ("BR", (leg["back"][0], leg["back"][1]))]
    for name, (lx, lz) in paare:
        out.append((f"leg.{name}", "body", (lx, P["hip_y"], lz), (lx, 0.02, lz)))
    return out


def assign_weights(obj, regions, P, bone_list):
    names = [b[0] for b in bone_list]
    groups = {n: obj.vertex_groups.new(name=n) for n in names}

    def add(vi, name, w):
        if w > 1e-4 and name in groups:
            groups[name].add([vi], w, "REPLACE")

    def verts(rname):
        if rname not in regions:
            return []
        a, b = regions[rname]
        return range(a, b)

    head_y0 = P["head"]["pos"][1] - P["head"]["r"] - 0.05
    for rname in ("body", "belly", "flecken", "fluegel"):
        for vi in verts(rname):
            add(vi, "body", 1.0)
    for rname in ("head", "muzzle", "nase", "mouth", "eyeL", "eyeR",
                  "shineL", "shineR", "cheekL", "cheekR", "schnabel", "tuft"):
        for vi in verts(rname):
            add(vi, "head", 1.0)
    for side in ("L", "R"):
        for vi in verts(f"ear{side}"):
            add(vi, f"ear.{side}", 1.0)
    for i in range(len(P["schwanz"])):
        for vi in verts(f"tail{i}"):
            add(vi, "tail", 1.0)
    for lname in ("FL", "FR", "BL", "BR"):
        for vi in verts(f"leg{lname}"):
            add(vi, f"leg.{lname}", 1.0)
    for vi in verts("fuesse"):
        co = obj.data.vertices[vi].co
        add(vi, "leg.FL" if co.x < 0 else "leg.FR", 1.0)
    # weicher Hals-Übergang: Body-Verts nahe Kopfunterkante leicht mitnehmen
    for vi in verts("body"):
        co = obj.data.vertices[vi].co
        t = ss((co.z - head_y0) / 0.15) * 0.5
        if t > 0:
            add(vi, "head", t)
            add(vi, "body", 1 - t)


# ---------------------------------------------------------------------------
# Animationen
# ---------------------------------------------------------------------------
def make_pose_idle(P, ente):
    d = 2.6

    def pose(t):
        ph = t / d * TAU
        breathe = math.sin(ph - math.pi / 2) * 0.5 + 0.5
        out = {
            ("body", "scale"): (1 + breathe * 0.02, 1 + breathe * 0.015, 1),
            ("head", "rotation_euler"): (math.sin(ph + 0.6) * 0.04, 0,
                                         math.sin(ph * 0.5) * 0.03),
            ("tail", "rotation_euler"): (0, math.sin(ph * 1.5) * 0.25, 0)
            if not ente else (math.sin(ph * 1.5) * 0.2, 0, 0),
        }
        if P["ohren"]:
            out[("ear.L", "rotation_euler")] = (math.sin(ph * 0.9) * 0.09, 0, 0)
            out[("ear.R", "rotation_euler")] = (math.sin(ph * 0.9 + math.pi) * 0.09, 0, 0)
        return out

    return d, pose


def make_pose_schritt(P, ente):
    d = 0.9 if not ente else 0.7

    def pose(t):
        ph = t / d * TAU
        out = {
            ("root", "location"): (0, 0, abs(math.sin(ph)) * 0.012),
            ("body", "rotation_euler"): (math.sin(ph * 2) * 0.02, 0,
                                         math.sin(ph) * (0.10 if ente else 0.03)),
            ("head", "rotation_euler"): (math.sin(ph * 2 + 1.0) * 0.05, 0, 0),
            ("tail", "rotation_euler"): (0, math.sin(ph) * 0.2, 0),
        }
        amp = 0.5 if not ente else 0.6
        offsets = {"FL": 0.0, "BR": math.pi * 0.5, "FR": math.pi,
                   "BL": math.pi * 1.5} if P["beine"]["back"] else \
                  {"FL": 0.0, "FR": math.pi}
        for lname, off in offsets.items():
            out[(f"leg.{lname}", "rotation_euler")] = (math.sin(ph + off) * amp, 0, 0)
        return out

    return d, pose


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", required=True,
                    choices=["reh", "fuchs", "ente", "katze"])
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    P = tier_params(args.tier)
    new_scene()
    mb = MeshBuilder()
    build_mesh(mb, P)
    name = "Ranch" + args.tier.capitalize()
    obj = build_object(name, mb, palette_farben=P["farben"])

    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"[build_tier] {args.tier}: verts={len(mb.verts)} tris={tris}")
    if tris > 6000:
        raise SystemExit(f"FEHLER: Tri-Budget überschritten: {tris}")

    bone_list = bones(P)
    arm = build_armature(name, bone_list)
    attach(obj, arm)
    assign_weights(obj, mb.regions, P, bone_list)

    ente = args.tier == "ente"
    d, fn = make_pose_idle(P, ente)
    bake_clip(arm, "idle", d, True, fn)
    d, fn = make_pose_schritt(P, ente)
    bake_clip(arm, "schritt", d, True, fn)

    export_glb(args.out)


if __name__ == "__main__":
    main()
