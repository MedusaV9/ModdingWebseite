#!/usr/bin/env python3
"""events_fx — PH-EVENTS Photon `.fx` assets (event sequences), authored with fxlib.

Generates the nine event-sequence effects from
docs/plans_v3/plans_v5/photon/IDEAS-events.md (#1, #2, #3, #5, #6):

    eclipse:intro_burst_ring          IntroSequence BURST HDR white-out ring (§1)
    eclipse:credits_strike_beam       CreditsSequence t=420 lightning-ladder beam (§2)
    eclipse:credits_confetti_burst    CreditsSequence t=650 DOOMSDAY mesh-shard confetti (§6)
    eclipse:structure_slam_mushroom   ExpansionSequence STRUCTURES slam column + clods (§3)
    eclipse:slam_dust_puff            collision sub-emitter of the mushroom clods (§3)
    eclipse:portal_iris_open_xbox     RiftFx STYLE_PORTAL open iris (violet) (§5a)
    eclipse:portal_iris_open_backrooms  RiftFx STYLE_BACKROOMS open iris (wax-gold) (§5a)
    eclipse:portal_loop_xbox          xbox portal identity loop (era pixels + CRT glow) (§5b)
    eclipse:portal_loop_backrooms     backrooms fluorescent flicker + haze loop (§5c)

These files are fxlib-generated (this script IS the committed source — the binary-diff
law's `.fxproj` requirement applies to editor exports only). Regenerate + validate with:

    python3 tools/photon/events_fx.py          # writes all nine into FX_ASSETS_DIR
    python3 tools/photon/fxlib.py validate src/main/resources/assets/eclipse/fx/*.fx

Budget notes (IDEAS-events.md cross-cutting table): every one-shot stays under ~120
particles; both portal loops carry cull boxes + modest maxParticles per the WINDOWED-loop
law (INTEGRATION.md §4). Textures are Photon's own shipped particle set (circle/smoke/
ring/laser) — no new PNGs to license.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, REPO_ROOT, SEG_LINEAR_DOWN,
    SEG_LINEAR_UP, block_atlas_material, burst, circle, cone, constant, curve, dot,
    gradient, mesh, nf3, random_between, random_gradient, sphere, sub_emitter,
    texture_material, validate_file,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"
TEX_RING = "photon:textures/particle/ring.png"
TEX_LASER = "photon:textures/particle/laser.png"

# IntroSequence.VORTEX_RADIUS (frozen R10) — the ring blooms to twice this.
VORTEX_RADIUS = 22.0
# RiftFx portal senders both use RIFT_FX_WIDTH = 5.0; iris/loops are authored for it
# (RiftFx applies executor setScale(width/5) on the iris for other widths).
PORTAL_WIDTH = 5.0

# Fast pop (y 0 -> 1 by x~0.35) then hold — the white-out ring snapping open.
SEG_POP_HOLD = (0.0, 0.0, 0.12, 0.85, 0.35, 1.0, 1.0, 1.0)
# Overshoot-ish iris: snap to full size fast, settle slightly back.
SEG_IRIS_POP = (0.0, 0.03, 0.12, 1.0, 0.5, 1.0, 1.0, 0.95)
# Hold near-full then shrink out late (confetti shard tails).
SEG_HOLD_SHRINK = (0.0, 1.0, 0.7, 1.0, 0.9, 0.6, 1.0, 0.0)


# ---------------------------------------------------------------------------
# §1 eclipse:intro_burst_ring — IntroSequence BURST white-out ring
# ---------------------------------------------------------------------------
def build_intro_burst_ring() -> FxBuilder:
    """One-shot, ~70 particles / 30t. Fired client-locally off the FX_SHOCKWAVE (1.0, 50)
    giant signature (FxPayloads shockwave branch) — emission starts the same tick as
    FLASH_WHITE; the 26t ring spans the shutter and hands its violet tail to FLASH_VIOLET
    (0xCC8800FF) at t+6."""
    fx = FxBuilder("intro_burst_ring")
    # THE white-out source: one flat HDR annulus snapping open on the terrain.
    (fx.particle_emitter(
            "ring_core",
            duration=30, looping=False, start_delay=constant(0),
            start_lifetime=constant(26), start_speed=constant(0.0),
            start_size=nf3(1.0), simulation_space="World", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(circle(radius=0.01, thickness=0.0))
       .with_material(texture_material(TEX_RING, hdr=(3.5, 3.0, 4.0),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.5, VORTEX_RADIUS * 2.0, [SEG_POP_HOLD],
                                           "lifetime", "size") for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.35, 0.85), (0.8, 0.12), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (0.55, 0.85, 0.6, 1.0), (1.0, 0.53, 0.0, 1.0)])))
    # One clean even ring of 48 sparks raining/skipping off the fresh island rim.
    (fx.particle_emitter(
            "ring_sparks",
            duration=30, looping=False, start_delay=constant(0),
            start_lifetime=random_between(20, 32), start_speed=random_between(0.6, 1.2),
            start_size=nf3(random_between(0.14, 0.28), random_between(0.14, 0.28),
                           random_between(0.14, 0.28)),
            simulation_space="World", max_particles=64)
       .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=constant(48))])
       .with_shape(circle(radius=VORTEX_RADIUS, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.6, 1.3, 2.0),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_physics(collision=True, removed_when_collided=False, gravity=0.25,
                     bounce_chance=0.4, bounce_rate=0.4, collided_friction=0.7)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.6, 0.7), (1.0, 0.0)],
            [(0.0, 1.0, 0.97, 1.0), (0.5, 0.75, 0.5, 1.0), (1.0, 0.5, 0.2, 0.9)]))
       .with_lights(sky=15, block=15))
    # The vortex "bursting open" read under the ring: slow hemisphere wisps.
    (fx.particle_emitter(
            "dome_wisp",
            duration=30, looping=False, start_delay=constant(0),
            start_lifetime=random_between(36, 56), start_speed=random_between(0.1, 0.3),
            start_size=nf3(random_between(1.6, 2.6), random_between(1.6, 2.6),
                           random_between(1.6, 2.6)),
            simulation_space="World", max_particles=32)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(20))])
       .with_shape(sphere(radius=8.0, thickness=0.2, arc=180.0))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.25), (1.0, 0.0)],
                [(0.0, 0.6, 0.45, 0.8), (1.0, 0.35, 0.2, 0.5)]),
            size_over_lifetime=nf3(*[curve(1.0, 1.8, [SEG_LINEAR_UP], "lifetime", "size")
                                     for _ in range(3)])))
    return fx


# ---------------------------------------------------------------------------
# §2 eclipse:credits_strike_beam — CreditsSequence t=420 ladder beam
# ---------------------------------------------------------------------------
def build_credits_strike_beam() -> FxBuilder:
    """Spawned once per strike at the impact point (CUE_CREDITS_STRIKE, a=intensity →
    executor setScale). Beam runs impact→zenith (local end +90Y — visually identical to
    zenith→impact, trivial anchor math); the per-strike 12t interval stagger stays
    server-side, no startDelay authoring needed."""
    fx = FxBuilder("credits_strike_beam")
    # Fat flash collapsing to a filament over the 14t.
    fx.beam_emitter(
        "main_beam", end=(0.0, 90.0, 0.0), duration=14, looping=False,
        width=curve(0.25, 1.4, [SEG_LINEAR_DOWN], "duration"),
        raycast="NONE",
        color_nf=gradient(
            [(0.0, 1.0), (0.5, 0.85), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (0.45, 0.85, 0.7, 1.0), (1.0, 0.55, 0.25, 1.0)])
    ).with_material(texture_material(TEX_LASER, hdr=(2.5, 2.2, 3.0),
                                     blend=BLEND_ADDITIVE))
    # The corona sheath — wide, faint, gone in 6t.
    fx.beam_emitter(
        "halo", end=(0.0, 90.0, 0.0), duration=6, looping=False,
        width=constant(3.0), raycast="NONE",
        color_nf=gradient(
            [(0.0, 0.15), (1.0, 0.0)],
            [(0.0, 0.9, 0.8, 1.0), (1.0, 0.65, 0.45, 1.0)])
    ).with_material(texture_material(TEX_LASER, hdr=(1.6, 1.5, 2.0),
                                     blend=BLEND_ADDITIVE))
    # Spray where the beam meets the water.
    (fx.particle_emitter(
            "sea_splash",
            duration=20, looping=False, start_delay=constant(0),
            start_lifetime=random_between(12, 20), start_speed=random_between(0.5, 0.9),
            start_size=nf3(random_between(0.1, 0.2), random_between(0.1, 0.2),
                           random_between(0.1, 0.2)),
            simulation_space="World", max_particles=24)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(16))])
       .with_shape(cone(angle=40.0, radius=0.4, thickness=0.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.4, 1.4, 1.8),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_physics(collision=False, gravity=0.4)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.9), (0.6, 0.55), (1.0, 0.0)],
            [(0.0, 0.9, 0.95, 1.0), (1.0, 0.55, 0.55, 0.9)]))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# §6 eclipse:credits_confetti_burst — DOOMSDAY mesh-shard confetti (t=650)
# ---------------------------------------------------------------------------
# Mirrors CreditsSequence.FLYER_PALETTE ("the run's greatest hits" made literal).
CONFETTI_MODELS = (
    "block/dark_oak_planks",
    "block/polished_blackstone_bricks",
    "block/smooth_basalt",
    "block/obsidian",
    "block/amethyst_block",
)


def build_credits_confetti_burst() -> FxBuilder:
    """Timing discipline (the comedy depends on it): the glint emitter's 8t life from the
    t=650 spawn dies at 658 — every additive/HDR element is gone before the flash dies at
    t=666; only shade-lit shards fall through the correction stillness."""
    fx = FxBuilder("credits_confetti_burst")
    pivot = fx.empty("overhead").at(0.0, 7.0, 0.0)
    for i, model in enumerate(CONFETTI_MODELS):
        (fx.particle_emitter(
                f"shards_{model.rsplit('/', 1)[1]}",
                duration=12, looping=False, start_delay=constant(0),
                start_lifetime=random_between(40, 70),
                start_speed=random_between(0.8, 1.6),
                start_size=nf3(random_between(0.12, 0.28), random_between(0.12, 0.28),
                               random_between(0.12, 0.28)),
                start_rotation=nf3(random_between(0.0, 360.0), random_between(0.0, 360.0),
                                   random_between(0.0, 360.0)),
                simulation_space="World", max_particles=16, parallel_rendering=True)
           .child_of(pivot)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(12))])
           .with_shape(mesh(model=model, emit_from="Triangle"))
           .with_material(block_atlas_material(blend=BLEND_ALPHA))
           .with_renderer(render_mode="Model", use_block_uv=True, shade=True,
                          vertex_sorting="DISTANCE")
           .with_cull_box((-30.0, -20.0, -30.0), (30.0, 12.0, 30.0))
           .with_physics(collision=False, gravity=0.35)
           .with_curves(
                rotation_over_lifetime=dict(roll=random_between(12.0, 30.0),
                                            yaw=random_between(12.0, 30.0)),
                size_over_lifetime=nf3(*[curve(0.0, 1.0, [SEG_HOLD_SHRINK],
                                               "lifetime", "size") for _ in range(3)])))
    # The flash sparkling off the shards — MUST be dead by t=666 (8t life => 658).
    (fx.particle_emitter(
            "glint",
            duration=8, looping=False, start_delay=constant(0),
            start_lifetime=constant(8), start_speed=random_between(0.2, 0.5),
            start_size=nf3(random_between(0.08, 0.14), random_between(0.08, 0.14),
                           random_between(0.08, 0.14)),
            simulation_space="World", max_particles=24)
       .child_of(pivot)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(20))])
       .with_shape(sphere(radius=2.5, thickness=0.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(2.0, 2.0, 2.4),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.7, 0.6), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (1.0, 0.85, 0.8, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# §3 eclipse:structure_slam_mushroom (+ eclipse:slam_dust_puff)
# ---------------------------------------------------------------------------
def build_structure_slam_mushroom() -> FxBuilder:
    """Authored at unit footprint — the CUE_STRUCTURE_SLAM tuner applies executor
    setScale(footprint·0.05). The vertical mushroom the flat dust rings can't do; the
    clods use real collision physics + a Collision sub-emitter (slam_dust_puff)."""
    fx = FxBuilder("structure_slam_mushroom")
    # Decelerating dust column that blooms into the cap as it slows.
    (fx.particle_emitter(
            "column",
            duration=16, looping=False, start_delay=constant(0),
            start_lifetime=random_between(30, 45), start_speed=constant(0.05),
            start_size=nf3(random_between(0.5, 0.9), random_between(0.5, 0.9),
                           random_between(0.5, 0.9)),
            simulation_space="World", max_particles=64)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(40))])
       .with_shape(circle(radius=0.15, thickness=1.0))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           curve(0.0, 1.6, [SEG_LINEAR_DOWN], "lifetime"),
                           constant(0))),
            size_over_lifetime=nf3(*[curve(1.0, 3.0, [SEG_LINEAR_UP], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.85), (0.5, 0.6), (1.0, 0.0)],
                [(0.0, 0.45, 0.33, 0.22), (0.5, 0.62, 0.55, 0.45),
                 (1.0, 0.75, 0.7, 0.62)])))
    # The roiling mushroom head, 8t behind the column.
    (fx.particle_emitter(
            "cap_roll",
            duration=16, looping=False, start_delay=constant(8),
            start_lifetime=random_between(30, 42), start_speed=random_between(0.15, 0.3),
            start_size=nf3(random_between(0.8, 1.2), random_between(0.8, 1.2),
                           random_between(0.8, 1.2)),
            simulation_space="World", max_particles=32)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(24))])
       .with_shape(sphere(radius=0.5, thickness=0.3, arc=180.0))
       .at(0.0, 3.2, 0.0)
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            noise=dict(frequency=0.6, position=nf3(0.08)),
            size_over_lifetime=nf3(*[curve(1.0, 2.0, [SEG_LINEAR_UP], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.7), (1.0, 0.0)],
                [(0.0, 0.5, 0.4, 0.3), (1.0, 0.7, 0.66, 0.58)])))
    # Real dirt-textured shards; every impact has a 50% chance of a secondary puff.
    (fx.particle_emitter(
            "clods",
            duration=16, looping=False, start_delay=constant(0),
            start_lifetime=random_between(30, 50), start_speed=random_between(0.6, 1.2),
            start_size=nf3(random_between(0.15, 0.3), random_between(0.15, 0.3),
                           random_between(0.15, 0.3)),
            start_rotation=nf3(random_between(0.0, 360.0), random_between(0.0, 360.0),
                               random_between(0.0, 360.0)),
            simulation_space="World", max_particles=16)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14))])
       .with_shape(mesh(model="block/dirt", emit_from="Triangle"))
       .with_material(block_atlas_material(blend=BLEND_ALPHA))
       .with_renderer(render_mode="Model", use_block_uv=True, shade=True,
                      vertex_sorting="DISTANCE")
       .with_physics(collision=True, removed_when_collided=False, gravity=0.6,
                     bounce_chance=0.5, bounce_rate=0.3, collided_friction=0.6)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           curve(0.0, 1.2, [SEG_LINEAR_DOWN], "lifetime"),
                           constant(0))),
            rotation_over_lifetime=dict(roll=random_between(8.0, 20.0),
                                        yaw=random_between(8.0, 20.0)))
       .with_sub_emitters(sub_emitter("eclipse:slam_dust_puff", event="Collision",
                                      probability=0.5, inherit=("Color",))))
    return fx


def build_slam_dust_puff() -> FxBuilder:
    """Deliberately minimal: every clod collision instantiates a full FXRuntime copy of
    this file (FX_FORMAT.md §9) — 5 ground-hugging billboards, 12t, one emitter."""
    fx = FxBuilder("slam_dust_puff")
    (fx.particle_emitter(
            "puff",
            duration=12, looping=False, start_delay=constant(0),
            start_lifetime=random_between(10, 14), start_speed=random_between(0.05, 0.15),
            start_size=nf3(random_between(0.35, 0.55), random_between(0.35, 0.55),
                           random_between(0.35, 0.55)),
            simulation_space="World", max_particles=8)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(5))])
       .with_shape(circle(radius=0.2, thickness=1.0))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.35), (1.0, 0.0)],
            [(0.0, 0.55, 0.45, 0.35), (1.0, 0.7, 0.65, 0.55)])))
    return fx


# ---------------------------------------------------------------------------
# §5a eclipse:portal_iris_open_{xbox,backrooms} — the open moment
# ---------------------------------------------------------------------------
def _build_portal_iris(name: str, iris_hdr, iris_rgb, spark_rgb) -> FxBuilder:
    fx = FxBuilder(name)
    # Camera-facing iris ring snapping open exactly when the tear does (overshoot pop).
    (fx.particle_emitter(
            "iris",
            duration=18, looping=False, start_delay=constant(0),
            start_lifetime=constant(18), start_speed=constant(0.0),
            start_size=nf3(1.0), simulation_space="Local", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(TEX_RING, hdr=iris_hdr, blend=BLEND_ADDITIVE))
       .with_renderer(facing_mode="LOOKAT_XYZ", vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.2, PORTAL_WIDTH * 1.3, [SEG_IRIS_POP],
                                           "lifetime", "size") for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.55, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (0.5, *iris_rgb), (1.0, *iris_rgb)])))
    # Rim flash: 24 sparks off a thin shell (orientation-free — the tear plane is
    # camera-dependent at open time).
    (fx.particle_emitter(
            "rim_flash",
            duration=12, looping=False, start_delay=constant(0),
            start_lifetime=random_between(8, 12), start_speed=random_between(0.3, 0.5),
            start_size=nf3(random_between(0.08, 0.16), random_between(0.08, 0.16),
                           random_between(0.08, 0.16)),
            simulation_space="World", max_particles=32)
       .with_emission(rate=constant(0.0), bursts=[burst(time=1, count=constant(24))])
       .with_shape(sphere(radius=PORTAL_WIDTH / 2.0, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.5, 1.4, 1.8),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.6, 0.6), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (1.0, *spark_rgb)]))
       .with_lights(sky=15, block=15))
    return fx


def build_portal_iris_open_xbox() -> FxBuilder:
    return _build_portal_iris("portal_iris_open_xbox",
                              iris_hdr=(2.0, 1.8, 2.6),
                              iris_rgb=(0.62, 0.3, 0.98),
                              spark_rgb=(0.62, 0.3, 0.98))


def build_portal_iris_open_backrooms() -> FxBuilder:
    return _build_portal_iris("portal_iris_open_backrooms",
                              iris_hdr=(2.6, 2.3, 1.4),
                              iris_rgb=(0.98, 0.74, 0.3),
                              spark_rgb=(0.98, 0.74, 0.3))


# ---------------------------------------------------------------------------
# §5b eclipse:portal_loop_xbox — era-pixel presence loop (identity loop)
# ---------------------------------------------------------------------------
def build_portal_loop_xbox() -> FxBuilder:
    """Portal-scoped identity loop (destroyed by RiftFx via closeRift — windowed per
    INTEGRATION.md §4). Era style law (xbox_era.fsh v2): CRT-ADJACENT, deliberately NO
    scanlines — flicker is luminance only."""
    fx = FxBuilder("portal_loop_xbox")
    # Chunky 8-bit motes emitted off real block-model geometry, sucked into the star.
    (fx.particle_emitter(
            "era_pixels",
            duration=40, looping=True, prewarm=20, start_delay=constant(0),
            start_lifetime=random_between(30, 50), start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(0.08, 0.16), random_between(0.08, 0.16),
                           random_between(0.08, 0.16)),
            simulation_space="Local", max_particles=96)
       .with_emission(rate=constant(0.6), bursts=[])
       .with_shape(mesh(model="block/grass_block", emit_from="Vertex"),
                   scale=nf3(2.4, 2.4, 2.4))
       .with_material(texture_material(TEX_CIRCLE, pixel_art=True, pixel_art_bits=8,
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-8.0, -4.0, -8.0), (8.0, 6.0, 8.0))
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.5), constant(0)),
                radial=constant(-0.05)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.8), (0.85, 0.6), (1.0, 0.0)],
                [(0.0, 0.62, 0.3, 0.98), (1.0, 0.4, 0.2, 0.7)])))
    # One CRT screen-glow quad behind the star; irregular luminance flicker (two authored
    # flicker tracks, re-rolled per cycle particle — never a stable pulse), NO scanlines.
    (fx.particle_emitter(
            "crt_flicker",
            duration=40, looping=True, prewarm=20, start_delay=constant(0),
            start_lifetime=constant(40), start_speed=constant(0.0),
            start_size=nf3(2.2, 2.2, 2.2), simulation_space="Local", max_particles=3)
       .with_emission(rate=constant(0.025), bursts=[])
       .with_shape(dot())
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.3, 1.1, 1.6),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(facing_mode="LOOKAT_XYZ", vertex_sorting="NONE")
       .with_cull_box((-4.0, -3.0, -4.0), (4.0, 4.0, 4.0))
       .with_curves(color_over_lifetime=random_gradient(
            [(0.0, 0.28), (0.12, 0.1), (0.25, 0.34), (0.4, 0.14), (0.55, 0.3),
             (0.7, 0.08), (0.85, 0.26), (1.0, 0.18)],
            [(0.0, 0.62, 0.3, 0.98), (1.0, 0.5, 0.25, 0.85)],
            [(0.0, 0.15), (0.1, 0.32), (0.3, 0.08), (0.45, 0.3), (0.6, 0.12),
             (0.8, 0.34), (1.0, 0.1)],
            [(0.0, 0.55, 0.28, 0.9), (1.0, 0.62, 0.3, 0.98)])))
    return fx


# ---------------------------------------------------------------------------
# §5c eclipse:portal_loop_backrooms — fluorescent flicker + yellow haze loop
# ---------------------------------------------------------------------------
def build_portal_loop_backrooms() -> FxBuilder:
    """100t cycle matches the portal's hum cadence. Dying-fluorescent stutter: two
    authored alpha tracks with long dark gaps + double-blink clusters, re-rolled per
    cycle; blinks kiss the bloom threshold (small hdr)."""
    fx = FxBuilder("portal_loop_backrooms")
    # The tube: one horizontal thin billboard above the tear.
    (fx.particle_emitter(
            "tube_flicker",
            duration=100, looping=True, prewarm=50, start_delay=constant(0),
            start_lifetime=constant(100), start_speed=constant(0.0),
            start_size=nf3(2.4, 0.3, 1.0), simulation_space="Local", max_particles=3)
       .at(0.0, 2.2, 0.0)
       .with_emission(rate=constant(0.01), bursts=[])
       .with_shape(dot())
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.4, 1.35, 1.0),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-4.0, -3.0, -4.0), (4.0, 3.0, 4.0))
       .with_curves(color_over_lifetime=random_gradient(
            [(0.0, 0.0), (0.05, 0.7), (0.1, 0.05), (0.18, 0.75), (0.25, 0.1),
             (0.5, 0.65), (0.75, 0.0), (0.85, 0.6), (1.0, 0.0)],
            [(0.0, 1.0, 0.95, 0.8), (1.0, 1.0, 0.9, 0.7)],
            [(0.0, 0.6), (0.2, 0.0), (0.4, 0.7), (0.45, 0.1), (0.5, 0.75),
             (0.8, 0.05), (1.0, 0.5)],
            [(0.0, 1.0, 0.95, 0.8), (1.0, 0.95, 0.85, 0.6)])))
    # The yellow soup leaking out: big soft near-still smoke, alpha <= 0.15.
    (fx.particle_emitter(
            "haze",
            duration=100, looping=True, prewarm=60, start_delay=constant(0),
            start_lifetime=random_between(80, 120), start_speed=random_between(0.01, 0.04),
            start_size=nf3(random_between(1.2, 2.0), random_between(1.2, 2.0),
                           random_between(1.2, 2.0)),
            simulation_space="Local", max_particles=48)
       .with_emission(rate=constant(0.3), bursts=[])
       .with_shape(sphere(radius=1.5, thickness=0.6))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-8.0, -3.0, -8.0), (8.0, 6.0, 8.0))
       .with_curves(
            noise=dict(frequency=0.5, position=nf3(0.04)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.15), (0.8, 0.1), (1.0, 0.0)],
                [(0.0, 0.91, 0.85, 0.63), (1.0, 0.8, 0.7, 0.45)]),
            size_over_lifetime=nf3(*[curve(1.0, 1.6, [SEG_LINEAR_UP], "lifetime", "size")
                                     for _ in range(3)])))
    # Grim little garnish: 4-6 dark specks orbiting the tube erratically.
    (fx.particle_emitter(
            "moth_motes",
            duration=100, looping=True, prewarm=50, start_delay=constant(0),
            start_lifetime=random_between(80, 110), start_speed=random_between(0.03, 0.08),
            start_size=nf3(random_between(0.05, 0.08), random_between(0.05, 0.08),
                           random_between(0.05, 0.08)),
            start_color=0xFF221A10, simulation_space="Local", max_particles=8)
       .at(0.0, 2.0, 0.0)
       .with_emission(rate=constant(0.05), bursts=[])
       .with_shape(sphere(radius=0.8, thickness=0.5))
       .with_material(texture_material(TEX_CIRCLE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-3.0, -2.0, -3.0), (3.0, 3.0, 3.0))
       .with_curves(
            noise=dict(frequency=1.2, position=nf3(0.15)),
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.6), constant(0)))))
    return fx


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
BUILDERS = {
    "intro_burst_ring.fx": build_intro_burst_ring,
    "credits_strike_beam.fx": build_credits_strike_beam,
    "credits_confetti_burst.fx": build_credits_confetti_burst,
    "structure_slam_mushroom.fx": build_structure_slam_mushroom,
    "slam_dust_puff.fx": build_slam_dust_puff,
    "portal_iris_open_xbox.fx": build_portal_iris_open_xbox,
    "portal_iris_open_backrooms.fx": build_portal_iris_open_backrooms,
    "portal_loop_xbox.fx": build_portal_loop_xbox,
    "portal_loop_backrooms.fx": build_portal_loop_backrooms,
}


def main() -> int:
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        raw_len, gz_len = builder_fn().write(path)  # write() round-trip-validates
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} "
                  f"(raw {raw_len} B, gzip {gz_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
