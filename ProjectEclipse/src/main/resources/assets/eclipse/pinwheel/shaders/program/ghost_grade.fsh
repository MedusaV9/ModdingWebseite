// eclipse:ghost_grade — spectral screen grade for 0-lives ghost players (P2 R18(c),
// GRADE priority, W10). Recipe core (frozen): 70% desaturation, cold blue-violet lift,
// 12% vignette, 1.5 px chromatic fringe, subtle 0.2 Hz breathing (premultiplied on Ghost
// CPU-side by client.GhostGradeFx).
//
// v2 (FX team GRADE): ghosts see a hauntingly beautiful world. On top of the core:
//   [g1] violet memory-color highlights — hue-selective desat: violet/magenta highlights
//        (the eclipse sun, altar glow, rift light) KEEP their color; everything else
//        drains to spectral gray. The eclipse is the last thing a ghost remembers.
//   [g2] spectral edge shimmer — luma-gradient silhouettes catch a noise-flickered
//        cold violet-white glint, so the world reads as a remembered outline.
//   [g3] heartbeat-adjacent vignette pulse — a slow lub-dub (~32 bpm) rides the
//        vignette: the heart that is no longer quite beating.
//   [g4] void sky — the dome pulls toward a deep violet void (static; composes with
//        world_grade's night dim: a ghost's sky is darker than a living player's).
// Uniforms: Ghost (frozen — the 30-tick eased 0..1 amount from EclipseFxState, breathing
// premultiplied CPU-side; every term scales with it so the grade is a no-op at 0) plus
// the v2 additive set fed by the same GhostGradeFx feeder (same commit):
//   Time   — pause-frozen seconds (the feeder's breath clock / 20, hour wrap)
//   Detail — 1 normal, 0 under reducedFx: gates shimmer + heartbeat (static grade stays)
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float Ghost;
uniform float Time;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

const vec3 LUMA_W = vec3(0.299, 0.587, 0.114);
/** Heartbeat period in seconds (~32 bpm — heartbeat-adjacent, not alive). */
const float BEAT_PERIOD = 1.9;

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    float ghost = clamp(Ghost, 0.0, 1.0);
    if (ghost <= 0.001) {
        fragColor = vec4(color, 1.0);
        return;
    }

    // 1.5 px chromatic fringe, radial from screen center (texel-accurate at any
    // resolution; the epsilon keeps normalize() defined on the exact center pixel).
    vec2 texel = 1.0 / vec2(textureSize(DiffuseSampler0, 0));
    vec2 fromCenter = texCoord - vec2(0.5);
    vec2 chromaDir = normalize(fromCenter + vec2(1.0e-5)) * texel * 1.5;
    vec3 graded = efxChroma(DiffuseSampler0, texCoord, chromaDir, ghost);

    // [g2] Edge field for the shimmer: one-sided luma gradient (2 extra taps).
    float lumaC = dot(graded, LUMA_W);
    float lumaX = dot(texture(DiffuseSampler0, texCoord + vec2(texel.x * 2.0, 0.0)).rgb, LUMA_W);
    float lumaY = dot(texture(DiffuseSampler0, texCoord + vec2(0.0, texel.y * 2.0)).rgb, LUMA_W);
    float edge = clamp(length(vec2(lumaX - lumaC, lumaY - lumaC)) * 6.0, 0.0, 1.0);

    // [g1] Violet memory mask BEFORE the desat: how violet/magenta and how bright this
    // pixel is. Memory pixels resist the gray (up to 85%) and keep a touch of their
    // chroma — the world drains EXCEPT for what the eclipse touched.
    vec3 chroma = graded - vec3(lumaC);
    float violetness = max(0.0, chroma.b * 1.2 + chroma.r * 0.4 - chroma.g * 1.6);
    float memory = clamp(violetness * 5.0, 0.0, 0.85) * smoothstep(0.18, 0.55, lumaC);

    // 70% desaturation, carved back where the memory mask holds.
    graded = mix(graded, vec3(lumaC), 0.70 * ghost * (1.0 - memory));
    // Gentle re-saturation glow on memory pixels so they read deliberate, not missed
    // (clamped: strong violet chroma has a negative green component that could push a
    // channel below zero and poison the multiplicative stages after it).
    graded = max(graded + chroma * memory * 0.35 * ghost, vec3(0.0));

    // Cold blue-violet: a shadow lift (raises blacks without clipping whites)…
    vec3 lift = vec3(0.020, 0.030, 0.075) * ghost;
    graded = graded * (1.0 - lift) + lift;
    // …plus a gentle cool cast over the whole frame.
    graded *= mix(vec3(1.0), vec3(0.86, 0.92, 1.10), ghost);

    // [g4] Void sky: the dome pulls toward a deep violet void — ghosts look up into
    // nothing. Static (survives reducedFx); composes with world_grade's night sky dim
    // deliberately (the ghost's sky IS darker than the living player's).
    float sky = step(0.9999, texture(DiffuseDepthSampler, texCoord).r);
    graded = mix(graded, graded * vec3(0.55, 0.50, 0.80) + vec3(0.010, 0.006, 0.038),
            sky * 0.45 * ghost);

    // [g2] Spectral edge shimmer: silhouettes catch a drifting cold glint, weighted to
    // the DARK side of contrast edges (glow reads as rim light, not as blooming
    // highlights). Noise runs on the pause-frozen clock — still frame on pause screen.
    float shimmer = efxNoise(texCoord * vec2(90.0, 55.0) + vec2(Time * 1.7, -Time * 1.1));
    graded += vec3(0.55, 0.50, 0.85) * edge * (0.35 + 0.40 * shimmer)
            * (1.0 - lumaC * 0.6) * 0.22 * ghost * Detail;

    // [g3] Heartbeat vignette: 12% base (frozen recipe) + a lub-dub pulse. Two gaussian
    // beats per period (squares by multiplication — pow is undefined for negative bases).
    float p = fract(Time / BEAT_PERIOD);
    float b1 = (p - 0.10) * (p - 0.10);
    float b2 = (p - 0.28) * (p - 0.28);
    float beat = exp(-140.0 * b1) + 0.55 * exp(-140.0 * b2);
    float d = distance(texCoord, vec2(0.5));
    graded *= 1.0 - smoothstep(0.30, 0.85, d) * (0.12 + 0.035 * beat * Detail) * ghost;

    // Output dither (±0.5/255): the shadow lift and vignette both create long smooth
    // gradients in the dark range where 8-bit quantization bands; slow reseed keeps the
    // dither itself sub-perceptual (kept under reducedFx — it is a correctness layer).
    vec2 screenPx = texCoord * vec2(textureSize(DiffuseSampler0, 0));
    graded += (efxHash(screenPx + vec2(mod(floor(Time * 4.0), 97.0))) - 0.5) * (1.0 / 255.0);

    fragColor = vec4(graded, 1.0);
}
