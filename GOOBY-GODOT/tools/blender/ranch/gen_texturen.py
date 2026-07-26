# gen_texturen.py — Kachelbare Pastell-Texturen der Gooby-Ranch, prozedural
# mit PIL (klein + verlustfrei, mobilfreundlich; 256×256 PNG).
# Farben an ranch_bau.gd angelehnt (WIESE_GRUEN, WEG_GRAU, HEU_GELB, ...).
# Alle Muster zeichnen mit Wrap-Around (x%N, y%N) → nahtlos kachelbar.
#
# Aufruf:  python3 gen_texturen.py [ZIEL_DIR]
# Default: GOOBY-GODOT/assets/ranch/texturen/
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

N = 256


def neu(farbe):
    return Image.new("RGB", (N, N), farbe)


def wrap_ellipse(draw, x, y, w, h, farbe):
    """Ellipse mit Torus-Wrap (9 Kopien) — hält die Kachel nahtlos."""
    for dx in (-N, 0, N):
        for dy in (-N, 0, N):
            draw.ellipse([x + dx, y + dy, x + dx + w, y + dy + h], fill=farbe)


def wrap_line(draw, x0, y0, x1, y1, farbe, breite=1):
    for dx in (-N, 0, N):
        for dy in (-N, 0, N):
            draw.line([x0 + dx, y0 + dy, x1 + dx, y1 + dy],
                      fill=farbe, width=breite)


def mische(basis, deck, alpha):
    return Image.blend(basis, deck, alpha)


def wiese():
    rng = random.Random(101)
    img = neu((148, 189, 117))                      # WIESE_GRUEN pastell
    d = ImageDraw.Draw(img)
    for _ in range(900):                            # weiche Farbtupfer
        x, y = rng.randrange(N), rng.randrange(N)
        t = rng.random()
        col = (137, 178, 106) if t < 0.45 else (158, 199, 128) if t < 0.9 \
            else (172, 209, 141)
        wrap_ellipse(d, x, y, rng.randint(3, 9), rng.randint(2, 6), col)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    d = ImageDraw.Draw(img)
    for _ in range(420):                            # Grashalm-Strichel
        x, y = rng.randrange(N), rng.randrange(N)
        l = rng.randint(3, 7)
        lean = rng.randint(-2, 2)
        col = (126, 168, 96) if rng.random() < 0.6 else (166, 204, 134)
        wrap_line(d, x, y, x + lean, y - l, col, 1)
    for _ in range(26):                             # Mini-Blümchen
        x, y = rng.randrange(N), rng.randrange(N)
        col = (249, 198, 207) if rng.random() < 0.5 else (252, 240, 216)
        wrap_ellipse(d, x, y, 3, 3, col)
    return img


def feldweg():
    rng = random.Random(202)
    img = neu((203, 183, 158))                      # warmer Sandweg
    d = ImageDraw.Draw(img)
    for _ in range(700):
        x, y = rng.randrange(N), rng.randrange(N)
        t = rng.random()
        col = (192, 170, 143) if t < 0.5 else (214, 196, 172)
        wrap_ellipse(d, x, y, rng.randint(4, 12), rng.randint(3, 8), col)
    img = img.filter(ImageFilter.GaussianBlur(1.6))
    d = ImageDraw.Draw(img)
    for _ in range(90):                             # Kiesel
        x, y = rng.randrange(N), rng.randrange(N)
        w = rng.randint(3, 7)
        col = rng.choice([(176, 158, 134), (222, 206, 184), (188, 172, 150)])
        wrap_ellipse(d, x, y, w, max(2, w - 2), col)
        wrap_ellipse(d, x + 1, y, w - 2, max(1, w - 4),
                     tuple(min(255, c + 14) for c in col))
    for _ in range(30):                             # Grasbüschel am Rand
        x, y = rng.randrange(N), rng.randrange(N)
        for _ in range(3):
            wrap_line(d, x, y, x + rng.randint(-3, 3), y - rng.randint(3, 6),
                      (150, 185, 118), 1)
    return img


def sand():
    rng = random.Random(303)
    img = neu((227, 204, 158))                      # Reitplatz-Sand
    d = ImageDraw.Draw(img)
    for _ in range(1400):
        x, y = rng.randrange(N), rng.randrange(N)
        t = rng.random()
        col = (219, 194, 146) if t < 0.5 else (236, 215, 172)
        wrap_ellipse(d, x, y, rng.randint(2, 5), rng.randint(1, 4), col)
    img = img.filter(ImageFilter.GaussianBlur(1.0))
    d = ImageDraw.Draw(img)
    # geharkte Bahnen (leichte horizontale Wellen, periodisch → nahtlos)
    for band in range(8):
        y0 = band * 32 + 8
        pts = [(x, y0 + int(3 * math.sin(x / N * 2 * math.pi * 3 + band)))
               for x in range(0, N + 8, 8)]
        for (x0, ya), (x1, yb) in zip(pts, pts[1:]):
            wrap_line(d, x0, ya, x1, yb, (214, 189, 141), 2)
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    return img


def holz():
    rng = random.Random(404)
    img = neu((232, 196, 154))                      # HOLZ_HELL
    d = ImageDraw.Draw(img)
    brett = 64
    for b in range(4):                              # 4 vertikale Bretter
        x0 = b * brett
        ton = rng.randint(-10, 10)
        d.rectangle([x0, 0, x0 + brett - 1, N],
                    fill=(232 + ton, 196 + ton, 154 + ton))
        # Maserung: leicht gebogene vertikale Linien (y-periodisch)
        for li in range(5):
            lx = x0 + 8 + li * 11 + rng.randint(-2, 2)
            amp = rng.randint(1, 3)
            phase = rng.random() * 2 * math.pi
            pts = [(lx + int(amp * math.sin(y / N * 2 * math.pi + phase)), y)
                   for y in range(0, N + 8, 8)]
            for (xa, y0), (xb, y1) in zip(pts, pts[1:]):
                wrap_line(d, xa, y0, xb, y1, (203, 164, 122), 1)
        # Astloch
        if rng.random() < 0.7:
            ax, ay = x0 + rng.randint(14, brett - 20), rng.randrange(N)
            wrap_ellipse(d, ax, ay, 7, 9, (191, 152, 110))
            wrap_ellipse(d, ax + 2, ay + 2, 3, 4, (173, 136, 96))
        # Brettfuge
        d.line([x0, 0, x0, N], fill=(198, 160, 118), width=2)
    return img.filter(ImageFilter.GaussianBlur(0.4))


def stroh():
    rng = random.Random(505)
    img = neu((226, 195, 116))                      # HEU_GELB gedämpft
    d = ImageDraw.Draw(img)
    for _ in range(1600):                           # kreuz-quer Halme
        x, y = rng.randrange(N), rng.randrange(N)
        l = rng.randint(8, 22)
        a = rng.random() * math.pi
        t = rng.random()
        col = (238, 211, 138) if t < 0.4 else (210, 176, 98) if t < 0.8 \
            else (247, 226, 163)
        wrap_line(d, x, y, x + int(l * math.cos(a)), y + int(l * math.sin(a)),
                  col, 1)
    img = img.filter(ImageFilter.GaussianBlur(0.5))
    d = ImageDraw.Draw(img)
    for _ in range(200):                            # helle Glanz-Halme oben
        x, y = rng.randrange(N), rng.randrange(N)
        l = rng.randint(6, 14)
        a = rng.random() * math.pi
        wrap_line(d, x, y, x + int(l * math.cos(a)), y + int(l * math.sin(a)),
                  (250, 232, 178), 1)
    return img


def wasser():
    img = neu((115, 173, 209))                      # WASSER_BLAU pastell
    px = img.load()
    for y in range(N):
        for x in range(N):
            # periodische Überlagerung → nahtlos, sanfte Wellen
            u, v = x / N * 2 * math.pi, y / N * 2 * math.pi
            w = (math.sin(u * 3 + math.sin(v * 2) * 1.4)
                 + math.sin(v * 4 + math.cos(u * 2) * 1.2)
                 + math.sin((u + v) * 2.5)) / 3.0
            base = (115, 173, 209)
            hell = (168, 214, 236)
            t = max(0.0, w) ** 2 * 0.8
            px[x, y] = tuple(int(b + (h - b) * t) for b, h in zip(base, hell))
    d = ImageDraw.Draw(img)
    rng = random.Random(606)
    for _ in range(40):                             # Glitzerpunkte
        x, y = rng.randrange(N), rng.randrange(N)
        wrap_ellipse(d, x, y, 2, 1, (236, 248, 252))
    return img


TEXTUREN = {
    "wiese": wiese, "feldweg": feldweg, "sand": sand,
    "holz": holz, "stroh": stroh, "wasser": wasser,
}


def main():
    ziel = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..", "..",
        "assets", "ranch", "texturen")
    ziel = os.path.abspath(ziel)
    os.makedirs(ziel, exist_ok=True)
    for name, fn in TEXTUREN.items():
        img = fn()
        pfad = os.path.join(ziel, f"{name}.png")
        img.save(pfad, optimize=True)
        kb = os.path.getsize(pfad) / 1024
        print(f"[gen_texturen] {pfad} ({kb:.0f} KiB)")


if __name__ == "__main__":
    main()
