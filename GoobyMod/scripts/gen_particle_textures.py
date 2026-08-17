#!/usr/bin/env python3
"""Erzeugt die Sprite-Frames + Partikel-JSONs der Feedback-Wave (Pillow).

Aufruf:   python3 scripts/gen_particle_textures.py           # (neu) schreiben
          python3 scripts/gen_particle_textures.py --check   # Validator-Modus

Gehoert AUSSCHLIESSLICH zur Partikel-Feedback-Wave und schreibt nur:
  textures/particle/confetti_0..3.png      (Schnipsel/Streamer/Stern/Dreieck)
  textures/particle/fluff_puff_0..3.png    (Fussel: dicht -> zerfasert)
  textures/particle/music_note_0..1.png    (Achtelnote, Doppelnote mit Balken)
  particles/confetti.json, fluff_puff.json, music_note.json

Die bestehenden Partikel (zzz, heart_gold, paw_print) bleiben bei
scripts/gen_textures.py — dieses Skript fasst sie NIE an.

Reproduzierbarkeit: EIGENER Seed (8121), unabhaengig vom geteilten
RNG-Strom in gen_textures.py — die Ausgabe ist damit byte-identisch,
egal welche anderen Generatoren vorher gelaufen sind.

--check validiert fail-closed (Exit-Code != 0 bei jedem Fehler):
  1. Pixel-identische Regeneration (PNGs driften nie von diesem Skript weg).
  2. JSON-Inhalt exakt wie erwartet (Namespace goobymod, Framelisten).
  3. Frame-Invarianten: 16x16 RGBA, transparenter 1-px-Rand, Alpha-Coverage
     im Low-Count-Band, Konfetti/Noten fast weiss (tintbar), Fussel-Frames
     loesen sich monoton auf, keine zwei Frames identisch.
  4. Negativ: keine verwaisten Frames (confetti_4 & Co. duerfen nicht
     existieren) und kein Fremd-Namespace in den JSONs.
"""
from __future__ import annotations

import argparse
import io
import json
import math
import os
import random
import sys

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                    "src", "main", "resources", "assets", "goobymod")
TEXTURE_DIR = os.path.join(ROOT, "textures", "particle")
PARTICLE_DIR = os.path.join(ROOT, "particles")

SEED = 8121
SIZE = 16

# Partikel -> Framezahl. Muss zu ModParticles + GoobyParticleWaveTests passen.
FRAMES = {"confetti": 4, "fluff_puff": 4, "music_note": 2}

# Cremefell wie in gen_textures.py (CREAM/CREAM_DARK) — Fussel = Goobys Fell.
CREAM = (243, 226, 200)
CREAM_DARK = (226, 205, 173)
CREAM_LIGHT = (255, 244, 222)

# Coverage-Band (Anteil Pixel mit Alpha >= 8) und Tint-Schwelle.
COVERAGE_MIN = 0.03
COVERAGE_MAX = 0.70
TINT_MIN_AVG = 190

rng = random.Random(SEED)


def new_canvas():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def gray(value, alpha=255):
    return (value, value, value, alpha)


# ---------------------------------------------------------------------------
# Konfetti: vier fast weisse Varianten — der Client tintet aus der Palette.
# ---------------------------------------------------------------------------

def confetti_frame_0():
    """Geknickter Papier-Schnipsel: zwei Falz-Haelften + Schattenkante."""
    img = new_canvas()
    d = ImageDraw.Draw(img)
    d.polygon([(3, 5), (8, 3), (9, 8), (4, 10)], fill=gray(252))
    d.polygon([(8, 3), (12, 6), (13, 11), (9, 8)], fill=gray(228))
    d.line((8, 3, 9, 8), fill=gray(208))
    d.line((4, 10, 9, 8), fill=gray(240))
    d.point((5, 5), fill=gray(255))
    d.point((11, 7), fill=gray(214))
    for _ in range(4):
        d.point((rng.randint(4, 12), rng.randint(4, 10)), fill=gray(244))
    return img


def confetti_frame_1():
    """Gedrehter Streamer: S-Kurve mit hell/dunkel wechselnden Segmenten."""
    img = new_canvas()
    d = ImageDraw.Draw(img)
    for t in range(11):
        x = 3 + t
        y = int(round(8 + 3.6 * math.sin(t * 0.62)))
        y = max(2, min(12, y))
        shade = 250 if (t // 2) % 2 == 0 else 224
        d.line((x, y, x, y + 2), fill=gray(shade))
        if t % 3 == 0:
            d.point((x, y), fill=gray(255))
    return img


def confetti_frame_2():
    """Vierstrahliger Funkel-Stern mit Diagonal-Glitzern."""
    img = new_canvas()
    d = ImageDraw.Draw(img)
    cx, cy = 8, 8
    for r in range(1, 6):
        shade = 255 - r * 9
        d.point((cx, cy - r), fill=gray(shade))
        d.point((cx, cy + r), fill=gray(shade))
        d.point((cx - r, cy), fill=gray(shade))
        d.point((cx + r, cy), fill=gray(shade))
        if r <= 2:
            d.point((cx - 1, cy - r), fill=gray(shade - 12))
            d.point((cx + 1, cy - r), fill=gray(shade - 12))
            d.point((cx - 1, cy + r), fill=gray(shade - 12))
            d.point((cx + 1, cy + r), fill=gray(shade - 12))
    d.rectangle((cx - 1, cy - 1, cx + 1, cy + 1), fill=gray(255))
    for sx, sy in ((3, 3), (13, 4), (3, 13), (12, 12)):
        d.point((sx, sy), fill=gray(236, 210))
    return img


def confetti_frame_3():
    """Dreiecks-Schnipsel mit Lichtkante plus kleiner Punkt-Kollege."""
    img = new_canvas()
    d = ImageDraw.Draw(img)
    d.polygon([(3, 4), (10, 6), (5, 12)], fill=gray(246))
    d.line((3, 4, 10, 6), fill=gray(255))
    d.line((3, 4, 5, 12), fill=gray(234))
    d.point((6, 8), fill=gray(220))
    d.point((5, 6), fill=gray(255))
    d.ellipse((11, 10, 13, 12), fill=gray(240))
    d.point((11, 10), fill=gray(255))
    return img


# ---------------------------------------------------------------------------
# Fussel: vier Frames, die sich monoton aufloesen (dicht -> zerfasert).
# ---------------------------------------------------------------------------

def fluff_frame(frame):
    img = new_canvas()
    px = img.load()
    cx = cy = 7.5
    radius = 4.7 + frame * 0.25
    hole_chance = (0.02, 0.16, 0.31, 0.47)[frame]
    base_alpha = (235, 202, 162, 118)[frame]
    for y in range(1, SIZE - 1):
        for x in range(1, SIZE - 1):
            edge = math.hypot(x - cx, y - cy) / radius
            if edge > 1.0 + rng.uniform(-0.08, 0.06):
                continue
            if rng.random() < hole_chance:
                continue
            alpha = int(base_alpha * max(0.35, 1.0 - edge * 0.75))
            if alpha < 10:
                continue
            roll = rng.random()
            base = CREAM_LIGHT if roll < 0.18 else CREAM_DARK if roll < 0.33 else CREAM
            n = rng.randint(-7, 7)
            px[x, y] = (max(0, min(255, base[0] + n)),
                        max(0, min(255, base[1] + n)),
                        max(0, min(255, base[2] + n)), alpha)
    # Abstehende Flusen-Straehnen — mit jedem Frame ein paar mehr.
    for _ in range(3 + frame * 2):
        angle = rng.uniform(0.0, math.tau)
        reach = radius + rng.uniform(0.2, 1.4)
        x = int(round(cx + math.cos(angle) * reach))
        y = int(round(cy + math.sin(angle) * reach))
        if 1 <= x <= SIZE - 2 and 1 <= y <= SIZE - 2:
            px[x, y] = CREAM + (max(12, int(base_alpha * 0.5)),)
    return img


# ---------------------------------------------------------------------------
# Musiknoten: zwei weisse Glyphen — der Client tintet pastellfarben.
# ---------------------------------------------------------------------------

def music_note_frame_0():
    """Achtelnote: Kopf, Hals und geschwungenes Faehnchen."""
    img = new_canvas()
    d = ImageDraw.Draw(img)
    d.ellipse((3, 10, 7, 13), fill=gray(250))
    d.point((6, 12), fill=gray(214))
    d.point((6, 13), fill=gray(214))
    d.point((4, 10), fill=gray(255))
    d.rectangle((7, 3, 8, 11), fill=gray(250))
    d.line((7, 3, 8, 3), fill=gray(255))
    for fx, fy in ((9, 4), (10, 5), (11, 6), (11, 7), (10, 8), (9, 9)):
        d.point((fx, fy), fill=gray(234))
        d.point((fx, fy + 1), fill=gray(222, 200))
    return img


def music_note_frame_1():
    """Doppelnote: zwei Koepfe, zwei Haelse, leicht geneigter Balken."""
    img = new_canvas()
    d = ImageDraw.Draw(img)
    d.ellipse((2, 11, 5, 13), fill=gray(250))
    d.ellipse((9, 10, 12, 12), fill=gray(250))
    d.point((3, 11), fill=gray(255))
    d.point((10, 10), fill=gray(255))
    d.point((4, 13), fill=gray(216))
    d.point((11, 12), fill=gray(216))
    d.rectangle((5, 5, 5, 12), fill=gray(250))
    d.rectangle((12, 4, 12, 11), fill=gray(250))
    d.line((5, 4, 12, 3), fill=gray(246))
    d.line((5, 5, 12, 4), fill=gray(230))
    return img


BUILDERS = {
    "confetti": (confetti_frame_0, confetti_frame_1, confetti_frame_2, confetti_frame_3),
    "fluff_puff": tuple(lambda f=f: fluff_frame(f) for f in range(4)),
    "music_note": (music_note_frame_0, music_note_frame_1),
}


def particle_json(name):
    return {"textures": [f"goobymod:{name}_{i}" for i in range(FRAMES[name])]}


def render_all():
    """Deterministische Gesamt-Ausgabe: {relativer Pfad: PNG-Image|JSON-str}."""
    global rng
    rng = random.Random(SEED)
    output = {}
    for name in FRAMES:
        for index, builder in enumerate(BUILDERS[name]):
            output[os.path.join("textures", "particle", f"{name}_{index}.png")] = builder()
        output[os.path.join("particles", f"{name}.json")] = (
            json.dumps(particle_json(name), indent=2) + "\n")
    return output


# ---------------------------------------------------------------------------
# Validierung (fail-closed)
# ---------------------------------------------------------------------------

def pixel_list(img):
    px = img.load()
    return [px[x, y] for y in range(img.height) for x in range(img.width)]


def coverage(img, threshold=8):
    return sum(1 for _, _, _, a in pixel_list(img) if a >= threshold)


def validate_frames(images_by_name):
    errors = []
    for name, frames in images_by_name.items():
        opaque_counts = []
        raw_bytes = []
        for index, img in enumerate(frames):
            tag = f"{name}_{index}"
            if img.size != (SIZE, SIZE):
                errors.append(f"{tag}: Groesse {img.size} != {SIZE}x{SIZE}")
                continue
            px = img.load()
            for i in range(SIZE):
                for x, y in ((i, 0), (i, SIZE - 1), (0, i), (SIZE - 1, i)):
                    if px[x, y][3] != 0:
                        errors.append(f"{tag}: 1-px-Rand nicht transparent bei {(x, y)}")
                        break
            opaque = coverage(img)
            share = opaque / (SIZE * SIZE)
            if not COVERAGE_MIN <= share <= COVERAGE_MAX:
                errors.append(f"{tag}: Alpha-Coverage {share:.2%} ausserhalb "
                              f"{COVERAGE_MIN:.0%}..{COVERAGE_MAX:.0%}")
            if name in ("confetti", "music_note"):
                pixels = [(r, g, b) for r, g, b, a in pixel_list(img) if a >= 8]
                for channel in range(3):
                    avg = sum(p[channel] for p in pixels) / max(1, len(pixels))
                    if avg < TINT_MIN_AVG:
                        errors.append(f"{tag}: Kanal {channel} zu dunkel fuer "
                                      f"Tint ({avg:.0f} < {TINT_MIN_AVG})")
            opaque_counts.append(opaque)
            raw_bytes.append(img.tobytes())
        if name == "fluff_puff" and (opaque_counts != sorted(opaque_counts, reverse=True)
                or len(set(opaque_counts)) != len(opaque_counts)):
            errors.append(f"{name}: Frames loesen sich nicht monoton auf: {opaque_counts}")
        for a in range(len(raw_bytes)):
            for b in range(a + 1, len(raw_bytes)):
                if raw_bytes[a] == raw_bytes[b]:
                    errors.append(f"{name}: Frame {a} und {b} sind pixel-identisch")
    return errors


def check(rendered):
    errors = []
    images_by_name = {name: [] for name in FRAMES}
    for rel_path, content in sorted(rendered.items()):
        disk_path = os.path.join(ROOT, rel_path)
        if not os.path.isfile(disk_path):
            errors.append(f"Datei fehlt: {rel_path} — Generator erneut ausfuehren")
            continue
        if rel_path.endswith(".json"):
            with open(disk_path, "r", encoding="utf-8") as handle:
                on_disk = handle.read()
            if on_disk != content:
                errors.append(f"{rel_path}: Inhalt weicht vom Generator ab")
            refs = json.loads(on_disk).get("textures", [])
            for ref in refs:
                if not ref.startswith("goobymod:"):
                    errors.append(f"{rel_path}: Fremd-Namespace-Referenz {ref}")
        else:
            with Image.open(disk_path) as handle:
                on_disk = handle.convert("RGBA")
            if on_disk.tobytes() != content.tobytes():
                errors.append(f"{rel_path}: Pixel weichen vom Generator ab")
            name = os.path.basename(rel_path).rsplit("_", 1)[0]
            images_by_name[name].append(on_disk)
    errors.extend(validate_frames({n: f for n, f in images_by_name.items() if f}))
    # Negativ: KEINE verwaisten Frames neben den deklarierten Framelisten.
    for name, count in FRAMES.items():
        orphan = os.path.join(TEXTURE_DIR, f"{name}_{count}.png")
        if os.path.exists(orphan):
            errors.append(f"Verwaister Frame ausserhalb der JSON-Liste: {name}_{count}.png")
    return errors


def write(rendered):
    for rel_path, content in sorted(rendered.items()):
        disk_path = os.path.join(ROOT, rel_path)
        os.makedirs(os.path.dirname(disk_path), exist_ok=True)
        if rel_path.endswith(".json"):
            with open(disk_path, "w", encoding="utf-8") as handle:
                handle.write(content)
        else:
            buffer = io.BytesIO()
            content.save(buffer, format="PNG")
            with open(disk_path, "wb") as handle:
                handle.write(buffer.getvalue())
        print(f"geschrieben: {rel_path}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="nur validieren (Exit != 0 bei Drift/Fehlern)")
    args = parser.parse_args(argv)

    rendered = render_all()
    self_errors = validate_frames({
        name: [rendered[os.path.join("textures", "particle", f"{name}_{i}.png")]
               for i in range(FRAMES[name])] for name in FRAMES})
    if self_errors:
        for line in self_errors:
            print(f"[FAIL] Generator-Invariante: {line}")
        return 1

    if args.check:
        errors = check(rendered)
        for line in errors:
            print(f"[FAIL] {line}")
        if errors:
            print(f"\nPartikel-Asset-Check FEHLGESCHLAGEN: {len(errors)} Fehler.")
            return 1
        print(f"Partikel-Asset-Check bestanden ({len(rendered)} Dateien).")
        return 0

    write(rendered)
    print("Alle Feedback-Wave-Partikel-Assets generiert!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
