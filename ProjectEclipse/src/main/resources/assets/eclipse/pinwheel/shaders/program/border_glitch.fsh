// eclipse:border_glitch v3 — LOCALIZED soft-border glitch (GLITCH team pass over the P2 R6
// v2 rewrite). v2 established the border-glued lens (blocky datamosh + RGB tear + invert
// pops); v3 makes the approach read as reality TEARING toward the ring:
//   1. blocky datamosh row displacement (efxBlockOffset, coarse + fine row scales),
//   1b. QUANTIZED datamosh pull: coarse screen cells snap toward the border direction in
//       4 discrete steps — space visibly compresses INTO the tear (v3),
//   1c. scanline desync burst riding the pushback KICK moment (v3, new Kick uniform),
//   1d. 2-frame FULL-screen tear at the kick IMPACT (v4, VEIL-REPASS-1): for the first
//       ~35 ms of the pulse the whole frame shears in two along a seed-rolled line —
//       the one instant the border is allowed to own every pixel. Displacement only
//       (no luminance flash), and it rides Kick, which is fed 0 under reducedFx.
//   2. RGB chromatic tear along the border direction, now scaling with proximity on top of
//       the masked strength (~14 px mid-approach → ~22 px touching, v3),
//   3. 2-frame color-invert pops while practically touching the ring (Proximity > 0.85).
// Uniforms (§3.3 names frozen; Kick is a v3 ADDITION), fed by border.client.BorderFxRenderer:
//   Proximity — 0 far → 1 touching; the strength curve is Proximity^1.5 (R6)
//   Time      — seconds (wraps at 100 s)
//   GlitchDir — NDC position of the nearest ring point (lens center; parked offscreen on
//               the border's side when the point is behind the camera)
//   Seed      — re-rolls with the world-patch reseed (post blocks and patches pop together);
//               +1000 flags the nether ring -> red-shifted palette (same pipeline)
//   Kick      — 1→0 pulse (~420 ms, quadratic) fired when the ring physically shoves the
//               player (prox rising edge through 1.0). ALWAYS 0 under reducedFx.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Proximity;
uniform float Time;
uniform vec2 GlitchDir;
uniform float Seed;
uniform float Kick;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    float prox = clamp(Proximity, 0.0, 1.0);
    float strength = pow(prox, 1.5);
    float nether = step(1000.0, Seed);
    float seed = Seed - nether * 1000.0;
    float kick = clamp(Kick, 0.0, 1.0);

    // Aspect-corrected screen coordinates so the lens is round on any resolution.
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
    float aspect = screenSize.x / max(screenSize.y, 1.0);
    vec2 p = (texCoord * 2.0 - 1.0) * vec2(aspect, 1.0);
    vec2 lens = clamp(GlitchDir, vec2(-2.5), vec2(2.5)) * vec2(aspect, 1.0);

    // Localized lens around the border's screen position; swells as the ring closes in.
    float lensRadius = mix(0.6, 1.6, strength);
    float lensDist = distance(p, lens);
    float mask = 1.0 - smoothstep(lensRadius * 0.35, lensRadius, lensDist);
    // Panic floor: touching the ring bleeds a fraction of the glitch across the whole
    // frame; the kick moment rips most of it fullscreen for its ~420 ms life (v3).
    mask = max(mask, smoothstep(0.85, 1.0, prox) * 0.35);
    mask = max(mask, kick * 0.75);
    float amt = strength * mask;

    // Direction toward the tear: aspect-space unit vector + its UV-space image (shared by
    // the v3 quantized pull and the RGB tear — v2 fed the aspect-space vector straight to
    // efxChroma, which overstretched the split horizontally on wide screens).
    vec2 tearDir = lens - p;
    float tearLen = length(tearDir);
    tearDir = tearLen > 1.0e-4 ? tearDir / tearLen : vec2(1.0, 0.0);
    vec2 tearUv = normalize(vec2(tearDir.x / aspect, tearDir.y));

    // Layer 1 — blocky datamosh displacement: coarse + fine row scales, re-gated ~12x/s and
    // re-laid-out whenever the CPU reseeds the world patches (Seed).
    float frameSeed = seed + floor(Time * 12.0) * 17.0;
    vec2 uv = texCoord;
    uv += efxBlockOffset(uv, frameSeed, amt);
    uv += efxBlockOffset(vec2(uv.x, uv.y * 3.7), frameSeed * 1.31, amt * 0.8) * 0.45;

    // Layer 1b (v3) — QUANTIZED pull toward the border: coarse cells snap toward the tear
    // in 4 discrete steps (0, 1/3, 2/3, 1 of the full pull). Quantizing the displacement is
    // what sells "datamosh", not smooth flow — blocks land on stepped offsets and pop to a
    // new layout with the 12 Hz frameSeed, like motion vectors gone stale.
    vec2 cell = floor(texCoord * vec2(26.0, 44.0));
    float cellGate = step(1.0 - 0.45 * amt, efxHash(cell + frameSeed * 0.013));
    float quantPull = floor(efxHash(cell * 1.71 + frameSeed * 0.031) * 4.0) * (1.0 / 3.0);
    // Polish 2: the kick briefly super-charges the pull — the shove reads as space slamming
    // back toward the ring, tying the desync burst and the datamosh field together.
    uv += tearUv * (quantPull * cellGate * min(1.0, amt + 0.5 * kick) * 0.028);

    // Wavy shear pulls rows toward the tear while very close.
    uv.x += sin(uv.y * 46.0 + Time * 9.0) * 0.006 * amt;

    // Layer 1c (v3) — scanline DESYNC burst on the kick moment: while the ring shoves the
    // player back, sparse thin scanlines rip near-full-width and a gated vertical sync-roll
    // wobbles the whole frame — a ~420 ms "reality rejected you" punch. Kick is fed as 0
    // under reducedFx, so the branch is dead there by construction.
    if (kick > 0.003) {
        float kickRow = floor(texCoord.y * 130.0);
        float kickGate = step(0.62, efxHash(vec2(kickRow, floor(Time * 45.0))));
        uv.x += (efxHash(vec2(kickRow * 3.17, seed)) - 0.5) * 0.24 * kick * kickGate;
        float rollGate = step(0.45, efxHash(vec2(floor(Time * 24.0), seed * 0.7)));
        uv.y += sin(Time * 63.0 + texCoord.y * 9.0) * 0.010 * kick * rollGate;

        // Layer 1d (v4) — the IMPACT frame: kick decays quadratically over 420 ms, so
        // kick > 0.85 is exactly the first ~35 ms (≈ 2 frames at 60 fps). For that
        // window the WHOLE frame tears in two at a seed-rolled line: the halves shear
        // in opposite directions along the tear axis (~32 px at 1080p at the crest).
        // Pure displacement — no flash, no invert — so the photosensitivity budget is
        // untouched; reducedFx never reaches here (Kick is fed 0 at the source).
        float impact = smoothstep(0.85, 0.97, kick);
        if (impact > 0.001) {
            float tearLine = 0.25 + 0.5 * efxHash(vec2(seed, 41.7));
            float side = step(tearLine, texCoord.y) * 2.0 - 1.0;
            uv += tearUv * side * 0.030 * impact;
        }
    }
    uv = clamp(uv, vec2(0.001), vec2(0.999));

    // Layer 2 — RGB tear along the direction toward the lens. v3: the split scales WITH
    // proximity on top of the masked strength (the tear physically widens as the ring
    // closes: ~14 px at 1080p mid-approach → ~24 px touching), plus a kick spike
    // (transient ~+10 px for the 420 ms burst — deliberate, it IS the punch).
    float tearAmt = 0.0073 * amt * (0.7 + 0.3 * sin(Time * 11.0)) * (1.0 + 0.75 * prox * prox)
            + 0.005 * kick;
    vec3 color = efxChroma(DiffuseSampler0, uv, tearUv, tearAmt);

    // Layer 3 — 2-frame color-invert pops while practically touching the ring (v3: the kick
    // counts as touching, so a pop can still land while the shove throws the camera back).
    float invertGate = step(0.85, max(prox, kick)) * step(0.962, efxHash(vec2(floor(Time * 28.0), seed)));
    color = mix(color, 1.0 - color, invertGate * clamp(mask * 1.6, 0.0, 1.0) * 0.85);

    // Palette wash + static sparkle inside the lens: violet ring, red-shifted in the nether.
    // v3 AV-sync hook: the grain bed follows the SAME prox² law as BorderStaticSound's
    // whisper (volume = proximity² × 0.5, IDEA-07 §3) — 70% lens-masked artifact term plus
    // a 30% prox²-synced fullscreen bed, so the visual static and the audio static loop
    // breathe as one without any new uniform.
    vec3 tint = mix(vec3(0.80, 0.55, 1.15), vec3(1.15, 0.48, 0.42), nether);
    float bed = prox * prox;
    float grain = efxNoise(p * 90.0 + vec2(Time * 37.0, seed)) * (0.7 * amt + 0.3 * bed);
    color = mix(color, color * tint, clamp(amt * 0.85, 0.0, 1.0) * 0.55);
    color += tint * grain * 0.13;

    // v3 banding guard: the lens mask / palette-wash gradients got stronger — temporal
    // ±1 LSB dither, scaled up slightly inside the lens.
    color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * (0.5 + amt));

    fragColor = vec4(color, 1.0);
}
