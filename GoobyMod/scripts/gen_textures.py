#!/usr/bin/env python3
"""Erzeugt die Item-/Block-/GUI-Texturen der Gooby Mod (Pillow).

Aufruf:  python3 scripts/gen_textures.py
Schreibt nach src/main/resources/assets/goobymod/textures/.

WICHTIG: Die fuenf Premium-ENTITY-Sheets (textures/entity/*.png) besitzt
seit v5.2 ausschliesslich scripts/gen_entity_textures.py. Dieses Skript
schreibt NIE nach textures/entity/ — ensure() erzwingt das hart. Die
Legacy-Entity-Painter (gen_gooby, Baby-Teil von gen_v38_family_assets)
malen nur noch in den Speicher, damit der geteilte RNG-Strom (Seed 8108)
stabil bleibt und alle uebrigen Texturen byte-identisch reproduzierbar
sind.
"""
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..", "src", "main", "resources", "assets", "goobymod", "textures")

# Farbpalette: braun-beige Fell, rosa Naeschen — NIEDLICH!
FUR = (201, 157, 111)
FUR_LIGHT = (216, 176, 133)
FUR_DARK = (176, 132, 90)
CREAM = (243, 226, 200)
CREAM_DARK = (226, 205, 173)
PINK = (247, 170, 196)
PINK_DARK = (224, 132, 165)
SMILE = (94, 60, 38)
PUPIL = (60, 42, 32)
PUPIL_LIGHT = (110, 80, 60)
WHITE = (255, 255, 255)

rng = random.Random(8108)


def ensure(path):
    # Fail-closed: Entity-Sheets gehoeren gen_entity_textures.py. Ein
    # versehentlich wieder eingebauter Schreibpfad wuerde die Premium-Felle
    # mit Legacy-Art ueberschreiben — deshalb hier hart verweigern.
    normalized = os.path.normpath(os.path.abspath(path))
    entity_dir = os.path.normpath(os.path.abspath(os.path.join(ROOT, "entity")))
    if normalized.startswith(entity_dir + os.sep):
        raise RuntimeError(
            f"gen_textures.py darf keine Entity-Texturen schreiben: {path}\n"
            "Entity-Sheets werden von scripts/gen_entity_textures.py erzeugt.")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def noisy_fill(draw, box, base, spread=7):
    """Fuellt ein Rechteck mit leicht rauschender Fellfarbe."""
    x0, y0, x1, y1 = box
    for x in range(x0, x1):
        for y in range(y0, y1):
            n = rng.randint(-spread, spread)
            draw.point((x, y), fill=(max(0, min(255, base[0] + n)),
                                     max(0, min(255, base[1] + n)),
                                     max(0, min(255, base[2] + n)), 255))


def box_uv(u0, v0, w, h, d):
    """Bedrock-Box-UV: liefert Face-Rechtecke (x0,y0,x1,y1)."""
    return {
        "up": (u0 + d, v0, u0 + d + w, v0 + d),
        "down": (u0 + d + w, v0, u0 + d + 2 * w, v0 + d),
        "east": (u0, v0 + d, u0 + d, v0 + d + h),
        "north": (u0 + d, v0 + d, u0 + d + w, v0 + d + h),
        "west": (u0 + d + w, v0 + d, u0 + d + w + d, v0 + d + h),
        "south": (u0 + 2 * d + w, v0 + d, u0 + 2 * d + 2 * w, v0 + d + h),
    }


def gen_gooby():
    """Legacy-Adult-Painter (altes UV-Layout, Kopf bei (0,25) 11x9x10).

    Schreibt seit v5.2 KEINE Datei mehr: textures/entity/gooby.png kommt aus
    gen_entity_textures.py. Der Malcode laeuft weiter in den Speicher, damit
    der geteilte RNG-Strom fuer die nachfolgenden Item-/Block-Generatoren
    (gen_fluff, gen_gooby_wool, gen_hutch, ...) unveraendert bleibt.
    """
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # --- Koerper (0,0), 14x12x12 ---
    body = box_uv(0, 0, 14, 12, 12)
    for face, box in body.items():
        noisy_fill(d, box, FUR_DARK if face == "down" else FUR)
    # Cremefarbener Bauchfleck vorne
    bx0, by0, bx1, by1 = body["north"]
    d.ellipse((bx0 + 3, by0 + 3, bx1 - 4, by1 - 1), fill=CREAM + (255,))
    for x in range(bx0 + 4, bx1 - 4):
        for y in range(by0 + 4, by1 - 2):
            if rng.random() < 0.25:
                d.point((x, y), fill=CREAM_DARK + (255,))
    # Ruecken: hellere Flausch-Tupfer
    sx0, sy0, sx1, sy1 = body["south"]
    for _ in range(10):
        d.point((rng.randint(sx0 + 1, sx1 - 2), rng.randint(sy0 + 1, sy1 - 2)), fill=FUR_LIGHT + (255,))

    # --- Kopf (0,25), 11x9x10 ---
    head = box_uv(0, 25, 11, 9, 10)
    for face, box in head.items():
        noisy_fill(d, box, FUR_DARK if face == "down" else FUR)
    hx0, hy0, hx1, hy1 = head["north"]  # 11 breit, 9 hoch
    # Cremefarbene Schnauze um die Nase
    d.ellipse((hx0 + 3, hy0 + 3, hx0 + 7, hy0 + 7), fill=CREAM + (255,))
    # PERMANENTES LAECHELN: breiter U-Bogen unter der Nase
    cy = hy0 + 5
    smile_pts = [(hx0 + 2, cy), (hx0 + 3, cy + 1), (hx0 + 4, cy + 2), (hx0 + 5, cy + 2),
                 (hx0 + 6, cy + 2), (hx0 + 7, cy + 1), (hx0 + 8, cy)]
    for p in smile_pts:
        d.point(p, fill=SMILE + (255,))
    # Rosa Wangen-Blush
    d.point((hx0 + 1, hy0 + 5), fill=PINK + (255,))
    d.point((hx0 + 1, hy0 + 6), fill=PINK + (255,))
    d.point((hx0 + 9, hy0 + 5), fill=PINK + (255,))
    d.point((hx0 + 9, hy0 + 6), fill=PINK + (255,))

    # --- Nase (56,0), 2x2x1 — rosa! ---
    nose = box_uv(56, 0, 2, 2, 1)
    for face, box in nose.items():
        d.rectangle((box[0], box[1], box[2] - 1, box[3] - 1), fill=PINK + (255,))
    nx0, ny0, nx1, ny1 = nose["north"]
    d.point((nx0, ny0 + 1), fill=PINK_DARK + (255,))
    d.point((nx0 + 1, ny0 + 1), fill=PINK_DARK + (255,))

    # --- Kulleraugen (Planes): links (44,25) 3x4, rechts (48,25) 3x4 ---
    for ex in (44, 48):
        d.rectangle((ex, 25, ex + 2, 28), fill=PUPIL + (255,))
        d.point((ex, 25), fill=WHITE + (255,))          # grosser Glanzpunkt
        d.point((ex + 2, 27), fill=PUPIL_LIGHT + (255,))  # kleiner Glanzpunkt
        d.point((ex + 1, 28), fill=PUPIL_LIGHT + (255,))
    # Geschlossene und halb geschlossene Lid-Zeilen fuer die Eyelid-Planes.
    for ex in (52, 56):
        d.line((ex, 25, ex + 2, 25), fill=FUR_DARK + (255,))
        d.line((ex, 27, ex + 2, 27), fill=FUR + (255,))
        d.point((ex + 1, 27), fill=PUPIL + (255,))

    # --- Ohren: links (42,30), rechts (0,44), je 4x10x2 ---
    for u0, v0 in ((42, 30), (0, 44)):
        ear = box_uv(u0, v0, 4, 10, 2)
        for face, box in ear.items():
            noisy_fill(d, box, FUR)
        ex0, ey0, ex1, ey1 = ear["north"]
        # Inneres Ohr rosa
        d.rectangle((ex0 + 1, ey0 + 1, ex1 - 2, ey1 - 3), fill=PINK + (255,))
        d.rectangle((ex0 + 1, ey0 + 2, ex1 - 2, ey1 - 5), fill=PINK_DARK + (255,))

    # --- Puschel-Schwanz (14,44), 4x4x3 — cremeweiss und fluffig ---
    tail = box_uv(14, 44, 4, 4, 3)
    for face, box in tail.items():
        noisy_fill(d, box, CREAM, spread=12)

    # --- Vorderpfoten (30,44) und (44,44), je 3x4x3 ---
    for u0, v0 in ((30, 44), (44, 44)):
        paw = box_uv(u0, v0, 3, 4, 3)
        for face, box in paw.items():
            noisy_fill(d, paw[face], FUR)
        px0, py0, px1, py1 = paw["north"]
        d.point((px0 + 1, py1 - 1), fill=FUR_DARK + (255,))  # Zehen-Andeutung

    # --- Fuesse (14,55) und (38,55), je 4x2x7 ---
    for u0, v0 in ((14, 55), (38, 55)):
        foot = box_uv(u0, v0, 4, 2, 7)
        for face, box in foot.items():
            noisy_fill(d, box, FUR)
        fx0, fy0, fx1, fy1 = foot["up"]
        # Cremefarbene Zehen vorne
        for i in range(3):
            d.point((fx0 + i + (fx1 - fx0 - 3) // 2, fy0), fill=CREAM + (255,))

    # BEWUSST KEIN save(): das Premium-Sheet gehoert gen_entity_textures.py.
    del img


def gen_nutella_item():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (60, 40, 28, 255)
    lid = (240, 235, 225, 255)
    lid_dark = (205, 198, 185, 255)
    choco = (95, 58, 33, 255)
    choco_dark = (74, 44, 24, 255)
    label = (250, 244, 232, 255)
    # Deckel
    d.rectangle((4, 2, 11, 4), fill=lid, outline=outline)
    d.line((5, 3, 10, 3), fill=lid_dark)
    # Glas-Korpus mit Schokocreme
    d.rectangle((3, 5, 12, 14), fill=choco, outline=outline)
    d.line((4, 6, 4, 13), fill=choco_dark)
    d.line((11, 6, 11, 13), fill=(133, 88, 55, 255))
    # Etikett mit Herzchen
    d.rectangle((5, 8, 10, 12), fill=label)
    d.point((7, 9), fill=(226, 80, 100, 255))
    d.point((8, 9), fill=(226, 80, 100, 255))
    d.point((7, 10), fill=(226, 80, 100, 255))
    d.point((8, 10), fill=(226, 80, 100, 255))
    d.point((7, 11), fill=(226, 80, 100, 255))
    img.save(ensure(os.path.join(ROOT, "item", "nutella.png")))


def gen_brush():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    wood = (146, 104, 62, 255)
    wood_dark = (114, 80, 46, 255)
    # Diagonaler Holzgriff
    for i in range(7):
        d.point((3 + i, 12 - i), fill=wood)
        d.point((4 + i, 12 - i), fill=wood)
        d.point((3 + i, 13 - i), fill=wood_dark)
    # Rosa Buerstenkopf
    d.ellipse((8, 2, 14, 7), fill=(247, 170, 196, 255), outline=(224, 132, 165, 255))
    for x, y in ((9, 3), (11, 3), (13, 4), (10, 5), (12, 5)):
        d.point((x, y), fill=(255, 210, 225, 255))
    img.save(ensure(os.path.join(ROOT, "item", "gooby_brush.png")))


def gen_fluff():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((3, 4, 12, 12), fill=CREAM + (255,))
    for _ in range(26):
        x, y = rng.randint(3, 12), rng.randint(4, 12)
        if ((x - 7.5) ** 2 + (y - 8) ** 2) < 22:
            d.point((x, y), fill=(CREAM_DARK if rng.random() < 0.5 else WHITE) + (255,))
    # Kleine abstehende Flusen
    for x, y in ((2, 6), (13, 7), (6, 3), (10, 13), (4, 12)):
        d.point((x, y), fill=CREAM + (255,))
    img.save(ensure(os.path.join(ROOT, "item", "gooby_fluff.png")))


def gen_gooby_wool():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    noisy_fill(d, (0, 0, 16, 16), CREAM, spread=9)
    # Weiche Wirbel
    for cx, cy in ((4, 4), (11, 6), (6, 11), (13, 13)):
        d.arc((cx - 2, cy - 2, cx + 2, cy + 2), 0, 270, fill=CREAM_DARK + (255,))
    for _ in range(8):
        d.point((rng.randint(0, 15), rng.randint(0, 15)), fill=WHITE + (255,))
    img.save(ensure(os.path.join(ROOT, "block", "gooby_wool.png")))


def _planks(d, highlight=False):
    wood = (156, 116, 72, 255)
    seam = (108, 76, 44, 255)
    noisy_fill(d, (0, 0, 16, 16), wood[:3], spread=6)
    for y in (3, 7, 11, 15):
        d.line((0, y, 15, y), fill=seam)
    for x, y in ((2, 1), (13, 5), (5, 9), (10, 13)):
        d.point((x, y), fill=seam)


def gen_hutch():
    # Seite
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    _planks(d)
    img.save(ensure(os.path.join(ROOT, "block", "rabbit_hutch_side.png")))
    # Front mit Eingangs-Torbogen + Herz
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    _planks(d)
    dark = (44, 30, 20, 255)
    d.rectangle((5, 9, 10, 15), fill=dark)
    d.rectangle((6, 7, 9, 9), fill=dark)
    d.point((5, 8), fill=dark)
    d.point((10, 8), fill=dark)
    heart = (226, 80, 100, 255)
    d.point((6, 4), fill=heart)
    d.point((8, 4), fill=heart)
    d.point((6, 5), fill=heart)
    d.point((7, 5), fill=heart)
    d.point((8, 5), fill=heart)
    d.point((7, 6), fill=heart)
    img.save(ensure(os.path.join(ROOT, "block", "rabbit_hutch_front.png")))
    # Dach: Stroh
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    noisy_fill(d, (0, 0, 16, 16), (196, 164, 84), spread=12)
    for x in (2, 5, 8, 11, 14):
        d.line((x, 0, x, 15), fill=(160, 130, 58, 255))
    img.save(ensure(os.path.join(ROOT, "block", "rabbit_hutch_top.png")))


def gen_v37_hutch_layers():
    """Hutch 2.0 interior, fixed nameplate, and three comfort overlays."""
    interior = Image.new("RGBA", (16, 16), (73, 49, 31, 255))
    d = ImageDraw.Draw(interior)
    for y in (3, 7, 11, 15):
        d.line((0, y, 15, y), fill=(49, 32, 22, 255))
    d.rectangle((3, 3, 12, 12), outline=(105, 72, 43, 255))
    interior.save(ensure(os.path.join(ROOT, "block", "rabbit_hutch_interior.png")))

    plate = Image.new("RGBA", (16, 16), (185, 139, 80, 255))
    d = ImageDraw.Draw(plate)
    d.rectangle((0, 0, 15, 15), outline=(82, 53, 29, 255), width=2)
    d.rectangle((2, 2, 13, 13), outline=(221, 180, 112, 255))
    for x, y in ((4, 4), (11, 4), (4, 11), (11, 11)):
        d.point((x, y), fill=(73, 45, 25, 255))
    plate.save(ensure(os.path.join(ROOT, "block", "rabbit_hutch_nameplate.png")))

    palettes = (
        ((218, 202, 176, 255), (176, 151, 119, 255), (239, 228, 207, 255)),
        ((235, 177, 190, 255), (192, 126, 148, 255), (251, 215, 222, 255)),
        ((244, 195, 94, 255), (194, 138, 45, 255), (255, 231, 153, 255)),
    )
    for level, (base, seam, shine) in enumerate(palettes, start=1):
        bedding = Image.new("RGBA", (16, 16), base)
        d = ImageDraw.Draw(bedding)
        for y in (3, 7, 11, 15):
            d.line((0, y, 15, y), fill=seam)
        for x, y in ((2, 2), (8, 5), (13, 9), (5, 13)):
            d.point((x, y), fill=shine)
        bedding.save(ensure(os.path.join(
            ROOT, "block", f"rabbit_hutch_bedding_{level}.png")))


def gen_jar_block():
    # Seite: oben Deckel-Streifen, unten Glas mit Schoko
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lid = (240, 235, 225, 255)
    lid_dark = (205, 198, 185, 255)
    d.rectangle((0, 2, 15, 4), fill=lid)
    d.line((0, 3, 15, 3), fill=lid_dark)
    glass = (210, 225, 230, 255)
    choco = (95, 58, 33, 255)
    d.rectangle((5, 11, 10, 15), fill=choco)
    d.rectangle((5, 11, 10, 11), fill=(133, 88, 55, 255))
    d.line((5, 11, 5, 15), fill=glass)
    d.line((10, 11, 10, 15), fill=glass)
    # Mini-Etikett
    d.rectangle((6, 12, 9, 14), fill=(250, 244, 232, 255))
    d.point((7, 13), fill=(226, 80, 100, 255))
    d.point((8, 13), fill=(226, 80, 100, 255))
    img.save(ensure(os.path.join(ROOT, "block", "nutella_jar_side.png")))
    # Deckel oben mit Ring
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 15, 15), fill=lid)
    d.ellipse((5, 5, 10, 10), outline=lid_dark)
    d.ellipse((3, 3, 12, 12), outline=(222, 215, 202, 255))
    img.save(ensure(os.path.join(ROOT, "block", "nutella_jar_top.png")))


def gen_zzz():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    z = (255, 255, 255, 255)
    shadow = (90, 70, 120, 255)
    # Grosses Z (mit Schatten fuer Lesbarkeit)
    pts = []
    for x in range(3, 13):
        pts.append((x, 3))
        pts.append((x, 12))
    for i in range(8):
        pts.append((11 - i, 4 + i))
    for x, y in pts:
        d.point((x + 1, y + 1), fill=shadow)
    for x, y in pts:
        d.point((x, y), fill=z)
    img.save(ensure(os.path.join(ROOT, "particle", "zzz.png")))


def gen_heart_gold():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (143, 88, 18, 255)
    gold = (255, 196, 48, 255)
    shine = (255, 244, 168, 255)
    d.polygon([(2, 5), (4, 2), (7, 2), (8, 4), (9, 2), (12, 2),
               (14, 5), (14, 8), (8, 14), (2, 8)], fill=outline)
    d.polygon([(3, 5), (5, 3), (7, 3), (8, 5), (9, 3), (11, 3),
               (13, 5), (13, 7), (8, 12), (3, 7)], fill=gold)
    d.rectangle((5, 4, 6, 5), fill=shine)
    d.point((4, 6), fill=shine)
    img.save(ensure(os.path.join(ROOT, "particle", "heart_gold.png")))


def gen_v36_training_items():
    treat = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(treat)
    d.ellipse((2, 4, 13, 13), fill=(98, 57, 34, 255), outline=(64, 39, 27, 255), width=2)
    d.ellipse((4, 5, 11, 11), fill=(177, 108, 56, 255))
    for x, y in ((5, 7), (8, 6), (10, 9), (6, 10)):
        d.point((x, y), fill=(245, 223, 172, 255))
    d.rectangle((6, 2, 9, 4), fill=(243, 226, 200, 255))
    treat.save(ensure(os.path.join(ROOT, "item", "training_treat.png")))

    book = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(book)
    d.rounded_rectangle((2, 2, 13, 14), radius=2, fill=(141, 91, 55, 255),
                        outline=(74, 48, 33, 255), width=2)
    d.rectangle((4, 3, 11, 12), fill=(243, 226, 200, 255))
    d.line((4, 4, 4, 12), fill=(201, 157, 111, 255), width=2)
    d.ellipse((6, 5, 10, 9), fill=(247, 170, 196, 255))
    d.point((7, 6), fill=(255, 255, 255, 255))
    book.save(ensure(os.path.join(ROOT, "item", "gooby_handbook.png")))


def _soften(color):
    """Aufgehellte Baby-Variante einer Adult-Fellfarbe."""
    return (min(255, int(color[0] * 0.82 + 52)),
            min(255, int(color[1] * 0.84 + 45)),
            min(255, int(color[2] * 0.88 + 35)))


def _fill_box_uv(d, u0, v0, w, h, depth, base, dark, spread=7):
    """Fuellt alle sechs Faces einer Box-UV; nicht-ganzzahlige Boxen werden
    nach aussen gerundet, damit keine transparenten Saumpixel bleiben."""
    import math
    for face, box in box_uv(u0, v0, w, h, depth).items():
        x0, y0, x1, y1 = (math.floor(box[0]), math.floor(box[1]),
                          math.ceil(box[2]), math.ceil(box[3]))
        if x1 <= x0 or y1 <= y0:
            continue
        noisy_fill(d, (x0, y0, min(x1, 64), min(y1, 64)),
                   dark if face == "down" else base, spread=spread)


def gen_v38_family_assets():
    """Nutella-Kuchen-Deckel; der Legacy-Baby-Painter malt nur noch in den
    Speicher (RNG-Strom-Stabilitaet) — textures/entity/gooby_baby.png kommt
    seit v5.2 aus gen_entity_textures.py."""
    baby = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(baby)
    fur = _soften(FUR)
    fur_dark = _soften(FUR_DARK)
    fur_light = _soften(FUR_LIGHT)
    cream = _soften(CREAM)

    # Koerper (0,0) 12x10x10 mit Bauchfleck vorne
    _fill_box_uv(d, 0, 0, 12, 10, 10, fur, fur_dark)
    body = box_uv(0, 0, 12, 10, 10)
    bx0, by0, bx1, by1 = body["north"]
    d.ellipse((bx0 + 2, by0 + 2, bx1 - 3, by1 - 1), fill=cream + (255,))

    # Kopf (0,23) 14x12x13 mit Schnauze, Laecheln und Blush
    _fill_box_uv(d, 0, 23, 14, 12, 13, fur, fur_dark)
    head = box_uv(0, 23, 14, 12, 13)
    hx0, hy0, hx1, hy1 = head["north"]
    d.ellipse((hx0 + 4, hy0 + 4, hx0 + 9, hy0 + 9), fill=cream + (255,))
    cy = hy0 + 7
    for p in ((hx0 + 3, cy), (hx0 + 4, cy + 1), (hx0 + 5, cy + 2), (hx0 + 6, cy + 2),
              (hx0 + 7, cy + 2), (hx0 + 8, cy + 1), (hx0 + 9, cy)):
        d.point(p, fill=SMILE + (255,))
    for px, py in ((hx0 + 1, hy0 + 6), (hx0 + 1, hy0 + 7),
                   (hx0 + 12, hy0 + 6), (hx0 + 12, hy0 + 7)):
        d.point((px, py), fill=PINK + (255,))
    sx0, sy0, sx1, sy1 = head["south"]
    for _ in range(8):
        d.point((rng.randint(sx0 + 1, sx1 - 2), rng.randint(sy0 + 1, sy1 - 2)),
                fill=fur_light + (255,))

    # Nase (56,0) 2x2x1 — rosa
    for face, box in box_uv(56, 0, 2, 2, 1).items():
        d.rectangle((box[0], box[1], box[2] - 1, box[3] - 1), fill=PINK + (255,))
    nx0, ny0, nx1, ny1 = box_uv(56, 0, 2, 2, 1)["north"]
    d.point((nx0, ny0 + 1), fill=PINK_DARK + (255,))
    d.point((nx0 + 1, ny0 + 1), fill=PINK_DARK + (255,))

    # Ohren: links (44,0), rechts (0,48), je 3x8x2 mit rosa Innenohr
    for u0, v0 in ((44, 0), (0, 48)):
        _fill_box_uv(d, u0, v0, 3, 8, 2, fur, fur_dark)
        ex0, ey0, ex1, ey1 = box_uv(u0, v0, 3, 8, 2)["north"]
        d.rectangle((ex0 + 1, ey0 + 1, ex1 - 2, ey1 - 3), fill=PINK + (255,))
        d.rectangle((ex0 + 1, ey0 + 2, ex1 - 2, ey1 - 5), fill=PINK_DARK + (255,))

    # Puschel-Schwanz (14,48) 4x4x3 — cremeweiss
    _fill_box_uv(d, 14, 48, 4, 4, 3, cream, cream, spread=12)

    # Vorderpfoten (30,48) und (42,48), je 2.5x3x3
    for u0 in (30, 42):
        _fill_box_uv(d, u0, 48, 2.5, 3, 3, fur, fur_dark)
        px0, py0, px1, py1 = box_uv(u0, 48, 2.5, 3, 3)["north"]
        d.point((int(px0) + 1, int(py1) - 1), fill=fur_dark + (255,))

    # Fuesse (14,56) und (38,56), je 3.5x1.5x6 mit Creme-Zehen
    for u0 in (14, 38):
        _fill_box_uv(d, u0, 56, 3.5, 1.5, 6, fur, fur_dark)
        fx0, fy0, fx1, fy1 = box_uv(u0, 56, 3.5, 1.5, 6)["up"]
        for i in range(2):
            d.point((int(fx0) + 1 + i, int(fy0)), fill=cream + (255,))

    # Riesige Kulleraugen (44,24)/(49,24) und Lid-Zeilen (44,30)/(49,30)
    for ex in (44, 49):
        d.rounded_rectangle((ex, 24, ex + 3, 28), radius=1, fill=PUPIL + (255,))
        d.rectangle((ex, 24, ex + 1, 25), fill=WHITE + (255,))
        d.point((ex + 3, 27), fill=PUPIL_LIGHT + (255,))
    d.line((44, 30, 47, 30), fill=fur_dark + (255,))
    d.line((49, 30, 52, 30), fill=fur_dark + (255,))
    # BEWUSST KEIN save(): das Premium-Sheet gehoert gen_entity_textures.py.
    del baby

    cake = Image.new("RGBA", (16, 16), (246, 224, 194, 255))
    d = ImageDraw.Draw(cake)
    chocolate = (105, 62, 35, 255)
    chocolate_light = (151, 91, 50, 255)
    cream = (255, 244, 220, 255)
    d.rectangle((0, 0, 15, 15), fill=(238, 210, 174, 255))
    d.ellipse((1, 1, 14, 14), fill=chocolate, outline=(72, 43, 28, 255))
    d.arc((3, 3, 12, 12), 20, 300, fill=chocolate_light, width=2)
    d.arc((5, 5, 10, 10), 180, 520, fill=cream, width=2)
    for x, y in ((4, 3), (11, 5), (3, 10), (9, 12)):
        d.point((x, y), fill=(247, 170, 196, 255))
    cake.save(ensure(os.path.join(ROOT, "block", "nutella_cake_top.png")))


def gen_v39_fashion_assets():
    """Tint-ready wardrobe sprites (Schal, Fliege, Tasche, Shimmer-Fluff).

    Die frueher hier abgeleiteten Coat-Recolors (gooby_cream/cocoa/spotted)
    entstehen seit v5.2 direkt in gen_entity_textures.py."""
    scarf = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(scarf)
    d.rectangle((2, 3, 13, 10), fill=(210, 210, 210, 255), outline=(75, 75, 75, 255))
    d.rectangle((6, 9, 9, 14), fill=(190, 190, 190, 255), outline=(75, 75, 75, 255))
    for y in (5, 8):
        d.line((3, y, 12, y), fill=(238, 238, 238, 255))
    scarf.save(ensure(os.path.join(ROOT, "item", "gooby_scarf.png")))

    bowtie = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(bowtie)
    d.polygon([(1, 4), (7, 7), (7, 9), (1, 12)], fill=(142, 35, 64, 255),
              outline=(75, 27, 42, 255))
    d.polygon([(15, 4), (9, 7), (9, 9), (15, 12)], fill=(142, 35, 64, 255),
              outline=(75, 27, 42, 255))
    d.rectangle((6, 6, 10, 10), fill=(215, 74, 110, 255), outline=(75, 27, 42, 255))
    bowtie.save(ensure(os.path.join(ROOT, "item", "gooby_bowtie.png")))

    satchel = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(satchel)
    d.rounded_rectangle((2, 3, 13, 14), radius=2, fill=(139, 87, 50, 255),
                        outline=(67, 42, 27, 255), width=2)
    d.arc((4, 0, 11, 8), 180, 360, fill=(91, 57, 34, 255), width=2)
    d.rectangle((6, 8, 9, 11), fill=(225, 176, 79, 255), outline=(91, 57, 34, 255))
    satchel.save(ensure(os.path.join(ROOT, "item", "tiny_satchel.png")))

    shimmer = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(shimmer)
    d.ellipse((3, 4, 12, 12), fill=(242, 224, 181, 255), outline=(170, 126, 50, 255))
    for x, y in ((2, 7), (5, 3), (12, 5), (13, 10), (8, 13)):
        d.polygon([(x, y - 1), (x + 1, y), (x, y + 1), (x - 1, y)],
                  fill=(255, 247, 151, 255))
    shimmer.save(ensure(os.path.join(ROOT, "item", "shimmer_fluff.png")))


def gen_v40_create_assets():
    """Transparent empty vessel used by Create Spout processing."""
    jar = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(jar)
    outline = (70, 72, 78, 255)
    glass = (180, 221, 235, 115)
    shine = (238, 250, 255, 220)
    d.rectangle((4, 2, 11, 4), fill=(220, 222, 220, 255), outline=outline)
    d.rectangle((3, 5, 12, 14), fill=glass, outline=outline)
    d.line((5, 6, 5, 12), fill=shine)
    d.line((6, 13, 10, 13), fill=(138, 183, 201, 180))
    d.rectangle((5, 8, 10, 11), fill=(246, 241, 226, 210))
    d.point((7, 9), fill=(226, 80, 100, 255))
    d.point((8, 9), fill=(226, 80, 100, 255))
    d.point((7, 10), fill=(226, 80, 100, 255))
    d.point((8, 10), fill=(226, 80, 100, 255))
    jar.save(ensure(os.path.join(ROOT, "item", "empty_jar.png")))


def gen_v41_wild_assets():
    """A small dirt decal and readable four-toed paw-print particle."""
    dirt = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(dirt)
    d.ellipse((1, 3, 14, 13), fill=(91, 57, 34, 210))
    d.ellipse((3, 5, 12, 12), fill=(118, 76, 43, 235))
    for x, y, color in ((4, 6, (151, 102, 57, 255)), (11, 8, (74, 45, 29, 255)),
                        (7, 11, (82, 49, 30, 255)), (9, 5, (171, 119, 68, 255))):
        d.rectangle((x, y, x + 1, y + 1), fill=color)
    dirt.save(ensure(os.path.join(ROOT, "block", "dug_dirt.png")))

    paw = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(paw)
    mark = (78, 54, 37, 210)
    d.ellipse((5, 7, 11, 13), fill=mark)
    d.ellipse((2, 4, 5, 8), fill=mark)
    d.ellipse((5, 2, 8, 6), fill=mark)
    d.ellipse((9, 2, 12, 6), fill=mark)
    d.ellipse((12, 4, 15, 8), fill=mark)
    paw.save(ensure(os.path.join(ROOT, "particle", "paw_print.png")))


def gen_v42_icon_font():
    """Four crisp 8×8 bubble glyphs: heart, Nutella, sleep, and alarm."""
    atlas = Image.new("RGBA", (32, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(atlas)
    # Heart
    d.polygon([(1, 2), (2, 1), (4, 2), (6, 1), (7, 2), (7, 4), (4, 7), (1, 4)],
              fill=(230, 75, 112, 255))
    # Nutella jar
    d.rectangle((10, 1, 14, 2), fill=(225, 225, 216, 255))
    d.rectangle((9, 3, 15, 7), fill=(112, 68, 39, 255), outline=(64, 42, 29, 255))
    d.rectangle((11, 4, 13, 6), fill=(250, 236, 211, 255))
    # Zzz
    d.line((17, 1, 22, 1), fill=(126, 103, 190, 255), width=1)
    d.line((22, 1, 17, 6), fill=(126, 103, 190, 255), width=1)
    d.line((17, 6, 22, 6), fill=(126, 103, 190, 255), width=1)
    # Alarm
    d.polygon([(27, 1), (31, 7), (23, 7)], fill=(246, 193, 58, 255),
              outline=(120, 75, 25, 255))
    d.line((27, 3, 27, 5), fill=(92, 53, 24, 255))
    d.point((27, 6), fill=(92, 53, 24, 255))
    atlas.save(ensure(os.path.join(ROOT, "font", "icons.png")))


def gen_v43_treasure_assets():
    """Map scraps, restored map, and a compact four-slot satchel panel."""
    scrap = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(scrap)
    d.polygon([(2, 2), (13, 3), (12, 13), (8, 12), (5, 14), (2, 11)],
              fill=(225, 204, 155, 255), outline=(91, 62, 38, 255))
    d.line((5, 6, 10, 5), fill=(132, 92, 55, 255))
    d.line((6, 9, 11, 8), fill=(132, 92, 55, 255))
    d.point((9, 10), fill=(196, 54, 64, 255))
    scrap.save(ensure(os.path.join(ROOT, "item", "torn_map_scrap.png")))

    treasure_map = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(treasure_map)
    d.polygon([(2, 1), (13, 2), (14, 13), (8, 14), (2, 12)],
              fill=(229, 211, 166, 255), outline=(78, 55, 34, 255))
    d.line((4, 4, 7, 7, 10, 5, 12, 8), fill=(77, 133, 92, 255))
    d.line((5, 11, 11, 5), fill=(181, 48, 54, 255), width=2)
    d.line((5, 5, 11, 11), fill=(181, 48, 54, 255), width=2)
    treasure_map.save(ensure(os.path.join(ROOT, "item", "gooby_treasure_map.png")))

    gui = Image.new("RGBA", (176, 143), (0, 0, 0, 0))
    d = ImageDraw.Draw(gui)
    d.rounded_rectangle((0, 0, 175, 142), radius=8, fill=(225, 193, 145, 255),
                        outline=(73, 48, 31, 255), width=3)
    d.rectangle((5, 46, 170, 138), fill=(199, 158, 109, 255),
                outline=(101, 65, 38, 255))
    for slot in range(4):
        x = 52 + slot * 18
        d.rectangle((x, 23, x + 17, 40), fill=(82, 52, 34, 255))
        d.rectangle((x + 1, 24, x + 16, 39), fill=(238, 216, 181, 255))
    # Vanilla-compatible player inventory slot grid.
    for row in range(3):
        for column in range(9):
            x, y = 7 + column * 18, 60 + row * 18
            d.rectangle((x, y, x + 17, y + 17), fill=(92, 59, 37, 255))
            d.rectangle((x + 1, y + 1, x + 16, y + 16), fill=(218, 185, 139, 255))
    for column in range(9):
        x, y = 7 + column * 18, 118
        d.rectangle((x, y, x + 17, y + 17), fill=(92, 59, 37, 255))
        d.rectangle((x + 1, y + 1, x + 16, y + 16), fill=(218, 185, 139, 255))
    gui.save(ensure(os.path.join(ROOT, "gui", "gooby_satchel.png")))


def gen_v50_handbook_assets():
    """Twelve compact illustrations for the paged LTS handbook screen."""
    handbook = os.path.join(ROOT, "gui", "handbook")
    for frame in range(4):
        image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        d = ImageDraw.Draw(image)
        bounce = (0, 1, 2, 1)[frame]
        d.ellipse((9, 25 - bounce, 55, 58 - bounce), fill=FUR + (255,),
                  outline=FUR_DARK + (255,), width=2)
        d.ellipse((17, 8 - bounce, 28, 35 - bounce), fill=FUR + (255,),
                  outline=FUR_DARK + (255,))
        d.ellipse((37, 8 - bounce, 48, 35 - bounce), fill=FUR + (255,),
                  outline=FUR_DARK + (255,))
        d.ellipse((17, 28 - bounce, 48, 54 - bounce), fill=FUR_LIGHT + (255,))
        eye_y = 36 - bounce if frame != 2 else 38 - bounce
        d.rectangle((25, eye_y, 27, eye_y + (0 if frame == 2 else 3)), fill=PUPIL + (255,))
        d.rectangle((39, eye_y, 41, eye_y + (0 if frame == 2 else 3)), fill=PUPIL + (255,))
        d.rectangle((32, 42 - bounce, 35, 44 - bounce), fill=PINK + (255,))
        d.arc((29, 42 - bounce, 38, 50 - bounce), 15, 165, fill=SMILE + (255,), width=2)
        image.save(ensure(os.path.join(handbook, f"portrait_{frame}.png")))

    colors = (
        (226, 80, 100, 255), (122, 85, 58, 255), (238, 177, 65, 255),
        (96, 155, 93, 255), (106, 139, 191, 255), (181, 114, 174, 255),
        (219, 149, 75, 255), (119, 100, 176, 255),
    )
    for chapter, color in enumerate(colors):
        image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        d = ImageDraw.Draw(image)
        d.rounded_rectangle((1, 1, 22, 22), radius=5, fill=(255, 244, 220, 255),
                            outline=(94, 60, 38, 255), width=2)
        if chapter == 0:
            d.ellipse((6, 6, 17, 17), fill=color)
        elif chapter == 1:
            d.polygon([(12, 4), (15, 9), (21, 10), (16, 14), (18, 20),
                       (12, 17), (6, 20), (8, 14), (3, 10), (9, 9)], fill=color)
        elif chapter == 2:
            d.arc((4, 5, 20, 19), 195, 345, fill=color, width=4)
        elif chapter == 3:
            d.rectangle((5, 7, 18, 18), fill=color)
            d.rectangle((8, 4, 15, 8), fill=(255, 244, 220, 255), outline=color)
        elif chapter == 4:
            d.ellipse((4, 8, 19, 19), fill=color)
            d.ellipse((8, 4, 15, 11), fill=(255, 244, 220, 255), outline=color)
        elif chapter == 5:
            d.polygon([(4, 17), (7, 7), (12, 4), (17, 7), (20, 17)], fill=color)
        elif chapter == 6:
            d.rectangle((5, 5, 18, 18), outline=color, width=3)
            d.line((7, 16, 16, 7), fill=color, width=2)
        else:
            d.polygon([(12, 3), (15, 9), (21, 12), (15, 15),
                       (12, 21), (9, 15), (3, 12), (9, 9)], fill=color)
        image.save(ensure(os.path.join(handbook, f"chapter_{chapter}.png")))


def gen_v52_content_wave():
    """Content-Wave v5.2: Nutella-Toast, Knopfauge, Gooby-Pluesch & -Statue.

    Nutzt einen EIGENEN Seed, damit die Ausgabe unabhaengig von der
    Aufrufreihenfolge der uebrigen Generatoren reproduzierbar bleibt.
    Es werden ausschliesslich neue Item-/Block-Texturen geschrieben.
    """
    wave_rng = random.Random(5215)

    def wave_noise(draw, box, base, spread=7):
        x0, y0, x1, y1 = box
        for x in range(x0, x1):
            for y in range(y0, y1):
                n = wave_rng.randint(-spread, spread)
                draw.point((x, y), fill=(max(0, min(255, base[0] + n)),
                                         max(0, min(255, base[1] + n)),
                                         max(0, min(255, base[2] + n)), 255))

    # --- Nutella-Toast (Item): Kruste, Krume, Schokoschicht mit Wirbeln ---
    toast = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(toast)
    crust = (166, 110, 58)
    crust_dark = (128, 80, 40)
    crumb = (238, 214, 166)
    choco = (95, 58, 33)
    choco_light = (133, 88, 55)
    choco_dark = (70, 42, 24)
    # Scheibenform: zwei Schultern oben + Korpus
    d.ellipse((2, 1, 8, 7), fill=crust)
    d.ellipse((7, 1, 13, 7), fill=crust)
    d.rectangle((2, 4, 13, 14), fill=crust)
    # Krume innen (mit leichtem Rauschen)
    d.ellipse((3, 2, 7, 6), fill=crumb)
    d.ellipse((8, 2, 12, 6), fill=crumb)
    wave_noise(d, (3, 4, 13, 14), crumb, spread=6)
    # Krusten-Schattenkante rechts/unten
    d.line((13, 5, 13, 14), fill=crust_dark)
    d.line((3, 14, 13, 14), fill=crust_dark)
    # Dicke Nutella-Schicht mit Wirbeln, Nuss-Stueckchen und Tropfnase
    d.rounded_rectangle((4, 5, 11, 12), radius=2, fill=choco)
    d.rectangle((5, 12, 6, 13), fill=choco)  # Tropfen
    d.point((5, 14), fill=choco_dark)
    d.arc((5, 6, 10, 11), 200, 80, fill=choco_light)
    d.arc((6, 7, 9, 10), 0, 250, fill=choco_light)
    for x, y in ((5, 10), (9, 6), (10, 11)):
        d.point((x, y), fill=choco_dark)  # Haselnuss-Stueckchen
    d.point((6, 6), fill=(205, 160, 110, 255))  # Glanzlicht
    d.point((7, 6), fill=(178, 130, 88, 255))
    toast.save(ensure(os.path.join(ROOT, "item", "nutella_toast.png")))

    # --- Knopfauge (Item): Bernstein-Knopf mit Fadenkreuz und 4 Loechern ---
    button = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(button)
    d.ellipse((4, 4, 13, 13), fill=(60, 40, 20, 110))  # weicher Schatten
    outline = (92, 58, 20, 255)
    d.ellipse((3, 3, 12, 12), fill=(222, 160, 64, 255), outline=outline)
    # Radiale Schattierung: oben-links heller, unten-rechts dunkler
    for x in range(4, 12):
        for y in range(4, 12):
            dx, dy = x - 7.5, y - 7.5
            if dx * dx + dy * dy > 17:
                continue
            shade = (x - 4) + (y - 4) + wave_rng.randint(-1, 1)
            if shade <= 4:
                d.point((x, y), fill=(240, 196, 110, 255))
            elif shade >= 11:
                d.point((x, y), fill=(190, 126, 40, 255))
    # Vier Faden-Loecher plus X-Vernaehung
    thread = (121, 85, 58, 255)
    d.line((6, 6, 9, 9), fill=thread)
    d.line((9, 6, 6, 9), fill=thread)
    for hx, hy in ((6, 6), (9, 6), (6, 9), (9, 9)):
        d.point((hx, hy), fill=(60, 38, 16, 255))
    # Glanzbogen oben links
    d.point((5, 4), fill=(255, 236, 190, 255))
    d.point((4, 5), fill=(255, 236, 190, 255))
    d.point((6, 4), fill=(248, 214, 150, 255))
    button.save(ensure(os.path.join(ROOT, "item", "button_eye.png")))

    # --- Pluesch: Fell mit Naehten und Flauschtupfern ---
    fur = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(fur)
    wave_noise(d, (0, 0, 16, 16), FUR)
    for y in (5, 11):  # gestrichelte Quernaehte
        for x in range(0, 16, 3):
            d.point((x, y), fill=FUR_DARK + (255,))
            d.point((x + 1, y), fill=FUR_DARK + (255,))
    for _ in range(9):
        d.point((wave_rng.randint(0, 15), wave_rng.randint(0, 15)),
                fill=FUR_LIGHT + (255,))
    for x, y in ((2, 2), (13, 8), (7, 14)):  # einzelne Stichkreuze
        d.point((x, y), fill=FUR_DARK + (255,))
        d.point((x + 1, y + 1), fill=FUR_DARK + (255,))
    fur.save(ensure(os.path.join(ROOT, "block", "gooby_plushie_fur.png")))

    # --- Pluesch: Bauch in Creme mit Stichkreuzen und Herz-Applikation ---
    belly = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(belly)
    wave_noise(d, (0, 0, 16, 16), CREAM, spread=9)
    for x, y in ((3, 4), (12, 5), (4, 12), (11, 13), (8, 3)):
        d.line((x - 1, y, x + 1, y), fill=CREAM_DARK + (255,))
        d.line((x, y - 1, x, y + 1), fill=CREAM_DARK + (255,))
    heart = (247, 170, 196, 255)
    for x, y in ((7, 7), (9, 7), (6, 8), (7, 8), (8, 8), (9, 8),
                 (10, 8), (7, 9), (8, 9), (9, 9), (8, 10)):
        d.point((x, y), fill=heart)
    d.point((7, 7), fill=(255, 210, 225, 255))
    belly.save(ensure(os.path.join(ROOT, "block", "gooby_plushie_belly.png")))

    # --- Pluesch: Gesicht mit aufgenaehten Knopfaugen (UV-Fenster 2..14) ---
    face = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(face)
    wave_noise(d, (0, 0, 16, 16), FUR)
    # Rand-Naht rund um das Gesichtsfenster
    for i in range(2, 14, 3):
        d.point((i, 2), fill=FUR_DARK + (255,))
        d.point((i, 13), fill=FUR_DARK + (255,))
        d.point((2, i), fill=FUR_DARK + (255,))
        d.point((13, i), fill=FUR_DARK + (255,))
    # Creme-Schnauze, rosa Naeschen, aufgesticktes Laecheln
    d.ellipse((5, 8, 10, 12), fill=CREAM + (255,))
    d.point((6, 9), fill=CREAM_DARK + (255,))
    d.point((9, 11), fill=CREAM_DARK + (255,))
    d.rectangle((7, 8, 8, 9), fill=PINK + (255,))
    d.point((7, 9), fill=PINK_DARK + (255,))
    for x, y in ((6, 11), (7, 12), (8, 12), (9, 11)):
        d.point((x, y), fill=SMILE + (255,))
    # Zwei Bernstein-Knopfaugen mit Fadenkreuz und Glanzpunkt
    for ex in (3, 9):
        d.ellipse((ex, 4, ex + 3, 7), fill=(222, 160, 64, 255),
                  outline=(92, 58, 20, 255))
        d.line((ex + 1, 5, ex + 2, 6), fill=(121, 85, 58, 255))
        d.line((ex + 2, 5, ex + 1, 6), fill=(121, 85, 58, 255))
        d.point((ex + 1, 4), fill=(255, 236, 190, 255))
    # Rosa Wangen-Blush
    d.point((2, 9), fill=PINK + (255,))
    d.point((3, 9), fill=PINK + (255,))
    d.point((12, 9), fill=PINK + (255,))
    d.point((13, 9), fill=PINK + (255,))
    face.save(ensure(os.path.join(ROOT, "block", "gooby_plushie_face.png")))

    # --- Pluesch: Ohr mit rosa Innenseite (UV-Fenster 4..12) ---
    ear = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(ear)
    wave_noise(d, (0, 0, 16, 16), FUR)
    d.ellipse((5, 3, 10, 12), fill=PINK + (255,))
    d.ellipse((6, 5, 9, 10), fill=PINK_DARK + (255,))
    d.point((7, 6), fill=(255, 210, 225, 255))
    for y in (2, 13):  # Naht oben/unten am Ohrrand
        d.point((6, y), fill=FUR_DARK + (255,))
        d.point((9, y), fill=FUR_DARK + (255,))
    ear.save(ensure(os.path.join(ROOT, "block", "gooby_plushie_ear.png")))

    # --- Statue: gemeisselter Stein mit Rissen, Moos und Sockelband ---
    stone_base = (138, 138, 142)
    stone_dark = (104, 104, 110)
    stone_light = (168, 168, 172)
    moss = (106, 139, 84)
    stone = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(stone)
    wave_noise(d, (0, 0, 16, 16), stone_base)
    # Risse (Polylinien) mit Lichtkante
    d.line((2, 3, 5, 6), fill=stone_dark + (255,))
    d.line((5, 6, 4, 9), fill=stone_dark + (255,))
    d.line((11, 2, 12, 5), fill=stone_dark + (255,))
    d.line((12, 5, 15, 7), fill=stone_dark + (255,))
    d.point((3, 4), fill=stone_light + (255,))
    d.point((12, 6), fill=stone_light + (255,))
    # Meissel-Zierband unten (Zeilen 12..15 — Sockel-UV)
    d.line((0, 12, 15, 12), fill=stone_dark + (255,))
    d.line((0, 13, 15, 13), fill=stone_light + (255,))
    for x in range(1, 16, 4):
        d.point((x, 14), fill=stone_dark + (255,))
    # Mooskissen
    for mx, my in ((1, 10), (2, 11), (14, 11), (13, 15), (6, 15)):
        d.point((mx, my), fill=moss + (255,))
        if wave_rng.random() < 0.6:
            d.point((mx + 1, my), fill=(88, 118, 68, 255))
    stone.save(ensure(os.path.join(ROOT, "block", "gooby_statue_stone.png")))

    # --- Statue: Gesicht als Gravur (dunkle Rille + Lichtkante darunter) ---
    sface = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(sface)
    wave_noise(d, (0, 0, 16, 16), stone_base)
    engrave = stone_dark
    for ex in (4, 9):  # runde Knopfaugen-Gravuren
        d.ellipse((ex, 4, ex + 3, 7), outline=engrave + (255,))
        d.point((ex + 1, 5), fill=engrave + (255,))
        d.point((ex + 2, 8), fill=stone_light + (255,))  # Lichtkante
    d.rectangle((7, 8, 8, 9), fill=engrave + (255,))  # Naeschen
    for x, y in ((6, 11), (7, 12), (8, 12), (9, 11)):  # Laecheln-Rille
        d.point((x, y), fill=engrave + (255,))
        d.point((x, y + 1), fill=stone_light + (255,))
    d.point((2, 14), fill=moss + (255,))
    d.point((13, 3), fill=moss + (255,))
    sface.save(ensure(os.path.join(ROOT, "block", "gooby_statue_face.png")))

    # --- Statue: Sockelplatte mit Rahmen und Pfoten-Gravur ---
    base = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(base)
    wave_noise(d, (0, 0, 16, 16), stone_base)
    d.rectangle((1, 1, 14, 14), outline=stone_dark + (255,))
    d.rectangle((2, 2, 13, 13), outline=stone_light + (255,))
    for cx, cy in ((3, 3), (12, 3), (3, 12), (12, 12)):  # Eck-Rosetten
        d.point((cx, cy), fill=stone_dark + (255,))
    # Pfoten-Gravur: Ballen + drei Zehen mit Lichtkante
    d.ellipse((6, 7, 9, 10), outline=stone_dark + (255,))
    d.point((7, 8), fill=stone_dark + (255,))
    d.point((8, 8), fill=stone_dark + (255,))
    for tx, ty in ((5, 5), (7, 4), (9, 5)):
        d.rectangle((tx, ty, tx + 1, ty + 1), outline=stone_dark + (255,))
        d.point((tx, ty + 2), fill=stone_light + (255,))
    d.point((10, 11), fill=stone_light + (255,))
    d.point((4, 13), fill=moss + (255,))
    d.point((11, 2), fill=moss + (255,))
    base.save(ensure(os.path.join(ROOT, "block", "gooby_statue_base.png")))


def gen_speech_bubble():
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    border = (122, 85, 58, 255)
    fill = (255, 252, 246, 240)
    # Blasen-Koerper: abgerundetes Rechteck, Zeilen 0..47
    d.rounded_rectangle((0, 0, 63, 47), radius=9, fill=fill, outline=border, width=2)
    # Schwaenzchen: Zeilen 48..62, Spalten 24..40 (Spitze unten Mitte)
    # Oberer Verbindungsbereich in Blasenfarbe (ueberlappt den unteren Rand)
    d.rectangle((26, 44, 38, 49), fill=fill)
    d.polygon([(26, 48), (38, 48), (32, 61)], fill=fill)
    d.line((26, 48, 31, 60), fill=border, width=2)
    d.line((38, 48, 33, 60), fill=border, width=2)
    d.point((32, 61), fill=border)
    img.save(ensure(os.path.join(ROOT, "misc", "speech_bubble.png")))


def gen_v53_fetch_ball():
    """Fetch-Wave v5.3: Gooby-Ball (Apportier-Spielzeug).

    Nutzt wie gen_v52_content_wave einen EIGENEN Seed, damit die Textur
    byte-identisch reproduzierbar bleibt, egal welche anderen Generatoren
    vorher am geteilten RNG-Strom (Seed 8108) gezogen haben.
    """
    ball_rng = random.Random(5310)

    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = SMILE + (255,)

    # Weicher Bodenschatten unter dem Ball
    d.ellipse((4, 12, 11, 14), fill=(60, 42, 32, 70))

    # Ballkoerper: 12x12-Kugel, obere Halbkugel rosa, untere creme.
    # Pro Pixel radial schattiert (Licht oben links, Schatten unten rechts)
    # plus leichtes deterministisches Gummi-Rauschen.
    cx, cy, radius = 7.5, 6.5, 5.7
    for y in range(1, 13):
        for x in range(2, 14):
            dx, dy = x - cx, y - cy
            if dx * dx + dy * dy > radius * radius:
                continue
            if y <= 6:
                base, dark = PINK, PINK_DARK
            else:
                base, dark = CREAM, CREAM_DARK
            shade = (dx + dy) / radius
            if shade < -0.55:
                base = tuple(min(255, c + 24) for c in base)
            elif shade > 0.7:
                base = dark
            n = ball_rng.randint(-4, 4)
            d.point((x, y), fill=(max(0, min(255, base[0] + n)),
                                  max(0, min(255, base[1] + n)),
                                  max(0, min(255, base[2] + n)), 255))

    # Kontur + gestrichelte Aequator-Naht zwischen den Halbkugeln
    d.ellipse((2, 1, 13, 12), outline=outline)
    for x in range(3, 13):
        if x % 3 != 2:
            d.point((x, 6), fill=outline)
        if x % 3 == 1:
            d.point((x, 7), fill=SMILE + (110,))

    # Aufgestickter Pfotenabdruck auf der Creme-Halbkugel
    paw = FUR_DARK + (255,)
    d.point((7, 9), fill=paw)
    d.point((8, 9), fill=paw)
    d.point((7, 10), fill=paw)
    d.point((8, 10), fill=paw)
    d.point((6, 8), fill=paw)
    d.point((9, 8), fill=paw)

    # Glanzlicht oben links auf der rosa Halbkugel
    d.point((4, 3), fill=(255, 228, 238, 255))
    d.point((5, 3), fill=(255, 214, 228, 255))
    d.point((4, 4), fill=(255, 214, 228, 255))

    img.save(ensure(os.path.join(ROOT, "item", "gooby_ball.png")))


def gen_v54_explorer_outfit():
    """Explorer-Outfit v5.4: Blumenkranz, Abenteuer-Halstuch, Picknick-Rucksack.

    Eigener Seed (5406) wie bei den v5.2/v5.3-Wellen: die drei Texturen sind
    byte-identisch reproduzierbar, unabhaengig davon, was andere Generatoren
    vorher am geteilten RNG-Strom gezogen haben. Die bemalten Regionen sind
    exakt die UV-Fenster der handgeschriebenen 3D-Itemmodelle
    (models/item/{flower_crown,adventure_bandana,picnic_backpack}.json) —
    validate_assets.py prueft beides gegeneinander.
    """
    outfit_rng = random.Random(5406)

    def shaded_fill(draw, box, base, spread=6):
        x0, y0, x1, y1 = box
        for x in range(x0, x1):
            for y in range(y0, y1):
                n = outfit_rng.randint(-spread, spread)
                draw.point((x, y), fill=(max(0, min(255, base[0] + n)),
                                         max(0, min(255, base[1] + n)),
                                         max(0, min(255, base[2] + n)), 255))

    # --- Blumenkranz (16x16) -------------------------------------------
    # Zeilen 0-3: Seiten-Streifen des geflochtenen Bands, Zeilen 8-11 Band
    # oben (mit Knospen), Zeilen 12-15 Band unten (dunkler); dazwischen die
    # vier 4x4-Bluetenfenster (rosa, Margerite, blau, Blatt).
    vine = (110, 84, 48)
    vine_dark = (84, 62, 34)
    leaf_green = (96, 142, 74)
    leaf_dark = (68, 108, 52)
    crown = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(crown)
    shaded_fill(d, (0, 0, 16, 4), vine)
    for x in range(0, 16, 4):  # Flecht-Diagonalen
        d.line((x, 3, x + 3, 0), fill=vine_dark + (255,))
        d.point((x + 1, 2), fill=leaf_green + (255,))
    shaded_fill(d, (0, 8, 16, 12), leaf_green)
    for x in range(1, 16, 3):  # Knospenpunkte auf der Bandoberseite
        d.point((x, 9 + (x % 2)), fill=(233, 196, 106, 255))
        d.point((x + 1, 10), fill=leaf_dark + (255,))
    shaded_fill(d, (0, 12, 16, 16), vine_dark)
    for x in range(2, 16, 4):
        d.line((x, 15, x + 2, 12), fill=vine + (255,))
    # Rosa Bluete (0,4)-(4,8)
    shaded_fill(d, (0, 4, 4, 8), (232, 130, 168), spread=8)
    d.point((1, 5), fill=(255, 190, 213, 255))
    d.point((2, 6), fill=(240, 196, 92, 255))  # Zentrum
    d.point((1, 6), fill=(214, 100, 142, 255))
    # Margerite (4,4)-(8,8)
    shaded_fill(d, (4, 4, 8, 8), (243, 240, 228), spread=5)
    d.point((5, 5), fill=(255, 255, 250, 255))
    d.point((6, 6), fill=(238, 186, 66, 255))  # Zentrum
    d.point((6, 5), fill=(222, 214, 194, 255))
    # Kornblumen-Blau (8,4)-(12,8)
    shaded_fill(d, (8, 4, 12, 8), (94, 122, 198), spread=8)
    d.point((9, 5), fill=(150, 172, 232, 255))
    d.point((10, 6), fill=(64, 84, 152, 255))
    d.point((10, 5), fill=(238, 232, 160, 255))  # Pollenpunkt
    # Blattfenster (12,4)-(16,8)
    shaded_fill(d, (12, 4, 16, 8), leaf_green, spread=7)
    d.line((12, 7, 15, 4), fill=leaf_dark + (255,))  # Blattader
    d.point((13, 5), fill=(150, 190, 120, 255))
    crown.save(ensure(os.path.join(ROOT, "item", "flower_crown.png")))

    # --- Abenteuer-Halstuch (16x16, tint-bereites Graustufen-Tuch) ------
    # Zeilen 0-5 Haupttuch, 6-9 Knoten-/Rollstreifen, (0,10)-(8,16)
    # Dreieckszipfel, (8,10)-(16,16) Kanten-/Fransenstreifen.
    bandana = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(bandana)
    shaded_fill(d, (0, 0, 16, 6), (208, 208, 208), spread=5)
    for x, y in ((2, 1), (5, 3), (9, 1), (12, 4), (14, 2), (7, 4)):
        d.point((x, y), fill=(178, 178, 178, 255))       # Paisley-Punkte
        d.point((x + 1, y), fill=(232, 232, 232, 255))   # Lichtkante
    d.line((0, 5, 15, 5), fill=(170, 170, 170, 255))     # Saumnaht
    shaded_fill(d, (0, 6, 16, 10), (186, 186, 186), spread=5)
    for x in range(0, 16, 3):  # Falten der Rolle
        d.line((x, 6, x + 1, 9), fill=(158, 158, 158, 255))
        d.point((x + 2, 7), fill=(214, 214, 214, 255))
    shaded_fill(d, (0, 10, 8, 16), (204, 204, 204), spread=5)
    d.line((0, 10, 7, 10), fill=(168, 168, 168, 255))    # Zipfel-Bordüre
    d.line((0, 15, 7, 15), fill=(150, 150, 150, 255))    # Fransenreihe
    d.point((3, 12), fill=(178, 178, 178, 255))
    d.point((5, 13), fill=(230, 230, 230, 255))
    shaded_fill(d, (8, 10, 16, 16), (172, 172, 172), spread=5)
    for y in range(10, 16, 2):
        d.point((9, y), fill=(146, 146, 146, 255))
        d.point((13, y + 1), fill=(200, 200, 200, 255))
    bandana.save(ensure(os.path.join(ROOT, "item", "adventure_bandana.png")))

    # --- Picknick-Rucksack (32x32) --------------------------------------
    leather = (139, 87, 50)
    leather_light = (168, 110, 65)
    leather_dark = (91, 57, 34)
    stitch = (222, 186, 128)
    blanket_red = (196, 60, 60)
    blanket_cream = (241, 230, 213)
    pack = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(pack)
    # Grundierung: gesamte Flaeche deckend, damit keine UV-Region Loecher hat.
    shaded_fill(d, (0, 0, 32, 32), leather)
    # Frontpanel (0,0)-(12,12) mit Ziernaht
    shaded_fill(d, (0, 0, 12, 12), leather)
    d.rectangle((0, 0, 11, 11), outline=leather_dark + (255,))
    d.rectangle((1, 1, 10, 10), outline=stitch + (255,))
    # Rueckenpanel (12,0)-(24,12) mit Kreuznaehten
    shaded_fill(d, (12, 0, 24, 12), leather)
    d.rectangle((12, 0, 23, 11), outline=leather_dark + (255,))
    for x, y in ((15, 3), (20, 3), (15, 8), (20, 8)):
        d.line((x - 1, y, x + 1, y), fill=stitch + (255,))
        d.line((x, y - 1, x, y + 1), fill=stitch + (255,))
    # Seitenpanels (0,12)-(6,24) und (6,12)-(12,24)
    shaded_fill(d, (0, 12, 6, 24), leather_light, spread=7)
    shaded_fill(d, (6, 12, 12, 24), leather_light, spread=7)
    for x0 in (0, 6):
        d.rectangle((x0, 12, x0 + 5, 23), outline=leather_dark + (255,))
        d.point((x0 + 2, 17), fill=leather_dark + (255,))  # Schnallenpunkt
        d.point((x0 + 3, 18), fill=stitch + (255,))
    # Deckelklappe (12,12)-(24,18)
    shaded_fill(d, (12, 12, 24, 18), leather_light, spread=7)
    d.rectangle((12, 12, 23, 17), outline=leather_dark + (255,))
    d.line((13, 16, 22, 16), fill=stitch + (255,))
    # Boden (12,18)-(24,24) dunkel
    shaded_fill(d, (12, 18, 24, 24), leather_dark)
    # Deckenrolle (0,24)-(24,30): rot-cremefarbene Streifen
    for x in range(0, 24):
        stripe = blanket_red if (x // 3) % 2 == 0 else blanket_cream
        for y in range(24, 30):
            n = outfit_rng.randint(-6, 6)
            d.point((x, y), fill=(max(0, min(255, stripe[0] + n)),
                                  max(0, min(255, stripe[1] + n)),
                                  max(0, min(255, stripe[2] + n)), 255))
    d.line((0, 24, 23, 24), fill=(150, 42, 42, 255))
    # Rollen-Enden (24,24)-(30,30): Spirale
    shaded_fill(d, (24, 24, 30, 30), blanket_cream, spread=4)
    d.ellipse((24, 24, 29, 29), outline=blanket_red + (255,))
    d.point((26, 26), fill=blanket_red + (255,))
    d.point((27, 27), fill=blanket_red + (255,))
    # Riemenstreifen (24,0)-(28,12) mit Loechern
    shaded_fill(d, (24, 0, 28, 12), leather_dark)
    for y in range(2, 12, 3):
        d.point((25, y), fill=(56, 34, 20, 255))
        d.point((26, y), fill=leather_light + (255,))
    # Snack-Tasche (24,12)-(32,20) mit Holz-Knebel
    shaded_fill(d, (24, 12, 32, 20), leather_light, spread=7)
    d.rectangle((24, 12, 31, 19), outline=leather_dark + (255,))
    d.line((25, 14, 30, 14), fill=stitch + (255,))
    d.rectangle((27, 15, 28, 17), fill=(196, 148, 92, 255))
    # Knopfauge-Schnalle (28,0)-(32,4): Bernstein mit Fadenkreuz
    d.rectangle((28, 0, 31, 3), fill=(222, 160, 64, 255))
    d.rectangle((28, 0, 31, 3), outline=(92, 58, 20, 255))
    d.point((29, 1), fill=(255, 236, 190, 255))
    d.point((30, 2), fill=(121, 85, 58, 255))
    pack.save(ensure(os.path.join(ROOT, "item", "picnic_backpack.png")))


def gen_v55_cozy_home():
    """Cozy-Home-Welle v5.5 (Release 5.3.0): Gooby-Woll-Couch.

    Eigener Seed (5530) wie bei den v5.2/v5.3/v5.4-Wellen: alle Texturen sind
    byte-identisch reproduzierbar, unabhaengig davon, was andere Generatoren
    vorher am geteilten RNG-Strom (Seed 8108) gezogen haben. Die bemalten
    Flaechen sind komplett deckend — validate_assets.py prueft die vom
    handgeschriebenen Couch-Modell benutzten UV-Fenster fail-closed.
    """
    cozy_rng = random.Random(5530)

    def cozy_noise(draw, box, base, spread=7):
        x0, y0, x1, y1 = box
        for x in range(x0, x1):
            for y in range(y0, y1):
                n = cozy_rng.randint(-spread, spread)
                draw.point((x, y), fill=(max(0, min(255, base[0] + n)),
                                         max(0, min(255, base[1] + n)),
                                         max(0, min(255, base[2] + n)), 255))

    # --- Couch-Polster: Creme-Wolle mit Steppnaehten und Flauschtupfern ---
    wool = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(wool)
    cozy_noise(d, (0, 0, 16, 16), CREAM, spread=9)
    # Diagonale Steppnaht-Rauten wie bei einem Polstermoebel
    for offset in (-16, -8, 0, 8):
        for i in range(16):
            x, y = i, i + offset
            if 0 <= y < 16 and (x + y) % 4 == 0:
                d.point((x, y), fill=CREAM_DARK + (255,))
            y2 = 15 - i + offset
            if 0 <= y2 < 16 and (x + y2) % 4 == 0:
                d.point((x, y2), fill=CREAM_DARK + (255,))
    # Polsterknoepfe an den Rauten-Kreuzungen
    for bx, by in ((4, 4), (12, 4), (8, 8), (4, 12), (12, 12)):
        d.point((bx, by), fill=(214, 186, 148, 255))
        d.point((bx + 1, by), fill=WHITE + (255,))
    for _ in range(7):
        d.point((cozy_rng.randint(0, 15), cozy_rng.randint(0, 15)), fill=WHITE + (255,))
    wool.save(ensure(os.path.join(ROOT, "block", "gooby_couch_wool.png")))

    # --- Lehnen-Front: Fabric plus rosa Herzkissen-Applikation ---
    front = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(front)
    cozy_noise(d, (0, 0, 16, 16), CREAM, spread=8)
    for y in (3, 12):  # Saumnaehte oben/unten an der Lehne
        for x in range(0, 16, 3):
            d.point((x, y), fill=CREAM_DARK + (255,))
            d.point((x + 1, y), fill=CREAM_DARK + (255,))
    heart = PINK + (255,)
    heart_dark = PINK_DARK + (255,)
    for x, y in ((6, 6), (7, 6), (9, 6), (10, 6),
                 (5, 7), (6, 7), (7, 7), (8, 7), (9, 7), (10, 7), (11, 7),
                 (6, 8), (7, 8), (8, 8), (9, 8), (10, 8),
                 (7, 9), (8, 9), (9, 9), (8, 10)):
        d.point((x, y), fill=heart)
    d.point((6, 6), fill=(255, 210, 225, 255))  # Glanzpunkt
    for x, y in ((5, 8), (11, 8), (6, 9), (10, 9), (7, 10), (9, 10)):
        d.point((x, y), fill=heart_dark)  # Herzrand-Schattierung
    front.save(ensure(os.path.join(ROOT, "block", "gooby_couch_front.png")))

    # --- Holzrahmen: warme Planken mit Duebeln (dunkler als der Stall) ---
    wood = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(wood)
    cozy_noise(d, (0, 0, 16, 16), (146, 104, 62), spread=6)
    seam = (104, 72, 42, 255)
    for y in (3, 7, 11, 15):
        d.line((0, y, 15, y), fill=seam)
    for x, y in ((3, 1), (12, 5), (6, 9), (10, 13)):
        d.point((x, y), fill=seam)
        d.point((x + 1, y), fill=(178, 134, 86, 255))
    wood.save(ensure(os.path.join(ROOT, "block", "gooby_couch_wood.png")))


if __name__ == "__main__":
    gen_gooby()
    gen_nutella_item()
    gen_brush()
    gen_fluff()
    gen_gooby_wool()
    gen_hutch()
    gen_v37_hutch_layers()
    gen_jar_block()
    gen_zzz()
    gen_heart_gold()
    gen_v36_training_items()
    gen_v38_family_assets()
    gen_v39_fashion_assets()
    gen_v40_create_assets()
    gen_v41_wild_assets()
    gen_v42_icon_font()
    gen_v43_treasure_assets()
    gen_v50_handbook_assets()
    gen_speech_bubble()
    gen_v52_content_wave()
    gen_v53_fetch_ball()
    gen_v54_explorer_outfit()
    gen_v55_cozy_home()
    print("Alle Gooby-Texturen generiert!")
