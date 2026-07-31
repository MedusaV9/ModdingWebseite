#!/usr/bin/env python3
"""altar_aura2_fx — F-075 V2 "Insel-Aura": island-SCALE Photon `.fx` assets.

The V1 aura (`altar_aura_fx.py`) hugs the altar dais (r 2.2-6.4). V2 scales the read
up to the ISLAND (top ellipse rx 16 / rz 14, `FloatingSanctumBuilder`): a perimeter
rim ring at the island edge, spiral streams converging rim -> altar crown, and the
one-shot stage-up ring wave. Rows registered by `veilfx/AltarAura2FxRows`; the loop
windows live in `client/drama/AltarAuraIdle` (min/max-level TIER SWAP so exactly one
rim and one spiral executor is ever live), the one-shot is dispatched from
`client/drama/AltarCeremonyFx`.

Generates (into `src/main/resources/assets/eclipse/fx/`, id = `eclipse:<name>`):

- `altar_aura_rim_lo.fx`     — stage 1-2 rim: sparse deep-violet motes rising off the
                               island edge circle (r 15.5) + a faint rim fog skirt.
- `altar_aura_rim_mid.fx`    — stage 3-4 rim: denser, taller, gold flecks + occasional
                               up-streamers on the pillar ring (r 9).
- `altar_aura_rim_hi.fx`     — stage 5 rim: full density, tallest climb, gold crests.
- `altar_aura_spiral_lo.fx`  — stage 2-3: two dim spiral streams converging rim ->
                               crown (loop-arc birth + inward radial + orbital drift).
- `altar_aura_spiral_hi.fx`  — stage 4+: four arms, bright heads, longer ribbons.
- `altar_aura_powerup.fx`    — ONE-SHOT stage-up beat: ground ring wave sweeping
                               altar -> rim in ~1.2 s + crown flash + 2 s spark rain.

All loop emitters are authored ISLAND-TOP-relative: the `AltarAuraIdle` windows anchor
them at `ALTAR_CENTER + (0, -4, 0)` (the island surface; altar sits +4 above it). The
one-shot is dispatched at the raw `ALTAR_CENTER` anchor and carries its own -3.4 floor
offset in the shape position.

House palette: violet #B98CFF / deep #6E4DA8 / core #E7D6FF, gold #FFE9B0.
Budgets: rim loops peak at ~146 live particles at stage 5 — legal because the whole
rim family is GPU-INSTANCED (FX-Wave-13 A7: `useGPUInstance: 1b` on every trail-less
billboard/horizontal loop emitter; jar-verified that the instanced upload honors
renderMode via `Mode.quaternion`). The spiral arms keep the CPU path (their `trails`
modules render through the CPU pipeline) and stay <= ~40. One executor per asset while
its window is open; the one-shot peaks at ~118 short-lived particles.

Every write round-trip-validates (fxlib law). Re-run after editing:
    python3 tools/photon/altar_aura2_fx.py
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

# Island geometry (FloatingSanctumBuilder): top ellipse rx 16 / rz 14 -> the rim
# circle averages the two axes and the 2.5 thickness band covers the deviation.
RIM_RADIUS = 15.5
RIM_THICKNESS = 2.5
PILLAR_RING_RADIUS = 9.0

# Palette as float RGB.
DEEP = (0.431, 0.302, 0.659)     # 6E4DA8
VIOLET = (0.725, 0.549, 1.0)     # B98CFF
CORE = (0.906, 0.839, 1.0)       # E7D6FF
GOLD = (1.0, 0.914, 0.69)        # FFE9B0


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


def twinkle_size(lo_frac):
    """Shrink-grow-shrink size curve over the particle life (glyph twinkle shape)."""
    seg = [(0.0, 0.6, 0.25, 1.0, 0.6, 1.0, 1.0, 0.55)]
    return nf3(curve(lo_frac, 1.0, seg, "lifetime", "size"),
               curve(lo_frac, 1.0, seg, "lifetime", "size"),
               curve(lo_frac, 1.0, seg, "lifetime", "size"))


# ---------------------------------------------------------------------------
# Rim ring family — eclipse:altar_aura_rim_{lo,mid,hi}
# ---------------------------------------------------------------------------
def _rim_motes(fx, rate, max_particles, climb, size_hi, hdr, alpha_hold, rgb_out):
    """The rim's rising motes: born on the island-edge circle, drifting up + around."""
    (fx.particle_emitter(
            "rim_motes",
            duration=100, looping=True, prewarm=80,
            start_lifetime=random_between(80, 120),
            start_speed=constant(0.0),
            # V2.1 readability pass: floor 0.12 (was 0.05) — sub-0.1 motes vanished
            # beyond ~15 blocks, defeating the island-scale read (llvmpipe QA).
            start_size=nf3(random_between(0.12, size_hi)),
            simulation_space="Local", max_particles=max_particles)
       .with_emission(rate=constant(rate))
       # The island edge: r 15.5 +- the thickness band covers the 14..16 ellipse.
       .with_shape(circle(radius=RIM_RADIUS, thickness=RIM_THICKNESS),
                   position=nf3(0, 0.3, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=hdr,
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False,
                      use_gpu_instance=True)
       .with_cull_box((-20.0, -3.0, -20.0), (20.0, 10.0, 20.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), climb, constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.05), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            noise=dict(frequency=0.35, quality="Noise2D",
                       position=nf3(constant(0.03), constant(0.01), constant(0.03)),
                       rotation=constant(0), size=constant(0)),
            # deep violet in -> hold -> tier colour out; a perimeter whisper
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, alpha_hold), (0.8, alpha_hold * 0.85), (1.0, 0.0)],
                [(0.0,) + DEEP, (1.0,) + rgb_out]))
       .with_lights(sky=15, block=15))


def _rim_fog(fx, alpha, hdr):
    """Faint fog skirt hugging the island lip, just outside the walkable edge."""
    (fx.particle_emitter(
            "rim_fog",
            duration=100, looping=True, prewarm=90,
            start_lifetime=random_between(100, 140),
            start_speed=constant(0.0),
            start_size=nf3(random_between(1.1, 1.8)),
            simulation_space="Local", max_particles=18)
       .with_emission(rate=constant(0.12))               # A7: 0.09/14 -> 0.12/18 (GPU)
       .with_shape(circle(radius=RIM_RADIUS + 0.7, thickness=0.3),
                   position=nf3(0, 0.15, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.02, hdr=hdr,
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE",
                      shade=False, use_gpu_instance=True)
       .with_cull_box((-20.0, -3.0, -20.0), (20.0, 4.0, 20.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.002), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.03), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, alpha), (0.7, alpha * 0.85), (1.0, 0.0)],
                [(0.0,) + DEEP, (1.0,) + DEEP]),
            size_over_lifetime=nf3(
                curve(0.6, 1.0, [(0.0, 0.4, 0.33, 1.0, 0.66, 1.0, 1.0, 0.6)],
                      "lifetime", "size"),
                curve(0.6, 1.0, [(0.0, 0.4, 0.33, 1.0, 0.66, 1.0, 1.0, 0.6)],
                      "lifetime", "size"),
                curve(0.6, 1.0, [(0.0, 0.4, 0.33, 1.0, 0.66, 1.0, 1.0, 0.6)],
                      "lifetime", "size")))
       .with_lights(sky=15, block=15))


def _rim_streamers(fx, burst_count, probability, hdr):
    """Occasional quick up-streamers on the pillar ring (mid/hi tiers only)."""
    (fx.particle_emitter(
            "rim_streamers",
            # prewarm one full cycle (LINT-PREWARM caps at duration): the t=20 burst is
            # already mid-climb at chunk-load like the rim_motes/_fog siblings, instead
            # of the ring standing bare for a second (LINT-PREWARM-FILL).
            duration=50, looping=True, prewarm=50,
            start_lifetime=random_between(38, 55),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.16, 0.26)),
            simulation_space="Local", max_particles=16)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=20, count=constant(burst_count), cycles=1,
                                    interval=1, probability=probability)])
       .with_shape(circle(radius=PILLAR_RING_RADIUS, thickness=0.2),
                   position=nf3(0, 0.6, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=hdr,
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False,
                      use_gpu_instance=True)
       .with_cull_box((-12.0, -1.0, -12.0), (12.0, 12.0, 12.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.5, 0.8), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.12), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.85), (0.7, 0.5), (1.0, 0.0)],
                [(0.0,) + GOLD, (1.0,) + VIOLET]),
            size_over_lifetime=twinkle_size(0.5))
       .with_lights(sky=15, block=15))


def build_altar_aura_rim_lo() -> FxBuilder:
    """Stage 1-2: the perimeter whisper — sparse, low, deep violet."""
    fx = FxBuilder("altar_aura_rim_lo")
    # A7 GPU bump: 0.5/40 -> 0.7/56 (and equivalents below) — instanced, so the
    # ~40 % density gain costs upload bytes, not per-particle CPU draw calls.
    _rim_motes(fx, rate=0.7, max_particles=56,
               climb=random_between(0.03, 0.06), size_hi=0.26,
               hdr=(1.3, 1.1, 1.6), alpha_hold=0.65, rgb_out=VIOLET)
    _rim_fog(fx, alpha=0.16, hdr=(1.0, 1.0, 1.0))
    return fx


def build_altar_aura_rim_mid() -> FxBuilder:
    """Stage 3-4: denser + taller, gold flecks, pillar-ring streamers arrive."""
    fx = FxBuilder("altar_aura_rim_mid")
    _rim_motes(fx, rate=1.7, max_particles=88,          # A7 GPU bump: 1.2/64
               climb=random_between(0.06, 0.11), size_hi=0.32,
               hdr=(1.5, 1.3, 1.8), alpha_hold=0.75, rgb_out=GOLD)
    _rim_fog(fx, alpha=0.19, hdr=(1.1, 1.0, 1.2))
    _rim_streamers(fx, burst_count=6, probability=0.8, hdr=(1.8, 1.5, 2.0))
    return fx


def build_altar_aura_rim_hi() -> FxBuilder:
    """Stage 5: full density, tallest climb, gold crests over a core-white body."""
    fx = FxBuilder("altar_aura_rim_hi")
    _rim_motes(fx, rate=2.8, max_particles=112,         # A7 GPU bump: 2.0/80
               climb=random_between(0.08, 0.16), size_hi=0.38,
               hdr=(1.8, 1.6, 2.1), alpha_hold=0.85, rgb_out=CORE)
    _rim_fog(fx, alpha=0.22, hdr=(1.3, 1.15, 1.4))
    _rim_streamers(fx, burst_count=10, probability=0.95, hdr=(2.2, 1.9, 1.7))
    return fx


# ---------------------------------------------------------------------------
# Spiral stream family — eclipse:altar_aura_spiral_{lo,hi}
# ---------------------------------------------------------------------------
def _spiral_arm(fx, name, yaw_deg, rate, max_particles, inward, orbital_speed,
                hdr, trail_lifetime, trail_width, head_alpha):
    """One converging arm: carriers born marching around the rim circle (loop arc),
    pulled inward (negative radial) while climbing toward the crown; each drags a
    short additive ribbon so the arm reads as a continuous stream."""
    ribbon_mat = texture_material(CIRCLE_TEX, discard=0.05, hdr=hdr,
                                  blend=BLEND_ADDITIVE)
    (fx.particle_emitter(
            name,
            duration=100, looping=True, prewarm=100,
            start_lifetime=constant(130),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.16, 0.26)),
            simulation_space="Local", max_particles=max_particles)
       .with_emission(rate=constant(rate))
       # Loop arc: birth point marches around the rim, so successive carriers form
       # a spiral arm instead of a random shell. The yaw rotation phase-offsets the
       # arms of one asset against each other.
       .with_shape(circle(radius=RIM_RADIUS, thickness=0.0, arc_mode="Loop",
                          arc_speed=0.22),
                   position=nf3(0, 0.4, 0), rotation=nf3(0, yaw_deg, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=hdr,
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-20.0, -3.0, -20.0), (20.0, 12.0, 20.0))
       .with_curves(
            velocity_over_lifetime=dict(
                # Inward pull converges r 15.5 -> ~1 over the 6.5 s life while the
                # orbital drift wraps ~1/3 turn — a lazy converging spiral, and the
                # slow climb lands the head at crown height (+4..+7 over the top).
                linear=nf3(constant(0), random_between(0.55, 0.8), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(orbital_speed), constant(0)),
                offset=nf3(0), radial=constant(inward), speed_modifier=constant(1)),
            # dim head in, brightening toward the core as it nears the altar
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, head_alpha), (0.75, head_alpha), (1.0, 0.0)],
                [(0.0,) + VIOLET, (0.7,) + CORE, (1.0,) + GOLD]))
       .with_module("trails", {
            "ratio": F(1.0),
            "lifetime": constant(trail_lifetime),
            "inheritParticleColor": B(1),
            "trailType": "TRAIL",
            "config": embedded_trail_config(
                ribbon_mat, time=10, min_vertex_distance=0.08,
                width=curve(0.0, trail_width,
                            [(0.0, 1.0, 0.33, 0.7, 0.66, 0.35, 1.0, 0.0)]),
                color_nf=gradient(
                    [(0.0, 0.7), (1.0, 0.0)],
                    [(0.0,) + VIOLET, (1.0,) + DEEP]))})
       .with_lights(sky=15, block=15))


def build_altar_aura_spiral_lo() -> FxBuilder:
    """Stage 2-3: two dim arms, slow convergence."""
    fx = FxBuilder("altar_aura_spiral_lo")
    for i, yaw in enumerate((0.0, 180.0)):
        _spiral_arm(fx, f"arm_{i}", yaw, rate=0.8, max_particles=8,
                    inward=-2.3, orbital_speed=0.32, hdr=(1.5, 1.3, 1.7),
                    trail_lifetime=0.3, trail_width=0.16, head_alpha=0.75)
    return fx


def build_altar_aura_spiral_hi() -> FxBuilder:
    """Stage 4+: four arms, bright heads, longer ribbons (the plan's 'trails x1.5')."""
    fx = FxBuilder("altar_aura_spiral_hi")
    for i, yaw in enumerate((0.0, 90.0, 180.0, 270.0)):
        _spiral_arm(fx, f"arm_{i}", yaw, rate=1.0, max_particles=10,
                    inward=-2.5, orbital_speed=0.4, hdr=(2.1, 1.8, 2.4),
                    trail_lifetime=0.45, trail_width=0.22, head_alpha=0.95)
    return fx


# ---------------------------------------------------------------------------
# eclipse:altar_aura_powerup — the ONE-SHOT stage-up beat
# ---------------------------------------------------------------------------
def build_altar_aura_powerup() -> FxBuilder:
    """Dispatched at the raw ALTAR_CENTER anchor by AltarCeremonyFx: ground ring wave
    altar -> rim (~1.2 s), a crown flash, and a short spark rain over the island."""
    fx = FxBuilder("altar_aura_powerup")

    # --- wave_ring: the expanding ground wave (floor sits 3.4 below the anchor) ---
    # FX-Wave-11 stacking-law pass: 48 additive sparks leaving one 0.8 r shell at
    # hdr 2.6 all overlapped for the first few ticks and flashed white before the
    # wave separated. Count 48->24 on a 1.5 r shell, hdr ~1.45, alpha crest 0.9->0.6.
    (fx.particle_emitter(
            "wave_ring",
            duration=40, looping=False,
            start_lifetime=constant(26),
            start_speed=constant(13.0),                  # radial: r 1.5 -> ~18 b
            start_size=nf3(random_between(0.15, 0.25)),
            simulation_space="World", max_particles=48)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(24), cycles=1, interval=1,
                                    probability=1.0)])
       .with_shape(circle(radius=1.5, thickness=0.0, arc=360.0,
                          arc_mode="BurstSpread"),
                   position=nf3(0, -3.4, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.45, 1.2, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-20.0, -6.0, -20.0), (20.0, 4.0, 20.0))
       .with_curves(
            # FX-Wave-11.1: pale-violet birth stop instead of pure white — the first
            # 2 ticks of the wave still overlap on the 1.5 r shell.
            color_over_lifetime=gradient(
                [(0.0, 0.6), (0.6, 0.6), (1.0, 0.0)],
                [(0.0, 0.906, 0.82, 1.0), (0.5,) + CORE, (1.0,) + VIOLET]),
            size_over_lifetime=nf3(
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.0, 1.0, [(0.0, 0.4, 0.15, 1.0, 0.7, 0.95, 1.0, 0.0)],
                      "lifetime", "size")))
       .with_lights(sky=15, block=15))

    # --- crown_flash: a short upward flare right at the altar crown ---------------
    # FX-Wave-11.1 stacking-law pass: 10 hdr-(2.4,2.0,2.8) white sparks born inside a
    # 0.4 r sphere WERE the "solid white ball at the centre" in the client test —
    # every spark overlapped every other one for its whole life. 5 sparks on a 1.0 r
    # shell at hdr ~1.6 and a 0.7 birth alpha keep the flare without the fusion.
    (fx.particle_emitter(
            "crown_flash",
            duration=40, looping=False,
            start_lifetime=random_between(12, 18),
            start_speed=random_between(0.6, 1.2),
            start_size=nf3(random_between(0.2, 0.35)),
            simulation_space="World", max_particles=10)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(5), cycles=1, interval=1,
                                    probability=1.0)])
       .with_shape(sphere(radius=1.0, thickness=0.0), position=nf3(0, 1.5, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.6, 1.3, 1.9),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 8.0, 4.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(1.2, 2.0), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.3), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            color_over_lifetime=gradient(
                [(0.0, 0.7), (0.5, 0.55), (1.0, 0.0)],
                [(0.0, 0.95, 0.88, 1.0), (1.0,) + GOLD]))
       .with_lights(sky=15, block=15))

    # --- spark_rain: a 2 s glitter fall over the whole island (t = 6) -------------
    (fx.particle_emitter(
            "spark_rain",
            duration=60, looping=False,
            start_lifetime=random_between(30, 42),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.06, 0.11)),
            simulation_space="World", max_particles=60)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=6, count=constant(60), cycles=1, interval=1,
                                    probability=1.0)])
       .with_shape(circle(radius=12.0, thickness=1.0), position=nf3(0, 9.0, 0))
       .with_material(texture_material(CIRCLE_TEX, discard=0.05, hdr=(1.6, 1.35, 1.9),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Billboard", vertex_sorting="NONE", shade=False)
       .with_cull_box((-16.0, -6.0, -16.0), (16.0, 12.0, 16.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-1.8, -1.2), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.08), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.8), (0.7, 0.5), (1.0, 0.0)],
                [(0.0,) + GOLD, (1.0,) + VIOLET]),
            size_over_lifetime=twinkle_size(0.5))
       .with_lights(sky=15, block=15))
    return fx


BUILDERS = {
    "altar_aura_rim_lo.fx": build_altar_aura_rim_lo,
    "altar_aura_rim_mid.fx": build_altar_aura_rim_mid,
    "altar_aura_rim_hi.fx": build_altar_aura_rim_hi,
    "altar_aura_spiral_lo.fx": build_altar_aura_spiral_lo,
    "altar_aura_spiral_hi.fx": build_altar_aura_spiral_hi,
    "altar_aura_powerup.fx": build_altar_aura_powerup,
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
