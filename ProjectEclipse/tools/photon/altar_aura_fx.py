#!/usr/bin/env python3
"""altar_aura_fx — F-075 "Stufen-Aura der Altar-Insel": Photon `.fx` loop assets.

The permanent, altar-level-scaled aura around the sanctum island. All four assets are
LOOPS under the WINDOWED-only law (INTEGRATION.md §4): rows registered by
`veilfx/AltarAuraFxRows`, windows driven by `client/drama/AltarAuraIdle` (stage gates +
hysteresis bands off the `ALTAR_CENTER` anchor and `ClientStateCache.altarLevel`).

Generates (into `src/main/resources/assets/eclipse/fx/`, id = `eclipse:<name>`):

- `altar_aura_motes.fx`  — stage 1+ baseline, near-field (< 96): sparse violet motes
                           rising off the island floor + a thin drifting ground-fog
                           ring. The "something is sacred here" whisper.
- `altar_aura_glyphs.fx` — stage 2+, near-field: orbiting rune-spark band around the
                           altar crown + a slow re-emitted ground ring pulse.
- `altar_aura_pillar.fx` — stage 2+, FAR tell (< 200): one soft pulsing light column
                           over the altar + a few climbing motes. Deliberately the
                           cheapest asset — it is the horizon read.
- `altar_aura_bands.fx`  — stage 4+, near-field: two tilted counter-orbiting light
                           bands dragging ribbons + occasional tangential energy arcs.

House palette: violet #B98CFF / deep #6E4DA8 / core #E7D6FF, gold #FFE9B0.
Budgets: every asset stays ≤ ~70 live particles; one Photon executor each against
`PhotonBridge.MAX_LIVE_EXECUTORS` while its window is open.

Every write round-trip-validates (fxlib law). Re-run after editing:
    python3 tools/photon/altar_aura_fx.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, F, FX_ASSETS_DIR, REPO_ROOT, TrailEmitter, FxBuilder,
    BLEND_ADDITIVE, burst, circle, constant, curve, gradient, nf3,
    random_between, sphere, texture_material, validate_file,
)

CIRCLE_TEX = "photon:textures/particle/circle.png"


def embedded_trail_config(material_entry, **kwargs):
    """Full TrailConfig compound for the particle `trails` module's embedded `config`
    (same class as the standalone trail_emitter config, FX_FORMAT.md §4.2)."""
    t = TrailEmitter("_embedded", **kwargs)
    t.with_material(material_entry)
    return t.build()["data"]["config"]


# Sine-ish breathing helper: y 0.5 -> 1 -> 0.5 -> 0 -> 0.5 over the cycle,
# mapped into [lo, hi] (fx_altar's corona breathing curve shape).
def breathing(lo, hi):
    return curve(lo, hi,
                 [(0.0, 0.5, 0.2, 1.0, 0.3, 1.0, 0.5, 0.5),
                  (0.5, 0.5, 0.7, 0.0, 0.8, 0.0, 1.0, 0.5)],
                 "lifetime", "value")


# ---------------------------------------------------------------------------
# 1. eclipse:altar_aura_motes — stage 1+ near-field baseline
# ---------------------------------------------------------------------------
def build_altar_aura_motes() -> FxBuilder:
    fx = FxBuilder("altar_aura_motes")

    # --- rising motes: sparse, slow, whisper-quiet ---------------------------
    (fx.particle_emitter(
            "aura_motes",
            duration=100, looping=True, prewarm=60,
            start_lifetime=random_between(70, 110),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.04, 0.09)),
            simulation_space="Local", max_particles=36)
       .with_emission(rate=constant(0.35))
       # Wide ring hugging the island floor around the dais (anchor = altar center).
       .with_shape(circle(radius=5.2, thickness=0.55))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.0, 0.85, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-9.0, -3.0, -9.0), (9.0, 7.0, 9.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.025, 0.05), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.06), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            noise=dict(frequency=0.4, quality="Noise2D",
                       position=nf3(constant(0.02), constant(0.01), constant(0.02)),
                       rotation=constant(0), size=constant(0)),
            # violet in -> hold -> out; never brighter than a whisper
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.55), (0.8, 0.45), (1.0, 0.0)],
                [(0.0, 0.725, 0.549, 1.0), (1.0, 1.0, 0.914, 0.69)]))
       .with_lights(sky=15, block=15))

    # --- ground fog ring: thin, slow, barely-there ---------------------------
    (fx.particle_emitter(
            "aura_fog",
            duration=100, looping=True, prewarm=80,
            start_lifetime=random_between(90, 130),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.55, 0.95)),
            simulation_space="Local", max_particles=14)
       .with_emission(rate=constant(0.09))
       # Hovers a hand above the floor, one block outside the dais skirt.
       .with_shape(circle(radius=6.4, thickness=0.25), position=nf3(0, -3.6, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.02, blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="HorizontalBillboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-9.0, -5.0, -9.0), (9.0, 3.0, 9.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.002), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.05), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            # deep violet, VERY low alpha — a fog impression, not a disc
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.14), (0.7, 0.12), (1.0, 0.0)],
                [(0.0, 0.431, 0.302, 0.659), (1.0, 0.431, 0.302, 0.659)]),
            size_over_lifetime=nf3(
                curve(0.6, 1.0, [(0.0, 0.4, 0.33, 1.0, 0.66, 1.0, 1.0, 0.6)],
                      "lifetime", "size"),
                curve(0.6, 1.0, [(0.0, 0.4, 0.33, 1.0, 0.66, 1.0, 1.0, 0.6)],
                      "lifetime", "size"),
                curve(0.6, 1.0, [(0.0, 0.4, 0.33, 1.0, 0.66, 1.0, 1.0, 0.6)],
                      "lifetime", "size")))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:altar_aura_glyphs — stage 2+ near-field
# ---------------------------------------------------------------------------
def build_altar_aura_glyphs() -> FxBuilder:
    fx = FxBuilder("altar_aura_glyphs")

    # --- rune-spark orbit band around the crown ------------------------------
    (fx.particle_emitter(
            "glyph_orbit",
            duration=100, looping=True, prewarm=100,
            start_lifetime=random_between(55, 80),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.1, 0.17)),
            simulation_space="Local", max_particles=12)
       .with_emission(rate=constant(0.16))
       # Loop arc: sparks march around the band instead of popping randomly.
       .with_shape(circle(radius=3.1, thickness=0.15, arc_mode="Loop", arc_speed=0.45),
                   position=nf3(0, 1.4, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.5, 1.2, 1.8),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-7.0, -2.0, -7.0), (7.0, 6.0, 7.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), breathing(-0.015, 0.015), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.35), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            # gold-white flare in, violet fade out — reads as living script
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.9), (0.5, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.914, 0.69), (0.5, 0.906, 0.839, 1.0),
                 (1.0, 0.725, 0.549, 1.0)]),
            # twinkle: shrink-grow-shrink over the life
            size_over_lifetime=nf3(
                curve(0.55, 1.0, [(0.0, 0.6, 0.25, 1.0, 0.6, 1.0, 1.0, 0.55)],
                      "lifetime", "size"),
                curve(0.55, 1.0, [(0.0, 0.6, 0.25, 1.0, 0.6, 1.0, 1.0, 0.55)],
                      "lifetime", "size"),
                curve(0.55, 1.0, [(0.0, 0.6, 0.25, 1.0, 0.6, 1.0, 1.0, 0.55)],
                      "lifetime", "size")))
       .with_lights(sky=15, block=15))

    # --- ground ring pulse: one expanding floor ring every ~3 s --------------
    (fx.particle_emitter(
            "ring_pulse",
            duration=60, looping=True, prewarm=0,
            start_lifetime=constant(26),
            start_speed=constant(0.85),                  # radial from the circle shell
            start_size=nf3(random_between(0.07, 0.11)),
            simulation_space="Local", max_particles=40)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(32), cycles=1, interval=1,
                                    probability=1.0)])
       .with_shape(circle(radius=2.2, thickness=0.0, arc=360.0, arc_mode="BurstSpread"),
                   position=nf3(0, -3.4, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.3, 1.05, 1.6),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-8.0, -5.0, -8.0), (8.0, 2.0, 8.0))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.5), (0.6, 0.3), (1.0, 0.0)],
            [(0.0, 0.906, 0.839, 1.0), (1.0, 0.482, 0.247, 0.851)]))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:altar_aura_pillar — stage 2+ FAR tell (the horizon read, < 200)
# ---------------------------------------------------------------------------
def build_altar_aura_pillar() -> FxBuilder:
    fx = FxBuilder("altar_aura_pillar")

    # --- the column itself: one soft pulsing beam ----------------------------
    beam = (fx.beam_emitter(
            "pillar_beam",
            duration=100, looping=True, end=(0.0, 42.0, 0.0),
            emit_rate=constant(0),                       # continuous
            raycast="NONE",
            color_nf=gradient(                           # violet-gold, soft
                [(0.0, 0.55), (0.5, 0.4), (1.0, 0.55)],
                [(0.0, 0.784, 0.62, 1.0), (0.5, 1.0, 0.914, 0.69),
                 (1.0, 0.784, 0.62, 1.0)]))
       .with_material(texture_material(CIRCLE_TEX, discard=0.02, hdr=(1.5, 1.25, 1.8),
                                       blend=BLEND_ADDITIVE)))
    # BeamConfig.width is a NumberFunction (fx_altar's sky_spear pattern): a slow
    # breath, never off — the far tell must read steady, not blinking.
    beam._config["width"] = curve(
        0.45, 0.8,
        [(0.0, 0.5, 0.2, 1.0, 0.3, 1.0, 0.5, 0.5), (0.5, 0.5, 0.7, 0.0, 0.8, 0.0, 1.0, 0.5)])
    beam.with_lights(sky=15, block=15)

    # --- a few climbing motes inside the column (cheap depth cue) ------------
    (fx.particle_emitter(
            "pillar_motes",
            duration=100, looping=True, prewarm=60,
            start_lifetime=random_between(60, 90),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.08, 0.14)),
            simulation_space="Local", max_particles=10)
       .with_emission(rate=constant(0.11))
       .with_shape(circle(radius=0.55, thickness=1.0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.4, 1.15, 1.7),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-2.0, -1.0, -2.0), (2.0, 44.0, 2.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.28, 0.42), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.2), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.8), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.914, 0.69), (1.0, 0.725, 0.549, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# 4. eclipse:altar_aura_bands — stage 4+ near-field (the high-stage crown)
# ---------------------------------------------------------------------------
def _orbit_band(fx, name, radius, height, tilt_deg, orbital_speed, thickness, hdr):
    """One tilted orbit band: few carriers dragging short additive ribbons."""
    ribbon_mat = texture_material(CIRCLE_TEX, discard=0.05, hdr=hdr,
                                  blend=BLEND_ADDITIVE)
    (fx.particle_emitter(
            name,
            duration=100, looping=True, prewarm=100,
            start_lifetime=constant(95),
            start_speed=constant(0.0),
            start_size=nf3(thickness),
            simulation_space="Local", max_particles=3)
       .with_emission(rate=constant(0.032))              # one new carrier as one dies
       .with_shape(circle(radius=radius, thickness=0.0, arc_mode="Loop", arc_speed=0.33),
                   position=nf3(0, height, 0), rotation=nf3(tilt_deg, 0, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=hdr,
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-8.0, -2.0, -8.0), (8.0, 8.0, 8.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), breathing(-0.012, 0.012), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(orbital_speed), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.9), (0.9, 0.9), (1.0, 0.0)],
                [(0.0, 1.0, 0.914, 0.69), (1.0, 0.906, 0.839, 1.0)]))
       .with_module("trails", {
            "ratio": F(1.0),
            "lifetime": constant(0.35),
            "inheritParticleColor": B(1),
            "trailType": "TRAIL",
            "config": embedded_trail_config(
                ribbon_mat, time=10, min_vertex_distance=0.06,
                width=curve(0.0, thickness * 1.4,
                            [(0.0, 1.0, 0.33, 0.7, 0.66, 0.35, 1.0, 0.0)]),
                color_nf=gradient(
                    [(0.0, 0.8), (1.0, 0.0)],
                    [(0.0, 0.784, 0.62, 1.0), (1.0, 0.431, 0.302, 0.659)]))})
       .with_lights(sky=15, block=15))


def build_altar_aura_bands() -> FxBuilder:
    fx = FxBuilder("altar_aura_bands")
    # Two counter-tilted, counter-rotating light bands bracketing the crown.
    _orbit_band(fx, "band_low", radius=3.6, height=0.9, tilt_deg=10.0,
                orbital_speed=0.55, thickness=0.11, hdr=(1.5, 1.2, 1.9))
    _orbit_band(fx, "band_high", radius=5.0, height=2.6, tilt_deg=-14.0,
                orbital_speed=-0.4, thickness=0.09, hdr=(1.8, 1.45, 1.1))

    # --- occasional energy arcs: 2 fast tangential sparks every ~4.5 s -------
    arc_mat = texture_material(CIRCLE_TEX, discard=0.05, hdr=(2.0, 1.5, 2.4),
                               blend=BLEND_ADDITIVE)
    (fx.particle_emitter(
            "arc_bolts",
            duration=90, looping=True, prewarm=0,
            start_lifetime=random_between(9, 13),
            start_speed=random_between(1.6, 2.2),
            start_size=nf3(0.09),
            simulation_space="Local", max_particles=6)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=30, count=constant(2), cycles=1, interval=1,
                                    probability=0.85)])
       # Born on a mid sphere shell, flung tangentially by the orbital field below.
       .with_shape(sphere(radius=4.2, thickness=0.1), position=nf3(0, 1.8, 0))
       .with_material(arc_mat)
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-8.0, -2.0, -8.0), (8.0, 8.0, 8.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(2.4), constant(0)),
                offset=nf3(0), radial=constant(-0.4), speed_modifier=constant(1)),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.6, 0.7), (1.0, 0.0)],
                [(0.0, 0.906, 0.839, 1.0), (1.0, 0.482, 0.247, 0.851)]))
       .with_module("trails", {
            "ratio": F(1.0),
            "lifetime": constant(0.7),
            "inheritParticleColor": B(1),
            "trailType": "TRAIL",
            "config": embedded_trail_config(
                arc_mat, time=6, min_vertex_distance=0.04,
                width=curve(0.0, 0.1, [(0.0, 1.0, 0.33, 0.66, 0.66, 0.33, 1.0, 0.0)]),
                color_nf=gradient(
                    [(0.0, 0.9), (1.0, 0.0)],
                    [(0.0, 0.906, 0.839, 1.0), (1.0, 0.482, 0.247, 0.851)]))})
       .with_lights(sky=15, block=15))
    return fx


BUILDERS = {
    "altar_aura_motes.fx": build_altar_aura_motes,
    "altar_aura_glyphs.fx": build_altar_aura_glyphs,
    "altar_aura_pillar.fx": build_altar_aura_pillar,
    "altar_aura_bands.fx": build_altar_aura_bands,
}


def main() -> int:
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
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B)"
                  " — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    sys.exit(main())
