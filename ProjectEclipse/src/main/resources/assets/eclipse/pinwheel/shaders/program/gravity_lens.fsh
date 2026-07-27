// eclipse:gravity_lens — WOAH-02 Gravitationsbruch veil-lensing post pass (FEATURE
// priority; registered by woah.gravityrift.client.GravityRiftLensFx, driven by
// GravityRiftClientState). NOT the black-hole pass: no event horizon, no rings — this
// is a REFRACTION anomaly. Space above the crater shivers like the air over a fire,
// except the haze streams UPWARD (the anti-gravity read), the whole frame leans
// gently toward the heart, the 45 s pulse sends one visible shock front through the
// glass, and the 10 s inversion turns the shimmer into a full-frame upward ripple
// with a cold violet lift.
// Layers, all scaled by Strength so the pass is a no-op at 0:
//   [g1] up-streaming refraction shimmer — two octaves of scrolling noise displace
//        the UVs near the heart's screen point; the scroll phase runs UP the screen
//        (heat-haze inverted); Detail-gated down to one octave under reducedFx
//   [g2] radial lean — a mild UV pull toward the heart (the "light bends into the
//        bowl" read; far subtler than black_hole's [b1])
//   [g3] pulse shock front — one expanding annular displacement band launched on the
//        beat (Pulse 1 → 0 raster from GravityRiftClientState.pulseKick): UVs are
//        pushed outward across the front, with a faint brightness crest riding it
//   [g4] inversion ripple — Invert 0..1 turns on frame-wide horizontal ripple bands
//        drifting upward + a violet-lifted, slightly desaturated grade ("the world
//        holds its breath upside down")
//   [g5] chroma fringe (Detail-gated) — a whisper of radial RGB split hugging the
//        strongest shimmer, so the anomaly reads glassy instead of smeared
// Uniforms (fed per frame by GravityRiftLensFx, no allocations):
//   Strength — eased 0..1 inside-amount (ramps over the zone approach apron)
//   Center   — heart center in UV space (SunTracker.worldToNdc; offscreen-safe hold)
//   Aspect   — viewport width / height (keeps the shimmer field circular)
//   Time     — pause-frozen seconds (shimmer scroll, ripple drift)
//   Pulse    — 0..1 beat kick (1 on the beat, decaying ~24 t; telegraph pre-ramp 0.4)
//   Invert   — 0..1 inversion window envelope (rise 20 t, hold, glide out)
//   Detail   — 1 normal, 0 under reducedFx (drops octave 2, the fringe and the crest)
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Strength;
uniform vec2 Center;
uniform float Aspect;
uniform float Time;
uniform float Pulse;
uniform float Invert;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

const vec3 LUMA_W = vec3(0.299, 0.587, 0.114);
// Cold amethyst identity (the heart is budding amethyst; the crater floor sculk).
const vec3 VIOLET_LIFT = vec3(0.72, 0.58, 1.0);
const vec3 CREST_COLOR = vec3(0.8, 0.72, 1.05);

void main() {
    float strength = clamp(Strength, 0.0, 1.0);
    float invert = clamp(Invert, 0.0, 1.0) * strength;
    float pulse = clamp(Pulse, 0.0, 1.0) * strength;
    if (strength <= 0.001) {
        fragColor = vec4(texture(DiffuseSampler0, texCoord).rgb, 1.0);
        return;
    }

    // Aspect-corrected frame so distances read circular on screen.
    vec2 toHeart = (texCoord - Center) * vec2(Aspect, 1.0);
    float dist = length(toHeart);
    vec2 dir = toHeart / max(dist, 1.0e-4);
    // The same radial direction mapped back into UV space (componentwise).
    vec2 dirUv = dir / vec2(Aspect, 1.0);

    // Proximity field of the anomaly: full inside ~0.12 screen radii of the heart,
    // fading out by ~0.55 — the shimmer hugs the bowl instead of smearing the sky.
    float field = smoothstep(0.55, 0.12, dist);

    // [g1] up-streaming refraction shimmer: noise sampled in a frame that scrolls
    // DOWN in texture space (so features climb UP on screen). Octave 2 Detail-gated.
    float ease = strength * strength * (3.0 - 2.0 * strength);
    vec2 shimmerUv = texCoord * vec2(9.0 * Aspect, 9.0);
    float n1 = efxNoise(shimmerUv + vec2(0.0, -Time * 0.9)) - 0.5;
    float n2 = (efxNoise(shimmerUv * 2.7 + vec2(3.7, -Time * 1.7)) - 0.5) * Detail;
    float shimmer = (n1 + 0.5 * n2) * (1.0 + 0.8 * invert);
    vec2 offset = vec2(shimmer * 0.55, shimmer) * 0.012 * ease * field;

    // [g2] radial lean: a mild pull toward the heart, saturating near the center.
    offset -= dirUv * 0.020 * ease * field * smoothstep(0.05, 0.30, dist);

    // [g3] pulse shock front: the ring radius expands as the kick decays
    // (r = 0.05 → 0.62 over Pulse 1 → 0); a gaussian-ish band displaces UVs outward.
    float crest = 0.0;
    if (pulse > 0.003) {
        float frontR = mix(0.62, 0.05, pulse);
        float band = exp(-pow((dist - frontR) / 0.045, 2.0));
        offset += dirUv * band * 0.016 * pulse;
        crest = band * pulse;
    }

    // [g4] inversion ripple: frame-wide horizontal bands drifting upward — reality
    // itself streams toward the sky while the window runs.
    if (invert > 0.003) {
        float ripple = sin(texCoord.y * 46.0 - Time * 7.0)
                + 0.5 * sin(texCoord.y * 83.0 - Time * 11.0);
        offset.x += ripple * 0.004 * invert;
        offset.y += 0.003 * invert * sin(Time * 3.0 + texCoord.x * 12.0);
    }

    vec2 warpedUv = clamp(texCoord + offset, vec2(0.001), vec2(0.999));

    // [g5] chroma fringe: radial RGB split scaled by the local displacement energy.
    float fringe = (length(offset) * 0.9 + 0.0006 * field * ease) * Detail;
    vec3 color = efxChroma(DiffuseSampler0, warpedUv, dirUv, fringe);

    // [g3] brightness crest riding the shock front (Detail-gated; subtle).
    color += CREST_COLOR * crest * 0.18 * Detail;

    // [g4] inversion grade: violet lift + mild desaturation, strongest near the bowl.
    if (invert > 0.003) {
        float luma = dot(color, LUMA_W);
        vec3 graded = mix(color, vec3(luma), 0.35 * invert);
        graded += VIOLET_LIFT * 0.06 * invert * (0.4 + 0.6 * field);
        color = graded;
    }

    // Output dither: the graded dark range bands at 8 bits otherwise.
    vec2 screenPx = texCoord * vec2(textureSize(DiffuseSampler0, 0));
    color += (efxHash(screenPx + vec2(mod(floor(Time * 4.0), 97.0))) - 0.5) * (1.0 / 255.0);

    fragColor = vec4(color, 1.0);
}
