#!/usr/bin/env python3
"""fx_altar — PH-ALTAR's Photon `.fx` assets, authored programmatically via fxlib.

Generates (into `src/main/resources/assets/eclipse/fx/`, id = `eclipse:<name>`):

- `altar_levelup`        — IDEAS-world.md #1 "Sanctum Ring 2.0": HDR bloom shock ring +
                           amethyst mesh-shard Triangle emission + spark ribbons + sky
                           spear. One-shot; consumed by the SHIPPED
                           `PhotonBridge.enhanceQuasarCue(ALTAR_LEVELUP_RING)` seam.
- `altar_corona_idle`    — IDEAS-world.md #9 + FX-Wave-13 A7 monument emission: three
                           lazy gold-violet ara corona ribbons + MONUMENT-SILHOUETTE
                           glints — the GeckoLib rune rings and the floating core shed
                           light from their own geometry (see MONUMENT GEOMETRY below)
                           instead of one abstract glitter sphere, plus a fresnel_shell
                           force-field impostor breathing around the eclipse core (A0
                           custom shader). LOOP (WINDOWED-only law, INTEGRATION.md §4);
                           driven by `client/drama/AltarCoronaIdle` via the
                           `FxCues.CUE_ALTAR_CORONA_IDLE` registry row.
- `altar_stageup_shockwave` — FX-Wave-13 A7 #4: monument-origin shock crest + ring-whip
                           sparks start-delay-synced to the GeckoLib `stage_up` one-shot
                           (2.5 s; see STAGE-UP TIMELINE below). One-shot; dispatched at
                           ceremony t=0 by `client/drama/AltarCeremonyFx` through
                           `AltarAura2FxRows.CUE_ALTAR_STAGEUP_SHOCKWAVE`.
- `offering_swallow_soul`— IDEAS-mobs.md #2: converging soul-ribbon spiral inhaled by
                           the altar + HDR comet tip. One-shot (32 t =
                           `OfferingSwallowFx.FLIGHT_TICKS`); spawned client-locally
                           from `OfferingSwallowFx.beginFlight` with allowMulti=true.

MONUMENT GEOMETRY (verified against `assets/eclipse/geo/block/altar.geo.json` +
`animations/block/altar.animation.json`; GeoBlockRenderer draws 1:1, 16 px = 1 block,
geo root at the block-cell floor = the ALTAR_CENTER anchor):

    bone     square half-extent  corner dist  centre y  static tilt  idle spin (12 s loop)
    ring_a   0.6875 b            0.972 b      1.250 b   —            +360°/12 s = +0.5236 rad/s
    ring_b   0.9375 b            1.326 b      1.594 b   12° about X  −360°/12 s = −0.5236 rad/s
    ring_c   0.5000 b            0.707 b      1.906 b   −8° about Z  +360°/12 s (+0.05 b y-bob)
    core     0.25 b cube (corner 0.433 b)     1.625 b   45° yaw      core_pivot +360°/12 s,
                                                                     glow_core −720°/12 s

Photon 2.1.5's `mesh` shape samples BAKED models only (`MeshData.loadFromQuads(List
<BakedQuad>)`, jar-verified) — the GeckoLib geo is not a baked model and the baked
`eclipse:block/altar` is a plain unit cube, so the monument is rebuilt here as thin
circle/sphere annuli at the exact radii/heights/tilts above, with orbital velocities
matching the GeckoLib spin directions (a point on a tilted ring yaw-spun about Y stays
at constant height — a horizontal-orbit particle born on the tilted circle IS the
exact swept path).

STAGE-UP TIMELINE (`animation.altar.stage_up`, 2.5 s = 50 t; the server triggers the
GeckoLib anim and sends FX_ALTAR_LEVELUP in the SAME tick, so ceremony t=0 ≈ anim t=0):
ring_a pop peaks 0.5 s (10 t), ring_b 0.6 s (12 t), ring_c 0.7 s (14 t); glow_core
flash peaks ~0.4 s (8 t) and ~1.3 s (26 t); rings whip a full ±360° lap over the
2.5 s (±2.513 rad/s, ring_c keeps its idle spin — no stage_up rotation channel).

Every write round-trip-validates (fxlib law). Re-run after editing:
    python3 tools/photon/fx_altar.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, F, FX_ASSETS_DIR, REPO_ROOT, AraTrailEmitter, FxBuilder, TrailEmitter,
    BLEND_ADDITIVE, BLEND_ALPHA, SEG_DECAY_TAIL, blend, block_atlas_material, burst,
    circle, cone, constant, curve, dot, function_shape, gradient, material_shader,
    mesh, nf3, random_between, sphere, texture_material, validate_file,
)

CIRCLE_TEX = "photon:textures/particle/circle.png"

# House palette as float RGB (FX-STYLE-GUIDE §1.1 SACRED).
DEEP = (0.431, 0.302, 0.659)     # 6E4DA8
VIOLET = (0.725, 0.549, 1.0)     # B98CFF
CORE_RGB = (0.906, 0.839, 1.0)   # E7D6FF
GOLD = (1.0, 0.914, 0.69)        # FFE9B0

# --- Monument silhouette constants (geo/anim law in the module docstring) -----------
# Idle ring spin: 360° / 12 s (orbital velocity module takes rad/s).
IDLE_SPIN = 0.5236
# Stage-up ring whip: 360° / 2.5 s.
STAGEUP_SPIN = 2.513
# Ring annuli: outer radius = corner distance (+ glint half-size), radiusThickness
# trims the band down to the mid-edge distance, so births cover exactly the swept
# square-frame footprint.
RING_A = dict(radius=1.00, thickness=0.35, y=1.250, tilt=(0.0, 0.0, 0.0), spin=+IDLE_SPIN)
RING_B = dict(radius=1.33, thickness=0.32, y=1.594, tilt=(12.0, 0.0, 0.0), spin=-IDLE_SPIN)
RING_C = dict(radius=0.71, thickness=0.34, y=1.906, tilt=(0.0, 0.0, -8.0), spin=+IDLE_SPIN)
CORE_Y = 1.625
# The spinning 0.25 b-half cube (45° yaw + twin counter-spins) sweeps a shell between
# its face distance (0.25) and corner distance (0.433).
CORE_SHELL = dict(radius=0.44, thickness=0.42)
# AltarCoronaIdle anchors the corona loop at ALTAR_CENTER + this crown height — the
# monument offsets below subtract it (monument y − CROWN_ABOVE_ANCHOR).
CROWN_ABOVE_ANCHOR = 3.2
# AltarBlockEntity.completeMilestone's FX_ALTAR_LEVELUP pos = block centre + 0.7
# = monument base + 1.2 (the stage-up asset is authored relative to THAT anchor).
LEVELUP_ANCHOR_Y = 1.2
# Rising eased 0→1 (hold low, commit late) — the mirror of SEG_DECAY_TAIL, for
# negative-range orbital decay curves (lower = fast end of the whip).
SEG_RISE_LATE = (0.0, 0.0, 0.35, 0.1, 0.7, 0.75, 1.0, 1.0)


def embedded_trail_config(material_entry, **kwargs):
    """Full TrailConfig compound for the particle `trails` module's embedded `config`
    (same class as the standalone trail_emitter config, FX_FORMAT.md §4.2)."""
    t = TrailEmitter("_embedded", **kwargs)
    t.with_material(material_entry)
    return t.build()["data"]["config"]


def embedded_ara_config(material_entry, **kwargs):
    """Full AraTrailConfig compound for the `trails` module's embedded `araConfig`
    (same class as the standalone ara_trail_emitter config, FX_FORMAT.md §4.3)."""
    a = AraTrailEmitter("_embedded", **kwargs)
    a.with_material(material_entry)
    return a.build()["data"]["config"]


# ---------------------------------------------------------------------------
# 1. eclipse:altar_levelup — IDEAS-world.md §1 (exact spec numbers)
# ---------------------------------------------------------------------------
def build_altar_levelup() -> FxBuilder:
    fx = FxBuilder("altar_levelup")
    root = fx.empty("altar_levelup_root")  # identity transform: shared origin

    # --- ring_shock: the HDR bloom shock ring -------------------------------
    # FX-Wave-11 stacking-law pass: 96 additive sparks born on one 0.6 r shell at
    # hdr 3.2 with a pure-white birth stop bloomed into a supernova at the altar.
    # Count 96->44 (cap 160->64) spread over a 1.5 r shell, hdr nerfed to ~1.45, the
    # birth stop starts at #E7C9FF instead of white and the alpha crest at 0.7.
    # FX-Wave-11.1: 44 sparks x ~0.3 b covered ~13 b of a 9.4 b circumference —
    # still >1 layer of overlap at birth, so the base of the sky spear kept flashing
    # into a pink ball. 36 sparks on a 2.4 r shell (15 b circumference), crest 0.55.
    (fx.particle_emitter(
            "ring_shock",
            duration=30, looping=False,
            start_lifetime=random_between(14, 20),
            start_speed=constant(2.4),                   # radial from the circle shell
            start_size=nf3(random_between(0.22, 0.4)),
            simulation_space="World", max_particles=64)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(36), cycles=1, interval=1,
                                    probability=1.0)])
       .with_shape(circle(radius=2.4, thickness=0.0, arc=360.0,
                          arc_mode="BurstSpread"))       # even spacing, no clumping
       .with_material(texture_material(CIRCLE_TEX, discard=0.05,
                                       hdr=(1.45, 1.1, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-10.0, -1.0, -10.0), (10.0, 6.0, 10.0))
       .with_curves(
            # #E7C9FF -> #E7C9FF -> violet #7B3FD9, alpha 0.55 -> 0.5 -> 0
            color_over_lifetime=gradient(
                [(0.0, 0.55), (0.5, 0.5), (1.0, 0.0)],
                [(0.0, 0.906, 0.788, 1.0), (0.5, 0.906, 0.788, 1.0),
                 (1.0, 0.482, 0.247, 0.851)]),
            # pop then dissolve: single-segment bezier [0,0.4 0.15,1 0.7,0.95 1,0]
            size_over_lifetime=nf3(
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size")))
       .with_lights(sky=15, block=15))

    # --- glyph_shards: amethyst mesh-model shards (the Photon-only hero) ----
    (fx.particle_emitter(
            "glyph_shards",
            duration=30, looping=False,
            start_lifetime=random_between(26, 44),
            start_speed=random_between(0.5, 1.1),
            start_size=nf3(random_between(0.18, 0.3)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="World", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=2, count=constant(26), cycles=1)])
       .with_shape(mesh("minecraft:block/amethyst_cluster", emit_from="Triangle"))
       .with_material(block_atlas_material(blend=blend(enable=False),
                                           depth_mask=True))
       # Opaque model pass reads crisper for solid shards (spec note).
       .with_renderer(render_mode="Model", use_block_uv=True, shade=True,
                      layer="Opaque", model_pivot=(0.0, 0.0, 0.0),
                      vertex_sorting="NONE")
       # Shards clatter onto the altar floor (real collision; parallelUpdate stays 0b).
       .with_physics(collision=True, removed_when_collided=False, friction=0.985,
                     collided_friction=0.55, gravity=0.18, bounce_chance=0.5,
                     bounce_rate=0.35, bounce_spread=0.0)
       .with_curves(rotation_over_lifetime=dict(roll=random_between(-9.0, 9.0),
                                                yaw=random_between(-6.0, 6.0)))
       .with_lights(sky=15, block=15))

    # --- spark_ribbons: 12 rising sparks dragging short TRAIL ribbons -------
    ribbon_mat = texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.6, 1.1, 2.2),
                                  blend=BLEND_ADDITIVE)
    (fx.particle_emitter(
            "spark_ribbons",
            duration=30, looping=False,
            start_lifetime=random_between(20, 30),
            start_speed=random_between(0.7, 1.2),
            start_size=nf3(0.09),
            simulation_space="World", max_particles=16)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=1, count=constant(12), cycles=1)])
       # FX-Wave-11.1: cone mouth 0.4 -> 1.2 r — 12 hdr-2.2 ribbon heads born inside
       # a 0.4 r disc were the last bright clump left at the spear base.
       .with_shape(cone(angle=18.0, radius=1.2))         # pointed +Y (fountain cone)
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.6, 1.1, 2.2),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_module("trails", {
            "ratio": F(1.0),
            "lifetime": constant(0.5),                   # fraction of particle lifetime
            "inheritParticleColor": B(1),
            "trailType": "TRAIL",
            "config": embedded_trail_config(
                ribbon_mat, time=8, min_vertex_distance=0.05,
                # v7 quality bar: eased die-off (the old chord-collinear taper was a
                # grandfathered LINT-LINEAR-CURVE — baseline entry retired with this).
                width=curve(0.0, 0.12, [SEG_DECAY_TAIL]),
                color_nf=gradient(                       # violet -> transparent
                    [(0.0, 0.9), (1.0, 0.0)],
                    [(0.0, 0.61, 0.42, 0.95), (1.0, 0.35, 0.2, 0.6)]))})
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (1.0, 0.62, 0.42, 1.0)]))
       .with_lights(sky=15, block=15))

    # --- sky_spear: 2 s vertical HDR lance ----------------------------------
    spear = (fx.beam_emitter(
            "sky_spear",
            duration=40, looping=False, end=(0.0, 48.0, 0.0),
            emit_rate=constant(0),                       # continuous
            raycast="NONE",
            color_nf=gradient(                           # white -> #B388FF
                [(0.0, 1.0), (0.6, 0.9), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, 0.702, 0.533, 1.0)]))
       .child_of(root)
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(2.0, 1.4, 2.8),
                                       blend=BLEND_ADDITIVE)))
    # BeamConfig.width is a NumberFunction (FX_FORMAT.md §4.1) but the fxlib ctor only
    # coerces scalars — set the animated curve directly: thick flash -> needle -> gone.
    spear._config["width"] = curve(0.0, 0.9, [(0.0, 1.0, 0.1, 1.0, 0.5, 0.35, 1.0, 0.0)])
    spear.with_lights(sky=15, block=15)
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:altar_corona_idle — IDEAS-world.md §9 (WINDOWED loop, L5-gated)
#    FX-Wave-13 A7: monument-silhouette emission (docstring geometry law)
# ---------------------------------------------------------------------------
def _rune_ring_glints(fx, name, ring, rate, max_particles, hdr, mid_rgb):
    """Glints born on one rune ring's swept annulus, orbiting WITH the GeckoLib spin.

    The annulus (radius/thickness) covers the square frame's mid-edge→corner sweep;
    the shape rotation applies the bone's static tilt; the orbital velocity matches
    the idle animation's ±360°/12 s yaw — the particles ride the ring instead of
    hovering in an abstract shell. GPU-instanced (permanent loop, no physics).
    """
    (fx.particle_emitter(
            name,
            duration=100, looping=True, prewarm=70,
            start_lifetime=random_between(45, 70),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.05, 0.1)),
            simulation_space="Local", max_particles=max_particles)
       .with_emission(rate=constant(rate))
       .with_shape(circle(radius=ring["radius"], thickness=ring["thickness"]),
                   position=nf3(0.0, ring["y"] - CROWN_ABOVE_ANCHOR, 0.0),
                   rotation=nf3(*ring["tilt"]))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=hdr,
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False,
                      use_gpu_instance=True)
       .with_cull_box((-5.0, -4.0, -5.0), (5.0, 6.0, 5.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), breathing_bob(-0.012, 0.012), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(ring["spin"]), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            # dark birth (law) -> tier colour -> deep fade; never a white pop
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.7), (0.75, 0.55), (1.0, 0.0)],
                [(0.0,) + DEEP, (0.5,) + mid_rgb, (1.0,) + VIOLET]),
            # twinkle: the glyph-orbit shrink-grow-shrink read
            size_over_lifetime=nf3(
                curve(0.55, 1.0, [(0.0, 0.6, 0.25, 1.0, 0.6, 1.0, 1.0, 0.55)],
                      "lifetime", "size"),
                curve(0.55, 1.0, [(0.0, 0.6, 0.25, 1.0, 0.6, 1.0, 1.0, 0.55)],
                      "lifetime", "size"),
                curve(0.55, 1.0, [(0.0, 0.6, 0.25, 1.0, 0.6, 1.0, 1.0, 0.55)],
                      "lifetime", "size")))
       .with_lights(sky=15, block=15))


# Sine-ish vertical breathing (fx_altar corona curve shape), mapped into [lo, hi].
def breathing_bob(lo, hi):
    return curve(lo, hi,
                 [(0.0, 0.5, 0.2, 1.0, 0.3, 1.0, 0.5, 0.5),
                  (0.5, 0.5, 0.7, 0.0, 0.8, 0.0, 1.0, 0.5)],
                 "lifetime", "value")


def build_altar_corona_idle() -> FxBuilder:
    fx = FxBuilder("altar_corona_idle")

    # Sine-ish vertical breathing: y 0.5 -> 1 -> 0.5 -> 0 -> 0.5 over the cycle,
    # mapped into [-0.02, 0.02] (0 at the midline).
    breathing = curve(-0.02, 0.02,
                      [(0.0, 0.5, 0.2, 1.0, 0.3, 1.0, 0.5, 0.5),
                       (0.5, 0.5, 0.7, 0.0, 0.8, 0.0, 1.0, 0.5)],
                      "lifetime", "value")

    ribbon_mat = texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.6, 1.3, 1.0),
                                  blend=BLEND_ADDITIVE)

    # --- corona_carriers: 3 eternal orbiters dragging ara ribbons ------------
    (fx.particle_emitter(
            "corona_carriers",
            duration=100, looping=True, prewarm=100,     # ring formed at window entry
            start_lifetime=constant(95),
            start_speed=constant(0.0),
            start_size=nf3(0.12),
            simulation_space="Local", max_particles=3)
       .with_emission(rate=constant(0.032))              # one new carrier as one dies
       .with_shape(circle(radius=2.6, thickness=0.0, arc_mode="Loop", arc_speed=0.33))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.6, 1.3, 1.0),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-5.0, -1.0, -5.0), (5.0, 6.0, 5.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), breathing, constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.6), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 1.0), (0.9, 1.0), (1.0, 0.0)],
                [(0.0, 1.0, 0.914, 0.69), (1.0, 1.0, 0.914, 0.69)]))
       .with_module("trails", {
            "ratio": F(1.0),
            "lifetime": constant(0.4),
            "inheritParticleColor": B(0),
            "trailType": "ARA_TRAIL",
            "araConfig": embedded_ara_config(
                ribbon_mat,
                space="World", alignment="View",
                thickness=0.16, smoothness=6,
                high_quality_corners=True, corner_roundness=8,
                time=1.6, time_interval=0.05,            # SECONDS (ara exception)
                # leaf-shaped ribbon: 0.6 -> 1 -> 0.1
                thickness_over_length=curve(
                    0.0, 1.0,
                    [(0.0, 0.6, 0.2, 1.0, 0.3, 1.0, 0.5, 1.0),
                     (0.5, 1.0, 0.7, 1.0, 0.9, 0.1, 1.0, 0.1)]),
                # #FFE9B0 -> #B47DFF -> transparent
                color_over_length=gradient(
                    [(0.0, 0.95), (0.6, 0.7), (1.0, 0.0)],
                    [(0.0, 1.0, 0.914, 0.69), (0.55, 0.706, 0.49, 1.0),
                     (1.0, 0.706, 0.49, 1.0)]),
                physics=dict(inertia=0.3, velocity_smoothing=0.8, damping=0.75))})
       .with_lights(sky=15, block=15))

    # --- FX-Wave-13 A7: the monument itself glows -----------------------------
    # The old `corona_dust` abstract glitter sphere (r 2.4 around the crown point,
    # nowhere near the actual model) is replaced by silhouette emission: glints born
    # ON the three rune-ring annuli riding the GeckoLib spins, the core shedding off
    # its own swept shell, and a fresnel_shell force-field impostor breathing around
    # the eclipse core. Anchor = ALTAR_CENTER + CROWN_ABOVE_ANCHOR (offsets negative).
    _rune_ring_glints(fx, "rune_ring_a_glints", RING_A, rate=0.21, max_particles=12,
                      hdr=(1.3, 1.05, 1.45), mid_rgb=CORE_RGB)
    # ring_b is the wide crown ring — it alone carries the gold mid-stop (≤35 % law).
    _rune_ring_glints(fx, "rune_ring_b_glints", RING_B, rate=0.25, max_particles=14,
                      hdr=(1.45, 1.25, 1.2), mid_rgb=GOLD)
    _rune_ring_glints(fx, "rune_ring_c_glints", RING_C, rate=0.15, max_particles=8,
                      hdr=(1.3, 1.05, 1.45), mid_rgb=CORE_RGB)

    # --- core_surface_motes: the eclipse core sheds off its own swept shell ---
    (fx.particle_emitter(
            "core_surface_motes",
            duration=100, looping=True, prewarm=60,
            start_lifetime=random_between(40, 60),
            start_speed=constant(0.06),                  # slow radial shed
            start_size=nf3(random_between(0.04, 0.08)),
            simulation_space="Local", max_particles=12)
       .with_emission(rate=constant(0.22))
       .with_shape(sphere(radius=CORE_SHELL["radius"],
                          thickness=CORE_SHELL["thickness"]),
                   position=nf3(0.0, CORE_Y - CROWN_ABOVE_ANCHOR, 0.0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.45, 1.2, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False,
                      use_gpu_instance=True)
       .with_cull_box((-5.0, -4.0, -5.0), (5.0, 6.0, 5.0))
       .with_curves(
            velocity_over_lifetime=dict(
                # co-rotate with core_pivot (+360°/12 s), bob with the idle float
                linear=nf3(constant(0), breathing_bob(-0.015, 0.015), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(IDLE_SPIN), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.75), (0.7, 0.5), (1.0, 0.0)],
                [(0.0,) + DEEP, (0.45,) + CORE_RGB, (1.0,) + VIOLET]))
       .with_lights(sky=15, block=15))

    # --- core_shell: ONE fresnel_shell force-field impostor around the core ---
    # A0 recipe 2.2: sphere impostor on a billboard quad — no mesh needed. RimHDR
    # capped at the 1.45 altar HDR law; heartbeat-style size breathing rides the
    # 12 s idle core pulse. BLEND_ALPHA + DISTANCE sorting (LINT-ALPHA-NOSORT law).
    (fx.particle_emitter(
            "core_shell",
            duration=100, looping=True, prewarm=100,
            start_lifetime=constant(95),
            start_speed=constant(0.0),
            start_size=nf3(1.0),
            simulation_space="Local", max_particles=1)
       .with_emission(rate=constant(0.032))              # one new shell as one dies
       .with_shape(dot(), position=nf3(0.0, CORE_Y - CROWN_ABOVE_ANCHOR, 0.0))
       .with_material(material_shader(
            "eclipse:fresnel_shell",
            uniforms={"ShellColor": (0.58, 0.42, 0.86, 0.5),
                      "RimHDRColor": (1.35, 1.05, 1.45, 1.0),
                      "FresnelPower": 2.8, "FaceAlpha": 0.05,
                      "IntersectWidth": 0.3},
            blend=BLEND_ALPHA, cull=True, depth_test=True, depth_mask=False))
       .with_renderer(render_mode="Billboard", vertex_sorting="DISTANCE", shade=False)
       .with_cull_box((-5.0, -4.0, -5.0), (5.0, 6.0, 5.0))
       .with_curves(
            # ±6 % breathing around the core's glow pulse; alpha in/out so the
            # windowed release never pops the shell
            size_over_lifetime=nf3(
                curve(0.88, 1.0,
                      [(0.0, 0.5, 0.2, 1.0, 0.3, 1.0, 0.5, 0.5),
                       (0.5, 0.5, 0.7, 0.0, 0.8, 0.0, 1.0, 0.5)],
                      "lifetime", "size"),
                curve(0.88, 1.0,
                      [(0.0, 0.5, 0.2, 1.0, 0.3, 1.0, 0.5, 0.5),
                       (0.5, 0.5, 0.7, 0.0, 0.8, 0.0, 1.0, 0.5)],
                      "lifetime", "size"),
                curve(0.88, 1.0,
                      [(0.0, 0.5, 0.2, 1.0, 0.3, 1.0, 0.5, 0.5),
                       (0.5, 0.5, 0.7, 0.0, 0.8, 0.0, 1.0, 0.5)],
                      "lifetime", "size")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.08, 1.0), (0.92, 1.0), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:altar_stageup_shockwave — FX-Wave-13 A7 #4 (one-shot, anim-synced)
#    The monument answers the GeckoLib `stage_up` one-shot: a crest leaves the
#    core on the first glow flash, then each rune ring is "dragged" by the whip
#    at ITS OWN pop keyframe. startDelay carries the sync (docstring timeline);
#    AltarCeremonyFx dispatches this at ceremony t=0 = anim t=0.
# ---------------------------------------------------------------------------
def _ring_whip(fx, name, ring, delay, count, whip, mid_rgb):
    """Whip glints born ON one rune ring's annulus at its stage-up pop keyframe.

    start_delay = the GeckoLib pop peak (ring_a 10 t / ring_b 12 t / ring_c 14 t);
    the orbital velocity launches at the ring's stage-up lap rate and the
    SEG_DECAY_TAIL speed envelope eases it back to rest — the shockwave grabs the
    ring, drags it, lets go. A slight outward radial rides the passing crest."""
    (fx.particle_emitter(
            name,
            duration=50, looping=False, start_delay=constant(delay),
            start_lifetime=random_between(24, 34),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.06, 0.11)),
            simulation_space="Local", max_particles=count + 2)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(count), cycles=1,
                                    interval=1, probability=1.0)])
       .with_shape(circle(radius=ring["radius"], thickness=ring["thickness"]),
                   position=nf3(0.0, ring["y"] - LEVELUP_ANCHOR_Y, 0.0),
                   rotation=nf3(*ring["tilt"]))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05,
                                       hdr=(1.3, 1.05, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-7.0, -2.0, -7.0), (7.0, 6.0, 7.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.03), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(whip), constant(0)),
                offset=nf3(0), radial=constant(0.12),
                # jar-verified: getVelocityMultiplier scales the SUMMED velocity
                # (linear + orbital + radial) — one envelope eases the whole whip.
                speed_modifier=curve(0.0, 1.0, [SEG_DECAY_TAIL])),
            # dark birth (law) -> tier colour -> deep fade; never a white pop
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.85), (0.6, 0.55), (1.0, 0.0)],
                [(0.0,) + DEEP, (0.4,) + mid_rgb, (1.0,) + VIOLET]),
            size_over_lifetime=nf3(
                curve(0.0, 1.0, [(0.0, 0.55, 0.1, 1.0, 0.6, 0.8, 1.0, 0.2)],
                      "lifetime", "size"),
                curve(0.0, 1.0, [(0.0, 0.55, 0.1, 1.0, 0.6, 0.8, 1.0, 0.2)],
                      "lifetime", "size"),
                curve(0.0, 1.0, [(0.0, 0.55, 0.1, 1.0, 0.6, 0.8, 1.0, 0.2)],
                      "lifetime", "size")))
       .with_lights(sky=15, block=15))


def build_altar_stageup_shockwave() -> FxBuilder:
    fx = FxBuilder("altar_stageup_shockwave")

    # --- core_shock: the crest leaves the core on glow flash #1 (t = 8) -------
    # Radial sweep 0.44 r -> ~4.5 b: it crosses ring_a (r 1.0) right as the ring's
    # own pop keyframe lands at t = 10 — the whips below read as "caught" by it.
    (fx.particle_emitter(
            "core_shock",
            duration=50, looping=False, start_delay=constant(8),
            start_lifetime=random_between(12, 16),
            start_speed=constant(5.5),                   # radial from the core shell
            start_size=nf3(random_between(0.16, 0.28)),
            simulation_space="World", max_particles=32)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(28), cycles=1, interval=1,
                                    probability=1.0)])
       .with_shape(circle(radius=CORE_SHELL["radius"], thickness=0.0, arc=360.0,
                          arc_mode="BurstSpread"),      # even spacing, no clumping
                   position=nf3(0.0, CORE_Y - LEVELUP_ANCHOR_Y, 0.0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05,
                                       hdr=(1.45, 1.1, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.2,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-7.0, -2.0, -7.0), (7.0, 6.0, 7.0))
       .with_curves(
            # pale-violet birth stop (stacking law: no white fusion at the shell)
            color_over_lifetime=gradient(
                [(0.0, 0.55), (0.5, 0.5), (1.0, 0.0)],
                [(0.0, 0.906, 0.788, 1.0), (0.5, 0.906, 0.788, 1.0),
                 (1.0, 0.482, 0.247, 0.851)]),
            size_over_lifetime=nf3(
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size")))
       .with_lights(sky=15, block=15))

    # --- ring whips: each ring dragged at ITS OWN GeckoLib pop keyframe -------
    # Whip rates/directions = the stage_up rotation channels: ring_a +360°/2.5 s,
    # ring_b −360°/2.5 s; ring_c has NO stage_up rotation channel — it keeps its
    # idle +360°/12 s, so its glints only shiver (small count, idle-rate drag).
    _ring_whip(fx, "ring_whip_a", RING_A, delay=10, count=14,
               whip=+STAGEUP_SPIN, mid_rgb=CORE_RGB)
    _ring_whip(fx, "ring_whip_b", RING_B, delay=12, count=16,
               whip=-STAGEUP_SPIN, mid_rgb=GOLD)
    _ring_whip(fx, "ring_whip_c", RING_C, delay=14, count=8,
               whip=+IDLE_SPIN, mid_rgb=CORE_RGB)

    # --- core_afterpulse: the gentler second glow flash (t = 26) --------------
    (fx.particle_emitter(
            "core_afterpulse",
            duration=50, looping=False, start_delay=constant(26),
            start_lifetime=random_between(10, 14),
            start_speed=constant(2.2),
            start_size=nf3(random_between(0.1, 0.18)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(10), cycles=1, interval=1,
                                    probability=1.0)])
       .with_shape(circle(radius=CORE_SHELL["radius"], thickness=0.0, arc=360.0,
                          arc_mode="BurstSpread"),
                   position=nf3(0.0, CORE_Y - LEVELUP_ANCHOR_Y, 0.0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05,
                                       hdr=(1.3, 1.0, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-7.0, -2.0, -7.0), (7.0, 6.0, 7.0))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.45), (0.5, 0.4), (1.0, 0.0)],
                [(0.0,) + DEEP, (0.4,) + CORE_RGB, (1.0,) + VIOLET]),
            size_over_lifetime=nf3(
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size")))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# 4. eclipse:offering_swallow_soul — IDEAS-mobs.md #2 (one-shot, 32 t flight)
# ---------------------------------------------------------------------------
# Shrinking inhale helix anchored at the altar (mirrors OfferingSwallowFx's flight
# spiral); speed expressions aim inward (0-… form: the expr parser has no unary minus).
HELIX_X = "(1-t)*2.4*cos(t*4*PI+randomA*6.28)"
HELIX_Y = "(1-t)*1.4"
HELIX_Z = "(1-t)*2.4*sin(t*4*PI+randomA*6.28)"
SPEED_X = "0-0.35*((1-t)*2.4*cos(t*4*PI+randomA*6.28))"
SPEED_Y = "0-0.35*((1-t)*1.4)"
SPEED_Z = "0-0.35*((1-t)*2.4*sin(t*4*PI+randomA*6.28))"


def build_offering_swallow_soul() -> FxBuilder:
    fx = FxBuilder("offering_swallow_soul")

    # Neutral (non-HDR) additive motes — the glow fan already tints per item; the
    # bloom read is reserved for the hdr_tip comet head.
    mote_ribbon_mat = texture_material(CIRCLE_TEX, discard=0.05, blend=BLEND_ADDITIVE)

    # --- soul_intake: helix motes dragging physically-lagging mini-ribbons ---
    (fx.particle_emitter(
            "soul_intake",
            duration=32, looping=False,                  # = OfferingSwallowFx.FLIGHT_TICKS
            start_lifetime=random_between(10, 14),
            start_speed=constant(1.0),
            start_size=nf3(random_between(0.05, 0.1)),
            simulation_space="World", max_particles=48)
       .with_emission(rate=constant(2.5))
       .with_shape(function_shape(x=HELIX_X, y=HELIX_Y, z=HELIX_Z,
                                  speed_x=SPEED_X, speed_y=SPEED_Y, speed_z=SPEED_Z))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 4.0, 4.0))
       .with_curves(color_over_lifetime=gradient(        # violet -> gold (house palette)
            [(0.0, 0.9), (0.7, 0.7), (1.0, 0.0)],
            [(0.0, 0.62, 0.42, 1.0), (1.0, 1.0, 0.85, 0.55)]))
       .with_module("trails", {
            "ratio": F(1.0),
            "lifetime": constant(0.6),
            "inheritParticleColor": B(1),
            "trailType": "ARA_TRAIL",
            "araConfig": embedded_ara_config(
                mote_ribbon_mat,
                space="World", alignment="View",
                thickness=0.06, smoothness=4,
                time=0.5, time_interval=0.05,            # short retention (budget note)
                thickness_over_length=curve(
                    0.0, 1.0, [(0.0, 1.0, 0.33, 0.66, 0.66, 0.33, 1.0, 0.1)]),
                physics=dict(inertia=0.4, velocity_smoothing=0.75, damping=0.6))})
       .with_lights(sky=15, block=15))

    # --- hdr_tip: 1-particle comet head re-emitted every 4 t on the helix ----
    (fx.particle_emitter(
            "hdr_tip",
            duration=32, looping=False,
            start_lifetime=constant(6),
            start_speed=constant(1.0),
            start_size=nf3(0.22),
            simulation_space="World", max_particles=4)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(1), cycles=8, interval=4,
                                    probability=1.0)])
       .with_shape(function_shape(x=HELIX_X, y=HELIX_Y, z=HELIX_Z,
                                  speed_x=SPEED_X, speed_y=SPEED_Y, speed_z=SPEED_Z))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(2.5, 1.8, 1.0),
                                       blend=BLEND_ADDITIVE))   # gold-hot bloom tip
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.4,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 4.0, 4.0))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (1.0, 0.0)],
            [(0.0, 1.0, 0.95, 0.8), (1.0, 1.0, 0.72, 0.35)]))
       .with_lights(sky=15, block=15))
    return fx


ASSETS = {
    "altar_levelup.fx": build_altar_levelup,
    "altar_corona_idle.fx": build_altar_corona_idle,
    "altar_stageup_shockwave.fx": build_altar_stageup_shockwave,
    "offering_swallow_soul.fx": build_offering_swallow_soul,
}


def main() -> int:
    rc = 0
    for name, builder_fn in ASSETS.items():
        path = FX_ASSETS_DIR / name
        builder = builder_fn()
        raw_len, gz_len = builder.write(path)            # write() round-trip-validates
        builder.write_fxproj(path.with_suffix(".fxproj"))  # binary-diff law sibling
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} "
                  f"(raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    sys.exit(main())
