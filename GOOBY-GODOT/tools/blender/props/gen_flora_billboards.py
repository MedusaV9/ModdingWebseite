#!/usr/bin/env python3
"""Billboard-Texturen der Openworld-Flora (VIS-1, Befund "Kornfeld sieht
aus wie gelbe Pfeile"): malt deterministisch (fester Seed) ein Korn-
Büschel und einen Lavendel-Busch als RGBA-Alphatexturen. Die Meshes dazu
baut WeltFlora (scripts/world/flora.gd) als gekreuzte Quads; gerendert
wird mit Alpha-Scissor + Wind-Shader (scripts/ranch/welt/flora_wind.gdshader).

Reines Pillow — KEIN Blender nötig:
    python3 tools/blender/props/gen_flora_billboards.py

Schreibt nach assets/ranch/welt/:
    korn_bueschel.png     (512x512, Ähren mit Halm, unten grün, oben gold)
    lavendel_busch.png    (512x512, Blütenähren + Blattbusch)
"""

from __future__ import annotations

import math
import pathlib
import random

from PIL import Image, ImageDraw, ImageFilter

SS = 4  # Supersampling: groß malen, LANCZOS-verkleinern = weiche Kanten.
SIZE = 512
OUT_DIR = pathlib.Path(__file__).resolve().parents[3] / "assets" / "ranch" / "welt"


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _mix(c1: tuple, c2: tuple, t: float) -> tuple:
    return tuple(int(round(_lerp(c1[i], c2[i], t))) for i in range(3))


def _bezier(p0, p1, p2, t):
    x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t**2 * p2[0]
    y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t**2 * p2[1]
    return x, y


def _stiel(draw, p0, p1, p2, farbe_unten, farbe_oben, breite):
    """Gebogener Halm als Kette kurzer Linien mit Farbverlauf."""
    schritte = 26
    letzte = _bezier(p0, p1, p2, 0.0)
    for i in range(1, schritte + 1):
        t = i / schritte
        punkt = _bezier(p0, p1, p2, t)
        farbe = _mix(farbe_unten, farbe_oben, t)
        draw.line([letzte, punkt], fill=farbe + (255,), width=max(1, int(breite * (1.0 - 0.35 * t))))
        letzte = punkt


def _korn(rng: random.Random) -> Image.Image:
    n = SIZE * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    gruen = (96, 138, 58)
    gruen_hell = (134, 168, 74)
    gold = (222, 178, 84)
    gold_hell = (238, 204, 116)
    gold_dunkel = (188, 142, 58)
    boden_y = n * 0.985
    # Bodennahe Blattbüschel: kurze, gebogene Grashalme.
    for _ in range(26):
        x0 = n * rng.uniform(0.18, 0.82)
        hoch = n * rng.uniform(0.10, 0.22)
        neig = n * rng.uniform(-0.10, 0.10)
        _stiel(
            draw,
            (x0, boden_y),
            (x0 + neig * 0.4, boden_y - hoch * 0.7),
            (x0 + neig, boden_y - hoch),
            gruen,
            gruen_hell,
            int(n * 0.008),
        )
    # Getreidehalme: Fuß im unteren Mittelteil, leichte Fächerung + Neigung.
    for i in range(11):
        x0 = n * (0.26 + 0.48 * i / 10.0) + n * rng.uniform(-0.02, 0.02)
        hoch = n * rng.uniform(0.60, 0.86)
        neig = n * rng.uniform(-0.16, 0.16)
        kopf = (x0 + neig, boden_y - hoch)
        _stiel(
            draw,
            (x0, boden_y),
            (x0 + neig * 0.35, boden_y - hoch * 0.62),
            kopf,
            gruen,
            gold,
            int(n * 0.007),
        )
        # Ähre: Körner-Reihen wechselseitig, leicht zur Halmneigung gedreht.
        aehre_h = n * rng.uniform(0.13, 0.17)
        winkel = math.atan2(neig, hoch) * 0.5
        for reihe in range(7):
            t = reihe / 6.0
            cy = kopf[1] + aehre_h * (0.92 - t)
            cx = kopf[0] + math.tan(winkel) * aehre_h * (0.92 - t) * 0.4
            breite_k = n * 0.016 * (1.0 - 0.35 * abs(t - 0.45))
            hoehe_k = n * 0.020
            farbe = _mix(gold, gold_hell, 0.35 + 0.4 * t)
            for seite in (-1.0, 1.0):
                ox = cx + seite * breite_k * 0.75
                draw.ellipse(
                    [ox - breite_k * 0.62, cy - hoehe_k * 0.52, ox + breite_k * 0.62, cy + hoehe_k * 0.52],
                    fill=farbe + (255,),
                    outline=gold_dunkel + (255,),
                    width=max(1, SS // 2),
                )
        # Grannen: feine helle Härchen über der Ähre.
        for _ in range(4):
            gx = kopf[0] + n * rng.uniform(-0.012, 0.012)
            gy = kopf[1] - aehre_h * rng.uniform(0.0, 0.15)
            lg = n * rng.uniform(0.05, 0.09)
            wg = winkel + rng.uniform(-0.30, 0.30)
            draw.line(
                [(gx, gy), (gx + math.sin(wg) * lg, gy - math.cos(wg) * lg)],
                fill=gold_hell + (235,),
                width=max(1, SS // 2),
            )
    return img


def _lavendel(rng: random.Random) -> Image.Image:
    n = SIZE * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    blatt = (116, 144, 108)
    blatt_hell = (150, 172, 128)
    lila = (150, 112, 198)
    lila_hell = (184, 148, 224)
    lila_tief = (118, 86, 168)
    boden_y = n * 0.985
    # Blatt-Busch unten: viele kurze silbergrüne Bögen.
    for _ in range(46):
        x0 = n * rng.uniform(0.20, 0.80)
        hoch = n * rng.uniform(0.14, 0.30)
        neig = n * rng.uniform(-0.14, 0.14)
        _stiel(
            draw,
            (x0, boden_y),
            (x0 + neig * 0.4, boden_y - hoch * 0.7),
            (x0 + neig, boden_y - hoch),
            blatt,
            blatt_hell,
            int(n * 0.009),
        )
    # Blütenstiele mit Ähren aus kleinen Blüten-Knospen.
    for i in range(13):
        x0 = n * (0.24 + 0.52 * i / 12.0) + n * rng.uniform(-0.02, 0.02)
        hoch = n * rng.uniform(0.52, 0.80)
        neig = n * rng.uniform(-0.13, 0.13)
        kopf = (x0 + neig, boden_y - hoch)
        _stiel(
            draw,
            (x0, boden_y),
            (x0 + neig * 0.4, boden_y - hoch * 0.66),
            kopf,
            blatt,
            blatt_hell,
            int(n * 0.006),
        )
        aehre_h = n * rng.uniform(0.10, 0.15)
        for reihe in range(6):
            t = reihe / 5.0
            cy = kopf[1] + aehre_h * (0.9 - t)
            r = n * 0.011 * (1.0 - 0.4 * t)
            farbe = _mix(lila, lila_hell, t * 0.7)
            for seite in (-0.8, 0.0, 0.8):
                ox = kopf[0] + seite * r * 1.15 + n * rng.uniform(-0.003, 0.003)
                draw.ellipse(
                    [ox - r, cy - r * 1.2, ox + r, cy + r * 1.2],
                    fill=farbe + (255,),
                    outline=lila_tief + (255,),
                    width=max(1, SS // 2),
                )
    return img


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, maler, seed in [
        ("korn_bueschel.png", _korn, 20260742),
        ("lavendel_busch.png", _lavendel, 20260739),
    ]:
        rng = random.Random(seed)
        gross = maler(rng)
        gross = gross.filter(ImageFilter.GaussianBlur(radius=SS * 0.35))
        klein = gross.resize((SIZE, SIZE), Image.LANCZOS)
        ziel = OUT_DIR / name
        klein.save(ziel)
        print(f"geschrieben: {ziel}")


if __name__ == "__main__":
    main()
