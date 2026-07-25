#!/usr/bin/env python3
"""PH-BOSS-A — Herald + Ferryman Photon `.fx` assets (IDEAS-boss.md concepts 1, 4, 5, 8, 9).

Programmatic source of truth for four repo-shipped effects (the fxlib script IS the
authoring artifact — re-run it instead of hand-editing the binary `.fx` blobs):

    eclipse:boss/roar_shockwave     — shared boss roar ring (concept 1, CUE_BOSS_ROAR)
    eclipse:boss/herald_shard_trail — shard ara-trail ribbon (concept 5, client seam)
    eclipse:boss/ferry_lantern_swarm— P2 soul-lantern model swarm (concept 4)
    eclipse:boss/ferry_oar_tear     — oar-sweep water-tear arc (concept 8, yaw in `a`)
    eclipse:boss/ferry_kneel_corona — P2 kneel corona, re-fire sustained (concept 9)

Also generates `eclipse:textures/particle/ring_soft.png` (soft radial ring falloff, the
concept-1 ring texture) deterministically — no image tooling required.

Run:  python3 tools/photon/fx_boss_herald_ferryman.py
Then: python3 tools/photon/fxlib.py validate src/main/resources/assets/eclipse/fx/boss/*.fx
"""
from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, F, I, L, BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, REPO_ROOT, FxBuilder,
    block_atlas_material, burst, circle, constant, curve, cylinder, dot, function_shape,
    gradient, mesh, nf3, random_between, rom, sphere, texture_material, validate_file,
)

BOSS_FX_DIR = FX_ASSETS_DIR / "boss"
RING_TEXTURE = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle/ring_soft.png"

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"


# ---------------------------------------------------------------------------
# ring_soft.png — 64x64 white ring, gaussian alpha falloff (stdlib PNG writer)
# ---------------------------------------------------------------------------
def _png_chunk(tag: bytes, data: bytes) -> bytes:
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_ring_soft(path: Path, size: int = 64, peak: float = 0.6, sigma: float = 0.13) -> None:
    rows = []
    for y in range(size):
        row = bytearray([0])  # filter 0 (None)
        for x in range(size):
            dx = (x + 0.5) / size * 2.0 - 1.0
            dy = (y + 0.5) / size * 2.0 - 1.0
            r = math.sqrt(dx * dx + dy * dy)
            alpha = int(round(255.0 * math.exp(-((r - peak) ** 2) / (2.0 * sigma * sigma))))
            row += bytes((255, 255, 255, alpha))
        rows.append(bytes(row))
    png = (b"\x89PNG\r\n\x1a\n"
           + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + _png_chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
           + _png_chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


# ---------------------------------------------------------------------------
# Concept 1 — eclipse:boss/roar_shockwave (shared HDR roar ring, one-shot 30t)
# ---------------------------------------------------------------------------
def build_roar_shockwave() -> FxBuilder:
    fx = FxBuilder("boss/roar_shockwave")
    violet_white = gradient([(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
                            [(0.0, 0.9, 0.8, 1.0), (1.0, 0.45, 0.2, 0.7)])

    # Ground-hugging expanding ring (Horizontal quad, fast-out ease to r~15).
    (fx.particle_emitter(
            "roar_ring",
            duration=30, looping=False, max_particles=4,
            start_lifetime=constant(26), start_speed=constant(0.0),
            start_size=nf3(1.0, 1.0, 1.0), simulation_space="World")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=1, cycles=1, probability=1.0)])
       .with_shape(dot())
       .with_material(texture_material("eclipse:textures/particle/ring_soft.png",
                                       hdr=(1.6, 1.1, 2.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", facing_mode="DEFAULT", shade=False,
                      vertex_sorting="NONE")
       .with_cull_box((-32.0, -2.0, -32.0), (32.0, 12.0, 32.0))
       .with_curves(
            size_over_lifetime=curve(0.0, 30.0, [(0.0, 0.04, 0.15, 0.9, 0.6, 1.0, 1.0, 1.0)],
                                     "lifetime", "size"),
            color_over_lifetime=violet_white))

    # Vertical light column (X shrinks 1 -> 0.1 over life; forced-fullbright).
    (fx.particle_emitter(
            "roar_column",
            duration=30, looping=False, max_particles=4,
            start_lifetime=constant(18), start_speed=constant(0.0),
            start_size=nf3(2.5, 10.0, 2.5), simulation_space="World")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=1, cycles=1, probability=1.0)])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.6, 1.1, 2.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard", vertex_sorting="NONE")
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 11.0, 4.0))
       .with_curves(
            size_over_lifetime=nf3(
                curve(0.1, 1.0, [(0.0, 1.0, 0.33, 0.66, 0.66, 0.33, 1.0, 0.0)],
                      "lifetime", "size"),
                constant(1.0), constant(1.0)),
            color_over_lifetime=violet_white)
       .with_lights(sky=15, block=15))

    # Radial spark sheet off a spherical shell (gravity-arced, mild HDR).
    (fx.particle_emitter(
            "roar_sparks",
            duration=30, looping=False, max_particles=96,
            start_lifetime=random_between(10, 22),
            start_speed=random_between(0.5, 1.1),
            start_size=nf3(random_between(0.05, 0.12), random_between(0.05, 0.12),
                           random_between(0.05, 0.12)),
            simulation_space="World")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=2, count=64, cycles=1, probability=1.0)])
       .with_shape(sphere(radius=1.2, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(0.8, 0.6, 1.2), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 11.0, 4.0))
       .with_physics(collision=True, friction=0.97, gravity=0.2, bounce_chance=0.0)
       .with_curves(
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0), (1.0, 0.45, 0.2, 0.7)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 5 — eclipse:boss/herald_shard_trail (entity-bound ara ribbon; loop is
# safe: the runtime dies with the projectile ≤ ~5 s later)
# ---------------------------------------------------------------------------
def build_herald_shard_trail() -> FxBuilder:
    fx = FxBuilder("boss/herald_shard_trail")
    (fx.ara_trail_emitter(
            "shard_ribbon",
            duration=100, looping=True,
            space="World", alignment="View", sorting="NewerOnTop",
            thickness=0.18, smoothness=4, high_quality_corners=False,
            time=0.45, time_interval=0.05, min_distance=0.05,  # SECONDS (ara exception)
            texture_mode="Stretch",
            thickness_over_length=curve(
                0.0, 1.0, [(0.0, 1.0, 0.4, 0.85, 0.9, 0.2, 1.0, 0.0)], "length", "thickness"),
            color_over_length=gradient(
                [(0.0, 0.9), (1.0, 0.0)],
                [(0.0, 1.0, 0.95, 1.0), (0.35, 0.75, 0.4, 1.0), (1.0, 0.3, 0.1, 0.5)]),
            physics=dict(gravity=(0.0, -0.4, 0.0), inertia=0.25,
                         velocity_smoothing=0.75, damping=0.8))
       .with_material(texture_material(CIRCLE, hdr=(1.3, 0.7, 2.0), blend=BLEND_ADDITIVE))
       .with_cull_box((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0)))
    return fx


# ---------------------------------------------------------------------------
# Concept 4 — eclipse:boss/ferry_lantern_swarm (soul-lantern Model particles)
# ---------------------------------------------------------------------------
def build_ferry_lantern_swarm() -> FxBuilder:
    fx = FxBuilder("boss/ferry_lantern_swarm")

    # 24 actual soul-lantern models rise in a slow counter-clockwise carousel.
    # Mesh shape doubles as the baked-model source for renderMode Model (FX_FORMAT §3.2);
    # shape scale spreads the emission points to roughly the spec's r=2.2 circle.
    (fx.particle_emitter(
            "lantern_swarm",
            duration=80, looping=False, max_particles=24,
            start_lifetime=random_between(50, 70), start_speed=constant(0.05),
            start_size=nf3(random_between(0.5, 0.7), random_between(0.5, 0.7),
                           random_between(0.5, 0.7)),
            start_rotation=nf3(constant(0), random_between(0.0, 360.0), constant(0)),
            simulation_space="Local")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=6, cycles=1, probability=1.0),
                              burst(time=10, count=6, cycles=3, interval=10, probability=1.0)])
       .with_shape(mesh("block/soul_lantern", emit_from="Triangle"), scale=nf3(4.4))
       .with_material(block_atlas_material(blend=BLEND_ALPHA, cull=True, depth_test=True,
                                           depth_mask=True))
       .with_renderer(render_mode="Model", use_block_uv=True, model_pivot=(0.5, 0.5, 0.5),
                      facing_mode="ROTATE_Y", shade=True)
       .with_cull_box((-8.0, -1.0, -8.0), (8.0, 7.0, 8.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.02, 0.05), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.35), constant(0)),
                offset=nf3(0)),
            rotation_over_lifetime=dict(yaw=random_between(-3.0, 3.0)),
            noise=dict(frequency=0.5, quality="Noise2D",
                       position=nf3(constant(0.04), constant(0.02), constant(0.04)))))

    # Teal soul-flame motes leaking off the ring under the lanterns.
    (fx.particle_emitter(
            "soul_leak",
            duration=80, looping=False, max_particles=64,
            start_lifetime=random_between(20, 30), start_speed=random_between(0.01, 0.05),
            start_size=nf3(random_between(0.06, 0.14), random_between(0.06, 0.14),
                           random_between(0.06, 0.14)),
            simulation_space="Local")
       .with_emission(rate=constant(1.2))
       .with_shape(circle(radius=2.4))
       .with_material(texture_material(CIRCLE, hdr=(0.4, 1.3, 1.2), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-8.0, -1.0, -8.0), (8.0, 7.0, 8.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.02, 0.05), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.8), (1.0, 0.0)],
                [(0.0, 0.4, 1.0, 0.9), (1.0, 0.15, 0.5, 0.55)]))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# Concept 8 — eclipse:boss/ferry_oar_tear (function-shape half-circle sweep).
# Local −Z is FORWARD (the yaw-from-a executor rotation aligns local −Z with the
# boss's look): the arc sweeps left (−X) through front (−Z) to right (+X) over 8t.
# ---------------------------------------------------------------------------
def _tear_arc_shape():
    return function_shape(
        x="-4.5*cos(t*PI)", y="0.1", z="-4.5*sin(t*PI)",
        speed_x="-0.6*cos(t*PI)", speed_y="0.35+0.3*randomA", speed_z="-0.6*sin(t*PI)")


def build_ferry_oar_tear() -> FxBuilder:
    fx = FxBuilder("boss/ferry_oar_tear")

    # Dense spray arc; every 2nd droplet drags a short ara ribbon (torn-water smear);
    # droplets die on deck contact so live counts stay tiny.
    tear_arc = (fx.particle_emitter(
            "tear_arc",
            duration=8, looping=False, max_particles=60,
            start_lifetime=random_between(10, 18), start_speed=constant(1.0),
            start_size=nf3(random_between(0.1, 0.25), random_between(0.1, 0.25),
                           random_between(0.1, 0.25)),
            simulation_space="World")
       .with_emission(rate=constant(7.0))
       .with_shape(_tear_arc_shape())
       .with_material(texture_material(CIRCLE, hdr=(0.5, 1.0, 1.1), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-7.0, -2.0, -7.0), (7.0, 4.0, 7.0))
       .with_physics(collision=True, removed_when_collided=True, gravity=0.45,
                     bounce_chance=0.0)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.9), (1.0, 0.0)],
                [(0.0, 0.75, 0.95, 1.0), (1.0, 0.1, 0.45, 0.5)])))
    tear_arc.with_module("trails", {
        "ratio": F(0.5),
        "lifetime": constant(0.5),
        "dieWithParticles": B(0),
        "sizeAffectsWidth": B(1),
        "sizeAffectsLifetime": B(0),
        "inheritParticleColor": B(1),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            "space": "World",
            "thickness": F(0.08),
            "time": F(0.25),               # seconds (ara exception)
            "smoothness": I(3),
            "textureMode": "Stretch",
            "thicknessOverLength": curve(
                0.0, 1.0, [(0.0, 1.0, 0.4, 0.8, 0.9, 0.15, 1.0, 0.0)], "length", "thickness"),
            "physicsSetting": {
                "warmup": F(0.0),
                "gravity": L([F(0.0), F(-0.3), F(0.0)]),
                "inertia": F(0.0),
                "velocitySmoothing": F(0.75),
                "damping": F(0.8)},
            "renderer": {
                "materials": rom([texture_material(CIRCLE, hdr=(0.5, 1.0, 1.1),
                                                   blend=BLEND_ADDITIVE)]),
                "layer": "Translucent", "cull": {"_enable": B(0)},
                "orderInLayer": I(0), "vertexSortingMode": "NONE"}}})

    # HDR sparkle highlights riding the same arc.
    (fx.particle_emitter(
            "tear_glint",
            duration=8, looping=False, max_particles=12,
            start_lifetime=random_between(4, 6), start_speed=constant(1.0),
            start_size=nf3(0.05, 0.05, 0.05), simulation_space="World")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=2, count=8, cycles=1, probability=1.0)])
       .with_shape(_tear_arc_shape())
       .with_material(texture_material(CIRCLE, hdr=(1.2, 1.8, 2.0), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-7.0, -2.0, -7.0), (7.0, 4.0, 7.0)))
    return fx


# ---------------------------------------------------------------------------
# Concept 9 — eclipse:boss/ferry_kneel_corona (100t one-shot, re-fired on the
# 20t crew cadence; allowMulti=false dedups re-sends while the runtime lives)
# ---------------------------------------------------------------------------
def build_ferry_kneel_corona() -> FxBuilder:
    fx = FxBuilder("boss/ferry_kneel_corona")

    # Slow teal halo orbiting the kneel (Template-B cylinder Loop recipe).
    (fx.particle_emitter(
            "corona_halo",
            duration=100, looping=False, prewarm=10, max_particles=96,
            start_lifetime=random_between(30, 50), start_speed=constant(0.02),
            start_size=nf3(random_between(0.12, 0.25), random_between(0.12, 0.25),
                           random_between(0.12, 0.25)),
            simulation_space="Local")
       .with_emission(rate=constant(0.8))
       .with_shape(cylinder(radius=1.3, thickness=0.1, arc_mode="Loop", arc_speed=0.5))
       .with_material(texture_material(CIRCLE, hdr=(0.3, 0.9, 0.8), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 5.0, 4.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.015, 0.04), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.5), constant(0)),
                offset=nf3(0)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.6), (0.8, 0.5), (1.0, 0.0)],
                [(0.0, 0.4, 0.95, 0.85), (1.0, 0.15, 0.5, 0.55)]))
       .with_lights(sky=15, block=15))

    # ONE faint ghost-bell dome; deliberately dim (no HDR — the read is "inert").
    (fx.particle_emitter(
            "invuln_shell",
            duration=100, looping=False, max_particles=4,
            start_lifetime=constant(90), start_speed=constant(0.0),
            start_size=nf3(3.2, 3.2, 3.2), simulation_space="Local")
       .with_emission(rate=constant(0.25),
                      bursts=[burst(time=0, count=1, cycles=1, probability=1.0)])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 5.0, 4.0))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.12), (0.5, 0.07), (0.75, 0.12), (1.0, 0.0)],
                [(0.0, 0.5, 0.75, 0.75), (1.0, 0.4, 0.6, 0.65)])))
    return fx


BUILDERS = {
    "roar_shockwave.fx": build_roar_shockwave,
    "herald_shard_trail.fx": build_herald_shard_trail,
    "ferry_lantern_swarm.fx": build_ferry_lantern_swarm,
    "ferry_oar_tear.fx": build_ferry_oar_tear,
    "ferry_kneel_corona.fx": build_ferry_kneel_corona,
}


def main() -> int:
    write_ring_soft(RING_TEXTURE)
    print(f"WROTE {RING_TEXTURE.relative_to(REPO_ROOT)}")
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = BOSS_FX_DIR / name
        raw_len, gz_len = builder_fn().write(path)  # write() round-trip-validates
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
