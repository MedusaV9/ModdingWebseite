#!/usr/bin/env python3
"""PH-SOCIAL asset generator — player-attached Photon effects (IDEAS-player.md 3/7/8/9/10).

Writes nine `.fx` files into `src/main/resources/assets/eclipse/fx/` (gzip NBT, fxlib
round-trip-validated on write). This script is the diffable SOURCE for the binary assets
(the binary-diff law substitute for `.fxproj` — regenerate, never hand-edit the `.fx`):

  theft_soul_rise / theft_soul_launch / theft_soul_arrive   heart-theft soul arc (concept 3)
  rebirth_aura_1 / rebirth_aura_2 / rebirth_aura_3          prestige ribbon orbit tiers (concept 7)
  ghost_wisp                                                Limbo ghost spectral wisps (concept 9)
  contract_mark                                             hunter-only target pulse ring (concept 8)
  glide_trail                                               edge-glide wingtip ara ribbons (concept 10)

Run: python3 tools/photon/gen_ph_social.py       (from the repo root or tools/photon/)
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    FX_ASSETS_DIR, REPO_ROOT, B, F, I, L, FxBuilder, BLEND_ADDITIVE, BLEND_ALPHA,
    SEG_DECAY_TAIL, aabb, burst, color, constant, curve, dot, gradient, nf3,
    random_between, rom, sphere, cylinder, texture_material, validate_file,
)

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
RING = "photon:textures/particle/ring.png"

# Ease-out expansion (fast growth, soft settle) for shock rings — x lifetime, y 0..1.
SEG_EASE_OUT = (0.0, 0.0, 0.15, 0.75, 0.5, 1.0, 1.0, 1.0)


def _ara_trails_module(thickness, time_s, color_over_length, material_entry,
                       inertia=0.3, damping=0.75, velocity_smoothing=0.75,
                       sorting=None, inherit_color=True):
    """`trails` toggle-module compound (trailType ARA_TRAIL + embedded araConfig).

    Omitted keys keep the Java defaults (FX_FORMAT.md §2/§3.3/§4.3)."""
    ara = {
        "space": "World", "alignment": "View",
        "thickness": F(float(thickness)),
        "time": F(float(time_s)), "timeInterval": F(0.05), "minDistance": F(0.025),
        "colorOverLength": color_over_length,
        "physicsSetting": {
            "warmup": F(0.0), "gravity": L([F(0.0), F(0.0), F(0.0)]),
            "inertia": F(float(inertia)), "velocitySmoothing": F(float(velocity_smoothing)),
            "damping": F(float(damping))},
        "renderer": {"materials": rom([material_entry]), "layer": "Translucent",
                     "cull": {"_enable": B(0)}, "orderInLayer": I(0),
                     "vertexSortingMode": "NONE"},
    }
    if sorting is not None:
        ara["sorting"] = sorting
    return {"trailType": "ARA_TRAIL", "inheritParticleColor": B(1 if inherit_color else 0),
            "araConfig": ara}


VIOLET_FADE = gradient([(0.0, 0.85), (1.0, 0.0)],
                       [(0.0, 0.72, 0.38, 0.95), (1.0, 0.4, 0.1, 0.6)])
GOLD_FADE = gradient([(0.0, 0.85), (1.0, 0.0)],
                     [(0.0, 1.0, 0.85, 0.45), (1.0, 0.75, 0.5, 0.15)])
GLIDE_FADE = gradient([(0.0, 0.7), (1.0, 0.0)],
                      [(0.0, 0.85, 0.93, 1.0), (1.0, 0.45, 0.65, 0.95)])


# ---------------------------------------------------------------------------
# Concept 3 — heart-theft soul arc (three one-shots, client-choreographed handoff)
# ---------------------------------------------------------------------------
def build_theft_soul_rise() -> FxBuilder:
    """Victim leg 1: purple heart-mote rises 1.2 blocks off the corpse, dragging a thin
    violet ara ribbon, while 12 wisps spiral INTO it (block-anchored — the victim entity
    is dead, an entity executor would be destroyed on its first tick)."""
    fx = FxBuilder("theft_soul_rise")
    (fx.particle_emitter(
            "soul_mote", duration=26, looping=False,
            start_lifetime=constant(20), start_speed=constant(0),
            start_size=nf3(0.22), start_color=color(0xFFC275F0),
            simulation_space="World", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.6, 0.6, 1.8), blend=BLEND_ADDITIVE))
       .with_lights()
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.06), constant(0))),
            color_over_lifetime=gradient([(0.0, 0.0), (0.15, 1.0), (0.85, 1.0), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0), (1.0, 0.85, 0.55, 1.0)]))
       .with_module("trails", _ara_trails_module(
            0.12, 0.9, VIOLET_FADE,
            texture_material(CIRCLE, hdr=(1.2, 0.5, 1.5), blend=BLEND_ADDITIVE),
            inertia=0.25, damping=0.8)))
    (fx.particle_emitter(
            "in_wisps", duration=22, looping=False,
            start_lifetime=random_between(12, 18), start_speed=constant(0),
            start_size=nf3(random_between(0.05, 0.09), random_between(0.05, 0.09),
                           random_between(0.05, 0.09)),
            start_color=color(0xFFB05CE6), simulation_space="World", max_particles=24)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(12))])
       .with_shape(sphere(radius=0.55, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.1, 0.45, 1.3), blend=BLEND_ADDITIVE))
       .with_lights()
       .with_curves(
            velocity_over_lifetime=dict(orbital=nf3(constant(0), constant(0.45), constant(0)),
                                        radial=constant(-0.06)),
            color_over_lifetime=gradient([(0.0, 0.9), (1.0, 0.0)],
                                         [(0.0, 0.8, 0.5, 1.0), (1.0, 0.45, 0.15, 0.7)])))
    return fx


def build_theft_soul_launch() -> FxBuilder:
    """Victim leg 2 (fired with setDelay(20) + setRotation aiming local +Z at the killer):
    a single comet mote departs at ~1.5 blocks/tick dragging a fat violet ara ribbon."""
    fx = FxBuilder("theft_soul_launch")
    (fx.particle_emitter(
            "soul_comet", duration=14, looping=False,
            start_lifetime=constant(10), start_speed=constant(1.5),
            start_size=nf3(0.26), start_color=color(0xFFD9A8FF),
            simulation_space="World", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape({"type": "function", "data": {
            "x": "0", "y": "0", "z": "0",
            "speedX": "0", "speedY": "0.08", "speedZ": "1"}})
       .with_material(texture_material(CIRCLE, hdr=(1.8, 0.8, 2.0), blend=BLEND_ADDITIVE))
       .with_lights()
       .with_curves(
            force_over_lifetime=dict(force=nf3(constant(0), constant(-0.02), constant(0)),
                                     simulation_space="World"),
            color_over_lifetime=gradient([(0.0, 1.0), (0.8, 1.0), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0), (1.0, 0.8, 0.5, 1.0)]))
       .with_module("trails", _ara_trails_module(
            0.25, 0.6, VIOLET_FADE,
            texture_material(CIRCLE, hdr=(1.4, 0.6, 1.7), blend=BLEND_ADDITIVE),
            inertia=0.2, damping=0.75, sorting="NewerOnTop")))
    return fx


def build_theft_soul_arrive() -> FxBuilder:
    """Killer leg (entity-attached, delay = 20 + flight time): 3t in-suck of 16 wisps,
    then an HDR heart bloom + soft expanding ring at the chest."""
    fx = FxBuilder("theft_soul_arrive")
    (fx.particle_emitter(
            "in_suck", duration=30, looping=False,
            start_lifetime=random_between(5, 8), start_speed=constant(0),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            start_color=color(0xFFB980F5), simulation_space="Local", max_particles=24)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(16))])
       .with_shape(sphere(radius=1.1, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.2, 0.5, 1.4), blend=BLEND_ADDITIVE))
       .with_lights()
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-0.28)),
            color_over_lifetime=gradient([(0.0, 0.9), (1.0, 0.0)],
                                         [(0.0, 0.85, 0.55, 1.0), (1.0, 0.5, 0.2, 0.8)])))
    (fx.particle_emitter(
            "heart_bloom", duration=30, looping=False,
            start_lifetime=constant(12), start_speed=constant(0),
            start_size=nf3(0.5), start_color=color(0xFFFFFFFF),
            simulation_space="Local", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=4, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.8, 0.5, 1.5), blend=BLEND_ADDITIVE))
       .with_lights()
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.0, 1.0, [(0.0, 0.2, 0.08, 1.0, 0.85, 0.35, 1.0, 0.0)],
                                           "lifetime", "size")] * 3),
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)],
                                         [(0.0, 1.0, 0.9, 1.0), (1.0, 0.9, 0.4, 0.9)])))
    (fx.particle_emitter(
            "soft_ring", duration=30, looping=False,
            start_lifetime=constant(10), start_speed=constant(0),
            start_size=nf3(1.0), start_color=color(0xFFCF8FF5),
            simulation_space="Local", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=4, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING, hdr=(1.1, 0.5, 1.3), blend=BLEND_ADDITIVE))
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.4, 1.9, [SEG_EASE_OUT], "lifetime", "size")] * 3),
            color_over_lifetime=gradient([(0.0, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 7 — rebirth prestige ribbon orbit (tiers 1-3; WITCH ring stays server-side)
# ---------------------------------------------------------------------------
def build_rebirth_aura(tier: int) -> FxBuilder:
    """`tier` ribbons at even phase offsets: each is one orbiting mote (burst 1/cycle,
    lifetime == duration => exactly one alive) dragging a silk-thin World-space ara
    ribbon that lags on movement; plus sparse rising witch-purple motes. Tier 3's third
    ribbon is gold-tinted. Executor anchors it at the feet (offset (0,-1.45,0))."""
    fx = FxBuilder(f"rebirth_aura_{tier}")
    radius, orbit_duration = 0.85, 40
    for i in range(tier):
        angle = 2.0 * math.pi * i / tier
        gold = tier == 3 and i == 2
        (fx.particle_emitter(
                f"orbit_{i}", duration=orbit_duration, looping=True, prewarm=12,
                start_lifetime=constant(orbit_duration), start_speed=constant(0),
                start_size=nf3(0.035),
                start_color=color(0xFFFFD98A if gold else 0xFFB668EE),
                simulation_space="Local", max_particles=4)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
           .with_shape(dot(), position=nf3(constant(radius * math.cos(angle)), constant(0.0),
                                           constant(radius * math.sin(angle))))
           .with_material(texture_material(
                CIRCLE, hdr=(1.2, 1.0, 0.5) if gold else (1.2, 0.6, 1.6),
                blend=BLEND_ADDITIVE))
           .with_cull_box((-2.0, -0.5, -2.0), (2.0, 2.5, 2.0))
           .with_lights()
           .with_curves(
                velocity_over_lifetime=dict(orbital=nf3(constant(0), constant(0.35), constant(0))))
           .with_module("trails", _ara_trails_module(
                0.06, 1.2, GOLD_FADE if gold else VIOLET_FADE,
                texture_material(CIRCLE, hdr=(1.1, 0.9, 0.45) if gold else (1.0, 0.5, 1.3),
                                 blend=BLEND_ADDITIVE),
                inertia=0.35, damping=0.7)))
    (fx.particle_emitter(
            "rising_motes", duration=60, looping=True, prewarm=10,
            start_lifetime=random_between(25, 35), start_speed=constant(0),
            start_size=nf3(random_between(0.06, 0.1), random_between(0.06, 0.1),
                           random_between(0.06, 0.1)),
            start_color=color(0xFF9B4CD0), simulation_space="Local", max_particles=16)
       .with_emission(rate=constant(0.15), bursts=[])
       .with_shape(cylinder(radius=0.6, thickness=1.0))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-2.0, -0.5, -2.0), (2.0, 2.5, 2.0))
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.02), constant(0))),
            color_over_lifetime=gradient([(0.0, 0.0), (0.25, 0.55), (1.0, 0.0)],
                                         [(0.0, 0.62, 0.32, 0.85)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 9 — Limbo ghost spectral wisp loop
# ---------------------------------------------------------------------------
def build_ghost_wisp() -> FxBuilder:
    """Cold pale-green/cyan wisps drifting off a ghost (rate 0.5/t, noise float) plus one
    faintly pulsing HDR core mote at the chest. Executor offset (0,-0.6,0)."""
    fx = FxBuilder("ghost_wisp")
    (fx.particle_emitter(
            "wisps", duration=60, looping=True, prewarm=15,
            start_lifetime=random_between(30, 45), start_speed=constant(0),
            start_size=nf3(random_between(0.1, 0.18), random_between(0.1, 0.18),
                           random_between(0.1, 0.18)),
            start_color=color(0xFFFFFFFF), simulation_space="Local", max_particles=48)
       .with_emission(rate=constant(0.5), bursts=[])
       .with_shape(sphere(radius=0.5, thickness=1.0))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-2.0, -1.0, -2.0), (2.0, 2.5, 2.0))
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.015), constant(0))),
            noise=dict(frequency=0.6, quality="Noise2D", position=nf3(0.08),
                       rotation=constant(0), size=constant(0)),
            color_over_lifetime=gradient([(0.0, 0.0), (0.25, 0.6), (0.8, 0.45), (1.0, 0.0)],
                                         [(0.0, 0.62, 0.95, 0.7), (1.0, 0.45, 0.9, 0.95)]))
       # Spec'd optional garnish (IDEAS-player #9 / QUALITY §2 row 4): hairline TRAIL
       # ribbons on 20 % of wisps — drifting streaks of ectoplasm, not every mote.
       .with_module("trails", {
            "ratio": F(0.2), "lifetime": constant(1.0),
            "dieWithParticles": B(1), "sizeAffectsWidth": B(0), "sizeAffectsLifetime": B(0),
            "inheritParticleColor": B(0),
            "colorOverLifetime": gradient([(0.0, 0.4), (1.0, 0.0)],
                                          [(0.0, 0.62, 0.95, 0.8)]),
            "trailType": "TRAIL",
            "config": {
                "time": I(12), "minVertexDistance": F(0.02),
                "widthOverTrail": constant(0.02),
                "colorOverTrail": gradient([(0.0, 0.4), (1.0, 0.0)],
                                           [(0.0, 0.62, 0.95, 0.8)]),
                "renderer": {
                    "materials": rom([texture_material(CIRCLE, hdr=(0.5, 1.0, 0.8),
                                                       blend=BLEND_ADDITIVE)]),
                    "layer": "Translucent",
                    "cull": {"_enable": B(1),
                             "cullBox": aabb((-2.0, -1.0, -2.0), (2.0, 2.5, 2.0))},
                    "orderInLayer": I(0), "vertexSortingMode": "NONE"}}}))
    (fx.particle_emitter(
            "core", duration=40, looping=True, prewarm=5,
            start_lifetime=constant(40), start_speed=constant(0),
            start_size=nf3(0.16), start_color=color(0xFFBFFFE0),
            simulation_space="Local", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(0.5, 1.0, 0.8), blend=BLEND_ADDITIVE))
       # Golden rule (FX_FORMAT §10 / LINT-CULL-LOOP): the loop's one chest mote sits at
       # the local origin — a small box fully contains it (PHOTON-QUALITY §2 row 4 fix).
       .with_cull_box((-1.0, -1.0, -1.0), (1.0, 1.0, 1.0))
       .with_lights()
       .with_curves(
            color_over_lifetime=gradient([(0.0, 0.15), (0.5, 0.7), (1.0, 0.15)],
                                         [(0.0, 0.75, 1.0, 0.88)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 8 — hunter's target-locked pulse ring (hunter-client-only)
# ---------------------------------------------------------------------------
def build_contract_mark() -> FxBuilder:
    """Heartbeat double-pulse (bursts @ t0 and t6 of a 30t cycle): a flat blood-orange
    sonar ring expanding at the feet, plus two slow-spinning crown motes over the head.
    Executor offset (0,-1.4,0) puts the local origin at the feet."""
    fx = FxBuilder("contract_mark")
    (fx.particle_emitter(
            "lock_ring", duration=30, looping=True,
            start_lifetime=constant(12), start_speed=constant(0),
            start_size=nf3(1.0), start_color=color(0xFFE05A28),
            simulation_space="Local", max_particles=8)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(1)), burst(time=6, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING, hdr=(1.4, 0.6, 0.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box((-2.5, -0.5, -2.5), (2.5, 3.0, 2.5))
       .with_lights()
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.6, 1.8, [SEG_EASE_OUT], "lifetime", "size")] * 3),
            color_over_lifetime=gradient([(0.0, 0.75), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))
    (fx.particle_emitter(
            "crown", duration=30, looping=True, prewarm=5,
            start_lifetime=constant(30), start_speed=constant(0),
            start_size=nf3(0.09), start_color=color(0xFFF08040),
            simulation_space="Local", max_particles=6)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(2))])
       .with_shape({"type": "circle", "data": {
            "radius": F(0.12), "radiusThickness": F(0.0), "arc": F(360.0),
            "shapeArc": {"arcMode": "BurstSpread", "arcSpread": F(0.0),
                         "arcSpeed": constant(1.0)}}},
                   position=nf3(constant(0.0), constant(2.2), constant(0.0)))
       .with_material(texture_material(CIRCLE, hdr=(1.2, 0.5, 0.2), blend=BLEND_ADDITIVE))
       .with_cull_box((-2.5, -0.5, -2.5), (2.5, 3.0, 2.5))
       .with_lights()
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(3.0)),
            velocity_over_lifetime=dict(orbital=nf3(constant(0), constant(0.2), constant(0)),
                                        offset=nf3(constant(0), constant(2.2), constant(0))),
            color_over_lifetime=gradient([(0.0, 0.35), (0.5, 0.8), (1.0, 0.35)],
                                         [(0.0, 1.0, 0.65, 0.35)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 10 — edge-glide wingtip ara ribbons (FORWARD AutoRotate executor)
# ---------------------------------------------------------------------------
def build_glide_trail() -> FxBuilder:
    """Two physics-lagged World-space ribbons off the wingtips (±0.55 X under FORWARD
    auto-rotate) with a taper + cool white-blue fade, plus a sparse sparkle emitter.
    Executor offset (0,-0.3,0)."""
    fx = FxBuilder("glide_trail")
    for side, x in (("left", -0.55), ("right", 0.55)):
        wing = fx.empty(f"wing_{side}").at(x, 0.0, -0.1)
        (fx.ara_trail_emitter(
                f"ribbon_{side}", looping=True,
                space="World", alignment="Velocity", thickness=0.12,
                time=0.8, time_interval=0.05, min_distance=0.05,
                # Eased taper (PHOTON-QUALITY §2 runner-up, fixed with the §6 REPLACE
                # flip): hold near-full thickness at the root, dissolve at the tail —
                # a feathered wingtip instead of the old ruler-straight linear taper.
                thickness_over_length=curve(0.0, 1.0, [SEG_DECAY_TAIL], "length", "thickness"),
                color_over_length=GLIDE_FADE,
                physics=dict(inertia=0.3, velocity_smoothing=0.8, damping=0.7))
           .child_of(wing)
           .with_material(texture_material(CIRCLE, hdr=(0.9, 1.0, 1.3), blend=BLEND_ADDITIVE))
           .with_cull_box((-4.0, -4.0, -4.0), (4.0, 4.0, 4.0)))
    (fx.particle_emitter(
            "sparkles", duration=60, looping=True,
            start_lifetime=random_between(10, 16), start_speed=constant(0),
            start_size=nf3(random_between(0.05, 0.08), random_between(0.05, 0.08),
                           random_between(0.05, 0.08)),
            start_color=color(0xFFDCEBFF), simulation_space="World", max_particles=16)
       .with_emission(rate=constant(0.2), bursts=[])
       .with_shape(sphere(radius=0.4, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=(1.0, 1.1, 1.4), blend=BLEND_ADDITIVE))
       .with_cull_box((-4.0, -4.0, -4.0), (4.0, 4.0, 4.0))
       .with_lights()
       .with_curves(
            color_over_lifetime=gradient([(0.0, 0.9), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0), (1.0, 0.6, 0.75, 1.0)])))
    return fx


BUILDERS = {
    "theft_soul_rise.fx": build_theft_soul_rise,
    "theft_soul_launch.fx": build_theft_soul_launch,
    "theft_soul_arrive.fx": build_theft_soul_arrive,
    "rebirth_aura_1.fx": lambda: build_rebirth_aura(1),
    "rebirth_aura_2.fx": lambda: build_rebirth_aura(2),
    "rebirth_aura_3.fx": lambda: build_rebirth_aura(3),
    "ghost_wisp.fx": build_ghost_wisp,
    "contract_mark.fx": build_contract_mark,
    "glide_trail.fx": build_glide_trail,
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
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
