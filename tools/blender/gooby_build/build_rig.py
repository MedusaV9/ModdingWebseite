# build_rig.py — Stage 2: Armature (21 Bones), deterministisches Skinning
# (Part-basierte Gewichte, weiche Übergänge am Körper/Ohransatz) und die
# 14 Shapekeys (8 Emotionen + blink + mouth_open + body_squeeze_door +
# Editor-Morphs eye_width/eye_size/ear_length).
#
# Aufruf:
#   blender --background --factory-startup --python build_rig.py -- \
#       --in /tmp/gooby_build/stage1_mesh.blend \
#       --out /tmp/gooby_build/stage2_rig.blend

import json
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gooby_params as P  # noqa: E402


def ss(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------
# Armature
# ---------------------------------------------------------------------------
def build_armature():
    arm_data = bpy.data.armatures.new("GoobyArmatureData")
    arm_obj = bpy.data.objects.new("GoobyArmature", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    ebones = {}
    for name, parent, head, tail in P.BONES:
        eb = arm_data.edit_bones.new(name)
        eb.head = P.to_blender(head)
        eb.tail = P.to_blender(tail)
        eb.roll = 0.0
        if parent:
            eb.parent = ebones[parent]
            eb.use_connect = False
        ebones[name] = eb
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


# ---------------------------------------------------------------------------
# Skinning: Part-Ranges → Bone-Gewichte
# ---------------------------------------------------------------------------
def recipe_y(v_co):
    """Blender-z zurück in Rezept-Höhe."""
    return v_co.z / P.RIG_SCALE


def assign_weights(obj, regions):
    mesh = obj.data
    bone_names = [b[0] for b in P.BONES]
    groups = {n: obj.vertex_groups.new(name=n) for n in bone_names}

    def add(vi, name, w):
        if w > 1e-4:
            groups[name].add([vi], w, "REPLACE")

    def region_verts(rname):
        a, b = regions[rname]
        return range(a, b)

    # Körper + Bauch: Höhenband-Blend hips → spine → chest
    for rname in ("body", "belly"):
        for vi in region_verts(rname):
            y = recipe_y(mesh.vertices[vi].co)
            t_sp = ss((y - 0.28) / 0.26)     # hips→spine 0.28..0.54
            t_ch = ss((y - 0.56) / 0.16)     # spine→chest 0.56..0.72
            w_ch = t_ch
            w_sp = t_sp * (1 - t_ch)
            w_hip = 1 - t_sp
            add(vi, "hips", w_hip)
            add(vi, "spine", w_sp)
            add(vi, "chest", w_ch)

    for vi in region_verts("tail"):
        add(vi, "tail", 1.0)

    # Kopf + Gesicht → head (Mund-Decals → jaw für spätere Lipsync-Poses)
    # FIX2: Hals-Blendband folgt der Kopf-Unterkante (Proportionen abgeleitet)
    neck0 = P.HEAD_BOTTOM_Y + 0.04
    for rname in ("head", "nose", "teeth", "cheekL", "cheekR"):
        for vi in region_verts(rname):
            y = recipe_y(mesh.vertices[vi].co)
            # weicher Hals-Übergang unten am Kopf
            t = ss((y - neck0) / 0.12)
            add(vi, "head", t)
            add(vi, "chest", 1 - t)
    for rname in ("mouth_smile", "mouth_frown", "mouth_flat", "mouth_open"):
        for vi in region_verts(rname):
            add(vi, "jaw", 1.0)

    # Augen
    for side in ("L", "R"):
        for rname in (f"eye{side}", f"eyeShine{side}"):
            for vi in region_verts(rname):
                add(vi, f"eye.{side}", 1.0)

    # Ohren: Blend entlang der Ohrhöhe (Pivot … Spitze, aus den Params)
    ear_base = P.EAR_BASE_Y
    ear_tip = P.EAR_TIP_RECIPE + 0.01
    for side in ("L", "R"):
        for rname in (f"ear{side}_outer", f"ear{side}_inner"):
            for vi in region_verts(rname):
                y = recipe_y(mesh.vertices[vi].co)
                t = ss((y - ear_base) / (ear_tip - ear_base) * 2.0 - 0.35)
                base_blend = ss((y - (ear_base - 0.06)) / 0.10)
                w01 = (1 - t) * base_blend
                w02 = t * base_blend
                add(vi, f"ear.{side}.01", w01)
                add(vi, f"ear.{side}.02", w02)
                add(vi, "head", 1 - base_blend)

    # Ärmchen / Füßchen
    for side in ("L", "R"):
        for vi in region_verts(f"arm{side}"):
            add(vi, f"arm.{side}", 1.0)
        for rname in (f"foot{side}", f"pad{side}"):
            for vi in region_verts(rname):
                add(vi, f"foot.{side}", 1.0)


# ---------------------------------------------------------------------------
# Shapekeys
# ---------------------------------------------------------------------------
class KeyBuilder:
    """Hilfsklasse: Basis-Koordinaten + Regionen → Shapekey-Verschiebungen."""

    def __init__(self, obj, regions):
        self.obj = obj
        self.mesh = obj.data
        self.regions = regions
        self.basis = [v.co.copy() for v in self.mesh.vertices]
        s = P.RIG_SCALE
        self.eye_center = {}
        for side, sx in (("L", -1), ("R", 1)):
            c = P.face_local_to_recipe(sx * P.EYE["pos"][0], P.EYE["pos"][1],
                                       P.EYE["pos"][2])
            self.eye_center[side] = P.to_blender(c)
        cz = P.face_surface_z(0.0, P.MOUTH["y"], P.MOUTH["push"])
        self.mouth_center = P.to_blender(
            P.face_local_to_recipe(0.0, P.MOUTH["y"], cz))
        self.cheek_center = {}
        for side, sx in (("L", -1), ("R", 1)):
            ccz = P.face_surface_z(sx * P.CHEEK["x"], P.CHEEK["y"], P.CHEEK["push"])
            self.cheek_center[side] = P.to_blender(
                P.face_local_to_recipe(sx * P.CHEEK["x"], P.CHEEK["y"], ccz))
        self.ear_pivot_z = P.EAR_BASE_Y * s
        self.ear_tip_z = (P.EAR_TIP_RECIPE + 0.01) * s
        self.sunk_out = (P.MOUTH["sunk_depth"] + 0.012) * s   # Decal-Ausfahrweg

    def new_key(self, name):
        sk = self.obj.shape_key_add(name=name, from_mix=False)
        sk.slider_min = -1.0
        sk.slider_max = 1.0
        return sk

    def verts(self, rname):
        a, b = self.regions[rname]
        return range(a, b)

    # --- Effekte ------------------------------------------------------------
    def scale_region(self, sk, rname, factors, center):
        fx, fy, fz = factors
        cx, cy, cz = center
        for vi in self.verts(rname):
            b = self.basis[vi]
            sk.data[vi].co = (cx + (b.x - cx) * fx,
                              cy + (b.y - cy) * fy,
                              cz + (b.z - cz) * fz)

    def translate_region(self, sk, rname, delta):
        dx, dy, dz = delta
        for vi in self.verts(rname):
            c = sk.data[vi].co
            sk.data[vi].co = (c[0] + dx, c[1] + dy, c[2] + dz)

    def lids(self, sk, k):
        """Augen zu k geschlossen: vertikaler Squash + leicht absenken."""
        for side in ("L", "R"):
            c = self.eye_center[side]
            fz = 1.0 - 0.90 * k
            drop = -0.012 * k * P.RIG_SCALE
            for rname in (f"eye{side}", f"eyeShine{side}"):
                for vi in self.verts(rname):
                    b = self.basis[vi]
                    sk.data[vi].co = (b.x, b.y, c[2] + (b.z - c[2]) * fz + drop)

    def eye_scale(self, sk, f):
        for side in ("L", "R"):
            c = self.eye_center[side]
            for rname in (f"eye{side}", f"eyeShine{side}"):
                self.scale_region(sk, rname, (f, f, f), c)

    def mouth_show(self, sk, which):
        """Verstecktes Mund-Decal herausfahren (recipe +z = blender −y)."""
        self.translate_region(sk, f"mouth_{which}", (0.0, -self.sunk_out, 0.0))

    def mouth_hide_smile(self, sk):
        self.translate_region(sk, "mouth_smile", (0.0, self.sunk_out, 0.0))

    def smile_scale(self, sk, f):
        self.scale_region(sk, "mouth_smile", (f, f, f), self.mouth_center)

    def cheeks_scale(self, sk, f):
        for side in ("L", "R"):
            self.scale_region(sk, f"cheek{side}", (f, f, f),
                              self.cheek_center[side])


def build_shapekeys(obj, regions):
    obj.shape_key_add(name="Basis", from_mix=False)
    kb = KeyBuilder(obj, regions)
    s = P.RIG_SCALE

    # --- 8 Emotionen ---------------------------------------------------------
    for emo in ("neutral", "happy", "sad", "sleepy", "ecstatic", "angry",
                "scared", "dizzy"):
        mouth, lids, smile, cheek, eye_f, _slant = P.EMOTIONS[emo]
        sk = kb.new_key(f"emotion_{emo}")
        if mouth == "smile":
            kb.smile_scale(sk, max(smile, 0.01))
        else:
            kb.mouth_hide_smile(sk)
            kb.mouth_show(sk, mouth)
        if lids > 0:
            kb.lids(sk, lids)
        if abs(cheek - 1.0) > 1e-3:
            kb.cheeks_scale(sk, cheek)
        if abs(eye_f - 1.0) > 1e-3 and lids <= 0:
            kb.eye_scale(sk, eye_f)

    # --- blink ---------------------------------------------------------------
    sk = kb.new_key("blink")
    kb.lids(sk, 1.0)

    # --- mouth_open ----------------------------------------------------------
    sk = kb.new_key("mouth_open")
    kb.mouth_hide_smile(sk)
    kb.mouth_show(sk, "open")

    # --- body_squeeze_door (Tür-Steckenbleib-Deform) ---------------------------
    sk = kb.new_key("body_squeeze_door")
    squeeze = {
        "body": (0.45, 0.18), "belly": (0.45, 0.18), "head": (0.42, 0.16),
        "nose": (0.42, 0.0), "cheekL": (0.42, 0.0), "cheekR": (0.42, 0.0),
        "teeth": (0.42, 0.0), "mouth_smile": (0.42, 0.0),
        "mouth_frown": (0.42, 0.0), "mouth_flat": (0.42, 0.0),
        "mouth_open": (0.42, 0.0),
        "eyeL": (0.42, 0.0), "eyeR": (0.42, 0.0),
        "eyeShineL": (0.42, 0.0), "eyeShineR": (0.42, 0.0),
        "earL_outer": (0.28, 0.0), "earL_inner": (0.28, 0.0),
        "earR_outer": (0.28, 0.0), "earR_inner": (0.28, 0.0),
        "armL": (0.62, 0.0), "armR": (0.62, 0.0),
        "footL": (0.30, 0.0), "footR": (0.30, 0.0),
        "padL": (0.30, 0.0), "padR": (0.30, 0.0),
        "tail": (0.20, 0.10),
    }
    for rname, (fx, fy) in squeeze.items():
        for vi in kb.verts(rname):
            b = kb.basis[vi]
            sk.data[vi].co = (b.x * (1.0 - fx), b.y * (1.0 + fy), b.z)

    # --- Editor-Morphs ---------------------------------------------------------
    sk = kb.new_key("eye_width")     # +1 = Augen weiter auseinander
    for side, sx in (("L", -1), ("R", 1)):
        for rname in (f"eye{side}", f"eyeShine{side}"):
            kb.translate_region(sk, rname, (sx * 0.024 * s, 0.0, 0.0))

    sk = kb.new_key("eye_size")      # +1 = 35 % größere Knopfaugen
    kb.eye_scale(sk, 1.35)

    sk = kb.new_key("ear_length")    # +1 = 25 % längere Schlappohren
    span = kb.ear_tip_z - kb.ear_pivot_z
    for side in ("L", "R"):
        for rname in (f"ear{side}_outer", f"ear{side}_inner"):
            for vi in kb.verts(rname):
                b = kb.basis[vi]
                t = max(0.0, (b.z - kb.ear_pivot_z) / span)
                stretch = t * 0.25 * span
                # Spitze folgt der Auswärts-Lehne
                lean = P.EAR_LEAN if side == "R" else -P.EAR_LEAN
                sk.data[vi].co = (b.x + lean * stretch * 0.4, b.y,
                                  b.z + stretch)

    names = [k.name for k in obj.data.shape_keys.key_blocks][1:]
    assert names == P.SHAPEKEYS, f"Shapekey-Reihenfolge falsch: {names}"
    print(f"[build_rig] {len(names)} Shapekeys: {names}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    in_blend = "/tmp/gooby_build/stage1_mesh.blend"
    out_blend = "/tmp/gooby_build/stage2_rig.blend"
    i = 0
    while i < len(argv):
        if argv[i] == "--in":
            in_blend = argv[i + 1]; i += 2
        elif argv[i] == "--out":
            out_blend = argv[i + 1]; i += 2
        else:
            i += 1

    bpy.ops.wm.open_mainfile(filepath=in_blend)
    obj = bpy.data.objects["Gooby"]
    regions = json.loads(obj["gooby_regions"])

    arm_obj = build_armature()
    assign_weights(obj, regions)
    build_shapekeys(obj, regions)

    obj.parent = arm_obj
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj

    # Pose-Bones: Rotation als XYZ-Euler (für keyframe-Tabellen in Stage 3)
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "XYZ"

    print(f"[build_rig] bones={len(arm_obj.data.bones)}")
    bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    print(f"[build_rig] OK → {out_blend}")


if __name__ == "__main__":
    main()
