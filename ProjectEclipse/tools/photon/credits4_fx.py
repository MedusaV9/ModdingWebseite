#!/usr/bin/env python3
"""CREDITS4 (F-090/F-093 "Map-Zerreißen V3") — authors the map-rip Photon assets:

  eclipse:credits4_crackfront  crack-front propagation step: violet glow motes hugging
                               the glowing seam slats + a rising dust curtain + a short
                               upward debris jet — fired by CreditsSequence.mapRipBeats
                               at every propagation step's segment midpoint (~40t
                               one-shot; 3 fronts × 6 steps = 18 fires per run, each on
                               a fresh midpoint marching hole → camera)
  eclipse:credits4_platebreak  mid-air sub-fracture snap: one sharp hot split flash +
                               a handful of slow dark shard puffs kicked outward —
                               fired once per plate at lift+40t (~30t one-shot; ≈40
                               fires, de-phased by the per-plate lift jitter)
  eclipse:credits4_jetburst    jet shred: two opposed fast particle streams racing up/
                               down the maw's polar axis + a few long stretched sparks
                               — fired at the fx anchor whenever a shredded sub-plate
                               sprays along the jet axis (~60t one-shot, paired with
                               the S2CCreditsJetPayload shader strobe)

Authored scale (anchor frame, ~4.3× at map read through the crushed FOV): a crack
step's segment is ~13 anchor-blocks, so the crackfront veil covers a 6–8-block seam
band; a plate silhouette is 8–20 blocks, so the platebreak flash pops at ~3 and its
puffs ride a 6-block shell; the jets must clear the ~26-block maw — the streams reach
~40 blocks along ±Y (the disc minor axis: the same columns black_hole.fsh strobes).

Java-side tick contract: CreditsMapRipAct's CRACK_STEP_TICKS = 15 (the veil's motes
outlive one step, so consecutive steps chain into one racing front); FRACTURE_SNAP
window 4t (the flash is authored to peak inside it); JET_SPRAY_TICKS = 50 (the streams
die just after the display spray drains).

FX-WAVE-13 C5 PASS — what changed and WHY (census §7 line C5, §2 row 30):

  1. UNITS. Photon reads `startSpeed` and `velocityOverLifetime.linear` in blocks per
     SECOND (`×0.05`/tick) and `radial` at `×0.01`/tick — the slip B6 found in
     `ceremony_fx.py` and C4 found across `worldevents_fx.py`, and this file had it in
     every emitter. The headline case: the jet streams above are documented to reach
     "~40 blocks along ±Y", their own cull box is sized ±55 for it, and the shader
     strobes matching columns — but at `speed 1.1–1.6` over a 22–34t life they actually
     travelled 1.2–2.7 blocks. The polar jets of a black hole were 3 % of the length of
     the maw they are supposed to clear, i.e. an invisible puff at the anchor. Every
     velocity in this file is now back-solved from the distance its own comment
     promises: `blocks = v × 0.05 × lifetimeTicks`.
  2. `lifetimeByEmitterSpeed` — the census wants the jet knots to scale their lifetime
     with emitter speed and calls this the feature's first user. It IS wired now, but as
     a no-op-safe arming only: on a static anchor the module can never fire. See the long
     block above `_jet_stream` for the jar evidence, and for the emitter-progress curve
     pair that delivers the same read here.
  3. `random_gradient` (via `varied()`) on every emitter carrying more than a couple of
     particles — this file had ZERO, so every mote, shard and spark was a colour clone.
  4. Dark birth tints (V2.1 stacking law): ramps OPEN below their own fade target, so a
     shell of additive quads born inside half a block stops converging on a white ball.
  5. HDR clamped to the wave-13 stacking ceiling 1.45, hue ratio preserved — the flash,
     the sparks and the seam glow all sat at 1.7–2.0.

Usage:  python3 tools/photon/credits4_fx.py            # write + validate all three
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, F, FX_ASSETS_DIR, FxBuilder, burst, circle, cone, constant, curve,
    cylinder, gradient, nf3, random_between, random_gradient, sphere, texture_material,
    validate_file)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"

# Finale palette (the ferryman2 law): near-black violet body, mid, hot white-violet.
VIOLET_DEEP = (0.18, 0.08, 0.28)
VIOLET_MID = (0.612, 0.482, 0.878)
VIOLET_HOT = (0.816, 0.702, 1.0)
# Sibling tints for `varied()` — inside the same palette, so the roll reads as variety
# rather than as a second colour.
VIOLET_MID_ALT = (0.52, 0.44, 0.86)
VIOLET_HOT_ALT = (0.90, 0.76, 0.98)
#: Birth tints (V2.1 stacking law): a ramp must OPEN below its OWN fade target, so the
#: near-black smoke ramps (which fade to ~0.05 luma) need a darker birth than the
#: additive violet ones — one shared dust birth would be a brightening, not a tint.
VIOLET_BIRTH = (0.12, 0.06, 0.20)
DUST_BIRTH = (0.022, 0.012, 0.038)

# ---------------------------------------------------------------------------
# WAVE-13 C5 levers. Local by design: `fxlib.py` is A0 ground this wave, so this is the
# same helper pair B6 landed in `ceremony_fx.py` and C4 in `worldevents_fx.py`, copied
# rather than shared so the generators can never block each other.
# ---------------------------------------------------------------------------
#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4 / §2 "HDR ~1.45").
HDR_CEILING = 1.45
#: Photon converts authored speed to blocks/tick with this factor, so a documented
#: distance back-solves as `v = blocks / (TICK_SECONDS * lifetimeTicks)`.
TICK_SECONDS = 0.05


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling inside the same palette;
    each particle rolls its own memoized lerp, so no two read identical."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


def speed_for(blocks, lifetime_ticks):
    """Authored speed that carries a particle `blocks` far over `lifetime_ticks`."""
    return round(blocks / (TICK_SECONDS * lifetime_ticks), 2)


def reach(speed_bps, lifetime_ticks):
    """Inverse of `speed_for` — the distance a knot covers, for the doc comments."""
    return round(speed_bps * TICK_SECONDS * lifetime_ticks, 1)


#: Jet decay over the emitter's own 60t duration: the throat holds full pressure for the
#: first third of the burst, then collapses. Shared by every jet NumberFunction so speed,
#: lifetime and emission all read off ONE shape (see `_jet_stream`).
SEG_JET_DECAY = (0.0, 1.0, 0.30, 1.0, 0.62, 0.18, 1.0, 0.0)


# ---------------------------------------------------------------------------
# 1. eclipse:credits4_crackfront — a propagation step of a racing crack front
# ---------------------------------------------------------------------------
def build_credits4_crackfront() -> FxBuilder:
    fx = FxBuilder("credits4_crackfront")
    root = fx.empty("crackfront_root")

    # Seam glow: small hot motes hugging the freshly opened seam band — near-static
    # (the CRACK glows, the slat displays carry the hard line), front-loaded so each
    # step reads as one bright pop that hands over to the next step's midpoint.
    (fx.particle_emitter(
            "crackfront_glow",
            duration=40, looping=False, start_lifetime=random_between(18, 30),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.3, 0.7)),
            simulation_space="Local", max_particles=40)
        .child_of(root)
        .with_emission(rate=constant(0.6),
                       bursts=[burst(time=0, count=constant(10))])
        .with_shape(cylinder(radius=6.0, thickness=0.8))
        .with_curves(
            # Birth tint: the mote lights UP out of the seam's own darkness instead of
            # popping in already hot — ten of these stack inside one seam band.
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.85), (0.6, 0.45), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.12, *VIOLET_HOT), (0.6, *VIOLET_MID),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.14, *VIOLET_HOT_ALT), (0.6, *VIOLET_MID_ALT),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.3, 1.0, 1.8)))
        .with_cull_box((-12.0, -6.0, -12.0), (12.0, 10.0, 12.0)))

    # Dust curtain: a low smoke sheet RISING off the tearing seam — the crust exhales
    # as the crack jumps (the reverse of the precrack trickle).
    (fx.particle_emitter(
            "crackfront_dust",
            duration=40, looping=False, start_lifetime=random_between(26, 40),
            # ~1 block of outward creep off the 7-block seam ring over a 33t life.
            start_speed=constant(speed_for(1.0, 33)),
            start_size=nf3(random_between(1.2, 2.4), random_between(1.2, 2.4),
                           random_between(1.2, 2.4)),
            simulation_space="Local", max_particles=30)
        .child_of(root)
        .with_emission(rate=constant(0.5),
                       bursts=[burst(time=0, count=constant(8))])
        .with_shape(cylinder(radius=7.0, thickness=0.7))
        .with_curves(
            # Rise 2.6-8.4 blocks over the sheet's 26-40t life (blocks/SECOND: the old
            # 0.1-0.24 lifted the curtain by 0.13-0.48 blocks, i.e. it never left the
            # seam). Stays well inside the +16 cull lid.
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           random_between(speed_for(2.6, 26), speed_for(8.4, 40)),
                           constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.38), (0.7, 0.22), (1.0, 0.0)],
                [(0.0, *DUST_BIRTH), (0.2, 0.16, 0.09, 0.24), (1.0, 0.07, 0.04, 0.12)],
                [(0.0, *DUST_BIRTH), (0.2, 0.13, 0.08, 0.21), (1.0, 0.05, 0.03, 0.1)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-14.0, -4.0, -14.0), (14.0, 16.0, 14.0)))

    # Debris jet: a short sharp spray of fast splinters kicked UP out of the seam the
    # instant the step lands — the physical half of the per-step shake pulse.
    (fx.particle_emitter(
            "crackfront_debris",
            duration=40, looping=False, start_lifetime=random_between(10, 18),
            # 5.5-15.3 blocks of throw over a 10-18t life — a splinter spray that
            # actually clears the 6-8-block seam band (it used to reach 0.4-1.1).
            start_speed=random_between(speed_for(5.5, 10), speed_for(15.3, 18)),
            start_size=nf3(random_between(0.12, 0.24)), max_particles=14)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(12))])
        .with_shape(cone(angle=16.0, radius=2.2, thickness=0.4))
        .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 0.8), (0.65, 0.4), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.1, *VIOLET_HOT), (1.0, *VIOLET_MID)],
                [(0.0, *VIOLET_BIRTH), (0.1, *VIOLET_HOT_ALT), (1.0, *VIOLET_MID_ALT)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.3, 1.05, 1.7)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=1.4)
        .with_cull_box((-10.0, -2.0, -10.0), (10.0, 20.0, 10.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:credits4_platebreak — a plate snapping into sub-plates mid-air
# ---------------------------------------------------------------------------
def build_credits4_platebreak() -> FxBuilder:
    fx = FxBuilder("credits4_platebreak")
    root = fx.empty("platebreak_root")

    # Split flash: ONE sharp hot pop at the fracture line — authored to peak inside
    # the act's 4t snap window (the visual crack of the audible crack SFX).
    (fx.particle_emitter(
            "platebreak_flash",
            duration=30, looping=False, start_lifetime=constant(10),
            start_speed=constant(0), start_size=nf3(2.6), max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(1)),
                               burst(time=3, count=constant(1))])
        .with_shape(circle(radius=1.6, thickness=0.3))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.5, 1.15, 2.0)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 1.7, [(0.0, 0.35, 1.0, 1.0, 0.3, 1.0, 1.0, 0.45)]),
            # Two flashes land 3t apart on the same seam — a birth tint keeps the
            # overlap from summing to a white disc.
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.9), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.12, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-10.0, -6.0, -10.0), (10.0, 10.0, 10.0)))

    # Shard puffs: a handful of slow dark chips kicked outward off the split seam,
    # sinking as they fade — the small-mass echo of the sub-plates shearing apart.
    (fx.particle_emitter(
            "platebreak_shards",
            duration=30, looping=False, start_lifetime=random_between(16, 26),
            # 1.8-4.9 blocks off the 6-block shell over a 16-26t life — chips that
            # visibly leave the plate (they used to move 0.2-0.65 of a block).
            start_speed=random_between(speed_for(1.8, 16), speed_for(4.9, 26)),
            start_size=nf3(random_between(0.2, 0.45)), max_particles=16)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=1, count=constant(14))])
        .with_shape(sphere(radius=6.0, thickness=0.25))
        .with_curves(
            # Sink 0.8-3.1 blocks while fading (blocks/SECOND — the old -0.06..-0.16
            # dropped a chip by 5 cm, so nothing read as "falling").
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           random_between(-speed_for(3.1, 26), -speed_for(0.8, 16)),
                           constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.65), (0.7, 0.3), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.15, *VIOLET_MID), (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.15, *VIOLET_MID_ALT), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 0.9, 1.4)))
        .with_cull_box((-14.0, -12.0, -14.0), (14.0, 12.0, 14.0)))

    # Fracture dust: one soft smoke exhale along the split — mass without noise.
    (fx.particle_emitter(
            "platebreak_dust",
            duration=30, looping=False, start_lifetime=random_between(18, 28),
            # ~1.2 blocks of exhale off the 4-block shell over a 23t life.
            start_speed=constant(speed_for(1.2, 23)),
            start_size=nf3(random_between(1.4, 2.6), random_between(1.4, 2.6),
                           random_between(1.4, 2.6)),
            simulation_space="Local", max_particles=10)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=1, count=constant(8))])
        .with_shape(sphere(radius=4.0, thickness=0.4))
        .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.3), (0.7, 0.16), (1.0, 0.0)],
                [(0.0, *DUST_BIRTH), (0.2, 0.15, 0.08, 0.22), (1.0, 0.06, 0.03, 0.1)],
                [(0.0, *DUST_BIRTH), (0.2, 0.12, 0.07, 0.19), (1.0, 0.05, 0.02, 0.08)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-12.0, -8.0, -12.0), (12.0, 10.0, 12.0)))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:credits4_jetburst — the relativistic jets shred a sub-plate
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# `lifetimeByEmitterSpeed` — the census asks for it here (§2 row 30: "Jet-Knoten mit
# lifetimeByEmitterSpeed, erster Nutzer überhaupt"). It is now authored on both streams,
# but the visible effect is carried by the curve pair below. WHY, from the 2.1.5 jar:
#
#   LifetimeByEmitterSpeedSetting.getLifetime(particle, emitter, base):
#       float s = emitter.getVelocity().length() * 20f;          // blocks/SECOND
#       float t = (s - speedRange.a) / (speedRange.b - speedRange.a);
#       return (int) (multiplier.get(t, particle::getMemRandom) * base);
#
#   Emitter.getVelocity() returns the field `velocity`, which Emitter.update() derives
#   from `position - previousPosition` — i.e. how fast the EMITTER OBJECT travels through
#   the world, not how fast its particles leave it.
#
# `credits4_jetburst` is spawned by `CreditsSequence.mapRipBeats` through
# `PhotonFxRegistry` -> `PhotonBridge.spawn(fx, pos)` at `blackHole.fxAnchor()` — a fixed
# Vec3, no entity leg. The emitter therefore never moves, `s` is identically 0, `t` is
# pinned at 0 and the multiplier is frozen at whatever it reads at zero. The module can
# only ever be a constant scale here; it is NOT a way to make fast knots live longer.
#
# So it ships ARMED BUT NEUTRAL: the multiplier curve starts at y=0, hence exactly
# `lower` = 1.0 at t=0, hence `(int)(1.0 * base)` = the unscaled lifetime. Today that is
# a runtime no-op (the asset is bit-honest about being the feature's first user); if a
# later beat ever re-anchors the burst onto the moving shred display, the jets stretch
# from ×1.0 to ×1.8 for free, without another asset pass.
#
# The read the census actually wants — "faster knots live longer" — is delivered by
# `SEG_JET_DECAY` instead: `startSpeed` and `startLifetime` are BOTH curves on the
# emitter's own duration axis, so `TileParticle.setupParticle` samples them at the same
# `emitter.getT()` and they are perfectly correlated by construction. A random pair could
# not do this: `RandomConstant.get` memoizes per NumberFunction INSTANCE
# (`particle.getMemRandom(this)`), so two `random_between`s roll independently.
#
#   t=0   speed 24.0 b/s, lifetime 34t  ->  24.0 x 0.05 x 34 = 40.8 blocks
#   t=1   speed 12.0 b/s, lifetime 17t  ->  12.0 x 0.05 x 17 = 10.2 blocks
#
# Lifetime is held exactly proportional to speed (34/24 = 17/12), which is the law
# `lifetimeByEmitterSpeed` would apply — so reach goes as speed SQUARED and the jet lances
# 40 blocks out of the throat on the burst's opening knot, then collapses to a 10-block
# stub as the shred drains. `sizeBySpeed` re-uses the same 12-24 b/s window so the long
# knots are also the fat ones.
# ---------------------------------------------------------------------------
#: Emitter-progress window the jet knots sweep, blocks/second (also the `sizeBySpeed`
#: window, so the two modules read off one number).
JET_SPEED_LO, JET_SPEED_HI = 12.0, 24.0
#: Proportional lifetimes: `JET_LIFE_HI / JET_SPEED_HI == JET_LIFE_LO / JET_SPEED_LO`.
JET_LIFE_LO, JET_LIFE_HI = 17.0, 34.0
#: Rising ease for the armed `lifetimeByEmitterSpeed` multiplier. Starts at y=0 so a
#: motionless emitter reads exactly `lower` (= ×1.0) — see the block above.
SEG_SPEED_RISE = (0.0, 0.0, 0.25, 0.08, 0.68, 0.9, 1.0, 1.0)


def _jet_stream(fx: FxBuilder, root, name: str, down: bool):
    """One fast particle stream racing out along the jet axis (±Y off the anchor)."""
    emitter = (fx.particle_emitter(
            name,
            duration=60, looping=False,
            start_lifetime=curve(JET_LIFE_LO, JET_LIFE_HI, [SEG_JET_DECAY],
                                 "duration", "lifetime"),
            start_speed=curve(JET_SPEED_LO, JET_SPEED_HI, [SEG_JET_DECAY],
                              "duration", "speed"),
            start_size=nf3(random_between(0.25, 0.5)), max_particles=40)
        .child_of(root)
        # The trickle decays on the same shape as speed/lifetime, so the throat thins out
        # instead of spitting the same stream of stubs after the pressure is gone.
        .with_emission(rate=curve(0.0, 0.9, [SEG_JET_DECAY], "duration", "value"),
                       bursts=[burst(time=0, count=constant(14)),
                               burst(time=10, count=constant(9)),
                               burst(time=22, count=constant(6))])
        .with_shape(cone(angle=7.0, radius=1.6, thickness=0.5))
        .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 0.85), (0.6, 0.5), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.1, *VIOLET_HOT), (0.55, *VIOLET_MID),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.12, *VIOLET_HOT_ALT), (0.55, *VIOLET_MID_ALT),
                 (1.0, *VIOLET_DEEP)]),
            # Fat head knots, thin tail stubs — the same 12-24 b/s window as the curve
            # pair. Back on the fxlib helpers since C2 fixed `_min_max` to the a/b keys
            # the LDLib2 `Range` codec actually reads (the raw with_module dicts were a
            # C5-local workaround; byte-identity of the rebuild is verified in the C2
            # report).
            size_by_speed=dict(
                size=nf3(curve(0.75, 1.5, [SEG_SPEED_RISE], "speed", "size")),
                range=(JET_SPEED_LO, JET_SPEED_HI)),
            lifetime_by_emitter_speed=dict(
                multiplier=curve(1.0, 1.8, [SEG_SPEED_RISE], "speed", "multiplier"),
                range=(0.0, 6.0)))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.35, 1.1, 1.8)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.0,
                       length_scale=1.8)
        .with_cull_box((-16.0, -55.0, -16.0), (16.0, 55.0, 16.0)))
    if down:
        emitter.rotated(180.0, 0.0, 0.0)
    return emitter


def build_credits4_jetburst() -> FxBuilder:
    fx = FxBuilder("credits4_jetburst")
    root = fx.empty("jetburst_root")

    # Two opposed streams: the up (approaching, Doppler-bright in the shader) jet and
    # the down (receding) jet. The opening knot reaches 40.8 blocks and the burst stays
    # past the ~26-block maw until ~t=0.4, so the streams visibly extend the strobing
    # shader columns before collapsing back into the throat.
    _jet_stream(fx, root, "jetburst_up", down=False)
    _jet_stream(fx, root, "jetburst_down", down=True)

    # Stretched sparks: a handful of LONG hot streaks riding the same axis — the
    # display spray's brightest siblings (rare, so they read as events, not noise).
    (fx.particle_emitter(
            "jetburst_sparks",
            duration=60, looping=False,
            # Same proportional law as the streams (22/45 == 13.2/27), one octave hotter:
            # the t=0 spark throws 49.5 blocks, the last one at t=0.53 still throws 31 —
            # so the sparks always outrun the stream head they ride with.
            start_lifetime=curve(13.2, 22.0, [SEG_JET_DECAY], "duration", "lifetime"),
            start_speed=curve(27.0, 45.0, [SEG_JET_DECAY], "duration", "speed"),
            start_size=nf3(random_between(0.4, 0.7)), max_particles=10)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=2, count=constant(4)),
                               burst(time=16, count=constant(3)),
                               burst(time=32, count=constant(2))])
        .with_shape(cone(angle=4.0, radius=1.0, thickness=0.3, arc_mode="Random"))
        .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.08, 1.0), (0.5, 0.55), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.08, 0.9, 0.82, 1.0), (1.0, *VIOLET_MID)],
                [(0.0, *VIOLET_BIRTH), (0.1, 0.82, 0.74, 1.0), (1.0, *VIOLET_MID_ALT)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.5, 1.2, 2.0)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.8,
                       length_scale=2.6)
        .with_cull_box((-12.0, -60.0, -12.0), (12.0, 60.0, 12.0)))

    # Axis glow: a faint violet haze hugging the launch throat so the burst has a
    # body at the anchor (the shader's jet root sits on the same screen spot).
    (fx.particle_emitter(
            "jetburst_throat",
            duration=60, looping=False, start_lifetime=random_between(20, 32),
            # ~0.8 blocks of swell off the 3-block throat shell over a 26t life — the
            # haze must stay a throat, so this one is deliberately the slowest thing here.
            start_speed=constant(speed_for(0.8, 26)),
            start_size=nf3(random_between(2.0, 3.4), random_between(2.0, 3.4),
                           random_between(2.0, 3.4)),
            simulation_space="Local", max_particles=8)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(6))])
        .with_shape(sphere(radius=3.0, thickness=0.5))
        .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.3), (0.7, 0.16), (1.0, 0.0)],
                [(0.0, *DUST_BIRTH), (0.15, 0.3, 0.18, 0.45), (1.0, 0.12, 0.06, 0.2)],
                [(0.0, *DUST_BIRTH), (0.15, 0.24, 0.14, 0.4), (1.0, 0.1, 0.05, 0.17)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-10.0, -10.0, -10.0), (10.0, 10.0, 10.0)))
    return fx


BUILDERS = {
    "credits4_crackfront.fx": build_credits4_crackfront,
    "credits4_platebreak.fx": build_credits4_platebreak,
    "credits4_jetburst.fx": build_credits4_jetburst,
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
