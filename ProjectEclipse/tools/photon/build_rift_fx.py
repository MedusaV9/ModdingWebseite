#!/usr/bin/env python3
"""PH-RIFT — authors the three rift/expansion Photon assets (IDEAS-world.md #2/#3 +
IDEAS-events.md #4) with fxlib:

  eclipse:expansion_rift_glow   event-horizon ring: 3 orbiting carriers dragging ara
                                ribbons + radial infall streaks (RiftFx.openRift seam,
                                zero new code — the bridge id already exists)
  eclipse:rift_piece_flash      piece-launch muzzle flash at the delivery-tear mouth
                                (RiftFx.tickSurge seam, 6t core <= SURGE_BURST_PERIOD)
  eclipse:growth_front_ribbon   traveling wavefront curtain, looping, attached to the
                                server's eclipse_growth_rider front-rider entity via
                                EntityEffectExecutor (ExpansionSequence.ClientHooks)

Usage:  python3 tools/photon/build_rift_fx.py            # write + validate all three
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, F, I, L, BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, box, burst, circle, cone,
    constant, curve, dot, gradient, nf3, random_between, rom, sphere,
    texture_material, validate_file)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"


def pts_curve(points, lower=0.0, upper=1.0, x_axis="duration", y_axis="value"):
    """Piecewise-linear NF curve through absolute (x, y) points (handles at thirds)."""
    segments = []
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        segments.append((x0, y0,
                         x0 + (x1 - x0) / 3.0, y0 + (y1 - y0) / 3.0,
                         x0 + 2.0 * (x1 - x0) / 3.0, y0 + 2.0 * (y1 - y0) / 3.0,
                         x1, y1))
    return curve(lower, upper, segments, x_axis, y_axis)


def ribbon_renderer(material_entry):
    """RendererSetting compound for an embedded araConfig (mirrors _init_renderer)."""
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": {"_enable": B(0)}, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


# ---------------------------------------------------------------------------
# 1. eclipse:expansion_rift_glow — IDEAS-world.md #2 (rank 2, zero-code seam)
# ---------------------------------------------------------------------------
def build_expansion_rift_glow() -> FxBuilder:
    fx = FxBuilder("expansion_rift_glow")
    root = fx.empty("rift_glow_root")

    # 3 orbiting carriers, each dragging a physics-lagged ara ribbon (the accretion disc).
    carriers = (fx.particle_emitter(
            "horizon_orbiters",
            duration=200, looping=False, start_lifetime=constant(190),
            start_speed=constant(0), start_size=nf3(0.12),
            simulation_space="Local", max_particles=3)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(3), cycles=1)])
        .with_shape(circle(radius=3.2, thickness=0.0, arc_mode="BurstSpread"))
        .with_curves(velocity_over_lifetime=dict(
            orbital_mode="AngularVelocity",
            orbital=nf3(constant(0), constant(1.1), constant(0))))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.8, 1.2, 2.6)))
        .with_cull_box((-8.0, -4.0, -8.0), (8.0, 6.0, 8.0)))
    # trails module, ARA_TRAIL type (FX_FORMAT §3.3 + §4.3) — the premium ribbon look:
    # segments lag/swing behind each carrier via inertia/damping physics.
    carriers.with_module("trails", {
        "ratio": F(1.0),
        "lifetime": constant(0.22),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            "space": "World",              # dropped segments stay behind in world space
            "alignment": "View",
            "thickness": F(0.35),
            "smoothness": I(5),
            "cornerRoundness": I(6),
            "time": F(0.9),                # seconds of ribbon tail
            "timeInterval": F(0.05),       # seconds between segment drops
            "colorOverLength": gradient(
                [(0.0, 1.0), (1.0, 0.0)],  # fade to transparent along the tail
                [(0.0, 0.816, 0.702, 1.0), (1.0, 0.816, 0.702, 1.0)]),  # #D0B3FF
            # Eased taper (QUALITY §2 row 10): the disc holds body near the carrier
            # and whips to a point — not a ruler-straight wedge.
            "thicknessOverLength": curve(
                0.0, 1.0, [(0.0, 1.0, 0.3, 0.95, 0.7, 0.35, 1.0, 0.15)]),
            "physicsSetting": {
                "warmup": F(0.0), "gravity": L([F(0.0), F(0.0), F(0.0)]),
                "inertia": F(0.35), "velocitySmoothing": F(0.75), "damping": F(0.7)},
            "renderer": ribbon_renderer(texture_material(CIRCLE_TEX, hdr=(1.8, 1.2, 2.6))),
        }})

    # Dust visibly sucked INTO the mouth, igniting white at the horizon.
    (fx.particle_emitter(
            "infall_streaks",
            duration=200, looping=False, start_lifetime=random_between(18, 30),
            start_speed=constant(0),
            start_size=nf3(random_between(0.05, 0.12), random_between(0.05, 0.12),
                           random_between(0.05, 0.12)),
            max_particles=140)
        .child_of(root)
        .with_emission(rate=constant(1.2))
        .with_shape(sphere(radius=4.5, thickness=0.15))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(-0.35)),  # inward pull
            # Hold-then-dive: streaks keep size on approach, shrink hard at the horizon.
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 1.0, 0.35, 0.95, 0.75, 0.55, 1.0, 0.2)]),
            # #9C7BE0 body with the t=0.85 white ignition spike at the horizon.
            color_over_lifetime=gradient(
                [(0.0, 0.85), (0.85, 0.9), (1.0, 0.0)],
                [(0.0, 0.612, 0.482, 0.878), (0.85, 0.612, 0.482, 0.878),
                 (1.0, 1.0, 1.0, 1.0)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.2, 0.9, 1.8)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=2.5, vertex_sorting="NONE")
        .with_cull_box((-8.0, -4.0, -8.0), (8.0, 6.0, 8.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:rift_piece_flash — IDEAS-world.md #3 (RiftFx.tickSurge seam)
# ---------------------------------------------------------------------------
def build_rift_piece_flash() -> FxBuilder:
    fx = FxBuilder("rift_piece_flash")

    # Single HDR pop — the loudest bloom in the rift set (4 ticks, forgivable).
    (fx.particle_emitter(
            "flash_core",
            duration=6, looping=False, start_lifetime=constant(4),
            start_speed=constant(0), start_size=nf3(2.8), max_particles=1)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1), cycles=1)])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=(3.5, 2.6, 4.0)))
        .with_curves(
            # The spec's authored pop, as ONE genuine Bézier (IDEAS-world #3 /
            # QUALITY §2 row 11): snap past full, sag, tail off.
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.55, 0.1, 1.0, 0.6, 0.8, 1.0, 0.2)]),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, 0.796, 0.659, 1.0)])))  # white -> #CBA8FF

    # Directional spray down the launch axis (authored +Y; tear fires out of its plane).
    (fx.particle_emitter(
            "flash_petals",
            duration=6, looping=False, start_lifetime=random_between(6, 10),
            start_speed=random_between(0.9, 1.7),
            start_size=nf3(random_between(0.1, 0.2), random_between(0.1, 0.2),
                           random_between(0.1, 0.2)),
            max_particles=20)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14), cycles=1)])
        .with_shape(cone(angle=65.0, radius=0.3))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.8, 1.4, 2.4)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.2, length_scale=3.0)
        .with_curves(color_by_speed=dict(  # fast = white, slow = violet
            color=gradient([(0.0, 1.0), (1.0, 1.0)],
                           [(0.0, 0.61, 0.44, 0.94), (1.0, 1.0, 1.0, 1.0)]),
            range=(0.2, 1.7))))

    # 8 alpha-blended smoke puffs kicked out with the flash (the lingering read).
    (fx.particle_emitter(
            "smoke_kick",
            duration=6, looping=False, start_lifetime=random_between(14, 22),
            start_speed=random_between(0.15, 0.4),
            start_size=nf3(random_between(0.4, 0.7), random_between(0.4, 0.7),
                           random_between(0.4, 0.7)),
            max_particles=10)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(8), cycles=1)])
        .with_shape(cone(angle=65.0, radius=0.3))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_curves(color_over_lifetime=gradient(  # grey-violet fade-out
            [(0.0, 0.5), (0.3, 0.4), (1.0, 0.0)],
            [(0.0, 0.55, 0.5, 0.62), (1.0, 0.35, 0.31, 0.42)])))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:growth_front_ribbon — IDEAS-events.md #4 (entity-anchor verdict)
# ---------------------------------------------------------------------------
def build_growth_front_ribbon() -> FxBuilder:
    fx = FxBuilder("growth_front_ribbon")

    # Continuous curtain hem: World-space ara ribbon lagging behind the front rider.
    (fx.ara_trail_emitter(
            "front_ribbon",
            duration=100, looping=True,
            space="World",                 # already-dropped segments trail behind
            alignment="View",
            thickness=2.5,
            smoothness=4,
            time=1.6,                      # seconds a segment lives (~20-40 block veil)
            time_interval=0.05,
            texture_mode="Stretch",
            color_over_length=gradient(    # dusty violet-grey fading to nothing
                [(0.0, 0.45), (0.6, 0.3), (1.0, 0.0)],
                [(0.0, 0.62, 0.58, 0.72), (1.0, 0.45, 0.4, 0.56)]),
            physics=dict(inertia=0.35, velocity_smoothing=0.75, damping=0.8))
        .at(0.0, 1.5, 0.0)
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_cull_box((-24.0, -8.0, -24.0), (24.0, 16.0, 24.0)))

    # Dust wall segment: World simulation space is the trick — emitted puffs stay where
    # the front passed, so the wall visibly travels and trails.
    (fx.particle_emitter(
            "dust_skirt",
            duration=20, looping=True, prewarm=10,
            start_lifetime=random_between(30, 50), start_speed=constant(0.1),
            start_size=nf3(random_between(0.5, 0.9), random_between(0.5, 0.9),
                           random_between(0.5, 0.9)),
            simulation_space="World", max_particles=220, parallel_update=True)
        .at(0.0, 0.5, 0.0)
        .with_emission(rate=constant(2.5))
        .with_shape(box(), scale=(12.0, 1.0, 2.0))
        .with_module("inheritVelocity", {"mode": "CURRENT", "multiply": constant(0.4)})
        .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.05), constant(0))),
            noise=dict(frequency=0.8, position=nf3(0.06)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.5), (0.7, 0.35), (1.0, 0.0)],
                [(0.0, 0.58, 0.54, 0.66), (1.0, 0.42, 0.38, 0.5)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-24.0, -8.0, -24.0), (24.0, 16.0, 24.0)))

    # Violet pinpricks riding the crest — ties the dust to the eclipse palette.
    (fx.particle_emitter(
            "crest_sparks",
            duration=20, looping=True,
            start_lifetime=random_between(40, 60), start_speed=constant(0.05),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="World", max_particles=80, parallel_update=True)
        .at(0.0, 2.0, 0.0)
        .with_emission(rate=constant(0.4))
        .with_shape(box(), scale=(12.0, 1.0, 2.0))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.2, 0.9, 1.8)))
        .with_lights(sky=15, block=15)
        .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.2, 1.0), (0.8, 0.7), (1.0, 0.0)],
            [(0.0, 0.75, 0.6, 1.0), (1.0, 0.5, 0.35, 0.85)]))
        .with_cull_box((-24.0, -8.0, -24.0), (24.0, 16.0, 24.0)))
    return fx


BUILDERS = {
    "expansion_rift_glow.fx": build_expansion_rift_glow,
    "rift_piece_flash.fx": build_rift_piece_flash,
    "growth_front_ribbon.fx": build_growth_front_ribbon,
}


def main() -> int:
    rc = 0
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
