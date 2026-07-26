#!/usr/bin/env python3
"""F-053 — Herald summon-cutscene Photon `.fx` assets.

Programmatic source of truth for the two effects the spawn cutscene
(`sequence/HeraldSummonSequence.java`) fires at the summon point — the fxlib script IS
the authoring artifact, re-run it instead of hand-editing the gzip-NBT blobs:

    eclipse:boss/herald_summon_pillar — light+ash column at the spawn point (beat B)
    eclipse:boss/herald_glyph_swirl   — two counter-rotating glyph bands (beat B/C)

Also writes `eclipse:textures/particle/herald_glyph.png` deterministically (a broken
rune ring — radial ticks around a cracked circle over a vertical bar); no image tooling
required, same stdlib PNG writer as `fx_boss_herald_ferryman.py`.

Run:  python3 tools/photon/fx_herald_summon.py
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
    BLEND_ADDITIVE, FX_ASSETS_DIR, REPO_ROOT, FxBuilder, burst, circle, constant, curve,
    cylinder, dot, gradient, nf3, random_between, texture_material, validate_file,
)

BOSS_FX_DIR = FX_ASSETS_DIR / "boss"
GLYPH_TEXTURE = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle/herald_glyph.png"

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
RING_SOFT = "eclipse:textures/particle/ring_soft.png"
GLYPH = "eclipse:textures/particle/herald_glyph.png"

# Herald violet-white, the palette the roar ring and shard trail already use.
VIOLET_WHITE = ((0.0, 0.9, 0.8, 1.0), (1.0, 0.45, 0.2, 0.7))


# ---------------------------------------------------------------------------
# herald_glyph.png — 64x64 rune mask (stdlib PNG writer, same as ring_soft).
# ---------------------------------------------------------------------------
def _png_chunk(tag: bytes, data: bytes) -> bytes:
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def _write_png(path: Path, size: int, alpha_fn) -> None:
    """White-RGB alpha-mask PNG; alpha_fn(nx, ny) -> 0..1 on normalized [-1, 1] coords."""
    rows = []
    for y in range(size):
        row = bytearray([0])  # filter 0 (None)
        for x in range(size):
            nx = (x + 0.5) / size * 2.0 - 1.0
            ny = (y + 0.5) / size * 2.0 - 1.0
            a = max(0.0, min(1.0, alpha_fn(nx, ny)))
            row += bytes((255, 255, 255, int(round(255.0 * a))))
        rows.append(bytes(row))
    png = (b"\x89PNG\r\n\x1a\n"
           + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + _png_chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
           + _png_chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def write_herald_glyph(path: Path, size: int = 64) -> None:
    """A cult sigil that still reads at 8 px on screen: one cracked rune ring (two gaps),
    eight radial ticks and a short vertical bar through the middle."""
    def alpha(nx, ny):
        r = math.sqrt(nx * nx + ny * ny)
        if r >= 1.0:
            return 0.0
        theta = math.atan2(ny, nx)
        edge = min(1.0, (1.0 - r) / 0.06)

        # Cracked ring at r = 0.62, two gaps 180 deg apart.
        gap = min(abs(((theta % math.pi) - math.pi * 0.5)), 0.22) / 0.22
        ring = math.exp(-((r - 0.62) / 0.07) ** 2) * gap

        # Eight radial ticks between r = 0.72 and 0.95.
        tick_phase = (theta * 8.0 / (2.0 * math.pi)) % 1.0
        tick_near = min(tick_phase, 1.0 - tick_phase) / 0.06
        ticks = max(0.0, 1.0 - tick_near) if 0.72 <= r <= 0.95 else 0.0

        # Vertical bar through the core.
        bar = math.exp(-(nx / 0.07) ** 2) * (1.0 if abs(ny) < 0.45 else 0.0)

        return min(1.0, ring + 0.85 * ticks + 0.7 * bar) * edge
    _write_png(path, size, alpha)


# ---------------------------------------------------------------------------
# eclipse:boss/herald_summon_pillar — the announcement column (one-shot 120t).
# The Herald arrives as a hole in the sky first: a light shaft, ash torn up
# around it, and one ground ring marking the dais it will hover over.
# ---------------------------------------------------------------------------
def build_herald_summon_pillar() -> FxBuilder:
    fx = FxBuilder("boss/herald_summon_pillar")
    violet_white = gradient([(0.0, 0.0), (0.12, 1.0), (0.75, 0.85), (1.0, 0.0)], list(VIOLET_WHITE))

    # The shaft itself: one tall forced-fullbright quad that snaps open in ~6t, holds,
    # then narrows to a thread as the boss takes over the moment.
    (fx.particle_emitter(
            "pillar_core",
            duration=120, looping=False, max_particles=4,
            start_lifetime=constant(110), start_speed=constant(0.0),
            start_size=nf3(3.2, 26.0, 3.2), simulation_space="World")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=1, cycles=1, probability=1.0)])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.7, 1.1, 2.4), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard", vertex_sorting="NONE")
       .with_cull_box((-6.0, -1.0, -6.0), (6.0, 30.0, 6.0))
       .with_curves(
            size_over_lifetime=nf3(
                curve(0.12, 1.0, [(0.0, 0.15, 0.05, 1.0, 0.1, 1.0, 0.35, 1.0),
                                  (0.35, 1.0, 0.6, 0.7, 0.8, 0.25, 1.0, 0.0)],
                      "lifetime", "size"),
                constant(1.0), constant(1.0)),
            color_over_lifetime=violet_white)
       .with_lights(sky=15, block=15))

    # Ash and ember flakes torn up out of the dais all around the shaft.
    (fx.particle_emitter(
            "ash_updraft",
            duration=120, looping=False, max_particles=200,
            start_lifetime=random_between(40, 80),
            start_speed=random_between(0.05, 0.2),
            start_size=nf3(random_between(0.08, 0.22), random_between(0.08, 0.22),
                           random_between(0.08, 0.22)),
            start_rotation=nf3(constant(0), random_between(0.0, 360.0), constant(0)),
            simulation_space="World")
       .with_emission(rate=constant(3.0),
                      bursts=[burst(time=0, count=40, cycles=1, probability=1.0)])
       .with_shape(circle(radius=5.0, thickness=0.55))
       .with_material(texture_material(SMOKE, hdr=(0.35, 0.2, 0.5), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-10.0, -1.0, -10.0), (10.0, 30.0, 10.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.12, 0.3), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.25), constant(0)),
                offset=nf3(0)),
            rotation_over_lifetime=dict(roll=random_between(-2.5, 2.5)),
            noise=dict(frequency=0.4, quality="Noise2D",
                       position=nf3(constant(0.06), constant(0.03), constant(0.06))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.9), (0.7, 0.6), (1.0, 0.0)],
                [(0.0, 0.85, 0.75, 1.0), (0.5, 0.5, 0.25, 0.75), (1.0, 0.25, 0.12, 0.3)])))

    # Ground ring marking the arena the Herald is about to claim.
    (fx.particle_emitter(
            "dais_ring",
            duration=120, looping=False, max_particles=4,
            start_lifetime=constant(40), start_speed=constant(0.0),
            start_size=nf3(1.0, 1.0, 1.0), simulation_space="World")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=1, cycles=1, probability=1.0)])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(1.5, 1.0, 2.1), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", facing_mode="DEFAULT", shade=False,
                      vertex_sorting="NONE")
       .with_cull_box((-24.0, -2.0, -24.0), (24.0, 8.0, 24.0))
       .with_curves(
            size_over_lifetime=curve(0.0, 22.0, [(0.0, 0.05, 0.15, 0.9, 0.6, 1.0, 1.0, 1.0)],
                                     "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.9), (0.6, 0.5), (1.0, 0.0)],
                                         list(VIOLET_WHITE))))
    return fx


# ---------------------------------------------------------------------------
# eclipse:boss/herald_glyph_swirl — two counter-rotating rune bands (one-shot
# 140t). Fired one beat after the pillar and once more at the materialisation,
# where the tighter inner band reads as the shape pulling itself together.
# ---------------------------------------------------------------------------
def build_herald_glyph_swirl() -> FxBuilder:
    fx = FxBuilder("boss/herald_glyph_swirl")
    rune_fade = gradient([(0.0, 0.0), (0.2, 1.0), (0.75, 0.8), (1.0, 0.0)], list(VIOLET_WHITE))

    # Wide slow band low over the dais (cylinder Loop arc = evenly spaced glyphs).
    (fx.particle_emitter(
            "glyph_band_outer",
            duration=140, looping=False, max_particles=48,
            start_lifetime=random_between(50, 80), start_speed=constant(0.02),
            start_size=nf3(random_between(0.55, 0.9), random_between(0.55, 0.9),
                           random_between(0.55, 0.9)),
            start_rotation=nf3(constant(0), constant(0), random_between(-20.0, 20.0)),
            simulation_space="World")
       .with_emission(rate=constant(0.9))
       .with_shape(cylinder(radius=4.6, thickness=0.12, arc_mode="Loop", arc_speed=0.6),
                   position=nf3(constant(0), constant(1.2), constant(0)))
       .with_material(texture_material(GLYPH, hdr=(1.3, 0.8, 2.0), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", facing_mode="DEFAULT", shade=False,
                      vertex_sorting="NONE")
       .with_cull_box((-10.0, -2.0, -10.0), (10.0, 16.0, 10.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.03, 0.07), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.45), constant(0)),
                offset=nf3(0)),
            rotation_over_lifetime=dict(roll=random_between(0.8, 2.0)),
            color_over_lifetime=rune_fade)
       .with_lights(sky=15, block=15))

    # Tight fast band climbing the shaft the other way — the two together read as a
    # cage closing around whatever is arriving.
    (fx.particle_emitter(
            "glyph_band_inner",
            duration=140, looping=False, max_particles=36,
            start_lifetime=random_between(40, 65), start_speed=constant(0.02),
            start_size=nf3(random_between(0.3, 0.5), random_between(0.3, 0.5),
                           random_between(0.3, 0.5)),
            simulation_space="World")
       .with_emission(rate=constant(0.8),
                      bursts=[burst(time=20, count=8, cycles=1, probability=1.0)])
       .with_shape(cylinder(radius=1.9, thickness=0.1, arc_mode="Loop", arc_speed=-1.1),
                   position=nf3(constant(0), constant(2.4), constant(0)))
       .with_material(texture_material(GLYPH, hdr=(1.6, 1.0, 2.3), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard", vertex_sorting="NONE")
       .with_cull_box((-6.0, -2.0, -6.0), (6.0, 18.0, 6.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.1, 0.18), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(-0.8), constant(0)),
                offset=nf3(0)),
            rotation_over_lifetime=dict(roll=random_between(-3.0, -1.0)),
            color_over_lifetime=rune_fade)
       .with_lights(sky=15, block=15))

    # Sparse motes so the bands are not floating in clean air.
    (fx.particle_emitter(
            "glyph_dust",
            duration=140, looping=False, max_particles=64,
            start_lifetime=random_between(25, 45), start_speed=random_between(0.01, 0.05),
            start_size=nf3(random_between(0.05, 0.11), random_between(0.05, 0.11),
                           random_between(0.05, 0.11)),
            simulation_space="World")
       .with_emission(rate=constant(1.2))
       .with_shape(circle(radius=4.2, thickness=0.8))
       .with_material(texture_material(CIRCLE, hdr=(1.0, 0.6, 1.6), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-10.0, -2.0, -10.0), (10.0, 16.0, 10.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.04, 0.1), constant(0))),
            color_over_lifetime=gradient([(0.0, 0.0), (0.25, 0.85), (1.0, 0.0)],
                                         list(VIOLET_WHITE))))
    return fx


BUILDERS = {
    "herald_summon_pillar.fx": build_herald_summon_pillar,
    "herald_glyph_swirl.fx": build_herald_glyph_swirl,
}


def main() -> int:
    write_herald_glyph(GLYPH_TEXTURE)
    print(f"WROTE {GLYPH_TEXTURE.relative_to(REPO_ROOT)}")
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = BOSS_FX_DIR / name
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
