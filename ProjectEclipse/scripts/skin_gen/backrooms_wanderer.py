#!/usr/bin/env python3
"""C18 Backrooms art companion (IDEAS-backrooms_finale §A3.1/§A4; MOB-GLITCH v2).

Generates the Wanderer's asset set from the shipped glitched_husk sources —
run from the ProjectEclipse root; deterministic (seeded), idempotent:

  1. geo: the husk geometry re-identified to the frozen `glitched_wanderer`
     triple id AND warped subtly WRONG (MOB-GLITCH): both arms stretched too
     long (the fingertips reach past the knee line), head + face shards
     deflated small (inflate < 0), the dislocated jaw's UV re-parked clear of
     the taller arm strip. The proportions are off by just enough to read as
     "person-shaped, but no" down a long corridor.
  2. animations: the husk set re-keyed to `animation.glitched_wanderer.*`
     (load-bearing: GlitchedMonster builds anim ids off geoId()) with three
     bespoke replacements/additions — `idle` (near-still + the head-turn-TOO-FAR
     beat), `walk` (unsettling slow corridor pace, head locked level) and the
     NEW `sprint` (the lookaway burst — GlitchedWandererEntity plays it while a
     gaze-burst speed modifier is live). attack/glitch_blink/death stay the
     renamed husk one-shots.
  3. textures/entity/glitched_wanderer{,_alt,_glowmask,_alt_glowmask}.png —
     painted directly on the WARPED geo with the husk's own material set
     (`glitched_husk.build`), then mono-yellow "wet paint" regraded: luminance
     mapped through a rot-yellow ramp (damp wallpaper read), the alt sheet's
     corruption pixels flared to hot pale-yellow, glowmasks re-tinted to the
     fluorescent froglight note (emissive glitch scars inherit it).
  4. textures/gui/backrooms_scare.png — THE jumpscare face (256x256): the
     Wanderer's own 8x8 head front face blown up x32, eye voids hollowed,
     scanline displacement + vignette. JumpscareOverlay caps it at 85% alpha.
"""
import json
import random
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "src/main/resources/assets/eclipse"
ENT = ASSETS / "textures/entity"
GUI = ASSETS / "textures/gui"

sys.path.insert(0, str(ROOT / "scripts/geckolib_gen/mobs"))
import glitched_husk as husk  # noqa: E402

WGEO = ASSETS / "geo/entity/glitched_wanderer.geo.json"

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
    """Paints the husk material language onto the WARPED wanderer geo (so the long
    arms get fully-textured strips), then regrades all four sheets mono-yellow in
    place. Must run AFTER geo_anim() has written the warped geo."""
    base, base_glow = husk.build(WGEO, alt=False).paint(ENT / "glitched_wanderer.png")
    alt, alt_glow = husk.build(WGEO, alt=True).paint(ENT / "glitched_wanderer_alt.png")

    regrade(base).save(ENT / "glitched_wanderer.png")
    regrade(alt, flare_vs=base).save(ENT / "glitched_wanderer_alt.png")
    regrade(base_glow, glow=True).save(ENT / "glitched_wanderer_glowmask.png")
    regrade(alt_glow, glow=True).save(ENT / "glitched_wanderer_alt_glowmask.png")
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


def _warp_geo(geo):
    """Subtly WRONG proportions (MOB-GLITCH): long arms, small head. The shoulder
    anchors stay put — only the cubes stretch/deflate — so every husk-derived
    animation still reads correctly on the warped rig."""
    bones = {b["name"]: b for b in geo["minecraft:geometry"][0]["bones"]}
    # Small head: deflate the skull and its shards (UV rects untouched — the scare
    # face crop and the head strip both stay at their husk coordinates).
    for name, shrink in (("head", -0.75), ("head_shard", -0.35), ("jaw_shard", -0.2)):
        for cube in bones[name]["cubes"]:
            cube["inflate"] = round(cube.get("inflate", 0) + shrink, 3)
    # Long arms: stretch both sleeves DOWN from the shoulder. Fingertips end at
    # y2/y6 — past the hip line, brushing the knees. Strips grow taller, still
    # inside the 64x64 canvas (arm_right 32..44 x 16..39, arm_left 44..56 x 16..34).
    arm_right = bones["arm_right"]["cubes"][0]
    arm_right["origin"][1] = 2
    arm_right["size"][1] = 20
    arm_left = bones["arm_left"]["cubes"][0]
    arm_left["origin"][1] = 6
    arm_left["size"][1] = 15
    # The taller arm_right strip (ends y39) would collide with the jaw UV at
    # (32,36) — re-park the wanderer's jaw strip below it.
    bones["jaw_shard"]["cubes"][0]["uv"] = [32, 40]


# --- bespoke wanderer animations (MOB-GLITCH) --------------------------------
# The husk's stutter language is deliberately absent from walk: the Wanderer's
# dread is SMOOTHNESS — a person-shaped thing pacing a corridor with its head
# locked dead level. The glitch vocabulary only erupts in the too-far head turn
# (idle) and the lookaway burst (sprint).

IDLE = {
    "loop": True,
    "animation_length": 5.0,
    "bones": {
        "root": {
            "position": {
                "0.0": [0, 0, 0],
                "4.2": [0, 0, 0],
                "4.25": [0.3, 0, -0.2],
                "4.3": [0, 0, 0],
                "5.0": [0, 0, 0],
            }
        },
        # REPASS-MOB: sway periods snapped to the 5.0 s loop (72*5 = 360deg) — the old
        # 60/70 deg/s sines wrapped mid-phase and popped the pose every loop.
        "body": {
            "rotation": [0, 0, "math.sin(query.anim_time * 72) * 0.6"]
        },
        "arm_right": {
            "rotation": [0, 0, "-2 + math.sin(query.anim_time * 72) * 1"]
        },
        "arm_left": {
            "rotation": [0, 0, "2 + math.sin(query.anim_time * 72 + 180) * 1"]
        },
        "head": {
            "rotation": {
                "0.0": [0, 0, 0],
                "2.0": [0, 0, 0],
                "2.1": [6, -118, 8],
                "3.3": [6, -118, 8],
                "3.4": [0, -25, 0],
                "3.55": [0, -25, 0],
                "3.6": [0, 0, 0],
                "5.0": [0, 0, 0],
            }
        },
        "head_shard": {
            "position": [0, "math.sin(query.anim_time * 36) * 0.2", 0]
        },
        "jaw_shard": {
            "rotation": {
                "0.0": [0, 0, 0],
                "2.0": [4, 0, 0],
                "2.1": [18, -6, 4],
                "3.3": [18, -6, 4],
                "3.4": [0, 0, 0],
                "5.0": [0, 0, 0],
            }
        },
        "glow_seam": {
            "scale": {
                "0.0": [1, 1, 1],
                "2.0": [1, 1, 1],
                "2.1": [1.5, 1, 1.5],
                "3.3": [1.5, 1, 1.5],
                "3.45": [1, 1, 1],
                "5.0": [1, 1, 1],
            }
        },
    },
}

WALK = {
    "loop": True,
    "animation_length": 1.6,
    "bones": {
        "root": {
            "position": {
                "0.0": {"post": [0, 0, 0], "lerp_mode": "catmullrom"},
                "0.4": {"post": [0, 0.3, 0], "lerp_mode": "catmullrom"},
                "0.8": {"post": [0, 0, 0], "lerp_mode": "catmullrom"},
                "1.2": {"post": [0, 0.3, 0], "lerp_mode": "catmullrom"},
                "1.6": {"post": [0, 0, 0], "lerp_mode": "catmullrom"},
            }
        },
        "body": {
            "rotation": {
                "0.0": {"post": [3, 0, 1.5], "lerp_mode": "catmullrom"},
                "0.8": {"post": [3, 0, -1.5], "lerp_mode": "catmullrom"},
                "1.6": {"post": [3, 0, 1.5], "lerp_mode": "catmullrom"},
            }
        },
        "leg_right": {
            "rotation": {
                "0.0": {"post": [22, 0, 0], "lerp_mode": "catmullrom"},
                "0.8": {"post": [-22, 0, 0], "lerp_mode": "catmullrom"},
                "1.6": {"post": [22, 0, 0], "lerp_mode": "catmullrom"},
            }
        },
        "leg_left": {
            "rotation": {
                "0.0": {"post": [-22, 0, 0], "lerp_mode": "catmullrom"},
                "0.8": {"post": [22, 0, 0], "lerp_mode": "catmullrom"},
                "1.6": {"post": [-22, 0, 0], "lerp_mode": "catmullrom"},
            }
        },
        "arm_right": {
            "rotation": {
                "0.0": {"post": [-10, 0, -3], "lerp_mode": "catmullrom"},
                "0.8": {"post": [10, 0, -3], "lerp_mode": "catmullrom"},
                "1.6": {"post": [-10, 0, -3], "lerp_mode": "catmullrom"},
            }
        },
        "arm_left": {
            "rotation": {
                "0.0": {"post": [10, 0, 3], "lerp_mode": "catmullrom"},
                "0.8": {"post": [-10, 0, 3], "lerp_mode": "catmullrom"},
                "1.6": {"post": [10, 0, 3], "lerp_mode": "catmullrom"},
            }
        },
        "head": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.75": [0, 0, 0],
                "0.8": [3, -7, 2],
                "0.9": [3, -7, 2],
                "0.95": [0, 0, 0],
                "1.6": [0, 0, 0],
            }
        },
        "jaw_shard": {
            "rotation": ["math.sin(query.anim_time * 225) * 3", 0, 0]
        },
        "shard_torso": {
            "rotation": {
                "0.0": {"post": [0, 3, 0], "lerp_mode": "catmullrom"},
                "0.8": {"post": [0, -4, -1], "lerp_mode": "catmullrom"},
                "1.6": {"post": [0, 3, 0], "lerp_mode": "catmullrom"},
            }
        },
    },
}

SPRINT = {
    "loop": True,
    "animation_length": 0.55,
    "bones": {
        "root": {
            "position": {
                "0.0": {"post": [0, 0, 0], "lerp_mode": "catmullrom"},
                "0.1375": {"post": [0, 0.9, 0], "lerp_mode": "catmullrom"},
                "0.275": {"post": [0, 0, 0], "lerp_mode": "catmullrom"},
                "0.4125": {"post": [0, 0.9, 0], "lerp_mode": "catmullrom"},
                "0.55": {"post": [0, 0, 0], "lerp_mode": "catmullrom"},
            }
        },
        "body": {
            "rotation": {
                "0.0": {"post": [16, 0, 2], "lerp_mode": "catmullrom"},
                "0.275": {"post": [16, 0, -2], "lerp_mode": "catmullrom"},
                "0.55": {"post": [16, 0, 2], "lerp_mode": "catmullrom"},
            }
        },
        "leg_right": {
            "rotation": {
                "0.0": {"post": [50, 0, 0], "lerp_mode": "catmullrom"},
                "0.275": {"post": [-50, 0, 0], "lerp_mode": "catmullrom"},
                "0.55": {"post": [50, 0, 0], "lerp_mode": "catmullrom"},
            }
        },
        "leg_left": {
            "rotation": {
                "0.0": {"post": [-50, 0, 0], "lerp_mode": "catmullrom"},
                "0.275": {"post": [50, 0, 0], "lerp_mode": "catmullrom"},
                "0.55": {"post": [-50, 0, 0], "lerp_mode": "catmullrom"},
            }
        },
        "arm_right": {
            "rotation": {
                "0.0": {"post": [-60, 0, -18], "lerp_mode": "catmullrom"},
                "0.275": {"post": [30, 0, -12], "lerp_mode": "catmullrom"},
                "0.55": {"post": [-60, 0, -18], "lerp_mode": "catmullrom"},
            }
        },
        "arm_left": {
            "rotation": {
                "0.0": {"post": [30, 0, 12], "lerp_mode": "catmullrom"},
                "0.275": {"post": [-60, 0, 18], "lerp_mode": "catmullrom"},
                "0.55": {"post": [30, 0, 12], "lerp_mode": "catmullrom"},
            }
        },
        # REPASS-MOB: jitter periods snapped to the 0.55 s loop (654.5*0.55 = 360deg,
        # 981.8*0.55 = 540deg half-period zero-crossing) — the old 700-1000 deg/s sines
        # wrapped mid-phase, the worst a ~10deg jaw snap every loop.
        "head": {
            "rotation": ["-12", "math.sin(query.anim_time * 981.8) * 4", 0]
        },
        "jaw_shard": {
            "rotation": ["20 + math.sin(query.anim_time * 654.5) * 10", 0, 0]
        },
        "head_shard": {
            "position": ["math.sin(query.anim_time * 981.8) * 0.3", 0, 0]
        },
        "shard_torso": {
            "position": [0, 0, "math.sin(query.anim_time * 981.8 + 180) * 0.3"]
        },
        "glow_seam": {
            "scale": ["1.3 + math.sin(query.anim_time * 654.5) * 0.2", 1, "1.3 + math.sin(query.anim_time * 654.5) * 0.2"]
        },
    },
}

# REPASS-MOB personality one-shot: the full-body "notice" FREEZE — fired by
# GlitchedWandererEntity.setTarget on first target acquisition (the Storm Hound
# howl trigger pattern). Hard linear snaps on purpose: the stalker locks up
# head-to-toe for half a second, seam flaring, then releases into the kill walk.
NOTICE = {
    "loop": False,
    "animation_length": 0.7,
    "bones": {
        "root": {
            "position": {
                "0.0": [0, 0, 0],
                "0.05": [0.4, 0, -0.3],
                "0.1": [0, 0, 0],
                "0.7": [0, 0, 0],
            }
        },
        "body": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.06": [-6, 0, -2],
                "0.55": [-6, 0, -2],
                "0.7": [0, 0, 0],
            }
        },
        "head": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.06": [-10, 0, 4],
                "0.55": [-10, 0, 4],
                "0.7": [0, 0, 0],
            }
        },
        "arm_right": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.06": [-18, 0, -6],
                "0.55": [-18, 0, -6],
                "0.7": [0, 0, 0],
            }
        },
        "arm_left": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.06": [14, 0, 5],
                "0.55": [14, 0, 5],
                "0.7": [0, 0, 0],
            }
        },
        "jaw_shard": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.06": [26, -8, 6],
                "0.55": [26, -8, 6],
                "0.7": [0, 0, 0],
            }
        },
        "glow_seam": {
            "scale": {
                "0.0": [1, 1, 1],
                "0.1": [1.6, 1, 1.6],
                "0.5": [1.6, 1, 1.6],
                "0.7": [1, 1, 1],
            }
        },
    },
}


def geo_anim():
    geo = json.loads((ASSETS / "geo/entity/glitched_husk.geo.json").read_text())
    geo["minecraft:geometry"][0]["description"]["identifier"] = "geometry.glitched_wanderer"
    _warp_geo(geo)
    WGEO.write_text(json.dumps(geo, indent=1) + "\n")

    anim = json.loads((ASSETS / "animations/entity/glitched_husk.animation.json").read_text())
    anim["animations"] = {
        key.replace("animation.glitched_husk.", "animation.glitched_wanderer."): value
        for key, value in anim["animations"].items()
    }
    # Bespoke locomotion set; attack/glitch_blink/death stay the husk one-shots.
    anim["animations"]["animation.glitched_wanderer.idle"] = IDLE
    anim["animations"]["animation.glitched_wanderer.walk"] = WALK
    anim["animations"]["animation.glitched_wanderer.sprint"] = SPRINT
    anim["animations"]["animation.glitched_wanderer.notice"] = NOTICE
    # REPASS-MOB: wanderer-only attack anticipation ease-in-hard — a mid key back-loads
    # the windup (24% of the raise at 60% of the windup time) so the arm coils instead
    # of ramping linearly. Husk source untouched; keyframe dicts re-sorted after insert.
    attack = anim["animations"]["animation.glitched_wanderer.attack"]["bones"]
    for bone, key, value in (("arm_right", "0.09", [-48, 0, -4]),
                             ("body", "0.09", [-3, -3, 0])):
        channel = dict(attack[bone]["rotation"])
        channel[key] = value
        attack[bone] = dict(attack[bone])
        attack[bone]["rotation"] = {k: channel[k] for k in sorted(channel, key=float)}
    (ASSETS / "animations/entity/glitched_wanderer.animation.json").write_text(
        json.dumps(anim, indent=1) + "\n")


def main():
    geo_anim()
    sheet = entity_sheets()
    scare_face(sheet)
    print("wanderer geo/anim (warped) + sheets + scare face written")


if __name__ == "__main__":
    main()
