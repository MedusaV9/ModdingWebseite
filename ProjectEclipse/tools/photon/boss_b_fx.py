#!/usr/bin/env python3
"""boss_b_fx — PH-BOSS-B generator: Fog Tyrant + Rift Warden Photon `.fx` assets.

Authors (via fxlib, see tools/photon/README.md) the four IDEAS-boss.md concepts owned by
worker PH-BOSS-B, straight from the ranked-concept specs (docs/plans_v3/plans_v5/photon/
IDEAS-boss.md #2, #6, #3, #7):

    eclipse:boss/tyrant_death_implosion   (#2, + child below — TWO-file law, blocker #3)
    eclipse:boss/fog_debris_puff          (#2 FirstCollision sub-emitter child)
    eclipse:boss/tyrant_blind_burst       (#6 releaseSquall HDR flash)
    eclipse:boss/warden_eye_laser         (#3 beam_emitter volley telegraph, raycast BLOCKS)
    eclipse:boss/warden_glitch_orbit      (#7 REVERSE_SUB/MAX stagger orbit, 40t)

Plus the three textures those concepts need (deterministic, seeded — safe to re-run):

    assets/eclipse/textures/particle/beam_core.png    (4-frame strip, tiles [1,4])
    assets/eclipse/textures/particle/glitch_shard.png (2x2 sheet)
    assets/eclipse/textures/particle/noise_strip.png  (white-noise sparkle)

This script IS the authoring source for these binary .fx blobs (fxlib generator in place
of an editor .fxproj). Run: python3 tools/photon/boss_b_fx.py
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, REPO_ROOT, SEG_EASE_OUT_CREST,
    SEG_LINEAR_DOWN, SEG_LINEAR_UP,
    FxBuilder, blend, box, circle, burst, color, constant, curve, dot, gradient, nf3,
    random_between, random_curve, sphere, sub_emitter, texture_material, validate_file,
)

TEXTURE_DIR = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle"


# ---------------------------------------------------------------------------
# Concept #2 — eclipse:boss/tyrant_death_implosion (+ fog_debris_puff child)
# ---------------------------------------------------------------------------
def build_tyrant_death_implosion() -> FxBuilder:
    """C8 thunderclap beat: inhale -> HDR white-out -> physics debris that bounces off the
    real arena floor and puffs fog where it lands (FirstCollision sub-emitters)."""
    fx = FxBuilder("boss/tyrant_death_implosion")
    cull = ((-16.0, -3.0, -16.0), (16.0, 10.0, 16.0))

    # The storm inhales into the chest core (accelerating inward radial suck).
    (fx.particle_emitter(
            "indraw",
            duration=24, looping=False, max_particles=96,
            start_lifetime=random_between(16, 24), start_speed=constant(0),
            start_size=nf3(random_between(0.15, 0.35), random_between(0.15, 0.35),
                           random_between(0.15, 0.35)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(90))])
       .with_shape(sphere(radius=7.0, thickness=0.15))
       .with_material(texture_material("photon:textures/particle/circle.png",
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(-1.4, 0.0, [(0.0, 1.0, 0.4, 0.9, 0.75, 0.35, 1.0, 0.0)],
                             "lifetime", "value")),
            color_over_lifetime=gradient(
                [(0.0, 0.15), (0.45, 0.9), (1.0, 0.0)],
                [(0.0, 0.9, 0.92, 0.9), (1.0, 0.25, 0.75, 0.75)])))

    # The bloom white-out beat at the moment the inhale completes.
    (fx.particle_emitter(
            "core_flash",
            duration=10, looping=False, start_delay=constant(24), max_particles=2,
            start_lifetime=constant(8), start_speed=constant(0),
            start_size=nf3(4.0, 4.0, 4.0), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material("photon:textures/particle/circle.png",
                                       hdr=(3.0, 3.0, 3.5), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [(0.0, 1.0, 0.1, 0.4, 0.6, 0.12, 1.0, 0.05)],
                                     "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (0.5, 0.9), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0)])))

    # Physics debris: bounces off the real floor, fog-puffs where it first lands.
    (fx.particle_emitter(
            "debris",
            duration=50, looping=False, start_delay=constant(24), max_particles=80,
            start_lifetime=random_between(20, 40), start_speed=random_between(0.6, 1.6),
            start_size=nf3(random_between(0.12, 0.3), random_between(0.12, 0.3),
                           random_between(0.12, 0.3)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(56))])
       .with_shape(sphere(radius=0.6, thickness=1.0))
       .with_material(texture_material("photon:textures/particle/circle.png",
                                       hdr=(1.2, 1.4, 1.6), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.6, length_scale=1.5)
       .with_cull_box(*cull)
       .with_physics(collision=True, removed_when_collided=False, friction=0.99,
                     collided_friction=0.55, gravity=0.5, bounce_chance=0.5,
                     bounce_rate=0.35, bounce_spread=0.15)
       .with_sub_emitters(sub_emitter("eclipse:boss/fog_debris_puff",
                                      event="FirstCollision", probability=0.6,
                                      inherit=("Color",)))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.8, 0.9), (1.0, 0.0)],
                [(0.0, 0.8, 0.95, 1.0), (1.0, 0.4, 0.7, 0.75)])))

    # Ground echo: the concept-1 ring recipe scaled to r=14, teal-white.
    (fx.particle_emitter(
            "ground_ring",
            duration=30, looping=False, start_delay=constant(26), max_particles=4,
            start_lifetime=constant(26), start_speed=constant(0),
            start_size=nf3(1.0, 1.0, 1.0), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material("photon:textures/particle/ring.png",
                                       hdr=(1.2, 1.8, 1.8), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.0, 28.0, [(0.0, 0.04, 0.15, 0.9, 0.6, 1.0, 1.0, 1.0)],
                                     "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
                                         [(0.0, 0.9, 1.0, 1.0), (1.0, 0.3, 0.8, 0.8)])))
    return fx


def build_fog_debris_puff() -> FxBuilder:
    """Sub-emitter child: a small CLOUD-grey alpha-blend fog puff where debris lands."""
    fx = FxBuilder("boss/fog_debris_puff")
    (fx.particle_emitter(
            "puff",
            duration=20, looping=False, max_particles=8,
            start_lifetime=random_between(12, 18), start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(0.3, 0.6), random_between(0.3, 0.6),
                           random_between(0.3, 0.6)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(5))])
       .with_shape(sphere(radius=0.25))
       .with_material(texture_material("photon:textures/particle/smoke.png",
                                       blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0))
       .with_curves(
            # Ease-out bloom to 2x (QUALITY §2 row 15): the puff kicks open on impact
            # and settles — it stamps on every debris bounce, so the ease is visible.
            size_over_lifetime=curve(1.0, 2.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.5), (0.4, 0.4), (1.0, 0.0)],
                [(0.0, 0.75, 0.78, 0.8), (1.0, 0.55, 0.6, 0.62)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #6 — eclipse:boss/tyrant_blind_burst
# ---------------------------------------------------------------------------
def build_tyrant_blind_burst() -> FxBuilder:
    """releaseSquall: over-driven HDR white-out + three staggered fog shells + crown arcs."""
    fx = FxBuilder("boss/tyrant_blind_burst")
    cull = ((-14.0, -2.0, -14.0), (14.0, 8.0, 14.0))

    # Retina-burn flash: HDR 4.0 deliberately over-drives the bloom bright-pass ~4t.
    # (Iris pair-test watch item: drop to 2.5 if the bright-pass clips — IDEAS-boss #6.)
    (fx.particle_emitter(
            "flash_core",
            duration=10, looping=False, max_particles=2,
            start_lifetime=constant(6), start_speed=constant(0),
            start_size=nf3(6.0, 6.0, 6.0), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material("photon:textures/particle/circle.png",
                                       hdr=(4.0, 4.0, 4.0), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [(0.0, 0.3, 0.05, 1.0, 0.5, 0.8, 1.0, 0.65)],
                                     "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (0.5, 0.9), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0)])))

    # Three staggered expanding fog shells (~ the shipped 3/7/12 CLOUD radii).
    # FX-Wave-11 stacking-law pass: 3x60 alpha smoke puffs born on one 0.8 r surface
    # with a near-white (0.85,0.88,0.90) birth tint composited into a second white ball
    # right behind the flash. Now 3x24 over a thick 1.5 r shell, birth tint slate, and
    # the alpha crest trimmed 0.65 -> 0.5 so the shells stay readable as fog.
    (fx.particle_emitter(
            "fog_shells",
            duration=26, looping=False, max_particles=80,
            start_lifetime=random_between(14, 22), start_speed=random_between(0.9, 1.3),
            start_size=nf3(random_between(0.4, 0.8), random_between(0.4, 0.8),
                           random_between(0.4, 0.8)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[
            burst(time=0, count=constant(24)),
            burst(time=5, count=constant(24)),
            burst(time=10, count=constant(24))])
       .with_shape(sphere(radius=1.5, thickness=0.25))
       .with_material(texture_material("photon:textures/particle/smoke.png",
                                       blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(1.0, 2.2, [SEG_LINEAR_UP], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.5), (0.7, 0.5), (1.0, 0.0)],
                [(0.0, 0.227, 0.227, 0.333), (1.0, 0.6, 0.66, 0.7)])))

    # Electric arcs off the crown at release.
    (fx.particle_emitter(
            "crown_arcs",
            duration=8, looping=False, max_particles=12,
            start_lifetime=random_between(4, 7), start_speed=random_between(0.4, 0.9),
            start_size=nf3(random_between(0.06, 0.12), random_between(0.06, 0.12),
                           random_between(0.06, 0.12)),
            simulation_space="World")
       .at(0.0, 3.4, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(10))])
       .with_shape(circle(radius=1.6))
       .with_material(texture_material("photon:textures/particle/circle.png",
                                       hdr=(2.2, 2.2, 2.6), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.2, length_scale=2.0)
       .with_cull_box(*cull)
       .with_curves(
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0), (1.0, 0.8, 0.85, 1.0)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #3 — eclipse:boss/warden_eye_laser
# ---------------------------------------------------------------------------
def build_warden_eye_laser() -> FxBuilder:
    """20t volley telegraph: raycast-clipped violet beam (local -Z, blocks stop it) + motes
    sucked INTO the eye. Aimed by the client via SpawnOptions rotation (yaw in payload a)."""
    fx = FxBuilder("boss/warden_eye_laser")

    beam = fx.beam_emitter(
        "eye_laser",
        end=(0.0, 0.0, -24.0), width=0.2, duration=20, looping=False, emit_rate=0,
        raycast="BLOCKS", raycast_block_mode="VISUAL", raycast_fluid_mode="NONE",
        color_nf=gradient([(0.0, 0.85), (1.0, 0.35)],
                          [(0.0, 0.75, 0.3, 1.0), (1.0, 0.3, 0.1, 0.5)]))
    # Thin flicker -> committed beam right before release (constructor only takes scalars).
    beam._config["width"] = curve(0.04, 0.28, [(0.0, 0.15, 0.55, 0.35, 0.9, 1.0, 1.0, 1.0)])
    (beam.with_material(texture_material("eclipse:textures/particle/beam_core.png",
                                         hdr=(2.0, 0.9, 3.0), blend=BLEND_ADDITIVE))
         .with_uv_animation(tiles=(1, 4), animation="SingleRow",
                            frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]))
         .with_lights(sky=15, block=15)
         .with_cull_box((-1.0, -1.0, -26.0), (1.0, 3.0, 1.0)))

    # Charge tell: violet motes pulled INTO the eye.
    (fx.particle_emitter(
            "eye_charge",
            duration=20, looping=False, max_particles=64,
            start_lifetime=random_between(8, 12), start_speed=constant(0),
            start_size=nf3(random_between(0.04, 0.1), random_between(0.04, 0.1),
                           random_between(0.04, 0.1)),
            simulation_space="Local")
       .with_emission(rate=constant(2.5))
       .with_shape(sphere(radius=0.9, thickness=0.0))
       .with_material(texture_material("photon:textures/particle/circle.png",
                                       hdr=(1.5, 0.8, 2.2), blend=BLEND_ADDITIVE))
       .with_cull_box((-1.0, -1.0, -26.0), (1.0, 3.0, 1.0))
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-0.5)),
            color_over_lifetime=gradient([(0.0, 0.9), (1.0, 0.0)],
                                         [(0.0, 0.75, 0.5, 1.0), (1.0, 0.5, 0.2, 0.8)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #7 — eclipse:boss/warden_glitch_orbit
# ---------------------------------------------------------------------------
def build_warden_glitch_orbit() -> FxBuilder:
    """P2 weakpoint (40t = STAGGER_TICKS): obsidian glitch shards orbit the core, REVERSE_SUB
    pass darkens the scene into 'holes in reality' + additive violet rims, MAX-blend static."""
    fx = FxBuilder("boss/warden_glitch_orbit")
    cull = ((-3.0, -1.0, -3.0), (3.0, 4.0, 3.0))

    # FX-Wave-11 stacking-law pass: 22 shards on a 1.1 r shell at full opacity stacked
    # their additive violet rims (hdr 2.0 blue) into a solid glowing shell instead of
    # discrete holes. Count 22->12, shards kept small (max 0.22), rim hdr nerfed to
    # ~1.45 and the alpha peak dropped to 0.7 via startColor (this emitter has no
    # colorOverLifetime gradient — the peak WAS the implicit opaque-white default).
    (fx.particle_emitter(
            "glitch_shards",
            duration=40, looping=False, max_particles=26,
            start_lifetime=random_between(30, 40), start_speed=constant(0),
            start_size=nf3(random_between(0.1, 0.22), random_between(0.1, 0.22),
                           random_between(0.1, 0.22)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            start_color=color(0xB3FFFFFF),
            simulation_space="Local")
       .at(0.0, 1.6, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(12))])
       .with_shape(sphere(radius=1.1, thickness=0.2))
       # Pass 1: REVERSE_SUB subtracts scene color under shard alpha (the void bite).
       .with_material(texture_material("eclipse:textures/particle/glitch_shard.png",
                                       blend=blend("SRC_ALPHA", "ONE", "ONE", "ZERO",
                                                   "REVERSE_SUB")))
       # Pass 2: additive violet rims (discard eats the fill, leaving edges).
       .with_material(texture_material("eclipse:textures/particle/glitch_shard.png",
                                       discard=0.45, hdr=(1.2, 0.5, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(order_in_layer=1)
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(2.5, 4.5), constant(0))),
            rotation_over_lifetime=dict(roll=random_between(-25.0, 25.0)),
            noise=dict(frequency=3.0, quality="Noise3D", position=nf3(0.12),
                       remap_curve=curve(0.0, 1.0,
                                         [(0.0, 0.0, 0.45, 0.0, 0.55, 1.0, 1.0, 1.0)])),
            uv_animation=dict(tiles=(2, 2), animation="WholeSheet",
                              frame_over_time=random_curve(0.0, 1.0, [SEG_LINEAR_UP],
                                                           [SEG_LINEAR_DOWN]),
                              cycle=3.0)))

    # MAX-blend static flicker: lighten-only sparkle that never over-accumulates.
    (fx.particle_emitter(
            "static_veil",
            duration=40, looping=False, max_particles=16,
            start_lifetime=random_between(4, 7), start_speed=constant(0),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="Local")
       .at(0.0, 1.3, 0.0)
       .with_emission(rate=constant(1.0))
       .with_shape(box(emit_from="Shell"), scale=nf3(1.2, 2.6, 1.2))
       .with_material(texture_material("eclipse:textures/particle/noise_strip.png",
                                       blend=blend("SRC_ALPHA", "ONE", "ONE", "ZERO", "MAX")))
       .with_cull_box(*cull))
    return fx


# ---------------------------------------------------------------------------
# Textures (deterministic; PIL)
# ---------------------------------------------------------------------------
def write_textures() -> list:
    from PIL import Image, ImageDraw

    written = []

    # beam_core.png — 4-frame vertical strip (tiles [1,4]): soft horizontal core line with
    # per-frame ripple so the SingleRow scroll reads as flowing energy.
    frame_w, frame_h, frames = 64, 64, 4
    img = Image.new("RGBA", (frame_w, frame_h * frames), (0, 0, 0, 0))
    px = img.load()
    for f in range(frames):
        core_w = (3.0, 4.5, 3.5, 5.5)[f]
        for x in range(frame_w):
            ripple = 0.75 + 0.25 * math.sin((x / frame_w) * math.tau * 2 + f * math.pi / 2)
            for y in range(frame_h):
                d = abs(y - frame_h / 2 + 0.5)
                a = math.exp(-((d / core_w) ** 2)) + 0.35 * math.exp(-((d / (core_w * 3)) ** 2))
                a = min(1.0, a * ripple)
                px[x, f * frame_h + y] = (255, 255, 255, int(a * 255))
    path = TEXTURE_DIR / "beam_core.png"
    img.save(path)
    written.append(path)

    # glitch_shard.png — 2x2 sheet of hard-edged angular shards (flipbook flicker frames).
    rng = random.Random(0xB055B)
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for cell in range(4):
        cx, cy = (cell % 2) * 64 + 32, (cell // 2) * 64 + 32
        points = []
        n = rng.randint(5, 7)
        for i in range(n):
            ang = (i / n) * math.tau + rng.uniform(-0.25, 0.25)
            r = rng.uniform(10, 28)
            points.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
        draw.polygon(points, fill=(255, 255, 255, 255))
        # A jitter notch bitten out of each shard: reads as datamosh damage.
        bx, by = rng.uniform(-14, 14), rng.uniform(-14, 14)
        draw.rectangle((cx + bx - 5, cy + by - 3, cx + bx + 5, cy + by + 3),
                       fill=(0, 0, 0, 0))
    path = TEXTURE_DIR / "glitch_shard.png"
    img.save(path)
    written.append(path)

    # noise_strip.png — white-noise sparkle for the MAX-blend static veil.
    rng = random.Random(0x57A71C)
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    for x in range(64):
        for y in range(64):
            v = rng.random()
            a = int(255 * v * v) if v > 0.55 else 0
            px[x, y] = (255, 255, 255, a)
    path = TEXTURE_DIR / "noise_strip.png"
    img.save(path)
    written.append(path)
    return written


BUILDERS = {
    "boss/tyrant_death_implosion.fx": build_tyrant_death_implosion,
    "boss/fog_debris_puff.fx": build_fog_debris_puff,
    "boss/tyrant_blind_burst.fx": build_tyrant_blind_burst,
    "boss/warden_eye_laser.fx": build_warden_eye_laser,
    "boss/warden_glitch_orbit.fx": build_warden_glitch_orbit,
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
