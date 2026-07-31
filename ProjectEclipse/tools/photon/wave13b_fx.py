#!/usr/bin/env python3
"""wave13b_fx — WAVE-13/B1 generator: Photon hero legs for three Quasar-only cues.

FX_CENSUS_WAVE13 §3 lists ten Quasar-only lanes (constants in `S2CQuasarPayload`, no
Photon row anywhere). Three of them are the most-seen FX in the whole event, and this
script authors their hero versions. The Quasar emitters stay on disk and keep firing as
the fallback lane underneath (baseline law) — nothing under `quasar/emitters/` is touched.

    eclipse:hero_heart_burst          the heart-fragment deposit at the altar:
                                      core flash -> shards -> INDRAW -> acceptance
                                      pulse -> afterglow.
    eclipse:hero_boss_slam            every boss ground slam: shock ring + real
                                      ballistic ground chips + a dust curtain that
                                      rolls out and then LIES THERE.
    eclipse:hero_expand_materialize   ring expansion: materialization columns rising
                                      out of the new ground + a glint veil dissolving
                                      in three staggered waves.

Wiring, sender inventory and the integrator patch snippet for the one foreign dispatch
point (`PhotonBridge.enhanceQuasarCue`): docs/plans_v3/session_0730/B1_HEROLEGS_REPORT.md.
Registrar (B1-owned): `veilfx/Wave13bPhotonFxRows`.


================  ANCHORS — the three cues do NOT share a frame  ================

The Quasar payload carries a bare position, no orientation and no floor probe, so each
asset has to know where the ground is relative to its own anchor:

  * `heart_burst`    FREE AIR. Fired at the altar crown +1.2, at a buyer's chest, at a
                     corpse. There is no reliable floor -> radially symmetric, no
                     `Horizontal` ground decals at all.
  * `boss_slam`      FLOOR AT LOCAL y = 0 (senders pass the boss's `position()`, i.e.
                     the feet). One sender (`FogBlindBurstGoal`) offsets +1.2; the
                     ground layers ride `eclipse:soft_particle`, whose SceneDepth fade
                     absorbs that error instead of razor-cutting the arena.
  * `map_expand`     FLOOR AT LOCAL y = -1.5 (`RingGrowthService` anchors at
                     `surfaceY + 1.5`).


================  UNITS — the trap that ate two earlier waves  ================

`startSpeed` / `velocityOverLifetime.linear` are Photon units x0.05 per tick, i.e.
1 unit ~= 1 block/SECOND. `radial` is x0.01 per tick, i.e. 1 unit ~= 0.2 block/s. An
indraw that must cross 3.4 blocks in ~20 ticks therefore needs radial ~= -20, NOT -0.4.
Every speed in this file is annotated with its block/second value.

`curve(lower, upper, segments)` evaluates to `lower + (upper - lower) * bezierY(t)`, so
the DIRECTION of a ramp is chosen by the segment, not by the argument order:
SEG_SMOOTH_UP walks lower -> upper, SEG_DECAY_TAIL walks upper -> lower.


================  STACKING LAW (wave 10/11 law, wave 13 ceiling)  ================

Birth tints are dark (SAC_VOID / STM_SLATE — dozens of alpha quads converge on the
birth color), alpha peaks stay <= 0.45 on every fog/dust body, HDR is capped at 1.45 and
only ever rides additive cores/rims, every alpha-blended pass sorts DISTANCE, and every
ground-hugging layer runs the A0 `eclipse:soft_particle` shader.

This script IS the authoring source for the binary .fx blobs. Run:
python3 tools/photon/wave13b_fx.py
python3 tools/photon/fxlib.py validate --lint
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, F, FX_ASSETS_DIR, REPO_ROOT,
    FxBuilder, burst, circle, cone, constant, curve, function_shape, gradient,
    material_shader, nf3, random_between, random_gradient, sphere,
    texture_material, validate_file,
    SEG_DECAY_TAIL, SEG_EASE_OUT_CREST, SEG_FLICKER_COMMIT, SEG_OVERSHOOT_SETTLE,
    SEG_POP_SHRINK, SEG_SMOOTH_DOWN, SEG_SMOOTH_UP,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"
TEX_RING = "photon:textures/particle/ring.png"
TEX_RING_SOFT = "eclipse:textures/particle/ring_soft.png"
TEX_STAR = "eclipse:textures/particle/star_2x2.png"
TEX_SQUARE = "eclipse:textures/particle/square_4x4.png"
TEX_WISP = "eclipse:textures/particle/purple_wisp.png"

# FX-STYLE-GUIDE §1 tokens. SACRED is the house violet family; STM_SLATE is the storm
# support grey the dust bodies borrow (dust is earth, not magic).
SAC_HOT = (0.965, 0.937, 1.0)        # #F6EFFF
SAC_VIOLET = (0.725, 0.549, 1.0)     # #B98CFF — THE purple
SAC_DEEP = (0.482, 0.310, 0.816)     # #7B4FD0
SAC_GOLD = (1.0, 0.820, 0.400)       # #FFD166 — reward/divinity, impact frames only
SAC_GOLD_PALE = (1.0, 0.914, 0.659)  # #FFE9A8
SAC_VOID = (0.180, 0.137, 0.278)     # #2E2347 — never fade to black, fade to aubergine
STM_SLATE = (0.227, 0.227, 0.333)    # #3A3A55
GLI_WHITE = (1.0, 1.0, 1.0)
# The shipped heart_burst Quasar gradient's mid stop — keeps the Photon hero leg and the
# fallback sketch reading as the same object when both play (LAYER).
HEART_PINK = (0.953, 0.788, 1.0)     # #F3C9FF

#: Wave-13 stacking-law HDR ceiling.
HDR_CEILING = 1.45


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING` while preserving the channel ratio (hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def rand_size3(lo, hi):
    """Per-axis random start size (house `nf3(random, random, random)` idiom)."""
    return nf3(random_between(lo, hi), random_between(lo, hi), random_between(lo, hi))


def size3(lower, upper, segments):
    """Uniform xyz `sizeOverLifetime` from one bezier spec."""
    return nf3(curve(lower, upper, segments, "lifetime", "size"),
               curve(lower, upper, segments, "lifetime", "size"),
               curve(lower, upper, segments, "lifetime", "size"))


def color_by_speed(cool_rgb, hot_rgb, lo_bps, hi_bps):
    """`colorBySpeed` module body — fast particles glow hotter.

    LDLib2's Range codec names its bounds `a`/`b` (jar-verified in wave 13/A1), which is
    why this goes through `with_module` instead of the `with_curves(color_by_speed=...)`
    convenience wrapper (that one writes min/max).
    """
    return {"color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, *cool_rgb), (1.0, *hot_rgb)]),
            "speedRange": {"a": F(float(lo_bps)), "b": F(float(hi_bps))}}


def soft(texture, soft_distance=1.2, near_fade=0.6):
    """The A0 soft-particle material — fog/dust that fades INTO geometry instead of
    slicing it. Alpha blend + DISTANCE sorting is mandatory on every consumer.

    SIZING `soft_distance` (polish-pass finding, see report §5): the shader computes
    `alpha *= smoothstep(0, 1, (sceneDepth - viewZ) / SoftDistance)`, so the fade is
    measured ALONG THE VIEW RAY, not vertically. A ground-parallel decal sitting h
    blocks over the floor is only `h / sin(elevation)` from the geometry behind it, and
    at the grazing angles a player actually watches an arena floor from that is a few
    tenths of a block. On a GPU where the scene-depth copy works, a generous
    `SoftDistance` therefore does not "soften" a ground decal — it ERASES it: this leg's
    shock ring sits 0.08 over the floor, so at a 10-degree viewing elevation the term is
    (0.08/sin 10) / 1.8 = 0.26 before the smoothstep, i.e. the ring keeps roughly a
    tenth of its authored alpha.

      * ground-PARALLEL decals (`render_mode="Horizontal"`): 0.3-0.6.
      * upright billboards that merely stand ON the floor: 0.7-1.0 — they are nearly
        perpendicular to the floor, so the ray clears it quickly and the term only
        bites where they actually intersect terrain, which is the point.

    NOT VISUALLY CONFIRMED ON THE DEV VM, and it cannot be: llvmpipe here hits the
    A0_SHADER_FOUNDATION.md 7.1 failure (`GL_INVALID_OPERATION in
    glBlitNamedFramebuffer(depth attachment format mismatch)` every frame), so
    `SamplerSceneDepth` reads 0.0, the shader's hardening path collapses the soft term
    to 1.0, and every `SoftDistance` in this file is a no-op locally. These values are
    derived from the shader math above; the ground layers were made readable on the VM
    by raising their ALPHA, which is a separate change and is the one that is visible in
    the capture. Re-check the ground legs on real hardware.
    """
    return material_shader("eclipse:soft_particle",
                           textures={"MainTexture": texture},
                           uniforms={"SoftDistance": soft_distance, "NearFade": near_fade},
                           blend=BLEND_ALPHA)


def sheet(tiles, frames, frame_over_time=None):
    """`uvAnimation` tile-picker for the house sprite SHEETS.

    `square_4x4.png` is a 4x4 grid of 16 square frames and `star_2x2.png` a 2x2 grid of
    4 star frames. Photon maps the WHOLE png onto the quad unless a uvAnimation module
    tells it the subdivision — without this every "chip" renders as a little white
    Rubik's-cube face (polish-pass finding, report §5). `frames` is the frame count, so
    the random start frame is what picks one cell per particle.
    """
    return dict(tiles=tiles, animation="WholeSheet",
                frame_over_time=frame_over_time if frame_over_time is not None else constant(0),
                start_frame=random_between(0.0, float(frames - 1)))


def cone_wall(angle=62.0, radius=0.9):
    """Shallow-walled launch cone: debris thrown outward-and-up rather than overhead
    (a narrow cone reads as a geyser, which is the opposite of a slam)."""
    return cone(angle=angle, radius=radius, thickness=0.4)


def ring_shape(r_lo, r_hi, y_expr="0"):
    """Uniform bearing on a flat ring band r_lo..r_hi (storm_nearfield house idiom)."""
    r = f"({r_lo}+randomB*{r_hi - r_lo})"
    return function_shape(x=f"cos(randomA*2*PI)*{r}",
                          z=f"sin(randomA*2*PI)*{r}",
                          y=y_expr)


# ---------------------------------------------------------------------------
# 1. eclipse:hero_heart_burst — the heart-fragment deposit (72t, free-air anchor)
# ---------------------------------------------------------------------------
# The Quasar sketch is seven gravity-fed heart sprites: it says "a heart popped", not
# "the altar ACCEPTED something". The hero leg tells the whole transaction in five
# beats — shatter, drift, indraw, acceptance, afterglow — and the acceptance beat is the
# only place gold enters (§1.1: gold marks reward/divinity, never ambient decoration).
#
# The indraw is a SEPARATE emitter born on a r=3.4 shell rather than a sign flip on the
# shards' radial: Photon ADDS velocityOverLifetime onto the birth velocity and particles
# have no damping, so a late negative radial only bends the shards' path instead of
# visibly sucking them home. Two layers = a legible pull (tyrant_death `gulp_motes`).
HEART_DURATION = 72
HEART_CULL = ((-9.0, -7.0, -9.0), (9.0, 9.0, 9.0))


def build_hero_heart_burst() -> FxBuilder:
    fx = FxBuilder("hero_heart_burst")

    # BEAT 1 (t=0) — the strike. One additive core on OVERSHOOT_SETTLE so it punches
    # past its target and relaxes; the HDR sits exactly on the 1.45 ceiling.
    #
    # SIZE (polish pass): 1.15 blocks, not the 2.8 this shipped with. circle.png is a
    # soft radial gradient — blow it up past ~1.5 blocks and it stops reading as a
    # flash and becomes a grey-white BUBBLE that swallows the altar and the player.
    # A strike is small, brief and brighter than everything else, not big.
    (fx.particle_emitter(
            "core_flash",
            duration=HEART_DURATION, looping=False, max_particles=2,
            start_lifetime=constant(11), start_speed=constant(0.0),
            start_size=nf3(constant(1.0)), simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=1)])
        .with_shape(sphere(radius=0.05))
        .with_material(texture_material(TEX_CIRCLE, hdr=hdr(1.38, 1.24, 1.45),
                                        blend=BLEND_ADDITIVE))
        .with_cull_box(*HEART_CULL)
        .with_curves(
            size_over_lifetime=size3(0.18, 1.15, [SEG_OVERSHOOT_SETTLE]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.08, 0.95), (0.45, 0.55), (1.0, 0.0)],
                [(0.0, *SAC_HOT), (0.35, *HEART_PINK), (1.0, *SAC_DEEP)])))

    # BEAT 2 (t=0) — the fragments. 5-9 b/s outward off a tight shell, stretched along
    # their velocity so they read as splinters and not dots. colorBySpeed is the census
    # ask: the fast ones off the break are white-hot, the tumbling ones are already cold.
    (fx.particle_emitter(
            "heart_shards",
            duration=HEART_DURATION, looping=False, max_particles=22,
            start_lifetime=random_between(26, 34),
            start_speed=random_between(5.0, 9.0),          # 5-9 blocks/second
            start_size=nf3(random_between(0.10, 0.20), random_between(0.10, 0.20),
                           random_between(0.10, 0.20)),
            simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=18)])
        .with_shape(sphere(radius=0.25, thickness=0.55))
        .with_module("colorBySpeed", color_by_speed(SAC_DEEP, SAC_HOT, 2.0, 9.0))
        .with_material(texture_material(TEX_WISP, hdr=hdr(1.05, 0.86, 1.45),
                                        blend=BLEND_ADDITIVE))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.35,
                       length_scale=2.2, vertex_sorting="NONE")
        .with_cull_box(*HEART_CULL)
        .with_curves(
            velocity_over_lifetime=dict(
                # Gentle sag so the fragments arc instead of flying dead straight; the
                # -1.4 b/s is small enough that the indraw still owns the second half.
                linear=nf3(constant(0.0), random_between(-1.8, -0.6), constant(0.0))),
            size_over_lifetime=size3(0.35, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=random_gradient(
                [(0.0, 0.0), (0.1, 0.9), (0.62, 0.5), (1.0, 0.0)],
                [(0.0, *SAC_HOT), (0.4, *SAC_VIOLET), (1.0, *SAC_VOID)],
                [(0.0, 0.0), (0.14, 0.75), (0.7, 0.4), (1.0, 0.0)],
                [(0.0, *HEART_PINK), (0.45, *SAC_DEEP), (1.0, *SAC_VOID)])))

    # BEAT 2b (t=1) — bodies under the splinters. Without these the break reads as a
    # handful of scratches; soft_particle keeps them from cutting the altar monument.
    (fx.particle_emitter(
            "shard_dust",
            duration=HEART_DURATION, looping=False, max_particles=16,
            start_lifetime=random_between(22, 32),
            start_speed=random_between(1.6, 3.4),          # 1.6-3.4 blocks/second
            start_size=rand_size3(0.30, 0.62), simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=1, count=14)])
        .with_shape(sphere(radius=0.4, thickness=0.8))
        .with_material(soft(TEX_SMOKE, soft_distance=0.9, near_fade=0.5))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box(*HEART_CULL)
        .with_curves(
            size_over_lifetime=size3(0.28, 1.15, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.34), (0.7, 0.2), (1.0, 0.0)],
                [(0.0, *SAC_VOID), (0.5, *SAC_DEEP), (1.0, *SAC_VOID)])))

    # BEAT 3 (t=12) — THE INDRAW. Born already fanned out on a 3.4-block shell (the only
    # way a converging layer reads: spawn spread, then pull), radial accelerating
    # -8 -> -30 = 1.6 -> 6.0 b/s inward. ~4.2 blocks of travel over 22t, so the front
    # arrives on the core at roughly t=30 — exactly under the acceptance pulse.
    (fx.particle_emitter(
            "indraw_motes",
            duration=HEART_DURATION, looping=False, max_particles=24,
            start_lifetime=random_between(19, 24), start_speed=constant(0.0),
            start_size=rand_size3(0.08, 0.17), simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=12, count=20)])
        .with_shape(sphere(radius=3.4, thickness=0.35))
        .with_material(texture_material(TEX_STAR, hdr=hdr(1.22, 1.04, 1.45),
                                        blend=BLEND_ADDITIVE))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.9,
                       length_scale=2.6, vertex_sorting="NONE")
        .with_cull_box(*HEART_CULL)
        .with_curves(
            uv_animation=sheet((2, 2), 4),
            velocity_over_lifetime=dict(
                radial=curve(-8.0, -30.0, [SEG_SMOOTH_UP], "lifetime", "value"),
                orbital=nf3(constant(0.0), random_between(-0.22, 0.22), constant(0.0))),
            size_over_lifetime=size3(0.5, 1.25, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.22, 0.7), (0.78, 0.85), (1.0, 0.0)],
                [(0.0, *SAC_VIOLET), (0.7, *SAC_HOT), (1.0, *SAC_DEEP)])))

    # BEAT 4 (t=28) — ACCEPTED. The one gold frame in the file: a single ring blooming
    # off the reassembled core as the altar takes the fragment.
    #
    # SIZE (polish pass): 2.6 blocks, down from 3.4. With the core flash cut back this
    # became the largest object in the leg by a wide margin and started reading as a
    # portal hoop around the player instead of a pulse leaving the fragment. It should
    # be the punctuation of the sentence, not the sentence.
    (fx.particle_emitter(
            "reforge_pulse",
            duration=HEART_DURATION, looping=False, max_particles=2,
            start_lifetime=constant(22), start_speed=constant(0.0),
            start_size=nf3(constant(1.0)), simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=28, count=1)])
        .with_shape(sphere(radius=0.05))
        .with_material(texture_material(TEX_RING, hdr=hdr(1.45, 1.24, 0.72),
                                        blend=BLEND_ADDITIVE))
        .with_renderer(facing_mode="LOOKAT_XYZ", vertex_sorting="NONE")
        .with_cull_box(*HEART_CULL)
        .with_curves(
            size_over_lifetime=size3(0.3, 2.6, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.8), (0.55, 0.4), (1.0, 0.0)],
                [(0.0, *SAC_HOT), (0.32, *SAC_GOLD), (0.72, *SAC_VIOLET),
                 (1.0, *SAC_VOID)])))

    # BEAT 5 (t=30) — the afterglow the Quasar sketch never had: what the altar did not
    # swallow drifts up and cools out over the next two seconds.
    (fx.particle_emitter(
            "afterglow_motes",
            duration=HEART_DURATION, looping=False, max_particles=18,
            start_lifetime=random_between(38, 58), start_speed=constant(0.0),
            start_size=rand_size3(0.16, 0.38), simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=30, count=8, cycles=2, interval=9)])
        .with_shape(sphere(radius=1.1, thickness=0.85))
        .with_material(soft(TEX_SMOKE, soft_distance=0.8, near_fade=0.5))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box(*HEART_CULL)
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(0.5, 1.3), constant(0.0)),
                orbital=nf3(constant(0.0), random_between(-0.3, 0.3), constant(0.0))),
            noise=dict(frequency=0.45, position=nf3(0.04)),
            size_over_lifetime=size3(0.4, 1.3, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.30), (0.72, 0.18), (1.0, 0.0)],
                [(0.0, *SAC_VOID), (0.45, *SAC_VIOLET), (1.0, *SAC_VOID)])))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:hero_boss_slam — every boss ground slam (130t, floor at local y = 0)
# ---------------------------------------------------------------------------
# The Quasar sketch is 14 colliding wisps: a puff, gone in 1.5 s. A slam is a WEIGHT
# event, so the hero leg spends its budget on the three things weight is made of — a
# pressure front (two rings, not one decal), real ballistic debris with collision, and
# dust that outlives the impact by five seconds instead of evaporating with it.
#
# Everything that touches the floor runs eclipse:soft_particle. The arena floors this
# fires on (Ferryman deck, Herald dais, open disc terrain) are all uneven; a hard quad
# ring saws a visible straight edge across them.
SLAM_DURATION = 130
SLAM_CULL = ((-24.0, -4.0, -24.0), (24.0, 12.0, 24.0))
FLOOR = 0.0


def build_hero_boss_slam() -> FxBuilder:
    fx = FxBuilder("hero_boss_slam")

    # BEAT 1 (t=0) — the hit. Short, bright, gone in half a second; POP_SHRINK so it
    # never lingers as a lamp. 1.5 blocks, not the 3.2 this shipped with — see
    # `core_flash` above: an oversized circle.png is a dome, not a flash, and this one
    # was big enough to hide the chips and the ring it is supposed to introduce.
    (fx.particle_emitter(
            "impact_flash",
            duration=SLAM_DURATION, looping=False, max_particles=2,
            start_lifetime=constant(9), start_speed=constant(0.0),
            start_size=nf3(constant(1.0)), simulation_space="World")
        .at(0.0, FLOOR + 0.35, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=1)])
        .with_shape(sphere(radius=0.05))
        .with_material(texture_material(TEX_CIRCLE, hdr=hdr(1.30, 1.18, 1.45),
                                        blend=BLEND_ADDITIVE))
        .with_cull_box(*SLAM_CULL)
        .with_curves(
            size_over_lifetime=size3(0.4, 1.5, [SEG_POP_SHRINK]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.06, 1.0), (0.4, 0.5), (1.0, 0.0)],
                [(0.0, *GLI_WHITE), (0.3, *SAC_VIOLET), (1.0, *SAC_VOID)])))

    # BEAT 2 (t=0) — the shock ring. 0.6 -> 17 blocks over 30t on EASE_OUT_CREST: fast
    # out of the gate, then coasting. Peak alpha 0.62 (was 0.44) — a flat ring is viewed
    # nearly edge-on from a player's eye height and 0.44 left it a smear. SoftDistance
    # 0.45 (was 1.8) — see `soft()`: on a ground-parallel decal a wide SoftDistance is
    # not softness, it is an erase. 0.45 still absorbs the arena's uneven floor (and the
    # one sender that anchors +1.2 off it) without eating the ring.
    (fx.particle_emitter(
            "shock_ring",
            duration=SLAM_DURATION, looping=False, max_particles=2,
            start_lifetime=constant(30), start_speed=constant(0.0),
            start_size=nf3(constant(1.0)), simulation_space="World")
        .at(0.0, FLOOR + 0.08, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=1)])
        .with_shape(sphere(radius=0.05))
        .with_material(soft(TEX_RING, soft_distance=0.45, near_fade=0.6))
        .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE")
        .with_cull_box(*SLAM_CULL)
        .with_curves(
            size_over_lifetime=size3(0.6, 17.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.62), (0.6, 0.3), (1.0, 0.0)],
                [(0.0, *SAC_HOT), (0.35, *SAC_VIOLET), (1.0, *SAC_VOID)])))

    # BEAT 2b (t=6) — the echo. One ring is a decal; two rings chasing each other at
    # different speeds are a pressure front. Tighter, dimmer, deliberately behind.
    (fx.particle_emitter(
            "ring_echo",
            duration=SLAM_DURATION, looping=False, max_particles=2,
            start_lifetime=constant(26), start_speed=constant(0.0),
            start_size=nf3(constant(1.0)), simulation_space="World")
        .at(0.0, FLOOR + 0.05, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=6, count=1)])
        .with_shape(sphere(radius=0.05))
        .with_material(soft(TEX_RING_SOFT, soft_distance=0.4, near_fade=0.6))
        .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE")
        .with_cull_box(*SLAM_CULL)
        .with_curves(
            size_over_lifetime=size3(0.5, 11.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.14, 0.42), (0.62, 0.22), (1.0, 0.0)],
                [(0.0, *SAC_VIOLET), (0.5, *SAC_DEEP), (1.0, *SAC_VOID)])))

    # BEAT 3 (t=0) — the chips. REAL world collision: they fly, they hit the floor, they
    # skitter (bounceChance 0.45, collidedFriction 0.5) and they stay put. gravity 1.2
    # is x0.04 = 0.048 b/t^2, so a 10 b/s launch apexes ~2.5 blocks up after ~10t.
    # colorBySpeed keeps the fast ones lit and lets the settled ones go to slate.
    #
    # Physics forbids parallelUpdate/useGPUInstance (LINT-GPU-PHYSICS: the collision
    # step needs level access off the client thread) — hence the trimmed count.
    (fx.particle_emitter(
            "ground_chips",
            duration=SLAM_DURATION, looping=False, max_particles=26,
            start_lifetime=random_between(34, 56),
            start_speed=random_between(7.0, 13.0),         # 7-13 blocks/second
            start_size=nf3(random_between(0.09, 0.20), random_between(0.09, 0.20),
                           random_between(0.09, 0.20)),
            start_rotation=nf3(constant(0.0), constant(0.0), random_between(0.0, 360.0)),
            simulation_space="World")
        .at(0.0, FLOOR + 0.25, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=22)])
        # Hemisphere-ish launch: a shallow-walled cone throws the chips out and up
        # instead of straight overhead (a vertical fountain reads as a geyser, not a slam).
        .with_shape(cone_wall(angle=62.0, radius=0.9))
        .with_module("colorBySpeed", color_by_speed(STM_SLATE, SAC_HOT, 3.0, 14.0))
        .with_physics(collision=True, removed_when_collided=False, friction=0.9,
                      collided_friction=0.5, gravity=1.2, bounce_chance=0.45,
                      bounce_rate=0.4, bounce_spread=0.35)
        # HDR 0.50/0.36/0.72, not 0.9/0.72/1.2. ADDITIVE hdrMode is `rgb += HDR.rgb`, a
        # flat offset: put ~1.0 on a body that already covers half a block of screen and
        # every chip clips to white paper. The stacking law's "HDR rides cores and rims"
        # applies to the chips too — the colour has to come from colorBySpeed.
        .with_material(texture_material(TEX_SQUARE, hdr=hdr(0.50, 0.36, 0.72),
                                        blend=BLEND_ADDITIVE,
                                        pixel_art=True, pixel_art_bits=4))
        .with_renderer(vertex_sorting="NONE")
        .with_cull_box(*SLAM_CULL)
        .with_curves(
            uv_animation=sheet((4, 4), 16),
            rotation_over_lifetime=random_between(-9.0, 9.0),
            size_over_lifetime=size3(0.25, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.07, 0.9), (0.7, 0.45), (1.0, 0.0)],
                [(0.0, *SAC_HOT), (0.3, *SAC_DEEP), (1.0, *SAC_VOID)])))

    # BEAT 4 (t=1) — the curtain rolls. Born on a 1.2-block collar and pushed out at
    # 6 b/s decaying to 1.2 b/s (radial 30 -> 6): ~10 blocks of travel over its life, so
    # the front visibly SLOWS instead of running off to the horizon at constant speed.
    (fx.particle_emitter(
            "dust_curtain",
            duration=SLAM_DURATION, looping=False, max_particles=30,
            start_lifetime=random_between(60, 90), start_speed=constant(0.0),
            start_size=rand_size3(0.9, 1.9), simulation_space="World")
        .at(0.0, FLOOR + 0.25, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=1, count=13, cycles=2, interval=7)])
        .with_shape(circle(radius=1.2, thickness=0.5))
        .with_material(soft(TEX_SMOKE, soft_distance=0.9, near_fade=0.7))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box(*SLAM_CULL)
        .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(6.0, 30.0, [SEG_DECAY_TAIL], "lifetime", "value"),
                linear=nf3(constant(0.0), random_between(0.15, 0.75), constant(0.0))),
            noise=dict(frequency=0.35, position=nf3(0.05)),
            size_over_lifetime=size3(0.4, 1.5, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.18, 0.32), (0.68, 0.2), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.5, *SAC_DEEP), (1.0, *SAC_VOID)])))

    # BEAT 5 (t=20) — and the dust STAYS. Flat, near-motionless banks seeded out on the
    # 5-9 block annulus the curtain has already reached, living 70-110t at alpha 0.22.
    # This is the whole point of the leg: after the flash is gone the arena is still
    # dirty, which is what makes the slam feel like it moved something.
    (fx.particle_emitter(
            "settled_bank",
            duration=SLAM_DURATION, looping=False, max_particles=18,
            start_lifetime=random_between(70, 110), start_speed=constant(0.0),
            start_size=rand_size3(1.8, 3.4), simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=20, count=7, cycles=2, interval=14)])
        .with_shape(ring_shape(5.0, 9.0, y_expr=f"{FLOOR + 0.18}+randomC*0.35"))
        # Ground-parallel again -> 0.6, not 2.0 (see `soft()`); the settled dust would be
        # the worst offender on real hardware because it lies flattest and lowest of all
        # six layers.
        .with_material(soft(TEX_SMOKE, soft_distance=0.6, near_fade=0.8))
        .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE", shade=True)
        .with_cull_box(*SLAM_CULL)
        .with_curves(
            velocity_over_lifetime=dict(radial=curve(0.6, 3.0, [SEG_DECAY_TAIL],
                                                     "lifetime", "value")),
            noise=dict(frequency=0.2, position=nf3(0.02)),
            size_over_lifetime=size3(0.55, 1.25, [SEG_SMOOTH_UP]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.22, 0.28), (0.7, 0.17), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.6, 0.26, 0.24, 0.35), (1.0, *SAC_VOID)])))

    # BEAT 6 (t=2) — vertical read. Without something climbing, a slam is a flat disc
    # seen from above and nothing at all seen from the side.
    (fx.particle_emitter(
            "updraft_motes",
            duration=SLAM_DURATION, looping=False, max_particles=16,
            start_lifetime=random_between(28, 44), start_speed=constant(0.0),
            start_size=rand_size3(0.07, 0.15), simulation_space="World")
        .at(0.0, FLOOR + 0.2, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=12)])
        .with_shape(circle(radius=2.2, thickness=0.9))
        .with_material(texture_material(TEX_STAR, hdr=hdr(1.05, 0.88, 1.4),
                                        blend=BLEND_ADDITIVE))
        .with_cull_box(*SLAM_CULL)
        .with_curves(
            uv_animation=sheet((2, 2), 4),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(1.5, 3.0), constant(0.0)),
                orbital=nf3(constant(0.0), random_between(-0.25, 0.25), constant(0.0))),
            size_over_lifetime=size3(0.3, 1.1, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.18, 0.7), (0.7, 0.3), (1.0, 0.0)],
                [(0.0, *SAC_VIOLET), (0.45, *SAC_HOT), (1.0, *SAC_VOID)])))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:hero_expand_materialize — ring expansion (86t, floor at local y = -1.5)
# ---------------------------------------------------------------------------
# `RingGrowthService` fires this at up to one scattered surface point every 5 ticks for
# the whole growth sweep, so several instances routinely overlap. The budget is therefore
# deliberately the smallest of the three legs (56 particles, no physics, no GPU) — this
# is a texture over a landscape event, not a set piece.
#
# The read the census asks for: the chunk SNAPS IN. Columns come up out of the new
# ground and a glint veil dissolves off them — in three staggered waves, because a veil
# that fades collectively reads as someone turning a dimmer down.
EXPAND_DURATION = 86
EXPAND_GROUND = -1.5                  # the cue anchors at surfaceY + 1.5
EXPAND_CULL = ((-9.0, -5.0, -9.0), (9.0, 14.0, 9.0))


def build_hero_expand_materialize() -> FxBuilder:
    fx = FxBuilder("hero_expand_materialize")

    # BEAT 1 (t=0) — the seam. The line where the new ground met the void, lit for a
    # second. soft_particle so it hugs whatever slope the column landed on.
    (fx.particle_emitter(
            "column_seam",
            duration=EXPAND_DURATION, looping=False, max_particles=2,
            start_lifetime=constant(26), start_speed=constant(0.0),
            start_size=nf3(constant(1.0)), simulation_space="World")
        .at(0.0, EXPAND_GROUND + 0.08, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=1)])
        .with_shape(sphere(radius=0.05))
        .with_material(soft(TEX_RING_SOFT, soft_distance=0.4, near_fade=0.5))
        .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE")
        .with_cull_box(*EXPAND_CULL)
        .with_curves(
            size_over_lifetime=size3(0.6, 4.2, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.6), (0.6, 0.3), (1.0, 0.0)],
                [(0.0, *SAC_HOT), (0.4, *SAC_VIOLET), (1.0, *SAC_VOID)])))

    # BEAT 2 (t=0) — the columns. Seven tall slats standing on a 0.4-1.4 collar, rising
    # 1.4-2.4 b/s out of the floor. The alpha ramp hesitates (0.25) before committing
    # (0.72): matter deciding whether to exist, which is the whole fiction of the cue.
    #
    # TEXTURE (polish pass): a single hard square off square_4x4.png, NOT circle.png.
    # A stretched soft radial gradient made these read as white FLAMES licking up out of
    # the ground — the exact wrong fiction. A hard-edged slat is matter, it shares the
    # voxel language of `voxel_motes` below, and it is what the Quasar sketch's
    # `veil:block` cubes were reaching for. Rise speed and HDR came down with it: at
    # 3.6 b/s over 38t the columns cleared 6 blocks and left the frame as lamps.
    (fx.particle_emitter(
            "materialize_columns",
            duration=EXPAND_DURATION, looping=False, max_particles=10,
            start_lifetime=random_between(26, 38), start_speed=constant(0.0),
            start_size=nf3(random_between(0.24, 0.42), random_between(1.3, 2.1),
                           random_between(0.24, 0.42)),
            simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=7)])
        .with_shape(ring_shape(0.4, 1.4, y_expr=f"{EXPAND_GROUND}+randomC*0.5"))
        # Lowest HDR in the file: a column is the largest single surface any of the three
        # legs draws, and the flat ADDITIVE offset turns large surfaces into white paper
        # (same trap as `ground_chips`). The violet has to survive — this cue plays over
        # open landscape where a white slab reads as a rendering error, not as matter.
        .with_material(texture_material(TEX_SQUARE, hdr=hdr(0.40, 0.26, 0.62),
                                        blend=BLEND_ADDITIVE,
                                        pixel_art=True, pixel_art_bits=4))
        .with_renderer(render_mode="VerticalBillboard", vertex_sorting="NONE")
        .with_cull_box(*EXPAND_CULL)
        .with_curves(
            uv_animation=sheet((4, 4), 16),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(1.4, 2.4), constant(0.0))),
            size_over_lifetime=size3(0.45, 1.15, [SEG_FLICKER_COMMIT]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.22), (0.3, 0.17), (0.46, 0.62), (0.8, 0.3), (1.0, 0.0)],
                [(0.0, *SAC_VOID), (0.45, *SAC_VIOLET), (1.0, *SAC_HOT)])))

    # BEAT 3 (t=0) — the voxels. Hard 4x4 quads carrying the Quasar sketch's block-ness
    # forward (its `veil:block` cubes were the one thing that version got right), pulled
    # toward the column axis at an accelerating 1.2 -> 2.8 b/s — the Photon answer to the
    # emitter JSON's point_attractor.
    (fx.particle_emitter(
            "voxel_motes",
            duration=EXPAND_DURATION, looping=False, max_particles=14,
            start_lifetime=random_between(24, 36), start_speed=constant(0.0),
            start_size=rand_size3(0.16, 0.32),
            start_rotation=nf3(constant(0.0), constant(0.0), random_between(0.0, 90.0)),
            simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=10)])
        .with_shape(ring_shape(1.5, 2.9, y_expr=f"{EXPAND_GROUND + 0.3}+randomC*3.2"))
        .with_material(texture_material(TEX_SQUARE, hdr=hdr(0.55, 0.42, 0.80),
                                        blend=BLEND_ADDITIVE,
                                        pixel_art=True, pixel_art_bits=4))
        .with_renderer(vertex_sorting="NONE")
        .with_cull_box(*EXPAND_CULL)
        .with_curves(
            uv_animation=sheet((4, 4), 16),
            velocity_over_lifetime=dict(
                radial=curve(-14.0, -6.0, [SEG_SMOOTH_DOWN], "lifetime", "value"),
                linear=nf3(constant(0.0), random_between(0.4, 1.4), constant(0.0))),
            size_over_lifetime=size3(0.35, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.16, 0.72), (0.66, 0.4), (1.0, 0.0)],
                [(0.0, *SAC_VOID), (0.5, *SAC_VIOLET), (1.0, *SAC_DEEP)])))

    # BEAT 4 (t=2/12/22) — the veil, dissolving. Three burst waves with staggered
    # lifetimes so the shimmer thins out in layers; random_gradient splits the glints
    # between the violet body and a pale-gold minority (new land is a gift, §1.1 gold =
    # reward — but only a minority, never the body color).
    (fx.particle_emitter(
            "glint_veil",
            duration=EXPAND_DURATION, looping=False, max_particles=34,
            start_lifetime=random_between(30, 52), start_speed=random_between(0.3, 1.1),
            start_size=rand_size3(0.05, 0.13), simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=10, cycles=3, interval=10)])
        .with_shape(sphere(radius=1.7, thickness=0.95))
        .with_material(texture_material(TEX_STAR, hdr=hdr(1.18, 1.0, 1.45),
                                        blend=BLEND_ADDITIVE))
        .with_cull_box(*EXPAND_CULL)
        .with_curves(
            # A real 4-point star per glint, and the 2x2 sheet scanned over the life is
            # the twinkle itself (stern_komet_star_glint idiom).
            uv_animation=sheet((2, 2), 4,
                               frame_over_time=curve(0.0, 4.0, [SEG_FLICKER_COMMIT])),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(0.6, 1.8), constant(0.0)),
                orbital=nf3(constant(0.0), random_between(-0.35, 0.35), constant(0.0))),
            noise=dict(frequency=0.9, position=nf3(0.06)),
            size_over_lifetime=size3(0.2, 1.1, [SEG_POP_SHRINK]),
            color_over_lifetime=random_gradient(
                [(0.0, 0.0), (0.2, 0.85), (0.65, 0.4), (1.0, 0.0)],
                [(0.0, *SAC_VIOLET), (0.55, *SAC_HOT), (1.0, *SAC_VOID)],
                [(0.0, 0.0), (0.3, 0.6), (0.72, 0.3), (1.0, 0.0)],
                [(0.0, *SAC_GOLD_PALE), (0.5, *SAC_VIOLET), (1.0, *SAC_VOID)])))

    # BEAT 5 (t=4) — the settle. A thin skirt of ground dust so the columns look like
    # they displaced something on the way up.
    (fx.particle_emitter(
            "ground_dust",
            duration=EXPAND_DURATION, looping=False, max_particles=12,
            start_lifetime=random_between(40, 60), start_speed=constant(0.0),
            start_size=rand_size3(0.7, 1.5), simulation_space="World")
        .at(0.0, EXPAND_GROUND + 0.25, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=4, count=10)])
        .with_shape(circle(radius=1.1, thickness=0.6))
        .with_material(soft(TEX_SMOKE, soft_distance=0.85, near_fade=0.6))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box(*EXPAND_CULL)
        .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(3.0, 10.0, [SEG_DECAY_TAIL], "lifetime", "value"),
                linear=nf3(constant(0.0), random_between(0.1, 0.5), constant(0.0))),
            size_over_lifetime=size3(0.45, 1.3, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.24), (0.7, 0.15), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.55, *SAC_DEEP), (1.0, *SAC_VOID)])))
    return fx


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
BUILDERS = {
    "hero_heart_burst.fx": build_hero_heart_burst,
    "hero_boss_slam.fx": build_hero_boss_slam,
    "hero_expand_materialize.fx": build_hero_expand_materialize,
}


def main() -> int:
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        builder = builder_fn()
        raw_len, gz_len = builder.write(path)  # write() round-trips + validates shader refs
        proj_len = builder.write_fxproj(path.with_suffix(".fxproj"))
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}:")
            for e in errors:
                print(f"  - {e}")
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B, "
                  f"fxproj {proj_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
