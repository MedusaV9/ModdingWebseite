#!/usr/bin/env python3
"""a0_proof_fx — A0 shader-foundation proof asset (eclipse:a0_shader_proof).

ONE deliberately-unregistered .fx that exercises all three A0 custom shaders
(assets/eclipse/shaders/core/, authored via fxlib.material_shader):

    soft_mist     eclipse:soft_particle      smoke bed hugging the ground — the
                                             SceneDepth fade means NO hard cut
                                             where the quads meet the floor
    force_dome    eclipse:fresnel_shell      one 3-blk force-field impostor:
                                             transparent face, glowing violet rim,
                                             SceneDepth seam where it meets ground
    glitch_pops   eclipse:rgb_split_distort  small flickering decals that smear the
                                             scene behind them into RGB-split wobble

NOT registered in any PhotonFxRegistry row (A0 contract: no shared registrar
files). `/dev photon test eclipse:a0_shader_proof` resolves the RAW fx id via
PhotonBridge.spawn -> Photon FXHelper -> assets/eclipse/fx/a0_shader_proof.fx
(verified: DevPhotonCommands + FxDevClient.photonTest — only `fx/cue/` prefixed
ids go through the registry). Remember `/photon_client clear_client_fx_cache`
after regenerating.

Stacking-law conformance: dark birth tints (SAC_VOID/STM_SLATE bodies), wide
birth shells, trimmed counts, HDR only on the fresnel rim (rgb*a max 2.0 < 4.0
ceiling), alpha-blended passes sort DISTANCE.

This script IS the authoring source for the binary .fx blob. Run:
python3 tools/photon/a0_proof_fx.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, FX_ASSETS_DIR, REPO_ROOT,
    FxBuilder, burst, circle, constant, curve, gradient, material_shader, nf3,
    random_between, sphere, validate_file,
    SEG_EASE_OUT_CREST, SEG_OVERSHOOT_SETTLE, SEG_DECAY_TAIL,
)

TEX_SMOKE = "photon:textures/particle/smoke.png"

# FX-STYLE-GUIDE §1 tokens (dark stacking bases + the sacred violet family).
SAC_VOID = (0.180, 0.137, 0.278)      # #2E2347 dark birth tint
STM_SLATE = (0.227, 0.227, 0.333)     # #3A3A55
SAC_VIOLET = (0.725, 0.549, 1.0)      # #B98CFF
GLI_MAGENTA = (1.0, 0.310, 0.847)     # #FF4FD8

CULL = ((-6.0, -2.0, -6.0), (6.0, 7.0, 6.0))
DURATION = 160  # ticks; one-shot


def _size3(lower, upper, segments):
    """Uniform xyz size_over_lifetime from one bezier curve spec."""
    return nf3(curve(lower, upper, segments, "lifetime", "size"),
               curve(lower, upper, segments, "lifetime", "size"),
               curve(lower, upper, segments, "lifetime", "size"))


def build_proof() -> FxBuilder:
    fx = FxBuilder("a0_shader_proof")

    # L1 soft mist bed: 12 fat smoke quads born ON the floor line so the classic
    # hard geometry cut would be maximally visible — soft_particle fades it out.
    (fx.particle_emitter(
            "soft_mist",
            duration=DURATION, looping=False, max_particles=24,
            start_lifetime=random_between(90, 130), start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(1.0, 1.6), random_between(1.0, 1.6),
                           random_between(1.0, 1.6)),
            simulation_space="Local")
       .at(0.0, 0.3, 0.0)
       .with_emission(bursts=[burst(time=0, count=12)])
       .with_shape(circle(radius=1.8, thickness=0.5))
       .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": TEX_SMOKE},
            uniforms={"SoftDistance": 0.9, "NearFade": 0.6},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), random_between(0.01, 0.04),
                                                   constant(0))),
            size_over_lifetime=_size3(0.55, 1.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.18, 0.5), (0.75, 0.4), (1.0, 0.0)],
                [(0.0, *SAC_VOID), (0.6, *STM_SLATE), (1.0, *SAC_VOID)])))

    # L2 force dome: ONE 3-blk fresnel impostor hovering half into the mist so
    # both reads land — violet rim glow + the SceneDepth seam ring at the floor.
    (fx.particle_emitter(
            "force_dome",
            duration=DURATION, looping=False, max_particles=2,
            start_lifetime=constant(150), start_speed=constant(0),
            start_size=nf3(constant(3.0), constant(3.0), constant(3.0)),
            simulation_space="Local")
       .at(0.0, 1.1, 0.0)
       .with_emission(bursts=[burst(time=10, count=1)])
       .with_shape(sphere(radius=0.05))
       .with_material(material_shader(
            "eclipse:fresnel_shell",
            uniforms={"ShellColor": (0.72, 0.55, 1.0, 0.85),
                      "RimHDRColor": (1.45, 1.1, 2.0, 1.0),
                      "FresnelPower": 2.5, "FaceAlpha": 0.07,
                      "IntersectWidth": 0.4},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*CULL)
       .with_curves(
            size_over_lifetime=_size3(0.2, 1.0, [SEG_OVERSHOOT_SETTLE]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 1.0), (0.85, 0.9), (1.0, 0.0)],
                [(0.0, *SAC_VIOLET), (1.0, *SAC_VIOLET)])))

    # L3 glitch pops: staggered volleys of small scene-smearing decals around the
    # dome shoulder — each quad chromatic-splits and wobbles the world behind it.
    (fx.particle_emitter(
            "glitch_pops",
            duration=DURATION, looping=False, max_particles=16,
            start_lifetime=random_between(18, 30), start_speed=constant(0),
            start_size=nf3(random_between(0.55, 0.95), random_between(0.55, 0.95),
                           random_between(0.55, 0.95)),
            simulation_space="Local")
       .at(0.0, 1.4, 0.0)
       .with_emission(bursts=[burst(time=25, count=3, cycles=4, interval=12)])
       .with_shape(sphere(radius=1.9, thickness=0.2))
       .with_material(material_shader(
            "eclipse:rgb_split_distort",
            uniforms={"SplitStrength": 0.007, "WobbleAmp": 0.0045,
                      "WobbleSpeed": 2.2,
                      "TintColor": (*GLI_MAGENTA, 0.3)},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*CULL)
       .with_curves(
            size_over_lifetime=_size3(0.6, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.9), (0.7, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, *GLI_MAGENTA)])))
    return fx


BUILDERS = {
    "a0_shader_proof.fx": build_proof,
}


def main() -> int:
    rc = 0
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
    sys.exit(main())
