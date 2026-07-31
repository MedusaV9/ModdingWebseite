#!/usr/bin/env python3
"""C18 Backrooms art companion (IDEAS-backrooms_finale §A3.1/§A4; MOB-GLITCH v2).

MB5 (MOB_ITEM_CENSUS §5 Welle M-B) moved this driver out of the `scripts/skin_gen/`
outlier slot (census §7 falle F-11) into `scripts/geckolib_gen/mobs/` next to its 19
siblings. The file name stays `backrooms_wanderer` (not `glitched_wanderer`) because
this driver is the Backrooms ART COMPANION, not a single mob's skin painter: it also
writes `textures/gui/backrooms_scare.png`, which belongs to no geo triple.

Generates the Wanderer's asset set from the shipped glitched_husk sources —
run from the ProjectEclipse root; deterministic (seeded), idempotent:

  1. geo: the husk geometry re-identified to the frozen `glitched_wanderer`
     triple id AND warped subtly WRONG (MOB-GLITCH): both arms stretched too
     long (the fingertips reach past the knee line), head + face shards
     deflated small (inflate < 0), the dislocated jaw's UV re-parked clear of
     the taller arm strip. The proportions are off by just enough to read as
     "person-shaped, but no" down a long corridor.
     MB5 additionally appends the cubeless locator `fx_shroud_anchor` — the
     published emitter anchor for B2's `eclipse:wanderer_static_shroud`
     (see docs/uv/backrooms_wanderer.md §FX).
  2. animations: the husk set re-keyed to `animation.glitched_wanderer.*`
     (load-bearing: GlitchedMonster builds anim ids off geoId()) with four
     bespoke replacements/additions — `idle` (near-still + the head-turn-TOO-FAR
     beat), `walk` (unsettling slow corridor pace, head locked level), `sprint`
     (the lookaway burst — GlitchedWandererEntity plays it while a gaze-burst
     speed modifier is live) and `notice` (the freeze-and-stare that precedes it).
     `notice` -> `sprint` is THE Backrooms horror beat; both clips are written on
     the 0.05 s tick grid so the server freeze and B5/B2's cues can line up with
     them exactly. attack/glitch_blink/death stay the renamed husk one-shots.
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

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "src/main/resources/assets/eclipse"
ENT = ASSETS / "textures/entity"
GUI = ASSETS / "textures/gui"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glitched_husk as husk  # noqa: E402

WGEO = ASSETS / "geo/entity/glitched_wanderer.geo.json"

RNG = random.Random(0xBAC2)  # deterministic output; re-runs are byte-stable

# MB5 (census §5 row MB5-d): published emitter locator for `wanderer_static_shroud`.
FX_ANCHOR_BONE = "fx_shroud_anchor"

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
    # MB5 (census §5 row MB5-d): the published FX locator for B2's
    # `wanderer_static_shroud`. Cubeless (paints nothing, costs nothing), parented to
    # `root` and NOT `body` on purpose — the shroud is a column of haze around the
    # thing, so it must NOT inherit the 20 deg sprint torso pitch.
    # Pivot y = 15.36 px reproduces B2's shipped anchor at rest: the LoopRow in
    # PhotonMobFx offsets `eye + (0,-0.7,0)`, eyeHeight is 1.66 (BackroomsEntities),
    # so 1.66 - 0.70 = 0.96 blocks = 15.36 model px.
    # The bone carries NO animation channel of its own in any clip, so a bone-bound
    # emitter differs from today's world-space row by exactly the `root` bone's motion
    # and nothing else: 0 px in idle/notice-hold, <=1.35 px (0.084 blocks) in sprint,
    # plus the glitch_blink stutter and the death sink — which is precisely the drift a
    # shroud SHOULD inherit. See docs/uv/backrooms_wanderer.md §FX.
    geo["minecraft:geometry"][0]["bones"].append({
        "name": FX_ANCHOR_BONE,
        "parent": "root",
        "pivot": [0, 15.36, 0],
    })


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

# MB5 (census §5 row MB5-b) — the sprint is the LOOKAWAY BURST, and it must not read
# as "a person running fast". Four deliberate wrongnesses, all verified against
# GeckoLib 4.9.2's own parser (see MB5_WANDERER_REPORT §4):
#
#   1. RIGID ARMS. They do not swing at all. Both are pinned to a fixed, asymmetric
#      pose and, because they hang off a torso pitched 20 deg forward, they trail
#      straight back like a dragged mannequin's. The only motion is a sub-degree
#      rattle (right) and two 1-tick spasms (left).
#   2. STEPPED TORSO / HEAD. `{"pre": .., "post": ..}` is a TRUE step in GeckoLib
#      (the pre key lands at t-0.001 s = 0.02 ticks — measured, not assumed), so the
#      torso yaw advances in four discrete jumps instead of rolling, and the head
#      snaps sideways for exactly one tick, twice per cycle. That is the
#      "ruckelnde Frame-Versätze" of the census row.
#   3. BROKEN GAIT. The legs are NOT contralateral: the right leg peaks forward at
#      0.00 s, the left at 0.40 s of a 0.60 s cycle (240 deg apart, not 180 deg), with
#      different amplitudes (62/-44 vs 46/-34) — a limping scuttle. The right leg
#      additionally DROPS A FRAME at the back of its stride (0.30 s and 0.35 s carry
#      the same value) and then catches up on a steeper slope.
#   4. DEAD-LEVEL HEAD. head.x = -20 exactly cancels body.x = +20, so the skull stays
#      world-level and locked on you while the body is thrown forward — except during
#      the 2-tick torso pitch hitch (0.30-0.40 s), where the head does NOT compensate
#      and dips 6 deg. All linear: no catmullrom anywhere in the cycle.
#
# Cycle length 0.55 -> 0.60 s: 12 ticks, so every beat lands on a whole tick AND the
# molang base frequency becomes exactly 360/0.6 = 600 deg/s (harmonics 1200/1800), i.e.
# value- AND derivative-continuous over the loop seam. The old 654.5/981.8 pair closed
# only to ~1e-4 deg and 981.8 (= 1.5 cycles) flipped its derivative at the seam.
SPRINT = {
    "loop": True,
    "animation_length": 0.6,
    "bones": {
        # Limp bob: high hop on the strong side (1.35 px, lists +X), a barely-there
        # 0.60 px lift on the weak side, and a hard landing that undershoots to -0.15 Z.
        "root": {
            "position": {
                "0.0": [0, 0, 0],
                "0.05": [0, 0.55, 0],
                "0.1": [0.15, 1.35, 0],
                "0.15": [0.15, 1.1, 0],
                "0.2": [0.05, 0.35, 0],
                "0.25": [0, 0, -0.15],
                "0.3": [0, 0.05, 0],
                "0.35": [-0.12, 0.42, 0],
                "0.4": [-0.12, 0.6, 0],
                "0.45": [-0.12, 0.48, 0],
                "0.5": [0, 0.18, 0],
                "0.55": [0, 0, 0],
                "0.6": [0, 0, 0],
            }
        },
        "body": {
            "rotation": {
                "0.0": [20, 0, 2],
                "0.15": {"pre": [20, 0, 2], "post": [20, -5, 2]},
                "0.3": {"pre": [20, -5, 2], "post": [26, 4, -2]},
                "0.4": {"pre": [26, 4, -2], "post": [20, 4, -2]},
                "0.45": {"pre": [20, 4, -2], "post": [20, -3, 2]},
                "0.55": {"pre": [20, -3, 2], "post": [20, 0, 2]},
                "0.6": [20, 0, 2],
            }
        },
        "leg_right": {
            "rotation": {
                "0.0": [62, 0, 0],
                "0.15": [12, 0, 0],
                "0.3": [-44, 0, 0],
                "0.35": [-44, 0, 0],
                "0.45": [4, 0, 0],
                "0.6": [62, 0, 0],
            }
        },
        "leg_left": {
            "rotation": {
                "0.0": [-24, 0, 0],
                "0.1": [-34, 0, 0],
                "0.25": [8, 0, 0],
                "0.4": [46, 0, 0],
                "0.5": [16, 0, 0],
                "0.6": [-24, 0, 0],
            }
        },
        # Rigid. 1800*0.6 = 1080 deg = 3 whole cycles -> seamless.
        "arm_right": {
            "rotation": ["3 + math.sin(query.anim_time * 1800) * 1.4", 0, -5]
        },
        "arm_left": {
            "rotation": {
                "0.0": [-7, 0, 8],
                "0.1": {"pre": [-7, 0, 8], "post": [-11, 0, 8]},
                "0.15": {"pre": [-11, 0, 8], "post": [-7, 0, 8]},
                "0.35": {"pre": [-7, 0, 8], "post": [-7, 0, 17]},
                "0.4": {"pre": [-7, 0, 17], "post": [-7, 0, 8]},
                "0.6": [-7, 0, 8],
            }
        },
        "head": {
            "rotation": {
                "0.0": [-20, 0, 3],
                "0.2": {"pre": [-20, 0, 3], "post": [-20, 11, 3]},
                "0.25": {"pre": [-20, 11, 3], "post": [-20, 0, 3]},
                "0.5": {"pre": [-20, 0, 3], "post": [-19, -7, 3]},
                "0.55": {"pre": [-19, -7, 3], "post": [-20, 0, 3]},
                "0.6": [-20, 0, 3],
            }
        },
        "jaw_shard": {
            "rotation": ["26 + math.sin(query.anim_time * 1800) * 10", 0,
                         "math.sin(query.anim_time * 1200) * 5"]
        },
        # The loose face plate does not slide — it TELEPORTS, once per step.
        "head_shard": {
            "position": {
                "0.0": [0, 0, 0],
                "0.25": {"pre": [0, 0, 0], "post": [0.6, -0.25, 0]},
                "0.3": {"pre": [0.6, -0.25, 0], "post": [0, 0, 0]},
                "0.45": {"pre": [0, 0, 0], "post": [-0.45, 0.2, 0]},
                "0.5": {"pre": [-0.45, 0.2, 0], "post": [0, 0, 0]},
                "0.6": [0, 0, 0],
            }
        },
        "shard_torso": {
            "position": ["math.sin(query.anim_time * 600) * 0.35", 0,
                         "math.sin(query.anim_time * 1200 + 180) * 0.3"]
        },
        # Two flares per cycle, phased onto the two footfalls (t = 0.00 / 0.30 s).
        "glow_seam": {
            "scale": ["1.3 + math.sin(query.anim_time * 1200 + 90) * 0.35", 1,
                      "1.3 + math.sin(query.anim_time * 1200 + 90) * 0.35"]
        },
        # FX_ANCHOR_BONE is deliberately NOT keyed here (nor in any other clip) — see
        # _warp_geo(): the anchor's whole value to B2 is that it is PREDICTABLE.
    },
}

# MB5 (census §5 row MB5-a) — THE horror beat of the Backrooms. Five acts over
# 1.05 s = 21 ticks. TICK GRID LAW: every single timestamp below is a multiple of
# 0.05 s, because the two consumers of this clip can only act on whole ticks — the
# server freeze (GlitchedWandererEntity.NoticeFreezeGoal holds MOVE+LOOK for exactly
# NOTICE_TICKS, so the mob cannot slide while its legs are planted) and B5/B2, whose
# flicker/audio cues are scheduled off the trigger tick. A beat at 0.04 s or 0.86 s
# cannot be cued; a beat at 0.05 s or 0.85 s can. Full timing analysis + the cue table
# live in MB5_WANDERER_REPORT §3.
#
#   ANTICIPATION  0.00-0.05  t+0..t+1. Head turns 9 deg AWAY (it was looking somewhere
#              (t+0..1)      else — no it wasn't), seam INHALES to 0.82x. The tell.
#   SNAP          0.10       t+2. TRUE step (pre/post): 18 deg pitch + 12 deg yaw +
#              (t+2)         10 deg roll in one frame, jaw drops 40 deg, seam flares
#                            0.82 -> 2.05, root jolts back. The census asks for a 0.1 s
#                            head snap; this one ARRIVES at exactly 0.10 s and the
#                            travel itself is instantaneous — necks do not do that.
#                            NB the head channel is ADDITIVE over GeckoLib's live head
#                            tracking (DefaultedEntityGeoModel does head.setRotX(
#                            head.getRotX() + headPitch)), so the snap is a delta on top
#                            of wherever you are standing: it can never be swallowed.
#   CATCH-UP      0.15/0.20  t+3 / t+4. The BODY arrives ONE TICK after the head — the
#              (t+3..4)      single strongest "that is not a person" read — and the left
#                            limbs one tick after the right (the rig is asymmetric, so
#                            the catch-up is too).
#   HOLD          0.25-0.85  t+5..t+17. 0.60 s / 12 ticks of frozen stare. Not perfectly
#              (t+5..17)     still: `shard_torso` carries a sub-pixel 3.3 Hz tremor, the
#                            seam breathes down 1.75 -> 1.58, and ONE dropped-frame
#                            corruption twitch fires at 0.50 s (head) / 0.55 s (jaw +
#                            seam) — 1 tick apart, so the face tears before the jaw does.
#   LOAD/RELEASE  0.85-1.05  t+17..t+21. It coils (torso pitches +12, legs load, seam
#              (t+17..21)    swells 2.35x) and uncoils to EXACT neutral. Landing on
#                            neutral is deliberate: when the one-shot ends, the action
#                            controller (transitionLength 0) drops its bones with no
#                            blend, and `idle` sits within ~1 deg of neutral, so the
#                            handoff to idle/walk/sprint is invisible.
NOTICE = {
    "loop": False,
    "animation_length": 1.05,
    "bones": {
        "root": {
            "position": {
                "0.0": [0, 0, 0],
                "0.05": [0, 0.15, 0.2],
                "0.1": {"pre": [0, 0.15, 0.2], "post": [0.45, -0.25, -0.4]},
                "0.15": [0, -0.1, -0.15],
                "0.25": [0, 0, 0],
                "0.85": [0, 0, 0],
                "0.95": [0, -0.55, 0.25],
                "1.05": [0, 0, 0],
            }
        },
        # The body does NOT move on the snap — it arrives one full tick late, hard.
        "body": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.05": [1.5, 0, 0],
                "0.1": [1.5, 0, 0],
                "0.15": {"pre": [1.5, 0, 0], "post": [-8, 5, -3]},
                "0.25": [-7, 4.5, -2.6],
                "0.85": [-7, 4.5, -2.6],
                "0.95": [12, 2, -1],
                "1.05": [0, 0, 0],
            }
        },
        "head": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.05": [4, 9, -3],
                "0.1": {"pre": [4, 9, -3], "post": [-14, -3, 7]},
                "0.25": [-14, -3, 7],
                "0.5": {"pre": [-14, -3, 7], "post": [-15.5, -12, 9]},
                "0.55": {"pre": [-15.5, -12, 9], "post": [-14, -3, 7]},
                "0.85": [-14, -3, 7],
                "0.95": [-4, -1, 4],
                "1.05": [0, 0, 0],
            }
        },
        "arm_right": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.15": {"pre": [0, 0, 0], "post": [-24, 0, -10]},
                "0.85": [-24, 0, -10],
                "0.95": [-34, 0, -14],
                "1.05": [0, 0, 0],
            }
        },
        "arm_left": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.2": {"pre": [0, 0, 0], "post": [17, 0, 8]},
                "0.85": [17, 0, 8],
                "0.95": [26, 0, 12],
                "1.05": [0, 0, 0],
            }
        },
        # MB5 bug fix: the 0.7 s version animated no legs at all, so the base
        # controller kept striding underneath and the "full-body freeze" walked.
        "leg_right": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.15": {"pre": [0, 0, 0], "post": [9, 0, 0]},
                "0.85": [9, 0, 0],
                "0.95": [-14, 0, 0],
                "1.05": [0, 0, 0],
            }
        },
        "leg_left": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.2": {"pre": [0, 0, 0], "post": [-7, 0, 0]},
                "0.85": [-7, 0, 0],
                "0.95": [16, 0, 0],
                "1.05": [0, 0, 0],
            }
        },
        "jaw_shard": {
            "rotation": {
                "0.0": [0, 0, 0],
                "0.05": [-6, 0, 0],
                "0.1": {"pre": [-6, 0, 0], "post": [34, -10, 8]},
                "0.25": [30, -9, 7],
                "0.5": [30, -9, 7],
                "0.55": {"pre": [30, -9, 7], "post": [40, -15, 11]},
                "0.6": {"pre": [40, -15, 11], "post": [30, -9, 7]},
                "0.85": [30, -9, 7],
                "0.95": [22, -4, 4],
                "1.05": [0, 0, 0],
            }
        },
        # The face plate does not follow the skull — it slides on, one tick late.
        "head_shard": {
            "position": {
                "0.0": [0, 0, 0],
                "0.1": [0, 0, 0],
                "0.15": [0.55, -0.2, -0.35],
                "0.25": [0.2, -0.05, -0.12],
                "0.85": [0.2, -0.05, -0.12],
                "1.05": [0, 0, 0],
            },
        },
        "shard_torso": {
            # A hold that is PERFECTLY still reads as a frozen GAME, not a frozen mob:
            # a sub-pixel tremor keeps it alive without breaking the stare. 1200 and
            # 2400 deg/s are the two lowest harmonics that are exactly 0 at BOTH ends of
            # a 1.05 s clip (1200*1.05 = 1260 = 7*180; 2400*1.05 = 2520 = 14*180), so the
            # tremor neither pops in at t=0 nor leaves a residual offset behind when the
            # controller drops the bone at t=1.05.
            "position": ["math.sin(query.anim_time * 1200) * 0.09", 0,
                         "math.sin(query.anim_time * 2400) * 0.07"],
            "rotation": {
                "0.0": [0, 0, 0],
                "0.15": {"pre": [0, 0, 0], "post": [0, -11, 3]},
                "0.85": [0, -11, 3],
                "1.05": [0, 0, 0],
            },
        },
        "glow_seam": {
            "scale": {
                "0.0": [1, 1, 1],
                "0.05": [0.82, 1, 0.82],
                "0.1": {"pre": [0.82, 1, 0.82], "post": [2.05, 1.15, 2.05]},
                "0.2": [1.75, 1.08, 1.75],
                "0.5": [1.62, 1.05, 1.62],
                "0.55": {"pre": [1.62, 1.05, 1.62], "post": [2.0, 1.12, 2.0]},
                "0.6": [1.66, 1.06, 1.66],
                "0.85": [1.58, 1.04, 1.58],
                "0.95": [2.35, 1.2, 2.35],
                "1.05": [1, 1, 1],
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
