// eclipse:world_grade — consolidated night/eclipse screen grade (P2 R3/R16, GRADE priority).
// THE "sky never darkens" fix: there was no darkness treatment at all before — perceived
// night brightness was whatever the user's gamma made of the vanilla lightmap. This pass
// crushes the FINAL image, so it defeats gamma without touching options.
//
// v2 (FX team GRADE): the eclipse as a living pressure. On top of the frozen grade core:
//   [i1] shadow-masked animated film grain (~18 fps reseed) — also the banding mask
//   [i2] radial darkening that breathes with EclipseAmount (double-sine, ~14 s period)
//   [i3] horizon tint band at the TRUE horizon (CPU-projected HorizonY, SunTracker law)
//   [i4] split-tone color depth (cool shadows / faintly warm highlights, crush-scaled)
//   [i5] ±0.5/255 output dither (always on — kills crush-gradient quantization banding)
//   [i6] sky seethe — ultra-low-frequency ±2% drift on sky pixels during the eclipse
//
// v3 (VEIL-REPASS-1): the night gains a color SCRIPT and local depth.
//   [r1] eclipse-phase / dawn-dusk color script — PhaseTint (signed −1..1) leans the
//        violet story: dusk & eclipse BUILDUP sink toward ember-magenta (the light is
//        being taken), dawn & eclipse ENDING relax toward a cool rose (it is being
//        given back). Modulates the desat target and the horizon band — state
//        feedback, static per frame, so it survives reducedFx like the grade core.
//   [r2] micro-contrast "clarity" — a 4-tap luma unsharp term, mid-tone weighted and
//        crush-scaled: the crush stops flattening texture into mud. Static layer.
// Frozen uniforms (§3.3): EclipseAmount, NightAmount, DesatAmount, ExposureMul — fed per
// frame by veilfx.VeilPostController (NightAmount = (1 - dayFactor) * 0.55, eclipse state
// from EclipseFxState). Active only while NightAmount > 0.01 || EclipseAmount > 0.01.
// v2 additive uniforms (fed by the same feeder, same commit — limbo-v3 precedent):
//   Time     — seconds, hourly wrap (limbo clock pattern); grain/breath/seethe clock
//   HorizonY — NDC y of the world horizon along the camera yaw (±10 park when behind
//              the camera / no frame captured — the band gaussian dies to zero there)
//   Detail   — 1 normal, 0 under reducedFx: gates grain, breathing amplitude and seethe
//              (the static grade core is readability-critical and never gated)
// v3 additive uniform (fed by the same feeder, same commit — the additive rule):
//   PhaseTint — signed color-script lean in [−1, 1]: −1 = full dusk/BUILDUP lean,
//               +1 = full dawn/ENDING lean, 0 = neutral deep night. Sun-elevation
//               edge (overworld) + eased eclipse-phase lean, combined CPU-side.
// v4 additive uniforms (F-077 V2 End-arrival — same feeder, same commit):
//   ArrivalDim   — 0..1 beat-1 omen dim: vignette-weighted exposure pull + gentle
//                  desat while the altar drains the world (EclipseFxState.arrivalDim,
//                  driven by the end_arrival_grade cue). 0 = bit-identical frame.
//   EndTintPulse — 0..1 beat-4 reveal pulse: sky-weighted end-violet wash as the rift
//                  implodes and the End disc is unveiled (end_arrival_tint cue).
// v5 additive uniforms (FX-12 nether-opening "Glutgrad" — same feeder, same commit):
//   HeatTint     — 0..1 ember-red lean: multiplicative red-shift + a slight highlight
//                  lift while the breach tears open (EclipseFxState.netherHeat, driven
//                  client-side by NetherOpenClientFx). 0 = bit-identical frame.
//   HeatShimmer  — 0..1 heat haze: a small UV wobble on sky/far pixels only (the [i6]
//                  seethe idiom on a faster clock), Detail-gated like every motion layer.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float EclipseAmount;
uniform float NightAmount;
uniform float DesatAmount;
uniform float ExposureMul;
uniform float Time;
uniform float HorizonY;
uniform float Detail;
uniform float PhaseTint;
uniform float ArrivalDim;
uniform float EndTintPulse;
uniform float HeatTint;
uniform float HeatShimmer;

in vec2 texCoord;

out vec4 fragColor;

// Breathing frequencies (rad/s): incommensurate pair so the inhale never metronomes.
const float BREATH_W1 = 0.44;
const float BREATH_W2 = 0.31;

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    vec2 texSize = vec2(textureSize(DiffuseSampler0, 0));
    vec2 screenPx = texCoord * texSize;
    // 0.55 cap keeps a full eclipse readable (dark violet dusk, not black) — the
    // cinematic flight and the approach walk both happen at EclipseAmount == 1.
    float crush = max(NightAmount, EclipseAmount * 0.55);

    // [r2] Clarity pre-pass: sample the 4 diagonal neighbors (~1.2 px) of the RAW frame
    // and keep the luma difference. The unsharp gain is applied AFTER the crush (below)
    // so the recovered texture rides the curve the player actually sees.
    vec2 texel = 1.2 / texSize;
    float rawLuma = dot(color, vec3(0.299, 0.587, 0.114));
    float hoodLuma = dot(
            texture(DiffuseSampler0, texCoord + texel).rgb
            + texture(DiffuseSampler0, texCoord - texel).rgb
            + texture(DiffuseSampler0, texCoord + vec2(texel.x, -texel.y)).rgb
            + texture(DiffuseSampler0, texCoord + vec2(-texel.x, texel.y)).rgb,
            vec3(0.299, 0.587, 0.114)) * 0.25;
    float clar = rawLuma - hoodLuma;

    // Shadow-crushing tone curve (robust against user gamma — operates on the final frame).
    color = efxCrush(color, crush);

    // [r2] Micro-contrast "clarity": luma-only (no chroma fringes), mid-tone weighted so
    // crushed shadows stay velvety and highlights never halo, clamped so a hard edge can
    // only swing ~±5%. Rides the crush: plain day is bit-identical. Static — survives
    // reducedFx (readability-positive, nothing pulses).
    float midW = smoothstep(0.05, 0.20, rawLuma) * (1.0 - smoothstep(0.55, 0.85, rawLuma));
    color *= 1.0 + clamp(clar, -0.06, 0.06) * 0.9 * crush * midW;

    // [r1] Color-script leans (mutually exclusive by construction: PhaseTint is signed).
    float dusk = max(-PhaseTint, 0.0);
    float dawn = max(PhaseTint, 0.0);

    // Desaturate toward violet as the eclipse deepens. v3: the violet target itself is
    // scripted — dusk/BUILDUP sinks it toward ember-magenta, dawn/ENDING relaxes it toward
    // a cool rose. Same luma either way (the tint is hue-only, the crush owns brightness):
    // all three targets sit at Rec.601 luma 0.734–0.736, so the script can never fight the
    // tuned totality mid-gray — polish 2 renormalized the leans (dawn was ~6% hot).
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 violetTint = vec3(0.82, 0.62, 1.10);
    violetTint = mix(violetTint, vec3(0.98, 0.58, 0.90), dusk * 0.40);
    violetTint = mix(violetTint, vec3(0.84, 0.64, 0.95), dawn * 0.50);
    vec3 violet = luma * violetTint;
    color = mix(color, mix(vec3(luma), violet, 0.7), clamp(DesatAmount, 0.0, 1.0));

    // [i4] Split-tone depth: shadows cool violet-blue, highlights faintly warm rose.
    // Multiplicative — never lifts blacks or clips whites, so the tuned totality
    // mid-gray (0.196) is untouched. The warm highlight eases off with EclipseAmount:
    // at totality the violet story owns the frame; on plain nights torchlight keeps
    // its warmth (that contrast IS the point of the layer).
    float tone = smoothstep(0.18, 0.62, luma);
    vec3 shadowTint = vec3(0.94, 0.93, 1.05);
    vec3 highlightTint = mix(vec3(1.03, 1.00, 0.97), vec3(1.0), EclipseAmount);
    color *= mix(vec3(1.0), mix(shadowTint, highlightTint, tone), crush * 0.7);

    // Sky-region extra dim: pixels at the far plane are pure sky — pull them down further
    // so the dome reads dark even where fog/sky colors fight the grade.
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    float sky = step(0.9999, depth);
    color *= 1.0 - sky * crush * 0.25;

    // [i3] Horizon tint band: a dusky magenta-violet dusk band hugging the TRUE horizon
    // (HorizonY = CPU projection of a camera-height point 4 km along the horizontal
    // forward, through the exact frame matrices — tracks pitch and view bobbing). The
    // band spills 35% onto far geometry so it melts over terrain silhouettes instead of
    // drawing a sticker line above them. Additive but tiny (≤ ~0.055 pre-exposure).
    float far = smoothstep(0.998, 0.9999, depth);
    float bandMask = max(sky, far * 0.35);
    float ndcY = texCoord.y * 2.0 - 1.0;
    // exp(-h·h), NOT pow(base, 2.0): pow is undefined for negative bases in GLSL and the
    // band argument is signed (pixels below the horizon line).
    float bandH = (ndcY - HorizonY) / 0.16;
    float band = exp(-bandH * bandH);
    float bandAmt = band * bandMask * max(NightAmount * 0.45, EclipseAmount);
    // [r1] The band follows the color script: ember at dusk/BUILDUP, rose at dawn/ENDING.
    vec3 bandColor = vec3(0.26, 0.09, 0.36);
    bandColor = mix(bandColor, vec3(0.40, 0.11, 0.24), dusk * 0.55);
    bandColor = mix(bandColor, vec3(0.30, 0.14, 0.40), dawn * 0.55);
    color += bandColor * bandAmt * 0.21;

    // [i2] Radial darkening breathing with EclipseAmount. Static part rides the crush
    // (plain night gets gentle ~4% edge pressure); the slow double-sine inhale rides
    // EclipseAmount * Detail. Totality corners swing ~7→11% — pressure, not blindness
    // (coefficients sized against the ACTUAL corner distance d ≈ 0.707, where the
    // 0.38..0.92 smoothstep reaches ~0.65 — not against its offscreen saturation point).
    float d = distance(texCoord, vec2(0.5));
    float breath = 0.5 + 0.35 * sin(Time * BREATH_W1) + 0.15 * sin(Time * BREATH_W2 + 1.3);
    float vig = 0.12 * crush + (0.035 + 0.075 * breath * Detail) * EclipseAmount;
    color *= 1.0 - smoothstep(0.38, 0.92, d) * vig;

    // [i6] Sky seethe: one low-frequency noise octave drifting over sky pixels only,
    // ±2% luminance at full eclipse — the dome itself seems to move. Gated by Detail.
    float seethe = efxNoise(texCoord * vec2(6.0, 3.5) + vec2(Time * 0.025, -Time * 0.017));
    color *= 1.0 + (seethe - 0.5) * 0.04 * sky * EclipseAmount * Detail;

    // [v4] F-077 beat-1 omen dim: a vignette-weighted exposure pull (the world "loses
    // light" toward the edges first) plus a gentle desat — the altar is drinking the
    // color out of the day. Static per frame; zero uniform = bit-identical frame.
    if (ArrivalDim > 0.001) {
        float dimEdge = smoothstep(0.25, 0.85, d);
        // V2.1 QA: 0.16/0.30/0.35 read as invisible on camera — the omen must be FELT.
        color *= 1.0 - ArrivalDim * (0.24 + 0.42 * dimEdge);
        float dimLuma = dot(color, vec3(0.299, 0.587, 0.114));
        color = mix(color, vec3(dimLuma), ArrivalDim * 0.5);
    }

    // [v4] F-077 beat-4 reveal pulse: a hue-only end-violet lean plus a sky-weighted
    // violet wash — the dome flashes end-purple as the rift snaps shut, then decays.
    if (EndTintPulse > 0.001) {
        float pulseLuma = dot(color, vec3(0.299, 0.587, 0.114));
        color = mix(color, pulseLuma * vec3(0.86, 0.70, 1.12), EndTintPulse * 0.25);
        color += vec3(0.24, 0.10, 0.36) * sky * EndTintPulse * 0.14;
    }

    // [v5] FX-12 "Glutgrad": the day-2 breach heats the whole frame. A multiplicative
    // ember lean (hue-only at first order — the crush still owns brightness) plus a
    // small warm lift that only the highlights receive, so the ground reads as lit by
    // something below the horizon. Static per frame; zero uniform = bit-identical frame.
    if (HeatTint > 0.001) {
        float heatLuma = dot(color, vec3(0.299, 0.587, 0.114));
        color = mix(color, color * vec3(1.20, 0.84, 0.68), HeatTint * 0.65);
        color += vec3(0.075, 0.026, 0.008) * HeatTint * smoothstep(0.30, 0.85, heatLuma);
    }

    // [v5] FX-12 heat shimmer: one low-frequency noise octave on a fast clock displaces
    // the SKY/far pixels (bandMask, the [i3] horizon-band weighting) by a few
    // thousandths of a screen. Applied as the DELTA between the wobbled and the
    // un-wobbled RAW sample so displaced pixels still ride the graded curve instead of
    // punching un-crushed source color through it. Gated by Detail like [i1]/[i2]/[i6].
    if (HeatShimmer > 0.001) {
        float haze = HeatShimmer * Detail * bandMask;
        float wob = efxNoise(texCoord * vec2(7.0, 15.0)
                + vec2(Time * 0.13, -Time * 0.47)) - 0.5;
        vec2 warp = vec2(wob * 0.0040, abs(wob) * 0.0026) * haze;
        vec3 wobbled = texture(DiffuseSampler0, texCoord + warp).rgb;
        color += clamp(wobbled - texture(DiffuseSampler0, texCoord).rgb, -0.25, 0.25) * haze * 0.8;
    }

    // Exposure dip (0.62 during eclipse TOTAL, eased CPU-side over 60 ticks — the old
    // 0.35 target rendered totality near-black on top of the crush; see EclipseFxState).
    color *= ExposureMul;

    // [i1] Film grain AFTER the exposure mul so it survives (and masks banding in) the
    // darkest totality frames. Reseeded at ~18 fps (film cadence, not per-frame static);
    // the clock is wrapped before hashing so hour-wrap precision loss can't pattern it.
    // Luma knee: strongest in crushed shadows, whisper in mid-tones, clean highlights.
    float grainClock = mod(floor(Time * 18.0), 289.0);
    float grain = efxHash(screenPx * 0.37 + vec2(grainClock * 17.13, grainClock * 7.77));
    float postLuma = dot(color, vec3(0.299, 0.587, 0.114));
    float shadowMask = 1.0 - smoothstep(0.0, 0.45, postLuma);
    color += (grain - 0.5) * 0.028 * crush * shadowMask * Detail;

    // [i5] Output dither: ±0.5/255, always on (reducedFx included) — the crush gradient
    // quantizes on smooth skies without it. Slow reseed keeps it sub-perceptual.
    color += (efxHash(screenPx + vec2(mod(floor(Time * 4.0), 97.0))) - 0.5) * (1.0 / 255.0);

    fragColor = vec4(color, 1.0);
}
