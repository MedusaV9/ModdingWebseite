// eclipse:altar_aura_grade — the sanctum island's high-stage shimmer (F-075, GRADE
// priority — evicted FIRST when the ≤3-pass budget fills: this garnish only runs
// "wenn frei"; the Photon aura loops are the baseline read and never depend on it).
// client/drama/AltarAuraGrade computes the zone strength each tick — stage factor
// ((level − 2) / 3 for levels 3..5, zero below) × proximity curve (1 − d/72)² against
// the eclipse:altar_center anchor — eases it over ~20 ticks and feeds the frozen Aura
// uniform per frame with a 0.15 Hz breath premultiplied (flattened under reducedFx)
// plus the F-075 V2 stage-up pulse headroom (clamped at 1).
//
// Layers (all deliberately faint — "die Luft über der Insel ist nicht normal", the
// island must glow, not the screen):
//   [g1] rising heat-shimmer — a slow upward-drifting noise field bends the sampling
//        UV by ≤ ~0.9 px: near the altar the air visibly wavers like above a candle.
//        Animated ⇒ gated by Detail (reducedFx flattens it away).
//   [g2] highlight bloom lift — luma-weighted lift on bright pixels: the altar's
//        emissives, the aura motes and the light bands bloom softly. F-075 V2: the
//        lift colour walks the stage ladder — violet at L3, gold-white at L5 (Gold).
//   [g3] midtone consecration tint — a whisper of warm violet in the midtones, riding
//        the same eased response so it fades in with the shimmer; the tint target
//        also warms toward gold with the stage ladder.
//   [g4] boundary ripple (F-075 V2) — a narrow horizontal refraction wobble
//        (≤ ~1.4 px) + a ~0.3 px chroma split, driven by the Edge band the feeder
//        computes around the d ≈ 24 aura shell: crossing ONTO the island reads as one
//        soft "surface tension" moment, gone once inside. Animated ⇒ Detail-gated.
// Output dither guards the long smooth gradients ([g2]/[g3]) against banding.
//
// Uniforms (fed by client/drama/AltarAuraGrade, same commit — additive-uniform rule):
//   Aura   — 0..1 eased zone×stage strength, breath + stage-up pulse pre-summed CPU-side
//   Edge   — 0..1 eased boundary-band strength (Gaussian at the 24-block shell)
//   Gold   — 0..1 eased stage colour ladder (0.15 / 0.5 / 1.0 at L3/L4/L5)
//   Time   — seconds on the feeder's 100 s wrap clock
//   Detail — 1 normal, 0 under reducedFx (gates the animated [g1]/[g4] layers)
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Aura;
uniform float Edge;
uniform float Gold;
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

    // [g4] Boundary ripple: two slow counter-drifting horizontal waves bend the
    // sampling UV sideways by ≤ ~1.4 px only while the camera sits in the Edge band —
    // the "surface tension" of stepping through the aura shell. Detail-gated like [g1].
    float edge = clamp(Edge, 0.0, 1.0) * Detail;
    if (edge > 0.001) {
        float band = sin(texCoord.y * 90.0 + Time * 9.0) * 0.6
                + sin(texCoord.y * 47.0 - Time * 6.3) * 0.4;
        uv.x += band * (1.4 / max(screenSize.x, 1.0)) * edge;
    }

    vec3 color = texture(DiffuseSampler0, uv).rgb;

    // [g4] chroma split: a whisper of dispersion (~0.3 px) riding the same band, so
    // the crossing moment refracts like a soap film instead of just wobbling.
    if (edge > 0.001) {
        vec2 split = vec2(0.3 / max(screenSize.x, 1.0), 0.0) * edge;
        color.r = texture(DiffuseSampler0, uv + split).r;
        color.b = texture(DiffuseSampler0, uv - split).b;
    }

    float luma = dot(color, vec3(0.299, 0.587, 0.114));

    // [g2] Highlight bloom lift: bright pixels (the model's glowmask, aura bands,
    // lightfall) get a soft halo push — smoothstepped so shadows and midtones stay
    // untouched. ≤ +12% at full aura on pure highlights. The lift colour follows the
    // stage ladder: violet (L3) → gold-white (L5).
    float glow = smoothstep(0.55, 0.95, luma);
    vec3 liftColor = mix(vec3(0.75, 0.55, 1.0), vec3(1.0, 0.9, 0.62), clamp(Gold, 0.0, 1.0));
    color += color * liftColor * glow * a * 0.12;

    // [g3] Midtone consecration tint: a faint pull in the midtones. The parabolic
    // midtone mask (4·l·(1−l)) leaves black and white alone, so the grade reads as
    // "the light here is different", not as a screen filter. The tint target warms
    // from cool violet toward candle-gold with the stage ladder.
    float mid = 4.0 * luma * (1.0 - luma);
    vec3 tintTarget = mix(vec3(1.02, 0.94, 1.10), vec3(1.06, 1.00, 0.92), clamp(Gold, 0.0, 1.0));
    vec3 tinted = mix(color, vec3(luma) * tintTarget, 0.22);
    color = mix(color, tinted, mid * a * 0.35);

    // Banding guard for the lifted gradients (slow reseed keeps the dither invisible).
    color += efxDither(gl_FragCoord.xy, fract(floor(Time * 4.0) / 89.0));

    fragColor = vec4(color, 1.0);
}
