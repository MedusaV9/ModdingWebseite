#!/usr/bin/env python3
"""nether_open_fx — Photon assets for the day-2 NETHER OPENING sequence.

Committed fxlib source of truth (binary-blob diff law, FX_FORMAT.md §7) for the eight
`.fx` blobs of `sequence/NetherOpeningSequence` + the breach ambience. F-102 ("Nether-
Masse") re-tuned the pre-eruption phases for STILL-FRAME readability: every phase owns a
dominant silhouette (Kegel -> Ringe -> Speichen-Stern -> Pilz-Säule -> Glutflocken), not
just a particle-count ramp — the in-game replay acceptance showed phases 1-2 reading as
static until the eruption:

  phase 1 OMEN      eclipse:nether_omen_ash        one-shot 240t: THE silhouette is a dark
                                                   ash VEIL CONE (apex ~22 blocks up) whose
                                                   soot slides down the lateral surface;
                                                   under it the W11 ash swell + lava glints
                                                   + ground seep skirt. veil_slump bakes
                                                   the mid-omen ground-shock poff at t=120
                                                   (NetherOpenClientFx kicks the camera on
                                                   the same tick)
  phase 2 TREMOR    eclipse:nether_quake_fissure   one-shot 140t: ONE glowing ground crack
                                                   (jagged randomA line) + its dust lift;
                                                   the client stamps several around the rim
                    eclipse:nether_tremor_waves    one-shot 360t (F-102): the quake carpet —
                                                   pebbles POPPING off the whole footprint
                                                   (real collision physics) under a boiling
                                                   flipbook ground-dust heave, both swelling
                                                   with the phase
                    eclipse:nether_tremor_ring     one-shot 50t (F-102): ONE beat stamp —
                                                   a flat dust ring racing outward + a
                                                   kiesel splash + grit glints; fired per
                                                   hop-wave SLAM via the
                                                   fx/cue/nether_tremor_slam cue lane
  phase 3 RUPTURE   eclipse:nether_rupture_spoke   one-shot 130t (F-102): ONE radial ember
                                                   RISS-SPEICHE (jagged glowing line local
                                                   +X 3..15) + rubble fountains popping
                                                   along it + tear dust; the client stamps
                                                   a 6-spoke star, each yawed outward
                    eclipse:nether_eruption        one-shot 200t: fire column + colliding
                                                   ember shrapnel + flipbook smoke pillar +
                                                   THREE staggered ground shock rings (the
                                                   echo waves land on the aftershock sound
                                                   stack) + tall dust curtains rolling
                                                   outward over the halo (W13/A6) + the
                                                   F-102 MUSHROOM CAP: a crown of flipbook
                                                   puffs materialising around the column
                                                   apex and spreading laterally — the
                                                   still-frame reads Säule + Pilz
  phase 4 AFTERMATH eclipse:nether_pit_plume       WINDOWED loop: the permanent smoke cloud
                                                   hanging over the pit — GPU-instanced
                                                   flipbook soot swathes (ember veins twitch
                                                   through the 4-frame boil), fire tongues
                                                   burning inside them, IRREGULAR ember-jet
                                                   burst cascades (startDelay spread +
                                                   burst probability instead of a uniform
                                                   spurt loop), soft-particle ground smoke
                                                   hugging the crater lip (SceneDepth fade,
                                                   eclipse:soft_particle), and a whisper-
                                                   subtle rgb_split heat shimmer directly
                                                   over the mouth (A0 distortion shader —
                                                   Photon's own stack has no refraction).
                                                   F-102 thickening: lazy dark FOG SHELLS
                                                   around the body, twitching EMBER MOTES
                                                   inside it, and probability-gated FIRE
                                                   TONGUES licking out of the mouth
  ambient           eclipse:nether_ash_snow        WINDOWED loop (N11): sparse dark ash
                                                   flakes snowing over a wide radius around
                                                   the pit + faint drifting soot haze —
                                                   random_gradient grey variation, tiny
                                                   counts, GPU-instanced. F-102 Nachglut:
                                                   a handful of TRÄGE GLUTFLOCKEN (slow
                                                   glowing flakes) sinking among them

Loop law (INTEGRATION.md §4): every looping emitter carries a renderer cull box + hard
maxParticles. Collision emitters keep parallelUpdate 0b (FX_FORMAT §3.1/§3.3 — collision
does real level queries and is forbidden on the parallel path); GPU-instanced emitters
carry NO physics (LINT-GPU-PHYSICS). W13 stacking law: dark birth tints, HDR <= 1.45 on
every plume/ash material (permanent loops must not own the bloom budget), heavy elements
low + slow.

Flipbook sheet: nether_plume_atlas.png (4x4, authored below, storm_puff_atlas school) —
each ROW is one soot-puff variant boiling through a seamless 4-frame loop with ember
veins baked in whose gain PULSES across the frames (the "zuckende Glut"); Photon
`uvAnimation {tiles:[4,4], animation:SingleRow}` memoizes a random row per particle and
frameOverTime plays the twitch. Verified against the Photon 2.1.5 jar:
UVAnimationSetting{tiles:Vector2i, animation:WholeSheet|SingleRow, frameOverTime:NF,
startFrame:NF, cycle:float}; the GPU-instanced path uploads TileParticle.getRealUVs()
per instance, so flipbook + useGPUInstance compose (ParticleInstanceRenderer.upload).

Run:  python3 tools/photon/nether_open_fx.py            # writes + validates all 8 assets
      python3 tools/photon/nether_open_fx.py --atlas    # force-regenerate the atlas PNG
"""
from fxlib import *  # noqa: F401,F403 - the authoring DSL is the point
from fxlib import B, F, I, L  # explicit for the raw module compounds

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
PLUME_ATLAS = "eclipse:textures/particle/nether_plume_atlas.png"
PLUME_ATLAS_PATH = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle/nether_plume_atlas.png"

# Crater geometry the assets are authored against (BreachGeometry): mouth r 16, creep halo
# r 28. Cull boxes are sized off the halo so nothing pops while the camera orbits the rim.
CRATER_R = 16.0
HALO_R = 28.0

# Phase lengths in ticks — MUST stay in sync with NetherOpeningSequence's tick table
# (the assets are finite one-shots; a shorter asset would die mid-phase).
OMEN_TICKS = 240
FISSURE_TICKS = 140
TREMOR_TICKS = 360          # TREMOR_END - OMEN_TICKS (the quake-carpet asset spans it)
ERUPTION_TICKS = 200

# F-102 silhouette geometry: the omen veil cone (apex height over the lip plane) and the
# rupture spoke line (local +X band; the client stamps SPOKE-many, each yawed outward).
VEIL_H = 22.0
SPOKE_X_MIN = 3.0
SPOKE_X_LEN = 12.0
# Beat tick of the mid-omen ground shock INSIDE the omen asset (= phase-local t): the
# veil_slump burst below and NetherOpenClientFx.OMEN_BEAT_AT must agree, or the camera
# kick and the dust poff drift apart.
OMEN_BEAT_TICK = 120
# Beat stamp length of the tremor ring asset (must outlive its ring+splash particles).
TREMOR_RING_TICKS = 50
SPOKE_TICKS = 130


#: Eased 0->1 swell over the emitter lifetime (LINT-LINEAR-CURVE: never ship chord-collinear
#: segments — the ramp must breathe, FX-STYLE-GUIDE house segments).
SEG_SWELL = (0.0, 0.0, 0.32, 0.04, 0.62, 0.96, 1.0, 1.0)
#: Eased 1->0 decay with a held head — a crack tears open hard, then only creeps.
SEG_TEAR_OFF = (0.0, 1.0, 0.1, 1.0, 0.3, 0.22, 1.0, 0.0)


def swell(lower, upper):
    """Eased emission/speed ramp from `lower` to `upper` over the emitter's own lifetime."""
    return curve(lower, upper, [SEG_SWELL])


def tear_off(lower, upper):
    """Eased front-loaded decay from `upper` down to `lower` (the tearing envelope)."""
    return curve(lower, upper, [SEG_TEAR_OFF])


def ribbon_renderer(material_entry):
    """RendererSetting compound for an EMBEDDED araConfig (mirrors fxlib._init_renderer);
    written explicitly so ribbons never fall back to the MISSING (pink) material."""
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": {"_enable": B(0)}, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


# ---------------------------------------------------------------------------
# nether_plume_atlas.png — 1024², 4x4 (W13/A6, storm_puff_atlas school)
# ---------------------------------------------------------------------------
def generate_plume_atlas(path, size=1024, grid=4, seed=20260731):
    """16 soot puffs: each ROW is one variant boiling through a seamless 4-frame loop
    (blob offsets 2π-periodic in the frame phase) for Photon `uvAnimation {tiles:[4,4],
    animation:SingleRow}` — the memoized random row picks the variant, frameOverTime
    plays the boil. What makes it a NETHER sheet: the RGB bakes fire-from-below light
    (bottom warm, top soot-dark) plus discrete ember VEINS whose gain pulses across the
    4 frames on per-vein phases — played back, the glut visibly twitches INSIDE the
    smoke. Rows carry rising ember intensity (0.30/0.55/0.80/1.05), so the random row
    also varies how fiery each swathe reads. Deterministic seed."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    cell = size // grid
    img = np.zeros((size, size, 4), np.float32)
    yy, xx = (np.mgrid[0:cell, 0:cell].astype(np.float32) + 0.5) / cell

    def smoothstep(a, b, x):
        t = np.clip((x - a) / (b - a), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)

    # Transparent margin so bilinear/mip sampling never bleeds across cells.
    edge = np.minimum(np.minimum(xx, 1.0 - xx), np.minimum(yy, 1.0 - yy))
    margin = smoothstep(0.015, 0.09, edge)

    ember_rgb = np.array((1.0, 0.44, 0.16), np.float32)   # FX-STYLE ember family
    row_ember = (0.30, 0.55, 0.80, 1.05)                  # per-row glut gain

    for row in range(grid):
        # Roundish cauliflower cluster (the plume swathes are volumetric, not flat).
        nblobs = 17
        ang = rng.uniform(0.0, 2.0 * np.pi, nblobs)
        dist = rng.uniform(0.0, 1.0, nblobs) ** 0.6
        bx = 0.5 + 0.27 * dist * np.cos(ang)
        by = 0.5 + 0.24 * dist * np.sin(ang)
        br = rng.uniform(0.085, 0.14, nblobs) * (1.2 - 0.4 * dist)
        bw = rng.uniform(0.6, 1.0, nblobs)
        ph = rng.uniform(0.0, 2.0 * np.pi, (nblobs, 2))
        amp = rng.uniform(0.02, 0.05, nblobs)
        ramp = rng.uniform(0.10, 0.20, nblobs)
        # Ember veins: a handful of small warm cores buried low in the cluster; each
        # vein's gain pulses on its own phase — THE twitching-glut mechanism.
        nveins = 6
        vx = 0.5 + rng.uniform(-0.24, 0.24, nveins)
        vy = 0.60 + rng.uniform(-0.08, 0.16, nveins)      # low = fire side
        vr = rng.uniform(0.030, 0.055, nveins)
        vph = rng.uniform(0.0, 2.0 * np.pi, nveins)
        vgain = rng.uniform(0.55, 1.0, nveins) * row_ember[row]
        for frame in range(grid):
            phase = 2.0 * np.pi * frame / grid
            density = np.zeros((cell, cell), np.float32)
            for i in range(nblobs):
                cx = bx[i] + amp[i] * np.sin(phase + ph[i, 0])
                cy = by[i] + amp[i] * np.cos(phase + ph[i, 1])
                r = br[i] * (1.0 + ramp[i] * np.sin(phase + ph[i, 0] + ph[i, 1]))
                density += bw[i] * np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2.0 * r * r))
            density /= np.percentile(density, 99.2)
            alpha = smoothstep(0.24, 0.62, density) * margin
            # Soot body lit from BELOW (yy grows downward on the sheet): bottom warm-grey,
            # top near-black. Dark birth tints live in the sheet itself (stacking law).
            light = 0.09 + 0.23 * yy + 0.08 * np.clip(density, 0.0, 1.0)
            rgb = light[..., None] * np.array((1.0, 0.92, 0.88), np.float32)[None, None, :]
            rgb[..., 0] += 0.04 * yy                       # faint ember cast low
            # Twitching glut: pulse each vein's gain over the 4-frame loop.
            glow = np.zeros((cell, cell), np.float32)
            for i in range(nveins):
                pulse = 0.35 + 0.65 * (0.5 + 0.5 * np.sin(phase * 2.0 + vph[i]))
                glow += vgain[i] * pulse * np.exp(
                    -((xx - vx[i]) ** 2 + (yy - vy[i]) ** 2) / (2.0 * vr[i] * vr[i]))
            glow *= np.clip(density, 0.0, 1.0)             # veins live INSIDE the smoke
            rgb += glow[..., None] * ember_rgb[None, None, :]
            tile = np.concatenate([np.clip(rgb, 0.0, 1.0), alpha[..., None]], axis=-1)
            img[row * cell:(row + 1) * cell, frame * cell:(frame + 1) * cell] = tile

    out = (np.clip(img, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out, "RGBA").save(path, optimize=True)
    return path.stat().st_size


# ---------------------------------------------------------------------------
# Phase 1 — OMEN: something under the desert is breathing
# ---------------------------------------------------------------------------
def build_nether_omen_ash() -> FxBuilder:
    """eclipse:nether_omen_ash — block-anchored at the future crater centre on the STILL
    CLOSED surface (BreachGeometry.centerX/lipY/centerZ). Nothing erupts yet: ash wells up
    out of the sand over the whole mouth footprint, a low skirt creeps outward over the
    halo, and single lava glints wink in the hairline cracks. Ramped in over the first
    ~third so the phase starts almost imperceptibly."""
    fx = FxBuilder("nether_omen_ash")

    # F-102: THE omen silhouette — a dark veil CONE standing over the mouth (apex
    # {VEIL_H} blocks up), its soot sliding down the lateral surface. randomB picks the
    # radius fraction, so a uniform roll lands MORE quads near the apex (r ~ B but the
    # area grows with B²) and the tip reads solid in a still frame; the sink + radial
    # creep approximate the slide down the cone. Big, few, DARK quads (stacking law +
    # llvmpipe still-frame read) — the phase starts almost empty and the cone condenses
    # out of nothing over the first third (swell ramp).
    (fx.particle_emitter(
            "veil_cone",
            duration=OMEN_TICKS, looping=False,
            start_lifetime=random_between(80, 140),
            start_speed=constant(0.0),
            start_size=nf3(random_between(2.2, 4.2), random_between(2.2, 4.2),
                           random_between(2.2, 4.2)),
            simulation_space="World", max_particles=110)
       .with_emission(rate=swell(0.5, 3.4))
       .with_shape(function_shape(
            x=f"cos(randomA*2*PI)*{CRATER_R - 2.0}*randomB",
            y=f"{VEIL_H}*(1-randomB)",
            z=f"sin(randomA*2*PI)*{CRATER_R - 2.0}*randomB"))
       .with_curves(
            velocity_over_lifetime=dict(  # the veil FALLS (inverted sacred vertical)
                linear=nf3(constant(0), random_between(-0.14, -0.06), constant(0)),
                radial=random_between(0.02, 0.05)),
            noise=dict(frequency=0.3, quality="Noise2D",
                       position=nf3(constant(0.04), constant(0.015), constant(0.04))),
            color_over_lifetime=gradient(  # #453B38 -> #1F1A1C, in-hold-out, ceiling 0.5
                [(0.0, 0.0), (0.18, 0.5), (0.8, 0.42), (1.0, 0.0)],
                [(0.0, 0.27, 0.231, 0.22), (1.0, 0.122, 0.102, 0.11)]),
            size_over_lifetime=curve(
                0.7, 1.4,
                [(0.0, 0.0, 0.15, 0.4, 0.5, 0.9, 1.0, 1.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R, -6.0, -HALO_R), (HALO_R, VEIL_H + 12.0, HALO_R)))

    # F-102 omen BEAT poff: the veil slumps once at t={OMEN_BEAT_TICK} — a flat dark
    # dust ring rolling off the mouth footprint the tick the client's mid-omen ground
    # shock lands (NetherOpenClientFx schedules the camera kick + boom off the same
    # phase payload, so both sides stay in lockstep without any new sync).
    (fx.particle_emitter(
            "veil_slump",
            duration=OMEN_TICKS, looping=False,
            start_lifetime=random_between(30, 52),
            start_speed=random_between(0.7, 1.4),
            start_size=nf3(random_between(1.2, 2.2), random_between(1.2, 2.2),
                           random_between(1.2, 2.2)),
            simulation_space="World", max_particles=34)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=OMEN_BEAT_TICK, count=constant(30), cycles=1)])
       .with_shape(circle(radius=CRATER_R * 0.7, thickness=0.1))
       .with_curves(
            velocity_over_lifetime=dict(  # launch spent fast, then the ring only creeps
                speed_modifier=curve(0.0, 1.0, SEG_APEX_DRAG)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.55), (1.0, 0.0)],
                [(0.0, 0.42, 0.36, 0.32), (1.0, 0.2, 0.16, 0.16)]),
            size_over_lifetime=curve(
                0.6, 1.5,
                [(0.0, 0.0, 0.15, 0.55, 0.5, 0.92, 1.0, 1.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R, -4.0, -HALO_R), (HALO_R, 12.0, HALO_R)))

    # Ash welling up out of the ground: rate RAMPS over the phase (the omen builds).
    (fx.particle_emitter(
            "ash_rise",
            duration=OMEN_TICKS, looping=False,
            start_lifetime=random_between(70, 130),
            start_speed=random_between(0.03, 0.12),
            start_size=nf3(random_between(0.5, 1.4), random_between(0.5, 1.4),
                           random_between(0.5, 1.4)),
            simulation_space="World", max_particles=170)
       .with_emission(rate=swell(0.6, 4.0))
       .with_shape(cylinder(radius=CRATER_R - 2.0, thickness=1.0))
       .with_curves(
            velocity_over_lifetime=dict(  # thermal lift + a lazy swirl
                linear=nf3(constant(0), random_between(0.05, 0.13), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.06), constant(0))),
            noise=dict(frequency=0.35, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.03), constant(0.05))),
            color_over_lifetime=gradient(  # #5A4A46 -> #2B2224, in-hold-out
                [(0.0, 0.0), (0.2, 0.55), (1.0, 0.0)],
                [(0.0, 0.353, 0.29, 0.275), (1.0, 0.169, 0.133, 0.141)]),
            size_over_lifetime=curve(
                0.7, 1.8,
                [(0.0, 0.0, 0.2, 0.35, 0.5, 0.9, 1.0, 1.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R, -6.0, -HALO_R), (HALO_R, 46.0, HALO_R)))

    # Lava glints seeping from hairline cracks: tiny, bright, short, all over the halo.
    (fx.particle_emitter(
            "crack_glints",
            duration=OMEN_TICKS, looping=False,
            start_lifetime=random_between(18, 34),
            start_speed=random_between(0.02, 0.09),
            start_size=nf3(random_between(0.05, 0.13), random_between(0.05, 0.13),
                           random_between(0.05, 0.13)),
            simulation_space="World", max_particles=70)
       .with_emission(rate=swell(0.3, 2.4))
       .with_shape(cylinder(radius=HALO_R - 6.0, thickness=1.0), scale=[1.0, 0.05, 1.0])
       .with_material(texture_material(CIRCLE, hdr=(2.0, 0.85, 0.3)))
       .with_lights(sky=15, block=15)
       .with_curves(color_over_lifetime=gradient(  # #FFB25E -> #FF7B3C -> out
            [(0.0, 0.0), (0.25, 0.95), (1.0, 0.0)],
            [(0.0, 1.0, 0.698, 0.369), (1.0, 1.0, 0.482, 0.235)]))
       .with_cull_box((-HALO_R, -4.0, -HALO_R), (HALO_R, 12.0, HALO_R)))

    # Flat seep skirt hugging the sand out to the creep halo — the "ground is venting" read.
    (fx.particle_emitter(
            "ground_seep",
            duration=OMEN_TICKS, looping=False,
            start_lifetime=random_between(50, 90),
            start_speed=random_between(0.12, 0.3),
            start_size=nf3(random_between(0.7, 1.6), random_between(0.7, 1.6),
                           random_between(0.7, 1.6)),
            simulation_space="World", max_particles=90)
       .with_emission(rate=swell(0.4, 2.0))
       .with_shape(cone(angle=82.0, radius=CRATER_R * 0.5))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(color_over_lifetime=gradient(  # dusty sand-grey, very soft
            [(0.0, 0.0), (0.25, 0.38), (1.0, 0.0)],
            [(0.0, 0.42, 0.36, 0.31), (1.0, 0.22, 0.18, 0.17)]))
       .with_cull_box((-HALO_R - 6.0, -4.0, -HALO_R - 6.0), (HALO_R + 6.0, 14.0, HALO_R + 6.0)))
    return fx


# ---------------------------------------------------------------------------
# Phase 2 — TREMOR: the ground cracks
# ---------------------------------------------------------------------------
def build_nether_quake_fissure() -> FxBuilder:
    """eclipse:nether_quake_fissure — ONE ground crack, stamped several times around the
    rim by the client (each stamp gets its own yaw through SpawnOptions.withRotationDeg, so
    one asset covers the whole star of fissures). The crack itself is a jagged randomA line
    of glowing embers laid flat on the surface; grey dust lifts off it as it "tears"."""
    fx = FxBuilder("nether_quake_fissure")

    # The glowing seam: randomA walks the particle along a 22-block line, the sin term
    # jitters it sideways so the crack reads jagged instead of ruler-straight.
    (fx.particle_emitter(
            "fissure_seam",
            duration=FISSURE_TICKS, looping=False,
            start_lifetime=random_between(60, FISSURE_TICKS),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.18, 0.42), random_between(0.18, 0.42),
                           random_between(0.18, 0.42)),
            simulation_space="World", max_particles=120)
       # Front races outward along the seam over the first ~40 %: the crack TEARS open.
       .with_emission(rate=tear_off(0.6, 8.0))
       .with_shape(function_shape(
            x="(randomA*2-1)*11",
            y="0.06",
            z="sin(randomA*37)*0.55 + (randomB*2-1)*0.25"))
       .with_material(texture_material(CIRCLE, hdr=(2.2, 0.9, 0.28)))
       .with_lights(sky=15, block=15)
       .with_curves(
            velocity_over_lifetime=dict(  # the seam breathes upward, barely
                linear=nf3(constant(0), random_between(0.005, 0.03), constant(0))),
            color_over_lifetime=gradient(  # #FFF3C4 core -> #FF7B3C -> #6B1E10 out
                [(0.0, 0.0), (0.1, 1.0), (0.75, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 0.953, 0.769), (0.35, 1.0, 0.482, 0.235),
                 (1.0, 0.42, 0.118, 0.063)]),
            size_over_lifetime=curve(
                0.35, 1.0,
                [(0.0, 0.0, 0.15, 0.9, 0.3, 1.0, 0.5, 1.0),
                 (0.5, 1.0, 0.7, 1.0, 0.85, 0.1, 1.0, 0.0)]))
       .with_cull_box((-16.0, -4.0, -16.0), (16.0, 12.0, 16.0)))

    # Dust lifting off the tearing seam (no collision: it is born ON the surface).
    (fx.particle_emitter(
            "fissure_dust",
            duration=FISSURE_TICKS, looping=False,
            start_lifetime=random_between(30, 60),
            start_speed=random_between(0.15, 0.45),
            start_size=nf3(random_between(0.35, 0.9), random_between(0.35, 0.9),
                           random_between(0.35, 0.9)),
            simulation_space="World", max_particles=80)
       .with_emission(rate=tear_off(0.2, 5.0))
       .with_shape(function_shape(
            x="(randomA*2-1)*11",
            y="0.1",
            z="sin(randomA*37)*0.55"))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.06, 0.16), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.6), (1.0, 0.0)],
                [(0.0, 0.44, 0.38, 0.33), (1.0, 0.2, 0.16, 0.15)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-16.0, -4.0, -16.0), (16.0, 18.0, 16.0)))
    return fx


# ---------------------------------------------------------------------------
# Phase 2b — TREMOR carpet + beat stamp (F-102)
# ---------------------------------------------------------------------------
def build_nether_tremor_waves() -> FxBuilder:
    """eclipse:nether_tremor_waves — the quake CARPET, block-anchored at the crater centre
    for the whole 360-t tremor (spawned once on the TREMOR phase payload). Two reads that
    make the pre-eruption quake land in a still frame:

      pebble_pops   Kiesel popping off the whole footprint on REAL collision physics
                    (they land and skitter instead of sinking through the sand); the
                    pop rate swells with the phase exactly like the hop-wave pressure
      heave_dust    a boiling flipbook ground-dust heave hugging the footprint — the
                    "Boden kocht" connective tissue under the pebbles

    Collision law: pebbles keep parallelUpdate off (FX_FORMAT §3.1)."""
    fx = FxBuilder("nether_tremor_waves")

    # Kiesel: small dark grit thrown 1-3 blocks up all over the mouth footprint,
    # falling back onto the REAL surface and bouncing out. Deliberately not glowing —
    # the quake is mechanical, the fire only arrives with the rupture.
    (fx.particle_emitter(
            "pebble_pops",
            duration=TREMOR_TICKS, looping=False,
            start_lifetime=random_between(24, 44),
            start_speed=random_between(0.5, 1.1),
            start_size=nf3(random_between(0.07, 0.18), random_between(0.07, 0.18),
                           random_between(0.07, 0.18)),
            simulation_space="World", max_particles=110,
            parallel_update=False)  # collision law (FX_FORMAT §3.1)
       .with_emission(rate=swell(1.5, 6.5))
       .with_shape(cone(angle=12.0, radius=CRATER_R * 0.95))
       .with_physics(collision=True, removed_when_collided=False, gravity=0.3,
                     friction=0.98, collided_friction=0.5, bounce_chance=0.55,
                     bounce_rate=0.35, bounce_spread=0.25)
       .with_curves(color_over_lifetime=random_gradient(  # sand grit <-> tuff grit
            [(0.0, 0.0), (0.08, 0.9), (0.85, 0.75), (1.0, 0.0)],
            [(0.0, 0.42, 0.369, 0.322), (1.0, 0.229, 0.196, 0.173)],
            [(0.0, 0.0), (0.08, 0.85), (0.85, 0.7), (1.0, 0.0)],
            [(0.0, 0.322, 0.298, 0.286), (1.0, 0.173, 0.157, 0.149)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R, -6.0, -HALO_R), (HALO_R, 14.0, HALO_R)))

    # Ground heave: a low boiling dust blanket over the footprint (flipbook boil rides
    # the shared 4x4 sheet). Heavy = low + slow: it never climbs past a few blocks.
    (fx.particle_emitter(
            "heave_dust",
            duration=TREMOR_TICKS, looping=False,
            start_lifetime=random_between(60, 110),
            start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(1.6, 3.0), random_between(1.6, 3.0),
                           random_between(1.6, 3.0)),
            simulation_space="World", max_particles=70)
       .with_emission(rate=swell(0.4, 2.2))
       .with_shape(cylinder(radius=CRATER_R * 0.95, thickness=1.0), scale=[1.0, 0.08, 1.0])
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.03, 0.09), constant(0))),
            noise=dict(frequency=0.32, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.015), constant(0.05))),
            uv_animation=dict(tiles=(4, 4), animation="SingleRow",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              start_frame=random_between(0.0, 4.0), cycle=2.0),
            color_over_lifetime=gradient(  # dark desert dust, alpha ceiling 0.4
                [(0.0, 0.0), (0.15, 0.4), (0.75, 0.3), (1.0, 0.0)],
                [(0.0, 0.78, 0.69, 0.61), (0.5, 0.55, 0.47, 0.42),
                 (1.0, 0.35, 0.29, 0.27)]),
            size_over_lifetime=curve(
                0.7, 1.6,
                [(0.0, 0.0, 0.18, 0.45, 0.55, 0.9, 1.0, 1.0)]))
       .with_material(texture_material(PLUME_ATLAS, discard=0.02, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R, -6.0, -HALO_R), (HALO_R, 16.0, HALO_R)))
    return fx


def build_nether_tremor_ring() -> FxBuilder:
    """eclipse:nether_tremor_ring — ONE quake-beat stamp: a flat dust ring racing out over
    the halo + a Kiesel splash + grit glints. Fired through the
    {@code eclipse:fx/cue/nether_tremor_slam} cue lane every time a hop wave SLAMS back
    down (NetherUpheavalFx sends the cue on the landing tick, rate-limited), so the
    visible ring, the camera kick and the thud are ONE beat. Successive stamps share the
    crater anchor inside this asset's ~50-t life, hence the row spawns with allowMulti."""
    fx = FxBuilder("nether_tremor_ring")

    # The dust wave: launched hard off the mouth rim, drag-spent within its first
    # quarter (the slam pushes, then the dust only rolls).
    (fx.particle_emitter(
            "dust_ring",
            duration=TREMOR_RING_TICKS, looping=False,
            start_lifetime=random_between(22, 36),
            start_speed=random_between(1.5, 2.3),
            start_size=nf3(random_between(0.9, 1.8), random_between(0.9, 1.8),
                           random_between(0.9, 1.8)),
            simulation_space="World", max_particles=50)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(46), cycles=1)])
       .with_shape(circle(radius=CRATER_R * 0.55, thickness=0.0))
       .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(0.0, 1.0, SEG_APEX_DRAG)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.6), (1.0, 0.0)],
                [(0.0, 0.45, 0.39, 0.34), (1.0, 0.23, 0.19, 0.18)]),
            size_over_lifetime=curve(
                0.55, 1.4,
                [(0.0, 0.0, 0.12, 0.6, 0.5, 0.95, 1.0, 1.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R - 8.0, -4.0, -HALO_R - 8.0), (HALO_R + 8.0, 10.0, HALO_R + 8.0)))

    # Kiesel splash: a clustered burst of grit jumping off the footprint with the slam
    # (one tick behind the ring — the ground answers the impact).
    (fx.particle_emitter(
            "kiesel_burst",
            duration=TREMOR_RING_TICKS, looping=False,
            start_lifetime=random_between(24, 40),
            start_speed=random_between(0.7, 1.5),
            start_size=nf3(random_between(0.08, 0.2), random_between(0.08, 0.2),
                           random_between(0.08, 0.2)),
            simulation_space="World", max_particles=26,
            parallel_update=False)  # collision law (FX_FORMAT §3.1)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=1, count=constant(22), cycles=1)])
       .with_shape(cone(angle=26.0, radius=CRATER_R * 0.55))
       .with_physics(collision=True, removed_when_collided=False, gravity=0.3,
                     friction=0.98, collided_friction=0.5, bounce_chance=0.6,
                     bounce_rate=0.35, bounce_spread=0.3)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.08, 0.9), (0.8, 0.7), (1.0, 0.0)],
            [(0.0, 0.42, 0.369, 0.322), (1.0, 0.2, 0.173, 0.157)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R, -6.0, -HALO_R), (HALO_R, 12.0, HALO_R)))

    # Grit glints: a pinch of warm sparks in the splash — each slam squeezes a little
    # more glow out of the hairline cracks (the omen glints answering the quake).
    (fx.particle_emitter(
            "grit_glints",
            duration=TREMOR_RING_TICKS, looping=False,
            start_lifetime=random_between(10, 20),
            start_speed=random_between(0.1, 0.3),
            start_size=nf3(random_between(0.05, 0.11), random_between(0.05, 0.11),
                           random_between(0.05, 0.11)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(9), cycles=1)])
       .with_shape(cylinder(radius=CRATER_R * 0.6, thickness=1.0), scale=[1.0, 0.05, 1.0])
       .with_material(texture_material(CIRCLE, hdr=(1.6, 0.7, 0.26)))
       .with_lights(sky=15, block=15)
       .with_curves(color_over_lifetime=gradient(  # #FFB25E -> #FF7B3C -> out
            [(0.0, 0.0), (0.2, 0.9), (1.0, 0.0)],
            [(0.0, 1.0, 0.698, 0.369), (1.0, 1.0, 0.482, 0.235)]))
       .with_cull_box((-HALO_R, -4.0, -HALO_R), (HALO_R, 8.0, HALO_R)))
    return fx


# ---------------------------------------------------------------------------
# Phase 3 — RUPTURE: the hole is torn open
# ---------------------------------------------------------------------------
# One violent throat-punch, then a long tail: shared emitter-t envelope for the fire and
# smoke rates so the whole eruption breathes as ONE event.
ERUPT_HUMPS = [(0.0, 1.0, 0.04, 1.0, 0.1, 0.55, 0.22, 0.42),
               (0.22, 0.42, 0.4, 0.3, 0.6, 0.16, 1.0, 0.05)]

#: Ballistic drag for the soot core: the launch speed is spent over the first ~quarter
#: of the life, then the slug only creeps. Mean ~0.154 of the start speed, i.e. a
#: ~50-block apex at 2.5-3.5 blk/t over 90-130t (the tallest slugs top out near 70).
SEG_APEX_DRAG = [(0.0, 1.0, 0.04, 0.68, 0.12, 0.28, 0.24, 0.14),
                 (0.24, 0.14, 0.48, 0.075, 0.74, 0.03, 1.0, 0.0)]
#: Birth height band of the fall-back debris over the crater (blocks over the lip plane).
DEBRIS_Y_MIN = 30.0
DEBRIS_Y_SPAN = 25.0
#: Apex of the eruption silhouette — every emitter that can reach it culls to this top.
ERUPT_CULL_TOP = 80.0


def build_nether_rupture_spoke() -> FxBuilder:
    """eclipse:nether_rupture_spoke — ONE radial RISS-GLUT-SPEICHE of the rupture moment:
    a jagged white-hot ember line torn along local +X ({@code SPOKE_X_MIN} ..
    {@code SPOKE_X_MIN + SPOKE_X_LEN} blocks from the crater axis), rubble fountains
    popping up along it (real collision, the Schutt lands and skitters) and tear dust
    lifting off the seam. The client stamps a 6-spoke star at the crater centre on the
    RUPTURE payload, each stamp yawed outward (the fissure-star precedent) — the ground
    around the erupting throat reads as a glowing star in a single frame.

    Cull boxes are rotation-symmetric (the executor yaw rotates the whole fx transform,
    so an asymmetric box could cull a rotated stamp wrongly — the fissure lesson)."""
    fx = FxBuilder("nether_rupture_spoke")

    # The glowing seam: hotter and wider than the tremor fissures — this is the moment
    # the ground actually gives way. tear_off front-loads the whole line (it RIPS).
    (fx.particle_emitter(
            "spoke_glow",
            duration=SPOKE_TICKS, looping=False,
            start_lifetime=random_between(50, 105),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.22, 0.5), random_between(0.22, 0.5),
                           random_between(0.22, 0.5)),
            simulation_space="World", max_particles=36)
       .with_emission(rate=tear_off(0.4, 6.5))
       .with_shape(function_shape(
            x=f"{SPOKE_X_MIN}+randomA*{SPOKE_X_LEN}",
            y="0.08",
            z="sin(randomA*29)*0.5 + (randomB*2-1)*0.22"))
       .with_material(texture_material(CIRCLE, hdr=(2.4, 1.0, 0.32)))
       .with_lights(sky=15, block=15)
       .with_curves(
            velocity_over_lifetime=dict(  # the seam exhales, barely
                linear=nf3(constant(0), random_between(0.004, 0.02), constant(0))),
            color_over_lifetime=gradient(  # #FFF3C4 -> #FF7B3C -> #6B1E10 out
                [(0.0, 0.0), (0.08, 1.0), (0.7, 0.75), (1.0, 0.0)],
                [(0.0, 1.0, 0.953, 0.769), (0.3, 1.0, 0.482, 0.235),
                 (1.0, 0.42, 0.118, 0.063)]),
            size_over_lifetime=curve(
                0.4, 1.0,
                [(0.0, 0.0, 0.1, 0.95, 0.25, 1.0, 0.55, 1.0),
                 (0.55, 1.0, 0.72, 0.95, 0.88, 0.12, 1.0, 0.0)]))
       .with_cull_box((-SPOKE_X_MIN - SPOKE_X_LEN - 3.0, -4.0, -SPOKE_X_MIN - SPOKE_X_LEN - 3.0),
                      (SPOKE_X_MIN + SPOKE_X_LEN + 3.0, 12.0, SPOKE_X_MIN + SPOKE_X_LEN + 3.0)))

    # Schuttfontänen: rubble slugs punched UP out of the tearing seam in waves (the
    # shape's speed vector is straight +Y; start_speed scales it), landing back on the
    # real ground. Warm at birth — torn loose glowing — then dead dark rubble.
    (fx.particle_emitter(
            "spoke_rubble",
            duration=SPOKE_TICKS, looping=False,
            start_lifetime=random_between(40, 80),
            start_speed=random_between(0.9, 1.9),
            start_size=nf3(random_between(0.12, 0.3), random_between(0.12, 0.3),
                           random_between(0.12, 0.3)),
            simulation_space="World", max_particles=26,
            parallel_update=False)  # collision law (FX_FORMAT §3.1)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(9), cycles=1),
                              burst(time=10, count=constant(6), cycles=4, interval=18)])
       .with_shape(function_shape(
            x=f"{SPOKE_X_MIN}+randomA*{SPOKE_X_LEN}",
            y="0.3",
            z="sin(randomA*29)*0.5",
            speed_y="1"))
       .with_physics(collision=True, removed_when_collided=False, gravity=0.32,
                     friction=0.98, collided_friction=0.5, bounce_chance=0.55,
                     bounce_rate=0.3, bounce_spread=0.3)
       .with_curves(color_over_lifetime=gradient(  # glowing birth -> dead rubble
            [(0.0, 0.0), (0.06, 0.95), (0.7, 0.8), (1.0, 0.0)],
            [(0.0, 1.0, 0.698, 0.369), (0.3, 0.42, 0.318, 0.263),
             (1.0, 0.2, 0.165, 0.149)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-SPOKE_X_MIN - SPOKE_X_LEN - 4.0, -6.0, -SPOKE_X_MIN - SPOKE_X_LEN - 4.0),
                      (SPOKE_X_MIN + SPOKE_X_LEN + 4.0, 14.0, SPOKE_X_MIN + SPOKE_X_LEN + 4.0)))

    # Tear dust: grey lift off the seam — the connective read between glow and rubble.
    (fx.particle_emitter(
            "spoke_dust",
            duration=SPOKE_TICKS, looping=False,
            start_lifetime=random_between(30, 60),
            start_speed=random_between(0.1, 0.3),
            start_size=nf3(random_between(0.5, 1.1), random_between(0.5, 1.1),
                           random_between(0.5, 1.1)),
            simulation_space="World", max_particles=16)
       .with_emission(rate=tear_off(0.2, 2.6))
       .with_shape(function_shape(
            x=f"{SPOKE_X_MIN}+randomA*{SPOKE_X_LEN}",
            y="0.15",
            z="sin(randomA*29)*0.5"))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.05, 0.12), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.18, 0.55), (1.0, 0.0)],
                [(0.0, 0.44, 0.38, 0.33), (1.0, 0.2, 0.16, 0.15)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-SPOKE_X_MIN - SPOKE_X_LEN - 3.0, -4.0, -SPOKE_X_MIN - SPOKE_X_LEN - 3.0),
                      (SPOKE_X_MIN + SPOKE_X_LEN + 3.0, 14.0, SPOKE_X_MIN + SPOKE_X_LEN + 3.0)))
    return fx


def build_nether_eruption() -> FxBuilder:
    """eclipse:nether_eruption — block-anchored at the crater centre on the lip plane, fired
    the tick the block-display fountain launches and the server starts carving. Fire column
    up the middle, colliding ember shrapnel raining onto the creep halo, a slow black smoke
    pillar that hands over to the permanent plume, and a ground-hugging shock ring."""
    fx = FxBuilder("nether_eruption")

    # Fire column: stretched billboards so the flames read as tongues, not dots.
    (fx.particle_emitter(
            "fire_column",
            duration=ERUPTION_TICKS, looping=False,
            start_lifetime=random_between(26, 56),
            start_speed=random_between(1.1, 2.6),
            start_size=nf3(random_between(0.6, 1.7), random_between(0.6, 1.7),
                           random_between(0.6, 1.7)),
            simulation_space="World", max_particles=200)
       .with_emission(rate=curve(0.4, 14.0, ERUPT_HUMPS))
       .with_shape(cone(angle=14.0, radius=CRATER_R * 0.4))
       .with_material(texture_material(CIRCLE, hdr=(2.4, 1.15, 0.4)))
       .with_lights(sky=15, block=15)
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.4,
                      length_scale=2.2, vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=gradient(  # #FFF3C4 -> #FFB25E -> #FF7B3C -> out
                [(0.0, 1.0), (0.6, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 0.953, 0.769), (0.4, 1.0, 0.698, 0.369),
                 (1.0, 1.0, 0.482, 0.235)]),
            size_over_lifetime=curve(
                0.2, 1.0,
                [(0.0, 0.4, 0.1, 1.0, 0.25, 1.0, 0.45, 1.0),
                 (0.45, 1.0, 0.65, 0.8, 0.85, 0.1, 1.0, 0.0)]))
       .with_cull_box((-HALO_R, -20.0, -HALO_R), (HALO_R, ERUPT_CULL_TOP, HALO_R)))

    # Overshooting soot core: near-black stretched slugs punched up the middle of the
    # throat FASTER and far longer-lived than the fire tongues, so the column's dark mass
    # keeps climbing (~55 blocks) after the flames have burnt out (~40). Alpha-blended
    # with a 0.5 ceiling — it must OCCLUDE the fire it overtakes, never add to it.
    (fx.particle_emitter(
            "column_core",
            duration=ERUPTION_TICKS, looping=False,
            start_lifetime=random_between(90, 130),
            start_speed=random_between(2.5, 3.5),
            start_size=nf3(random_between(1.3, 2.8), random_between(1.3, 2.8),
                           random_between(1.3, 2.8)),
            simulation_space="World", max_particles=60)
       # Same throat-punch envelope as the fire and smoke (one event, one breath).
       .with_emission(rate=curve(0.2, 4.0, ERUPT_HUMPS))
       .with_shape(cone(angle=7.0, radius=CRATER_R * 0.22))
       .with_curves(
            velocity_over_lifetime=dict(  # drag to the apex, then hang
                speed_modifier=curve(0.0, 1.0, SEG_APEX_DRAG)),
            noise=dict(frequency=0.25, quality="Noise2D",
                       position=nf3(constant(0.04), constant(0.02), constant(0.04))),
            color_over_lifetime=gradient(  # near-black soot, alpha ceiling 0.5
                [(0.0, 0.0), (0.14, 0.5), (0.7, 0.36), (1.0, 0.0)],
                [(0.0, 0.12, 0.1, 0.1), (1.0, 0.06, 0.05, 0.055)]),
            size_over_lifetime=curve(
                0.6, 1.7,
                [(0.0, 0.0, 0.22, 0.5, 0.6, 0.92, 1.0, 1.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.8,
                      length_scale=2.8, vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R, -20.0, -HALO_R), (HALO_R, ERUPT_CULL_TOP, HALO_R)))

    # F-102 PILZWOLKE: the cap that turns the column into a mushroom. Big flipbook puffs
    # are born directly in a crown ring around the column apex as the soot core arrives
    # up there (bursts at t=34/54/78 — the core's 2.5-3.5 blk/t launch reaches y~45 in
    # that window) and spread LATERALLY: each puff's velocity is its own crown angle
    # baked into the shape's speed vector, drag-spent over the first quarter, so the cap
    # widens ~7 blocks and then hangs. A still frame reads Säule + Pilz.
    (fx.particle_emitter(
            "mushroom_cap",
            duration=ERUPTION_TICKS, looping=False,
            start_lifetime=random_between(100, 160),
            start_speed=random_between(0.25, 0.45),
            start_size=nf3(random_between(3.5, 6.5), random_between(3.5, 6.5),
                           random_between(3.5, 6.5)),
            simulation_space="World", max_particles=46)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=34, count=constant(16), cycles=1),
                              burst(time=54, count=constant(14), cycles=1),
                              burst(time=78, count=constant(12), cycles=1)])
       .with_shape(function_shape(
            x="cos(randomA*2*PI)*(5+randomB*9)",
            y="43+randomC*9",
            z="sin(randomA*2*PI)*(5+randomB*9)",
            speed_x="cos(randomA*2*PI)",
            speed_y="0.12",
            speed_z="sin(randomA*2*PI)"))
       .with_curves(
            velocity_over_lifetime=dict(  # crown spread spent by ~1/4 life, then hang
                speed_modifier=curve(0.0, 1.0, SEG_APEX_DRAG),
                linear=nf3(constant(0), random_between(0.006, 0.024), constant(0))),
            rotation_over_lifetime=dict(roll=random_between(-0.3, 0.3)),
            noise=dict(frequency=0.24, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.02), constant(0.05))),
            uv_animation=dict(tiles=(4, 4), animation="SingleRow",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              start_frame=random_between(0.0, 4.0), cycle=2.0),
            color_over_lifetime=gradient(  # alpha body + cooling; the sheet is dark
                [(0.0, 0.0), (0.14, 0.66), (0.75, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 0.96, 0.92), (0.5, 0.72, 0.66, 0.65),
                 (1.0, 0.46, 0.4, 0.42)]),
            size_over_lifetime=curve(
                0.75, 1.6,
                [(0.0, 0.0, 0.15, 0.5, 0.5, 0.92, 1.0, 1.0)]))
       .with_material(texture_material(PLUME_ATLAS, discard=0.02, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R - 8.0, -20.0, -HALO_R - 8.0),
                      (HALO_R + 8.0, ERUPT_CULL_TOP, HALO_R + 8.0)))

    # Debris rain-back: chunks born HIGH over the crater halo (y 30-55) falling back as
    # −y streaks in three waves — the column's own mass returning, which is what sells
    # the throw height. Cooling-ember ramp, HDR kept to a fleck (1.4) so 70 streaks stay
    # sparks in the sky instead of a second fire sheet.
    (fx.particle_emitter(
            "debris_rain",
            duration=ERUPTION_TICKS, looping=False,
            start_lifetime=random_between(70, 120),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.14, 0.34), random_between(0.14, 0.34),
                           random_between(0.14, 0.34)),
            simulation_space="World", max_particles=70)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=40, count=constant(20), cycles=3, interval=40)])
       # Flat disc over the halo footprint, lifted into the debris band (randomB keeps
       # x/z on ONE radius per particle; randomC picks its birth height).
       .with_shape(function_shape(
            x=f"cos(randomA*2*PI)*{HALO_R}*randomB",
            y=f"{DEBRIS_Y_MIN}+randomC*{DEBRIS_Y_SPAN}",
            z=f"sin(randomA*2*PI)*{HALO_R}*randomB"))
       .with_curves(
            velocity_over_lifetime=dict(  # tips over, then accelerates down
                linear=nf3(constant(0), curve(-0.9, -0.12, [SEG_DECAY_TAIL]), constant(0))),
            color_over_lifetime=gradient(  # dull orange -> dead dark
                [(0.0, 0.0), (0.12, 0.85), (0.8, 0.45), (1.0, 0.0)],
                [(0.0, 1.0, 0.55, 0.22), (0.55, 0.62, 0.26, 0.12),
                 (1.0, 0.24, 0.1, 0.07)]),
            size_over_lifetime=curve(
                0.35, 1.0,
                [(0.0, 1.0, 0.3, 0.95, 0.72, 0.5, 1.0, 0.0)]))
       .with_material(texture_material(CIRCLE, hdr=(1.4, 0.6, 0.22)))
       .with_lights(sky=15, block=15)
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.5,
                      length_scale=2.2, vertex_sorting="NONE")
       .with_cull_box((-HALO_R - 10.0, -24.0, -HALO_R - 10.0),
                      (HALO_R + 10.0, ERUPT_CULL_TOP, HALO_R + 10.0)))

    # Ember shrapnel: REAL collision, so glowing chunks skitter over the crimson creep
    # halo and the crater lip instead of sinking through it (parallelUpdate stays off).
    (fx.particle_emitter(
            "ember_shrapnel",
            duration=ERUPTION_TICKS, looping=False,
            start_lifetime=random_between(45, 95),
            start_speed=random_between(1.4, 3.2),
            start_size=nf3(random_between(0.1, 0.28), random_between(0.1, 0.28),
                           random_between(0.1, 0.28)),
            simulation_space="World", max_particles=150,
            parallel_update=False)  # collision law (FX_FORMAT §3.1)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(60), cycles=1),
                              burst(time=14, count=constant(34), cycles=3, interval=26)])
       .with_shape(cone(angle=46.0, radius=CRATER_R * 0.35))
       .with_physics(collision=True, removed_when_collided=False, gravity=0.34,
                     friction=0.98, collided_friction=0.55, bounce_chance=0.65,
                     bounce_rate=0.3, bounce_spread=0.3)
       .with_material(texture_material(CIRCLE, hdr=(2.2, 1.0, 0.35)))
       .with_lights(sky=15, block=15)
       .with_curves(color_over_lifetime=gradient(  # cooling ember
            [(0.0, 1.0), (0.7, 0.85), (1.0, 0.0)],
            [(0.0, 1.0, 0.86, 0.55), (0.5, 1.0, 0.482, 0.235),
             (1.0, 0.42, 0.118, 0.063)]))
       .with_cull_box((-HALO_R - 10.0, -24.0, -HALO_R - 10.0),
                      (HALO_R + 10.0, 60.0, HALO_R + 10.0)))

    # Black smoke pillar — the visual handover to the permanent plume: it climbs to roughly
    # the plume's hover height and is still fading when the loop window materialises.
    # W13: boils through the shared 4x4 flipbook (SingleRow variant per puff) instead of
    # the static smoke PNG; the near-white gradient only shapes alpha/cooling — the soot
    # darkness and ember under-light live in the sheet.
    (fx.particle_emitter(
            "smoke_pillar",
            duration=ERUPTION_TICKS, looping=False,
            start_lifetime=random_between(90, 170),
            start_speed=random_between(0.5, 1.3),
            start_size=nf3(random_between(1.6, 3.4), random_between(1.6, 3.4),
                           random_between(1.6, 3.4)),
            simulation_space="World", max_particles=180)
       .with_emission(rate=curve(0.8, 8.0, ERUPT_HUMPS))
       .with_shape(cone(angle=22.0, radius=CRATER_R * 0.5))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.06, 0.18), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.12), constant(0))),
            noise=dict(frequency=0.4, quality="Noise2D",
                       position=nf3(constant(0.07), constant(0.04), constant(0.07))),
            uv_animation=dict(tiles=(4, 4), animation="SingleRow",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              start_frame=random_between(0.0, 4.0), cycle=3.0),
            color_over_lifetime=gradient(  # alpha envelope + cooling; sheet is dark
                [(0.0, 0.0), (0.12, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 0.97, 0.94), (0.45, 0.78, 0.72, 0.7),
                 (1.0, 0.5, 0.44, 0.46)]),
            size_over_lifetime=curve(
                0.8, 2.4,
                [(0.0, 0.0, 0.25, 0.4, 0.55, 0.85, 1.0, 1.0)]))
       .with_material(texture_material(PLUME_ATLAS, discard=0.02, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R - 8.0, -20.0, -HALO_R - 8.0), (HALO_R + 8.0, 80.0, HALO_R + 8.0)))

    # Ground shock rings: W13 — THREE flat dust waves racing out over the halo. The echo
    # waves land ON the aftershock sound stack (NetherOpeningSequence.tickRupture fires
    # explosion/ghast echoes at local t=18/46), and the start_speed envelope makes each
    # later wave slower — aftershocks, not copies.
    (fx.particle_emitter(
            "shock_ring",
            duration=90, looping=False,
            start_lifetime=random_between(24, 42),
            start_speed=curve(1.35, 2.5, [SEG_TEAR_OFF]),  # wave 1 fast, echoes lazier
            start_size=nf3(random_between(0.9, 2.0), random_between(0.9, 2.0),
                           random_between(0.9, 2.0)),
            simulation_space="World", max_particles=124)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(72), cycles=1),
                              burst(time=22, count=constant(48), cycles=1),
                              burst(time=50, count=constant(36), cycles=1)])
       .with_shape(circle(radius=CRATER_R * 0.6, thickness=0.0))
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.04), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.65), (1.0, 0.0)],
                [(0.0, 0.47, 0.4, 0.34), (1.0, 0.24, 0.19, 0.18)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R - 16.0, -6.0, -HALO_R - 16.0), (HALO_R + 16.0, 20.0, HALO_R + 16.0)))

    # Dust curtains: W13 — tall, heavy walls of desert dust shoved off the crater rim,
    # ROLLING outward over the halo (radial launch spent fast, then a slow crawl; a lazy
    # per-particle roll sells the "wälzen"). Heavy = low + slow (mass law): they never
    # climb, they only spread and thin out. Boil rides the shared flipbook.
    (fx.particle_emitter(
            "dust_curtains",
            duration=ERUPTION_TICKS, looping=False,
            start_lifetime=random_between(90, 150),
            start_speed=random_between(0.5, 0.9),
            start_size=nf3(random_between(2.2, 3.6), random_between(3.6, 6.0),
                           random_between(2.2, 3.6)),
            simulation_space="World", max_particles=60)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=8, count=constant(24), cycles=1),
                              burst(time=30, count=constant(18), cycles=1),
                              burst(time=56, count=constant(14), cycles=1)])
       .with_shape(circle(radius=CRATER_R * 0.85, thickness=0.15))
       .with_curves(
            velocity_over_lifetime=dict(  # launch spent by ~1/4 life, then creep
                speed_modifier=curve(0.0, 1.0, SEG_APEX_DRAG),
                radial=constant(0.05)),
            rotation_over_lifetime=dict(roll=random_between(-0.35, 0.35)),
            noise=dict(frequency=0.28, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.02), constant(0.05))),
            uv_animation=dict(tiles=(4, 4), animation="SingleRow",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              start_frame=random_between(0.0, 4.0), cycle=2.0),
            color_over_lifetime=gradient(  # dark desert dust, alpha ceiling 0.42
                [(0.0, 0.0), (0.12, 0.42), (0.75, 0.3), (1.0, 0.0)],
                [(0.0, 0.86, 0.76, 0.68), (0.5, 0.62, 0.53, 0.47),
                 (1.0, 0.4, 0.33, 0.3)]),
            size_over_lifetime=curve(
                0.75, 1.5,
                [(0.0, 0.0, 0.2, 0.45, 0.55, 0.9, 1.0, 1.0)]))
       .with_material(texture_material(PLUME_ATLAS, discard=0.02, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R - 16.0, -6.0, -HALO_R - 16.0), (HALO_R + 16.0, 26.0, HALO_R + 16.0)))
    return fx


# ---------------------------------------------------------------------------
# Phase 4 — AFTERMATH: the permanent plume (WINDOWED loop, NetherPitPlume owns it)
# ---------------------------------------------------------------------------
# The plume anchor sits PLUME_HOVER blocks over the lip plane (NetherPitPlume) — the
# ground-hugging layers below are authored at this offset under the emitter origin.
PLUME_HOVER = 14.0

# Ember jets (W13): three desynced cascades instead of ONE uniform spurt loop. Each jet
# owns a co-prime-ish cycle length, a random startDelay (rolled once per materialize, so
# every window opening phases differently) and probability-gated bursts — the pit spits
# WHEN IT WANTS TO, not on a metronome.  (name, cycle ticks, delay band, mouth offset,
# cone tilt deg (x, z), burst rows)
EMBER_JETS = (
    ("jet_a", 190, (0.0, 50.0), (3.5, 0.0), (7.0, -4.0),
     ((24, 10, 2, 9, 0.6), (130, 7, 1, 1, 0.45))),
    ("jet_b", 230, (15.0, 90.0), (-2.5, 2.5), (-6.0, 6.0),
     ((60, 12, 3, 8, 0.5), (170, 8, 1, 1, 0.4))),
    ("jet_c", 270, (40.0, 130.0), (-1.0, -3.5), (3.0, 8.0),
     ((10, 9, 2, 11, 0.55), (205, 11, 2, 7, 0.35))),
)

#: Ember-jet drag: launch spent over the first ~third, then the sparks hang and tip over.
SEG_JET_DRAG = [(0.0, 1.0, 0.06, 0.72, 0.16, 0.34, 0.32, 0.18),
                (0.32, 0.18, 0.55, 0.09, 0.78, 0.04, 1.0, 0.0)]


def build_nether_pit_plume() -> FxBuilder:
    """eclipse:nether_pit_plume — the permanent cloud over the opened pit, anchored by
    NetherPitPlume at (centerX, lipY + PLUME_HOVER, centerZ). W13/A6 rebuild, six layers:

      smoke_swathes  GPU-instanced flipbook soot body (4x4 SingleRow off the authored
                     atlas — ember veins twitch through the 4-frame boil), parallel
                     update, slow orbital churn
      inner_fire     orange tongues burning INSIDE the swathes (HDR clamped to the 1.45
                     stacking budget, random_gradient so no two tongues repeat)
      ember_jet_a/b/c irregular burst cascades out of the mouth (startDelay spread +
                     burst probability — never a metronome), thin ara-ribbon streaks
      rim_smoke      ground swathes hugging the crater lip on eclipse:soft_particle —
                     SceneDepth fade instead of the old hard clip against the rim
      heat_shimmer   a whisper of eclipse:rgb_split_distort directly over the mouth
                     (the scene wobbles through the hot air; VERY subtle by law)
      heat_glow      the wide dull-orange breathing wash under it all (unchanged)

    F-102 thickening (the user's "Rauchwolke mit Feuer drin", multi-shell):

      fog_shells     a handful of HUGE lazy near-black fog shells turning around the
                     smoke body — the dark halo that gives the cloud volume from afar
                     (wide shells + dark tints: exactly the stacking-law recipe)
      ember_motes    tiny GPU-instanced sparks twitching INSIDE the body (short lives =
                     the twinkle; the distance read of "fire inside the smoke")
      tongue_flares  probability-gated bursts of bigger fire tongues licking out of the
                     mouth every few seconds — occasional by design, never a metronome

    Loop law: WINDOWED-only (hysteresis in NetherPitPlume), every emitter cull-boxed +
    hard-capped; GPU emitters carry no physics; HDR <= 1.45 everywhere in this file."""
    fx = FxBuilder("nether_pit_plume")

    # Layer 1 — the smoke body: GPU-instanced flipbook swathes. The sheet bakes the soot
    # darkness + the twitching ember veins; the gradient only shapes alpha and a gentle
    # cooling multiplier (storm_cloud_belt school). No physics, no level access ->
    # useGPUInstance + parallelUpdate are legal (LINT-GPU-PHYSICS).
    (fx.particle_emitter(
            "smoke_swathes",
            duration=200, looping=True, prewarm=60,
            start_lifetime=random_between(180, 300),
            start_speed=random_between(0.01, 0.06),
            start_size=nf3(random_between(2.2, 5.0), random_between(2.2, 5.0),
                           random_between(2.2, 5.0)),
            simulation_space="World", max_particles=150, parallel_update=True)
       .with_emission(rate=constant(0.62))
       .with_shape(cylinder(radius=CRATER_R * 0.72, thickness=0.75), scale=[1.0, 0.45, 1.0])
       .with_curves(
            velocity_over_lifetime=dict(  # the cloud ROTATES; it barely climbs
                linear=nf3(constant(0), random_between(0.004, 0.022), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.085), constant(0))),
            noise=dict(frequency=0.22, quality="Noise3D",
                       position=nf3(constant(0.05), constant(0.025), constant(0.05))),
            uv_animation=dict(tiles=(4, 4), animation="SingleRow",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              start_frame=random_between(0.0, 4.0), cycle=3.0),
            color_over_lifetime=gradient(  # alpha body + soot cooling; sheet is dark
                [(0.0, 0.0), (0.18, 0.72), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.96, 0.93), (0.55, 0.78, 0.72, 0.72),
                 (1.0, 0.52, 0.46, 0.48)]),
            size_over_lifetime=curve(
                0.75, 1.35,
                [(0.0, 0.0, 0.12, 0.55, 0.3, 1.0, 0.5, 1.0),
                 (0.5, 1.0, 0.72, 1.0, 0.88, 0.15, 1.0, 0.0)]))
       .with_material(texture_material(PLUME_ATLAS, discard=0.02, blend=BLEND_ALPHA))
       .with_lights(sky=3, block=8)  # under-lit by the fire, never fullbright
       .with_renderer(use_gpu_instance=True, shade=False, vertex_sorting="DISTANCE")
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 30.0, HALO_R)))

    # Layer 2 — fire tongues burning INSIDE the cloud: same orbital rate as the smoke, so
    # they ride WITH the swathes instead of drifting out of them. W13: HDR pulled from 2.3
    # to the 1.45 stacking budget (a permanent loop must not own the bloom), and a
    # random_gradient splits the tongues into a hot and a sooty ramp — no two repeat.
    (fx.particle_emitter(
            "inner_fire",
            duration=200, looping=True, prewarm=30,
            start_lifetime=random_between(45, 95),
            start_speed=random_between(0.05, 0.2),
            start_size=nf3(random_between(0.5, 1.5), random_between(0.5, 1.5),
                           random_between(0.5, 1.5)),
            simulation_space="World", max_particles=56)
       .with_emission(rate=constant(0.75))
       .with_shape(sphere(radius=CRATER_R * 0.42, thickness=0.85), scale=[1.0, 0.5, 1.0])
       .with_material(texture_material(CIRCLE, hdr=(1.45, 0.72, 0.26)))
       .with_lights(sky=15, block=15)
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.9,
                      length_scale=1.8, vertex_sorting="NONE")
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.02, 0.09), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.085), constant(0))),
            noise=dict(frequency=0.5, quality="Noise2D",
                       position=nf3(constant(0.04), constant(0.03), constant(0.04)),
                       # gusty billowing instead of even wobble (remap steps the noise)
                       remap_curve=curve(0.0, 1.0,
                                         [(0.0, 0.0, 0.4, 0.06, 0.55, 0.9, 1.0, 1.0)])),
            color_over_lifetime=random_gradient(  # hot ramp <-> sooty ramp per tongue
                [(0.0, 0.0), (0.14, 0.95), (0.7, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 0.698, 0.369), (0.45, 1.0, 0.482, 0.235),
                 (1.0, 0.42, 0.118, 0.063)],
                [(0.0, 0.0), (0.14, 0.8), (0.7, 0.55), (1.0, 0.0)],
                [(0.0, 1.0, 0.55, 0.25), (0.45, 0.8, 0.36, 0.16),
                 (1.0, 0.3, 0.09, 0.05)]),
            size_over_lifetime=curve(
                0.25, 1.0,
                [(0.0, 0.15, 0.1, 0.95, 0.25, 1.0, 0.45, 1.0),
                 (0.45, 1.0, 0.66, 0.85, 0.86, 0.12, 1.0, 0.0)]))
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 26.0, HALO_R)))

    # Layer 3 — ember jets (replaces the old uniform spark_spurts): three desynced,
    # probability-gated burst cascades shooting out of the pit mouth at different tilts.
    # Each spark drags a thin ara ribbon (the census "Funken-Trails"). Loop-legal: bursts
    # re-roll every cycle, the WINDOWED controller owns start/stop.
    for name, cycle_t, delay_band, (mx, mz), (tilt_x, tilt_z), rows in EMBER_JETS:
        jet = (fx.particle_emitter(
                name,
                duration=cycle_t, looping=True,
                start_delay=random_between(*delay_band),
                start_lifetime=random_between(38, 70),
                start_speed=random_between(2.2, 3.4),
                start_size=nf3(random_between(0.08, 0.2), random_between(0.08, 0.2),
                               random_between(0.08, 0.2)),
                simulation_space="World", max_particles=26)
           .with_emission(rate=constant(0.0),
                          bursts=[burst(time=t, count=constant(c), cycles=cy,
                                        interval=iv, probability=p)
                                  for t, c, cy, iv, p in rows])
           .with_shape(cone(angle=6.5, radius=1.8),
                       position=[mx, -PLUME_HOVER + 1.5, mz],
                       rotation=[tilt_x, 0.0, tilt_z])
           .with_material(texture_material(CIRCLE, hdr=(1.45, 0.7, 0.25)))
           .with_lights(sky=15, block=15)
           .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.5,
                          length_scale=2.2, vertex_sorting="NONE")
           .with_curves(
                velocity_over_lifetime=dict(  # launch spent, hang, tip over
                    speed_modifier=curve(0.0, 1.0, SEG_JET_DRAG),
                    linear=nf3(constant(0), random_between(-0.06, -0.02), constant(0))),
                color_over_lifetime=gradient(  # white-hot birth -> cooling ember
                    [(0.0, 1.0), (0.6, 0.8), (1.0, 0.0)],
                    [(0.0, 1.0, 0.953, 0.769), (0.35, 1.0, 0.698, 0.369),
                     (1.0, 0.42, 0.118, 0.063)]))
           .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 44.0, HALO_R)))
        jet.with_module("trails", {
            "ratio": F(0.3), "lifetime": constant(1.0),
            "dieWithParticles": B(0), "sizeAffectsWidth": B(0),
            "inheritParticleColor": B(1),
            "trailType": "ARA_TRAIL",
            "araConfig": {
                "space": "World", "alignment": "View",
                "thickness": F(0.06), "smoothness": I(4),
                "highQualityCorners": B(0),
                "time": F(0.35), "timeInterval": F(0.05), "minDistance": F(0.12),
                "thicknessOverLength": curve(
                    0.0, 1.0, [(0.0, 1.0, 0.2, 0.82, 0.62, 0.28, 1.0, 0.0)]),
                "colorOverLength": gradient(
                    [(0.0, 0.7), (0.5, 0.4), (1.0, 0.0)],
                    [(0.0, 1.0, 0.698, 0.369), (1.0, 0.42, 0.118, 0.063)]),
                "physicsSetting": {
                    "warmup": F(0.0), "gravity": L([F(0.0), F(0.0), F(0.0)]),
                    "inertia": F(0.2), "velocitySmoothing": F(0.6), "damping": F(0.85)},
                "renderer": ribbon_renderer(
                    texture_material(CIRCLE, hdr=(1.3, 0.62, 0.24))),
            }})

    # Layer 4 — rim smoke on eclipse:soft_particle: heavy ground swathes creeping out of
    # the mouth and over the crater lip. The SceneDepth fade ends the old hard clip where
    # the quads meet the rim geometry (A0 §2.1 recipe: BLEND_ALPHA + DISTANCE sorting +
    # depth_mask off). Heavy = low + slow: it never climbs, it only crawls outward.
    (fx.particle_emitter(
            "rim_smoke",
            duration=200, looping=True, prewarm=80,
            start_lifetime=random_between(150, 240),
            start_speed=random_between(0.01, 0.04),
            start_size=nf3(random_between(2.4, 4.2), random_between(2.4, 4.2),
                           random_between(2.4, 4.2)),
            simulation_space="World", max_particles=36)
       .with_emission(rate=constant(0.16))
       .with_shape(cylinder(radius=CRATER_R * 0.9, thickness=0.5),
                   position=[0.0, -PLUME_HOVER + 0.9, 0.0], scale=[1.0, 0.12, 1.0])
       .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE},
            uniforms={"SoftDistance": 1.1, "NearFade": 0.6},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            velocity_over_lifetime=dict(  # radial creep over the lip, no climb
                radial=random_between(0.03, 0.08),
                linear=nf3(constant(0), random_between(0.002, 0.012), constant(0))),
            noise=dict(frequency=0.18, quality="Noise2D",
                       position=nf3(constant(0.03), constant(0.008), constant(0.03))),
            color_over_lifetime=gradient(  # #2E2624 -> #1A1516, alpha ceiling 0.5
                [(0.0, 0.0), (0.2, 0.5), (0.75, 0.38), (1.0, 0.0)],
                [(0.0, 0.18, 0.149, 0.141), (1.0, 0.102, 0.082, 0.086)]),
            size_over_lifetime=curve(
                0.65, 1.5,
                [(0.0, 0.0, 0.18, 0.5, 0.5, 0.9, 1.0, 1.0)]))
       .with_cull_box((-HALO_R - 6.0, -26.0, -HALO_R - 6.0), (HALO_R + 6.0, 8.0, HALO_R + 6.0)))

    # Layer 5 — heat shimmer directly over the mouth: a handful of large, slowly rising
    # eclipse:rgb_split_distort quads. Deliberately homeopathic (SplitStrength ~1/4 of the
    # shader default, warm tint alpha 0.10) — the scene behind the pit mouth WAVERS, it
    # never "glitches". Overlapping shimmer quads do not stack (SceneColor is a pre-pass
    # copy, A0 §5), so counts stay tiny and spread out.
    (fx.particle_emitter(
            "heat_shimmer",
            duration=200, looping=True, prewarm=60,
            start_lifetime=random_between(100, 160),
            start_speed=constant(0.0),
            start_size=nf3(random_between(2.4, 3.8), random_between(2.4, 3.8),
                           random_between(2.4, 3.8)),
            simulation_space="World", max_particles=10)
       .with_emission(rate=constant(0.06))
       .with_shape(cylinder(radius=CRATER_R * 0.4, thickness=1.0),
                   position=[0.0, -8.5, 0.0], scale=[1.0, 3.0, 1.0])
       .with_material(material_shader(
            "eclipse:rgb_split_distort",
            uniforms={"SplitStrength": 0.0018, "WobbleAmp": 0.0035,
                      "WobbleSpeed": 1.15,
                      "TintColor": (1.0, 0.52, 0.28, 0.10)},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            velocity_over_lifetime=dict(  # hot air rises, slowly
                linear=nf3(constant(0), random_between(0.02, 0.05), constant(0))),
            color_over_lifetime=gradient(  # alpha ramps the distortion in and out
                [(0.0, 0.0), (0.25, 0.85), (0.75, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]),
            size_over_lifetime=curve(
                0.7, 1.25,
                [(0.0, 0.0, 0.2, 0.55, 0.55, 0.95, 1.0, 1.0)]))
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 14.0, HALO_R)))

    # Layer 6 — heat glow: a few huge, almost invisible additive sheets breathing under the
    # cloud (the wide dull bloom the shimmer quads sit inside). Unchanged from W11.
    (fx.particle_emitter(
            "heat_glow",
            duration=200, looping=True, prewarm=40,
            start_lifetime=random_between(120, 200),
            start_speed=constant(0.0),
            start_size=nf3(random_between(5.0, 9.0), random_between(5.0, 9.0),
                           random_between(5.0, 9.0)),
            simulation_space="World", max_particles=18)
       .with_emission(rate=constant(0.12))
       .with_shape(cylinder(radius=CRATER_R * 0.5, thickness=1.0), scale=[1.0, 0.3, 1.0])
       .with_material(texture_material(CIRCLE, hdr=(0.9, 0.42, 0.16)))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.008, 0.03), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.05), constant(0))),
            color_over_lifetime=gradient(  # very low alpha throughout — this is a wash
                [(0.0, 0.0), (0.3, 0.14), (0.7, 0.12), (1.0, 0.0)],
                [(0.0, 1.0, 0.55, 0.25), (1.0, 0.65, 0.25, 0.12)]),
            size_over_lifetime=curve(
                0.85, 1.25,
                [(0.0, 0.2, 0.15, 0.2, 0.3, 1.0, 0.5, 1.0),
                 (0.5, 1.0, 0.7, 1.0, 0.85, 0.2, 1.0, 0.2)]))
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 24.0, HALO_R)))

    # Layer 7 (F-102) — fog shells: very few, very large, very dark veils on a wide
    # shell around the smoke body, turning with it. They read from 100+ blocks as the
    # cloud's dark OUTLINE — the "träge dunkle Fog-Schalen" of the census ask. Alpha
    # ceiling 0.2: a silhouette thickener, never a wall.
    (fx.particle_emitter(
            "fog_shells",
            duration=240, looping=True, prewarm=200,
            start_lifetime=random_between(220, 340),
            start_speed=constant(0.0),
            start_size=nf3(random_between(6.0, 11.0), random_between(6.0, 11.0),
                           random_between(6.0, 11.0)),
            simulation_space="World", max_particles=20)
       .with_emission(rate=constant(0.05))
       .with_shape(sphere(radius=CRATER_R * 0.85, thickness=0.25), scale=[1.0, 0.55, 1.0])
       .with_curves(
            velocity_over_lifetime=dict(  # rides the body's churn, half speed
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.045), constant(0)),
                linear=nf3(constant(0), random_between(0.002, 0.012), constant(0))),
            noise=dict(frequency=0.14, quality="Noise3D",
                       position=nf3(constant(0.03), constant(0.012), constant(0.03))),
            color_over_lifetime=gradient(  # #241D1D -> #120E10, alpha ceiling 0.2
                [(0.0, 0.0), (0.22, 0.2), (0.78, 0.16), (1.0, 0.0)],
                [(0.0, 0.141, 0.114, 0.114), (1.0, 0.071, 0.055, 0.063)]),
            size_over_lifetime=curve(
                0.85, 1.25,
                [(0.0, 0.0, 0.2, 0.5, 0.55, 0.95, 1.0, 1.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 30.0, HALO_R)))

    # Layer 8 (F-102) — ember motes: tiny sparks twitching INSIDE the smoke body. The
    # twinkle is the short life (20-40t pop in/out); at distance dozens of them are THE
    # "Feuer drin" read even when single tongues are too small to resolve. No physics,
    # no level access -> GPU-instanced + parallel (LINT-GPU-PHYSICS).
    (fx.particle_emitter(
            "ember_motes",
            duration=200, looping=True, prewarm=40,
            start_lifetime=random_between(20, 40),
            start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(0.06, 0.14), random_between(0.06, 0.14),
                           random_between(0.06, 0.14)),
            simulation_space="World", max_particles=60, parallel_update=True)
       .with_emission(rate=constant(1.2))
       .with_shape(sphere(radius=CRATER_R * 0.6, thickness=0.9), scale=[1.0, 0.5, 1.0])
       .with_material(texture_material(CIRCLE, hdr=(1.45, 0.6, 0.22)))
       .with_lights(sky=15, block=15)
       .with_renderer(use_gpu_instance=True, vertex_sorting="NONE")
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.01, 0.05), constant(0))),
            color_over_lifetime=random_gradient(  # hot mote <-> sooty mote per spark
                [(0.0, 0.0), (0.25, 1.0), (0.6, 0.85), (1.0, 0.0)],
                [(0.0, 1.0, 0.698, 0.369), (1.0, 1.0, 0.482, 0.235)],
                [(0.0, 0.0), (0.25, 0.75), (0.6, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.55, 0.25), (1.0, 0.42, 0.118, 0.063)]),
            size_over_lifetime=curve(
                0.4, 1.0,
                [(0.0, 0.1, 0.2, 1.0, 0.6, 0.85, 1.0, 0.0)]))
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 26.0, HALO_R)))

    # Layer 9 (F-102) — tongue flares: every few seconds (probability-gated, co-prime
    # 170t cycle against the 200t body and the 190/230/270t jets) a couple of BIGGER
    # fire tongues lick out of the mouth and up into the smoke — the occasional flare
    # that proves the fire is alive. HDR pinned to the 1.45 stacking budget.
    (fx.particle_emitter(
            "tongue_flares",
            duration=170, looping=True,
            start_lifetime=random_between(30, 55),
            start_speed=random_between(0.5, 0.9),
            start_size=nf3(random_between(1.2, 2.4), random_between(1.2, 2.4),
                           random_between(1.2, 2.4)),
            simulation_space="World", max_particles=14)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=20, count=constant(3), cycles=2, interval=30,
                                    probability=0.55),
                              burst(time=120, count=constant(2), cycles=1,
                                    probability=0.4)])
       .with_shape(cone(angle=24.0, radius=CRATER_R * 0.3),
                   position=[0.0, -4.0, 0.0])
       .with_material(texture_material(CIRCLE, hdr=(1.45, 0.72, 0.26)))
       .with_lights(sky=15, block=15)
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.0,
                      length_scale=2.6, vertex_sorting="NONE")
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.03, 0.09), constant(0))),
            noise=dict(frequency=0.45, quality="Noise2D",
                       position=nf3(constant(0.04), constant(0.03), constant(0.04))),
            color_over_lifetime=gradient(  # hot birth -> ember -> out
                [(0.0, 1.0), (0.55, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 0.953, 0.769), (0.35, 1.0, 0.698, 0.369),
                 (1.0, 1.0, 0.482, 0.235)]),
            size_over_lifetime=curve(
                0.3, 1.0,
                [(0.0, 0.2, 0.12, 0.95, 0.3, 1.0, 0.5, 1.0),
                 (0.5, 1.0, 0.68, 0.85, 0.86, 0.12, 1.0, 0.0)]))
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 26.0, HALO_R)))
    return fx


# ---------------------------------------------------------------------------
# Ambient — ASH SNOW (N11): the desert remembers the fire (WINDOWED loop)
# ---------------------------------------------------------------------------
ASH_RADIUS = 46.0   # flake field radius around the pit (inside the 128-block window)
ASH_CULL = 52.0


def build_nether_ash_snow() -> FxBuilder:
    """eclipse:nether_ash_snow — sparse dark ash snowing over a wide radius around the
    opened pit, plus a faint drifting soot haze. Anchored at the SAME plume anchor
    (lipY + PLUME_HOVER) by NetherPitPlume's window controller — one probe, one window,
    two loops. Deliberately ambient: no distanceRate, tiny counts, near-invisible
    per-particle cost (flakes are GPU-instanced, no physics). random_gradient rolls a
    warm-grey and a cold-grey ramp per flake so the fall never bands."""
    fx = FxBuilder("nether_ash_snow")

    # Flakes: born in a wide slab well above the desert, sinking slowly with a lazy sway.
    # Heavy = low + slow law inverted for ash: the flakes are LIGHT, so they drift — the
    # sway noise leads, the fall barely wins.
    (fx.particle_emitter(
            "ash_flakes",
            duration=240, looping=True, prewarm=200,
            start_lifetime=random_between(260, 420),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.05, 0.13), random_between(0.05, 0.13),
                           random_between(0.05, 0.13)),
            simulation_space="World", max_particles=120, parallel_update=True)
       .with_emission(rate=constant(0.32))
       .with_shape(cylinder(radius=ASH_RADIUS, thickness=1.0),
                   position=[0.0, 9.0, 0.0], scale=[1.0, 5.0, 1.0])
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.10, -0.045), constant(0))),
            noise=dict(frequency=0.16, quality="Noise2D",
                       position=nf3(constant(0.045), constant(0.008), constant(0.045))),
            color_over_lifetime=random_gradient(  # warm-grey <-> cold-grey per flake
                [(0.0, 0.0), (0.1, 0.85), (0.85, 0.7), (1.0, 0.0)],
                [(0.0, 0.45, 0.42, 0.40), (1.0, 0.22, 0.20, 0.20)],
                [(0.0, 0.0), (0.1, 0.7), (0.85, 0.6), (1.0, 0.0)],
                [(0.0, 0.32, 0.30, 0.31), (1.0, 0.14, 0.12, 0.13)]),
            size_over_lifetime=curve(
                0.7, 1.0,
                [(0.0, 1.0, 0.55, 0.95, 0.85, 0.55, 1.0, 0.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(use_gpu_instance=True, shade=True, vertex_sorting="DISTANCE")
       .with_cull_box((-ASH_CULL, -34.0, -ASH_CULL), (ASH_CULL, 20.0, ASH_CULL)))

    # Haze: a handful of huge, nearly invisible soot veils drifting through the field —
    # the connective tissue between the flakes and the plume.
    (fx.particle_emitter(
            "ash_haze",
            duration=240, looping=True, prewarm=160,
            start_lifetime=random_between(180, 260),
            start_speed=random_between(0.005, 0.02),
            start_size=nf3(random_between(5.5, 8.5), random_between(5.5, 8.5),
                           random_between(5.5, 8.5)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.05))
       .with_shape(cylinder(radius=ASH_RADIUS * 0.65, thickness=0.8),
                   position=[0.0, 2.0, 0.0], scale=[1.0, 2.5, 1.0])
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.02), constant(0)),
                linear=nf3(constant(0), random_between(-0.015, -0.004), constant(0))),
            noise=dict(frequency=0.12, quality="Noise2D",
                       position=nf3(constant(0.02), constant(0.006), constant(0.02))),
            color_over_lifetime=gradient(  # alpha ceiling 0.09 — a veil, not a wall
                [(0.0, 0.0), (0.25, 0.09), (0.75, 0.07), (1.0, 0.0)],
                [(0.0, 0.27, 0.24, 0.24), (1.0, 0.15, 0.13, 0.14)]),
            size_over_lifetime=curve(
                0.85, 1.2,
                [(0.0, 0.0, 0.2, 0.5, 0.55, 0.95, 1.0, 1.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-ASH_CULL, -34.0, -ASH_CULL), (ASH_CULL, 16.0, ASH_CULL)))

    # F-102 NACHGLUT — träge Glutflocken: a sparse handful of glowing flakes sinking
    # even slower than the ash (the fire keeps falling out of the sky long after the
    # eruption). GPU-instanced, no physics; HDR pinned to the 1.45 permanent budget.
    (fx.particle_emitter(
            "glut_flakes",
            duration=240, looping=True, prewarm=200,
            start_lifetime=random_between(200, 320),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.05, 0.11), random_between(0.05, 0.11),
                           random_between(0.05, 0.11)),
            simulation_space="World", max_particles=40, parallel_update=True)
       .with_emission(rate=constant(0.1))
       .with_shape(cylinder(radius=ASH_RADIUS * 0.8, thickness=1.0),
                   position=[0.0, 9.0, 0.0], scale=[1.0, 5.0, 1.0])
       .with_material(texture_material(CIRCLE, hdr=(1.4, 0.6, 0.22)))
       .with_lights(sky=15, block=15)
       .with_renderer(use_gpu_instance=True, vertex_sorting="NONE")
       .with_curves(
            velocity_over_lifetime=dict(  # träger than the ash: barely sinking
                linear=nf3(constant(0), random_between(-0.06, -0.03), constant(0))),
            noise=dict(frequency=0.14, quality="Noise2D",
                       position=nf3(constant(0.04), constant(0.006), constant(0.04))),
            color_over_lifetime=random_gradient(  # bright glut <-> dimming glut
                [(0.0, 0.0), (0.12, 0.95), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 0.698, 0.369), (0.6, 1.0, 0.482, 0.235),
                 (1.0, 0.42, 0.118, 0.063)],
                [(0.0, 0.0), (0.12, 0.7), (0.8, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 0.55, 0.25), (0.6, 0.62, 0.26, 0.12),
                 (1.0, 0.3, 0.09, 0.05)]),
            size_over_lifetime=curve(
                0.7, 1.0,
                [(0.0, 1.0, 0.5, 0.95, 0.85, 0.5, 1.0, 0.0)]))
       .with_cull_box((-ASH_CULL, -34.0, -ASH_CULL), (ASH_CULL, 20.0, ASH_CULL)))
    return fx


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
BUILDERS = {
    "nether_omen_ash.fx": build_nether_omen_ash,
    "nether_quake_fissure.fx": build_nether_quake_fissure,
    "nether_tremor_waves.fx": build_nether_tremor_waves,
    "nether_tremor_ring.fx": build_nether_tremor_ring,
    "nether_rupture_spoke.fx": build_nether_rupture_spoke,
    "nether_eruption.fx": build_nether_eruption,
    "nether_pit_plume.fx": build_nether_pit_plume,
    "nether_ash_snow.fx": build_nether_ash_snow,
}


def main(force_atlas: bool = False) -> int:
    rc = 0
    if force_atlas or not PLUME_ATLAS_PATH.exists():
        atlas_len = generate_plume_atlas(PLUME_ATLAS_PATH)
        print(f"WROTE {PLUME_ATLAS_PATH.relative_to(REPO_ROOT)} ({atlas_len} B)")
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        builder = builder_fn()
        raw_len, gz_len = builder.write(path)  # write() round-trip-validates
        builder.write_fxproj(path.with_suffix(".fxproj"))  # binary-diff law sibling
        errors = validate_file(path)
        if errors:
            print(f"FAIL  {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    import sys
    sys.exit(main(force_atlas="--atlas" in sys.argv[1:]))
