#!/usr/bin/env python3
"""newfx_d_fx — NEWFX-D Photon `.fx` assets (client atmosphere & transit), via fxlib.

Generates the five PLAN-NEWFX §2 D-package assets (into
`src/main/resources/assets/eclipse/fx/`, id = `eclipse:<name>`), consumed by the
`veilfx/AtmospherePhotonFxRows` id table (only D5 is a registry row — D1/D4 are
client-latched direct spawns, D2 rides `PhotonBridge.ensureAttachedFx`, D3 runs
per-anchor `LoopHandle`s in `veilfx/rift/RiftDrawIn`):

    eclipse:border_first_contact   D1 once-per-save floor-to-sky datamosh hairline at
                                   the ring bearing (~2 s; the 3 shards are Java-side)
    eclipse:breach_drift_cocoon    D2 glitch-ember cocoon + stretched light-threads
                                   riding the drift faller (entity-attached loop)
    eclipse:portal_draw_in         D3 dust/streamer in-draw compressing to sparks at
                                   the rift event line (per-anchor windowed loop)
    eclipse:totality_diamond_ring  D4 ONE blinding rim bead + short streak arc
                                   (photosensitivity: <=2 full-bright flash ticks)
    eclipse:storm_outrunners       D5 torn head-height gray wind-ribbon whipping past
                                   (windowed loop; the wisp cadence is Quasar-side)

These files are fxlib-generated (this script IS the committed source — the binary-diff
law's `.fxproj` requirement applies to editor exports only, tools/photon precedent).
Regenerate + validate with:

    python3 tools/photon/newfx_d_fx.py
    python3 tools/photon/fxlib.py validate src/main/resources/assets/eclipse/fx/{border_first_contact,breach_drift_cocoon,portal_draw_in,totality_diamond_ring,storm_outrunners}.fx

Style-guide conformance (FX-STYLE-GUIDE.md):
  - Palette: D1/D2/D3 are GLITCH (§1.3) — GLI_WHITE pops, GLI_VIOLET bleed, GLI_DEAD
    dropped-signal cells; magenta/cyan appear ONLY as a displaced split pair on D1's
    fringe flecks. D4 is the one SACRED moment (GLI_WHITE -> SAC_GOLD_PALE glints,
    settling on SAC_VOID). D5 stays desaturated STORM slate (§1.5 — storms are
    weather, not magic: alpha-blend, no bloom, no accent hues).
  - Motion: glitch = snaps + holds (§2) — datamosh cells pop with squared-off alpha
    holds and zero easing; the cocoon threads stutter via low-frequency/high-amplitude
    noise; D5 is pure storm shear (fast tangential whip, vertical motion none).
  - Timing: D1 scans hold/snap/drip inside its ~2 s; D4 is spine 0/2/28 (the crest IS
    the anticipation — the eclipse ramp did the telegraphing). Loops (D2/D3/D5) have
    no spine; their windows own materialize/release (INTEGRATION.md §4).
  - Budget: every emitter ships a cull box + hard maxParticles (worst D-stack
    ~190 live << 1500); Photon spawns charge MAX_LIVE_EXECUTORS, not FxBudget.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, BLEND_ALPHA, F, FX_ASSETS_DIR, FxBuilder, I, L, REPO_ROOT,
    box, burst, circle, constant, curve, dot, gradient, nf3, random_between,
    random_gradient, rom, sphere, texture_material, validate_file,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"
TEX_STATIC = "eclipse:textures/particle/static_4x4.png"
TEX_SQUARE = "eclipse:textures/particle/square_4x4.png"
TEX_BEAM = "eclipse:textures/particle/beam_core.png"

# §1.3 GLITCH + §1.1/§1.5 support tokens (r, g, b in 0..1).
GLI_WHITE = (1.0, 1.0, 1.0)
GLI_VIOLET = (0.725, 0.549, 1.0)      # #B98CFF
GLI_DEAD = (0.141, 0.110, 0.220)      # #241C38
GLI_MAGENTA = (1.0, 0.310, 0.847)     # #FF4FD8
GLI_CYAN = (0.310, 0.910, 1.0)        # #4FE8FF
SAC_GOLD_PALE = (1.0, 0.914, 0.659)   # #FFE9A8
SAC_VOID = (0.180, 0.137, 0.278)      # #2E2347
STM_SLATE = (0.227, 0.227, 0.333)     # #3A3A55


def pts_curve(points, lock=True):
    """NF curve through (t, value) points — linear bezier segments (build_world_fx helper)."""
    lo = min(v for _, v in points)
    hi = max(v for _, v in points)
    span = (hi - lo) or 1.0
    norm = [(t, (v - lo) / span) for t, v in points]
    segments = []
    for (x0, y0), (x1, y1) in zip(norm, norm[1:]):
        segments.append((x0, y0,
                         x0 + (x1 - x0) / 3.0, y0 + (y1 - y0) / 3.0,
                         x0 + 2.0 * (x1 - x0) / 3.0, y0 + 2.0 * (y1 - y0) / 3.0,
                         x1, y1))
    return curve(lo, hi if hi != lo else lo + 1.0, segments, lock=lock)


def ribbon_renderer(material_entry):
    """RendererSetting compound for an EMBEDDED araConfig (build_world_fx helper);
    written explicitly so ribbons never fall back to the MISSING (pink) material."""
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": {"_enable": B(0)}, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


def rgb(color, *alpha_scaled):
    """(t, r, g, b) rows from a palette token — gradient() rgb_pts convenience."""
    return [(t, color[0], color[1], color[2]) for t in alpha_scaled]


# ---------------------------------------------------------------------------
# D1 — eclipse:border_first_contact (one-shot, ~44t, anchored at the ring point)
# ---------------------------------------------------------------------------
def build_border_first_contact() -> FxBuilder:
    """One floor-to-sky hairline of datamosh static at the ring bearing. Anchored by
    FirstContactSeam at (nearest ring point, eyeY-1.5). GLITCH grammar: the beam width
    SNAPS between quantized holds (no easing), the cells pop with hard alpha holds on
    short lifetimes, magenta/cyan appear only as an offset split pair of edge flecks."""
    fx = FxBuilder("border_first_contact")

    # L1 hairline: a vertical beam whose width flickers in steps — the "line" read
    # from any distance. Dies over the last quarter (the vanish, fade to aubergine).
    (fx.beam_emitter(
            "hairline",
            duration=44, looping=False,
            end=(0.0, 30.0, 0.0),
            # Quantized width snaps (12 Hz-ish holds): 0 -> pop -> hold -> drop ...
            width=pts_curve([(0.0, 0.02), (0.05, 0.16), (0.18, 0.16), (0.2, 0.05),
                             (0.34, 0.05), (0.36, 0.13), (0.55, 0.13), (0.58, 0.04),
                             (0.75, 0.09), (0.9, 0.02), (1.0, 0.0)], lock=False),
            color_nf=gradient(
                [(0.0, 0.9), (0.7, 0.7), (1.0, 0.0)],
                [(0.0, *GLI_WHITE), (0.35, *GLI_VIOLET), (1.0, *SAC_VOID)]))
       .at(0.0, -2.0, 0.0)
       .with_material(texture_material(TEX_BEAM, hdr=(1.3, 1.2, 1.5))))

    # L2 datamosh cells: hard static quads popping along the column — burst every 2t
    # keeps the 12 Hz-ish reseed read; 3–7t lifetimes with squared-off alpha = holds.
    (fx.particle_emitter(
            "datamosh_cells",
            duration=40, looping=False,
            start_lifetime=random_between(3, 7),
            start_speed=constant(0.01),
            start_size=nf3(random_between(0.18, 0.42), random_between(0.18, 0.42),
                           random_between(0.18, 0.42)),
            simulation_space="World", max_particles=40)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(2), cycles=15, interval=2)])
       .with_shape(box(emit_from="Volume"), position=(0.0, 12.0, 0.0),
                   scale=(0.18, 28.0, 0.18))
       .with_material(texture_material(TEX_STATIC, hdr=(1.2, 1.0, 1.4),
                                       pixel_art=True, pixel_art_bits=4))
       .with_curves(color_over_lifetime=gradient(
            # snap in 1t, HOLD, snap out — no eased ramps (glitch law).
            [(0.0, 0.0), (0.08, 0.95), (0.75, 0.85), (0.85, 0.0), (1.0, 0.0)],
            [(0.0, *GLI_WHITE), (0.3, *GLI_VIOLET), (1.0, *GLI_DEAD)]))
       .with_cull_box((-2.0, -3.0, -2.0), (2.0, 30.0, 2.0)))

    # L3 chroma fringe: sparse magenta/cyan fleck pairs displaced off the line on one
    # axis (±0.1) — the ONLY legal magenta/cyan appearance (§1.3 split-pair rule).
    (fx.particle_emitter(
            "chroma_fringe",
            duration=40, looping=False,
            start_lifetime=random_between(2, 4),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.12, 0.24), random_between(0.12, 0.24),
                           random_between(0.12, 0.24)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=2, count=constant(2), cycles=9, interval=4)])
       .with_shape(box(emit_from="Volume"), position=(0.0, 10.0, 0.0),
                   scale=(0.55, 22.0, 0.18))
       .with_material(texture_material(TEX_SQUARE, hdr=(1.2, 1.2, 1.2),
                                       pixel_art=True, pixel_art_bits=4))
       .with_curves(color_over_lifetime=random_gradient(
            [(0.0, 0.85), (0.8, 0.7), (1.0, 0.0)], [(0.0, *GLI_MAGENTA), (1.0, *GLI_MAGENTA)],
            [(0.0, 0.85), (0.8, 0.7), (1.0, 0.0)], [(0.0, *GLI_CYAN), (1.0, *GLI_CYAN)]))
       .with_cull_box((-2.0, -3.0, -2.0), (2.0, 30.0, 2.0)))
    return fx


# ---------------------------------------------------------------------------
# D2 — eclipse:breach_drift_cocoon (entity-attached loop on the drift faller)
# ---------------------------------------------------------------------------
def build_breach_drift_cocoon() -> FxBuilder:
    """Loose cocoon riding the faller (Local space — the aura law). Three thread
    carriers orbit the body dragging short lagging ribbons that the noise stutter
    snaps sideways; glitch-embers pop on a thin shell around the chest. Entity
    executor auto-cleans on death; DriftCocoon stops it gracefully at DRIFT_END."""
    fx = FxBuilder("breach_drift_cocoon")

    # L1 thread carriers: slow wrap + hard positional stutter (frame-skip read); the
    # ribbons are the "stretched light-threads" that snap and re-form.
    carriers = (fx.particle_emitter(
            "thread_carriers",
            duration=60, looping=True,
            start_lifetime=constant(55), start_speed=constant(0.0),
            start_size=nf3(0.09), simulation_space="Local", max_particles=3)
        .with_emission(rate=constant(0.055))  # ~one new carrier as one dies
        .with_shape(circle(radius=1.25, thickness=0.15), position=(0.0, 1.1, 0.0))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0.0), constant(0.09), constant(0.0))),
            # Low-frequency / high-amplitude noise = sideways stutter, not shimmer.
            noise=dict(frequency=0.25, quality="Noise3D",
                       position=nf3(constant(0.16), constant(0.05), constant(0.16))))
        .with_material(texture_material(TEX_CIRCLE, hdr=(1.2, 1.0, 1.6)))
        .with_cull_box((-2.5, -2.0, -2.5), (2.5, 3.5, 2.5)))
    carriers.with_module("trails", {
        "ratio": F(1.0),
        "lifetime": constant(0.5),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            "space": "World", "alignment": "View",
            "thickness": F(0.07),
            "smoothness": I(3),  # deliberately low: threads keep their kinks
            "time": F(0.55), "timeInterval": F(0.05),
            # GLI_WHITE core -> GLI_VIOLET bleed -> out.
            "colorOverLength": gradient(
                [(0.0, 0.85), (0.55, 0.55), (1.0, 0.0)],
                [(0.0, *GLI_WHITE), (0.4, *GLI_VIOLET), (1.0, *GLI_VIOLET)]),
            "physicsSetting": {  # lag hard, snap back — threads re-forming
                "warmup": F(0.0), "gravity": L([F(0.0), F(0.0), F(0.0)]),
                "inertia": F(0.5), "velocitySmoothing": F(0.6), "damping": F(0.7)},
            "renderer": ribbon_renderer(texture_material(TEX_CIRCLE, hdr=(1.2, 1.0, 1.6))),
        }})

    # L2 glitch embers: hard cells popping on the cocoon shell, held then dropped.
    (fx.particle_emitter(
            "glitch_embers",
            duration=60, looping=True,
            start_lifetime=random_between(6, 12),
            start_speed=random_between(0.01, 0.03),
            start_size=nf3(random_between(0.07, 0.16), random_between(0.07, 0.16),
                           random_between(0.07, 0.16)),
            simulation_space="Local", max_particles=36)
       .with_emission(rate=constant(1.1))
       .with_shape(sphere(radius=1.05, thickness=0.2), position=(0.0, 1.0, 0.0),
                   scale=(1.0, 1.5, 1.0))
       .with_material(texture_material(TEX_STATIC, hdr=(1.15, 1.0, 1.35),
                                       pixel_art=True, pixel_art_bits=4))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.9), (0.7, 0.8), (0.8, 0.0), (1.0, 0.0)],
                [(0.0, *GLI_WHITE), (0.35, *GLI_VIOLET), (1.0, *GLI_DEAD)]),
            noise=dict(frequency=0.3, quality="Noise3D",
                       position=nf3(constant(0.1), constant(0.03), constant(0.1))))
       .with_cull_box((-2.5, -2.0, -2.5), (2.5, 3.5, 2.5)))
    return fx


# ---------------------------------------------------------------------------
# D3 — eclipse:portal_draw_in (windowed loop, one per portal rift anchor)
# ---------------------------------------------------------------------------
def build_portal_draw_in() -> FxBuilder:
    """Ambient in-draw at an open portal tear: motes born on a ~4-block shell fall
    INTO the plane, accelerating and compressing (size shrink, brightness rise) until
    they die as sparks at the event line; two streamer carriers spiral in dragging
    thin ribbons. Sphere emission keeps it orientation-agnostic (upright portals and
    the odd flat tear share the asset). GLI_VIOLET body — the §6.4 bridge tone both
    portal palettes (xbox violet / backrooms wax-gold) contain."""
    fx = FxBuilder("portal_draw_in")

    # L1 in-draw motes: negative radial speed = inward; speed_modifier ramps them
    # faster as they age (the pull strengthens approaching the event line).
    (fx.particle_emitter(
            "indraw_motes",
            duration=60, looping=True,
            start_lifetime=random_between(11, 16),
            start_speed=random_between(-0.42, -0.24),
            start_size=nf3(random_between(0.05, 0.12), random_between(0.05, 0.12),
                           random_between(0.05, 0.12)),
            simulation_space="World", max_particles=70)
       .with_emission(rate=constant(1.6))
       .with_shape(sphere(radius=4.0, thickness=0.12))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.1, 0.9, 1.5)))
       .with_curves(
            velocity_over_lifetime=dict(
                speed_modifier=pts_curve([(0.0, 0.55), (0.7, 1.1), (1.0, 1.8)])),
            size_over_lifetime=pts_curve([(0.0, 1.0), (0.7, 0.6), (1.0, 0.25)]),
            color_over_lifetime=gradient(  # dim drift -> white-hot at the line
                [(0.0, 0.0), (0.25, 0.5), (0.85, 0.75), (1.0, 0.0)],
                [(0.0, *SAC_VOID), (0.55, *GLI_VIOLET), (1.0, *GLI_WHITE)]))
       .with_cull_box((-6.0, -6.0, -6.0), (6.0, 6.0, 6.0)))

    # L2 streamer carriers: spiral-in pair dragging thin light-threads.
    streamers = (fx.particle_emitter(
            "streamer_carriers",
            duration=60, looping=True,
            start_lifetime=random_between(20, 26),
            start_speed=random_between(-0.16, -0.1),
            start_size=nf3(0.06), simulation_space="World", max_particles=2)
        .with_emission(rate=constant(0.085))
        .with_shape(sphere(radius=3.6, thickness=0.05))
        .with_curves(velocity_over_lifetime=dict(
            orbital_mode="AngularVelocity",
            orbital=nf3(constant(0.0), constant(0.12), constant(0.0)),
            speed_modifier=pts_curve([(0.0, 0.7), (1.0, 1.6)])))
        .with_material(texture_material(TEX_CIRCLE, hdr=(1.2, 1.0, 1.6)))
        .with_cull_box((-6.0, -6.0, -6.0), (6.0, 6.0, 6.0)))
    streamers.with_module("trails", {
        "ratio": F(1.0),
        "lifetime": constant(0.6),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            "space": "World", "alignment": "View",
            "thickness": F(0.06),
            "smoothness": I(4),
            "time": F(0.7), "timeInterval": F(0.05),
            "colorOverLength": gradient(
                [(0.0, 0.7), (0.6, 0.45), (1.0, 0.0)],
                [(0.0, *GLI_VIOLET), (1.0, *SAC_VOID)]),
            "physicsSetting": {
                "warmup": F(0.0), "gravity": L([F(0.0), F(0.0), F(0.0)]),
                "inertia": F(0.3), "velocitySmoothing": F(0.75), "damping": F(0.8)},
            "renderer": ribbon_renderer(texture_material(TEX_CIRCLE, hdr=(1.2, 1.0, 1.6))),
        }})

    # L3 event-line sparks: tiny white pops at the center — the compression payoff.
    (fx.particle_emitter(
            "event_sparks",
            duration=60, looping=True,
            start_lifetime=random_between(4, 7),
            start_speed=random_between(0.02, 0.06),
            start_size=nf3(random_between(0.04, 0.09), random_between(0.04, 0.09),
                           random_between(0.04, 0.09)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.4))
       .with_shape(sphere(radius=0.35))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.8, 1.6, 2.0)))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.9), (0.5, 0.6), (1.0, 0.0)],
            [(0.0, *GLI_WHITE), (1.0, *GLI_VIOLET)]))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0)))
    return fx


# ---------------------------------------------------------------------------
# D4 — eclipse:totality_diamond_ring (one-shot, 30t, anchored on the sun bearing)
# ---------------------------------------------------------------------------
def build_totality_diamond_ring() -> FxBuilder:
    """ONE blinding bead on the blacked-out rim, a short streak arc, dead by ~1.5 s.
    Anchored 60 blocks out along the sun direction by TotalityPeakFx, so sizes are
    authored for distance (bead ~3 blocks = ~3° angular). PHOTOSENSITIVITY: exactly
    one bead, full-bright for <=2 ticks (§3 impact law), then a decaying glow — no
    strobe, no repeats, nothing else flashes."""
    fx = FxBuilder("totality_diamond_ring")

    # L1 the bead: 2 flash ticks at full alpha/size, then a fast-decaying glow.
    (fx.particle_emitter(
            "bead",
            duration=30, looping=False,
            start_lifetime=constant(30), start_speed=constant(0.0),
            start_size=nf3(3.0), simulation_space="World", max_particles=1)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1), cycles=1)])
       .with_shape(dot())
       .with_material(texture_material(TEX_CIRCLE, hdr=(2.0, 1.95, 1.85)))
       .with_curves(
            size_over_lifetime=pts_curve([(0.0, 1.0), (0.07, 1.0), (0.2, 0.45),
                                          (1.0, 0.18)]),
            color_over_lifetime=gradient(
                # alpha 1.0 only for t<=0.067 of 30t = the 2 legal flash frames.
                [(0.0, 1.0), (0.067, 1.0), (0.14, 0.55), (0.75, 0.3), (1.0, 0.0)],
                [(0.0, *GLI_WHITE), (0.25, *SAC_GOLD_PALE), (1.0, *SAC_VOID)]))
       .with_cull_box((-10.0, -6.0, -10.0), (10.0, 8.0, 10.0)))

    # L2 the streak: one carrier slides along the rim tangent dragging a white-gold
    # ribbon — "streaks a short arc, and dies". At 60 blocks any world tangent reads
    # as along-the-rim.
    streak = (fx.particle_emitter(
            "streak_carrier",
            duration=30, looping=False,
            start_lifetime=constant(22), start_speed=constant(0.0),
            start_size=nf3(0.5), simulation_space="World", max_particles=1)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=1, count=constant(1), cycles=1)])
        .with_shape(dot())
        .with_curves(velocity_over_lifetime=dict(
            linear=nf3(constant(0.42), constant(0.14), constant(0.0)),
            speed_modifier=pts_curve([(0.0, 1.0), (1.0, 0.25)])))  # eases out, dies
        .with_material(texture_material(TEX_CIRCLE, hdr=(1.8, 1.7, 1.5)))
        .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.9), (0.6, 0.5), (1.0, 0.0)],
            [(0.0, *GLI_WHITE), (0.5, *SAC_GOLD_PALE), (1.0, *SAC_VOID)]))
        .with_cull_box((-10.0, -6.0, -10.0), (10.0, 8.0, 10.0)))
    streak.with_module("trails", {
        "ratio": F(1.0),
        "lifetime": constant(1.0),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            "space": "World", "alignment": "View",
            "thickness": F(0.55),
            "smoothness": I(6),
            "time": F(0.9), "timeInterval": F(0.05),
            "thicknessOverLength": pts_curve([(0.0, 1.0), (1.0, 0.1)]),
            "colorOverLength": gradient(
                [(0.0, 0.85), (0.55, 0.5), (1.0, 0.0)],
                [(0.0, *GLI_WHITE), (0.45, *SAC_GOLD_PALE), (1.0, *SAC_VOID)]),
            "physicsSetting": {
                "warmup": F(0.0), "gravity": L([F(0.0), F(0.0), F(0.0)]),
                "inertia": F(0.2), "velocitySmoothing": F(0.8), "damping": F(0.85)},
            "renderer": ribbon_renderer(texture_material(TEX_CIRCLE, hdr=(1.8, 1.7, 1.5))),
        }})

    # L3 settle glints: six pale-gold sparks shed off the bead, fading to void.
    (fx.particle_emitter(
            "settle_glints",
            duration=30, looping=False,
            start_lifetime=random_between(10, 16),
            start_speed=random_between(0.2, 0.45),
            start_size=nf3(random_between(0.3, 0.55), random_between(0.3, 0.55),
                           random_between(0.3, 0.55)),
            simulation_space="World", max_particles=6)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=2, count=constant(6), cycles=1)])
       .with_shape(sphere(radius=0.5, thickness=0.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.5, 1.4, 1.1)))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.8), (0.6, 0.45), (1.0, 0.0)],
            [(0.0, *SAC_GOLD_PALE), (1.0, *SAC_VOID)]))
       .with_cull_box((-10.0, -6.0, -10.0), (10.0, 8.0, 10.0)))
    return fx


# ---------------------------------------------------------------------------
# D5 — eclipse:storm_outrunners (windowed loop at the player's head-height anchor)
# ---------------------------------------------------------------------------
def build_storm_outrunners() -> FxBuilder:
    """ONE torn horizontal gray ribbon whipping past at head height inside the near
    approach band (the Photon garnish over StormApproachFx's Quasar runner cadence).
    Storm grammar only (§2 shear): fast tangential motion, no vertical drift, slate
    body, alpha-blend, zero bloom (§1.5 — storms are weather, not magic)."""
    fx = FxBuilder("storm_outrunners")

    # L1 ribbon carriers: born on a wide ring around the anchor, whipped tangentially
    # (~1.1 blk/t at r=5) so the torn ribbon streaks PAST the player's head.
    carriers = (fx.particle_emitter(
            "ribbon_carriers",
            duration=80, looping=True,
            start_lifetime=random_between(22, 30),
            start_speed=constant(0.0),
            start_size=nf3(0.12), simulation_space="World", max_particles=2)
        .with_emission(rate=constant(0.07))
        .with_shape(circle(radius=5.0, thickness=0.08))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0.0), constant(0.22), constant(0.0))),
            noise=dict(frequency=0.5, quality="Noise2D",  # the "torn" flutter
                       position=nf3(constant(0.09), constant(0.04), constant(0.09))))
        .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-8.0, -3.0, -8.0), (8.0, 4.0, 8.0)))
    carriers.with_module("trails", {
        "ratio": F(1.0),
        "lifetime": constant(0.6),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            "space": "World", "alignment": "View",
            "thickness": F(0.3),
            "smoothness": I(3),  # low on purpose: the ribbon keeps its tears
            "time": F(0.8), "timeInterval": F(0.06),
            # Ragged width: repeated pinches along the length = torn edges.
            "thicknessOverLength": pts_curve([(0.0, 0.15), (0.15, 1.0), (0.3, 0.35),
                                              (0.5, 0.9), (0.65, 0.25), (0.8, 0.7),
                                              (1.0, 0.05)], lock=False),
            "colorOverLength": gradient(
                [(0.0, 0.5), (0.6, 0.35), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (1.0, *GLI_DEAD)]),
            "physicsSetting": {  # sag + whip in its own slipstream
                "warmup": F(0.0), "gravity": L([F(0.0), F(-0.02), F(0.0)]),
                "inertia": F(0.35), "velocitySmoothing": F(0.7), "damping": F(0.75)},
            "renderer": ribbon_renderer(texture_material(TEX_SMOKE, blend=BLEND_ALPHA)),
        }})

    # L2 ripped-air rags: faint slate puffs shed where the ribbon passes.
    (fx.particle_emitter(
            "air_rags",
            duration=80, looping=True,
            start_lifetime=random_between(8, 13),
            start_speed=random_between(0.02, 0.06),
            start_size=nf3(random_between(0.25, 0.5), random_between(0.25, 0.5),
                           random_between(0.25, 0.5)),
            simulation_space="World", max_particles=20)
       .with_emission(rate=constant(0.5))
       .with_shape(circle(radius=4.5, thickness=0.25))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.25, 0.3), (1.0, 0.0)],
            [(0.0, *STM_SLATE), (1.0, *GLI_DEAD)]))
       .with_cull_box((-8.0, -3.0, -8.0), (8.0, 4.0, 8.0)))
    return fx


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
BUILDERS = {
    "border_first_contact.fx": build_border_first_contact,
    "breach_drift_cocoon.fx": build_breach_drift_cocoon,
    "portal_draw_in.fx": build_portal_draw_in,
    "totality_diamond_ring.fx": build_totality_diamond_ring,
    "storm_outrunners.fx": build_storm_outrunners,
}


def main() -> int:
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        raw_len, gz_len = builder_fn().write(path)  # write() round-trip-validates
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}:")
            for e in errors:
                print(f"  - {e}")
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
