#!/usr/bin/env python3
"""C18 Backrooms art companion (IDEAS-backrooms_finale §A3.1/§A4).

Generates the Wanderer's asset set from the shipped glitched_husk sources —
run from the ProjectEclipse root; deterministic (seeded), idempotent:

  1. geo/animations: byte-copies of the husk pair with identifiers renamed to
     the frozen `glitched_wanderer` triple id (`animation.glitched_wanderer.*`
     is load-bearing: GlitchedMonster builds anim ids off geoId()).
  2. textures/entity/glitched_wanderer{,_alt,_glowmask,_alt_glowmask}.png —
     the mono-yellow "wet paint" regrade of the husk sheets: luminance mapped
     through a rot-yellow ramp (damp wallpaper read), the alt sheet's
     corruption pixels flared to hot pale-yellow, glowmasks re-tinted to the
     fluorescent froglight note.
  3. textures/gui/backrooms_scare.png — THE jumpscare face (256x256): the
     Wanderer's own 8x8 head front face blown up x32, eye voids hollowed,
     scanline displacement + vignette. JumpscareOverlay caps it at 85% alpha.
"""
import json
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "src/main/resources/assets/eclipse"
ENT = ASSETS / "textures/entity"
GUI = ASSETS / "textures/gui"

RNG = random.Random(0xBAC2)  # deterministic output; re-runs are byte-stable

# Rot-yellow luminance ramp: damp baseboard black -> ochre -> pale fluorescent.
RAMP = [
    (0.00, (24, 18, 6)),
    (0.35, (94, 74, 24)),
    (0.65, (168, 138, 50)),
    (0.85, (214, 188, 104)),
    (1.00, (240, 224, 164)),
]


def lum(rgb):
    r, g, b = rgb[:3]
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0


def ramp(t):
    t = max(0.0, min(1.0, t))
    for (t0, c0), (t1, c1) in zip(RAMP, RAMP[1:]):
        if t <= t1:
            f = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * f) for a, b in zip(c0, c1))
    return RAMP[-1][1]


def regrade(src, flare_vs=None, glow=False):
    """Mono-yellow regrade. flare_vs: base image — pixels differing strongly
    from it (the alt sheet's corruption) flare to hot pale yellow instead."""
    out = Image.new("RGBA", src.size, (0, 0, 0, 0))
    sp, op = src.load(), out.load()
    bp = flare_vs.load() if flare_vs is not None else None
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = sp[x, y]
            if a == 0:
                continue
            t = lum((r, g, b))
            if glow:
                # Fluorescent froglight note: pale yellow, luminance-scaled.
                c = (min(255, round(200 + 55 * t)), min(255, round(180 + 60 * t)),
                     round(90 + 70 * t))
            else:
                c = ramp(t)
                if bp is not None:
                    br, bg, bb, ba = bp[x, y]
                    if ba and abs(r - br) + abs(g - bg) + abs(b - bb) > 90:
                        # Corruption pixel: hot flare so the datamosh burst reads.
                        c = (min(255, c[0] + 70), min(255, c[1] + 66), min(255, c[2] + 40))
            op[x, y] = (*c, a)
    return out


def entity_sheets():
    base = Image.open(ENT / "glitched_husk.png").convert("RGBA")
    alt = Image.open(ENT / "glitched_husk_alt.png").convert("RGBA")
    glow = Image.open(ENT / "glitched_husk_glowmask.png").convert("RGBA")
    altglow = Image.open(ENT / "glitched_husk_alt_glowmask.png").convert("RGBA")

    regrade(base).save(ENT / "glitched_wanderer.png")
    regrade(alt, flare_vs=base).save(ENT / "glitched_wanderer_alt.png")
    regrade(glow, glow=True).save(ENT / "glitched_wanderer_glowmask.png")
    regrade(altglow, glow=True).save(ENT / "glitched_wanderer_alt_glowmask.png")
    return regrade(base)


def scare_face(sheet):
    """256x256 jumpscare face off the Wanderer's own head front face (UV 32,8 8x8)."""
    face = sheet.crop((32, 8, 40, 16)).resize((256, 256), Image.NEAREST)
    px = face.load()

    # Hollow the eye voids (rows 3-4 of the 8x8 face -> 96..160px) and a gaping
    # mouth (rows 6-7), pure black with a froglight pinprick pupil each.
    def void(x0, y0, x1, y1):
        for y in range(y0, y1):
            for x in range(x0, x1):
                px[x, y] = (6, 5, 2, 255)

    void(40, 100, 104, 156)     # left eye (wider than the sprite's — wrong on purpose)
    void(152, 100, 216, 156)    # right eye
    void(84, 196, 172, 244)     # mouth
    for cx, cy in ((72, 128), (184, 128)):
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                if dx * dx + dy * dy <= 9:
                    px[cx + dx, cy + dy] = (240, 224, 164, 255)

    # Deterministic scanline displacement slabs (the GLITCHED read).
    for _ in range(14):
        y0 = RNG.randrange(0, 250)
        h = RNG.randrange(2, 7)
        shift = RNG.randrange(-24, 25)
        band = face.crop((0, y0, 256, min(256, y0 + h)))
        face.paste(band, (shift, y0))

    # Vignette to black so the overlay's screen-cover crop has no hard edges.
    for y in range(256):
        for x in range(256):
            r, g, b, a = px[x, y]
            dx, dy = (x - 128) / 128.0, (y - 128) / 128.0
            d = min(1.0, (dx * dx + dy * dy) ** 0.5)
            k = 1.0 - 0.85 * max(0.0, d - 0.45) / 0.55
            px[x, y] = (round(r * k), round(g * k), round(b * k), a)

    GUI.mkdir(parents=True, exist_ok=True)
    face.save(GUI / "backrooms_scare.png")


def geo_anim():
    geo = json.loads((ASSETS / "geo/entity/glitched_husk.geo.json").read_text())
    geo["minecraft:geometry"][0]["description"]["identifier"] = "geometry.glitched_wanderer"
    (ASSETS / "geo/entity/glitched_wanderer.geo.json").write_text(
        json.dumps(geo, indent=1) + "\n")

    anim = json.loads((ASSETS / "animations/entity/glitched_husk.animation.json").read_text())
    anim["animations"] = {
        key.replace("animation.glitched_husk.", "animation.glitched_wanderer."): value
        for key, value in anim["animations"].items()
    }
    (ASSETS / "animations/entity/glitched_wanderer.animation.json").write_text(
        json.dumps(anim, indent=1) + "\n")


def main():
    sheet = entity_sheets()
    scare_face(sheet)
    geo_anim()
    print("wanderer sheets + scare face + geo/anim written")


if __name__ == "__main__":
    main()
