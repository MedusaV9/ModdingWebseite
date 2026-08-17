#!/usr/bin/env python3
"""Premium-Painter fuer alle Gooby ENTITY-Texturen (Pillow, deterministisch).

Malt die Felle direkt anhand der Runtime-Geometrien (geo/*.geo.json):
jede Cube-Face bekommt Fellrichtung (gerichtete Strähnen), Ambient
Occlusion an den Kanten, Face-abhängiges Licht, Rim-Highlights und —
beim Spotted-Coat — echte, organisch gewachsene Flecken statt eines
Modulo-Musters.

Erzeugt AUSSCHLIESSLICH die fuenf Entity-Sheets (Groessen/Dateinamen
bleiben erhalten):
    textures/entity/gooby.png            (classic)
    textures/entity/gooby_cream.png
    textures/entity/gooby_cocoa.png
    textures/entity/gooby_spotted.png
    textures/entity/gooby_baby.png

Aufruf:  python3 scripts/gen_entity_textures.py
Item-/Block-/GUI-Texturen liegen weiterhin bei scripts/gen_textures.py.
"""
from __future__ import annotations

import json
import math
import os
import random

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
GEO_DIR = os.path.join(ROOT, "src", "main", "resources", "assets", "goobymod", "geo")
OUT_DIR = os.path.join(ROOT, "src", "main", "resources", "assets", "goobymod",
                       "textures", "entity")

SMILE = (94, 60, 38)
WHITE = (255, 255, 255)

# Face-abhaengiges Licht (Sonne von oben, Front klar lesbar).
FACE_LIGHT = {"up": 1.08, "down": 0.78, "north": 1.0,
              "south": 0.96, "east": 0.9, "west": 0.9}

PALETTES = {
    "classic": {
        "fur": (201, 157, 111), "fur_light": (221, 181, 137), "fur_dark": (170, 126, 85),
        "cream": (243, 226, 200), "cream_dark": (224, 203, 171),
        "pink": (247, 170, 196), "pink_dark": (222, 130, 163),
        "spots": None,
    },
    "cream": {
        "fur": (233, 214, 182), "fur_light": (245, 231, 205), "fur_dark": (204, 181, 145),
        "cream": (250, 241, 224), "cream_dark": (233, 219, 195),
        "pink": (249, 178, 202), "pink_dark": (226, 138, 169),
        "spots": None,
    },
    "cocoa": {
        "fur": (128, 84, 52), "fur_light": (152, 105, 68), "fur_dark": (99, 62, 38),
        "cream": (224, 194, 158), "cream_dark": (200, 168, 131),
        "pink": (238, 152, 180), "pink_dark": (211, 116, 147),
        "spots": None,
    },
    "spotted": {
        "fur": (226, 207, 176), "fur_light": (241, 225, 197), "fur_dark": (197, 175, 141),
        "cream": (248, 238, 218), "cream_dark": (229, 215, 190),
        "pink": (247, 170, 196), "pink_dark": (222, 130, 163),
        "spots": ((112, 72, 45), (88, 55, 34)),
    },
}


def soften(color):
    """Aufgehellte Baby-Variante einer Adult-Fellfarbe."""
    return (min(255, int(color[0] * 0.82 + 52)),
            min(255, int(color[1] * 0.84 + 45)),
            min(255, int(color[2] * 0.88 + 35)))


def baby_palette():
    base = PALETTES["classic"]
    return {key: (soften(value) if isinstance(value, tuple) else value)
            for key, value in base.items()}


def clamp(v):
    return max(0, min(255, int(round(v))))


def shade(color, mul, add=0):
    return (clamp(color[0] * mul + add), clamp(color[1] * mul + add),
            clamp(color[2] * mul + add))


def mix(a, b, t):
    return (clamp(a[0] + (b[0] - a[0]) * t), clamp(a[1] + (b[1] - a[1]) * t),
            clamp(a[2] + (b[2] - a[2]) * t))


def box_uv_faces(u0, v0, w, h, d):
    """Bedrock-Box-UV: Face -> (x0, y0, x1, y1) in Texel-Koordinaten."""
    return {
        "up": (u0 + d, v0, u0 + d + w, v0 + d),
        "down": (u0 + d + w, v0, u0 + d + 2 * w, v0 + d),
        "east": (u0, v0 + d, u0 + d, v0 + d + h),
        "north": (u0 + d, v0 + d, u0 + d + w, v0 + d + h),
        "west": (u0 + d + w, v0 + d, u0 + d + w + d, v0 + d + h),
        "south": (u0 + 2 * d + w, v0 + d, u0 + 2 * d + 2 * w, v0 + d + h),
    }


def outward(rect):
    x0, y0, x1, y1 = rect
    return (math.floor(x0), math.floor(y0), math.ceil(x1), math.ceil(y1))


def cube_faces(cube):
    """Liefert {face: int-rect} fuer Box-UV- und Per-Face-UV-Cubes."""
    uv = cube.get("uv")
    w, h, d = cube["size"]
    faces = {}
    if isinstance(uv, dict):
        for face, spec in uv.items():
            u, v = spec["uv"]
            us, vs = spec["uv_size"]
            faces[face] = outward((u, v, u + us, v + vs))
    else:
        for face, rect in box_uv_faces(uv[0], uv[1], w, h, d).items():
            x0, y0, x1, y1 = outward(rect)
            if x1 > x0 and y1 > y0:
                faces[face] = (x0, y0, x1, y1)
    return faces


def load_geo(path):
    with open(path, "r", encoding="utf-8") as handle:
        geometry = json.load(handle)["minecraft:geometry"][0]
    return geometry


# ---------------------------------------------------------------------------
# Mal-Primitive
# ---------------------------------------------------------------------------

def paint_fur_face(px, rect, face, base, palette, rng):
    """Basisfell mit Richtung, AO und Rim-Licht auf eine Face-Region malen."""
    x0, y0, x1, y1 = rect
    light = FACE_LIGHT.get(face, 1.0)
    width, height = x1 - x0, y1 - y0

    for x in range(x0, x1):
        column_bias = rng.uniform(-4, 4)
        for y in range(y0, y1):
            noise = rng.uniform(-6, 6) + column_bias
            px[x, y] = shade(base, light, noise) + (255,)

    # Fellrichtung: kurze, dunklere Straehnen die nach unten auslaufen.
    streaks = max(2, (width * height) // 5)
    dark = mix(base, palette["fur_dark"], 0.75)
    for _ in range(streaks):
        sx = rng.randint(x0, x1 - 1)
        sy = rng.randint(y0, max(y0, y1 - 2))
        length = rng.randint(2, 3)
        strength = rng.uniform(0.35, 0.6)
        for i in range(length):
            yy = sy + i
            if yy >= y1:
                break
            fade = strength * (1.0 - i / max(1, length))
            current = px[sx, yy]
            px[sx, yy] = mix(current[:3], shade(dark, light), fade) + (255,)

    # Einzelne helle Deckhaare.
    guard = mix(base, palette["fur_light"], 0.9)
    for _ in range(max(1, (width * height) // 14)):
        gx = rng.randint(x0, x1 - 1)
        gy = rng.randint(y0, y1 - 1)
        px[gx, gy] = shade(guard, light, 4) + (255,)

    # Ambient Occlusion: Kanten abdunkeln, Ecken staerker.
    for x in range(x0, x1):
        for y in (y0, y1 - 1):
            px[x, y] = shade(px[x, y][:3], 0.88) + (255,)
    for y in range(y0, y1):
        for x in (x0, x1 - 1):
            px[x, y] = shade(px[x, y][:3], 0.9) + (255,)
    for cx, cy in ((x0, y0), (x1 - 1, y0), (x0, y1 - 1), (x1 - 1, y1 - 1)):
        px[cx, cy] = shade(px[cx, cy][:3], 0.86) + (255,)

    # Rim-Highlight oben auf Front-/Top-Faces.
    if face in ("north", "up") and height >= 3:
        for x in range(x0 + 1, x1 - 1):
            px[x, y0] = shade(px[x, y0][:3], 1.07, 5) + (255,)


def paint_soft_face(px, rect, face, base, rng, spread=9):
    """Weiches, flauschiges Material (Puschel, Creme-Flaechen)."""
    x0, y0, x1, y1 = rect
    light = FACE_LIGHT.get(face, 1.0)
    for x in range(x0, x1):
        for y in range(y0, y1):
            px[x, y] = shade(base, light, rng.uniform(-spread, spread)) + (255,)
    for x in range(x0, x1):
        px[x, y1 - 1] = shade(px[x, y1 - 1][:3], 0.9) + (255,)


def noisy_ellipse(px, rect, inset, color, color_dark, rng):
    """Gefleckte Ellipse (Bauch-/Schnauzenfleck) mit weicher Kante."""
    x0, y0, x1, y1 = rect
    x0i, y0i = x0 + inset[0], y0 + inset[1]
    x1i, y1i = x1 - inset[2], y1 - inset[3]
    if x1i <= x0i or y1i <= y0i:
        return
    cx, cy = (x0i + x1i - 1) / 2.0, (y0i + y1i - 1) / 2.0
    rx, ry = max(0.8, (x1i - x0i) / 2.0), max(0.8, (y1i - y0i) / 2.0)
    for x in range(x0i, x1i):
        for y in range(y0i, y1i):
            dist = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if dist <= 1.0 + rng.uniform(-0.18, 0.12):
                base = color_dark if rng.random() < 0.22 else color
                px[x, y] = shade(base, 1.0, rng.uniform(-5, 5)) + (255,)


def grow_spot(px, rect, rng, colors, size):
    """Echter Fleck: organisch per Random-Walk gewachsener Pixel-Blob."""
    x0, y0, x1, y1 = rect
    if x1 - x0 < 3 or y1 - y0 < 3:
        return
    seed = (rng.randint(x0 + 1, x1 - 2), rng.randint(y0 + 1, y1 - 2))
    blob = {seed}
    tries = 0
    while len(blob) < size and tries < size * 6:
        tries += 1
        bx, by = rng.choice(tuple(blob))
        nx = bx + rng.choice((-1, 0, 1))
        ny = by + rng.choice((-1, 0, 1))
        if x0 <= nx < x1 and y0 <= ny < y1:
            blob.add((nx, ny))
    light, dark = colors
    for (sx, sy) in blob:
        neighbours = sum(1 for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                         if (sx + dx, sy + dy) in blob) - 1
        color = dark if neighbours >= 5 else light
        face_mul = 1.0
        px[sx, sy] = shade(color, face_mul, rng.uniform(-6, 6)) + (255,)


# ---------------------------------------------------------------------------
# Detail-Dekor pro Koerperteil
# ---------------------------------------------------------------------------

def decorate_body(px, faces, palette, rng):
    # Cremefarbener Bauchfleck vorne, mit gefleckter Kante.
    if "north" in faces:
        noisy_ellipse(px, faces["north"], (3, 3, 3, 1),
                      palette["cream"], palette["cream_dark"], rng)
    # Ruecken: dezenter dunkler Aalstrich + helle Flausch-Tupfer.
    if "up" in faces:
        x0, y0, x1, y1 = faces["up"]
        mid = (x0 + x1) // 2
        for y in range(y0 + 1, y1 - 1):
            px[mid, y] = mix(px[mid, y][:3], palette["fur_dark"], 0.35) + (255,)
    if "south" in faces:
        x0, y0, x1, y1 = faces["south"]
        for _ in range(10):
            tx = rng.randint(x0 + 1, x1 - 2)
            ty = rng.randint(y0 + 1, y1 - 2)
            px[tx, ty] = mix(px[tx, ty][:3], palette["fur_light"], 0.8) + (255,)


def decorate_muzzle(px, faces, palette, rng):
    for face, rect in faces.items():
        paint_soft_face(px, rect, face, palette["cream"], rng, spread=6)
    if "north" in faces:
        x0, y0, x1, y1 = faces["north"]
        cx = (x0 + x1 - 1) // 2
        # Philtrum unter der Nase + kleines "w"-Laecheln.
        px[cx, y0] = mix(palette["cream_dark"], SMILE, 0.45) + (255,)
        bottom = y1 - 1
        for dx in (-1, 1):
            if x0 <= cx + dx < x1:
                px[cx + dx, bottom] = SMILE + (255,)
        for dx in (-2, 2):
            if x0 <= cx + dx < x1:
                px[cx + dx, bottom] = mix(SMILE, palette["cream_dark"], 0.4) + (255,)
        px[cx, bottom] = mix(SMILE, palette["cream_dark"], 0.25) + (255,)


def decorate_cheek(px, faces, palette, rng):
    rosy = mix(palette["fur"], palette["pink"], 0.3)
    for face, rect in faces.items():
        paint_soft_face(px, rect, face, rosy, rng, spread=6)
    if "north" in faces:
        x0, y0, x1, y1 = faces["north"]
        cx, cy = (x0 + x1 - 1) // 2, (y0 + y1 - 1) // 2
        px[cx, cy] = palette["pink"] + (255,)
        if cy + 1 < y1:
            px[cx, cy + 1] = mix(palette["pink"], palette["pink_dark"], 0.6) + (255,)


def decorate_inner_ear(px, rect, palette, rng):
    x0, y0, x1, y1 = rect
    for x in range(x0, x1):
        for y in range(y0, y1):
            t = (y - y0) / max(1, (y1 - y0) - 1)
            base = mix(palette["pink"], palette["pink_dark"], 0.25 + 0.5 * t)
            px[x, y] = shade(base, 1.0, rng.uniform(-5, 5)) + (255,)
    for x in range(x0, x1):
        px[x, y0] = mix(px[x, y0][:3], palette["fur_dark"], 0.45) + (255,)


def decorate_eye(px, rect, palette, rng):
    x0, y0, x1, y1 = rect
    top = (96, 66, 46)
    middle = (61, 43, 32)
    bottom = (40, 28, 21)
    glow = (116, 84, 62)
    for x in range(x0, x1):
        for y in range(y0, y1):
            t = (y - y0) / max(1, (y1 - y0) - 1)
            if t < 0.4:
                color = mix(top, middle, t / 0.4)
            else:
                color = mix(middle, bottom, (t - 0.4) / 0.6)
            px[x, y] = shade(color, 1.0, rng.uniform(-4, 4)) + (255,)
    # Grosser Glanzpunkt oben, kleiner Gegen-Glanz unten.
    px[x0, y0] = WHITE + (255,)
    if x1 - x0 >= 4:
        px[x0 + 1, y0] = mix(WHITE, top, 0.35) + (255,)
    px[x1 - 1, y1 - 2] = glow + (255,)
    px[x1 - 2, y1 - 1] = glow + (255,)


def decorate_eyelid(px, rect, palette, rng):
    x0, y0, x1, y1 = rect
    for x in range(x0, x1):
        for y in range(y0, y1):
            px[x, y] = shade(palette["fur_dark"], 1.0, rng.uniform(-5, 5)) + (255,)
    px[x0, y0] = mix(palette["fur_dark"], palette["fur"], 0.5) + (255,)


def decorate_nose(px, faces, palette, rng):
    for face, rect in faces.items():
        x0, y0, x1, y1 = rect
        for x in range(x0, x1):
            for y in range(y0, y1):
                px[x, y] = shade(palette["pink"], FACE_LIGHT.get(face, 1.0),
                                 rng.uniform(-4, 4)) + (255,)
    if "north" in faces:
        x0, y0, x1, y1 = faces["north"]
        for x in range(x0, x1):
            px[x, y1 - 1] = palette["pink_dark"] + (255,)
        px[x0, y0] = mix(palette["pink"], WHITE, 0.55) + (255,)


def decorate_toes(px, faces, palette, rng, cream_tips=False):
    base = mix(palette["fur"], palette["fur_light"], 0.5)
    for face, rect in faces.items():
        paint_soft_face(px, rect, face, base, rng, spread=5)
    if "north" in faces:
        x0, y0, x1, y1 = faces["north"]
        width = x1 - x0
        for frac in (1 / 3, 2 / 3):
            tx = x0 + max(1, min(width - 2, int(width * frac)))
            for y in range(y0, y1):
                px[tx, y] = mix(px[tx, y][:3], palette["fur_dark"], 0.6) + (255,)
    if cream_tips and "up" in faces:
        x0, y0, x1, y1 = faces["up"]
        for x in range(x0 + 1, x1 - 1):
            px[x, y0] = palette["cream"] + (255,)


def decorate_foot(px, faces, palette, rng):
    if "up" in faces:
        x0, y0, x1, y1 = faces["up"]
        for i in range(3):
            tx = x0 + i + (x1 - x0 - 3) // 2
            if x0 <= tx < x1:
                px[tx, y0] = palette["cream"] + (255,)


# ---------------------------------------------------------------------------
# Sheet-Painter
# ---------------------------------------------------------------------------

FUR_BONES = {"body", "head", "earLeft", "earRight", "pawLeft", "pawRight",
             "footLeft", "footRight"}
SPOT_FACES = ("north", "south", "east", "west", "up")


def paint_sheet(geometry, palette, seed):
    description = geometry["description"]
    size = (description["texture_width"], description["texture_height"])
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    px = image.load()
    rng = random.Random(seed)
    spot_targets = []

    for bone in geometry["bones"]:
        name = bone["name"]
        for index, cube in enumerate(bone.get("cubes", [])):
            faces = cube_faces(cube)
            if name in ("eyeLeft", "eyeRight"):
                decorate_eye(px, faces["north"], palette, rng)
                continue
            if name in ("eyelidLeft", "eyelidRight"):
                decorate_eyelid(px, faces["north"], palette, rng)
                continue
            if name == "nose":
                decorate_nose(px, faces, palette, rng)
                continue
            if name == "muzzle":
                decorate_muzzle(px, faces, palette, rng)
                continue
            if name in ("cheekLeft", "cheekRight"):
                decorate_cheek(px, faces, palette, rng)
                continue
            if name == "tail":
                fluff = palette["cream"] if index == 0 else mix(palette["cream"], WHITE, 0.3)
                for face, rect in faces.items():
                    paint_soft_face(px, rect, face, fluff, rng, spread=12)
                continue
            if name == "body" and index == 1:  # Brust-Flausch
                for face, rect in faces.items():
                    paint_soft_face(px, rect, face,
                                    mix(palette["cream"], WHITE, 0.15), rng, spread=8)
                continue
            if name in ("earLeft", "earRight") and index == 1:  # Ohrspitzen-Fluff
                tip = mix(palette["fur"], palette["fur_light"], 0.55)
                for face, rect in faces.items():
                    paint_soft_face(px, rect, face, tip, rng, spread=7)
                continue
            if name in ("earLeft", "earRight") and index == 2:  # Innenohr-Plane
                decorate_inner_ear(px, faces["north"], palette, rng)
                continue
            if name in ("pawLeft", "pawRight", "footLeft", "footRight") and index == 1:
                decorate_toes(px, faces, palette, rng,
                              cream_tips=name.startswith("foot"))
                continue

            # Standard: Fell auf alle Faces, dunklere Unterseite.
            for face, rect in faces.items():
                base = palette["fur_dark"] if face == "down" else palette["fur"]
                paint_fur_face(px, rect, face, base, palette, rng)
                if name in ("body", "head", "earLeft", "earRight") and index == 0 \
                        and face in SPOT_FACES:
                    spot_targets.append(rect)
            if name == "body" and index == 0:
                decorate_body(px, faces, palette, rng)
            if name in ("footLeft", "footRight") and index == 0:
                decorate_foot(px, faces, palette, rng)

    # Echte Flecken zum Schluss ueber das Grundfell wachsen lassen.
    if palette["spots"]:
        weighted = [rect for rect in spot_targets
                    for _ in range(max(1, (rect[2] - rect[0]) * (rect[3] - rect[1]) // 24))]
        for _ in range(9):
            rect = rng.choice(weighted)
            grow_spot(px, rect, rng, palette["spots"], size=rng.randint(7, 16))

    # Dekor, das ueber Flecken liegen muss (Gesicht bleibt sauber lesbar).
    for bone in geometry["bones"]:
        if bone["name"] == "head":
            for cube in bone.get("cubes", []):
                faces = cube_faces(cube)
                if "north" in faces and palette["spots"]:
                    # Frontal keine Flecken ueber Augenpartie: leichte Aufhellung.
                    x0, y0, x1, y1 = faces["north"]
                    for x in range(x0 + 1, x1 - 1):
                        px[x, y0 + 1] = mix(px[x, y0 + 1][:3],
                                            palette["fur_light"], 0.2) + (255,)
    return image


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    adult = load_geo(os.path.join(GEO_DIR, "gooby.geo.json"))
    baby = load_geo(os.path.join(GEO_DIR, "gooby_baby.geo.json"))

    jobs = [
        ("gooby.png", adult, PALETTES["classic"], "gooby:classic:v52"),
        ("gooby_cream.png", adult, PALETTES["cream"], "gooby:cream:v52"),
        ("gooby_cocoa.png", adult, PALETTES["cocoa"], "gooby:cocoa:v52"),
        ("gooby_spotted.png", adult, PALETTES["spotted"], "gooby:spotted:v52"),
        ("gooby_baby.png", baby, baby_palette(), "gooby:baby:v52"),
    ]
    for filename, geometry, palette, seed in jobs:
        image = paint_sheet(geometry, palette, seed)
        image.save(os.path.join(OUT_DIR, filename))
        print(f"gemalt: textures/entity/{filename}")


if __name__ == "__main__":
    main()
