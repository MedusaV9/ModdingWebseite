#!/usr/bin/env python3
"""fx_altar — PH-ALTAR's Photon `.fx` assets, authored programmatically via fxlib.

Generates (into `src/main/resources/assets/eclipse/fx/`, id = `eclipse:<name>`):

- `altar_levelup`        — IDEAS-world.md #1 "Sanctum Ring 2.0": HDR bloom shock ring +
                           amethyst mesh-shard Triangle emission + spark ribbons + sky
                           spear. One-shot; consumed by the SHIPPED
                           `PhotonBridge.enhanceQuasarCue(ALTAR_LEVELUP_RING)` seam.
- `altar_corona_idle`    — IDEAS-world.md #9: three lazy gold-violet ara corona ribbons
                           + ring-body glitter. LOOP (WINDOWED-only law, INTEGRATION.md
                           §4); driven by `client/drama/AltarCoronaIdle` via the
                           `FxCues.CUE_ALTAR_CORONA_IDLE` registry row.
- `offering_swallow_soul`— IDEAS-mobs.md #2: converging soul-ribbon spiral inhaled by
                           the altar + HDR comet tip. One-shot (32 t =
                           `OfferingSwallowFx.FLIGHT_TICKS`); spawned client-locally
                           from `OfferingSwallowFx.beginFlight` with allowMulti=true.

Every write round-trip-validates (fxlib law). Re-run after editing:
    python3 tools/photon/fx_altar.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, F, FX_ASSETS_DIR, REPO_ROOT, AraTrailEmitter, FxBuilder, TrailEmitter,
    BLEND_ADDITIVE, blend, block_atlas_material, burst, circle, cone, constant, curve,
    function_shape, gradient, mesh, nf3, random_between, sphere, texture_material,
    validate_file,
)

CIRCLE_TEX = "photon:textures/particle/circle.png"


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
    (fx.particle_emitter(
            "ring_shock",
            duration=30, looping=False,
            start_lifetime=random_between(14, 20),
            start_speed=constant(2.4),                   # radial from the circle shell
            start_size=nf3(random_between(0.22, 0.4)),
            simulation_space="World", max_particles=64)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(44), cycles=1, interval=1,
                                    probability=1.0)])
       .with_shape(circle(radius=1.5, thickness=0.0, arc=360.0,
                          arc_mode="BurstSpread"))       # even spacing, no clumping
       .with_material(texture_material(CIRCLE_TEX, discard=0.05,
                                       hdr=(1.45, 1.1, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-10.0, -1.0, -10.0), (10.0, 6.0, 10.0))
       .with_curves(
            # #E7C9FF -> #E7C9FF -> violet #7B3FD9, alpha 0.7 -> 0.6 -> 0
            color_over_lifetime=gradient(
                [(0.0, 0.7), (0.5, 0.6), (1.0, 0.0)],
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
       .with_shape(cone(angle=18.0, radius=0.4))         # pointed +Y (fountain cone)
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
                width=curve(0.0, 0.12,
                            [(0.0, 1.0, 0.33, 0.66, 0.66, 0.33, 1.0, 0.0)]),
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
# ---------------------------------------------------------------------------
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

    # --- corona_dust: <=30 glitter motes filling the ring body ---------------
    (fx.particle_emitter(
            "corona_dust",
            duration=100, looping=True, prewarm=40,
            start_lifetime=random_between(30, 50),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.03, 0.07)),
            simulation_space="Local", max_particles=30)
       .with_emission(rate=constant(0.4))
       .with_shape(sphere(radius=2.4, thickness=0.6))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(0.8, 0.7, 0.5),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-5.0, -1.0, -5.0), (5.0, 6.0, 5.0))
       .with_curves(
            noise=dict(frequency=0.6, quality="Noise2D",
                       position=nf3(constant(0.03), constant(0.02), constant(0.03)),
                       rotation=constant(0), size=constant(0)),
            color_over_lifetime=gradient(                # gold-violet in-hold-out
                [(0.0, 0.0), (0.25, 0.6), (0.75, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 0.9, 0.65), (1.0, 0.7, 0.5, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:offering_swallow_soul — IDEAS-mobs.md #2 (one-shot, 32 t flight)
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
    "offering_swallow_soul.fx": build_offering_swallow_soul,
}


def main() -> int:
    rc = 0
    for name, builder_fn in ASSETS.items():
        path = FX_ASSETS_DIR / name
        raw_len, gz_len = builder_fn().write(path)       # write() round-trip-validates
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
