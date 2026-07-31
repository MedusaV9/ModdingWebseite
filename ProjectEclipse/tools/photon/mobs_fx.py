#!/usr/bin/env python3
"""mobs_fx — PH-MOBS generator: custom-mob + celebration Photon `.fx` assets.

Authors (via fxlib, see tools/photon/README.md) the IDEAS-mobs.md concepts owned by
worker PH-MOBS (docs/plans_v3/plans_v5/photon/IDEAS-mobs.md #1, #3, #4 hound half, #5 pop,
#6 ribbon, #7, #8, #9, #10 — #2 offering ribbon is PH-ALTAR's):

    eclipse:boss_intro_shockwave     (#1  name-lock ground ring + dust + crack beams)
    eclipse:award_star_shower        (#3  model-particle star rain w/ collision bounce)
    eclipse:award_star_glint         (#3  Collision sub-emitter child)
    eclipse:sentinel_alert           (#7  freeze camera-flash petal puff, one-shot)
    eclipse:sentinel_petal_orbit     (#7  frozen-statue petal halo, loop)
    eclipse:gazer_gaze_beam          (#9  raycast gaze thread + hypnosis rings, loop)
    eclipse:glitch_pop               (#5  REVERSE_SUB+ADD datamosh blink pop)
    eclipse:shadow_bolt_ribbon       (#6  projectile ara ribbon + wither motes, loop)
    eclipse:hound_lunge_windup       (#4  20t collapsing spiral telegraph + release pop)
    eclipse:hound_dash_trail         (#4  ara ribbon + distanceRate grit along the dash)
    eclipse:other_dread_aura         (#8  light-eating REVERSE_SUB shroud, loop)
    eclipse:wanderer_static_shroud   (#10 shade:1b flicker-synced paint haze, loop)
    eclipse:gazer_tether_snap        (N12 the gaze thread tearing off, one-shot)
    eclipse:revenant_fog_ribbons     (#4  robe-hem wisps + TRAIL streamers, loop)

Plus the deterministic textures (safe to re-run; static_4x4 is the shared #5/#10
flipbook the IDEAS-mobs delta table calls for):

    assets/eclipse/textures/particle/static_4x4.png  (4x4 white-noise flipbook frames)
    assets/eclipse/textures/particle/square_4x4.png  (4x4 identical soft squares — the
        glitch_pop REVERSE_SUB pass shares the emitter uvAnimation, so its texture must
        tile the same grid)
    assets/eclipse/textures/particle/petal_soft.png  (single soft petal, tinted at runtime)

This script IS the authoring source for these binary .fx blobs (fxlib generator in place
of an editor .fxproj). Run: python3 tools/photon/mobs_fx.py

FX-Welle 13 / team B2 — the MOVEMENT PACKAGE (FX_CENSUS_WAVE13 §7 row B2). Mobs are the
one family where every asset rides an `EntityEffectExecutor`, so the four levers the
census counts as unused actually bite here (see docs/plans_v3/session_0730/
B2_MOB_REPORT.md §0.2 for the verified semantics):

    distanceRate      particles per BLOCK MOVED — only meaningful on the entity lanes,
                      never on the position cues (glitch_pop: accumulatedDistance stays 0)
    inheritVelocity   emitterVelocity*multiply in WORLD space. World-space emitter +
                      positive = wake; Local-space emitter + NEGATIVE = drag, which is
                      exactly "the aura tears along when the mob walks"
    colorBySpeed      input |realVelocity|*20 = BLOCKS/SECOND, output MULTIPLIES the
                      lifetime colour. speedRange is an LDLib2 Range (codec fields a/b —
                      NOT fxlib's min/max), hence with_module instead of with_curves
    random_gradient   two ramps lerped per particle: no two hounds/gazers read identical

Plus N12 (gaze tether, §2 of the report): `gazer_gaze_beam` becomes a viscous ara thread
that lags and frays when the hood turns, and `gazer_tether_snap` is the tear-off moment
fired by MobPhotonFxRows' client-side gaze watcher.
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, BLEND_ADDITIVE, BLEND_ALPHA, F, FX_ASSETS_DIR, I, REPO_ROOT, SEG_DECAY_TAIL,
    SEG_EASE_OUT_CREST, SEG_LINEAR_DOWN, SEG_LINEAR_UP, SEG_POP_SHRINK, SEG_SMOOTH_UP,
    FxBuilder, aabb, blend, block_atlas_material, box, burst, circle, cone, constant,
    curve, cylinder, dot, function_shape, gradient, mesh, nf3, random_between,
    random_color, random_gradient, rom, sphere, sub_emitter, texture_material,
    validate_file,
)

TEXTURE_DIR = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle"
CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
RING = "photon:textures/particle/ring.png"
BEAM_CORE = "eclipse:textures/particle/beam_core.png"  # shared, authored by boss_b_fx.py
STATIC_4X4 = "eclipse:textures/particle/static_4x4.png"
SQUARE_4X4 = "eclipse:textures/particle/square_4x4.png"
STAR_2X2 = "eclipse:textures/particle/star_2x2.png"  # shared, authored by gen_player_fx.py
PETAL = "eclipse:textures/particle/petal_soft.png"

# The IDEAS-mobs #5 two-pass law: pass 1 rips light out of the framebuffer (dst - src,
# factors ONE/ONE per the spec) — works with bloom off, no dark-bloom dependency.
BLEND_REVERSE_SUB = blend("ONE", "ONE", "ONE", "ZERO", "REVERSE_SUB")

# Rise-then-fall bezier pair (0 -> 1 -> 0 across the axis) for breathing curves.
SEGS_BREATHE = [(0.0, 0.0, 0.17, 0.6, 0.33, 1.0, 0.5, 1.0),
                (0.5, 1.0, 0.67, 1.0, 0.83, 0.6, 1.0, 0.0)]

# FX-STYLE-GUIDE §1 tokens used by the moved-in revenant asset (see MOVEMENT PACKAGE).
FOG_TEAL = (0.55, 0.66, 0.65)         # desaturated grey-teal fog body
STM_SLATE = (0.227, 0.227, 0.333)     # #3A3A55
GLI_DEAD = (0.141, 0.110, 0.220)      # #241C38
COR_VIOLET = (0.616, 0.306, 0.867)    # #9D4EDD
COR_INK = (0.235, 0.035, 0.424)       # #3C096C

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4) — many sprites inside one half-block
#: converge to the sprite's own colour above this.
HDR_CEILING = 1.45


# ---------------------------------------------------------------------------
# Wave-13 movement-package helpers (B2). fxlib belongs to team A0 this wave, so the
# three gaps below are patched here instead of there.
# ---------------------------------------------------------------------------
def hdr(r, g, b):
    """Clamps an authored HDR triple to HDR_CEILING, preserving the hue ratio."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def eased(points, lock=True):
    """NF curve through (t, value) points with smoothstep tangents — every non-flat
    segment carries genuinely off-chord control points (LINT-LINEAR-CURVE clean)."""
    lo = min(v for _, v in points)
    hi = max(v for _, v in points)
    span = (hi - lo) or 1.0
    norm = [(t, (v - lo) / span) for t, v in points]
    segments = []
    for (x0, y0), (x1, y1) in zip(norm, norm[1:]):
        third = (x1 - x0) / 3.0
        segments.append((x0, y0, x0 + third, y0, x1 - third, y1, x1, y1))
    return curve(lo, hi if hi != lo else lo + 1.0, segments, lock=lock)


def inherit_velocity(multiply, mode="CURRENT"):
    """`inheritVelocity` body — InheritVelocitySetting{mode, multiply}.

    CURRENT re-reads the emitter velocity every tick (INITIAL freezes it at birth).
    On a World-space emitter a POSITIVE multiply drags the particle along in the mob's
    wake; on a Local-space emitter the particle already rides the transform, so a
    NEGATIVE multiply is the lag/drag knob — that is how an aura "tears along".
    """
    return {"mode": mode, "multiply": constant(float(multiply))}


def color_by_speed(cool_rgb, hot_rgb, lo_bps, hi_bps):
    """`colorBySpeed` body — ColorBySpeedSetting{color, speedRange}.

    Input is blocks/second (|realVelocity| * 20); the result MULTIPLIES the lifetime
    colour, so the hot end stays at/near white or fast particles just go dark.
    `speedRange` is an LDLib2 `Range`, whose codec fields are `a`/`b` — NOT the
    `min`/`max` pair `fxlib._min_max` writes, hence with_module over with_curves.
    """
    return {"color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, *cool_rgb), (1.0, *hot_rgb)]),
            "speedRange": {"a": F(float(lo_bps)), "b": F(float(hi_bps))}}


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling ramp inside the same identity;
    each particle rolls its own memoized lerp between the two (anti clone-look)."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


def ara_toggles_on(emitter):
    """Marks an ara trail's `section` / `physicsSetting` toggle groups as enabled.

    Both extend LDLib2's `ToggleGroup`, which deserialises to DISABLED unless the compound
    carries an explicit `_enable: 1b`. `fxlib.AraTrailEmitter` writes the group's payload
    but not that flag, so every `physics=dict(...)` block in this file was INERT before
    this pass (`AraTrailParticle.updatePhysics` gates on `physicsSetting.isEnable()`).
    """
    for key in ("section", "physicsSetting"):
        block = emitter._config.get(key)
        if isinstance(block, dict):
            block["_enable"] = B(1)
    return emitter


def ribbon_renderer(material_entry, sorting="DISTANCE", cull_box=None):
    """Explicit RendererSetting for EMBEDDED trail/ara configs (never MISSING-pink);
    fxlib's _RendererMixin only serves standalone emitters."""
    cull = {"_enable": B(0)} if cull_box is None else \
        {"_enable": B(1), "cullBox": aabb(*cull_box)}
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": cull, "orderInLayer": I(0), "vertexSortingMode": sorting}


# ---------------------------------------------------------------------------
# Concept #1 — eclipse:boss_intro_shockwave (one-shot, spawned with setDelay(decodeEnd))
# ---------------------------------------------------------------------------
def build_boss_intro_shockwave() -> FxBuilder:
    """The instant the intro card locks the boss name: bloom-crested particle ring
    expanding from the summon point, world-lit dust grounding it, and 4 raycast-clipped
    crack-glow beams bleeding along the ground seams."""
    fx = FxBuilder("boss_intro_shockwave")
    cull = ((-6.0, -2.0, -6.0), (6.0, 4.0, 6.0))

    # The particles ARE the ring: circle-shell burst launched radially.
    # FX-Wave-11 stacking-law pass: 90 additive sparks born on a 0.4 r shell with
    # hdr 2.4 converged into one white supernova ball. Count 90->40 on a 1.2 r shell,
    # hdr nerfed to ~1.45 and the alpha crest to 0.7 — the ring reads as an arc of
    # separate sparks again.
    # FX-Wave-11.1 readability pass: at 2.2 b/t the 0.14-0.24 sparks left a 12-block
    # FOV in <6 ticks and the whole beat read as "nothing happened". Slower (1.25),
    # bigger (0.22-0.36), longer (20-28t), 48 sparks, crest 0.85 — punchy but still
    # born spread on the 1.2 r shell so nothing re-converges to white.
    (fx.particle_emitter(
            "ring",
            duration=30, looping=False, max_particles=96,
            start_lifetime=random_between(20, 28), start_speed=constant(1.25),
            start_size=nf3(random_between(0.22, 0.36), random_between(0.22, 0.36),
                           random_between(0.22, 0.36)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(48))])
       .with_shape(circle(radius=1.2, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(CIRCLE, hdr=(1.5, 1.2, 1.8), blend=BLEND_ADDITIVE))
       .with_lights()
       .with_cull_box(*cull)
       .with_curves(
            # Decay tail: sparks hold size while the ring expands, then collapse late —
            # the crest breathes instead of ticking down (QUALITY §2 row 6).
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.85), (0.6, 0.7), (1.0, 0.0)],
                [(0.0, 0.95, 0.9, 1.0), (1.0, 0.6, 0.4, 0.95)])))

    # FX-Wave-11.1: single expanding ground-flash quad. ONE particle cannot stack,
    # so this is the legal way to buy back the "impact frame" the trimmed ring lost:
    # a horizontal HDR disc popping 3 -> 9 blocks in 8 ticks, gone before the dust.
    (fx.particle_emitter(
            "ground_flash",
            duration=10, looping=False, max_particles=2,
            start_lifetime=constant(8), start_speed=constant(0),
            start_size=nf3(3.0, 3.0, 3.0), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot(), position=nf3(0, 0.15, 0))
       .with_material(texture_material(CIRCLE, hdr=(1.8, 1.4, 2.4), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE", shade=False)
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.0, 3.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.85), (0.45, 0.5), (1.0, 0.0)],
                [(0.0, 0.9, 0.8, 1.0), (1.0, 0.55, 0.35, 0.95)])))

    # World-lit dust kick that grounds the bloom flash (shade samples the lightmap).
    # FX-Wave-11.1: kicked harder (speed 0.3-0.65, size 0.35-0.6, 30 puffs) so the
    # dust visibly rolls outward — the dark birth tint below keeps the pile legal.
    (fx.particle_emitter(
            "dust_kick",
            duration=30, looping=False, max_particles=32,
            start_lifetime=random_between(18, 26), start_speed=random_between(0.3, 0.65),
            start_size=nf3(random_between(0.35, 0.6), random_between(0.35, 0.6),
                           random_between(0.35, 0.6)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(30))])
       .with_shape(cone(angle=30.0, radius=0.6))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_physics(collision=False, gravity=0.12, bounce_chance=0.0)
       .with_cull_box(*cull)
       .with_curves(
            # Smoothstep billow — dust swells open, no mechanical ramp.
            size_over_lifetime=curve(1.0, 1.8, [SEG_SMOOTH_UP], "lifetime", "size"),
            # FX-Wave-11 stacking-law pass: the birth tint was light grey (0.65,0.6,0.7),
            # so 24 overlapping alpha puffs composited toward white right on top of the
            # ring flash. Birth now starts dark (0.30,0.30,0.40) and only warms later.
            color_over_lifetime=gradient(
                [(0.0, 0.55), (0.5, 0.4), (1.0, 0.0)],
                [(0.0, 0.3, 0.3, 0.4), (1.0, 0.45, 0.4, 0.55)])))

    # Light bleeding along the ground cracks: 4 short radial beams, clipped by terrain.
    pivot = fx.empty("crack_pivot")
    for i in range(4):
        ang = math.radians(90.0 * i)
        end = (2.5 * math.sin(ang), -0.35, -2.5 * math.cos(ang))
        (fx.beam_emitter(
                f"crack_glow_{i}",
                end=end, width=0.12, duration=12, looping=False, emit_rate=0,
                raycast="BLOCKS", raycast_block_mode="VISUAL", raycast_fluid_mode="NONE",
                color_nf=gradient([(0.0, 0.9), (1.0, 0.0)],
                                  [(0.0, 0.85, 0.7, 1.0), (1.0, 0.5, 0.3, 0.9)]))
           .child_of(pivot)
           .with_material(texture_material(BEAM_CORE, hdr=(1.5, 1.1, 2.2),
                                           blend=BLEND_ADDITIVE))
           .with_cull_box((-3.0, -1.5, -3.0), (3.0, 1.5, 3.0)))
    return fx


# ---------------------------------------------------------------------------
# Concept #3 — eclipse:award_star_shower (+ award_star_glint Collision child)
# ---------------------------------------------------------------------------
def build_award_star_shower() -> FxBuilder:
    """Podium moment: spinning nether-star MODEL particles rain from +5, bounce off the
    real floor (the one collision-physics concept in the batch) and glint on impact."""
    fx = FxBuilder("award_star_shower")
    cull = ((-5.0, -1.0, -5.0), (5.0, 7.0, 5.0))

    # renderMode Model renders each particle as the mesh shape's baked model; the shape
    # scale (3, 0.5, 3) spreads emission points like the spec's 3x0.5x3 drop box.
    (fx.particle_emitter(
            "star_fall",
            duration=50, looping=False, max_particles=64,
            start_lifetime=random_between(30, 45), start_speed=constant(0.05),
            start_size=nf3(random_between(0.12, 0.2), random_between(0.12, 0.2),
                           random_between(0.12, 0.2)),
            start_rotation=nf3(constant(0), random_between(0.0, 360.0),
                               random_between(0.0, 360.0)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[
            burst(time=0, count=constant(14)),
            burst(time=6, count=constant(14)),
            burst(time=12, count=constant(14))])
       .with_shape(mesh(model="item/nether_star", emit_from="Triangle"),
                   position=nf3(0.0, 5.0, 0.0), scale=nf3(3.0, 0.5, 3.0))
       # block_atlas + useBlockUV: each particle IS the baked nether-star model with its
       # real sprite (the HDR celebration light rides the glint sub-emitter instead).
       # depthMask 1b: translucent Model particles need depth writes or DISTANCE sorting
       # (PHOTON-QUALITY §2 row 14 — z-shimmer when overlapping stars had neither).
       .with_material(block_atlas_material(blend=BLEND_ALPHA, depth_mask=True))
       .with_renderer(render_mode="Model", use_block_uv=True)
       .with_lights()
       .with_physics(collision=True, removed_when_collided=False, friction=0.99,
                     collided_friction=0.6, gravity=0.5, bounce_chance=0.85,
                     bounce_rate=0.45, bounce_spread=0.15)
       .with_sub_emitters(sub_emitter("eclipse:award_star_glint",
                                      event="Collision", probability=0.5))
       .with_cull_box(*cull)
       .with_curves(
            rotation_over_lifetime=constant(14.0),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.85, 0.95), (1.0, 0.0)],
                [(0.0, 1.0, 0.95, 0.75), (1.0, 0.95, 0.8, 0.45)])))

    # Soft additive gold veil around the winner (no physics; pure celebration light).
    (fx.particle_emitter(
            "gold_haze",
            duration=50, looping=False, max_particles=24,
            start_lifetime=random_between(28, 40), start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(0.35, 0.6), random_between(0.35, 0.6),
                           random_between(0.35, 0.6)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(20))])
       .with_shape(sphere(radius=1.1, thickness=0.4))
       .at(0.0, 1.2, 0.0)
       .with_material(texture_material(CIRCLE, hdr=(1.1, 0.95, 0.5), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.02), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 0.85, 0.45), (1.0, 0.85, 0.6, 0.25)])))
    return fx


def build_award_star_glint() -> FxBuilder:
    """Collision sub-emitter child: a 4-particle HDR micro-spark at every star bounce.
    Identity read (QUALITY §5.1 rule 6): star-shaped glints off star_2x2.png (authored
    by gen_player_fx.py), each picking a random frame; pop-shrink size so the glint
    flares and dies instead of linearly popping out of existence (§2 row 13)."""
    fx = FxBuilder("award_star_glint")
    (fx.particle_emitter(
            "glint",
            duration=10, looping=False, max_particles=8,
            start_lifetime=random_between(4, 7), start_speed=random_between(0.05, 0.18),
            start_size=nf3(random_between(0.04, 0.08), random_between(0.04, 0.08),
                           random_between(0.04, 0.08)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(4))])
       .with_shape(sphere(radius=0.08))
       .with_material(texture_material(STAR_2X2, hdr=(1.8, 1.5, 0.6), blend=BLEND_ADDITIVE))
       .with_cull_box((-1.0, -1.0, -1.0), (1.0, 1.0, 1.0))
       .with_curves(
            uv_animation=dict(tiles=(2, 2), animation="WholeSheet",
                              frame_over_time=constant(0),
                              start_frame=random_between(0.0, 3.0)),
            size_over_lifetime=curve(0.0, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)],
                                         [(0.0, 1.0, 0.95, 0.7)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #7 — eclipse:sentinel_alert + eclipse:sentinel_petal_orbit
# (anchored by PhotonMobFx at body center: entity eye - 0.9)
# ---------------------------------------------------------------------------
def build_sentinel_alert() -> FxBuilder:
    """DATA_FROZEN rising edge: a petal-flash cracks off the statue + one mid-bright HDR
    wink at the chest — the 'caught you looking' camera flash.

    W13/B2: no movement levers here on purpose — the row only fires on the FREEZE edge,
    i.e. the statue is by definition standing still, so inheritVelocity/distanceRate
    would be measurably-zero no-ops. What it does get is `random_gradient` on the petals
    (a sentinel you meet three times must not flash three identical puffs) and the
    LINT-LINEAR-CURVE fix on the wink."""
    fx = FxBuilder("sentinel_alert")
    cull = ((-2.0, -1.5, -2.0), (2.0, 2.0, 2.0))

    (fx.particle_emitter(
            "petal_puff",
            duration=10, looping=False, max_particles=24,
            start_lifetime=random_between(6, 10), start_speed=random_between(0.3, 0.55),
            start_size=nf3(random_between(0.08, 0.14), random_between(0.08, 0.14),
                           random_between(0.08, 0.14)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            start_color=random_color(0xFFFFFFFF, 0xFFF3C4D8),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(20))])
       .with_shape(sphere(radius=0.45, thickness=0.25), scale=nf3(1.0, 2.2, 1.0))
       .with_material(texture_material(PETAL, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull)
       .with_curves(
            rotation_over_lifetime=random_between(-30.0, 30.0),
            # Two ramps: pure bone-white petals and faintly rose-shadowed ones.
            color_over_lifetime=varied(
                [(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)],
                [(0.0, 0.95, 0.88, 0.93), (1.0, 0.78, 0.66, 0.76)])))

    # Single chest-height HDR wink (mid-bright: a flash, not a flare).
    (fx.particle_emitter(
            "wink",
            duration=10, looping=False, max_particles=2,
            start_lifetime=constant(6), start_speed=constant(0),
            start_size=nf3(0.5, 0.5, 0.5), simulation_space="World")
       .at(0.0, 0.35, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.2, 1.0, 0.9), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            # W13/B2 LINT-LINEAR-CURVE fix: the wink was a mechanical linear ramp-down.
            # A camera flash blooms open and collapses — pop-shrink, not a dimmer.
            size_over_lifetime=curve(0.0, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)],
                                         [(0.0, 1.0, 0.95, 0.9)])))
    return fx


def build_sentinel_petal_orbit() -> FxBuilder:
    """WINDOWED loop while frozen: a slow halo of pale petals orbits the statue, lit by a
    forced lightmap so they read at night without bloom. destroy(false) on thaw.

    W13/B2: the loop's own attach predicate is `isFrozen()`, so the executor never moves
    while it runs — the movement pair stays out and the anti-repetition lever
    (`random_gradient`) does the work instead."""
    fx = FxBuilder("sentinel_petal_orbit")
    (fx.particle_emitter(
            "petal_halo",
            duration=80, looping=True, prewarm=30, max_particles=48,
            start_lifetime=random_between(50, 70), start_speed=constant(0.02),
            start_size=nf3(random_between(0.08, 0.14), random_between(0.08, 0.14),
                           random_between(0.08, 0.14)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            start_color=random_color(0xFFFFFFFF, 0xFFEFBFD4),
            simulation_space="Local")
       .with_emission(rate=constant(0.55))
       .with_shape(cylinder(radius=1.1, thickness=0.0, arc_mode="Loop", arc_speed=0.4),
                   scale=nf3(1.0, 1.8, 1.0))
       .with_material(texture_material(PETAL, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_lights(sky=15, block=10)
       .with_cull_box((-2.5, -1.8, -2.5), (2.5, 3.0, 2.5))
       .with_curves(
            velocity_over_lifetime=dict(
                orbital=nf3(constant(0), constant(0.5), constant(0)),
                orbital_mode="AngularVelocity"),
            rotation_over_lifetime=random_between(-8.0, 8.0),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.85), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, 0.95, 0.85, 0.92)],
                [(0.0, 0.93, 0.85, 0.98), (1.0, 0.72, 0.62, 0.8)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #9 + N12 — eclipse:gazer_gaze_beam (loop, AutoRotate.LOOK) and its
# eclipse:gazer_tether_snap tear-off child.
#
# COORD FRAME (verified against the shipped jar, B2_MOB_REPORT §0.1). AutoRotate.LOOK is
#   root.updateRotation(new Quaternionf(rotation)
#           .rotateXYZ(0, atan2(-look.z, look.x), look.y));
# JOML's rotateXYZ applies Rz FIRST, then Ry, so a local vector maps as
#   +X -> (cos(ly)*lx/h, sin(ly), cos(ly)*lz/h) ~= the LOOK direction
#   -Z -> (lz/h, 0, -lx/h)                       = the look turned 90 deg sideways
# The shipped asset aimed its 14-block thread down local -Z, i.e. PERPENDICULAR to the
# stare, and hung the hypnosis rings in the matching wrong plane. Both are fixed below:
# the thread runs along +X and the rings sit in the YZ plane facing down it.
# ---------------------------------------------------------------------------
#: How far along the gaze the tether's physics anchor rides. Long enough that a head
#: turn sweeps it through a wide arc (the swing), short enough to stay inside the cull.
TETHER_REACH = 3.2
#: Gaze palette: the thread is violet-ink, never a laser (IDEAS-mobs #9 design caution).
GAZE_DIM = (0.30, 0.20, 0.45)
GAZE_LIT = (0.72, 0.58, 0.95)


def build_gazer_gaze_beam() -> FxBuilder:
    """N12 — the gaze stops being a line and becomes a VISCOUS THREAD.

    Three ara strands hang off an anchor {TETHER_REACH} blocks down the stare with
    deliberately DIFFERENT inertia/damping: while the hood holds still they overlap
    pixel-for-pixel (no extra read, no extra cost), and the moment the head turns they
    fan apart and drag behind the swing — the thread visibly stretches, and when the
    stare finally breaks the strands run out of segment lifetime and fray away. The
    tension beads ride the same anchor in World space with a positive inheritVelocity,
    so a head whip flings them off the cord and `colorBySpeed` lights them up exactly
    for that instant. The discrete tear is `gazer_tether_snap`, fired by the client
    gaze watcher in MobPhotonFxRows.
    """
    fx = FxBuilder("gazer_gaze_beam")
    # Cull along +X now (the real stare axis) and wide enough for the tether swing.
    cull_beam = ((-1.5, -2.0, -1.5), (15.0, 2.0, 1.5))
    cull_near = ((-1.5, -1.5, -1.5), (5.5, 1.5, 1.5))

    thread = fx.beam_emitter(
        "gaze_thread",
        end=(14.0, 0.0, 0.0), width=0.055, duration=60, looping=True, emit_rate=0,
        raycast="BLOCKS_AND_ENTITIES", raycast_block_mode="VISUAL",
        raycast_fluid_mode="NONE",
        # Brighter at the gazer end, fading to nothing toward the watched player: a
        # thread you *sense*, not a laser (design caution in IDEAS-mobs #9).
        color_nf=gradient([(0.0, 0.32), (0.6, 0.12), (1.0, 0.0)],
                          [(0.0, 0.5, 0.35, 0.65), (1.0, 0.3, 0.2, 0.45)]))
    (thread.with_material(texture_material(BEAM_CORE, blend=BLEND_ADDITIVE))
           .with_uv_animation(tiles=(1, 4), animation="SingleRow",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]), cycle=2.0)
           .with_cull_box(*cull_beam))

    # The physics anchor: a child empty parked down the stare. AutoRotate.LOOK re-aims
    # the root every frame, so this point sweeps an ARC through the world when the hood
    # turns — which is precisely the emitter motion the ara physics integrates.
    anchor = fx.empty("tether_anchor").at(TETHER_REACH, 0.0, 0.0)

    # Three strands, same anchor, different lag. Identical while still, viscous when moved.
    for name, inertia, damping, time_s, thick in (
            ("tether_strand_core", 0.30, 0.82, 0.40, 0.055),
            ("tether_strand_mid", 0.44, 0.70, 0.55, 0.038),
            ("tether_strand_slack", 0.58, 0.58, 0.70, 0.026)):
        strand = (fx.ara_trail_emitter(
                name,
                duration=60, looping=True,
                space="World", alignment="View", thickness=thick,
                time=time_s, time_interval=0.05, min_distance=0.03,
                thickness_over_length=eased([(0.0, 1.0), (0.55, 0.6), (1.0, 0.0)]),
                color_over_length=gradient(
                    [(0.0, 0.55), (0.5, 0.26), (1.0, 0.0)],
                    [(0.0, *GAZE_LIT), (0.55, *GAZE_DIM), (1.0, 0.06, 0.03, 0.1)]),
                physics=dict(inertia=inertia, velocity_smoothing=0.85, damping=damping))
           .child_of(anchor)
           .with_material(texture_material(BEAM_CORE, hdr=hdr(0.75, 0.45, 1.2),
                                           blend=BLEND_ADDITIVE))
           .with_cull_box(*cull_beam))
        ara_toggles_on(strand)

    # Tension beads: World space so they are LEFT BEHIND by the swing; the positive
    # inheritVelocity is what actually throws them, and colorBySpeed turns that throw
    # into light. A motionless stare therefore stays almost invisible.
    (fx.particle_emitter(
            "tension_beads",
            duration=60, looping=True, prewarm=10, max_particles=20,
            start_lifetime=random_between(9, 16), start_speed=constant(0.02),
            start_size=nf3(random_between(0.03, 0.055), random_between(0.03, 0.055),
                           random_between(0.03, 0.055)),
            simulation_space="World")
       .child_of(anchor)
       .with_emission(rate=constant(0.45), distance_rate=constant(0.30))
       .with_shape(sphere(radius=0.10))
       .with_module("inheritVelocity", inherit_velocity(0.85))
       .with_module("colorBySpeed", color_by_speed(GAZE_DIM, GAZE_LIT, 0.6, 7.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.8, 0.5, 1.25),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull_beam)
       .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.7), (0.75, 0.4), (1.0, 0.0)],
                [(0.0, *GAZE_LIT), (1.0, *GAZE_DIM)],
                [(0.0, 0.6, 0.66, 0.98), (1.0, 0.22, 0.18, 0.4)])))

    # Fray wisps: Local space, so a NEGATIVE inheritVelocity drags them off the cord —
    # the fuzz that makes the thread look wet/viscous rather than drawn.
    (fx.particle_emitter(
            "fray_wisps",
            duration=60, looping=True, prewarm=15, max_particles=16,
            start_lifetime=random_between(14, 22), start_speed=constant(0.015),
            start_size=nf3(random_between(0.05, 0.09), random_between(0.05, 0.09),
                           random_between(0.05, 0.09)),
            simulation_space="Local")
       .with_emission(rate=constant(0.35))
       .with_shape(box(emit_from="Volume"), position=nf3(TETHER_REACH * 0.5, 0.0, 0.0),
                   scale=nf3(TETHER_REACH, 0.10, 0.10))
       .with_module("inheritVelocity", inherit_velocity(-0.5))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull_beam)
       .with_curves(
            noise=dict(frequency=0.6, quality="Noise2D", position=nf3(0.05)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.28), (1.0, 0.0)],
                [(0.0, *GAZE_DIM), (1.0, 0.05, 0.03, 0.09)],
                [(0.0, 0.24, 0.14, 0.36), (1.0, 0.04, 0.02, 0.07)])))

    for name, arc_speed in (("hypnosis_ring", 0.6), ("hypnosis_ring_counter", -0.6)):
        (fx.particle_emitter(
                name,
                duration=60, looping=True, prewarm=20, max_particles=12,
                start_lifetime=constant(20), start_speed=constant(0.01),
                start_size=nf3(0.05, 0.05, 0.05), simulation_space="Local")
           .with_emission(rate=constant(0.5))
           # circle() is an XZ ring; rotating the shape 90 deg about Z lifts it into the
           # YZ plane, i.e. a ring standing PERPENDICULAR to the +X stare axis.
           .with_shape(circle(radius=0.45, thickness=0.0, arc_mode="Loop",
                              arc_speed=arc_speed),
                       rotation=nf3(0.0, 0.0, 90.0))
           .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
           # Quads in the emitter's YZ plane so they face down the gaze with the ring.
           .with_renderer(facing_mode="EMITTER_TRANSFORM_YZ", vertex_sorting="DISTANCE")
           .with_cull_box(*cull_near)
           .with_curves(
                rotation_over_lifetime=random_between(-6.0, 6.0),
                color_over_lifetime=varied(
                    [(0.0, 0.0), (0.3, 0.35), (1.0, 0.0)],
                    [(0.0, 0.55, 0.4, 0.7), (1.0, 0.35, 0.25, 0.5)],
                    [(0.0, 0.42, 0.34, 0.72), (1.0, 0.24, 0.18, 0.42)])))
    return fx


def build_gazer_tether_snap() -> FxBuilder:
    """N12 tear-off (one-shot, 22 t) — fired at the gazer's eye the tick the client gaze
    watcher (MobPhotonFxRows) sees the stare cone break.

    Deliberately rotation-agnostic (AUTO_ROTATE_NONE): the snap only uses radial motion
    and one pop, so it reads the same no matter where the hood ended up pointing after
    the whip. The recoil runs INWARD — the cord snapping back into the hood, not an
    explosion — and the closing pop is DARK: the gazer losing you is a light going out.
    """
    fx = FxBuilder("gazer_tether_snap")
    cull = ((-2.5, -2.5, -2.5), (2.5, 2.5, 2.5))

    # Recoil: born on a 1.1 r shell and hauled back to the eye. radial is scaled x0.01
    # per tick, so -55 is ~1.1 block/s of inward rush over the 10-16 t life.
    (fx.particle_emitter(
            "snap_recoil",
            duration=16, looping=False, max_particles=28,
            start_lifetime=random_between(10, 16), start_speed=constant(0.02),
            start_size=nf3(random_between(0.04, 0.075), random_between(0.04, 0.075),
                           random_between(0.04, 0.075)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(18))])
       .with_shape(sphere(radius=1.1, thickness=0.35))
       .with_module("colorBySpeed", color_by_speed(GAZE_DIM, GAZE_LIT, 0.4, 3.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.85, 0.5, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-55.0)),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.75), (0.7, 0.35), (1.0, 0.0)],
                [(0.0, *GAZE_LIT), (1.0, *GAZE_DIM)],
                [(0.0, 0.58, 0.62, 0.96), (1.0, 0.2, 0.14, 0.34)])))

    # Fibre shards: the strands that DIDN'T make it back, flung outward and stretched.
    (fx.particle_emitter(
            "fiber_shards",
            duration=14, looping=False, max_particles=16,
            start_lifetime=random_between(5, 9), start_speed=random_between(1.6, 3.2),
            start_size=nf3(random_between(0.03, 0.06), random_between(0.03, 0.06),
                           random_between(0.03, 0.06)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(10))])
       .with_shape(sphere(radius=0.18, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.6, 0.3, 0.95),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.4,
                      length_scale=2.6)
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                speed_modifier=eased([(0.0, 1.0), (0.5, 0.34), (1.0, 0.08)])),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 0.6), (1.0, 0.0)],
                [(0.0, *GAZE_DIM), (1.0, *COR_INK)],
                [(0.0, 0.4, 0.2, 0.6), (1.0, 0.1, 0.02, 0.18)])))

    # The stare going out: ONE alpha quad that swells and dies. No HDR — the whole point
    # of the beat is subtraction of attention, not a flare.
    (fx.particle_emitter(
            "loss_pop",
            duration=14, looping=False, max_particles=2,
            start_lifetime=constant(9), start_speed=constant(0),
            start_size=nf3(0.42, 0.42, 0.42), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.0, 1.6, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.5), (1.0, 0.0)],
                [(0.0, *GAZE_DIM), (1.0, 0.03, 0.02, 0.06)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #5 — eclipse:glitch_pop (the code-reserved GlitchedMonster.tryBlink slot)
# ---------------------------------------------------------------------------
def build_glitch_pop() -> FxBuilder:
    """Datamosh blink pop: ONE emitter, TWO material passes on the same quads — pass 1
    REVERSE_SUB (ONE/ONE) rips a dark decompression hole out of the framebuffer, pass 2
    ADD scatters RGB-split static shards (4x4 flipbook). World space: the hole hangs in
    the air after the mob is gone. allowMulti=true at the call site (origin + exit can
    share a BlockPos).

    W13/B2: this is the one mob asset on a POSITION cue (CUE_GLITCH_POP carries a
    BlockPos, not an entity), so its executor never accumulates distance and never has an
    emitter velocity — distanceRate and inheritVelocity would both be provable no-ops and
    stay out. The pass here is the LINT-LINEAR-CURVE fix: the datamosh shards used to
    ramp down like a dimmer, they now snap open and rot away."""
    fx = FxBuilder("glitch_pop")
    (fx.particle_emitter(
            "datamosh",
            duration=14, looping=False, max_particles=32,
            start_lifetime=random_between(6, 10), start_speed=random_between(0.05, 0.25),
            start_size=nf3(random_between(0.14, 0.3), random_between(0.14, 0.3),
                           random_between(0.14, 0.3)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            # Chromatic-aberration split: pure-red .. pure-blue lerp per particle. The
            # SUB pass eats that channel (cyan/yellow shadow), the ADD pass re-emits it.
            start_color=random_color(0xFFFF2A2A, 0xFF2A2AFF),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(18))])
       .with_shape(box(emit_from="Shell"), scale=nf3(0.8, 1.9, 0.8))
       # Pass 1: the dark rip. Both passes share the emitter uvAnimation, so this
       # texture is a 4x4 sheet of identical soft squares (square_4x4.png).
       .with_material(texture_material(SQUARE_4X4, blend=BLEND_REVERSE_SUB))
       # Pass 2: hot static shards over the hole.
       .with_material(texture_material(STATIC_4X4, hdr=(1.2, 1.2, 1.2),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")  # REVERSE_SUB is order-independent vs itself
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 3.0, 2.0))
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              cycle=2.0),
            size_over_lifetime=eased([(0.0, 1.0), (0.2, 1.0), (1.0, 0.4)]),
            color_over_lifetime=gradient([(0.0, 1.0), (0.7, 0.9), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #6 — eclipse:shadow_bolt_ribbon (loop; entity executor auto-destroys with bolt)
# ---------------------------------------------------------------------------
def build_shadow_bolt_ribbon() -> FxBuilder:
    """Wither-violet ara ribbon dragged by the homing bolt (World-space segments lag
    behind the eye anchor every frame) + a drip of wither motes inheriting bolt speed.

    W13/B2: `ara_toggles_on` is the headline here — the ribbon shipped with a
    physicsSetting payload but no `_enable: 1b`, so its inertia/damping never ran and the
    "lag" was pure segment history. The motes get the full movement set: a stronger
    inheritVelocity so they hang in the bolt's wake, distanceRate so a long homing arc
    sheds proportionally more, and colorBySpeed so the ones that lose the bolt cool from
    violet into ink."""
    fx = FxBuilder("shadow_bolt_ribbon")
    cull = ((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0))

    ribbon = (fx.ara_trail_emitter(
            "bolt_ribbon",
            duration=100, looping=True,
            space="World", alignment="View", thickness=0.16,
            time=0.45, time_interval=0.05, min_distance=0.05,
            # Eased taper (LINT-LINEAR-CURVE): the ribbon holds its body, then whips thin.
            thickness_over_length=eased([(0.0, 1.0), (0.5, 0.62), (1.0, 0.0)]),
            # Violet core fading to black edge along the tail; the faint HDR on the
            # material is a bright-violet bloom thread (NOT a dark bloom).
            color_over_length=gradient(
                [(0.0, 0.85), (0.6, 0.4), (1.0, 0.0)],
                [(0.0, 0.5, 0.2, 0.65), (1.0, 0.06, 0.02, 0.1)]),
            physics=dict(inertia=0.4, velocity_smoothing=0.8, damping=0.7))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.9, 0.4, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull))
    ara_toggles_on(ribbon)

    (fx.particle_emitter(
            "wither_motes",
            duration=100, looping=True, max_particles=16,
            start_lifetime=random_between(8, 14), start_speed=constant(0.02),
            start_size=nf3(random_between(0.05, 0.09), random_between(0.05, 0.09),
                           random_between(0.05, 0.09)),
            simulation_space="World")
       # distanceRate bites on this lane: the executor rides the projectile, so a long
       # homing arc sheds proportionally more motes than a point-blank shot.
       .with_emission(rate=constant(0.4), distance_rate=constant(0.55))
       .with_shape(sphere(radius=0.12))
       .with_module("inheritVelocity", inherit_velocity(0.45))
       .with_module("colorBySpeed", color_by_speed(COR_INK, COR_VIOLET, 1.0, 12.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.8, 0.35, 1.1),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.8), (1.0, 0.0)],
                [(0.0, 0.55, 0.25, 0.7), (1.0, 0.2, 0.05, 0.3)],
                [(0.0, 0.42, 0.14, 0.62), (1.0, 0.12, 0.02, 0.22)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #4 (hound half) — eclipse:hound_lunge_windup + eclipse:hound_dash_trail
# ---------------------------------------------------------------------------
def build_hound_lunge_windup() -> FxBuilder:
    """20t = ChargedLungeGoal.WINDUP_TICKS: an electric spiral collapses inward onto the
    rooted hound (function shape over emitter t), crest blooming as the glow-spine anim
    peaks, then a 16-burst release pop at t=19 (spawns at the spiral's collapsed center).

    W13/B2 — silent-defect fix: this emitter already asked for `colorBySpeed`, but through
    `with_curves(color_by_speed=...)`, which writes `speedRange` as `{min, max}`. The
    module's `Range` codec reads `a`/`b`, so the range never deserialised and the whole
    module was dead. It is re-attached via `with_module` with a real range tuned to the
    spiral's own tempo: the function shape drives ~0.42 b/s at the outer turn and stalls
    toward the centre, so the outside reads white-hot and the collapse cools to spine-blue
    — you can now SEE the charge tightening. The hound is rooted for the whole 20 t
    (that is what the windup is), so inheritVelocity/distanceRate stay out as no-ops."""
    fx = FxBuilder("hound_lunge_windup")
    (fx.particle_emitter(
            "charge_spiral",
            duration=20, looping=False, max_particles=80,
            start_lifetime=random_between(6, 10), start_speed=constant(1.0),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="Local")
       .with_emission(rate=constant(3.0), bursts=[burst(time=19, count=constant(16))])
       .with_shape(function_shape(
            x="(1-t)*1.2*cos(t*6*PI)", z="(1-t)*1.2*sin(t*6*PI)", y="0.2+t*0.6",
            speed_x="0-x*0.35", speed_y="0.05", speed_z="0-z*0.35"))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.8, 1.0, 1.4),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box((-2.0, -0.5, -2.0), (2.0, 2.0, 2.0))
       .with_module("colorBySpeed",
                    color_by_speed((0.55, 0.75, 1.0), (1.0, 1.0, 1.0), 0.05, 0.45))
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 1.0), (0.75, 0.9), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)],
                [(0.0, 0.82, 0.93, 1.0), (1.0, 0.66, 0.82, 1.0)])))
    return fx


#: Blocks of dash travel per shed grit particle (the distanceRate lever). At the hound's
#: dash speed a 16 t lunge covers ~7 blocks, so ~20 grit motes lay the whole line —
#: independent of frame rate, unlike a per-tick emissionRate.
DASH_GRIT_PER_BLOCK = 0.35


def build_hound_dash_trail() -> FxBuilder:
    """One-shot 16t ~= MAX_DASH_TICKS: a physics-lagged ara ribbon (fat -> nothing)
    whipped and settled behind the dash line. Attached AutoRotate.FORWARD.

    W13/B2 — this is the census' named distanceRate target, and mobs are where it works:
    the executor rides the hound, so `accumulatedDistance` really grows. `dash_grit`
    therefore emits per BLOCK TRAVELLED, not per tick, which means a short pounce leaves a
    short scar and a full-length lunge leaves a long one — the trail finally encodes how
    far the thing actually moved. It also fixes two shipped defects: the ribbon's
    physicsSetting had no `_enable: 1b` (inertia/damping never ran) and its alpha material
    rendered with vertexSortingMode NONE (LINT-ALPHA-NOSORT)."""
    fx = FxBuilder("hound_dash_trail")
    cull = ((-8.0, -2.0, -8.0), (8.0, 3.0, 8.0))

    ribbon = (fx.ara_trail_emitter(
            "dash_ribbon",
            duration=16, looping=False,
            space="World", alignment="Velocity", thickness=0.35,
            time=0.7, time_interval=0.05, min_distance=0.05,
            # Eased taper (LINT-LINEAR-CURVE): a body that holds, then tears to nothing.
            thickness_over_length=eased([(0.0, 1.0), (0.45, 0.68), (1.0, 0.0)]),
            # Fog-grey with a transparent tail.
            color_over_length=gradient(
                [(0.0, 0.5), (0.6, 0.3), (1.0, 0.0)],
                [(0.0, 0.62, 0.66, 0.7), (1.0, 0.42, 0.46, 0.52)]),
            physics=dict(inertia=0.55, velocity_smoothing=0.8, damping=0.7))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull))
    ara_toggles_on(ribbon)

    # Grit shed along the dash line. World space + positive inheritVelocity: the motes
    # launch in the hound's wake and then fall out of it, and colorBySpeed makes exactly
    # that decay visible (white-hot at launch, cold slate once the hound has left them).
    (fx.particle_emitter(
            "dash_grit",
            duration=16, looping=False, max_particles=40,
            start_lifetime=random_between(8, 16), start_speed=random_between(0.1, 0.35),
            start_size=nf3(random_between(0.035, 0.075), random_between(0.035, 0.075),
                           random_between(0.035, 0.075)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), distance_rate=constant(DASH_GRIT_PER_BLOCK))
       .with_shape(sphere(radius=0.22, thickness=0.5))
       .with_module("inheritVelocity", inherit_velocity(0.30))
       .with_module("colorBySpeed", color_by_speed((0.30, 0.34, 0.42), (0.95, 0.98, 1.0),
                                                   0.8, 6.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.75, 0.85, 1.1),
                                       blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.09, bounce_chance=0.0)
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.7), (0.7, 0.35), (1.0, 0.0)],
                [(0.0, 0.86, 0.9, 1.0), (1.0, 0.34, 0.38, 0.46)],
                [(0.0, 0.72, 0.84, 0.98), (1.0, 0.24, 0.28, 0.36)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #8 — eclipse:other_dread_aura (loop; 24-block attach gate lives in PhotonMobFx)
# ---------------------------------------------------------------------------
def build_other_dread_aura() -> FxBuilder:
    """Slow-breathing shroud that visibly EATS light: large soft REVERSE_SUB quads hug the
    body (~12% luminance subtraction, 5 s sine breath — photosensitivity-safe) while
    desaturated violet motes fall (dread falls, not rises). No hdr anywhere: darkness
    comes from subtraction, never from bloom.

    W13/B2 — the census' "Auren mit inheritVelocity (reißen beim Laufen mit)" case. Both
    emitters are Local space, so they were previously welded to the transform and slid
    around The Other like a decal. A NEGATIVE multiply is the drag knob there: the shroud
    now lags behind its own body when it walks and re-settles when it stops, which is the
    single biggest tell that this thing is not a teammate. distanceRate on the motes makes
    the aura shed harder the further it stalks you. Deliberately NO colorBySpeed: the
    module MULTIPLIES the lifetime colour, i.e. it can only brighten toward white, and a
    light-eating shroud that lights up when it moves would invert the whole concept."""
    fx = FxBuilder("other_dread_aura")
    cull = ((-2.0, -1.5, -2.0), (2.0, 3.0, 2.0))

    (fx.particle_emitter(
            "light_eater",
            duration=100, looping=True, prewarm=50, max_particles=8,
            start_lifetime=random_between(90, 110), start_speed=constant(0.005),
            start_size=nf3(random_between(0.9, 1.3), random_between(0.9, 1.3),
                           random_between(0.9, 1.3)),
            # ~12% grey: with ONE/ONE REVERSE_SUB this subtracts a subtle dimming veil.
            start_color=0xFF1F1F26,
            simulation_space="Local")
       .with_emission(rate=constant(0.08))
       .with_shape(box(emit_from="Volume"), scale=nf3(0.7, 1.8, 0.7))
       # Local space -> negative multiply = drag: the veil peels off the body when he
       # walks instead of riding it like a sticker.
       .with_module("inheritVelocity", inherit_velocity(-0.35))
       .with_material(texture_material(CIRCLE, blend=BLEND_REVERSE_SUB))
       .with_renderer(order_in_layer=-1)  # shroud draws before other translucents
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.85, 1.0, SEGS_BREATHE, "lifetime", "size")))

    (fx.particle_emitter(
            "violet_motes",
            duration=100, looping=True, prewarm=30, max_particles=16,
            start_lifetime=constant(40), start_speed=constant(0.01),
            start_size=nf3(random_between(0.06, 0.1), random_between(0.06, 0.1),
                           random_between(0.06, 0.1)),
            simulation_space="Local")
       # distanceRate is real on this lane (entity-attached loop): the closer he stalks,
       # the more the aura sheds, so approach alone thickens the dread.
       .with_emission(rate=constant(0.4), distance_rate=constant(0.5))
       .with_shape(box(emit_from="Volume"), scale=nf3(0.9, 1.9, 0.9))
       .with_module("inheritVelocity", inherit_velocity(-0.5))
       .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(-0.025), constant(0))),
            # Greyed violet, luminance far below the bloom threshold (no hdr at all).
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.5), (1.0, 0.0)],
                [(0.0, 0.353, 0.306, 0.4), (1.0, 0.227, 0.196, 0.267)],
                [(0.0, 0.286, 0.271, 0.376), (1.0, 0.176, 0.169, 0.239)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #10 — eclipse:wanderer_static_shroud (loop; shade:1b IS the concept)
# ---------------------------------------------------------------------------
def build_wanderer_static_shroud() -> FxBuilder:
    """Backrooms Wanderer: mono-yellow paint haze with shade:1b — every particle samples
    the world lightmap, so the shroud dims in perfect sync with tickFlicker's real dark
    windows, zero sync code. The sparse REVERSE_SUB static flecks keep shade:0b: they are
    the thing that does NOT obey the lights.

    W13/B2: both emitters are Local, so a negative inheritVelocity is the drag knob — the
    paint haze now smears behind the wanderer's shamble and the seams tear off harder.
    distanceRate on the seams ties the corruption density to how far it has walked. No
    colorBySpeed and no HDR here by design: `shade:1b` IS the concept, and hdr on an
    alpha-blended shaded material is LINT-HDR-DUST."""
    fx = FxBuilder("wanderer_static_shroud")
    cull = ((-2.0, -1.5, -2.0), (2.0, 3.0, 2.0))

    (fx.particle_emitter(
            "paint_haze",
            duration=50, looping=True, prewarm=25, max_particles=32,
            start_lifetime=random_between(25, 35), start_speed=constant(0.02),
            start_size=nf3(random_between(0.14, 0.24), random_between(0.14, 0.24),
                           random_between(0.14, 0.24)),
            simulation_space="Local")
       .with_emission(rate=constant(0.8))
       .with_shape(box(emit_from="Volume"), scale=nf3(0.8, 1.9, 0.8))
       .with_module("inheritVelocity", inherit_velocity(-0.4))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)  # the whole concept
       .with_cull_box(*cull)
       .with_curves(
            noise=dict(frequency=0.7, quality="Noise2D", position=nf3(0.05)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.5), (0.8, 0.35), (1.0, 0.0)],
                # Mono-yellow "wet paint" (Backrooms texture-sheet palette).
                [(0.0, 0.85, 0.76, 0.35), (1.0, 0.7, 0.6, 0.25)],
                [(0.0, 0.74, 0.7, 0.42), (1.0, 0.58, 0.53, 0.3)])))

    (fx.particle_emitter(
            "static_seams",
            duration=50, looping=True, max_particles=8,
            start_lifetime=random_between(10, 16), start_speed=constant(0.01),
            start_size=nf3(random_between(0.12, 0.2), random_between(0.12, 0.2),
                           random_between(0.12, 0.2)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            start_color=0xFF9A9A9A,
            simulation_space="Local")
       .with_emission(rate=constant(0.2), distance_rate=constant(0.65))
       .with_shape(box(emit_from="Shell"), scale=nf3(0.85, 1.95, 0.85))
       .with_module("inheritVelocity", inherit_velocity(-0.55))
       .with_material(texture_material(STATIC_4X4, blend=BLEND_REVERSE_SUB))
       .with_cull_box(*cull)
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              cycle=3.0),
            color_over_lifetime=varied([(0.0, 0.9), (1.0, 0.0)],
                                       [(0.0, 1.0, 1.0, 1.0)],
                                       [(0.0, 0.78, 0.78, 0.86)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #4 (revenant half) — eclipse:revenant_fog_ribbons (loop, 60t)
#
# OWNERSHIP NOTE (FX_CENSUS_WAVE13 §7 conflict law 1: "one .fx belongs to exactly ONE
# generator"). This builder shipped inside `backlog_fx.py`, whose wave-13 owner is A5 for
# the TYRANT parts, while `fx/revenant_*` is listed under B2. It was moved here so the
# asset and its generator live in the same conflict unit again; the removal on the
# backlog_fx.py side is exactly three lines (docstring entry, function, BUILDERS row).
# ---------------------------------------------------------------------------
def build_revenant_fog_ribbons() -> FxBuilder:
    """IDEAS-mobs #4: the Fog Revenant's CAMPFIRE hem smoke upgraded to lagging robe
    ribbons — a low cylinder-shell wisp emitter whose particles drag short TRAIL-type
    streamers as the noise wobble tears them off the hem. Local space (the aura follows
    the drift); attached by PhotonMobFx at eye -0.9 (hem, not eyes), nearest-4 cap.

    W13/B2: a robe hem is the most literal "tears along when it walks" surface in the mob
    set, and it was the one thing the Local-space emitter could not do. The negative
    inheritVelocity gives the hem real drag (it trails, then settles), distanceRate ties
    the shed rate to distance drifted rather than time, and random_gradient stops a patch
    of four revenants from wearing one identical robe."""
    fx = FxBuilder("revenant_fog_ribbons")
    cull = ((-3.0, -1.5, -3.0), (3.0, 3.5, 3.0))

    wisps = (fx.particle_emitter(
            "hem_wisps",
            duration=60, looping=True, prewarm=20,
            start_lifetime=random_between(30, 40),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.14, 0.26), random_between(0.14, 0.26),
                           random_between(0.14, 0.26)),
            simulation_space="Local", max_particles=64)
        .with_emission(rate=constant(0.6), distance_rate=constant(0.45))
        .with_shape(cylinder(radius=0.5, thickness=0.3), scale=(1.0, 0.3, 1.0))
        .with_module("inheritVelocity", inherit_velocity(-0.4))
        .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), constant(0.028), constant(0.0)),
                speed_modifier=eased([(0.0, 0.5), (0.6, 1.0), (1.0, 1.2)])),
            noise=dict(frequency=0.5, quality="Noise2D",
                       position=nf3(constant(0.06), constant(0.02), constant(0.06))),
            size_over_lifetime=eased([(0.0, 0.7), (0.45, 1.0), (1.0, 0.5)]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.4), (0.75, 0.28), (1.0, 0.0)],
                [(0.0, *FOG_TEAL), (0.75, *STM_SLATE), (1.0, *GLI_DEAD)],
                [(0.0, 0.46, 0.53, 0.56), (0.75, 0.18, 0.19, 0.28), (1.0, *GLI_DEAD)]))
        .with_cull_box(*cull))
    # The streamers: short plain-TRAIL strips torn off rising wisps (the "robe ribbon"
    # read — cheap segments, no ara physics on a per-mob loop).
    wisps.with_module("trails", {
        "ratio": F(0.5),
        "lifetime": constant(0.4),
        "inheritParticleColor": B(1),
        "trailType": "TRAIL",
        "config": {
            "time": I(10), "minVertexDistance": F(0.04),
            "widthOverTrail": eased([(0.0, 0.12), (1.0, 0.0)]),
            "colorOverTrail": gradient(
                [(0.0, 0.35), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (1.0, *GLI_DEAD)]),
            "renderer": ribbon_renderer(
                texture_material(SMOKE, blend=BLEND_ALPHA), sorting="DISTANCE",
                cull_box=cull)}})
    return fx


# ---------------------------------------------------------------------------
# Textures (deterministic; PIL)
# ---------------------------------------------------------------------------
def write_textures() -> list:
    from PIL import Image, ImageDraw

    written = []

    # static_4x4.png — the shared #5/#10 flipbook: 4x4 grid of 16x16 white-noise frames
    # (WholeSheet uvAnimation steps through them for the datamosh shimmer).
    rng = random.Random(0x574471C)
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    for fy in range(4):
        for fx_ in range(4):
            for x in range(16):
                for y in range(16):
                    v = rng.random()
                    a = int(255 * v * v) if v > 0.45 else 0
                    px[fx_ * 16 + x, fy * 16 + y] = (255, 255, 255, a)
    path = TEXTURE_DIR / "static_4x4.png"
    img.save(path)
    written.append(path)

    # square_4x4.png — 16 identical soft squares on the same 4x4 grid, so the glitch_pop
    # REVERSE_SUB pass survives the shared emitter uvAnimation unchanged.
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    for fy in range(4):
        for fx_ in range(4):
            for x in range(16):
                for y in range(16):
                    dx = abs(x - 7.5) / 8.0
                    dy = abs(y - 7.5) / 8.0
                    d = max(dx, dy)
                    a = 0.0 if d > 0.95 else min(1.0, (0.95 - d) / 0.3)
                    px[fx_ * 16 + x, fy * 16 + y] = (255, 255, 255, int(a * 255))
    path = TEXTURE_DIR / "square_4x4.png"
    img.save(path)
    written.append(path)

    # petal_soft.png — one soft cherry-ish petal (white; tinted by startColor at runtime):
    # an ellipse pinched to a point at the stem end, soft alpha falloff.
    size = 32
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    for x in range(size):
        for y in range(size):
            # Normalized coords, petal axis along +y.
            nx = (x - size / 2 + 0.5) / (size / 2)
            ny = (y - size / 2 + 0.5) / (size / 2)
            # Width envelope: 0 at the stem (ny=-0.9), widest around ny=0.3.
            tt = (ny + 0.9) / 1.7
            if tt <= 0.0 or tt > 1.0:
                continue
            width = 0.62 * math.sin(min(1.0, tt) * math.pi) ** 0.8
            if width < 1e-3:
                continue
            d = abs(nx) / width
            if d >= 1.0:
                continue
            a = (1.0 - d * d) * min(1.0, (1.0 - abs(ny)) * 3.0)
            px[x, y] = (255, 255, 255, int(max(0.0, min(1.0, a)) * 255))
    path = TEXTURE_DIR / "petal_soft.png"
    img.save(path)
    written.append(path)
    return written


BUILDERS = {
    "boss_intro_shockwave.fx": build_boss_intro_shockwave,
    "award_star_shower.fx": build_award_star_shower,
    "award_star_glint.fx": build_award_star_glint,
    "sentinel_alert.fx": build_sentinel_alert,
    "sentinel_petal_orbit.fx": build_sentinel_petal_orbit,
    "gazer_gaze_beam.fx": build_gazer_gaze_beam,
    "gazer_tether_snap.fx": build_gazer_tether_snap,
    "glitch_pop.fx": build_glitch_pop,
    "shadow_bolt_ribbon.fx": build_shadow_bolt_ribbon,
    "hound_lunge_windup.fx": build_hound_lunge_windup,
    "hound_dash_trail.fx": build_hound_dash_trail,
    "other_dread_aura.fx": build_other_dread_aura,
    "wanderer_static_shroud.fx": build_wanderer_static_shroud,
    "revenant_fog_ribbons.fx": build_revenant_fog_ribbons,
}


def main() -> int:
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    for path in write_textures():
        print(f"WROTE {path.relative_to(REPO_ROOT)}")
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        builder = builder_fn()
        raw_len, gz_len = builder.write(path)  # write() round-trip-validates
        builder.write_fxproj(path.with_suffix(".fxproj"))  # binary-diff law sibling
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    sys.exit(main())
