// eclipse:resonance_shimmer — WOAH-04 §4.6: the struck-crystal air shimmer.
// A subtle radial chromatic offset (≤ 2 px at ShimmerAmount = 1) that blooms for a
// beat when a crystal is struck close by (peak 0.35, 12 t decay) or the finale fires
// (peak 0.6, 40 t) — "the air itself rings". Registered by woah.resonance.client
// .ResonanceFieldFx as a FEATURE-priority VeilPostController.PipelineSpec; the
// controller owns the Iris gate, the veilPostFx toggle and the ≤3-pass budget, and
// the activation predicate is simply envelope > 0 (reducedFx ⇒ false).
//
// Template lineage: altar_aberration.fsh (the shipped chromatic-split post), reduced
// to its cheapest form — 3 taps total, no rings/ghosting/sparkle. The split gets a
// faint 6.5 Hz tremble on top (a sounding tuning fork, not a static lens): amplitude
// ±20% of the split, so it disappears together with the envelope.
//
// Uniforms (fed per-frame by ResonanceFieldFx.feedShimmer, primitives only):
//   ShimmerAmount — 0..~0.6 envelope (tick-domain linear decay)
//   Time          — seconds on a 100 s wrap clock
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float ShimmerAmount;
uniform float Time;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    float a = clamp(ShimmerAmount, 0.0, 1.0);
    vec2 center = vec2(0.5);
    vec2 delta = texCoord - center;

    // The ring tremble: ±20% split modulation at ~6.5 Hz — reads as vibration, and
    // decays to nothing with the envelope itself.
    float tremble = 1.0 + 0.2 * sin(Time * 40.84);

    // Radial RGB split away from the screen center: 0.003 · a ≈ 2 px at the edge of a
    // 1080p frame for the finale peak (a = 0.6 ⇒ ~1.2 px) — plan cap ≤ 2 px.
    float split = 0.003 * a * tremble;
    vec3 color;
    color.r = texture(DiffuseSampler0, texCoord + delta * split).r;
    color.g = texture(DiffuseSampler0, texCoord).g;
    color.b = texture(DiffuseSampler0, texCoord - delta * split).b;

    // A whisper of cool lift so the shimmer beat also reads on still frames.
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(color, vec3(luma) * vec3(0.94, 0.97, 1.06), a * 0.12);

    // Output dither (±0.5/255) against banding on the lift gradient.
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
    color += (efxHash(texCoord * screenSize + vec2(mod(floor(Time * 4.0), 89.0))) - 0.5) * (1.0 / 255.0);

    fragColor = vec4(color, 1.0);
}
