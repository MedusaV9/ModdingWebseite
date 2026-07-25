// eclipse:glitch_invert — GLITCHZONE effect (TRANSITION priority): the palette flips
// negative and cannot hold itself together. The full-strength read is an inverted frame
// whose hue keeps ROTATING in unstable quantized snaps (a drifting wander that locks to
// ~22.5° detents and occasionally pops a whole detent), posterized down to a handful of
// levels, with brief gated inversion "drops" where the negative collapses back toward
// positive for a re-roll — film slipping in the gate. Fed by client.GlitchZoneFx:
// Strength (0..1 ramp — no-op at 0), Time (wall-clock seconds), Detail (0 under reduced
// FX: hue wander freezes at a fixed angle and the drops stop; the static negative +
// posterize grade survives).
#include eclipse:eclipse_common
#include eclipse:eclipse_glitch

uniform sampler2D DiffuseSampler0;
uniform float Strength;
uniform float Time;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

const float TAU = 6.28318530718;

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    if (s <= 0.0005) {
        fragColor = vec4(scene, 1.0);
        return;
    }
    float detail = clamp(Detail, 0.0, 1.0);
    float seed = floor(Time * 4.0);

    // --- unstable hue rotation ------------------------------------------------------------
    // A slow noise wander sets the target angle; it locks to 16 detents (22.5° steps) so
    // the hue SNAPS between poses instead of cycling smoothly (glitch verbs: snap, never
    // flow), and every re-roll can pop one extra detent. Frozen at a fixed detent under
    // reduced FX.
    float wander = efxNoise(vec2(Time * 0.35, 3.7)) * 2.0 - 1.0;
    float pop = (step(0.8, efxHash(vec2(seed, 17.9))) * 2.0 - 1.0) * step(0.5, detail);
    float angle = mix(TAU * 0.125, floor((wander * 2.5 + pop) * 16.0) / 16.0 * TAU, detail);

    // --- inversion with gated drops ----------------------------------------------------------
    // invPulse is 1 (full negative) most of the time; ~1 re-roll in 6 dips toward 0.35
    // for one pattern step — the image "almost recovers", then flips back.
    float drop = step(0.84, efxHash(vec2(seed, 41.3))) * detail;
    float invPulse = 1.0 - 0.65 * drop;
    vec3 negative = vec3(1.0) - scene;
    vec3 color = mix(scene, negative, s * invPulse);
    color = gzHueRotate(color, angle * s);

    // --- posterization steps -------------------------------------------------------------------
    // Levels collapse with Strength (deep in the zone ~5 per channel). The banding is the
    // point here, so no dither on this layer — the steps must read as steps.
    float levels = mix(48.0, 5.0, s);
    color = mix(color, gzPosterize(color, levels), s);

    // --- seam shimmer ---------------------------------------------------------------------------
    // Faint violet glow where posterize bands meet: both taps quantize the SCENE luma
    // (same domain), so the term fires exactly on band boundaries — the negative looks
    // etched into levels, not just recoloured.
    vec2 texel = 1.0 / vec2(textureSize(DiffuseSampler0, 0));
    float qC = floor(gzLuma(scene) * levels + 0.5) / max(levels, 1.0);
    float qN = floor(gzLuma(texture(DiffuseSampler0, clamp(texCoord + vec2(0.0, texel.y * 1.5), vec2(0.001), vec2(0.999))).rgb) * levels + 0.5) / max(levels, 1.0);
    color += vec3(0.35, 0.10, 0.45) * smoothstep(0.02, 0.15, abs(qC - qN)) * 0.25 * s;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
