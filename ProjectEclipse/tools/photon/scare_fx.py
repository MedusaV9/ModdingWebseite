#!/usr/bin/env python3
"""SCARE (F-064/F-065) — authors the two camera-anchored Photon assets the client
ScareDirector spawns right in front of the player's face (client/scare/ScareScripts):

  eclipse:scare_swarm    a soul-green mote SWARM that erupts and buzzes around a point
                         2.5-4 blocks ahead of the camera — a tight chittering core
                         cloud, stretched rush-streaks blowing outward PAST the camera,
                         one dark announcing puff, and a few lingering stragglers.
                         Fired by the `swarm` jumpscare (twice, staggered) and once,
                         smaller, by `soul_leak` (~70 t one-shot).
  eclipse:scare_wraith   a pale fleeting apparition for `phantom_swoop`: a bone-white
                         smoke smear that SURGES upward through the view with whipping
                         stretched streaks, one hot core pop, then dark tatters sinking
                         away (~55 t one-shot).
  eclipse:whisper_hands  N6 (FX_CENSUS_WAVE13 §6): fog HANDS rising out of a low mist
                         seam and reaching up/inward for the player's face for ~2.5 s
                         before they lose their shape and rot away (~60 t one-shot).

Authoring constraints (why these look the way they do):
  * ScareDirector.spawnPhoton places the FX at camera + view offsets but does NOT
    rotate it toward the camera — the world orientation vs. the view is unknown. So
    every effect here only uses camera-safe motion: radial bursts (read from any
    angle), radial-INWARD converges and vertical surges (up is up for every camera).
    No lateral "screen-space" sweeps. N6's hands therefore climb out of a ring BELOW
    the anchor and converge on it, which reads as "reaching for you" from any heading
    without a single line of rotation code in the director.
  * Spawned 2.5-4.0 blocks ahead at script scale 0.6-1.2 → authored radii stay ≤ ~2.5
    blocks so the cloud fills the view without clipping into the near plane.
  * All three are ONE-SHOTS (looping=False + bursts) — the scare system never loops FX.
  * The executor is anchored to a WORLD POSITION, not to an entity, so it never moves:
    `distanceRate` and `inheritVelocity` are provable no-ops here and stay out. The two
    movement levers that DO apply are `colorBySpeed` (the fast lanes) and
    `random_gradient` (these assets fire over and over across 31 jumpscares — the clone
    look is more expensive here than anywhere else in the mod).

FX-Welle 13 / team B2 polish pass:
  * V2.1 stacking law — every ramp used to be born on its HOT stop. Two dozen alpha
    sprites inside one half-block right in front of the camera composite toward the
    sprite's own colour, so the opening frame read as one green/white blob. Every birth
    tint now starts on the DEEP stop and blooms at t ~= 0.1-0.15.
  * HDR is clamped to the wave-13 ceiling (HDR_CEILING) with the hue ratio preserved;
    `wraith_veil`, `wraith_core` and `swarm_stragglers` were above it.
  * Timing snap against client/scare/ScareScripts (see SCRIPT SYNC below): bursts are
    placed on the script beats they are supposed to punctuate instead of near them.

Usage:  python3 tools/photon/scare_fx.py            # write + validate all three
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, FX_ASSETS_DIR, REPO_ROOT, FxBuilder, SEG_DECAY_TAIL,
    SEG_EASE_OUT_CREST, SEG_POP_SHRINK, F, burst, circle, constant, curve, cylinder,
    dot, gradient, nf3, random_between, random_gradient, sphere, texture_material,
    validate_file)

TEXTURE_DIR = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle"
CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"
#: N6 hand silhouette, authored below (a scare texture in textures/scare is a HUD sheet,
#: not a particle sprite — the fog hands need their own particle-dir texture).
HAND_TEX = "eclipse:textures/particle/hand_reach.png"

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4).
HDR_CEILING = 1.45

# Swarm palette — soul-fire green/cyan, sits with the `swarm` script's green outline
# pulse AND `soul_leak`'s cyan void grade.
SOUL_HOT = (0.45, 1.0, 0.82)
SOUL_MID = (0.14, 0.55, 0.42)
SOUL_DEEP = (0.03, 0.16, 0.11)

# Wraith palette — cold bone-white with a blue-violet edge (the smear_ghost overlay
# that follows it in `phantom_swoop` is the same family).
BONE_HOT = (0.92, 0.95, 1.0)
BONE_MID = (0.55, 0.58, 0.74)
BONE_DEEP = (0.09, 0.09, 0.16)

# Whisper-hands palette — the glitch-zone grey-violet the N6 concept lives in: fog that
# is almost the wall it came out of, with a bruised edge.
HAND_PALE = (0.62, 0.60, 0.70)
HAND_MID = (0.30, 0.27, 0.38)
HAND_DEEP = (0.07, 0.06, 0.11)

# --- SCRIPT SYNC (keep in step with client/scare/ScareScripts) ----------------------
# `swarm`         : photon @3 (scale 1.2) and @20 (scale 0.8); VEX_CHARGE @24;
#                   EVENT_RIFT_SLAM + shake @50.
# `phantom_swoop` : photon @4; PHANTOM_SWOOP @2; PHANTOM_BITE + flash + shake @26.
# `soul_leak`     : photon @20 (scale 0.6) — reuses scare_swarm, quiet tail.
# `whisper_hands` : photon @18 (scale 1.0) and @46 (scale 0.85, offset right); each
#                   instance's SOUL_ESCAPE rasp sits on its own spawn + HAND_REACH_TICK
#                   (script ticks 52 and 80 — ScareScripts.HAND_REACH mirrors the
#                   constant below, so the two files move together).
SWARM_SPAWN_TICK = 3            # script tick of the FIRST swarm photon beat
SWARM_CHARGE_TICK = 24          # VEX_CHARGE
SWARM_SECOND_SPAWN_TICK = 20    # script tick of the SECOND swarm photon beat
SWARM_SLAM_TICK = 50            # EVENT_RIFT_SLAM + shake
WRAITH_SPAWN_TICK = 4           # script tick of the phantom_swoop photon beat
WRAITH_BITE_TICK = 26           # PHANTOM_BITE + flash + shake


def hdr(r, g, b):
    """Clamps an authored HDR triple to HDR_CEILING, preserving the hue ratio."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def color_by_speed(cool_rgb, hot_rgb, lo_bps, hi_bps):
    """`colorBySpeed` body. Input is blocks/second (|realVelocity| * 20) and the result
    MULTIPLIES the lifetime colour, so the hot end sits at/near white. `speedRange` is an
    LDLib2 `Range` whose codec fields are `a`/`b` (NOT fxlib's `min`/`max`)."""
    return {"color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, *cool_rgb), (1.0, *hot_rgb)]),
            "speedRange": {"a": F(float(lo_bps)), "b": F(float(hi_bps))}}


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling ramp inside the same identity;
    each particle rolls its own memoized lerp (anti clone-look)."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


# ---------------------------------------------------------------------------
# 1. eclipse:scare_swarm — chittering mote swarm rushing the camera
# ---------------------------------------------------------------------------
def build_scare_swarm() -> FxBuilder:
    fx = FxBuilder("scare_swarm")
    root = fx.empty("swarm_root")

    # Core cloud: a dense burst of small motes that BUZZ around the anchor point —
    # high orbital drag + strong noise keeps them milling chaotically right in front
    # of the face instead of dispersing.
    # FX-Wave-11 stacking-law pass: 52 motes born inside a 0.5 r ball right in the
    # camera's face stacked their green hdr into one glowing blob. Opening burst
    # 52->24 over a 1.2 r volume, hdr green 1.9->1.45, alpha crest 0.95->0.6.
    (fx.particle_emitter(
            "swarm_motes",
            duration=70, looping=False, start_lifetime=random_between(26, 44),
            start_speed=random_between(0.12, 0.3),
            start_size=nf3(random_between(0.05, 0.14)),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(24)),
                               burst(time=10, count=constant(24))])
        .with_shape(sphere(radius=1.2, thickness=1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(1.2, 2.4), constant(0)),
                radial=random_between(-0.12, 0.1)),          # breathing, not fleeing
            noise=dict(frequency=1.6, position=nf3(0.22)),   # the chitter jitter
            # W13/B2 stacking law: born on SOUL_DEEP, hot only from t=0.12 on. Two dozen
            # motes stacking their birth frame used to composite into one green blob.
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 0.6), (0.75, 0.55), (1.0, 0.0)],
                [(0.0, *SOUL_DEEP), (0.12, *SOUL_HOT), (0.6, *SOUL_MID),
                 (1.0, *SOUL_DEEP)],
                [(0.0, *SOUL_DEEP), (0.12, 0.26, 0.86, 0.94), (0.6, 0.1, 0.42, 0.46),
                 (1.0, 0.02, 0.1, 0.12)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.2, 1.45, 1.45)))
        .with_cull_box((-4.0, -3.0, -4.0), (4.0, 3.0, 4.0)))

    # Rush streaks: fast stretched motes exploding OUT of the core — at 2.5-4 blocks
    # ahead, a radial burst means a fistful of them blow straight past the camera.
    # FX-Wave-11 stacking-law pass: births widened 0.25 -> 0.8 r and the green hdr
    # nerfed to ~1.45 so the two waves read as separate streaks, not a green flash.
    #
    # W13/B2 TIMING SNAP. The waves used to sit at internal 1/14, which put them
    # nowhere in particular. Both jumpscare instances are now aimed at real beats:
    #   wave 2 @21  -> instance 1 (spawned @3)  lands on VEX_CHARGE @24
    #   wave 3 @30  -> instance 2 (spawned @20) lands on EVENT_RIFT_SLAM + shake @50
    # Before this the whole stretch between charge and slam had no photon event at all.
    (fx.particle_emitter(
            "swarm_rush",
            duration=70, looping=False, start_lifetime=random_between(10, 18),
            start_speed=random_between(2.2, 4.2),
            start_size=nf3(random_between(0.06, 0.12)), max_particles=60)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=1, count=constant(22)),
                               burst(time=SWARM_CHARGE_TICK - SWARM_SPAWN_TICK,
                                     count=constant(16)),
                               burst(time=SWARM_SLAM_TICK - SWARM_SECOND_SPAWN_TICK,
                                     count=constant(14))])
        .with_shape(sphere(radius=0.8, thickness=0.4))
        .with_module("colorBySpeed", color_by_speed(SOUL_MID, (0.9, 1.0, 0.98),
                                                    1.5, 12.0))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 1.0), (0.6, 0.5), (1.0, 0.0)],
                [(0.0, *SOUL_DEEP), (0.1, *SOUL_HOT), (1.0, *SOUL_MID)],
                [(0.0, *SOUL_DEEP), (0.1, 0.28, 0.9, 1.0), (1.0, 0.1, 0.4, 0.5)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.3, 1.45, 1.45)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.8,
                       length_scale=2.4)
        .with_cull_box((-6.0, -5.0, -6.0), (6.0, 5.0, 6.0)))

    # Announcing puff: one near-black soot pop the instant the swarm appears — the
    # dark mass the motes seem to pour out of.
    (fx.particle_emitter(
            "swarm_puff",
            duration=40, looping=False, start_lifetime=constant(22),
            start_speed=constant(0.04),
            start_size=nf3(random_between(0.9, 1.4), random_between(0.9, 1.4),
                           random_between(0.9, 1.4)),
            simulation_space="Local", max_particles=6)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(4))])
        .with_shape(sphere(radius=0.3, thickness=1.0))
        .with_curves(
            size_over_lifetime=curve(0.6, 1.5, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.6), (0.7, 0.3), (1.0, 0.0)],
                [(0.0, 0.05, 0.12, 0.09), (1.0, *SOUL_DEEP)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0)))

    # Stragglers: a handful of slow, long-lived motes that keep drifting after the
    # rush — the tail `soul_leak` reads as souls leaking out of the player.
    (fx.particle_emitter(
            "swarm_stragglers",
            duration=70, looping=False, start_lifetime=random_between(45, 65),
            start_speed=random_between(0.05, 0.14),
            start_size=nf3(random_between(0.04, 0.09)), max_particles=16)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=4, count=constant(10))])
        .with_shape(sphere(radius=0.8, thickness=0.6))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.03, 0.09), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.4, 0.9), constant(0))),
            noise=dict(frequency=0.9, position=nf3(0.08)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.7), (0.8, 0.4), (1.0, 0.0)],
                [(0.0, *SOUL_DEEP), (0.2, *SOUL_MID), (1.0, *SOUL_DEEP)],
                [(0.0, *SOUL_DEEP), (0.2, 0.1, 0.44, 0.46), (1.0, 0.02, 0.1, 0.08)]))
        # W13/B2: was (1.1, 1.6, 1.4) — over the 1.45 stacking ceiling.
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 1.6, 1.4)))
        .with_cull_box((-4.0, -2.0, -4.0), (4.0, 5.0, 4.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:scare_wraith — pale apparition surging up through the view
# ---------------------------------------------------------------------------
def build_scare_wraith() -> FxBuilder:
    fx = FxBuilder("scare_wraith")
    root = fx.empty("wraith_root")

    # Body: a few big pale smoke quads that SURGE upward fast and tear apart — the
    # smear of the wraith itself. Vertical motion reads from every camera angle.
    (fx.particle_emitter(
            "wraith_body",
            duration=55, looping=False, start_lifetime=random_between(16, 26),
            start_speed=constant(0.05),
            start_size=nf3(random_between(0.8, 1.5), random_between(1.2, 2.2),
                           random_between(0.8, 1.5)),
            simulation_space="Local", max_particles=10)
        .child_of(root)
        .at(0.0, -0.8, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(6))])
        .with_shape(sphere(radius=0.4, thickness=1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.9, 1.6), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.5, 1.1), constant(0))),
            size_over_lifetime=curve(0.5, 1.6, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 0.75), (0.6, 0.4), (1.0, 0.0)],
                [(0.0, *BONE_DEEP), (0.12, *BONE_HOT), (0.55, *BONE_MID),
                 (1.0, *BONE_DEEP)],
                [(0.0, *BONE_DEEP), (0.12, 0.78, 0.82, 0.95), (0.55, 0.4, 0.43, 0.6),
                 (1.0, 0.06, 0.06, 0.12)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-3.0, -2.0, -3.0), (3.0, 8.0, 3.0)))

    # Veil streaks: stretched pale whips riding up with the body — the "swoop" lines.
    (fx.particle_emitter(
            "wraith_veil",
            duration=55, looping=False, start_lifetime=random_between(10, 16),
            start_speed=random_between(0.3, 0.7),
            start_size=nf3(random_between(0.08, 0.16)), max_particles=40)
        .child_of(root)
        .at(0.0, -0.8, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(18)),
                               burst(time=6, count=constant(12))])
        .with_shape(sphere(radius=0.5, thickness=0.5))
        .with_module("colorBySpeed", color_by_speed(BONE_MID, (1.0, 1.0, 1.0), 2.0, 14.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(1.4, 2.6), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 0.95), (0.7, 0.45), (1.0, 0.0)],
                [(0.0, *BONE_DEEP), (0.1, *BONE_HOT), (1.0, *BONE_MID)],
                [(0.0, *BONE_DEEP), (0.1, 0.84, 0.88, 1.0), (1.0, 0.42, 0.46, 0.66)]))
        # W13/B2: was (1.6, 1.7, 2.0) — clamped to the 1.45 stacking ceiling.
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.6, 1.7, 2.0)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=3.0)
        .with_cull_box((-3.0, -2.0, -3.0), (3.0, 9.0, 3.0)))

    # Core pop: ONE hot flash right as it passes (t=2) — the moment the swoop sound
    # lands in the `phantom_swoop` script.
    (fx.particle_emitter(
            "wraith_core",
            duration=30, looping=False, start_lifetime=constant(10),
            start_speed=constant(0), start_size=nf3(1.4), max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=2, count=constant(1))])
        .with_shape(dot())
        # W13/B2: was (2.0, 2.1, 2.6) — the single worst offender against the ceiling.
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(2.0, 2.1, 2.6)))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.8, [SEG_POP_SHRINK]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.06, 0.4), (0.15, 0.85), (1.0, 0.0)],
                [(0.0, *BONE_MID), (0.15, *BONE_HOT), (1.0, *BONE_MID)]))
        .with_cull_box((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0)))

    # Tatters: dark scraps left behind, sinking slowly — the wraith is already gone.
    # W13/B2 TIMING SNAP: a second, harder burst at the BITE. The script fires
    # PHANTOM_BITE + flash + shake at 26, i.e. internal tick 22 — at which point the
    # shipped asset was completely spent, so the loudest beat of the whole jumpscare had
    # no photon image at all. The recoil burst gives the bite something to tear.
    (fx.particle_emitter(
            "wraith_tatters",
            duration=55, looping=False, start_delay=constant(6),
            start_lifetime=random_between(22, 36), start_speed=constant(0.06),
            start_size=nf3(random_between(0.3, 0.6), random_between(0.5, 0.9),
                           random_between(0.3, 0.6)),
            simulation_space="Local", max_particles=22)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(9)),
                               burst(time=WRAITH_BITE_TICK - WRAITH_SPAWN_TICK - 6,
                                     count=constant(8))])
        .with_shape(sphere(radius=0.9, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.22, -0.08), constant(0))),
            noise=dict(frequency=0.7, position=nf3(0.06)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.5), (0.75, 0.3), (1.0, 0.0)],
                [(0.0, *BONE_DEEP), (1.0, 0.04, 0.04, 0.08)],
                [(0.0, 0.07, 0.06, 0.13), (1.0, 0.03, 0.03, 0.06)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-3.0, -6.0, -3.0), (3.0, 3.0, 3.0)))

    # The bite itself: one DARK swallow at internal 22 (= script tick 26). Deliberately
    # not a second white flash — the script already fires a fullscreen Flash on that
    # tick, and the authoring law allows one bright pop per ~2 s. This is the shadow
    # under it: a fast dark bloom that eats the frame the flash just lit.
    (fx.particle_emitter(
            "wraith_bite",
            duration=40, looping=False, start_lifetime=constant(12),
            start_speed=constant(0.05),
            start_size=nf3(random_between(1.0, 1.7), random_between(1.0, 1.7),
                           random_between(1.0, 1.7)),
            simulation_space="Local", max_particles=6)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=WRAITH_BITE_TICK - WRAITH_SPAWN_TICK,
                                     count=constant(4))])
        .with_shape(sphere(radius=0.35, thickness=1.0))
        .with_curves(
            size_over_lifetime=curve(0.55, 1.7, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 0.72), (0.6, 0.35), (1.0, 0.0)],
                [(0.0, 0.05, 0.05, 0.1), (1.0, *BONE_DEEP)],
                [(0.0, 0.04, 0.04, 0.09), (1.0, 0.07, 0.07, 0.13)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-4.0, -3.0, -4.0), (4.0, 4.0, 4.0)))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:whisper_hands — N6: fog hands reaching out of the seam (one-shot, 60 t)
# ---------------------------------------------------------------------------
#: Ring the hands climb out of, and how far below the anchor the seam sits.
HAND_RING_RADIUS = 1.45
HAND_SEAM_DROP = -1.25
#: Tick the reach peaks / the hands lose their shape (script sound lands here).
HAND_REACH_TICK = 34


def build_whisper_hands() -> FxBuilder:
    """N6 (FX_CENSUS_WAVE13 §6): "Nebelhände greifen aus Glitch-Zonen-Rändern nach dem
    Spieler (2-3 s, dann Zerfall)."

    Anchoring: `GlitchZoneFx` only publishes effect/strength/colour/origin — it has no
    zone RADIUS and no public accessor, so a true zone-EDGE anchor is impossible without
    a B4-owned change (patch snippet in B2_MOB_REPORT §7). Per the brief's fallback this
    ships as the ScareDirector variant, anchored in front of the player along the view.

    Rotation: `spawnPhoton` does not rotate toward the camera, so the whole beat is built
    out of camera-safe motion only. The hands are born on a ring BELOW the anchor and
    climb up + radially INWARD toward it — "up" and "inward" read identically from every
    heading, so the grab works whether the player is facing north or straight at the sky,
    with zero rotation code in the director.

    Shape: a real hand silhouette (hand_reach.png, authored below). Without it the beat is
    six smoke balls and the entire concept is illegible; VerticalBillboard keeps the palms
    upright and turned toward the camera as they rise.
    """
    fx = FxBuilder("whisper_hands")
    root = fx.empty("hands_root")
    cull = ((-4.0, -4.0, -4.0), (4.0, 4.0, 4.0))

    # The seam: a low, wide mist disc the hands appear to be pushing through. Born dark
    # (V2.1) and never bright — it is the wall, not an effect.
    (fx.particle_emitter(
            "fog_bed",
            duration=60, looping=False, start_lifetime=random_between(34, 52),
            start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(0.7, 1.3), random_between(0.35, 0.6),
                           random_between(0.7, 1.3)),
            simulation_space="Local", max_particles=14)
        .child_of(root)
        .at(0.0, HAND_SEAM_DROP, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(8)),
                               burst(time=10, count=constant(4))])
        .with_shape(cylinder(radius=HAND_RING_RADIUS, thickness=0.55),
                    scale=nf3(1.0, 0.25, 1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.04, 0.12), constant(0)),
                radial=random_between(-0.8, -0.2)),
            noise=dict(frequency=0.5, position=nf3(0.05)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.22, 0.42), (0.7, 0.3), (1.0, 0.0)],
                [(0.0, *HAND_DEEP), (0.3, *HAND_MID), (1.0, *HAND_DEEP)],
                [(0.0, *HAND_DEEP), (0.3, 0.24, 0.23, 0.32), (1.0, 0.05, 0.05, 0.09)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(*cull))

    # The hands. radial is scaled x0.01/tick, linear x0.05/tick, so -2.6 radial is
    # ~0.5 block/s of closing and 0.5 linear is ~0.5 block/s of climb: over the ~40 t
    # life they travel roughly a block up and a block in — a reach, not a lunge.
    (fx.particle_emitter(
            "fog_hands",
            duration=52, looping=False, start_lifetime=random_between(34, 46),
            start_speed=constant(0.03),
            start_size=nf3(random_between(0.42, 0.62), random_between(0.72, 1.05),
                           random_between(0.42, 0.62)),
            start_rotation=nf3(constant(0), constant(0), random_between(-14.0, 14.0)),
            simulation_space="Local", max_particles=9)
        .child_of(root)
        .at(0.0, HAND_SEAM_DROP, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=2, count=constant(3)),
                               burst(time=9, count=constant(2)),
                               burst(time=17, count=constant(2))])
        .with_shape(cylinder(radius=HAND_RING_RADIUS, thickness=0.0),
                    scale=nf3(1.0, 0.12, 1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.42, 0.62), constant(0)),
                radial=random_between(-3.0, -2.2)),
            rotation_over_lifetime=random_between(-2.5, 2.5),
            # Grow while reaching, then lose the shape entirely — the "Zerfall".
            size_over_lifetime=curve(0.0, 1.25, [
                (0.0, 0.5, 0.12, 0.86, 0.3, 1.0, 0.55, 1.0),
                (0.55, 1.0, 0.72, 0.96, 0.86, 0.4, 1.0, 0.0)]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.18, 0.62), (0.68, 0.5), (1.0, 0.0)],
                [(0.0, *HAND_DEEP), (0.25, *HAND_MID), (0.7, *HAND_PALE),
                 (1.0, *HAND_DEEP)],
                [(0.0, *HAND_DEEP), (0.25, 0.24, 0.22, 0.33), (0.7, 0.5, 0.5, 0.6),
                 (1.0, 0.05, 0.05, 0.1)]))
        .with_material(texture_material(HAND_TEX, blend=BLEND_ALPHA))
        # Upright and turned toward the camera: a hand from any heading.
        .with_renderer(render_mode="VerticalBillboard", vertex_sorting="DISTANCE")
        .with_cull_box(*cull))

    # Fingertip wisps: the fog the fingers shed as they close in. colorBySpeed is the one
    # movement lever that applies to a world-anchored executor — it makes the fastest
    # (closest-reaching) wisps the palest ones.
    (fx.particle_emitter(
            "finger_wisps",
            duration=52, looping=False, start_lifetime=random_between(14, 24),
            start_speed=random_between(0.06, 0.18),
            start_size=nf3(random_between(0.03, 0.07)), max_particles=34)
        .child_of(root)
        .at(0.0, HAND_SEAM_DROP + 0.55, 0.0)
        .with_emission(rate=constant(0.55),
                       bursts=[burst(time=HAND_REACH_TICK, count=constant(10))])
        .with_shape(cylinder(radius=HAND_RING_RADIUS * 0.85, thickness=0.3),
                    scale=nf3(1.0, 0.5, 1.0))
        .with_module("colorBySpeed", color_by_speed(HAND_MID, HAND_PALE, 0.4, 3.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.25, 0.5), constant(0)),
                radial=random_between(-2.4, -1.4)),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.5), (0.75, 0.3), (1.0, 0.0)],
                [(0.0, *HAND_DEEP), (0.3, *HAND_MID), (1.0, *HAND_DEEP)],
                [(0.0, *HAND_DEEP), (0.3, 0.36, 0.33, 0.45), (1.0, 0.06, 0.06, 0.1)]))
        .with_material(texture_material(CIRCLE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(*cull))

    # The failure: right after the reach peaks the hands come apart into soot instead of
    # touching you. No flash, no bang — N6 is a dread beat, the horror is that they
    # ALMOST reached.
    (fx.particle_emitter(
            "grasp_rot",
            duration=60, looping=False, start_delay=constant(HAND_REACH_TICK),
            start_lifetime=random_between(16, 26), start_speed=random_between(0.05, 0.2),
            start_size=nf3(random_between(0.1, 0.22)),
            simulation_space="Local", max_particles=20)
        .child_of(root)
        .at(0.0, HAND_SEAM_DROP + 0.9, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(14))])
        .with_shape(cylinder(radius=HAND_RING_RADIUS * 0.6, thickness=0.6),
                    scale=nf3(1.0, 0.7, 1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.28, -0.1), constant(0))),
            noise=dict(frequency=0.8, position=nf3(0.09)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.45), (0.7, 0.22), (1.0, 0.0)],
                [(0.0, *HAND_MID), (1.0, *HAND_DEEP)],
                [(0.0, 0.22, 0.2, 0.3), (1.0, 0.04, 0.04, 0.08)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(*cull))
    return fx


# ---------------------------------------------------------------------------
# hand_reach.png — deterministic N6 hand silhouette (PIL, safe to re-run)
# ---------------------------------------------------------------------------
def write_textures() -> list:
    """64x64 white hand silhouette with soft alpha (tinted at runtime by the ramps).

    Palm + four fingers + thumb, all reaching toward the TOP of the sheet, with the wrist
    end faded out so the quad dissolves into the mist instead of ending on a hard edge
    (that fade also keeps the read honest if a future Photon build flips V).
    """
    from PIL import Image

    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()

    # Capsule field: alpha = softened distance to the nearest bone segment.
    # (cx0, cy0, cx1, cy1, radius) in normalised sheet coords, y = 0 at the top.
    palm = (0.5, 0.80, 0.5, 0.58, 0.20)
    fingers = [
        (0.34, 0.62, 0.29, 0.30, 0.062),   # index
        (0.45, 0.60, 0.44, 0.20, 0.066),   # middle (longest)
        (0.56, 0.60, 0.59, 0.25, 0.062),   # ring
        (0.66, 0.64, 0.72, 0.38, 0.054),   # little
        (0.36, 0.76, 0.18, 0.58, 0.062),   # thumb, splayed
    ]

    def capsule_distance(x, y, seg):
        x0, y0, x1, y1, _ = seg
        dx, dy = x1 - x0, y1 - y0
        length_sq = dx * dx + dy * dy
        t = 0.0 if length_sq == 0.0 else ((x - x0) * dx + (y - y0) * dy) / length_sq
        t = max(0.0, min(1.0, t))
        return math.hypot(x - (x0 + t * dx), y - (y0 + t * dy)), t

    for iy in range(size):
        for ix in range(size):
            nx = (ix + 0.5) / size
            ny = (iy + 0.5) / size
            best = 0.0
            for seg in [palm] + fingers:
                distance, t = capsule_distance(nx, ny, seg)
                # Fingers taper toward their tip; the palm keeps its width.
                radius = seg[4] * (1.0 - 0.35 * t) if seg is not palm else seg[4]
                if distance >= radius:
                    continue
                best = max(best, min(1.0, (radius - distance) / (radius * 0.55)))
            if best <= 0.0:
                continue
            # Wrist fade: nothing survives below y = 0.86, half strength from 0.74.
            if ny > 0.74:
                best *= max(0.0, (0.90 - ny) / 0.16)
            px[ix, iy] = (255, 255, 255, int(max(0.0, min(1.0, best)) * 255))
    path = TEXTURE_DIR / "hand_reach.png"
    img.save(path)
    return [path]


BUILDERS = {
    "scare_swarm.fx": build_scare_swarm,
    "scare_wraith.fx": build_scare_wraith,
    "whisper_hands.fx": build_whisper_hands,
}


def main() -> int:
    rc = 0
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    for path in write_textures():
        print(f"WROTE {path.relative_to(REPO_ROOT)}")
    for name, builder in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        b = builder()
        raw_len, gz_len = b.write(path)  # write() round-trip-validates
        b.write_fxproj(path.with_suffix(".fxproj"))  # binary-diff law sibling
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path} (raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
