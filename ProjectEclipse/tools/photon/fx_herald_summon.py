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
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, REPO_ROOT, SEG_DECAY_TAIL,
    SEG_EASE_OUT_CREST, FxBuilder, burst, circle, constant, curve, cylinder, dot,
    function_shape, gradient, nf3, random_between, random_gradient, sphere,
    texture_material, validate_file,
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
# FX-Wave-13 A4 — Herald silhouette reveal (census §5: "the boss is suddenly just
# THERE"). The beats live INSIDE herald_summon_pillar rather than behind a new cue:
# the pillar is already fired once, at a known tick, at a known point, so every beat
# below is just a `startDelay` off that one spawn — no FxCues.java edit, no second
# broadcast, and a photon-less client is unaffected.
#
# Geometry (HeraldSummonSequence + HeraldsLureItem/DevEventCommands + HeraldEntity):
#   fx origin  = Run.center      = (altar.x, groundY, altar.z)
#   hover slot = Run.hover.y     = altarPos.getY() + HeraldEntity.SUMMON_HEIGHT
#   altarPos.getY()              = groundY + AltarSanctumBuilder.ALTAR_ABOVE_GROUND
#   => hover is a FIXED  4 + 12 = 16 blocks above the fx origin on BOTH spawn paths.
#
# Timing (all HeraldSummonSequence constants, minus PILLAR_TICK = 15):
#   SILHOUETTE_TICK  55 -> fx  40   the fog closes and the backlight comes up
#   MATERIALIZE_TICK 130 -> fx 115   the curtain PARTS, backlight flares
#   SPAWN_TICK       150 -> fx 135   the real entity takes over
# ---------------------------------------------------------------------------
HOVER_Y = 16.0
REVEAL_TICK = 40
PART_TICK = 115
HANDOFF_TICK = 135


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
       .with_material(texture_material(CIRCLE, hdr=(1.03, 0.66, 1.45), blend=BLEND_ADDITIVE))
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
       .with_material(texture_material(RING_SOFT, hdr=(1.04, 0.69, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", facing_mode="DEFAULT", shade=False,
                      vertex_sorting="NONE")
       .with_cull_box((-24.0, -2.0, -24.0), (24.0, 8.0, 24.0))
       .with_curves(
            size_over_lifetime=curve(0.0, 22.0, [(0.0, 0.05, 0.15, 0.9, 0.6, 1.0, 1.0, 1.0)],
                                     "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.9), (0.6, 0.5), (1.0, 0.0)],
                                         list(VIOLET_WHITE))))

    add_silhouette_reveal(fx)
    return fx


# ---------------------------------------------------------------------------
# The reveal itself (see the beat/geometry block at the top of the file).
# ---------------------------------------------------------------------------
def _spindle_shape():
    """Crowned-godhead spindle around the hover slot, in Photon's expression language.

    `HeraldSummonSequence.profileRadius` is a 3-branch piecewise; the same silhouette
    without conditionals is a half-sine (torso bulge) tapered linearly toward the crown:
    r(t) = (0.35 + 0.95·sin(πt))·(1 − 0.5t) — 0.35 at the feet, ~1.0 across the
    shoulders, 0.18 at the crown. `randomA` scatters the azimuth over the full circle.
    """
    radius = "(0.35+0.95*sin(t*PI))*(1.0-0.5*t)"
    return function_shape(
        x=f"{radius}*cos(randomA*2*PI)",
        y=f"{HOVER_Y - 2.3}+t*4.6",
        z=f"{radius}*sin(randomA*2*PI)",
        speed_y="0.01+0.02*randomB")


def add_silhouette_reveal(fx: FxBuilder) -> None:
    """Fog curtain -> backlight -> dark body -> the curtain parts."""
    cull = ((-12.0, -2.0, -12.0), (12.0, 26.0, 12.0))

    # 1. Backlight. One tall violet-white quad centred on the hover slot: the boss
    #    materialises INSIDE it, so the halo that survives around the model's outline
    #    is what turns an unlit body into a readable silhouette. Two bursts — the slow
    #    swell while the fog is closed, and the flare on the part beat.
    (fx.particle_emitter(
            "reveal_backlight",
            duration=HANDOFF_TICK - REVEAL_TICK + 10, looping=False,
            start_delay=constant(REVEAL_TICK), max_particles=4,
            start_lifetime=constant(78), start_speed=constant(0.0),
            start_size=nf3(7.0, 10.0, 7.0), simulation_space="World")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(1)),
                              burst(time=PART_TICK - REVEAL_TICK, count=constant(1))])
       .with_shape(dot(), position=nf3(0, HOVER_Y, 0))
       .with_material(texture_material(CIRCLE, hdr=(1.15, 0.7, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard", vertex_sorting="NONE", shade=False)
       .with_cull_box(*cull)
       .with_curves(
            # Comes up slowly (the light behind the fog), holds, blows out at the end.
            size_over_lifetime=curve(
                0.35, 1.0, [(0.0, 0.1, 0.35, 0.28, 0.6, 0.85, 0.75, 1.0),
                            (0.75, 1.0, 0.85, 1.0, 0.94, 0.45, 1.0, 0.0)],
                "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.35, 0.35), (0.7, 0.7), (0.88, 0.5), (1.0, 0.0)],
                [(0.0, 0.55, 0.3, 0.85), (0.55, 0.85, 0.62, 1.0), (1.0, 1.0, 0.9, 1.0)]))
       .with_lights(sky=15, block=15))

    # 2. Fog curtain. A dark, slowly rotating smoke wall standing in FRONT of the
    #    backlight — alpha-blended and near-black at birth (wave-13 dark-birth law), so
    #    it subtracts detail instead of adding glow. DISTANCE sorting: it is the one
    #    translucent stack in the file and it overlaps itself constantly.
    (fx.particle_emitter(
            "reveal_fog_curtain",
            duration=PART_TICK - REVEAL_TICK, looping=False,
            start_delay=constant(REVEAL_TICK), max_particles=34,
            start_lifetime=random_between(34, 52), start_speed=constant(0.0),
            start_size=nf3(random_between(2.2, 3.4)), simulation_space="World")
       .with_emission(rate=constant(0.9),
                      bursts=[burst(time=0, count=constant(10))])
       .with_shape(cylinder(radius=3.1, thickness=0.3, arc_mode="Random"),
                   position=nf3(0, HOVER_Y - 0.4, 0), scale=nf3(1.0, 5.6, 1.0))
       .with_material(texture_material(SMOKE, discard=0.02, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=False)
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.3, 0.9), constant(0)),
                orbital_mode="AngularVelocity",
                # b/s again: 0.9 rad/s turns the curtain ~a third of a revolution over
                # the 75t it is closed — a drift, not a carousel.
                orbital=nf3(constant(0), constant(0.9), constant(0)),
                offset=nf3(0), radial=constant(-0.25)),
            rotation_over_lifetime=dict(roll=random_between(-1.4, 1.4)),
            noise=dict(frequency=0.35, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.03), constant(0.05))),
            # Umbral near-black in, a hint of bruised violet out — never brightens.
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.82), (0.72, 0.7), (1.0, 0.0)],
                [(0.0, 0.04, 0.02, 0.07), (0.45, 0.1, 0.05, 0.16),
                 (1.0, 0.17, 0.09, 0.26)])))

    # 3. The body. Dark alpha motes filling the same crowned spindle the vanilla
    #    SOUL_FIRE_FLAME rings trace (HeraldSummonSequence.profileRadius) — the vanilla
    #    pass draws the OUTLINE in light, this one fills it in with shadow so the shape
    #    is a hole in the backlight rather than a sparkle cloud.
    (fx.particle_emitter(
            "reveal_silhouette",
            duration=HANDOFF_TICK - REVEAL_TICK - 12, looping=False,
            start_delay=constant(REVEAL_TICK), max_particles=110,
            start_lifetime=random_between(16, 28), start_speed=constant(0.0),
            start_size=nf3(random_between(0.5, 0.95)), simulation_space="World")
       .with_emission(rate=constant(3.0), bursts=[burst(time=0, count=constant(14))])
       .with_shape(_spindle_shape())
       .with_material(texture_material(SMOKE, discard=0.02, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=False)
       .with_cull_box(*cull)
       .with_curves(
            # Scatter tightens toward the materialise beat, mirroring the server-side
            # SILHOUETTE_SPREAD_START ramp: the noise the shape is built from calms down.
            noise=dict(frequency=0.6, quality="Noise3D",
                       position=nf3(curve(0.02, 0.16, [SEG_DECAY_TAIL], "duration", "value"),
                                    curve(0.02, 0.16, [SEG_DECAY_TAIL], "duration", "value"),
                                    curve(0.02, 0.16, [SEG_DECAY_TAIL], "duration", "value"))),
            size_over_lifetime=curve(0.5, 1.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.9), (0.75, 0.85), (1.0, 0.0)],
                [(0.0, 0.02, 0.01, 0.04), (1.0, 0.06, 0.03, 0.1)])))

    # 4. Ember updraft. Motes torn off the dais that climb the full 16 blocks into the
    #    hover slot over their life — the vertical link between the broken floor and the
    #    thing assembling above it. random_gradient per ember (census A4 note: kill the
    #    repetition read on a beat players will watch several times an event).
    #    Photon speeds are BLOCKS PER SECOND (Photon multiplies every velocity by 0.05
    #    before adding it per tick — jar-verified in VelocityOverLifetimeSetting), so
    #    5.4-7.2 b/s over a 46-66t (2.3-3.3 s) life is the 16-block climb.
    (fx.particle_emitter(
            "reveal_embers",
            duration=HANDOFF_TICK - REVEAL_TICK + 4, looping=False,
            start_delay=constant(REVEAL_TICK - 4), max_particles=80,
            start_lifetime=random_between(46, 66), start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(0.07, 0.18)), simulation_space="World")
       .with_emission(rate=constant(1.5), bursts=[burst(time=0, count=constant(12))])
       .with_shape(circle(radius=4.2, thickness=0.7), position=nf3(0, 0.3, 0))
       .with_material(texture_material(CIRCLE, hdr=(0.9, 0.45, 1.35), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.7, length_scale=1.4,
                      vertex_sorting="NONE")
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(5.4, 7.2), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(-0.9), constant(0)),
                offset=nf3(0), radial=constant(-0.6)),
            noise=dict(frequency=0.5, quality="Noise2D",
                       position=nf3(constant(0.07), constant(0.02), constant(0.07))),
            # Dark birth on both rolls; one ember burns violet, the other bone-white.
            color_over_lifetime=random_gradient(
                [(0.0, 0.0), (0.12, 0.9), (0.7, 0.55), (1.0, 0.0)],
                [(0.0, 0.16, 0.05, 0.24), (0.35, 0.8, 0.4, 1.0), (1.0, 0.35, 0.14, 0.55)],
                [(0.0, 0.0), (0.18, 0.75), (0.65, 0.45), (1.0, 0.0)],
                [(0.0, 0.12, 0.09, 0.14), (0.4, 0.95, 0.88, 1.0), (1.0, 0.5, 0.3, 0.6)])))

    # 5. The part. The curtain does not fade — it is BLOWN outward on the materialise
    #    beat, which is the frame the shape stops being a rumour.
    (fx.particle_emitter(
            "reveal_curtain_part",
            duration=26, looping=False,
            start_delay=constant(PART_TICK), max_particles=28,
            start_lifetime=random_between(18, 26), start_speed=random_between(2.4, 4.0),
            start_size=nf3(random_between(2.0, 3.0)), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(18))])
       .with_shape(cylinder(radius=3.0, thickness=0.2, arc_mode="Random"),
                   position=nf3(0, HOVER_Y - 0.4, 0), scale=nf3(1.0, 5.2, 1.0))
       .with_material(texture_material(SMOKE, discard=0.02, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=False)
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.4, 1.4), constant(0)),
                offset=nf3(0),
                # b/s: 5.0 -> 0.25 b/t, so the curtain halves clear ~3 blocks of the
                # hover slot in the first half-second and then coast to a stop.
                radial=curve(0.0, 5.0, [(0.0, 1.0, 0.2, 0.7, 0.6, 0.2, 1.0, 0.0)],
                             "lifetime", "value")),
            size_over_lifetime=curve(1.0, 1.7, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.68), (0.3, 0.5), (1.0, 0.0)],
                [(0.0, 0.14, 0.07, 0.2), (1.0, 0.3, 0.18, 0.42)])))

    # 6. Rim glints riding the parting edge — the light finally getting past the fog.
    (fx.particle_emitter(
            "reveal_rim_glint",
            duration=20, looping=False,
            start_delay=constant(PART_TICK), max_particles=24,
            start_lifetime=random_between(10, 18), start_speed=random_between(1.6, 3.6),
            start_size=nf3(random_between(0.1, 0.22)), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(16))])
       .with_shape(sphere(radius=1.9, thickness=0.25),
                   position=nf3(0, HOVER_Y - 0.2, 0))
       .with_material(texture_material(CIRCLE, hdr=(1.3, 1.0, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box(*cull)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 1.0), (0.6, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.95, 1.0), (1.0, 0.6, 0.28, 0.9)]))
       .with_lights(sky=15, block=15))


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
       .with_material(texture_material(GLYPH, hdr=(0.94, 0.58, 1.45), blend=BLEND_ADDITIVE))
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
       .with_material(texture_material(GLYPH, hdr=(1.01, 0.63, 1.45), blend=BLEND_ADDITIVE))
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
       .with_material(texture_material(CIRCLE, hdr=(0.91, 0.54, 1.45), blend=BLEND_ADDITIVE))
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
