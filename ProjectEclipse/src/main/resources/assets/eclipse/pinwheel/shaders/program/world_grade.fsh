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
// Frozen uniforms (§3.3): EclipseAmount, NightAmount, DesatAmount, ExposureMul — fed per
// frame by veilfx.VeilPostController (NightAmount = (1 - dayFactor) * 0.55, eclipse state
// from EclipseFxState). Active only while NightAmount > 0.01 || EclipseAmount > 0.01.
// v2 additive uniforms (fed by the same feeder, same commit — limbo-v3 precedent):
//   Time     — seconds, hourly wrap (limbo clock pattern); grain/breath/seethe clock
//   HorizonY — NDC y of the world horizon along the camera yaw (±10 park when behind
//              the camera / no frame captured — the band gaussian dies to zero there)
//   Detail   — 1 normal, 0 under reducedFx: gates grain, breathing amplitude and seethe
//              (the static grade core is readability-critical and never gated)
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

in vec2 texCoord;

out vec4 fragColor;

// Breathing frequencies (rad/s): incommensurate pair so the inhale never metronomes.
const float BREATH_W1 = 0.44;
const float BREATH_W2 = 0.31;

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    vec2 screenPx = texCoord * vec2(textureSize(DiffuseSampler0, 0));
    // 0.55 cap keeps a full eclipse readable (dark violet dusk, not black) — the
    // cinematic flight and the approach walk both happen at EclipseAmount == 1.
    float crush = max(NightAmount, EclipseAmount * 0.55);

    // Shadow-crushing tone curve (robust against user gamma — operates on the final frame).
    color = efxCrush(color, crush);

    // Desaturate toward violet as the eclipse deepens.
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 violet = luma * vec3(0.82, 0.62, 1.10);
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
    color += vec3(0.26, 0.09, 0.36) * bandAmt * 0.21;

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
