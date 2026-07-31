#!/usr/bin/env python3
"""wand2_fx — F-038/F-039 wand spell-system Photon `.fx` assets (the 6 highlight cues),
WAVE-13/A2 setpiece pass on top.

Authors the second wave of wand effect files programmatically via fxlib (the repo's
diffable source of truth for these binary assets — regenerate, never hand-edit). Every
asset is LAYER garnish over the photon-less Quasar/vanilla baseline composed server-side
in `wand/WandSpellEffects`; rows live in `client/wand/WandPhotonFxRows`, cue ids in
`network/fx/FxCues` (CUE_WAND_*):

  eclipse:wand_umbra_implosion   Umbra-Lanze (riss.umbralanze, F-038) endpoint void bite:
                                 inhale streaks -> void core swell -> HDR bite at t=+3
                                 (UMBRA_BITE_TICKS syncs the server's damage schedule).
  eclipse:wand_event_horizon     Ereignishorizont (riss.ereignishorizont) standing vortex:
                                 accretion streaks + TWO counter-tilted accretion RIBBON
                                 bands (per-particle ara trails), accelerating in-fall,
                                 fresnel-shell horizon membrane, dark core. The collapse
                                 is the wand_horizon_* Birth chain spawned by the row.
  eclipse:wand_horizon_collapse  Collapse ROOT (row-delayed to a - HORIZON_COLLAPSE_LEAD):
                                 the vortex crashes inward over HORIZON_COLLAPSE_LEAD
                                 ticks; a seed particle born on the finale damage tick
                                 Birth-chains the kernel (tyrant_death_fx blueprint).
  eclipse:wand_horizon_kernel    Birth child of the seed: HDR bite + fresnel dome snap
                                 + last-gulp motes; the dome Birth-chains the shockwave.
  eclipse:wand_horizon_shockwave Birth child of the dome: outward ring sheet to the
                                 spell radius + glitch-square shard spray (the one
                                 moment the capstone pushes instead of pulls).
  eclipse:wand_sonnenkern        Sonnenkern (glut.sonnenkern) solar detonation. The WHOLE
                                 asset is setDelay(a = telegraphTicks)ed caller-side so
                                 t=0 here IS the damage tick (stern_komet_impact pattern).
                                 W13/A2: 3 staggered ground shock rings + rolling dust
                                 wave + flipbook glut convection + subtle heat shimmer.
  eclipse:wand_inferno_pillar    Inferno (glut.inferno) fire-storm: rotating ember cyclone
                                 (now with per-ember ara trails + colorBySpeed) + heat
                                 core + zone embers + flipbook convection swathes + 3
                                 opening shock rings + dust wave + heat shimmer, one-shot
                                 over INFERNO_WINDOW (the shipped durationTicks default).
  eclipse:wand_star_dome         Sternenschild/Novawächter (stern.*) shield IGNITION beat
                                 on the caster (entity lane): the dome is now a REAL
                                 fresnel-shell force field + star weave + ring shock.
  eclipse:wand_judgment_finale   Himmelsgericht (stern.himmelsgericht) verdict: sky lance
                                 + star-shard rain with FirstCollision splash stamps +
                                 constellation web (anchor stars, glint chains and ara
                                 runner lines between them) + consecration ground circle
                                 with rune glints. The WHOLE asset is setDelay(a =
                                 finaleDelay)ed caller-side — t=0 IS the verdict tick.
  eclipse:wand_star_splash       FirstCollision child of the shard rain: a star-white
                                 ground stamp + glint flicks (day_rift_dust_puff school,
                                 kept under the LINT-SUBEM-FAT 8-particle budget).

WAVE-13/A2 laws applied everywhere in this file:

  * UNITS (the A1/A5 finding): Photon scales `linear`/`startSpeed` by 0.05/tick
    (1 unit ~ 1 block/SECOND) but `radial` by 0.01/tick (1 unit ~ 0.2 block/s). The
    pre-wave radial values here (-0.26 … -1.1) moved a tenth of a block over a whole
    particle life — every in-fall below is retuned into real block/s and the
    accelerating pulls ride radial CURVES (curve() ramps lower->upper, so the
    strongest suction is authored as the |larger| magnitude on the correct end).
  * HDR is clamped to the wave-13 stacking ceiling (HDR_CEILING 1.45) via `hdr()`,
    hue ratio preserved (the shipped file peaked at 3.0).
  * Birth-sub-emitter chains follow the tyrant_death_fx.py blueprint: children are
    written FIRST (LINT-SUBEM-RESOLVE reads them off disk), every child file stays
    under the 8-burst-particle LINT-SUBEM-FAT budget, and the cascade is sequenced
    by WHEN the parent particle is born, never by child delays.
  * Ribbons: `section` tubes are broken in Photon 2.1.5 (see the A4 derivation in
    fx_boss_herald_ferryman.py) — accretion ribbons are per-particle `trails`
    modules (trailType ARA_TRAIL) on orbiting carrier particles, highQualityCorners
    OFF, flat stacked bands only.
  * colorBySpeed serialises through LDLib2 `Range.CODEC` whose fields are `a`/`b`
    (NOT the min/max pair fxlib._min_max writes) — attached via with_module
    (fxlib belongs to team A0; API used read-only).
  * random_gradient (`varied`) on the big reads so no two casts repeat exactly.
  * Path identity (F-070): RISS sharp/inward violet-cyan, GLUT billowing/upward
    white-gold->amber->deep red, STERN radiant/geometric star-white + pale gold.
  * All one-shots, no loops (no cull-box law; generous cull boxes are still set on
    the heavy emitters), maxParticles always explicit, dark birth tints on every
    alpha body, alpha passes sort DISTANCE.

Flipbook sheet: wand_ember_atlas.png (4x4, authored below, nether_plume_atlas school) —
each ROW is one glut-puff variant boiling through a seamless 4-frame loop with pulsing
ember veins, played back via uvAnimation SingleRow.

Run:  python3 tools/photon/wand2_fx.py            # writes + validates all 10 assets
      python3 tools/photon/wand2_fx.py --atlas    # force-regenerate the atlas PNG
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import *  # noqa: F401,F403 - fxlib is the sanctioned star-import API

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
SQUARE_4X4 = "eclipse:textures/particle/square_4x4.png"   # glitch identity squares
STAR_2X2 = "eclipse:textures/particle/star_2x2.png"       # 4-point-star twinkle flipbook
RING_SOFT = "eclipse:textures/particle/ring_soft.png"     # soft annulus (ground rings)
DOME_FAINT = "eclipse:textures/particle/dome_faint.png"   # faint hemisphere shell
BEAM_CORE = "eclipse:textures/particle/beam_core.png"     # hot beam cross-section strip
EMBER_ATLAS = "eclipse:textures/particle/wand_ember_atlas.png"  # A2 4x4 glut boil sheet
EMBER_ATLAS_PATH = REPO_ROOT / \
    "src/main/resources/assets/eclipse/textures/particle/wand_ember_atlas.png"

# --- palette anchors (F-070 path identity, mirrored from wandfx2_fx.py) -------------
RISS_DEEP = 0xFF7B4FD0     # SAC_DEEP violet
RISS_VIOLET = 0xFFB98CFF   # SAC_VIOLET (HUD tint)
RISS_CYAN = 0xFF4FE8FF     # GLI_CYAN
RISS_MAGENTA = 0xFFFF4FD8  # GLI_MAGENTA
GLUT_GOLD = 0xFFFFE9A8     # white-gold core
GLUT_AMBER = 0xFFFFC873    # warm amber
GLUT_EMBER = 0xFFFF7B3C    # ERA_EMBER (HUD tint family)
STERN_WHITE = 0xFFF2F6FF   # ice white
STERN_CYAN = 0xFF7FE7FF    # star cyan (HUD tint)
STERN_GOLD = 0xFFF7E3B0    # pale gold

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4).
HDR_CEILING = 1.45

#: colorBySpeed cool/hot ends per path (module MULTIPLIES the lifetime color, so the
#: hot end stays at/near white — fast particles must never simply go dark).
COOL_RISS = (0.55, 0.42, 0.85)
COOL_GLUT = (0.85, 0.34, 0.10)
COOL_STERN = (0.56, 0.70, 0.94)
HOT_WHITE = (1.0, 1.0, 1.0)
HOT_CYAN = (0.86, 1.0, 1.0)
HOT_GOLD = (1.0, 0.96, 0.80)

# --- sync contracts (keep in step with the Java side) -----------------------------
# WandSpellEffects.castUmbralanze schedules the implosion damage +3t after the cue.
UMBRA_BITE_TICKS = 3
# WandSpells riss.ereignishorizont "durationTicks" default — the vortex window baked
# here. The collapse is NOT baked: WandPhotonFxRows delays a wand_horizon_collapse
# spawn by (a - HORIZON_COLLAPSE_LEAD) so the crunch converges and the Birth-chain
# snap lands exactly on the server's finale damage tick.
HORIZON_WINDOW = 120
#: Ticks the wand_horizon_collapse in-fall needs before its seed births the kernel.
#: MUST stay in sync with HORIZON_COLLAPSE_LEAD in client/wand/WandPhotonFxRows.
HORIZON_COLLAPSE_LEAD = 8
# WandSpells glut.inferno "durationTicks" default — the fire-storm window baked here.
INFERNO_WINDOW = 140
# Authored zone radii = the shipped WandSpells defaults (tier scaling untouched —
# these cues carry timing in `a`, never a live radius).
HORIZON_R = 8.0        # riss.ereignishorizont "radius"
INFERNO_R = 9.0        # glut.inferno "radius"
SONNENKERN_R = 6.0     # glut.sonnenkern "radius"
GERICHT_R = 9.0        # stern.himmelsgericht "zoneRadius"

# The 2x2 star-sheet twinkle tracks (wand_idle_stern's steppy off-chord re-picks).
TWINKLE_FRAMES = dict(
    tiles=(2, 2), animation="WholeSheet",
    frame_over_time=random_curve(
        0.0, 1.0,
        [(0.0, 0.05, 0.25, 0.9, 0.45, 0.1, 0.65, 0.7),
         (0.65, 0.7, 0.75, 0.0, 0.9, 0.95, 1.0, 0.25)],
        [(0.0, 0.6, 0.2, 0.05, 0.4, 1.0, 0.55, 0.15),
         (0.55, 0.15, 0.7, 0.85, 0.85, 0.05, 1.0, 0.5)],
        "lifetime"),
    start_frame=random_between(0.0, 3.0), cycle=3.0)

#: Eased "wave 1 fast, echoes lazier" envelope for staggered dust-wave start speeds
#: (control points genuinely off the chord — LINT-LINEAR-CURVE tolerance 0.02).
SEG_WAVE_FALLOFF = [(0.0, 1.0, 0.12, 0.72, 0.3, 0.38, 0.55, 0.2),
                    (0.55, 0.2, 0.7, 0.12, 0.88, 0.04, 1.0, 0.0)]


def rand_size3(lo, hi):
    """Per-axis random start size (the house nf3(random, random, random) idiom)."""
    return nf3(random_between(lo, hi), random_between(lo, hi), random_between(lo, hi))


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def color_by_speed(cool_rgb, hot_rgb, lo_bps, hi_bps):
    """`colorBySpeed` module body — ColorBySpeedSetting{color, speedRange}.

    Input is blocks/second (|realVelocity| * 20), output MULTIPLIES the lifetime color.
    `speedRange` is an LDLib2 `Range`, whose codec fields are `a`/`b` — NOT the
    min/max pair `fxlib._min_max` writes, hence with_module (A1 finding)."""
    return {"color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, *cool_rgb), (1.0, *hot_rgb)]),
            "speedRange": {"a": F(float(lo_bps)), "b": F(float(hi_bps))}}


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling ramp inside the same path
    identity; each particle rolls its own memoized lerp between the two."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


# ---------------------------------------------------------------------------
# wand_ember_atlas.png — 512², 4x4 (W13/A2, nether_plume_atlas school, GLUT tune)
# ---------------------------------------------------------------------------
def generate_ember_atlas(path, size=512, grid=4, seed=20260731):
    """16 glut puffs: each ROW is one convection-cell variant boiling through a
    seamless 4-frame loop (blob offsets 2π-periodic in the frame phase) for Photon
    `uvAnimation {tiles:[4,4], animation:SingleRow}`. GLUT identity vs the nether
    sheet: lit from BELOW in white-gold->amber (not sooty grey), with discrete ember
    VEINS whose gain pulses across the 4 frames on per-vein phases — played back, the
    glut visibly breathes inside the rising smoke. Rows carry rising vein intensity
    (0.45/0.7/0.95/1.25) so the memoized random row also varies how fiery each swathe
    reads. Deterministic seed; alpha-margined so mips never bleed across cells."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    cell = size // grid
    img = np.zeros((size, size, 4), np.float32)
    yy, xx = (np.mgrid[0:cell, 0:cell].astype(np.float32) + 0.5) / cell

    def smoothstep(a, b, x):
        t = np.clip((x - a) / (b - a), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)

    edge = np.minimum(np.minimum(xx, 1.0 - xx), np.minimum(yy, 1.0 - yy))
    margin = smoothstep(0.02, 0.1, edge)

    ember_rgb = np.array((1.0, 0.45, 0.14), np.float32)   # ERA ember family
    row_ember = (0.45, 0.7, 0.95, 1.25)                   # per-row vein gain

    for row in range(grid):
        nblobs = 15
        ang = rng.uniform(0.0, 2.0 * np.pi, nblobs)
        dist = rng.uniform(0.0, 1.0, nblobs) ** 0.6
        bx = 0.5 + 0.26 * dist * np.cos(ang)
        by = 0.5 + 0.24 * dist * np.sin(ang)
        br = rng.uniform(0.09, 0.15, nblobs) * (1.2 - 0.4 * dist)
        bw = rng.uniform(0.6, 1.0, nblobs)
        ph = rng.uniform(0.0, 2.0 * np.pi, (nblobs, 2))
        amp = rng.uniform(0.02, 0.055, nblobs)
        ramp = rng.uniform(0.1, 0.22, nblobs)
        nveins = 5
        vx = 0.5 + rng.uniform(-0.22, 0.22, nveins)
        vy = 0.58 + rng.uniform(-0.06, 0.18, nveins)      # low = fire side
        vr = rng.uniform(0.035, 0.06, nveins)
        vph = rng.uniform(0.0, 2.0 * np.pi, nveins)
        vgain = rng.uniform(0.6, 1.0, nveins) * row_ember[row]
        for frame in range(grid):
            phase = 2.0 * np.pi * frame / grid
            density = np.zeros((cell, cell), np.float32)
            for i in range(nblobs):
                cx = bx[i] + amp[i] * np.sin(phase + ph[i, 0])
                cy = by[i] + amp[i] * np.cos(phase + ph[i, 1])
                r = br[i] * (1.0 + ramp[i] * np.sin(phase + ph[i, 0] + ph[i, 1]))
                density += bw[i] * np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2.0 * r * r))
            density /= np.percentile(density, 99.2)
            alpha = smoothstep(0.22, 0.6, density) * margin
            # Smoke body lit from BELOW (yy grows downward): bottom warm amber-grey,
            # top cooled ash. Dark-ish birth tints live in the sheet (stacking law).
            light = 0.12 + 0.3 * yy + 0.07 * np.clip(density, 0.0, 1.0)
            rgb = light[..., None] * np.array((1.0, 0.82, 0.62), np.float32)[None, None, :]
            rgb[..., 0] += 0.06 * yy                      # amber cast toward the fire
            glow = np.zeros((cell, cell), np.float32)
            for i in range(nveins):
                pulse = 0.3 + 0.7 * (0.5 + 0.5 * np.sin(phase * 2.0 + vph[i]))
                glow += vgain[i] * pulse * np.exp(
                    -((xx - vx[i]) ** 2 + (yy - vy[i]) ** 2) / (2.0 * vr[i] * vr[i]))
            glow *= np.clip(density, 0.0, 1.0)            # veins live INSIDE the smoke
            rgb += glow[..., None] * ember_rgb[None, None, :]
            tile = np.concatenate([np.clip(rgb, 0.0, 1.0), alpha[..., None]], axis=-1)
            img[row * cell:(row + 1) * cell, frame * cell:(frame + 1) * cell] = tile

    out = (np.clip(img, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out, "RGBA").save(path, optimize=True)
    return path.stat().st_size


# ---------------------------------------------------------------------------
# Shared setpiece primitives
# ---------------------------------------------------------------------------
def ground_shock_rings(fx, root, prefix, ring_rgb_hdr, ring_rgb_stops, times, peaks,
                       y, duration, life=15):
    """THREE staggered ground shock rings (the committed nether_eruption RUPTURE
    pattern): wave 1 fast + wide, the echoes smaller and dimmer — aftershocks, not
    copies. One emitter per wave so every echo owns its own eased growth curve
    (bursts on a shared emitter would share one size envelope)."""
    alphas = (0.85, 0.58, 0.4)
    for i, (t, peak) in enumerate(zip(times, peaks)):
        (fx.particle_emitter(f"{prefix}_shockring_{i + 1}",
                duration=duration, looping=False, start_delay=constant(t),
                start_lifetime=constant(life + i * 3), start_speed=constant(0),
                start_size=nf3(1.0), simulation_space="Local", max_particles=2)
           .child_of(root)
           .at(0.0, y, 0.0)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
           .with_shape(dot())
           .with_material(texture_material(RING_SOFT, hdr=hdr(*ring_rgb_hdr),
                                           blend=BLEND_ADDITIVE))
           .with_renderer(render_mode="Horizontal")
           .with_curves(
                size_over_lifetime=curve(
                    0.4, peak, [(0.0, 0.0, 0.18, 0.85, 0.55, 1.0, 1.0, 1.0)],
                    "lifetime", "size"),
                color_over_lifetime=gradient(
                    [(0.0, alphas[i]), (0.55, alphas[i] * 0.55), (1.0, 0.0)],
                    ring_rgb_stops)))


def dust_wave(fx, root, name, born_r, duration, times, counts, rgb_a, rgb_b,
              y=0.15, speed=(1.1, 2.6)):
    """Rolling dust wall racing outward in staggered waves: the start_speed CURVE
    over emitter time makes each later burst leave slower (nether shock_ring
    pattern), so the echoes visibly lag the first slam."""
    return (fx.particle_emitter(name,
            duration=duration, looping=False,
            start_lifetime=random_between(18, 30),
            start_speed=curve(speed[0], speed[1], SEG_WAVE_FALLOFF),
            start_size=rand_size3(0.7, 1.5),
            simulation_space="World", max_particles=sum(counts) + 8)
       .child_of(root)
       .at(0.0, y, 0.0)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=t, count=constant(c))
                              for t, c in zip(times, counts)])
       .with_shape(circle(radius=born_r, thickness=0.0))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.05), constant(0))),
            size_over_lifetime=curve(0.6, 1.6, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.5), (0.7, 0.3), (1.0, 0.0)],
                rgb_a, rgb_b)))


def heat_shimmer(fx, root, name, duration, radius, y, height, count, rate,
                 lifetime=(28, 44), delay=0, tint=(1.0, 0.52, 0.28, 0.08)):
    """A whisper of eclipse:rgb_split_distort rolling in after the blast (the A6
    nether_pit_plume recipe): the scene wobbles through the hot air. VERY subtle by
    law — SplitStrength/WobbleAmp sit well below the glitch-accent defaults and the
    alpha envelope caps the mix at the gradient's peak."""
    return (fx.particle_emitter(name,
            duration=duration, looping=False, start_delay=constant(delay),
            start_lifetime=random_between(*lifetime), start_speed=constant(0.0),
            start_size=rand_size3(1.8, 3.0),
            simulation_space="World", max_particles=count)
       .child_of(root)
       .with_emission(rate=constant(rate), bursts=[burst(time=1, count=constant(2))])
       .with_shape(cylinder(radius=radius, thickness=1.0),
                   position=[0.0, y, 0.0], scale=[1.0, height, 1.0])
       .with_material(material_shader(
            "eclipse:rgb_split_distort",
            uniforms={"SplitStrength": 0.0016, "WobbleAmp": 0.0032,
                      "WobbleSpeed": 1.2, "TintColor": tint},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            velocity_over_lifetime=dict(  # hot air rises, slowly
                linear=nf3(constant(0), random_between(0.5, 1.1), constant(0))),
            color_over_lifetime=gradient(  # alpha ramps the distortion in and out
                [(0.0, 0.0), (0.3, 0.8), (0.75, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]),
            size_over_lifetime=curve(
                0.7, 1.3, [(0.0, 0.0, 0.2, 0.55, 0.55, 0.95, 1.0, 1.0)],
                "lifetime", "size")))


def convection_swathes(fx, root, name, duration, born_r, rate, max_p,
                       lifetime=(26, 40), rise=(0.9, 1.7), size=(0.9, 1.8),
                       delay=0, alpha_peak=0.5):
    """Rising glut convection on the wand_ember_atlas flipbook (A6 school): billowing
    swathes whose baked ember veins twitch through the 4-frame boil. Alpha-blended +
    shaded + NO hdr (LINT-HDR-DUST), the gradient only shapes alpha and a cooling
    multiplier — the fire light lives in the sheet."""
    return (fx.particle_emitter(name,
            duration=duration, looping=False, start_delay=constant(delay),
            start_lifetime=random_between(*lifetime),
            start_speed=random_between(0.5, 1.0),
            start_size=rand_size3(*size),
            simulation_space="World", max_particles=max_p)
       .child_of(root)
       .with_emission(rate=constant(rate), bursts=[burst(time=1, count=constant(5))])
       .with_shape(cone(angle=14.0, radius=born_r))
       .with_material(texture_material(EMBER_ATLAS, discard=0.02, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(*rise), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.1, 0.3), constant(0))),
            noise=dict(frequency=0.35, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.02), constant(0.05))),
            uv_animation=dict(tiles=(4, 4), animation="SingleRow",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              start_frame=random_between(0.0, 4.0), cycle=2.5),
            size_over_lifetime=curve(
                0.7, 2.0, [(0.0, 0.0, 0.25, 0.4, 0.55, 0.85, 1.0, 1.0)],
                "lifetime", "size"),
            color_over_lifetime=gradient(  # alpha envelope + cooling; sheet is warm
                [(0.0, 0.0), (0.15, alpha_peak), (0.75, alpha_peak * 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.97, 0.92), (0.5, 0.86, 0.76, 0.68),
                 (1.0, 0.55, 0.46, 0.42)])))


def flash(fx, root, name, size, bloom, lifetime=8, delay=0):
    """One single-frame HDR bloom pop — the shared 'money tick' primitive.
    `bloom` is the authored HDR triple; it is clamped to the stacking ceiling here."""
    return (fx.particle_emitter(name,
            duration=max(20, lifetime + delay + 2), looping=False,
            start_delay=constant(delay), start_lifetime=constant(lifetime),
            start_speed=constant(0), start_size=nf3(size),
            simulation_space="Local", max_particles=4)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE, hdr=hdr(*bloom), blend=BLEND_ADDITIVE))
        .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.3, 0.06, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
        .with_lights(sky=15, block=15))


def ara_trails_module(thickness, time_s, head_rgba, tail_rgba, hdr_rgb,
                      inertia=None, smoothness=3):
    """Per-particle ara ribbon (`trails` module, trailType ARA_TRAIL — the A4
    lantern-thread recipe). `inertia=None` welds the ribbon to the particle (crisp
    line); a dict(gravity=, inertia=, damping=) makes it swing and lag."""
    ara = {
        "space": "World",
        "thickness": F(float(thickness)),
        "time": F(float(time_s)),          # SECONDS (ara exception)
        "smoothness": I(int(smoothness)),
        "highQualityCorners": B(0),        # miter compensation shreds dense ribbons
        "textureMode": "Stretch",
        "thicknessOverLength": curve(
            0.0, 1.0, [(0.0, 1.0, 0.3, 0.82, 0.75, 0.18, 1.0, 0.0)],
            "length", "thickness"),
        "colorOverLength": gradient(
            [(0.0, head_rgba[3]), (0.5, head_rgba[3] * 0.55), (1.0, 0.0)],
            [(0.0, *head_rgba[:3]), (1.0, *tail_rgba[:3])]),
        "renderer": {
            "materials": rom([texture_material(CIRCLE, hdr=hdr(*hdr_rgb),
                                               blend=BLEND_ADDITIVE)]),
            "layer": "Translucent", "cull": {"_enable": B(0)},
            "orderInLayer": I(0), "vertexSortingMode": "NONE"}}
    if inertia is not None:
        ara["physicsSetting"] = {
            "_enable": B(1),
            "warmup": F(0.0),
            "gravity": L([F(float(v)) for v in inertia.get("gravity", (0.0, 0.0, 0.0))]),
            "inertia": F(float(inertia.get("inertia", 0.2))),
            "velocitySmoothing": F(float(inertia.get("velocity_smoothing", 0.75))),
            "damping": F(float(inertia.get("damping", 0.85)))}
    return {
        "ratio": F(1.0),
        "lifetime": constant(1.0),
        "dieWithParticles": B(1),
        "sizeAffectsWidth": B(0),
        "sizeAffectsLifetime": B(0),
        "inheritParticleColor": B(0),
        "trailType": "ARA_TRAIL",
        "araConfig": ara}


# ---------------------------------------------------------------------------
# eclipse:wand_umbra_implosion — F-038 Umbra-Lanze endpoint (one-shot, ~26t)
# W13/A2: units-law repass only (T1 spell, not a top-tier setpiece).
# ---------------------------------------------------------------------------
def build_wand_umbra_implosion() -> FxBuilder:
    """Inhale (negative radial streaks) -> void-core swell -> HDR bite on the damage
    tick (start_delay = UMBRA_BITE_TICKS) with glitch-square shrapnel.

    A2 repass: the inhale radial was -1.1 (0.22 block/s — the streaks crossed a tenth
    of the 2.2 shell before dying). It is now an accelerating curve -14 -> -48
    (2.8 -> 9.6 block/s) that lands the streaks on the core right at the bite, with
    `colorBySpeed` whitening them as they plunge; the bite HDR is clamped to 1.45."""
    fx = FxBuilder("wand_umbra_implosion")
    root = fx.empty("umbra")

    # Streaks sucked into the endpoint from a 2.2-block shell (the inhale).
    (fx.particle_emitter("inhale_streaks",
            duration=26, looping=False, start_lifetime=random_between(4, 7),
            start_speed=constant(0),
            start_size=rand_size3(0.08, 0.18),
            start_color=random_color(RISS_DEEP, RISS_CYAN),
            simulation_space="Local", max_particles=48)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(20)),
                              burst(time=2, count=constant(14))])
       .with_shape(sphere(radius=2.2, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.9, 1.2, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.7, length_scale=2.2)
       .with_module("colorBySpeed", color_by_speed(COOL_RISS, HOT_CYAN, 2.0, 9.0))
       .with_curves(
            velocity_over_lifetime=dict(  # the implosion pull, now in real block/s
                radial=curve(-48.0, -14.0, [SEG_DECAY_TAIL], "lifetime")),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 1.0), (1.0, 0.55)],
                [(0.0, 1.0, 1.0, 1.0)],
                [(0.0, 0.72, 0.55, 1.0), (1.0, 0.48, 0.93, 1.0)]))
       .with_lights(sky=15, block=15))

    # Void core: a DARK alpha-blended swirl that swells while inhaling, then collapses
    # to nothing exactly on the bite (additive can't go dark — this can).
    (fx.particle_emitter("void_core",
            duration=26, looping=False, start_lifetime=constant(UMBRA_BITE_TICKS + 7),
            start_speed=constant(0), start_size=nf3(1.0),
            start_color=color(0xFF2E2347),  # SAC_VOID
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(9.0)),
            size_over_lifetime=curve(  # swell to full by the bite, then snap shut
                0.0, 1.9, [(0.0, 0.25, 0.12, 0.95, 0.3, 1.0, 0.42, 1.0),
                           (0.42, 1.0, 0.6, 0.95, 0.85, 0.1, 1.0, 0.0)],
                "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.85), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 0.18, 0.14, 0.28), (1.0, 0.1, 0.07, 0.18)])))

    # The bite: single-frame white-cyan HDR slice on the server's damage tick.
    (fx.particle_emitter("bite_flash",
            duration=26, looping=False, start_delay=constant(UMBRA_BITE_TICKS),
            start_lifetime=constant(10), start_speed=constant(0), start_size=nf3(1.7),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=hdr(1.7, 2.4, 2.8),
                                       blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.3, 0.06, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    # Glitch-square shrapnel spat from the closing bite.
    (fx.particle_emitter("bite_shards",
            duration=26, looping=False, start_delay=constant(UMBRA_BITE_TICKS),
            start_lifetime=random_between(8, 14), start_speed=random_between(6.0, 14.0),
            start_size=rand_size3(0.05, 0.11),
            start_color=random_color(RISS_CYAN, RISS_MAGENTA),
            simulation_space="World", max_particles=12)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(10))])
       .with_shape(sphere(radius=0.25, thickness=0.0))
       .with_material(texture_material(SQUARE_4X4, hdr=hdr(1.0, 1.3, 1.4),
                                       blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .with_physics(collision=False, gravity=0.18, bounce_chance=0.0)
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=constant(0),
                              start_frame=random_between(0.0, 15.0)),
            size_over_lifetime=curve(0.2, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_event_horizon — standing vortex (one-shot, HORIZON_WINDOW ticks)
# W13/A2 rebuild: real accretion + membrane + accelerating in-fall.
# ---------------------------------------------------------------------------
def build_wand_event_horizon() -> FxBuilder:
    """The RISS capstone vortex. Cue anchor = aim point +1 (castEreignishorizont).

      accretion        rim-born streaks orbiting AND accelerating inward (radial
                       curve -4 -> -13 block/s over each particle's life), whitening
                       with speed — the disc finally FALLS in instead of posing.
      ribbon_band_a/b  TWO counter-tilted carrier rings dragging per-particle ara
                       ribbons (trails module) — the accretion RIBBONS. Slight
                       physics lag on the deep band, welded near band; both spiral
                       inward with the same radial law.
      infall_motes     wide-shell motes on an accelerating plunge, dying at the core.
      horizon_membrane ONE fresnel-shell impostor at the horizon radius: transparent
                       face, violet HDR rim, lit seam where it cuts the ground.
      core_swirl       the dark alpha hole itself (unchanged read, darker tail).
      horizon_ring     faint equator ring, slow roll.

    The collapse finale is NOT here: WandPhotonFxRows spawns wand_horizon_collapse
    delayed to (a - HORIZON_COLLAPSE_LEAD) so its Birth-chain snap lands exactly on
    the server's finale damage tick even when wand.json retunes durationTicks."""
    fx = FxBuilder("wand_event_horizon")
    root = fx.empty("horizon")
    cull = ((-HORIZON_R - 4.0, -5.0, -HORIZON_R - 4.0), (HORIZON_R + 4.0, 7.0, HORIZON_R + 4.0))

    # Orbiting streaks born on the rim, dragged inward — the accretion disc body.
    (fx.particle_emitter("accretion",
            duration=HORIZON_WINDOW, looping=False,
            start_lifetime=random_between(20, 30), start_speed=constant(0),
            start_size=rand_size3(0.1, 0.2),
            start_color=random_color(RISS_VIOLET, RISS_CYAN),
            simulation_space="Local", max_particles=72)
       .child_of(root)
       .with_emission(rate=constant(1.4))
       .with_shape(circle(radius=HORIZON_R * 0.85, thickness=0.15))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.9, 1.1, 1.4),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.6, length_scale=2.4)
       .with_module("colorBySpeed", color_by_speed(COOL_RISS, HOT_CYAN, 2.5, 12.0))
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(1.1, 1.8), constant(0)),
                # In-fall ACCELERATION (census recipe): 0.8 -> 13 block/s over the
                # particle's life — slow drift at the rim, a plunge at the horizon.
                radial=curve(-65.0, -4.0, [SEG_DECAY_TAIL], "lifetime")),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.95), (0.85, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)],
                [(0.0, 0.74, 0.58, 1.0), (1.0, 0.42, 0.91, 1.0)]))
       .with_lights(sky=15, block=15))

    # The accretion RIBBONS: two counter-tilted carrier bands dragging ara threads.
    # Deep band lags on light ribbon physics (the wake swings through the turns),
    # near band is welded (the crisp bright read). Carriers stay CPU (trails law).
    for name, y_off, radius, orbital, thickness, time_s, head, tail, glow, lag in (
            ("ribbon_band_deep", -0.55, HORIZON_R * 0.8, (0.8, 1.2), 0.26, 1.1,
             (0.62, 0.4, 0.95, 0.5), (0.2, 0.08, 0.45), (0.85, 0.5, 1.45),
             dict(gravity=(0.0, -0.4, 0.0), inertia=0.3, damping=0.84)),
            ("ribbon_band_near", 0.4, HORIZON_R * 0.62, (1.5, 2.1), 0.14, 0.7,
             (0.9, 0.85, 1.0, 0.8), (0.35, 0.75, 0.95), (1.05, 1.2, 1.45), None)):
        band = (fx.particle_emitter(name,
                duration=HORIZON_WINDOW, looping=False,
                start_lifetime=random_between(42, 66), start_speed=constant(0),
                start_size=rand_size3(0.05, 0.09),
                start_color=random_color(RISS_VIOLET, RISS_CYAN),
                simulation_space="Local", max_particles=14)
           .child_of(root)
           .at(0.0, y_off, 0.0)
           .with_emission(rate=constant(0.08),
                          bursts=[burst(time=2, count=constant(4)),
                                  burst(time=40, count=constant(3)),
                                  burst(time=78, count=constant(3))])
           .with_shape(circle(radius=radius, thickness=0.08))
           .with_material(texture_material(CIRCLE, hdr=hdr(*glow), blend=BLEND_ADDITIVE))
           .with_cull_box(*cull)
           .with_curves(
                velocity_over_lifetime=dict(
                    orbital_mode="AngularVelocity",
                    orbital=nf3(constant(0), random_between(*orbital), constant(0)),
                    radial=curve(-16.0, -3.0, [SEG_DECAY_TAIL], "lifetime")),
                color_over_lifetime=gradient(
                    [(0.0, 0.0), (0.2, 0.9), (0.85, 0.6), (1.0, 0.0)],
                    [(0.0, 1.0, 1.0, 1.0)]))
           .with_lights(sky=15, block=15))
        band.with_module("trails", ara_trails_module(
            thickness, time_s, head, tail, glow, inertia=lag))

    # Motes spiraling down the gravity well from a wider shell, dying at the center.
    (fx.particle_emitter("infall_motes",
            duration=HORIZON_WINDOW, looping=False,
            start_lifetime=random_between(20, 28),
            start_speed=constant(0),
            start_size=rand_size3(0.05, 0.1),
            start_color=random_color(RISS_DEEP, 0xFF37E6E6),
            simulation_space="Local", max_particles=56)
       .child_of(root)
       .with_emission(rate=constant(2.2))
       .with_shape(sphere(radius=HORIZON_R * 0.75, thickness=0.3))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.8, 1.0, 1.2),
                                       blend=BLEND_ADDITIVE))
       .with_module("colorBySpeed", color_by_speed(COOL_RISS, HOT_CYAN, 1.5, 10.0))
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(  # accelerating plunge: 2 -> 11 block/s
                radial=curve(-55.0, -10.0, [SEG_DECAY_TAIL], "lifetime")),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.9), (1.0, 0.1)],
                [(0.0, 1.0, 1.0, 1.0)],
                [(0.0, 0.66, 0.5, 1.0), (1.0, 0.5, 0.88, 1.0)])))

    # The event-horizon MEMBRANE (A0 fresnel_shell): a sphere impostor at the core —
    # near-transparent face, violet HDR rim on the 1.45 ceiling, glowing seam where
    # the shell cuts the ground. Breathes gently over the window.
    (fx.particle_emitter("horizon_membrane",
            duration=HORIZON_WINDOW, looping=False,
            start_lifetime=constant(HORIZON_WINDOW - 4),
            start_speed=constant(0), start_size=nf3(4.6),
            simulation_space="Local", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(material_shader(
            "eclipse:fresnel_shell",
            uniforms={"ShellColor": (0.26, 0.18, 0.42, 0.6),
                      "RimHDRColor": (1.02, 0.78, 1.45, 1.0),
                      "FresnelPower": 2.9, "FaceAlpha": 0.06,
                      "IntersectWidth": 0.4},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(  # slow double breath, never fully still
                0.86, 1.0, [(0.0, 0.6, 0.2, 1.0, 0.35, 0.75, 0.55, 0.95),
                            (0.55, 0.95, 0.72, 0.7, 0.9, 1.0, 1.0, 0.85)],
                "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 1.0), (0.9, 0.9), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)])))

    # Slow dark core swirl (the hole itself) — alpha-blended so it reads DARK.
    (fx.particle_emitter("core_swirl",
            duration=HORIZON_WINDOW, looping=False,
            start_lifetime=constant(HORIZON_WINDOW - 4),
            start_speed=constant(0), start_size=nf3(2.6),
            start_color=color(0xFF2E2347),  # SAC_VOID
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull)
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(3.0)),
            size_over_lifetime=curve(0.6, 1.0, [SEG_OVERSHOOT_SETTLE], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.8), (0.85, 0.7), (1.0, 0.0)],
                [(0.0, 0.16, 0.12, 0.26), (1.0, 0.1, 0.07, 0.18)])))

    # Faint horizontal event-horizon ring hovering at the rim.
    (fx.particle_emitter("horizon_ring",
            duration=HORIZON_WINDOW, looping=False,
            start_lifetime=constant(HORIZON_WINDOW - 4),
            start_speed=constant(0), start_size=nf3(HORIZON_R * 1.6),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=hdr(0.7, 0.9, 1.2),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box(*cull)
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(1.2)),
            size_over_lifetime=curve(0.85, 1.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.5), (0.85, 0.4), (1.0, 0.0)],
                [(0.0, 0.65, 0.55, 1.0), (1.0, 0.35, 0.55, 0.9)])))
    return fx


# ---------------------------------------------------------------------------
# Horizon collapse Birth chain (tyrant_death_fx blueprint; children FIRST in
# BUILDERS so LINT-SUBEM-RESOLVE always resolves on a clean checkout).
# ---------------------------------------------------------------------------
def build_wand_horizon_shockwave() -> FxBuilder:
    """Stage 2 (Birth child of the kernel's dome): the one moment the capstone
    PUSHES — an outward ring sheet to the spell radius + glitch-square shards.
    Chain terminus; burst sum 1 + 6 = 7 <= 8 (LINT-SUBEM-FAT)."""
    fx = FxBuilder("wand_horizon_shockwave")
    cull = ((-HORIZON_R - 4.0, -4.0, -HORIZON_R - 4.0), (HORIZON_R + 4.0, 5.0, HORIZON_R + 4.0))

    # The blast ring, racing out to the finale damage radius. Sits below the cue
    # anchor (castEreignishorizont centers +1 over the aim point).
    (fx.particle_emitter("blast_ring",
            duration=22, looping=False, max_particles=2,
            start_lifetime=constant(18), start_speed=constant(0),
            start_size=nf3(1.0), simulation_space="World")
       .at(0.0, -0.7, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=hdr(1.05, 0.85, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(
                0.6, HORIZON_R * 2.1, [(0.0, 0.0, 0.16, 0.85, 0.5, 1.0, 1.0, 1.0)],
                "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.6, 0.45), (1.0, 0.0)],
                [(0.0, 0.9, 0.82, 1.0), (1.0, 0.5, 0.35, 0.85)])))

    # Glitch shards blown outward and skittering off the ground.
    (fx.particle_emitter("glitch_shards",
            duration=22, looping=False, max_particles=8,
            start_lifetime=random_between(10, 16), start_speed=random_between(8.0, 15.0),
            start_size=rand_size3(0.06, 0.12),
            start_color=random_color(RISS_CYAN, RISS_MAGENTA),
            simulation_space="World", parallel_update=False)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(6))])
       .with_shape(sphere(radius=0.4, thickness=0.0))
       .with_material(texture_material(SQUARE_4X4, hdr=hdr(1.0, 1.3, 1.4),
                                       blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .with_physics(collision=True, friction=0.98, collided_friction=0.55, gravity=0.3,
                     bounce_chance=0.5, bounce_rate=0.35, bounce_spread=0.15)
       .with_cull_box(*cull)
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=constant(0),
                              start_frame=random_between(0.0, 15.0)),
            size_over_lifetime=curve(0.25, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))
    return fx


def build_wand_horizon_kernel() -> FxBuilder:
    """Stage 1 (Birth child of the collapse seed): the singularity answers — one
    white-violet HDR bite + a fresnel dome SNAP whose single particle Birth-chains
    the shockwave (p=1.0, exactly one ring) + the last-gulp motes.
    Burst sum 1 + 1 + 4 = 6 <= 8."""
    fx = FxBuilder("wand_horizon_kernel")
    cull = ((-7.0, -4.0, -7.0), (7.0, 6.0, 7.0))

    # The bite: single-frame slice on the finale damage tick.
    (fx.particle_emitter("bite_flash",
            duration=24, looping=False, max_particles=2,
            start_lifetime=constant(10), start_speed=constant(0),
            start_size=nf3(2.2), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=hdr(1.2, 1.05, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.3, 0.06, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    # The dome snap (fresnel_shell): pops past the horizon size and folds shut.
    # This ONE particle is the stage-1 -> stage-2 link (Birth p=1.0).
    (fx.particle_emitter("dome_snap",
            duration=24, looping=False, max_particles=2,
            start_lifetime=constant(16), start_speed=constant(0),
            start_size=nf3(5.2), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(material_shader(
            "eclipse:fresnel_shell",
            uniforms={"ShellColor": (0.3, 0.22, 0.48, 0.7),
                      "RimHDRColor": (1.1, 0.9, 1.45, 1.0),
                      "FresnelPower": 2.7, "FaceAlpha": 0.06,
                      "IntersectWidth": 0.45},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull)
       .with_sub_emitters(sub_emitter("eclipse:wand_horizon_shockwave",
                                      event="Birth", probability=1.0))
       .with_curves(
            size_over_lifetime=curve(  # overshoot out, then fold to nothing
                0.0, 1.0, [(0.0, 0.2, 0.1, 1.12, 0.4, 0.95, 0.6, 0.9),
                           (0.6, 0.9, 0.78, 0.6, 0.92, 0.12, 1.0, 0.0)],
                "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 1.0), (0.7, 0.85), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)])))

    # The last gulp: what the crunch could not swallow gets pulled the final metre.
    (fx.particle_emitter("gulp_motes",
            duration=24, looping=False, max_particles=6,
            start_lifetime=random_between(10, 15), start_speed=constant(0),
            start_size=rand_size3(0.2, 0.4),
            start_color=random_color(RISS_DEEP, RISS_VIOLET),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(4))])
       .with_shape(sphere(radius=2.6, thickness=0.3))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.9, 0.75, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-30.0)),  # 6 block/s inward
            size_over_lifetime=curve(0.15, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)])))
    return fx


def build_wand_horizon_collapse() -> FxBuilder:
    """Collapse ROOT — spawned by WandPhotonFxRows with delay (a −
    HORIZON_COLLAPSE_LEAD): the whole vortex crashes inward over the lead window and
    a single seed particle born at t=HORIZON_COLLAPSE_LEAD Birth-chains the kernel,
    so the snap lands ON the server's finale damage tick (chain rule 2: cascades are
    sequenced by when the PARENT is born, never by child delays)."""
    fx = FxBuilder("wand_horizon_collapse")
    root = fx.empty("collapse")
    cull = ((-HORIZON_R - 4.0, -5.0, -HORIZON_R - 4.0), (HORIZON_R + 4.0, 7.0, HORIZON_R + 4.0))

    # The crunch: every remaining streak plunges for the throat, accelerating.
    (fx.particle_emitter("crunch_infall",
            duration=HORIZON_COLLAPSE_LEAD + 8, looping=False,
            start_lifetime=constant(HORIZON_COLLAPSE_LEAD),
            start_speed=constant(0),
            start_size=rand_size3(0.08, 0.18),
            start_color=random_color(RISS_VIOLET, RISS_CYAN),
            simulation_space="Local", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(22)),
                              burst(time=3, count=constant(12))])
       .with_shape(sphere(radius=HORIZON_R * 0.8, thickness=0.25))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.0, 1.15, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.7, length_scale=2.6)
       .with_module("colorBySpeed", color_by_speed(COOL_RISS, HOT_CYAN, 4.0, 18.0))
       .with_cull_box(*cull)
       .with_curves(
            # 6.4 blocks in 8t needs ~16 block/s мean: ramp 8 -> 22 block/s.
            velocity_over_lifetime=dict(
                radial=curve(-110.0, -40.0, [SEG_DECAY_TAIL], "lifetime")),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 1.0), (1.0, 0.6)],
                [(0.0, 1.0, 1.0, 1.0)],
                [(0.0, 0.72, 0.55, 1.0), (1.0, 0.48, 0.93, 1.0)]))
       .with_lights(sky=15, block=15))

    # Dark veil dragged in with the crunch (the vortex body deflating).
    (fx.particle_emitter("crunch_veil",
            duration=HORIZON_COLLAPSE_LEAD + 8, looping=False,
            start_lifetime=constant(HORIZON_COLLAPSE_LEAD + 2),
            start_speed=constant(0),
            start_size=rand_size3(0.8, 1.5),
            start_color=color(0xFF2E2347),
            simulation_space="Local", max_particles=10)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(8))])
       .with_shape(sphere(radius=HORIZON_R * 0.55, thickness=0.3))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(-70.0, -25.0, [SEG_DECAY_TAIL], "lifetime")),
            size_over_lifetime=curve(0.3, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.6), (1.0, 0.0)],
                [(0.0, 0.16, 0.12, 0.26), (1.0, 0.1, 0.07, 0.18)])))

    # The seed: ONE particle, born exactly when the in-fall converges — the only
    # thing in this file that knows about the chain.
    (fx.particle_emitter("collapse_seed",
            duration=HORIZON_COLLAPSE_LEAD + 12, looping=False,
            start_lifetime=constant(6), start_speed=constant(0),
            start_size=nf3(0.9), simulation_space="World", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=HORIZON_COLLAPSE_LEAD, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull)
       .with_sub_emitters(sub_emitter("eclipse:wand_horizon_kernel",
                                      event="Birth", probability=1.0))
       .with_curves(
            size_over_lifetime=curve(0.15, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.4), (1.0, 0.0)],
                [(0.0, 0.16, 0.12, 0.26), (1.0, 0.1, 0.07, 0.18)])))
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_sonnenkern — solar detonation (one-shot ~70t; caller delays by telegraph)
# ---------------------------------------------------------------------------
def build_wand_sonnenkern() -> FxBuilder:
    """t=0 IS the damage tick (the row setDelay(a)s the whole spawn). Cue anchor =
    the aim point at GROUND level. W13/A2 meteor-impact wucht:

      core_flash / pillar   the white-gold money tick (HDR clamped to 1.45)
      3x shockring          staggered ground shock rings (nether RUPTURE pattern) —
                            slam, echo, echo, each on the aftershock rhythm
      impact_dust           rolling dust wall racing outward in 3 lagging waves
      solar_debris          physics ember chunks chaining the shipped glut children
      convection            rising glut swathes on the wand_ember_atlas flipbook —
                            the crater keeps burning instead of cutting to black
      shimmer               rgb_split_distort heat wobble rolling in after the blast
                            (VERY subtle by law)"""
    fx = FxBuilder("wand_sonnenkern")
    root = fx.empty("sonnenkern")
    dur = 70
    cull = ((-SONNENKERN_R - 6.0, -3.0, -SONNENKERN_R - 6.0),
            (SONNENKERN_R + 6.0, 16.0, SONNENKERN_R + 6.0))

    (fx.particle_emitter("core_flash",
            duration=dur, looping=False, start_lifetime=constant(10), start_speed=constant(0),
            start_size=nf3(2.6), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=hdr(2.6, 1.8, 0.6),
                                       blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.3, 0.06, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    # Vertical solar pillar: stretched along a slow upward velocity.
    (fx.particle_emitter("pillar",
            duration=dur, looping=False, start_lifetime=constant(16),
            start_speed=constant(9.0), start_size=nf3(1.0), simulation_space="Local",
            max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(cone(angle=0.5, radius=0.05))
       .with_material(texture_material(CIRCLE, hdr=hdr(2.0, 1.4, 0.5),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.0, length_scale=4.5)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.6, 0.7), (1.0, 0.0)], [(0.0, 1.0, 0.9, 0.65)]))
       .with_lights(sky=15, block=15))

    # THREE staggered ground shock rings — the committed nether_eruption pattern.
    ground_shock_rings(fx, root, "sonnenkern",
                       ring_rgb_hdr=(1.5, 1.0, 0.35),
                       ring_rgb_stops=[(0.0, 1.0, 0.9, 0.6), (1.0, 1.0, 0.7, 0.35)],
                       times=(0, 7, 16), peaks=(SONNENKERN_R * 2.0, SONNENKERN_R * 1.45,
                                                SONNENKERN_R * 1.0),
                       y=0.08, duration=dur)

    # Rolling dust wall (ash-brown — GLUT leaves residue).
    dust_wave(fx, root, "impact_dust", born_r=SONNENKERN_R * 0.4, duration=dur,
              times=(0, 8, 18), counts=(26, 16, 10),
              rgb_a=[(0.0, 0.6, 0.46, 0.34), (1.0, 0.28, 0.2, 0.15)],
              rgb_b=[(0.0, 0.52, 0.38, 0.28), (1.0, 0.22, 0.16, 0.12)],
              y=0.2).with_cull_box(*cull)

    # Physics ember debris — bounces chain the SHIPPED glut children (splash / fizzle).
    (fx.particle_emitter("solar_debris",
            duration=dur, looping=False, start_lifetime=random_between(22, 36),
            start_speed=random_between(10.0, 22.0),
            start_size=rand_size3(0.08, 0.18),
            start_color=random_color(GLUT_GOLD, GLUT_EMBER),
            simulation_space="World", max_particles=32, parallel_update=False)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(22))])
       .with_shape(sphere(radius=0.5, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.5, 0.9, 0.3),
                                       blend=BLEND_ADDITIVE))
       .with_physics(collision=True, friction=0.98, collided_friction=0.6, gravity=0.42,
                     bounce_chance=0.6, bounce_rate=0.4, bounce_spread=0.12)
       .with_module("colorBySpeed", color_by_speed(COOL_GLUT, HOT_GOLD, 2.0, 20.0))
       .with_cull_box(*cull)
       .with_curves(color_over_lifetime=varied(
            [(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
            [(0.0, 1.0, 0.95, 0.75), (0.45, 1.0, 0.55, 0.2), (1.0, 0.45, 0.12, 0.04)],
            [(0.0, 1.0, 0.8, 0.44), (0.45, 0.94, 0.38, 0.11), (1.0, 0.33, 0.08, 0.02)]))
       .with_sub_emitters(
            sub_emitter("eclipse:glut_splash", event="Collision", probability=0.4),
            sub_emitter("eclipse:glut_ember_die", event="Death", probability=0.3))
       .with_lights(sky=15, block=15))

    # Rising glut convection replaces the old flat smoke dome: the crater BURNS.
    convection_swathes(fx, root, "convection", duration=dur, born_r=SONNENKERN_R * 0.35,
                       rate=0.55, max_p=28, delay=3, lifetime=(26, 42),
                       rise=(1.0, 2.0), size=(1.0, 2.0),
                       alpha_peak=0.5).with_cull_box(*cull)

    # Rolling heat shimmer over the crater — SEHR subtil (law).
    heat_shimmer(fx, root, "shimmer", duration=dur, radius=SONNENKERN_R * 0.4,
                 y=1.6, height=2.2, count=5, rate=0.05, delay=4,
                 lifetime=(26, 40)).with_cull_box(*cull)
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_inferno_pillar — fire-storm (one-shot, INFERNO_WINDOW ticks)
# ---------------------------------------------------------------------------
def build_wand_inferno_pillar() -> FxBuilder:
    """The GLUT capstone fire-storm. Cue anchor = zone center +0.5 (castInferno).

      3x shockring + storm_dust  opening slam: the storm ARRIVES (staggered rings +
                                 dust wall racing over the zone, nether pattern)
      fire_cyclone               rotating ember wall (shapeArc Loop sweep); every
                                 ~4th ember drags a short warm ara ribbon (trails
                                 module) and colorBySpeed sells the whirl speed
      heat_core                  flickering stretched flames standing in the middle
      convection                 rising flipbook glut swathes shading the cyclone —
                                 the aufsteigende Glut-Konvektion (atlas boil)
      zone_embers                sparse drifting embers across the whole radius-9 zone
      ash                        dark alpha ash column riding the same flipbook
      shimmer                    nachrollender rgb_split heat wobble (VERY subtle)

    The per-eruption ground beats stay the server's Quasar baseline."""
    fx = FxBuilder("wand_inferno_pillar")
    root = fx.empty("inferno")
    cull = ((-INFERNO_R - 5.0, -3.0, -INFERNO_R - 5.0), (INFERNO_R + 5.0, 15.0, INFERNO_R + 5.0))

    # Opening slam — the storm makes landfall (anchor sits +0.5 over ground).
    ground_shock_rings(fx, root, "inferno",
                       ring_rgb_hdr=(1.45, 0.9, 0.3),
                       ring_rgb_stops=[(0.0, 1.0, 0.85, 0.55), (1.0, 1.0, 0.62, 0.3)],
                       times=(0, 12, 28), peaks=(INFERNO_R * 2.0, INFERNO_R * 1.4,
                                                 INFERNO_R * 0.95),
                       y=-0.35, duration=INFERNO_WINDOW)
    dust_wave(fx, root, "storm_dust", born_r=INFERNO_R * 0.35, duration=INFERNO_WINDOW,
              times=(0, 14, 32), counts=(24, 16, 10),
              rgb_a=[(0.0, 0.6, 0.46, 0.34), (1.0, 0.28, 0.2, 0.15)],
              rgb_b=[(0.0, 0.5, 0.36, 0.26), (1.0, 0.2, 0.15, 0.12)],
              y=-0.3).with_cull_box(*cull)

    # The cyclone wall: embers born sweeping around a 2.2-radius column, rising.
    cyclone = (fx.particle_emitter("fire_cyclone",
            duration=INFERNO_WINDOW, looping=False,
            start_lifetime=random_between(24, 34), start_speed=constant(0),
            start_size=rand_size3(0.08, 0.16),
            start_color=random_color(GLUT_AMBER, GLUT_EMBER),
            simulation_space="Local", max_particles=128)
       .child_of(root)
       .with_emission(rate=constant(3.0))
       .with_shape(cylinder(radius=2.2, thickness=0.12, arc_mode="Loop", arc_speed=1.1))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.45, 0.8, 0.25),
                                       blend=BLEND_ADDITIVE))
       .with_module("colorBySpeed", color_by_speed(COOL_GLUT, HOT_GOLD, 1.5, 9.0))
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(2.4, 4.4), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.9, 1.3), constant(0))),
            color_over_lifetime=varied(  # white-hot -> amber -> deep red -> 0
                [(0.0, 0.0), (0.15, 1.0), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 0.92, 0.75), (0.4, 1.0, 0.5, 0.15), (1.0, 0.4, 0.08, 0.02)],
                [(0.0, 1.0, 0.82, 0.5), (0.4, 0.95, 0.4, 0.1), (1.0, 0.34, 0.06, 0.02)]))
       .with_lights(sky=15, block=15))
    # Every ~4th ember drags a short warm thread — the whirl leaves a woven wake.
    trail_mod = ara_trails_module(0.06, 0.4,
                                  (1.0, 0.78, 0.42, 0.5), (0.5, 0.14, 0.04),
                                  (1.3, 0.7, 0.28), inertia=None)
    trail_mod["ratio"] = F(0.25)
    cyclone.with_module("trails", trail_mod)

    # Flickering heat core: sparse tall stretched flames standing in the middle.
    (fx.particle_emitter("heat_core",
            duration=INFERNO_WINDOW, looping=False, start_lifetime=constant(18),
            start_speed=constant(10.0), start_size=nf3(0.8), simulation_space="Local",
            max_particles=8)
       .child_of(root)
       .with_emission(rate=constant(0.15))
       .with_shape(cone(angle=1.0, radius=0.2))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.9, 1.1, 0.35),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.0, length_scale=5.0)
       .with_cull_box(*cull)
       .with_curves(color_over_lifetime=varied(
            [(0.0, 0.0), (0.2, 1.0), (0.75, 0.7), (1.0, 0.0)],
            [(0.0, 1.0, 0.85, 0.55)],
            [(0.0, 1.0, 0.72, 0.38)]))
       .with_lights(sky=15, block=15))

    # Rising glut convection shading the cyclone (atlas flipbook, A6 school).
    convection_swathes(fx, root, "convection", duration=INFERNO_WINDOW, born_r=1.9,
                       rate=0.4, max_p=40, lifetime=(30, 46), rise=(1.4, 2.6),
                       size=(0.9, 1.9), alpha_peak=0.55).with_cull_box(*cull)

    # Sparse embers drifting up across the whole eruption zone (radius ~9).
    (fx.particle_emitter("zone_embers",
            duration=INFERNO_WINDOW, looping=False,
            start_lifetime=random_between(20, 30),
            start_speed=random_between(0.4, 1.2),
            start_size=rand_size3(0.04, 0.09),
            simulation_space="Local", max_particles=64)
       .child_of(root)
       .with_emission(rate=constant(1.6))
       .with_shape(circle(radius=INFERNO_R * 0.9, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.2, 0.6, 0.18),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(1.2, 2.6), constant(0))),
            noise=dict(frequency=0.6, quality="Noise2D",
                       position=nf3(constant(0.04), constant(0.01), constant(0.04)),
                       rotation=constant(0), size=constant(0)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 1.0), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.7, 0.3), (1.0, 0.5, 0.15, 0.04)],
                [(0.0, 1.0, 0.82, 0.48), (1.0, 0.4, 0.1, 0.03)]))
       .with_lights(sky=15, block=15))

    # Ash column shading the cyclone (dark alpha smoke on the shared flipbook).
    (fx.particle_emitter("ash",
            duration=INFERNO_WINDOW, looping=False, start_lifetime=constant(36),
            start_speed=random_between(1.0, 2.0),
            start_size=rand_size3(0.5, 0.9),
            simulation_space="Local", max_particles=24)
       .child_of(root)
       .with_emission(rate=constant(0.5))
       .with_shape(cone(angle=18.0, radius=1.6))
       .with_material(texture_material(EMBER_ATLAS, discard=0.02, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*cull)
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="SingleRow",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              start_frame=random_between(0.0, 4.0), cycle=2.0),
            size_over_lifetime=curve(1.0, 2.1, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.4), (1.0, 0.0)],
                [(0.0, 0.4, 0.32, 0.28), (1.0, 0.16, 0.12, 0.1)])))

    # Nachrollender heat shimmer standing over the zone (VERY subtle by law).
    heat_shimmer(fx, root, "shimmer", duration=INFERNO_WINDOW, radius=INFERNO_R * 0.35,
                 y=1.8, height=2.6, count=6, rate=0.05, delay=6,
                 lifetime=(30, 46)).with_cull_box(*cull)
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_star_dome — shield ignition on the caster (entity one-shot, ~55t)
# ---------------------------------------------------------------------------
def build_wand_star_dome() -> FxBuilder:
    """Dome shell + woven star sprites + feet ring shock + ignition pop. Anchored on
    the caster (entity lane, body-center offset in the row); the SUSTAINED shield
    stays the server's Quasar constellation baseline.

    W13/A2: the dome is now a REAL force field — the faint texture shell is replaced
    by the A0 fresnel_shell impostor (transparent face, star-blue HDR rim on the
    1.45 ceiling, lit seam where it cuts the ground); weave orbits vary per star."""
    fx = FxBuilder("wand_star_dome")
    root = fx.empty("dome")

    # The fresnel force-field blooming out and settling around the caster.
    (fx.particle_emitter("dome_shell",
            duration=55, looping=False, start_lifetime=constant(50), start_speed=constant(0),
            start_size=nf3(3.4), simulation_space="Local", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(material_shader(
            "eclipse:fresnel_shell",
            uniforms={"ShellColor": (0.58, 0.68, 0.92, 0.5),
                      "RimHDRColor": (1.05, 1.2, 1.45, 1.0),
                      "FresnelPower": 3.0, "FaceAlpha": 0.07,
                      "IntersectWidth": 0.38},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(0.35, 1.0, [SEG_OVERSHOOT_SETTLE], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 1.0), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)])))

    # The star weave: 4-point-star sprites on the shell, orbiting + twinkling —
    # per-star orbital speeds so the weave breathes instead of turning as a disc.
    (fx.particle_emitter("star_weave",
            duration=55, looping=False, start_lifetime=random_between(30, 46),
            start_speed=constant(0),
            start_size=rand_size3(0.07, 0.12),
            simulation_space="Local", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(0.35),
                      bursts=[burst(time=0, count=constant(16))])
       .with_shape(sphere(radius=1.6, thickness=0.0))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.0, 1.0, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.15, 0.45), constant(0))),
            size_over_lifetime=curve(  # double-hump twinkle
                0.3, 1.0, [(0.0, 0.4, 0.2, 1.0, 0.3, 0.2, 0.5, 0.9),
                           (0.5, 0.9, 0.7, 0.1, 0.9, 1.0, 1.0, 0.2)], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 1.0), (0.8, 0.8), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.75, 0.85, 1.0)],
                [(0.0, 0.97, 0.93, 0.86), (1.0, 0.8, 0.78, 0.95)]))
       .with_lights(sky=15, block=15))

    # Ring shock at the feet (anchor = body center, so the ring sits ~1 block down).
    (fx.particle_emitter("feet_ring",
            duration=55, looping=False, start_lifetime=constant(14), start_speed=constant(0),
            start_size=nf3(1.0), simulation_space="Local", max_particles=4)
       .child_of(root)
       .at(0.0, -0.9, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=hdr(1.0, 1.1, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.8, 5.0, [(0.0, 0.0, 0.2, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.8), (1.0, 0.0)], [(0.0, 0.85, 0.9, 1.0)])))

    # Ignition pop — brief HDR bloom as the shield snaps on.
    flash(fx, root, "ignition_flash", 1.4, (1.6, 1.7, 2.4), lifetime=8)
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_star_splash — FirstCollision child of the judgment shard rain
# ---------------------------------------------------------------------------
def build_wand_star_splash() -> FxBuilder:
    """W13/A2 FirstCollision child (day_rift_dust_puff school): a star-white ground
    stamp + glint flicks where a verdict shard lands. Kept at the LINT-SUBEM-FAT
    budget (1 + 5 = 6 burst particles) — the rain stamps this a dozen times per
    verdict and each stamp deep-copies a runtime."""
    fx = FxBuilder("wand_star_splash")
    cull = ((-3.5, -1.5, -3.5), (3.5, 3.5, 3.5))

    # The stamp: one flat star-white ring blooming across whatever the shard hit.
    (fx.particle_emitter("stamp_ring",
            duration=16, looping=False, max_particles=2,
            start_lifetime=constant(13), start_speed=constant(0),
            start_size=nf3(0.6), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=hdr(0.95, 1.0, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.3, 2.4, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.75), (0.6, 0.35), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.7, 0.8, 1.0)])))

    # Five star-glint flicks off the contact point, folding back down.
    (fx.particle_emitter("splash_glints",
            duration=16, looping=False, max_particles=6,
            start_lifetime=random_between(8, 14), start_speed=random_between(3.0, 6.0),
            start_size=rand_size3(0.05, 0.09), simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(5))])
       .with_shape(cone(angle=52.0, radius=0.12))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.0, 1.05, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.4, bounce_chance=0.0)
       .with_cull_box(*cull)
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            size_over_lifetime=curve(0.4, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.9), (0.7, 0.5), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.75, 0.85, 1.0)],
                [(0.0, 0.97, 0.93, 0.84), (1.0, 0.8, 0.78, 0.95)])))
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_judgment_finale — the verdict (one-shot ~55t; caller delays by finaleDelay)
# ---------------------------------------------------------------------------
# Constellation geometry: a radius-6.3 pentagon inside the radius-9 zone. Anchors,
# glint chains and ara runner lines are all derived from these two numbers so the
# figure always closes.
CONST_N = 5
CONST_R = 6.3
_CONST_STEP = 2.0 * 3.14159265 / CONST_N          # 1.2566371 rad between vertices
_CONST_EDGE = 2.0 * CONST_R * 0.5877853           # edge length of the pentagon (7.406)
#: vertex k angle expression term — (k + 0.25) keeps a flat edge facing the caster.
_K = "(floor(randomA*5)+0.25)"
_K1 = "(floor(randomA*5)+1.25)"


def build_wand_judgment_finale() -> FxBuilder:
    """t=0 IS the verdict damage tick (the row setDelay(a)s the whole spawn). Cue
    anchor = zone center at GROUND level. W13/A2 constellation verdict:

      sky_lance           24-block beam slamming the zone (HDR clamped)
      verdict_flash       the money frame
      zone_ring           one crisp radius-9 judgment ring (spell zoneRadius)
      consecration_*      Weihe-Bodenkreis: a standing ground circle that outlives
                          the blast + rune glints twinkling up off the rim
      starfall            star shards raining down over the zone with REAL collision;
                          FirstCollision stamps eclipse:wand_star_splash (A3 school)
      constellation_*     anchor stars on a pentagon, glint chains along its edges,
                          and ara-ribbon RUNNERS that draw the lines between anchors
      star_burst          4-point star shards blown outward, twinkling out
      afterglow           soft dome so the verdict decays instead of cutting"""
    fx = FxBuilder("wand_judgment_finale")
    root = fx.empty("judgment")
    dur = 55
    cull = ((-GERICHT_R - 5.0, -3.0, -GERICHT_R - 5.0), (GERICHT_R + 5.0, 26.0, GERICHT_R + 5.0))

    # The lance: a 24-block vertical beam flashing down onto the zone center.
    lance = fx.beam_emitter("sky_lance",
            end=(0.0, -24.0, 0.0), width=curve(0.0, 1.4, [SEG_POP_SHRINK], "duration"),
            duration=16, looping=False, raycast="NONE",
            color_nf=gradient([(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
                              [(0.0, 0.95, 0.95, 1.0), (1.0, 0.75, 0.8, 1.0)]))
    lance.child_of(root).at(0.0, 24.0, 0.0)
    lance.with_material(texture_material(BEAM_CORE, hdr=hdr(1.8, 1.8, 2.6),
                                         blend=BLEND_ADDITIVE))
    lance.with_lights(sky=15, block=15)

    flash(fx, root, "verdict_flash", 3.0, (2.2, 2.2, 3.0), lifetime=12)

    # Zone-wide judgment ring (zoneRadius 9 -> 18-block diameter sweep).
    (fx.particle_emitter("zone_ring",
            duration=dur, looping=False, start_lifetime=constant(16), start_speed=constant(0),
            start_size=nf3(1.5), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=hdr(1.3, 1.3, 1.9),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.5, GERICHT_R * 2.2, [(0.0, 0.0, 0.18, 0.85, 0.55, 1.0, 1.0, 1.0)],
                "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.9), (1.0, 0.0)], [(0.0, 0.9, 0.92, 1.0)])))

    # Weihe-Bodenkreis: the consecration circle STANDS after the blast (slow roll,
    # pale gold-white) instead of vanishing with the shock ring.
    (fx.particle_emitter("consecration_circle",
            duration=dur, looping=False, start_lifetime=constant(dur - 6),
            start_speed=constant(0), start_size=nf3(CONST_R * 2.15),
            simulation_space="Local", max_particles=2)
       .child_of(root)
       .at(0.0, 0.06, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=hdr(1.15, 1.12, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box(*cull)
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(0.8)),
            size_over_lifetime=curve(0.9, 1.0, [SEG_OVERSHOOT_SETTLE], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.6), (0.7, 0.42), (1.0, 0.0)],
                [(0.0, 0.97, 0.93, 0.8), (1.0, 0.8, 0.78, 0.68)])))

    # Rune glints twinkling up off the consecration rim.
    (fx.particle_emitter("consecration_runes",
            duration=dur, looping=False, start_lifetime=random_between(20, 34),
            start_speed=random_between(0.3, 0.7),
            start_size=rand_size3(0.06, 0.11),
            simulation_space="Local", max_particles=24)
       .child_of(root)
       .at(0.0, 0.1, 0.0)
       .with_emission(rate=constant(0.45), bursts=[burst(time=2, count=constant(8))])
       .with_shape(circle(radius=CONST_R, thickness=0.04))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.05, 1.02, 1.35),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.3, 0.7), constant(0))),
            size_over_lifetime=curve(  # double-hump twinkle
                0.3, 1.0, [(0.0, 0.4, 0.2, 1.0, 0.3, 0.2, 0.5, 0.9),
                           (0.5, 0.9, 0.7, 0.1, 0.9, 1.0, 1.0, 0.2)], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.95), (0.75, 0.6), (1.0, 0.0)],
                [(0.0, 0.97, 0.93, 0.8), (1.0, 0.85, 0.8, 0.66)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.75, 0.85, 1.0)]))
       .with_lights(sky=15, block=15))

    # Star-shard rain: REAL collision (vanilla collideBoundingBox sweeps the step, no
    # tunnelling) — every landing can stamp a wand_star_splash. Born spread over the
    # zone, falling 20-30 block/s from ~14 blocks up, dying on impact.
    (fx.particle_emitter("starfall",
            duration=dur, looping=False, start_lifetime=random_between(30, 40),
            start_speed=random_between(20.0, 30.0),
            start_size=rand_size3(0.08, 0.16),
            start_color=random_color(STERN_WHITE, STERN_CYAN),
            simulation_space="World", max_particles=30, parallel_update=False)
       .child_of(root)
       .at(0.0, 14.0, 0.0)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(12)),
                              burst(time=4, count=constant(8)),
                              burst(time=9, count=constant(6))])
       .with_shape(function_shape(
            x=f"cos(randomA*2*PI)*(randomB*{GERICHT_R * 0.85:.2f})",
            z=f"sin(randomA*2*PI)*(randomB*{GERICHT_R * 0.85:.2f})",
            speed_y="-1"))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 1.15, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.5,
                      length_scale=2.2)
       .with_physics(collision=True, removed_when_collided=True, gravity=0.25,
                     friction=1.0, bounce_chance=0.0)
       .with_sub_emitters(sub_emitter("eclipse:wand_star_splash",
                                      event="FirstCollision", probability=0.5))
       .with_module("colorBySpeed", color_by_speed(COOL_STERN, HOT_WHITE, 12.0, 32.0))
       .with_cull_box(*cull)
       .with_curves(color_over_lifetime=varied(
            [(0.0, 0.0), (0.1, 1.0), (0.9, 0.8), (1.0, 0.0)],
            [(0.0, 0.95, 0.95, 1.0), (1.0, 0.75, 0.85, 1.0)],
            [(0.0, 0.97, 0.93, 0.84), (1.0, 0.8, 0.78, 0.95)]))
       .with_lights(sky=15, block=15))

    # Constellation anchors: bright stars standing on the pentagon vertices.
    (fx.particle_emitter("constellation_anchors",
            duration=dur, looping=False, start_lifetime=random_between(32, 44),
            start_speed=constant(0), start_size=rand_size3(0.16, 0.24),
            simulation_space="Local", max_particles=10)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=1, count=constant(8))])
       .with_shape(function_shape(
            x=f"cos({_K}*{_CONST_STEP:.7f})*{CONST_R}",
            y="0.45",
            z=f"sin({_K}*{_CONST_STEP:.7f})*{CONST_R}"))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.15, 1.15, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            size_over_lifetime=curve(  # double-hump twinkle
                0.45, 1.0, [(0.0, 0.4, 0.2, 1.0, 0.3, 0.2, 0.5, 0.9),
                            (0.5, 0.9, 0.7, 0.1, 0.9, 1.0, 1.0, 0.2)],
                "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 1.0), (0.8, 0.75), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.78, 0.86, 1.0)]))
       .with_lights(sky=15, block=15))

    # Glint chains along the pentagon edges: born pre-lerped between vertex k and
    # k+1 (randomB is the along-edge fraction) — the constellation LINES appear as
    # chains of small twinkles even where no runner passes.
    (fx.particle_emitter("constellation_web",
            duration=dur, looping=False, start_lifetime=random_between(14, 24),
            start_speed=constant(0), start_size=rand_size3(0.04, 0.08),
            simulation_space="Local", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(0.5),
                      bursts=[burst(time=2, count=constant(18)),
                              burst(time=10, count=constant(10))])
       .with_shape(function_shape(
            x=f"(cos({_K}*{_CONST_STEP:.7f})*(1-randomB)+cos({_K1}*{_CONST_STEP:.7f})*randomB)*{CONST_R}",
            y="0.42",
            z=f"(sin({_K}*{_CONST_STEP:.7f})*(1-randomB)+sin({_K1}*{_CONST_STEP:.7f})*randomB)*{CONST_R}"))
       .with_material(texture_material(STAR_2X2, hdr=hdr(0.95, 1.0, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            size_over_lifetime=curve(0.35, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.85), (0.75, 0.5), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.75, 0.85, 1.0)],
                [(0.0, 0.97, 0.93, 0.82), (1.0, 0.82, 0.79, 0.95)])))

    # Runners: star sparks born ON a vertex flying to the NEXT vertex in exactly 20t
    # (start_speed = edge length in block/s), each dragging a short welded ara ribbon
    # — the lines of the constellation draw themselves between the anchors.
    runners = (fx.particle_emitter("constellation_runners",
            duration=dur, looping=False, start_lifetime=constant(20),
            start_speed=constant(_CONST_EDGE),
            start_size=rand_size3(0.09, 0.13),
            simulation_space="Local", max_particles=10)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=2, count=constant(3)),
                              burst(time=8, count=constant(3)),
                              burst(time=14, count=constant(2))])
       .with_shape(function_shape(
            x=f"cos({_K}*{_CONST_STEP:.7f})*{CONST_R}",
            y="0.42",
            z=f"sin({_K}*{_CONST_STEP:.7f})*{CONST_R}",
            speed_x=f"(cos({_K1}*{_CONST_STEP:.7f})-cos({_K}*{_CONST_STEP:.7f}))*{CONST_R / _CONST_EDGE:.5f}",
            speed_z=f"(sin({_K1}*{_CONST_STEP:.7f})-sin({_K}*{_CONST_STEP:.7f}))*{CONST_R / _CONST_EDGE:.5f}"))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 1.12, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 1.0), (0.85, 0.8), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.8, 0.86, 1.0)]))
       .with_lights(sky=15, block=15))
    runners.with_module("trails", ara_trails_module(
        0.07, 0.55, (0.95, 0.95, 1.0, 0.7), (0.55, 0.7, 0.95),
        (1.05, 1.1, 1.45), inertia=None))

    # Star shards blown outward by the verdict — actual 4-point stars, twinkling out.
    (fx.particle_emitter("star_burst",
            duration=dur, looping=False, start_lifetime=random_between(20, 32),
            start_speed=random_between(8.0, 18.0),
            start_size=rand_size3(0.07, 0.13),
            simulation_space="World", max_particles=32)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(24))])
       .with_shape(sphere(radius=0.6, thickness=0.0))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.1, 1.1, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.12, bounce_chance=0.0)
       .with_module("colorBySpeed", color_by_speed(COOL_STERN, HOT_WHITE, 3.0, 16.0))
       .with_cull_box(*cull)
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            size_over_lifetime=curve(0.3, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 1.0), (0.7, 0.75), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.7, 0.8, 1.0)],
                [(0.0, 0.97, 0.93, 0.84), (1.0, 0.78, 0.76, 0.95)]))
       .with_lights(sky=15, block=15))

    # Afterglow dome so the verdict bloom decays instead of cutting.
    (fx.particle_emitter("afterglow",
            duration=dur, looping=False, start_delay=constant(4), start_lifetime=constant(30),
            start_speed=constant(0), start_size=nf3(2.4), simulation_space="Local",
            max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(DOME_FAINT, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 1.8, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.35), (1.0, 0.0)],
                [(0.0, 0.7, 0.75, 1.0), (1.0, 0.45, 0.55, 0.85)])))
    return fx


# ---------------------------------------------------------------------------
# main — Birth/Collision children FIRST so the parents' fxLocation refs always
# resolve on a clean checkout (LINT-SUBEM-RESOLVE reads them off disk).
# ---------------------------------------------------------------------------
BUILDERS = {
    "wand_star_splash.fx": build_wand_star_splash,
    "wand_horizon_shockwave.fx": build_wand_horizon_shockwave,
    "wand_horizon_kernel.fx": build_wand_horizon_kernel,
    "wand_horizon_collapse.fx": build_wand_horizon_collapse,
    "wand_umbra_implosion.fx": build_wand_umbra_implosion,
    "wand_event_horizon.fx": build_wand_event_horizon,
    "wand_sonnenkern.fx": build_wand_sonnenkern,
    "wand_inferno_pillar.fx": build_wand_inferno_pillar,
    "wand_star_dome.fx": build_wand_star_dome,
    "wand_judgment_finale.fx": build_wand_judgment_finale,
}


def main(force_atlas: bool = False) -> int:
    rc = 0
    if force_atlas or not EMBER_ATLAS_PATH.exists():
        atlas_len = generate_ember_atlas(EMBER_ATLAS_PATH)
        print(f"WROTE {EMBER_ATLAS_PATH.relative_to(REPO_ROOT)} ({atlas_len} B)")
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        builder = builder_fn()
        raw_len, gz_len = builder.write(path)  # write() round-trip + shader-ref validates
        builder.write_fxproj(path.with_suffix(".fxproj"))  # binary-diff law sibling
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    sys.exit(main(force_atlas="--atlas" in sys.argv[1:]))
