// eclipse:altar_aura_grade — the sanctum island's high-stage shimmer (F-075, GRADE
// priority — evicted FIRST when the ≤3-pass budget fills: this garnish only runs
// "wenn frei"; the Photon aura loops are the baseline read and never depend on it).
// client/drama/AltarAuraGrade computes the zone strength each tick — stage factor
// ((level − 2) / 3 for levels 3..5, zero below) × proximity curve (1 − d/72)² against
// the eclipse:altar_center anchor — eases it over ~20 ticks and feeds the frozen Aura
// uniform per frame with a 0.15 Hz breath premultiplied (flattened under reducedFx).
//
// Layers (all deliberately faint — "die Luft über der Insel ist nicht normal", the
// island must glow, not the screen):
//   [g1] rising heat-shimmer — a slow upward-drifting noise field bends the sampling
//        UV by ≤ ~0.9 px: near the altar the air visibly wavers like above a candle.
//        Animated ⇒ gated by Detail (reducedFx flattens it away).
//   [g2] highlight bloom lift — luma-weighted violet-gold lift on bright pixels: the
//        altar's emissives, the aura motes and the light bands bloom softly.
//   [g3] midtone consecration tint — a whisper of warm violet in the midtones, riding
//        the same eased response so it fades in with the shimmer.
// Output dither guards the long smooth gradients ([g2]/[g3]) against banding.
//
// Uniforms (fed by client/drama/AltarAuraGrade, same commit — additive-uniform rule):
//   Aura   — 0..1 eased zone×stage strength, breath premultiplied CPU-side
//   Time   — seconds on the feeder's 100 s wrap clock
//   Detail — 1 normal, 0 under reducedFx (gates the animated shimmer layer)
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Aura;
uniform float Time;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    float a = clamp(Aura, 0.0, 1.0);
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));

    // [g1] Rising heat-shimmer: two octaves of value noise drifting upward at ~0.06
    // UV/s. Displacement peaks at ~0.9 px (aspect-corrected) at full aura — enough to
    // waver torch flames and the altar silhouette, never enough to smear text.
    vec2 uv = texCoord;
    float shimmer = a * Detail;
    if (shimmer > 0.001) {
        vec2 flow = vec2(0.0, Time * 0.06);
        float nx = efxNoise(texCoord * vec2(26.0, 14.0) + flow * vec2(9.0, 22.0)) - 0.5;
        float ny = efxNoise(texCoord * vec2(22.0, 12.0) + flow * vec2(9.0, 22.0) + vec2(7.31, 3.77)) - 0.5;
        uv += vec2(nx, ny) * (0.9 / max(screenSize.y, 1.0)) * shimmer;
    }

    vec3 color = texture(DiffuseSampler0, uv).rgb;
    float luma = dot(color, vec3(0.299, 0.587, 0.114));

    // [g2] Highlight bloom lift: bright pixels (the model's glowmask, aura bands,
    // lightfall) get a soft violet-gold halo push — smoothstepped so shadows and
    // midtones stay untouched. ≤ +12% at full aura on pure highlights.
    float glow = smoothstep(0.55, 0.95, luma);
    color += color * vec3(0.75, 0.55, 1.0) * glow * a * 0.12;

    // [g3] Midtone consecration tint: a faint warm-violet pull in the midtones. The
    // parabolic midtone mask (4·l·(1−l)) leaves black and white alone, so the grade
    // reads as "the light here is different", not as a screen filter.
    float mid = 4.0 * luma * (1.0 - luma);
    vec3 tinted = mix(color, vec3(luma) * vec3(1.02, 0.94, 1.10), 0.22);
    color = mix(color, tinted, mid * a * 0.35);

    // Banding guard for the lifted gradients (slow reseed keeps the dither invisible).
    color += efxDither(gl_FragCoord.xy, fract(floor(Time * 4.0) / 89.0));

    fragColor = vec4(color, 1.0);
}
