#!/usr/bin/env python3
"""grave_lantern_fx — FX-Wave-13 N4 "Seelenlaterne am Grab" (census §6 row N4).

One asset, one WINDOWED loop:

    eclipse:grave_soul_lantern   the ghost lantern hovering over a player grave

The client controller is `client/lives/GraveLanternFx` (a per-grave
`PhotonBridge.spawnLoop` window with hysteresis — the `StormFxClient` crown-halo shape,
because `PhotonFxRegistry.ensureLoop` manages exactly ONE loop per logical id and a
hardcore map has many graves at once). The loop anchors at the grave block CENTER, so
everything here is authored in grave-local space with the lamp head at y = +{LAMP_Y}.

AUTHORING NOTES (what the A4 "Laternenschwarm" pass proved — census §2 row 12):

  * Photon's `renderMode: Model` BAKES the block model to a single UV'd cube. A
    `soul_lantern` at the size it wants to be reads as a crate, so the body stays SMALL
    ({LAMP_SIZE} b) and the GLOW carries the lamp — the halo emitter is the effect, the
    cube is only the silhouette hint inside it.
  * A Model particle without the `lights` module renders at the ambient lightmap of the
    spot it hovers in, i.e. as a dark lump at night. Every visible emitter here is
    forced to sky/block 15.
  * The `mesh` shape doubles as the model source for `renderMode: Model` (FX_FORMAT
    §3.2), so the shape scale is held at {LAMP_JITTER} — the lamp must be at the SAME
    point every loop cycle, otherwise the 80t re-emission reads as a teleport.
  * `TrailSection`/`AraPhysicsSetting` are LDLib2 `ToggleGroup`s: without an explicit
    `_enable: 1b` their payload is never deserialised (the A4 finding). The Ara thread
    here is an embedded `trails` ARA_TRAIL config, so the flag is written by hand.

PALETTE (the emotional marker of the hardcore map): a SMALL warm flame — the only warm
thing at a grave — inside a cold violet field. Warm carries the "someone was here", cold
violet carries "and the veil took them". Birth tints are dark on every ramp, HDR is
capped at the wave-13 stacking ceiling ({HDR_CEILING}), and the whole tree stays under
~40 live particles because a grave lantern is a DAUER-PRÄSENZ effect, not a payoff.

Run:  python3 tools/photon/grave_lantern_fx.py
Then: python3 tools/photon/fxlib.py validate --lint
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import *  # noqa: F401,F403 - fxlib is the sanctioned star-import API

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"

#: `photon:.../smoke.png` is a 2x2 FLIPBOOK, not a single puff — drawn without a
#: `uvAnimation` module every particle renders the whole sheet, i.e. four smoke blobs in a
#: square (the in-game finding that killed the first soft-halo pass). Holding
#: `frameOverTime` at 0 with a random `startFrame` picks ONE of the four per particle and
#: keeps it there, which also gives the halo free silhouette variety.
SMOKE_TILES = dict(tiles=(2, 2), animation="WholeSheet",
                   frame_over_time=constant(0.0),
                   start_frame=random_between(0.0, 3.99), cycle=1.0)

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4) — nothing here goes above it.
HDR_CEILING = 1.45
#: Lamp head height over the grave block CENTER (the loop anchor), in blocks.
LAMP_Y = 1.35
#: Baked-cube edge length of the soul-lantern model particle (see the A4 note above).
LAMP_SIZE = 0.34
#: Mesh-shape spread for the lamp body — effectively zero: the lamp must not wander.
LAMP_JITTER = 0.02
#: One loop cycle in ticks; the lamp body's lifetime equals it, so exactly one is alive.
LOOP_TICKS = 80
#: Top face of the grave block in loop-anchor space (the anchor is the block CENTER and
#: `eclipse:grave` is a full cube_column) — the slab pool and the Ara thread's landing
#: point both sit a hair above it so nothing renders INSIDE the block.
SLAB_TOP = 0.55

#: Local cull AABB — lamp + halo + motes + the Ara thread down to the grave slab.
CULL = ((-2.0, -1.0, -2.0), (2.0, 3.0, 2.0))


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def ribbon_renderer(material_entry, cull_box=None):
    """Renderer compound for EMBEDDED trail/ara configs (trails module, FX_FORMAT §4.2/4.3).

    fxlib's `_RendererMixin` only serves standalone emitters; an embedded AraTrailConfig
    carries its own renderer block, and without one the ribbon falls back to the MISSING
    (pink) material.
    """
    cull = {"_enable": B(0)} if cull_box is None else {"_enable": B(1), "cullBox": aabb(*cull_box)}
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": cull, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


# ---------------------------------------------------------------------------
# Candle flicker envelopes. Two DIFFERENT shapes fed to `random_curve`, which lerps
# between them once per particle off the memoized TileParticle roll — so the halo, the
# flame tongues and the motes never breathe in lockstep (the A4 swarm lesson, applied to
# a single lamp: one shared envelope reads as a machine, two read as a flame).
# Every control point sits genuinely off its chord (LINT-LINEAR-CURVE tolerance 0.02).
# ---------------------------------------------------------------------------
_FLICKER_A = [(0.0, 0.34, 0.06, 1.0, 0.18, 0.62, 0.34, 0.9),
              (0.34, 0.9, 0.52, 0.45, 0.7, 1.0, 1.0, 0.16)]
_FLICKER_B = [(0.0, 0.2, 0.1, 0.86, 0.3, 0.3, 0.46, 1.0),
              (0.46, 1.0, 0.6, 0.38, 0.86, 0.82, 1.0, 0.1)]
#: Gust: the flame nearly gutters mid-life and recovers — the "is it about to go out?" beat.
_GUTTER = [(0.0, 1.0, 0.12, 0.86, 0.3, 0.18, 0.46, 0.24),
           (0.46, 0.24, 0.62, 0.3, 0.8, 1.0, 1.0, 0.78)]


def build_grave_soul_lantern() -> FxBuilder:
    fx = FxBuilder("grave_soul_lantern")

    # ---------------------------------------------------------------- lamp body
    # ONE baked soul-lantern cube, re-emitted exactly once per loop cycle with a lifetime
    # equal to the cycle, so the body is continuous without ever stacking. It turns very
    # slowly (0.35 deg/tick ~ 28 deg per cycle) — enough that the silhouette is alive,
    # slow enough that nobody reads it as a spinning item drop.
    (fx.particle_emitter(
            "lamp_body",
            duration=LOOP_TICKS, looping=True, prewarm=20,
            start_lifetime=constant(LOOP_TICKS), start_speed=constant(0.0),
            start_size=nf3(LAMP_SIZE), start_rotation=nf3(constant(0), constant(0), constant(0)),
            simulation_space="Local", max_particles=4)
       .at(0.0, LAMP_Y, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(mesh("block/soul_lantern", emit_from="Triangle"), scale=nf3(LAMP_JITTER))
       .with_material(block_atlas_material(blend=BLEND_ALPHA, cull=True, depth_test=True,
                                           depth_mask=True))
       .with_renderer(render_mode="Model", use_block_uv=True, model_pivot=(0.5, 0.5, 0.5),
                      facing_mode="ROTATE_Y", shade=True)
       .with_cull_box(*CULL)
       .with_curves(
            rotation_over_lifetime=dict(yaw=constant(0.35)),
            # A hair of vertical drift so the lamp HANGS rather than sits (0.06 b/s up,
            # noise pushes it back — the two together are the hover).
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.06), constant(0))),
            noise=dict(frequency=0.35, quality="Noise3D",
                       position=nf3(constant(0.035), constant(0.05), constant(0.035))))
       # Light SOURCE, not a lit block: without this the cube is a dark lump at night,
       # which is exactly when a grave is looked at.
       .with_lights(sky=15, block=15))

    # ---------------------------------------------------------------- warm halo (the read)
    # "Glow dominiert": the halo is BIGGER than the baked cube, so the lamp reads as light
    # with a hint of housing inside it instead of a floating crate. The flicker is the
    # whole point — random_curve pairs two envelopes so consecutive halos never match.
    #
    # ADDITIVE BUDGET (the in-game finding, and the reason every number here is small):
    # `rate x lifetime` particles overlap on the SAME point, and additive blending sums
    # them. The first pass ran ~6 concurrent halos at HDR 1.45 and alpha 0.62 — a summed
    # ~8x over white, i.e. a small SUN over the grave with the lamp, the flame and the
    # motes all invisible inside it. The steady-state count (0.16 x 21 ~ 3.4) times the
    # peak alpha times the HDR peak is held near 1.0 now: a hot core with a real falloff,
    # which is what actually reads as a lantern.
    (fx.particle_emitter(
            "lamp_halo",
            duration=LOOP_TICKS, looping=True, prewarm=20,
            start_lifetime=random_between(16, 26), start_speed=constant(0.0),
            start_size=nf3(random_between(0.36, 0.52)),
            simulation_space="Local", max_particles=6)
       .at(0.0, LAMP_Y, 0.0)
       .with_emission(rate=constant(0.16))
       .with_shape(sphere(radius=0.05, thickness=1.0))
       # SMOKE, not CIRCLE: circle.png has a near-hard edge, and a stack of them reads as an
       # opaque amber BALL hanging over the grave (the second in-game finding). The smoke
       # puff's long falloff is what turns the same energy into a glow with an edge you
       # cannot point at — and it lets the baked lantern cube show THROUGH the light.
       .with_material(texture_material(SMOKE, hdr=hdr(1.0, 0.58, 0.24), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box(*CULL)
       .with_curves(
            uv_animation=SMOKE_TILES,
            size_over_lifetime=random_curve(0.72, 1.1, _FLICKER_A, _FLICKER_B,
                                            "lifetime", "size"),
            # Birth tint DARK (ember-brown), peak warm amber, out through deep ember.
            color_over_lifetime=random_gradient(
                [(0.0, 0.0), (0.16, 0.3), (0.7, 0.2), (1.0, 0.0)],
                [(0.0, 0.26, 0.13, 0.05), (0.3, 1.0, 0.72, 0.34), (1.0, 0.92, 0.42, 0.16)],
                [(0.0, 0.0), (0.22, 0.24), (0.66, 0.18), (1.0, 0.0)],
                [(0.0, 0.22, 0.1, 0.04), (0.35, 0.98, 0.64, 0.26), (1.0, 0.8, 0.3, 0.1)]))
       .with_lights(sky=15, block=15))

    # ---------------------------------------------------------------- flame tongues
    # The small warm flame itself: a handful of tiny tongues licking UP out of the lamp
    # head (offset above the cube so the depth-tested body never eats them). The gutter
    # curve makes the flame nearly die and come back — a grave lantern is not a torch.
    (fx.particle_emitter(
            "lamp_flame",
            duration=LOOP_TICKS, looping=True, prewarm=20,
            start_lifetime=random_between(9, 16), start_speed=random_between(0.02, 0.06),
            start_size=nf3(random_between(0.07, 0.12), random_between(0.11, 0.19),
                           random_between(0.07, 0.12)),
            simulation_space="Local", max_particles=10)
       .at(0.0, LAMP_Y + 0.06, 0.0)
       .with_emission(rate=constant(0.34))
       .with_shape(sphere(radius=0.045, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.3, 0.86, 0.38), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.28, 0.6), constant(0))),
            size_over_lifetime=random_curve(0.3, 1.0, _GUTTER, _FLICKER_B, "lifetime", "size"),
            noise=dict(frequency=0.9, quality="Noise2D",
                       position=nf3(constant(0.02), constant(0.012), constant(0.02))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.55), (0.62, 0.34), (1.0, 0.0)],
                [(0.0, 0.3, 0.14, 0.05), (0.25, 1.0, 0.82, 0.46), (1.0, 0.86, 0.32, 0.1)]))
       .with_lights(sky=15, block=15))

    # ---------------------------------------------------------------- cold violet rim motes
    # The counterpoint: slow, cold, sparse. They are born on a shell around the lamp and
    # drift outward-and-up, so the warm core always sits inside a violet field. This is
    # the layer that says "veil", and it is deliberately the DIMMEST thing here.
    (fx.particle_emitter(
            "rim_motes",
            duration=LOOP_TICKS, looping=True, prewarm=40,
            start_lifetime=random_between(30, 52), start_speed=random_between(0.01, 0.05),
            start_size=nf3(random_between(0.035, 0.075), random_between(0.035, 0.075),
                           random_between(0.035, 0.075)),
            simulation_space="Local", max_particles=24)
       .at(0.0, LAMP_Y - 0.1, 0.0)
       .with_emission(rate=constant(0.34))
       .with_shape(sphere(radius=0.42, thickness=0.5))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.66, 0.36, 1.1), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.18, 0.45), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.1, 0.4), constant(0)),
                offset=nf3(0), radial=random_between(-0.1, 0.22)),
            size_over_lifetime=random_curve(0.35, 1.0, _FLICKER_B, _FLICKER_A,
                                            "lifetime", "size"),
            noise=dict(frequency=0.4, quality="Noise3D",
                       position=nf3(constant(0.03), constant(0.02), constant(0.03))),
            # SAC_VOID birth -> GLI_VIOLET mid -> SAC_DEEP out (all §1 palette tokens).
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.24, 0.5), (0.72, 0.34), (1.0, 0.0)],
                [(0.0, 0.18, 0.14, 0.28), (0.35, 0.73, 0.55, 1.0), (1.0, 0.48, 0.31, 0.82)]))
       .with_lights(sky=15, block=15))

    # ---------------------------------------------------------------- the Ara thread
    # "Dünner Ara-Faden nach unten": a near-invisible wisp sinks from the lamp head to the
    # slab and DRAGS the ribbon. An Ara trail needs a MOVING carrier — a static emitter
    # draws nothing at all — so the thread is a slow drip that continuously re-forms,
    # which also reads as the grave still leaking. The carrier is dim on purpose: the
    # ribbon is the effect. Physics (`_enable` written by hand, see the module docstring)
    # gives the thread its sag and sway.
    #
    # Geometry: Photon scales `linear` by 0.05 per tick, so a unit is ~1 block/s — the
    # 1.15 sink over 12 ticks covers 0.69 b, from y = LAMP_Y - 0.12 down to just above
    # SLAB_TOP. It must NOT overshoot: the grave is a full cube and a ribbon inside it is
    # invisible z-fighting mush.
    (fx.particle_emitter(
            "soul_thread",
            duration=LOOP_TICKS, looping=True, prewarm=20,
            start_lifetime=constant(12), start_speed=constant(0.0),
            start_size=nf3(0.03), start_color=color(0x40FFFFFF),
            simulation_space="Local", max_particles=6)
       .at(0.0, LAMP_Y - 0.12, 0.0)
       # Rate vs. lifetime IS the thread's continuity (the third in-game finding). One
       # ribbon only spans the full drop at the END of its carrier's life, so a rate that
       # keeps a single drip alive shows a stub that grows and vanishes. ~3.6 concurrent
       # carriers at staggered depths overlap into ONE continuous thread that still visibly
       # runs downward — the grave "leaking" instead of a blinking dash.
       .with_emission(rate=constant(0.3))
       .with_shape(sphere(radius=0.03, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.5, 0.3, 0.85), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(-1.15), constant(0))),
            noise=dict(frequency=0.6, quality="Noise2D",
                       position=nf3(constant(0.02), constant(0.0), constant(0.02))))
       .with_module("trails", {
            "ratio": F(1.0),
            "lifetime": constant(0.65),
            "dieWithParticles": B(1),
            "sizeAffectsWidth": B(0),
            "sizeAffectsLifetime": B(0),
            "inheritParticleColor": B(0),
            "trailType": "ARA_TRAIL",
            "araConfig": {
                "space": "World",
                "alignment": "View",
                "thickness": F(0.055),
                "smoothness": I(3),
                # highQualityCorners stays OFF: its miter compensation divides thickness
                # by max(dot, 0.15), which shreds a slow, densely-sampled thread into a
                # comb of spikes (the herald_shard_trail derivation).
                "highQualityCorners": B(0),
                "time": F(0.65),          # SECONDS (the ara exception) — spans the drip
                "minDistance": F(0.02),
                "textureMode": "Stretch",
                # Full at the head (at the lamp), tapering to a true point at the slab.
                "thicknessOverLength": curve(
                    0.0, 1.0, [(0.0, 1.0, 0.22, 0.86, 0.7, 0.24, 1.0, 0.0)],
                    "length", "thickness"),
                "colorOverLength": gradient(
                    [(0.0, 0.72), (0.4, 0.46), (1.0, 0.0)],
                    [(0.0, 0.78, 0.6, 1.0), (0.55, 0.5, 0.3, 0.85), (1.0, 0.22, 0.12, 0.4)]),
                "physicsSetting": {
                    "_enable": B(1),      # the flag IS the switch (ToggleGroup, see above)
                    "warmup": F(0.0),
                    "gravity": L([F(0.0), F(-0.1), F(0.0)]),
                    "inertia": F(0.28),
                    "velocitySmoothing": F(0.8),
                    "damping": F(0.86)},
                "renderer": ribbon_renderer(
                    texture_material(CIRCLE, hdr=hdr(0.7, 0.4, 1.2), blend=BLEND_ADDITIVE),
                    cull_box=CULL)}}))

    # ---------------------------------------------------------------- slab pool
    # Where the thread lands: one dim horizontal violet pool lying ON the grave, breathing
    # with the same flicker family. It is what makes the lantern read as belonging to THIS
    # block from 40 blocks out, and it is a single particle.
    (fx.particle_emitter(
            "slab_pool",
            duration=LOOP_TICKS, looping=True, prewarm=20,
            start_lifetime=constant(LOOP_TICKS), start_speed=constant(0.0),
            start_size=nf3(1.05), simulation_space="Local", max_particles=3)
       .at(0.0, SLAB_TOP, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, hdr=hdr(0.42, 0.24, 0.8), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE")
       .with_cull_box(*CULL)
       .with_curves(
            uv_animation=SMOKE_TILES,
            size_over_lifetime=random_curve(0.86, 1.06, _FLICKER_A, _FLICKER_B,
                                            "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.3), (0.9, 0.26), (1.0, 0.0)],
                [(0.0, 0.16, 0.12, 0.26), (0.4, 0.6, 0.42, 0.95), (1.0, 0.4, 0.26, 0.72)]))
       .with_lights(sky=15, block=15))
    return fx


BUILDERS = {
    "grave_soul_lantern.fx": build_grave_soul_lantern,
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
