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
concept-1 ring texture — 256x256: the roar ring scales to r~30 blocks, 64 px banded up
close, PHOTON-QUALITY §4) and `eclipse:textures/particle/dome_faint.png` (the concept-9
invuln-shell dome, previously a smoke.png stand-in) deterministically — no image
tooling required.

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
    gradient, mesh, nf3, random_between, random_curve, rom, sphere, texture_material,
    validate_file,
)

BOSS_FX_DIR = FX_ASSETS_DIR / "boss"
RING_TEXTURE = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle/ring_soft.png"
DOME_TEXTURE = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle/dome_faint.png"

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
DOME_FAINT = "eclipse:textures/particle/dome_faint.png"


# ---------------------------------------------------------------------------
# Ara-trail toggle groups — the ONE reason `section`/`physicsSetting` never did
# anything in this repo (FX-Wave-13 A4 finding).
#
# `TrailSection` and `AraPhysicsSetting` both extend Photon's `ToggleGroup`, i.e.
# LDLib2 `IToggleConfigurable`. Its `deserializeNBT` reads `_enable` FIRST and then
# short-circuits: `if (!isEnable() && skipDisableSerialize()) return;` — with
# `skipDisableSerialize()` hard-coded to `true`. A compound written WITHOUT the flag
# therefore deserialises as DISABLED and its payload is never read at all. fxlib's
# `AraTrailEmitter` writes the payload but not the flag, so every ara trail in the
# tree has been rendering as `appendFlatTrail` (flat band, zero segment physics)
# no matter what section/physics the generator asked for.
#
# fxlib.py is A0-owned shared ground this wave, so the A4 assets stamp the flag on
# their own emitters instead of changing the library.
# ---------------------------------------------------------------------------
def ara_toggles_on(emitter):
    """Marks an ara trail's `section` / `physicsSetting` toggle groups as enabled.

    Both fields extend LDLib2's `ToggleGroup`, which deserialises to DISABLED unless the
    compound carries an explicit `_enable: 1b`. `fxlib.AraTrailEmitter` writes the group's
    payload but not that flag, so a `physics=dict(...)` block is inert until this runs.
    (fxlib is a shared file this team must not touch — hence the post-hoc patch.)
    """
    for key in ("section", "physicsSetting"):
        block = emitter._config.get(key)
        if isinstance(block, dict):
            block["_enable"] = B(1)
    return emitter


# ---------------------------------------------------------------------------
# ring_soft.png — 256x256 white ring, gaussian alpha falloff (stdlib PNG writer).
# 256 px per PHOTON-QUALITY §4/§5.1 rule 6: ground rings that scale past r=10 need
# >= 256 px or they band/blur up close (the roar ring reaches r~30 blocks).
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


def write_ring_soft(path: Path, size: int = 256, peak: float = 0.6, sigma: float = 0.13) -> None:
    _write_png(path, size, lambda nx, ny: math.exp(
        -((math.sqrt(nx * nx + ny * ny) - peak) ** 2) / (2.0 * sigma * sigma)))


def write_dome_faint(path: Path, size: int = 128) -> None:
    """Ghost-bell shell: bright soft rim (limb of a translucent dome seen face-on) over
    a very faint interior fill that strengthens toward the edge — soap-bubble shading.
    Peak alpha 1.0 at the rim; the .fx gradient scales the whole shell to <= 0.12."""
    def alpha(nx, ny):
        r = math.sqrt(nx * nx + ny * ny)
        if r >= 1.0:
            return 0.0
        rim = math.exp(-((r - 0.86) / 0.07) ** 2)
        interior = 0.22 * (0.35 + 0.65 * r * r)
        return (interior + rim) * min(1.0, (1.0 - r) / 0.04 if r > 0.96 else 1.0)
    _write_png(path, size, alpha)


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
                                       hdr=(1.05, 0.72, 1.45), blend=BLEND_ADDITIVE))
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
       .with_material(texture_material(CIRCLE, hdr=(1.05, 0.72, 1.45), blend=BLEND_ADDITIVE))
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
#
# FX-Wave-13 A4 "Ara-Vollausbau" (census §2 row 9 — the flattest premium ribbon in
# the tree). The shard homes at 0.45 b/t with 0.18 steering, so it ARCS: the whole
# point of the upgrade is that the arcs now carry volume, lag and a taper.
#
# THREE stacked ribbons instead of one flat band. They differ in width, length and
# — the part that actually sells volume — in `inertia`, so they separate through
# every homing turn and the shard flies inside its own wake instead of dragging a
# single decal behind it:
#
#   veil    0.62 thick / 1.30 s / inertia 0.50 — wide dim violet smear, swings widest
#   ribbon  0.32 thick / 1.00 s / inertia 0.22 — the main read, corona violet
#   core    0.09 thick / 0.40 s / no physics   — white-hot spine welded to the shard
#
# Each carries the recipe's width curve (broad head -> point tail), a gradient along
# the ribbon AND a second gradient over each segment's own age.
#
# WHY NO `section` (the obvious way to get a crystal tube, deliberately not used):
# Photon 2.1.5's `AraTrailParticle.appendSection` extrudes the cross-section along
# `bitangent` and `this.tangent` — but for every alignment except `Local`,
# `this.tangent` IS the along-curve direction (it is set to `(nextV+prevV)*0.5` a few
# lines above). So the section ring has exactly zero extent on the third axis: it is
# a flat sheet lying in the plane that CONTAINS the direction of travel, smeared
# forward/back over itself, and it vanishes to a sliver whenever the camera is off to
# the side. Measured against the decompiled math on a shard-like arc, a 6-point star
# at thickness 0.3 spans 0.600 b across, 0.520 b ALONG travel and 0.000 b on the
# perpendicular — i.e. no tube at all. `Local` is the only geometrically sound
# alignment for sections, and it would need the emitter frame rotated onto the flight
# path by `AutoRotate.FORWARD`, whose quaternion in `EntityEffectExecutor` is built as
# `rotateXYZ(0, atan2(-z, x), y)` — the raw Y component fed in as a Z angle, so it
# does not survive a climbing/diving shard. Stacked flat ribbons are what the other
# 14 ara trails in the tree use, and they are the only path that renders correctly.
#
# Choppiness is fixed by `smoothness`, NOT by `timeInterval`/`minDistance`: emission
# runs in `render()` and drops AT MOST ONE point per FRAME, so on a low-FPS client the
# point cloud is sparse no matter how small the interval is. `smoothness` is the
# Catmull-style subdivision between existing points and is the only lever that adds
# geometry the emitter never sampled.
#
# WHY NO `high_quality_corners` (also deliberate — it SHREDS the ribbon):
# `appendFlatTrail` compensates miter joins with
#     correctedThickness = sectionThickness / max(bitangent . nextSectionBitangent, 0.15)
# so any segment whose bitangent is poorly conditioned — which is every near-degenerate
# segment produced by dense sampling plus `smoothness` subdivision — is drawn up to
# 6.67x too thick. On a shard-speed ribbon that renders as a comb of vertical spikes
# instead of a band. None of the other 14 ara trails in the tree switch it on, and
# `cornerRoundness` is gated behind the same flag, so leaving both at their defaults is
# both the house pattern and the only stable one. `minDistance` is held at 0.07 (above
# the 0.05 `smoothingDistance` default) for the same reason: it keeps consecutive points
# far enough apart that the per-point frame stays well conditioned.
# ---------------------------------------------------------------------------
def _shard_taper(knee: float) -> dict:
    """Width curve: full at the head, `knee` at mid-length, out to a true point."""
    return curve(0.0, 1.0,
                 [(0.0, 1.0, 0.18, 0.97, 0.42, knee + 0.18, 0.55, knee),
                  (0.55, knee, 0.74, knee * 0.55, 0.9, 0.04, 1.0, 0.0)],
                 "length", "thickness")


def build_herald_shard_trail() -> FxBuilder:
    fx = FxBuilder("boss/herald_shard_trail")
    # Generous entity-local box: ~9 b of veil at 0.45 b/t plus the gravity sag.
    cull = ((-12.0, -12.0, -12.0), (12.0, 12.0, 12.0))

    # 1. Veil — widest, longest, laggiest. Dim on its own; it exists to give the
    #    ribbon something to be bright against and to smear the turns.
    veil = fx.ara_trail_emitter(
        "shard_veil",
        duration=100, looping=True,
        space="World", alignment="View", sorting="NewerOnTop",
        thickness=0.62, smoothness=3,
        time=1.3, time_interval=0.04, min_distance=0.07,  # SECONDS (ara exception)
        texture_mode="Stretch",
        thickness_over_length=_shard_taper(0.62),
        # Dim violet at the head, umbral indigo out to nothing — birth tint stays dark.
        color_over_length=gradient(
            [(0.0, 0.42), (0.45, 0.34), (0.8, 0.14), (1.0, 0.0)],
            [(0.0, 0.62, 0.34, 0.95), (0.45, 0.4, 0.16, 0.8), (1.0, 0.18, 0.06, 0.4)]),
        physics=dict(warmup=0.0, gravity=(0.0, -1.9, 0.0), inertia=0.5,
                     velocity_smoothing=0.62, damping=0.88))
    ara_toggles_on(veil)
    (veil
       .with_material(texture_material(CIRCLE, hdr=(0.62, 0.3, 0.95), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull))

    # 2. Main ribbon — the read. Highest smoothness of the three, because this is the
    #    silhouette players actually track.
    ribbon = fx.ara_trail_emitter(
        "shard_ribbon",
        duration=100, looping=True,
        space="World", alignment="View", sorting="NewerOnTop",
        thickness=0.32, smoothness=6,
        time=1.0, time_interval=0.04, min_distance=0.07,
        texture_mode="Stretch",
        thickness_over_length=_shard_taper(0.46),
        # Head white-hot -> corona violet -> umbral indigo, alpha out with the taper.
        color_over_length=gradient(
            [(0.0, 0.95), (0.35, 0.82), (0.78, 0.42), (1.0, 0.0)],
            [(0.0, 1.0, 0.95, 1.0), (0.3, 0.72, 0.38, 1.0),
             (0.7, 0.45, 0.16, 0.85), (1.0, 0.28, 0.1, 0.5)]),
        # Colour over each SEGMENT's own age (the "over its lifetime" ramp). RGB only —
        # `colorOverLength` owns the alpha so the two multiplies cannot cancel the ribbon.
        color_over_segment_time=gradient(
            [(0.0, 1.0), (1.0, 1.0)],
            [(0.0, 1.0, 0.92, 1.0), (0.45, 0.8, 0.45, 1.0), (1.0, 0.55, 0.24, 0.95)]),
        physics=dict(warmup=0.0, gravity=(0.0, -1.5, 0.0), inertia=0.22,
                     velocity_smoothing=0.7, damping=0.82))
    ara_toggles_on(ribbon)
    (ribbon
       .with_material(texture_material(CIRCLE, hdr=(1.05, 0.5, 1.45), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull))

    # 3. Hot spine: NO physics, so it stays welded to the shard while the other two
    #    swing off it — that separation is what sells the lag.
    (fx.ara_trail_emitter(
            "shard_core",
            duration=100, looping=True,
            space="World", alignment="View", sorting="NewerOnTop",
            thickness=0.09, smoothness=4,
            time=0.4, time_interval=0.04, min_distance=0.07,
            texture_mode="Stretch",
            thickness_over_length=_shard_taper(0.34),
            color_over_length=gradient(
                [(0.0, 1.0), (0.4, 0.65), (1.0, 0.0)],
                [(0.0, 1.0, 0.98, 1.0), (1.0, 0.85, 0.6, 1.0)]))
       .with_material(texture_material(CIRCLE, hdr=(1.45, 1.2, 1.45), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull))
    return fx


# ---------------------------------------------------------------------------
# Concept 4 — eclipse:boss/ferry_lantern_swarm (soul-lantern Model particles)
#
# FX-Wave-13 A4 "Laternenschwarm" (census §2 row 12). The shipped version was a
# CAROUSEL: one shared 0.35 rad/t orbital on every lantern, so all 24 turned as a
# rigid disc. The swarm read comes from breaking that lockstep:
#
#   * per-lantern orbital speed AND radial drift (each light keeps its own orbit)
#   * a gentle per-lantern breathe (`random_curve` — two different pulse shapes, the
#     roll is memoized per particle, so no two lanterns are in phase)
#   * `lights` on the models so the lanterns are LIT objects in the umbral dark
#     instead of shaded blocks, plus a warm amber halo emitter riding the same mesh
#     distribution and the same drift
#   * a warm ara thread off every second lantern (the census's "Ara-Fäden")
#
# Palette law: the lanterns are the ONLY warm thing in the scene — the soul leak
# stays cold teal underneath so the amber has something to be warm against.
# ---------------------------------------------------------------------------
# Per-lantern breathe: two envelopes with different periods; random_curve lerps
# between them once per particle, so the swarm never pulses in unison.
_LANTERN_BREATHE_A = [(0.0, 0.72, 0.12, 1.0, 0.35, 1.0, 0.5, 0.78),
                      (0.5, 0.78, 0.62, 0.62, 0.82, 1.0, 1.0, 0.85)]
_LANTERN_BREATHE_B = [(0.0, 0.95, 0.18, 0.66, 0.44, 0.7, 0.62, 1.0),
                      (0.62, 1.0, 0.78, 0.94, 0.9, 0.7, 1.0, 0.8)]


def build_ferry_lantern_swarm() -> FxBuilder:
    fx = FxBuilder("boss/ferry_lantern_swarm")
    cull = ((-9.0, -1.0, -9.0), (9.0, 8.0, 9.0))
    # Warm lantern amber -> ember red. Deliberately off the cold house palette.
    lantern_warm = gradient(
        [(0.0, 0.0), (0.14, 0.85), (0.75, 0.7), (1.0, 0.0)],
        [(0.0, 0.28, 0.14, 0.06), (0.3, 1.0, 0.72, 0.34), (1.0, 0.95, 0.45, 0.18)])

    # 24 actual soul-lantern models drift on their own orbits.
    # Mesh shape doubles as the baked-model source for renderMode Model (FX_FORMAT §3.2);
    # shape scale spreads the emission points to roughly the spec's r=2.2 circle.
    lanterns = (fx.particle_emitter(
            "lantern_swarm",
            duration=80, looping=False, max_particles=24,
            start_lifetime=random_between(50, 70), start_speed=constant(0.05),
            # Photon's Model bake flattens soul_lantern's multipart model to a UV'd cube,
            # so the body has to stay SMALL and let the halo carry the lamp read — at the
            # shipped 0.5-0.7 the cubes are legible as crates once the swarm spreads out.
            start_size=nf3(random_between(0.22, 0.34), random_between(0.22, 0.34),
                           random_between(0.22, 0.34)),
            start_rotation=nf3(constant(0), random_between(0.0, 360.0), constant(0)),
            simulation_space="Local")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=6, cycles=1, probability=1.0),
                              burst(time=10, count=6, cycles=3, interval=10, probability=1.0)])
       # Scale is the SPREAD of the emission volume, not the lantern size: a soul_lantern
       # model is only ~0.4x0.5 in model space, so the shipped 4.4 packed all 24 lanterns
       # into a ~1.6 b clump that read as one amber blob. 11 wide / 5 tall puts them on
       # roughly the spec's r=2.2 circle with enough radius for the orbital drift to bite.
       .with_shape(mesh("block/soul_lantern", emit_from="Triangle"),
                   scale=nf3(11.0, 5.0, 11.0))
       .with_material(block_atlas_material(blend=BLEND_ALPHA, cull=True, depth_test=True,
                                           depth_mask=True))
       .with_renderer(render_mode="Model", use_block_uv=True, model_pivot=(0.5, 0.5, 0.5),
                      facing_mode="ROTATE_Y", shade=True)
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                # Photon velocities are BLOCKS PER SECOND (the runtime multiplies every
                # velocity by 0.05 before adding it per tick — jar-verified in
                # VelocityOverLifetimeSetting), so the shipped 0.02-0.05 "rise" was
                # 0.05 blocks over the whole 60t life, i.e. a dead-still ring.
                linear=nf3(constant(0), random_between(0.5, 1.7), constant(0)),
                orbital_mode="AngularVelocity",
                # Own orbit per lantern (some even hang back) + a slow in/out breath
                # on the radius — the two together are what turns a disc into a swarm.
                orbital=nf3(constant(0), random_between(0.25, 1.1), constant(0)),
                offset=nf3(0), radial=random_between(-0.45, 0.7)),
            rotation_over_lifetime=dict(yaw=random_between(-3.0, 3.0)),
            size_over_lifetime=random_curve(0.82, 1.12, _LANTERN_BREATHE_A,
                                            _LANTERN_BREATHE_B, "lifetime", "size"),
            noise=dict(frequency=0.5, quality="Noise3D",
                       position=nf3(constant(0.07), constant(0.045), constant(0.07))))
       # Lanterns are light SOURCES: without this the block model renders at the
       # ambient lightmap of a night-time deck, i.e. as a dark lump.
       .with_lights(sky=15, block=15))
    # Warm ara thread off every second lantern — the swarm leaves a wake instead of
    # sliding through clean air. Thin + short, so 12 live ribbons stay cheap.
    lanterns.with_module("trails", {
        "ratio": F(0.5),
        "lifetime": constant(0.6),
        "dieWithParticles": B(1),
        "sizeAffectsWidth": B(1),
        "sizeAffectsLifetime": B(0),
        "inheritParticleColor": B(0),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            "space": "World",
            "thickness": F(0.07),
            "time": F(0.9),                # seconds (ara exception)
            "smoothness": I(3),
            # highQualityCorners stays OFF: its miter compensation divides thickness by
            # max(dot, 0.15), which shreds short segments into spikes (see the
            # herald_shard_trail header for the full derivation).
            "highQualityCorners": B(0),
            "textureMode": "Stretch",
            "thicknessOverLength": curve(
                0.0, 1.0, [(0.0, 1.0, 0.3, 0.78, 0.75, 0.2, 1.0, 0.0)], "length", "thickness"),
            "colorOverLength": gradient(
                [(0.0, 0.55), (0.45, 0.3), (1.0, 0.0)],
                [(0.0, 1.0, 0.78, 0.42), (1.0, 0.75, 0.3, 0.12)]),
            "physicsSetting": {
                "_enable": B(1),           # see ara_toggles_on — the flag IS the switch
                "warmup": F(0.0),
                "gravity": L([F(0.0), F(-0.12), F(0.0)]),
                "inertia": F(0.3),
                "velocitySmoothing": F(0.8),
                "damping": F(0.85)},
            "renderer": {
                "materials": rom([texture_material(CIRCLE, hdr=(1.35, 0.8, 0.35),
                                                   blend=BLEND_ADDITIVE)]),
                "layer": "Translucent", "cull": {"_enable": B(0)},
                "orderInLayer": I(0), "vertexSortingMode": "NONE"}}})

    # The light each lantern throws: a warm halo on the SAME mesh distribution and the
    # same drift parameters, so the glows travel with the swarm. `random_curve` size
    # flicker on top of the breathe gives the candle read the census asks for.
    (fx.particle_emitter(
            "lantern_glow",
            duration=80, looping=False, max_particles=28,
            start_lifetime=random_between(50, 70), start_speed=constant(0.05),
            start_size=nf3(random_between(0.7, 1.05)),
            simulation_space="Local")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=6, cycles=1, probability=1.0),
                              burst(time=10, count=6, cycles=3, interval=10, probability=1.0)])
       # Same distribution AND spread as the lantern models, so every halo sits on a lamp.
       .with_shape(mesh("block/soul_lantern", emit_from="Triangle"),
                   scale=nf3(11.0, 5.0, 11.0))
       .with_material(texture_material(CIRCLE, hdr=(1.45, 0.85, 0.35), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.5, 1.7), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.25, 1.1), constant(0)),
                offset=nf3(0), radial=random_between(-0.45, 0.7)),
            size_over_lifetime=random_curve(0.6, 1.25, _LANTERN_BREATHE_B,
                                            _LANTERN_BREATHE_A, "lifetime", "size"),
            noise=dict(frequency=0.5, quality="Noise3D",
                       position=nf3(constant(0.07), constant(0.045), constant(0.07))),
            color_over_lifetime=lantern_warm)
       .with_lights(sky=15, block=15))

    # Cold counterpoint: teal soul-flame motes leaking off the ring under the lanterns.
    # Given the same swarm drift so they read as part of the shoal, not a static ring.
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
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.6, 1.5), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.2, 0.8), constant(0)),
                offset=nf3(0)),
            size_over_lifetime=random_curve(0.55, 1.15, _LANTERN_BREATHE_A,
                                            _LANTERN_BREATHE_B, "lifetime", "size"),
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
       .with_material(texture_material(CIRCLE, hdr=(0.87, 1.3, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-7.0, -2.0, -7.0), (7.0, 4.0, 7.0)))
    return fx


# ---------------------------------------------------------------------------
# Concept 9 — eclipse:boss/ferry_kneel_corona (100t one-shot, re-fired on the
# 20t crew cadence; allowMulti=false dedups re-sends while the runtime lives)
#
# FXWAVE-9 #3 V2: the P2 kneel read as a STALLED fight (boss frozen, one thin
# halo). Three additions keep the beat alive without a single Java change —
# breathing ground-fog skirt (r5.5), a SECOND counter-orbiting halo band higher
# up (opposed spin sells "contained power"), and a heartbeat bloom that thumps
# twice per re-fire window at chest height. Live-particle budget ≈60.
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

    # V2: counter-orbiting upper band (y≈2.6, spin OPPOSED to corona_halo) — the
    # two rings shearing against each other read as bound, waiting power.
    (fx.particle_emitter(
            "corona_halo_hi",
            duration=100, looping=False, prewarm=10, max_particles=64,
            start_lifetime=random_between(28, 44), start_speed=constant(0.02),
            start_size=nf3(random_between(0.10, 0.2), random_between(0.10, 0.2),
                           random_between(0.10, 0.2)),
            simulation_space="Local")
       .with_emission(rate=constant(0.55))
       .with_shape(cylinder(radius=1.7, thickness=0.1, arc_mode="Loop", arc_speed=0.5),
                   position=nf3(0, 2.6, 0))
       .with_material(texture_material(CIRCLE, hdr=(0.45, 1.05, 1.0), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 6.0, 4.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.02, -0.008), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(-0.55), constant(0)),
                offset=nf3(0)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.55), (0.8, 0.45), (1.0, 0.0)],
                [(0.0, 0.55, 1.0, 0.95), (1.0, 0.2, 0.6, 0.6)]))
       .with_lights(sky=15, block=15))

    # V2: breathing ground-fog skirt — a wide, slow teal haze hugging the deck
    # around the kneel so the whole ARENA area reads "ritual in progress".
    (fx.particle_emitter(
            "kneel_fog",
            duration=100, looping=False, prewarm=40, max_particles=18,
            start_lifetime=random_between(70, 95), start_speed=constant(0.0),
            start_size=nf3(random_between(1.4, 2.2)),
            simulation_space="Local")
       .with_emission(rate=constant(0.15))
       .with_shape(circle(radius=5.5, thickness=0.35), position=nf3(0, 0.2, 0))
       .with_material(texture_material(CIRCLE, discard=0.02, hdr=(0.25, 0.6, 0.55),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE", shade=False)
       .with_cull_box((-8.0, -1.0, -8.0), (8.0, 3.0, 8.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.0015), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.04), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.16), (0.7, 0.13), (1.0, 0.0)],
                [(0.0, 0.3, 0.8, 0.7), (1.0, 0.2, 0.55, 0.5)]),
            size_over_lifetime=nf3(
                curve(0.7, 1.0, [(0.0, 0.5, 0.35, 1.0, 0.7, 1.0, 1.0, 0.6)],
                      "lifetime", "size"),
                curve(0.7, 1.0, [(0.0, 0.5, 0.35, 1.0, 0.7, 1.0, 1.0, 0.6)],
                      "lifetime", "size"),
                curve(0.7, 1.0, [(0.0, 0.5, 0.35, 1.0, 0.7, 1.0, 1.0, 0.6)],
                      "lifetime", "size")))
       .with_lights(sky=15, block=15))

    # V2: heartbeat bloom — two soft chest-height thumps per 100t window (the
    # kneel has a pulse; pairs with the server-side subboom swell).
    (fx.particle_emitter(
            "kneel_heartbeat",
            duration=100, looping=False, max_particles=6,
            start_lifetime=constant(22), start_speed=constant(0.0),
            start_size=nf3(1.1), simulation_space="Local")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=10, count=constant(2), cycles=2, interval=50)])
       .with_shape(dot(), position=nf3(0, 1.6, 0))
       .with_material(texture_material(CIRCLE, hdr=(1.45, 1.09, 1.36), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-3.0, 0.0, -3.0), (3.0, 4.0, 3.0))
       .with_curves(
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.25, 0.25, 1.0, 0.6, 0.85, 1.0, 0.6)],
                "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.18, 0.5), (0.5, 0.2), (1.0, 0.0)],
                [(0.0, 0.5, 1.0, 0.9), (1.0, 0.3, 0.7, 0.7)]))
       .with_lights(sky=15, block=15))

    # ONE faint ghost-bell dome; deliberately dim (no HDR — the read is "inert").
    # dome_faint.png (authored above) replaces the smoke.png stand-in, and the spec'd
    # slow pulse (IDEAS-boss #9 / QUALITY §2 row 7) lands as a 2-segment eased breathe:
    # the shell swells and relaxes once per cycle while the gradient echoes it in alpha.
    (fx.particle_emitter(
            "invuln_shell",
            duration=100, looping=False, max_particles=4,
            start_lifetime=constant(90), start_speed=constant(0.0),
            start_size=nf3(3.2, 3.2, 3.2), simulation_space="Local")
       .with_emission(rate=constant(0.25),
                      bursts=[burst(time=0, count=1, cycles=1, probability=1.0)])
       .with_shape(dot())
       .with_material(texture_material(DOME_FAINT, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 5.0, 4.0))
       .with_curves(
            size_over_lifetime=curve(
                0.96, 1.04,
                [(0.0, 0.0, 0.2, 0.9, 0.35, 1.0, 0.5, 1.0),
                 (0.5, 1.0, 0.65, 1.0, 0.8, 0.1, 1.0, 0.0)],
                "lifetime", "size"),
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
    write_dome_faint(DOME_TEXTURE)
    print(f"WROTE {DOME_TEXTURE.relative_to(REPO_ROOT)}")
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
