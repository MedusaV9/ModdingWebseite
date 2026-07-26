// eclipse:black_hole — F-056 black-hole finale post pass (FEATURE priority; registered
// by client.credits.CreditsBlackHolePostFx, driven by CreditsSkyFx.holeAmount).
// F-068 polish pass: the lensing now RAMPS with the sky intensity ladder, the horizon
// shimmers, an accretion glow with Doppler beaming and infalling star streaks joined.
// Layers, all scaled by Strength so the pass is a no-op at 0:
//   [b1] radial UV pull — every pixel is dragged toward the hole center (gravitational
//        lensing read). F-068: an eased Strength ramp drives it (weak early scene, hard
//        late) plus a near-field 1/r term so the drag visibly steepens toward the hole
//   [b2] swirl — the pulled UVs additionally rotate around the center (the accretion
//        drag), angle falling off with distance so the far frame stays stable; also
//        riding the lensing ramp
//   [b2b] chromatic aberration (F-068, Detail-gated) — the warped sample splits RGB
//        radially, strongest in a band hugging the photon ring (light of different
//        wavelengths bending apart at the rim)
//   [b3] event horizon — pixels inside the core radius drain to pure black with a soft
//        edge; F-068: the core radius SHIMMERS (angular noise breathing ±4%) and the
//        thin warm-violet photon ring rides it with a Doppler-bright approaching limb
//   [b3b] accretion glow (F-068, Doppler) — two soft elliptical glow bands in the
//        display disc's squashed frame (y×0.58), the approaching (screen-right) side
//        beaming brighter — matches CreditsBlackHoleAct's per-fragment Doppler ladder
//   [b3c] star streaks (F-068, Detail-gated) — thin radial dashes on hashed angular
//        buckets flowing INWARD over time (stars being pulled in), windowed between the
//        ring and the mid-frame so the far sky stays calm
//   [b4] desaturation + darkening — "Farben ergrauen": the whole frame drains toward
//        gray then black as Strength climbs (the slow all-black exit is the fade
//        overlay's job; this pass gets ~80% of the way there)
// Uniforms (fed per frame by CreditsBlackHolePostFx, no allocations — UNCHANGED):
//   Strength — eased 0..1 hole amount (CreditsSkyFx; the server's 4-step ladder)
//   Hole     — hole center in UV space (SunTracker.worldToNdc remapped; offscreen-safe)
//   Aspect   — viewport width / height (keeps the swirl/ring circular)
//   Time     — pause-frozen seconds (ring shimmer, streak flow)
//   Detail   — 1 normal, 0 under reducedFx (drops shimmer, ring, streaks, aberration)
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Strength;
uniform vec2 Hole;
uniform float Aspect;
uniform float Time;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

const vec3 LUMA_W = vec3(0.299, 0.587, 0.114);
// Warm-violet finale palette (the ferryman2 law, mirrored from the Photon assets).
const vec3 RING_COLOR = vec3(0.85, 0.62, 1.05);
const vec3 DISC_COLOR = vec3(0.72, 0.52, 0.95);
const vec3 STREAK_COLOR = vec3(0.82, 0.72, 1.0);

void main() {
    float strength = clamp(Strength, 0.0, 1.0);
    if (strength <= 0.001) {
        fragColor = vec4(texture(DiffuseSampler0, texCoord).rgb, 1.0);
        return;
    }

    // Aspect-corrected frame so distances read circular on screen.
    vec2 toHole = (texCoord - Hole) * vec2(Aspect, 1.0);
    float dist = length(toHole);
    vec2 dir = toHole / max(dist, 1.0e-4);
    float ang = atan(toHole.y, toHole.x);

    // F-068 lensing ramp: the eased square keeps the early scene subtle and lets the
    // late intensity steps (0.85 → 1.0) visibly bend the whole frame.
    float lens = strength * strength * (3.0 - 2.0 * strength);

    // [b1] radial pull: smooth far-field falloff + a 1/r near-field term (the drag
    // steepens toward the hole instead of plateauing).
    float pull = smoothstep(0.7, 0.04, dist) * (0.10 + 0.13 * lens)
            + 0.05 * lens / (dist * 6.0 + 0.6);
    // [b2] swirl: rotation angle decays with distance (accretion drag).
    float swirl = smoothstep(0.58, 0.0, dist) * (0.85 + 0.95 * lens);
    float cs = cos(swirl);
    float sn = sin(swirl);
    vec2 swirled = vec2(toHole.x * cs - toHole.y * sn, toHole.x * sn + toHole.y * cs);
    vec2 warpedUv = clamp(Hole + (swirled - dir * pull * dist) / vec2(Aspect, 1.0),
            vec2(0.001), vec2(0.999));

    // F-068 event-horizon geometry first (the aberration band needs the ring radius).
    float core = 0.06 + 0.10 * strength;
    // [b3] shimmer: the horizon breathes ±4% on angular noise (Detail-gated).
    float wobble = (efxNoise(vec2(ang * 2.3 + 7.0, Time * 0.7)) - 0.5) * 0.08 * Detail;
    float coreR = core * (1.0 + wobble);

    // [b2b] chromatic aberration: RGB split along the radial direction, peaking in a
    // band around the photon ring and fading into the far frame (Detail-gated).
    vec2 dirUv = dir / vec2(Aspect, 1.0);
    float ringBand = smoothstep(coreR * 4.5, coreR * 1.6, dist)
            * smoothstep(coreR * 0.8, coreR * 1.4, dist);
    float caAmt = (0.0012 + 0.0035 * (0.35 + 0.65 * ringBand)) * lens * Detail;
    vec3 color = efxChroma(DiffuseSampler0, warpedUv, dirUv, caAmt);

    // [b4] desaturate + darken: the world grays out, then dims (never fully black here —
    // the sustained fade owns the final exit; the floor keeps the ring readable).
    float luma = dot(color, LUMA_W);
    color = mix(color, vec3(luma), 0.85 * strength);
    color *= 1.0 - 0.55 * strength;

    // [b3] event horizon: core drains to black with the shimmering edge.
    float horizon = smoothstep(coreR * 1.6, coreR * 0.7, dist);
    color = mix(color, vec3(0.0), horizon * strength);

    // Doppler beaming factor: the approaching (screen-right) limb burns brighter —
    // mirrors the display act's per-fragment brightness ladder (cos(theta) law).
    float doppler = 1.0 + 0.55 * (toHole.x / max(dist, 1.0e-4));

    // [b3] photon ring: thin, hot, shimmering, Doppler-beamed (Detail-gated).
    float ringShimmer = 0.75 + 0.25 * efxNoise(vec2(ang * 3.0, Time * 0.6));
    float ring = smoothstep(coreR * 2.2, coreR * 1.55, dist)
            * (1.0 - smoothstep(coreR * 1.55, coreR * 1.0, dist));
    color += RING_COLOR * ring * ringShimmer * doppler * 0.6 * strength * Detail;

    // [b3b] accretion glow: two soft elliptical bands in the display disc's squashed
    // frame (matches the act's 0.55 up-scale), Doppler-beamed, gently shimmering.
    vec2 discP = vec2(toHole.x, toHole.y * 1.72);
    float dDisc = length(discP);
    float band1 = smoothstep(coreR * 3.4, coreR * 2.4, dDisc)
            * (1.0 - smoothstep(coreR * 2.4, coreR * 1.5, dDisc));
    float band2 = smoothstep(coreR * 5.6, coreR * 4.0, dDisc)
            * (1.0 - smoothstep(coreR * 4.0, coreR * 2.8, dDisc));
    float discShimmer = 0.8 + 0.2 * efxNoise(vec2(ang * 4.0 - Time * 0.35, dDisc * 9.0));
    color += DISC_COLOR * (band1 * 0.28 + band2 * 0.13) * doppler * discShimmer * strength;

    // [b3c] star streaks: hashed angular buckets carry thin dashes flowing INWARD
    // (phase dist*k + Time — constant-phase points move to smaller dist over time).
    if (Detail > 0.5) {
        float buckets = 48.0;
        float bucketF = (ang / 3.14159265 + 1.0) * 0.5 * buckets;
        float bucket = floor(bucketF);
        float on = step(0.80, efxHash(vec2(bucket, 7.3)));
        float line = smoothstep(0.5, 0.08, abs(fract(bucketF) - 0.5));
        float flowSpeed = 0.22 + 0.18 * efxHash(vec2(bucket, 3.1));
        float head = fract(dist * 1.7 + Time * flowSpeed + efxHash(vec2(bucket, 11.7)));
        float dash = smoothstep(0.0, 0.22, head) * (1.0 - smoothstep(0.4, 0.62, head));
        float radialWin = smoothstep(coreR * 2.0, coreR * 3.5, dist)
                * (1.0 - smoothstep(0.38, 0.7, dist));
        color += STREAK_COLOR * on * line * dash * radialWin * 0.33 * lens;
    }

    // Output dither: the desaturated dark range bands at 8 bits otherwise.
    vec2 screenPx = texCoord * vec2(textureSize(DiffuseSampler0, 0));
    color += (efxHash(screenPx + vec2(mod(floor(Time * 4.0), 97.0))) - 0.5) * (1.0 / 255.0);

    fragColor = vec4(color, 1.0);
}
