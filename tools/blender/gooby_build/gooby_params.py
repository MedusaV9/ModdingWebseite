# gooby_params.py — Single Source of Truth für den Gooby-Charakter-Build.
# ALLE Proportions-Zahlen sind 1:1 aus der Web-Referenz (vor-Godot-Version):
#   /workspace/GOOBY/src/character/gooby.js       (PEAR_PROFILE, Pivots, Maße)
#   /workspace/GOOBY/src/character/goobyFace.js   (Augen/Nase/Zähne/Wangen/Mund)
#   /workspace/GOOBY/src/gfx/materials.js         (PALETTE/DETAIL-Hexfarben)
#   /workspace/GOOBY/src/character/emotions.js    (FACES-Tabelle → Emotions-Morphs)
#
# FB1 (User-Feedback ×3: "Gooby braucht sein altes Model aus der alten
# vor-Godot-Version wieder"): die FIX2-Neuinterpretation (Kopf ×1.30,
# Kulleraugen r0.065, dicke Wangen r0.078, breite Ohren r0.10) ist
# ZURÜCKGEBAUT auf die exakten Web-Zahlen — Messlatte sind die gerenderten
# Web-Screenshots (Kopf/Körper-Breite ≈ 0.75, Auge/Kopf ≈ 0.14, schlanke
# aufrechte Ohren, Birnenkörper 0.78 hoch mit Hüft-Maximum r0.46).
# Bone-/Clip-/Shapekey-NAMEN bleiben Frozen-Contract; die Bone-POSITIONEN
# werden unten aus den Parametern ABGELEITET statt hartkodiert.
#
# Koordinaten: "Rezept-Raum" wie im Web (three.js, Y-up, Charakter guckt +Z;
# Birnenkörper 0.78 hoch, Gesamthöhe bis Ohrspitzen = RECIPE_HEIGHT unten).
# Der fertige Rig wird auf TARGET_HEIGHT skaliert (1 Unit ≈ 1 m). Blender ist
# Z-up und der Charakter guckt dort -Y; build_mesh.py konvertiert mit
# to_blender().

import math

TARGET_HEIGHT = 1.05

# ---------------------------------------------------------------------------
# §D2.2 Birnen-Profil (x = Radius, y = Höhe) — CatmullRom, 26 Samples, 24 Seg.
# 1:1 gooby.js PEAR_PROFILE: Hüft-Maximum r0.46 bei y0.40, oben schmaler
# (DER dicke Birnen-Look — "widest at the hips").
# ---------------------------------------------------------------------------
PEAR_PROFILE = [
    (0.0, 0.0), (0.3, 0.02), (0.43, 0.2), (0.46, 0.4),
    (0.4, 0.58), (0.3, 0.7), (0.18, 0.76), (0.0, 0.78),
]
PEAR_SAMPLES = 26
PEAR_SEGMENTS = 24

# ---------------------------------------------------------------------------
# Farbpalette (materials.js PALETTE + DETAIL) — Kenney-Stil Palette-Textur
# ---------------------------------------------------------------------------
PALETTE = {
    "body":     "#F6EAD7",
    "belly":    "#FFF9EC",
    "earInner": "#F6A8B8",
    "nose":     "#E88BA0",
    "cheek":    "#F9C6CF",
    "eye":      "#3A2E2E",
    "eyeShine": "#FFFFFF",
    "pawPad":   "#F3B7C3",
    "tooth":    "#FFFFFF",
    "mouth":    "#4A2B33",
}
# Zellenreihenfolge auf der Palette-Textur (4×4-Raster, 64 px Zellen, 256²)
PALETTE_ORDER = [
    "body", "belly", "earInner", "nose",
    "cheek", "eye", "eyeShine", "pawPad",
    "tooth", "mouth",
]
PALETTE_GRID = 4          # 4×4 Zellen
PALETTE_SIZE = 256        # px

# ---------------------------------------------------------------------------
# Körperteile (Rezept-Raum, Web-Zahlen)
# ---------------------------------------------------------------------------
# Kopf-Gruppe: Pivot (0, 0.685, 0), uniform 1.08 skaliert (gooby.js headGrp)
HEAD_PIVOT_Y = 0.685
HEAD_GRP_SCALE = 1.08
# Kopf-Sphere r0.30, scale (1.05, 0.92, 0.95), lokal (0, 0.16, 0.02)
HEAD_LOCAL = (0.0, 0.16, 0.02)
HEAD_R = 0.30
HEAD_SCALE = (1.05, 0.92, 0.95)

# goobyFace.js: HEAD-Ellipsoid im Körperraum VOR der Gruppenskalierung,
# Face-local() = (x, y - 0.7, z) relativ zum Face-Pivot 0.7
FACE_PIVOT_Y = 0.7
FACE_HEAD = {"cx": 0.0, "cy": 0.86, "cz": 0.02, "rx": 0.315, "ry": 0.276, "rz": 0.285}

# Bauchfleck: Sphere r0.30, scale (1, 1.05, 0.42) bei (0, 0.32, 0.34)
BELLY = {"r": 0.30, "scale": (1.0, 1.05, 0.42), "pos": (0.0, 0.32, 0.34)}
# Puschelschwanz: Web r0.09 bei (0, 0.18, -0.42) — leicht gepufft auf 0.10
# (Ein-Mesh-Build: der Puschel muss sichtbar aus dem Lathe-Körper ragen)
TAIL = {"r": 0.10, "pos": (0.0, 0.18, -0.42)}

# Ohren: Pivots kopf-lokal (±0.13, 0.36, 0) [= body 1.06 - 0.7], Tilt ±0.175
# — schlanke, aufrechte Kapsel-Ohren wie im Web (r0.085 × 0.34)
EAR = {
    "pivot_local": (0.13, 1.06 - FACE_PIVOT_Y, 0.0),
    "tilt": 0.175,
    "outer_r": 0.085, "outer_len": 0.34, "outer_y": 0.24,
    "inner_r": 0.055, "inner_len": 0.26,
    "inner_scale": (0.72, 1.0, 0.5), "inner_pos": (0.0, 0.26, 0.063),
}

# Augen: kleine Knopf-Perlen r0.045 bei face-local (±0.115, 0.90, 0.255);
# Glanzpunkt r0.015 — der Web-Gooby hat bewusst KEINE Kulleraugen.
EYE = {
    "pos": (0.115, 0.90, 0.255), "r": 0.045,
    "shine_r": 0.015, "shine_off": (0.012, 0.015, 0.03),
}

# Nase: r0.035, scale (1.15, 0.85, 0.6) bei (0, 0.845, 0.295)
NOSE = {"r": 0.035, "scale": (1.15, 0.85, 0.6), "pos": (0.0, 0.845, 0.295)}

# Hasenzähne: 2 Boxen 0.030×0.038×0.012 bei ±0.0165, Gruppe y 0.788,
# z = surface + 0.022, rot.x 0.2
TEETH = {"w": 0.030, "h": 0.038, "d": 0.012, "dx": 0.0165,
         "y": 0.788, "z_push": 0.022, "rot_x": 0.2, "tilt": 0.045}

# Wangen: kleine rosa Kreise r0.05 bei (±0.17, 0.83) auf der Kopfoberfläche
# (push 0.006 statt Web 0.004: die Godot-Wange ist eine gewölbte Kugelkappe,
# kein flaches Decal — der Hauch Abstand verhindert Z-Fighting)
CHEEK = {"r": 0.05, "x": 0.17, "y": 0.83, "push": 0.006}

# Mund-Decals (goobyFace.js mouthDefs): Anker y 0.748, z surface+0.014,
# rot.x 0.28. Versteckte Shapes stecken SUNK_DEPTH im Kopf und werden per
# Shapekey herausgeschoben.
MOUTH = {
    "y": 0.748, "push": 0.014, "rot_x": 0.28,
    "smile_R": 0.075, "smile_w": 0.02, "smile_a0": 0.55,   # π+0.55 … 2π−0.55
    "frown_R": 0.075, "frown_w": 0.018, "frown_a0": 0.65,
    "flat_w": 0.085, "flat_h": 0.02,
    "open_rx": 0.04, "open_ry": 0.05,
    "sunk_depth": 0.06,
}

# Ärmchen: Kapsel r0.08 × Zyl. 0.18, Pivots (±0.36, 0.52, 0.05), Mesh y −0.12
# Ruhepose (gebacken): rot.x = −0.5 (auf dem Bauch), rot.z = ∓0.38 (Pfötchen raus)
ARM = {"pivot": (0.36, 0.52, 0.05), "r": 0.08, "len": 0.18, "mesh_y": -0.12,
       "rest_fwd": 0.5, "rest_out": 0.38}

# Füßchen: Kapsel r0.11 × 0.22 liegend, scale (0.85, 1, 0.5),
# Pivots (±0.16, 0.05, 0.20), Splay ±18°, Mesh z 0.08; Pad r0.075
FOOT = {"pivot": (0.16, 0.05, 0.20), "r": 0.11, "len": 0.22,
        "scale": (0.85, 1.0, 0.5), "mesh_z": 0.08, "splay_deg": 18.0,
        "pad_r": 0.075, "pad_scale": (0.8, 1.35), "pad_pos": (0.0, -0.052, 0.14)}

# ---------------------------------------------------------------------------
# Abgeleitete Größen (FIX2): Ohr-Geometrie/Gesamthöhe folgen den Parametern —
# eine Proportionsänderung oben zieht Bones, Skinning-Bänder und Shapekey-
# Spannen automatisch mit (statt 6 hartkodierte Stellen zu verstimmen).
# ---------------------------------------------------------------------------
EAR_LEAN = EAR["tilt"] * 1.25                     # Auswärts-Lehne (build_mesh)
EAR_BASE_X = EAR["pivot_local"][0] * HEAD_GRP_SCALE
EAR_BASE_Y = HEAD_PIVOT_Y + EAR["pivot_local"][1] * HEAD_GRP_SCALE
_EAR_LEN = (EAR["outer_y"] + EAR["outer_len"] / 2 + EAR["outer_r"]) * HEAD_GRP_SCALE
EAR_TIP_X = EAR_BASE_X + math.sin(EAR_LEAN) * _EAR_LEN
EAR_TIP_RECIPE = EAR_BASE_Y + math.cos(EAR_LEAN) * _EAR_LEN
_EAR_MID_X = EAR_BASE_X + math.sin(EAR_LEAN) * _EAR_LEN * 0.5
_EAR_MID_Y = EAR_BASE_Y + math.cos(EAR_LEAN) * _EAR_LEN * 0.5

RECIPE_HEIGHT = EAR_TIP_RECIPE                    # Höhe bis zu den Ohrspitzen
RIG_SCALE = TARGET_HEIGHT / RECIPE_HEIGHT

# Kopf-Zentrum im Rezept-Raum (für Bones/Skinning)
HEAD_CENTER_Y = HEAD_PIVOT_Y + HEAD_LOCAL[1] * HEAD_GRP_SCALE
HEAD_TOP_Y = HEAD_CENTER_Y + HEAD_R * HEAD_SCALE[1] * HEAD_GRP_SCALE
HEAD_BOTTOM_Y = HEAD_CENTER_Y - HEAD_R * HEAD_SCALE[1] * HEAD_GRP_SCALE


def _arm_tip(sx):
    """Pfotenspitze der eingebackenen Arm-Ruhepose (für den Arm-Bone-Tail)."""
    tip_y = ARM["mesh_y"] - (ARM["len"] / 2 + ARM["r"]) + 0.03
    c_f, s_f = math.cos(-ARM["rest_fwd"]), math.sin(-ARM["rest_fwd"])
    y, z = tip_y * c_f, tip_y * s_f
    a = sx * ARM["rest_out"]
    c_o, s_o = math.cos(a), math.sin(a)
    x = -y * s_o
    y = y * c_o
    return (sx * ARM["pivot"][0] + x, ARM["pivot"][1] + y, ARM["pivot"][2] + z)


# ---------------------------------------------------------------------------
# Rig: 21 Bones (Plan "~22") — NAMEN sind Frozen-Contract für gooby_rig.gd;
# die Positionen sind aus den Proportions-Parametern oben abgeleitet.
# ---------------------------------------------------------------------------
_EYE_X = EYE["pos"][0] * HEAD_GRP_SCALE
_EYE_Y = HEAD_PIVOT_Y + (EYE["pos"][1] - FACE_PIVOT_Y) * HEAD_GRP_SCALE
BONES = [
    # (name, parent, head_recipe(x,y,z), tail_recipe(x,y,z))
    ("root",     None,     (0.0, 0.00, 0.0),   (0.0, 0.14, 0.0)),
    ("hips",     "root",   (0.0, 0.14, 0.0),   (0.0, 0.40, 0.0)),
    ("spine",    "hips",   (0.0, 0.40, 0.0),   (0.0, 0.58, 0.0)),
    ("chest",    "spine",  (0.0, 0.58, 0.0),   (0.0, HEAD_PIVOT_Y, 0.0)),
    ("head",     "chest",  (0.0, HEAD_PIVOT_Y, 0.0), (0.0, HEAD_TOP_Y, 0.0)),
    ("jaw",      "head",   (0.0, 0.75, 0.26),  (0.0, 0.71, 0.38)),
    ("eye.L",    "head",   (-_EYE_X, _EYE_Y, 0.20), (-_EYE_X, _EYE_Y, 0.34)),
    ("eye.R",    "head",   (_EYE_X, _EYE_Y, 0.20),  (_EYE_X, _EYE_Y, 0.34)),
    ("ear.L.01", "head",   (-EAR_BASE_X, EAR_BASE_Y, 0.0), (-_EAR_MID_X, _EAR_MID_Y, 0.0)),
    ("ear.L.02", "ear.L.01", (-_EAR_MID_X, _EAR_MID_Y, 0.0), (-EAR_TIP_X, EAR_TIP_RECIPE, 0.0)),
    ("ear.R.01", "head",   (EAR_BASE_X, EAR_BASE_Y, 0.0),  (_EAR_MID_X, _EAR_MID_Y, 0.0)),
    ("ear.R.02", "ear.R.01", (_EAR_MID_X, _EAR_MID_Y, 0.0), (EAR_TIP_X, EAR_TIP_RECIPE, 0.0)),
    # Ärmchen-Bones folgen der eingebackenen Ruhepose (auf dem Bauch)
    ("arm.L",    "chest",  (-ARM["pivot"][0], ARM["pivot"][1], ARM["pivot"][2]), _arm_tip(-1)),
    ("arm.R",    "chest",  (ARM["pivot"][0], ARM["pivot"][1], ARM["pivot"][2]), _arm_tip(1)),
    ("leg.L",    "hips",   (-0.16, 0.14, 0.10), (-0.16, 0.05, 0.20)),
    ("leg.R",    "hips",   (0.16, 0.14, 0.10),  (0.16, 0.05, 0.20)),
    ("foot.L",   "leg.L",  (-0.16, 0.05, 0.20), (-0.16, 0.05, 0.44)),
    ("foot.R",   "leg.R",  (0.16, 0.05, 0.20),  (0.16, 0.05, 0.44)),
    ("tail",     "hips",   (0.0, 0.18, TAIL["pos"][2] + 0.08),
     (0.0, 0.18, TAIL["pos"][2] - 0.10)),
]

# ---------------------------------------------------------------------------
# Shapekeys (14 ≤ Budget 24) — Namen sind Frozen-Contract für gooby_rig.gd
# ---------------------------------------------------------------------------
SHAPEKEYS = [
    "emotion_neutral", "emotion_happy", "emotion_sad", "emotion_sleepy",
    "emotion_ecstatic", "emotion_angry", "emotion_scared", "emotion_dizzy",
    "blink", "mouth_open", "body_squeeze_door",
    "eye_width", "eye_size", "ear_length",
]

# Emotions-Rezepte (aus emotions.js FACES abgeleitet):
#   mouth: welches Decal sichtbar wird ('smile' bleibt, andere fahren raus)
#   lids: 0 (offen) … 1 (zu) — als vertikale Augen-Squash-Stärke
#   smile/cheek/eye_scale: Skalierungsfaktoren
EMOTIONS = {
    #             mouth     lids  smile  cheek  eye_scale  eye_slant
    "neutral":  ("smile",   0.05, 0.99,  1.00,  1.00, 0.0),
    "happy":    ("smile",   0.00, 1.12,  1.10,  1.00, 0.0),
    "ecstatic": ("smile",   0.00, 1.28,  1.20,  1.12, 0.0),
    "sad":      ("frown",   0.30, 0.00,  1.00,  1.00, 0.0),
    "angry":    ("flat",    0.42, 0.00,  1.00,  0.95, 0.5),   # ≈ grumpy im Web
    "sleepy":   ("flat",    0.60, 0.00,  1.00,  1.00, 0.0),
    "scared":   ("open",    0.00, 0.00,  1.00,  1.25, -0.3),
    "dizzy":    ("open",    0.10, 0.00,  1.00,  1.00, 0.0),
}

TRI_BUDGET = 8000

# ---------------------------------------------------------------------------
# M1-Clip-Liste (Task-bindend): Name → (Dauer s, loop)
# ---------------------------------------------------------------------------
CLIP_LIST = {
    "idle":            (2.6, True),
    "idle_lookaround": (2.5, False),
    "walk":            (0.7, True),
    "hop":             (0.6, False),
    "sit":             (2.0, True),
    "sleep":           (2.2, True),
    "wave":            (1.0, False),
    "squeeze_door":    (1.8, True),
    "brush_teeth":     (1.1, True),
    "build_hammer":    (0.9, True),
    "celebrate":       (0.9, False),
}

ANIM_FPS = 24


def hex_to_rgb(hex_str):
    """'#RRGGBB' → (r, g, b) 0..1 linear-ish (sRGB-Werte, Konvertierung im Shader)."""
    h = hex_str.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb_to_linear(c):
    """sRGB-Komponente → linear (für Blender-Image-Pixels)."""
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def palette_uv(part):
    """UV-Zellenmitte des Palette-Feldes für ein Körperteil."""
    idx = PALETTE_ORDER.index(part)
    col = idx % PALETTE_GRID
    row = idx // PALETTE_GRID
    u = (col + 0.5) / PALETTE_GRID
    v = 1.0 - (row + 0.5) / PALETTE_GRID
    return (u, v)


def face_local_to_recipe(x, y, z):
    """goobyFace-local (x, y_body, z) → Rezept-Raum (Kopfgruppe 0.685 + 1.08)."""
    s = HEAD_GRP_SCALE
    return (x * s, HEAD_PIVOT_Y + (y - FACE_PIVOT_Y) * s, z * s)


def face_surface_z(x, y, push=0.004):
    """goobyFace.js surfaceZ: Kopf-Oberflächen-z für (x, y) im Körperraum."""
    h = FACE_HEAD
    k = 1.0 - ((x - h["cx"]) / h["rx"]) ** 2 - ((y - h["cy"]) / h["ry"]) ** 2
    return h["cz"] + h["rz"] * max(0.0, k) ** 0.5 + push


def to_blender(p, scale=RIG_SCALE):
    """Rezept-Raum (three.js: Y-up, Gesicht +Z) → Blender (Z-up, Gesicht −Y).

    Der glTF-Export (Y-up) macht daraus wieder Y-up mit Gesicht +Z.
    """
    x, y, z = p
    return (x * scale, -z * scale, y * scale)


def dir_to_blender(d):
    """Richtungsvektor Rezept-Raum → Blender (ohne Skalierung)."""
    x, y, z = d
    return (x, -z, y)
