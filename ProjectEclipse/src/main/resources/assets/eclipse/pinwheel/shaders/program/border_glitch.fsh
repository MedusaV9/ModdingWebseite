// eclipse:border_glitch v2 — LOCALIZED soft-border glitch (P2 R6 rewrite, FEATURE priority).
// v1 applied a weak, uniform fullscreen aberration; v2 masks three layered artifacts to a
// lens glued to the border's screen position, so the effect reads as "reality tearing over
// there" instead of a screen-wide filter:
//   1. blocky datamosh row displacement (efxBlockOffset, coarse + fine row scales),
//   2. RGB chromatic tear along the border direction (efxChroma, up to ~14 px),
//   3. 2-frame color-invert pops while practically touching the ring (Proximity > 0.85).
// Uniforms (frozen §3.3), fed per frame by border.client.BorderFxRenderer:
//   Proximity — 0 far → 1 touching; the strength curve is Proximity^1.5 (R6)
//   Time      — seconds (wraps at 100 s)
//   GlitchDir — NDC position of the nearest ring point (lens center; parked offscreen on
//               the border's side when the point is behind the camera)
//   Seed      — re-rolls with the world-patch reseed (post blocks and patches pop together);
//               +1000 flags the nether ring -> red-shifted palette (same pipeline)
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Proximity;
uniform float Time;
uniform vec2 GlitchDir;
uniform float Seed;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    float prox = clamp(Proximity, 0.0, 1.0);
    float strength = pow(prox, 1.5);
    float nether = step(1000.0, Seed);
    float seed = Seed - nether * 1000.0;

    // Aspect-corrected screen coordinates so the lens is round on any resolution.
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
    float aspect = screenSize.x / max(screenSize.y, 1.0);
    vec2 p = (texCoord * 2.0 - 1.0) * vec2(aspect, 1.0);
    vec2 lens = clamp(GlitchDir, vec2(-2.5), vec2(2.5)) * vec2(aspect, 1.0);

    // Localized lens around the border's screen position; swells as the ring closes in.
    float lensRadius = mix(0.6, 1.6, strength);
    float lensDist = distance(p, lens);
    float mask = 1.0 - smoothstep(lensRadius * 0.35, lensRadius, lensDist);
    // Panic floor: touching the ring bleeds a fraction of the glitch across the whole frame.
    mask = max(mask, smoothstep(0.85, 1.0, prox) * 0.35);
    float amt = strength * mask;

    // Layer 1 — blocky datamosh displacement: coarse + fine row scales, re-gated ~12x/s and
    // re-laid-out whenever the CPU reseeds the world patches (Seed).
    float frameSeed = seed + floor(Time * 12.0) * 17.0;
    vec2 uv = texCoord;
    uv += efxBlockOffset(uv, frameSeed, amt);
    uv += efxBlockOffset(vec2(uv.x, uv.y * 3.7), frameSeed * 1.31, amt * 0.8) * 0.45;
    // Wavy shear pulls rows toward the tear while very close.
    uv.x += sin(uv.y * 46.0 + Time * 9.0) * 0.006 * amt;
    uv = clamp(uv, vec2(0.001), vec2(0.999));

    // Layer 2 — RGB tear along the direction toward the lens (up to ~14 px at full strength).
    vec2 tearDir = lens - p;
    float tearLen = length(tearDir);
    tearDir = tearLen > 1.0e-4 ? tearDir / tearLen : vec2(1.0, 0.0);
    float tearAmt = 0.0073 * amt * (0.7 + 0.3 * sin(Time * 11.0));
    vec3 color = efxChroma(DiffuseSampler0, uv, tearDir, tearAmt);

    // Layer 3 — 2-frame color-invert pops while practically touching the ring.
    float invertGate = step(0.85, prox) * step(0.962, efxHash(vec2(floor(Time * 28.0), seed)));
    color = mix(color, 1.0 - color, invertGate * clamp(mask * 1.6, 0.0, 1.0) * 0.85);

    // Palette wash + static sparkle inside the lens: violet ring, red-shifted in the nether.
    vec3 tint = mix(vec3(0.80, 0.55, 1.15), vec3(1.15, 0.48, 0.42), nether);
    float grain = efxNoise(p * 90.0 + vec2(Time * 37.0, seed)) * amt;
    color = mix(color, color * tint, clamp(amt * 0.85, 0.0, 1.0) * 0.55);
    color += tint * grain * 0.13;

    fragColor = vec4(color, 1.0);
}
