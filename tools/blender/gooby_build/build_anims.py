# build_anims.py — Stage 3: die 11 M1-Clips als deterministische Keyframe-
# Tabellen. Jeder Clip ist eine Pose-Funktion pose(t) (Portierung der
# goobyAnims.js-Sinus/Ease-Mathematik auf Bones), gesampelt mit 24 fps in
# eine bpy-Action; jede Action landet auf einem eigenen NLA-Track
# (Track-Name = Clip-Name, Loops mit "-loop"-Suffix für den Godot-Import).
#
# Aufruf:
#   blender --background --factory-startup --python build_anims.py -- \
#       --in /tmp/gooby_build/stage2_rig.blend \
#       --out /tmp/gooby_build/stage3_anims.blend

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gooby_params as P  # noqa: E402

TAU = math.pi * 2.0
S = P.RIG_SCALE


def ss(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------
# Pose-Funktionen: t (Sekunden) → {(bone, prop): (x, y, z)}
# prop ∈ {"location", "rotation_euler", "scale"}; fehlende Bones = Rest.
# Achsen (roll=0, vertikale Bones): rot.x = nicken (+ = nach hinten kippen),
# rot.y = drehen (yaw), rot.z = seitlich lehnen. root-scale.y = vertikal.
# ---------------------------------------------------------------------------
def pose_idle(t):
    ph = t / 2.6
    breathe = math.sin(ph * TAU - math.pi / 2) * 0.5 + 0.5
    sway = math.sin(ph * TAU) * 0.052
    return {
        ("root", "scale"): (1 - breathe * 0.008, 1 + breathe * 0.03,
                            1 - breathe * 0.008),
        ("hips", "rotation_euler"): (0, 0, math.sin(ph * TAU) * 0.022),
        ("head", "rotation_euler"): (0, 0, math.sin(ph * TAU + 0.7) * 0.02),
        ("ear.L.01", "rotation_euler"): (sway * 0.6, 0, sway * 0.4),
        ("ear.R.01", "rotation_euler"): (math.sin(ph * TAU + 0.9) * 0.031, 0,
                                         -sway * 0.4),
        ("ear.L.02", "rotation_euler"): (sway * 0.5, 0, 0),
        ("ear.R.02", "rotation_euler"): (math.sin(ph * TAU + 1.2) * 0.026, 0, 0),
        ("arm.L", "rotation_euler"): (0, 0, -breathe * 0.05),
        ("arm.R", "rotation_euler"): (0, 0, breathe * 0.05),
    }


def pose_idle_lookaround(t):
    # links gucken → halten → rechts gucken → zurück; Ohren perken beim Drehen
    d = 2.5
    if t < 0.5:
        yaw = ss(t / 0.5) * 0.5
    elif t < 1.0:
        yaw = 0.5
    elif t < 1.6:
        yaw = 0.5 - ss((t - 1.0) / 0.6) * 1.0
    elif t < 2.0:
        yaw = -0.5
    else:
        yaw = -0.5 + ss((t - 2.0) / (d - 2.0)) * 0.5
    perk = math.sin(min(1.0, t / d) * math.pi) * 0.18
    return {
        ("head", "rotation_euler"): (0, yaw, yaw * 0.06),
        ("chest", "rotation_euler"): (0, yaw * 0.25, 0),
        ("ear.L.01", "rotation_euler"): (-perk, 0, 0),
        ("ear.R.01", "rotation_euler"): (-perk, 0, 0),
        ("ear.L.02", "rotation_euler"): (-perk * 0.6, 0, 0),
        ("ear.R.02", "rotation_euler"): (-perk * 0.6, 0, 0),
    }


def pose_walk(t):
    ph = t / 0.7
    step = math.sin(ph * TAU)            # L/R-Wechsel
    bob = abs(math.sin(ph * TAU))        # 2 Schritte pro Loop
    return {
        ("root", "location"): (0, 0, bob * 0.035 * S),
        ("root", "scale"): (1 + bob * 0.01, 1 - bob * 0.02, 1 + bob * 0.01),
        ("hips", "rotation_euler"): (0.04, 0, step * 0.085),
        ("head", "rotation_euler"): (0.03, 0, -step * 0.05),
        ("foot.L", "rotation_euler"): (max(0.0, step) * 0.85, 0, 0),
        ("foot.R", "rotation_euler"): (max(0.0, -step) * 0.85, 0, 0),
        ("leg.L", "rotation_euler"): (step * 0.28, 0, 0),
        ("leg.R", "rotation_euler"): (-step * 0.28, 0, 0),
        ("arm.L", "rotation_euler"): (-step * 0.38, 0, 0),
        ("arm.R", "rotation_euler"): (step * 0.38, 0, 0),
        ("ear.L.01", "rotation_euler"): (bob * 0.22, 0, step * 0.06),
        ("ear.R.01", "rotation_euler"): (bob * 0.22, 0, -step * 0.06),
        ("ear.L.02", "rotation_euler"): (bob * 0.28, 0, 0),
        ("ear.R.02", "rotation_euler"): (bob * 0.28, 0, 0),
        ("tail", "rotation_euler"): (0, 0, step * 0.2),
    }


def pose_hop(t):
    # goobyAnims 'jump': crouch 0.85 → Sprung y+0.25 → Land-Squash
    out = {}
    if t < 0.16:
        k = t / 0.16
        out[("root", "scale")] = (1 + k * 0.1, 1 - k * 0.15, 1 + k * 0.1)
    elif t < 0.48:
        k = (t - 0.16) / 0.32
        h = math.sin(k * math.pi)
        out[("root", "location")] = (0, 0, h * 0.25 * S)
        out[("root", "scale")] = (1 - h * 0.05, 1 + h * 0.08, 1 - h * 0.05)
        out[("ear.L.01", "rotation_euler")] = (h * 0.35, 0, 0)
        out[("ear.R.01", "rotation_euler")] = (h * 0.35, 0, 0)
        out[("ear.L.02", "rotation_euler")] = (h * 0.4, 0, 0)
        out[("ear.R.02", "rotation_euler")] = (h * 0.4, 0, 0)
    else:
        k = (t - 0.48) / 0.12
        sq = math.sin(min(1.0, k) * math.pi)
        out[("root", "scale")] = (1 + sq * 0.12, 1 - sq * 0.15, 1 + sq * 0.12)
    return out


def pose_sit(t):
    # Sitzpose (Couch/Brettspiel) mit Atem-Loop
    breathe = math.sin((t / 2.0) * TAU - math.pi / 2) * 0.5 + 0.5
    k = 1.0
    return {
        ("root", "location"): (0, 0, -0.10 * S * k),
        ("root", "rotation_euler"): (-0.10 * k, 0, 0),
        ("root", "scale"): (1, 1 + breathe * 0.025, 1),
        ("foot.L", "rotation_euler"): (1.05 * k, 0, 0),
        ("foot.R", "rotation_euler"): (1.05 * k, 0, 0),
        ("leg.L", "rotation_euler"): (0.30 * k, 0, 0),
        ("leg.R", "rotation_euler"): (0.30 * k, 0, 0),
        ("arm.L", "rotation_euler"): (0.25 * k, 0, -breathe * 0.04),
        ("arm.R", "rotation_euler"): (0.25 * k, 0, breathe * 0.04),
        ("head", "rotation_euler"): (0.05 * k, 0, 0),
    }


def pose_sleep(t):
    # SLEEP_POSE-Port: Rückenlage, Atmen, Ohren gedroopt
    breathe = math.sin((t / 2.2) * TAU) * 0.5 + 0.5
    return {
        ("root", "rotation_euler"): (-1.25, 0, 0),         # auf den Rücken
        ("root", "location"): (0, 0.10 * S, 0.16 * S),
        ("root", "scale"): (1 + breathe * 0.012, 1 + breathe * 0.04, 1),
        ("ear.L.01", "rotation_euler"): (0.45 * 0.55, 0, 0.2),
        ("ear.R.01", "rotation_euler"): (0.5 * 0.55, 0, -0.2),
        ("ear.L.02", "rotation_euler"): (0.3, 0, 0.1),
        ("ear.R.02", "rotation_euler"): (0.32, 0, -0.1),
        ("arm.L", "rotation_euler"): (0.35, 0, -0.1),
        ("arm.R", "rotation_euler"): (0.35, 0, 0.1),
        ("head", "rotation_euler"): (-0.08, 0, 0),
        ("foot.L", "rotation_euler"): (0.35, 0, 0),
        ("foot.R", "rotation_euler"): (0.35, 0, 0),
    }


def pose_wave(t):
    # Arm hoch + 3× Winken (goobyAnims 'wave')
    up = ss(t / 0.18) * ss((1.0 - t) / 0.15)
    wig = math.sin(((t - 0.18) / 0.55) * math.pi * 3) if t > 0.18 else 0.0
    return {
        ("arm.R", "rotation_euler"): (up * 2.1, 0, up * (0.45 + wig * 0.5)),
        ("head", "rotation_euler"): (0, 0, -up * 0.08),
        ("ear.R.01", "rotation_euler"): (-up * 0.12, 0, -up * 0.08),
    }


def pose_squeeze_door(t):
    # STECKT in der Tür: Strampeln + Zappeln (der Squeeze-Morph pulsiert
    # zur Laufzeit in gooby_rig.gd — Bones machen die Komik)
    f4 = math.sin((t / 1.8) * TAU * 4)
    f4b = math.sin((t / 1.8) * TAU * 4 + math.pi)
    f2 = math.sin((t / 1.8) * TAU * 2)
    return {
        ("root", "rotation_euler"): (0.06, f2 * 0.05, 0),
        ("root", "location"): (f4 * 0.008 * S, 0, abs(f4) * 0.008 * S),
        ("foot.L", "rotation_euler"): (0.4 + f4 * 0.55, 0, 0),
        ("foot.R", "rotation_euler"): (0.4 + f4b * 0.55, 0, 0),
        ("leg.L", "rotation_euler"): (f4 * 0.3, 0, 0),
        ("leg.R", "rotation_euler"): (f4b * 0.3, 0, 0),
        ("arm.L", "rotation_euler"): (0.9 + f4b * 0.4, 0, -0.3),
        ("arm.R", "rotation_euler"): (0.9 + f4 * 0.4, 0, 0.3),
        ("head", "rotation_euler"): (-0.1, f2 * 0.08, 0),
        ("ear.L.01", "rotation_euler"): (0.2 + f4 * 0.1, 0, 0.1),
        ("ear.R.01", "rotation_euler"): (0.2 + f4b * 0.1, 0, -0.1),
    }


def pose_brush_teeth(t):
    # Schrubben am Mund mit Kopf-Mitwackeln (F §1.4 'toothbrush')
    scrub = math.sin((t / 1.1) * TAU * 3)
    return {
        ("arm.R", "rotation_euler"): (1.7, 0, -0.35 + scrub * 0.22),
        ("arm.L", "rotation_euler"): (0.1, 0, -0.05),
        ("head", "rotation_euler"): (0.06, scrub * 0.07, scrub * 0.04),
        ("root", "scale"): (1, 1 + abs(scrub) * 0.01, 1),
        ("ear.L.01", "rotation_euler"): (scrub * 0.05, 0, 0.05),
        ("ear.R.01", "rotation_euler"): (-scrub * 0.05, 0, -0.05),
    }


def pose_build_hammer(t):
    # Hämmern + Rückstoß-Wobble (D §3.1 Aufbau-Gag)
    ph = (t / 0.9) % 1.0
    if ph < 0.35:
        lift = ss(ph / 0.35)             # ausholen
    elif ph < 0.5:
        lift = 1.0 - ss((ph - 0.35) / 0.15)  # zuschlagen (schnell)
    else:
        lift = 0.0
    impact = math.sin(max(0.0, min(1.0, (ph - 0.5) / 0.25)) * math.pi)
    return {
        ("arm.R", "rotation_euler"): (0.6 + lift * 1.8, 0, 0.25),
        ("arm.L", "rotation_euler"): (0.3, 0, -0.15),
        ("root", "scale"): (1 + impact * 0.06, 1 - impact * 0.08,
                            1 + impact * 0.06),
        ("hips", "rotation_euler"): (impact * 0.04 - lift * 0.05, 0, 0),
        ("head", "rotation_euler"): (lift * 0.10 - impact * 0.06, 0, 0),
        ("ear.L.01", "rotation_euler"): (impact * 0.18, 0, 0.05),
        ("ear.R.01", "rotation_euler"): (impact * 0.18, 0, -0.05),
    }


def pose_celebrate(t):
    # happyBounce-Port: 2 Hüpfer, Squash, Ohren-Flop, Arme hoch
    hop = abs(math.sin((t / 0.45) * math.pi))
    landing = 1 - hop
    return {
        ("root", "location"): (0, 0, hop * 0.12 * S),
        ("root", "scale"): (1 + landing * 0.15 - hop * 0.04,
                            1 - landing * 0.15 + hop * 0.06,
                            1 + landing * 0.15 - hop * 0.04),
        ("arm.L", "rotation_euler"): (2.0, 0, -0.35),
        ("arm.R", "rotation_euler"): (2.0, 0, 0.35),
        ("ear.L.01", "rotation_euler"): (hop * 0.5 - 0.15, 0, 0.05),
        ("ear.R.01", "rotation_euler"): (hop * 0.5 - 0.15, 0, -0.05),
        ("ear.L.02", "rotation_euler"): (hop * 0.3, 0, 0),
        ("ear.R.02", "rotation_euler"): (hop * 0.3, 0, 0),
        ("head", "rotation_euler"): (-hop * 0.06, 0, 0),
    }


CLIP_POSES = {
    "idle": pose_idle,
    "idle_lookaround": pose_idle_lookaround,
    "walk": pose_walk,
    "hop": pose_hop,
    "sit": pose_sit,
    "sleep": pose_sleep,
    "wave": pose_wave,
    "squeeze_door": pose_squeeze_door,
    "brush_teeth": pose_brush_teeth,
    "build_hammer": pose_build_hammer,
    "celebrate": pose_celebrate,
}

REST = {"location": (0.0, 0.0, 0.0), "rotation_euler": (0.0, 0.0, 0.0),
        "scale": (1.0, 1.0, 1.0)}


def bake_clip(arm, name, duration, loop):
    """Pose-Funktion mit ANIM_FPS in eine Action samplen."""
    fn = CLIP_POSES[name]
    fps = P.ANIM_FPS
    n_frames = max(2, round(duration * fps))
    track_name = f"{name}-loop" if loop else name

    action = bpy.data.actions.new(track_name)
    action.use_fake_user = True
    arm.animation_data.action = action

    # Welche (bone, prop)-Kanäle benutzt der Clip insgesamt?
    used = set()
    for fi in range(n_frames + 1):
        used |= set(fn(fi / fps).keys())

    for fi in range(n_frames + 1):
        t = fi / fps
        if loop:
            t = t % duration if fi < n_frames else 0.0   # letzter Frame = erster
        pose = fn(min(t, duration))
        for (bone, prop) in used:
            pb = arm.pose.bones[bone]
            val = pose.get((bone, prop), REST[prop])
            setattr(pb, prop, val)
            pb.keyframe_insert(prop, frame=fi)

    for fc in action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"

    # NLA-Track (Name = glTF-Animationsname)
    track = arm.animation_data.nla_tracks.new()
    track.name = track_name
    strip = track.strips.new(track_name, 0, action)
    strip.name = track_name
    arm.animation_data.action = None

    # Pose zurücksetzen
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)
    return n_frames


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    in_blend = "/tmp/gooby_build/stage2_rig.blend"
    out_blend = "/tmp/gooby_build/stage3_anims.blend"
    i = 0
    while i < len(argv):
        if argv[i] == "--in":
            in_blend = argv[i + 1]; i += 2
        elif argv[i] == "--out":
            out_blend = argv[i + 1]; i += 2
        else:
            i += 1

    bpy.ops.wm.open_mainfile(filepath=in_blend)
    arm = bpy.data.objects["GoobyArmature"]
    arm.animation_data_create()
    bpy.context.scene.render.fps = P.ANIM_FPS

    for name, (duration, loop) in P.CLIP_LIST.items():
        frames = bake_clip(arm, name, duration, loop)
        print(f"[build_anims] {name}: {duration}s loop={loop} frames={frames}")

    bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    print(f"[build_anims] OK → {out_blend} ({len(P.CLIP_LIST)} Clips)")


if __name__ == "__main__":
    main()
