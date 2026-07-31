// eclipse:end_static — FX-Wave-13 N10 "End-Statik" (census §6 row N10, FEATURE priority).
//
// THE BEAT: the End disc hangs in the overworld sky and the rift over it never fully healed.
// Get close and the IMAGE starts to fail — a fine chromatic split tears through the frame in
// crackling bursts, and the void behind the world bleeds through wherever the picture is
// dark enough to let it. It is the rift telling you that the screen is the thin part.
//
// CONSTRUCTION (screen-space, zero textures — the eclipse_common law):
//   [1] Crackle envelope. "Knistern" is not a pulse: Time is quantized into
//       CRACKLE_RATE slots per second, each slot hashes to its OWN amplitude, and only the
//       slots above CRACKLE_DUTY fire at all. Inside a firing slot the burst decays
//       exponentially — a click, not a square wave. Neighbouring slots are decorrelated, so
//       there is no rhythm to lock onto and the signal reads as interference.
//   [2] Chromatic aberration. Radial split from the frame centre (the lens direction), so
//       the middle of the screen stays readable and the corners tear. The amount is
//       modulated by a horizontal BAND noise re-rolled once per crackle slot: the split is
//       never uniform down the frame, which is what separates "a broken signal" from "a
//       lens filter". Capped at ABERRATION_MAX (≈3 px at 854 wide) — fein, per the mandate.
//   [3] Starfield bleed. Two parallax layers of the shared gzVoidStars lattice along the
//       view ray, anchored to the wrapped camera position so they hold still in the world
//       while the camera moves. They are only ALLOWED to show where the image is dark
//       (`shadow`), which is literally the mandate's "Sternfeld-Bleed in Schattenpartien",
//       and they open up further with distance — near-field mass stays solid, the far dark
//       dissolves into void.
//
// LAWS:
//   * At StaticStrength 0 the input sample is returned untouched (bit-identical frame) and
//     the feeder drops the pass from the manager entirely.
//   * Degenerate depth (a depth attachment that never received its blit reads flat 0.0 — the
//     A0 session-0731 heuristic): every depth-DERIVED term is multiplied by gzDepthValid, so
//     the bleed degrades to the pure luma mask instead of painting garbage. No depth term
//     here feeds a normalize()/cross(), so there is no NaN path to begin with.
//   * Detail 0 (reducedFx) makes the whole shader TIME-INVARIANT: the crackle envelope parks
//     at a steady level, the band re-roll freezes, the grain loses its temporal jitter and
//     the star twinkle stops. The rift still reads as a broken signal; nothing flickers
//     (the BackroomsFlickerOverlay photosensitivity rule).
//
// Uniforms (fed by veilfx.EndStaticFx — Veil's VeilRenderTime does NOT exist in pinwheel
// post shaders, so Time comes from Java like storm_interior/rift_glitch/umbral_veins):
//   StaticStrength — 0..1 eased rift proximity (0 = idle; the whole shader is a no-op there)
//   Time           — pause-frozen seconds, wrapped at 100 s by the feeder. Every rate in
//                    here divides that wrap exactly, so no cycle is ever cut mid-flight:
//                    CRACKLE_RATE 10/s = 1000 slots, and gzVoidStars' 5 s twinkle = 20 cycles.
//   Detail         — 1 normal, 0 under reducedFx (see the law above)
//
// No value-less `return` in main() — see the glsl-processor note in umbral_veins.fsh.
#include eclipse:eclipse_common
#include eclipse:eclipse_glitch
#include veil:space_helper

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float StaticStrength;
uniform float Time;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

/** Burst slots per second. Divides the feeder's 100 s Time wrap exactly (1000 slots). */
const float CRACKLE_RATE = 10.0;
/** Share of slots that fire at all — the rest are the silence between the clicks. */
const float CRACKLE_DUTY = 0.34;
/** Decay of one burst across its slot: e^-3.4 ≈ 0.03, so a click is over well before the next. */
const float CRACKLE_DECAY = 3.4;
/** The envelope never drops to nothing — a dead-quiet frame would read as "effect off". */
const float CRACKLE_FLOOR = 0.28;
/** reducedFx parks the envelope here (between the floor and a typical burst). */
const float CRACKLE_STEADY = 0.60;
/** Peak radial split at the frame corner, in UV units (~3 px at 854 wide). Fein. */
const float ABERRATION_MAX = 0.0035;
/** Tear bands down the frame. Kept ≤ 40 so the hash argument stays fp32-clean (efxDither law). */
const float BAND_FREQ = 34.0;
/**
 * Slot wrap for the per-slot re-rolls, i.e. the period of the crackle pattern itself:
 * 200 slots / 10 per second = it repeats every 20 s, which is far past the point where an
 * ear or an eye can lock onto a loop.
 *
 * Two constraints meet here. It has to DIVIDE the slot count of one Time wrap
 * (100 s × CRACKLE_RATE = 1000 slots; 1000 / 200 = 5 exactly) — a wrap of 32 would land
 * slot 1000 on hash bucket 8 instead of 0 and the whole pattern would jump every 100 s.
 * And it has to stay small enough for efxHash to remain well-conditioned in fp32: the
 * largest argument this feeds is 200 × 311.7 ≈ 62 k, where an fp32 ulp is ~0.008 rad — two
 * orders of magnitude finer than the sin() needs, and well inside what gzHash3 already
 * ships (its mod-32 lattice reaches ~353 k).
 */
const float BAND_SLOT_WRAP = 200.0;
/** Luma window the void is allowed through: fully open below LO, fully closed above HI. */
const float SHADOW_LO = 0.030;
const float SHADOW_HI = 0.300;
/** Parallax layers: sample distance along the ray (blocks) and lattice cell size (blocks). */
const float FAR_DIST = 260.0;
const float FAR_CELL = 16.0;
const float MID_DIST = 72.0;
const float MID_CELL = 8.0;
/** Camera-anchor wrap. 512/16 = 32 and 512/8 = 64 are multiples of GZ_VOID_CELLS (32), so
    the lattice is continuous across the wrap — the glitch_void law. */
const float VOID_WRAP = 512.0;
/** End void star colour: cold white with the dimension's violet lean. */
const vec3 END_STAR = vec3(0.70, 0.66, 0.98);
const float STAR_GAIN = 0.55;
/** Lattice occupancy per layer. Tuned so the far layer reads as a FIELD (a bleed) rather
    than as a handful of pinpricks, while the near layer stays sparse enough to parallax. */
const float FAR_DENSITY = 0.52;
const float MID_DENSITY = 0.30;
/** Peak luminance static. The carrier of the "Knistern"; deliberately under a ±3 LSB nudge. */
const float GRAIN_MAX = 0.026;

/**
 * The crackle envelope in [0,1] — see construction note [1].
 *
 * @param detail 0 parks the envelope at CRACKLE_STEADY (time-invariant: reducedFx sees a
 *               steady broken signal instead of a burst train)
 */
float endCrackle(float time, float detail) {
    float slot = floor(time * CRACKLE_RATE);
    float roll = efxHash(vec2(mod(slot, BAND_SLOT_WRAP), 7.31));
    // Soft gate rather than a step: a slot right at the duty line fires at partial strength,
    // so the train has weak clicks in it instead of only full-power hits.
    float fire = smoothstep(1.0 - CRACKLE_DUTY, 1.0 - CRACKLE_DUTY * 0.35, roll);
    float within = fract(time * CRACKLE_RATE);
    float burst = fire * exp(-within * CRACKLE_DECAY)
            * (0.55 + 0.45 * efxHash(vec2(mod(slot, BAND_SLOT_WRAP), 19.7)));
    return mix(CRACKLE_STEADY, CRACKLE_FLOOR + (1.0 - CRACKLE_FLOOR) * burst, detail);
}

void main() {
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    vec3 color = scene;
    float s = clamp(StaticStrength, 0.0, 1.0);

    if (s > 0.0005) { // else: idle — the scene passes through bit-identical
        float detail = clamp(Detail, 0.0, 1.0);
        float env = endCrackle(Time, detail);
        // Slot index for the per-slot re-rolls, frozen under reducedFx and wrapped small
        // enough to keep every hash argument fp32-well-conditioned.
        float slot = mod(floor(Time * CRACKLE_RATE) * detail, BAND_SLOT_WRAP);

        // --- [2] chromatic aberration ----------------------------------------------------
        vec2 q = texCoord * 2.0 - 1.0;
        float radial = dot(q, q);
        // inversesqrt on a floored length: dead centre (radial 0) would divide by zero and
        // the direction is arbitrary there anyway — the edge weight already kills it.
        vec2 dir = q * inversesqrt(max(radial, 1.0e-6));
        float edge = clamp(radial * 0.5, 0.0, 1.0); // 0 centre, 1 at the corners
        float band = efxNoise(vec2(texCoord.y * BAND_FREQ, slot * 0.37));
        float amount = ABERRATION_MAX * s * env * (0.25 + 0.75 * edge) * (0.45 + 0.90 * band);
        color = efxChroma(DiffuseSampler0, texCoord, dir, amount);

        // --- [3] starfield bleed ---------------------------------------------------------
        float depthSample = texture(DiffuseDepthSampler, texCoord).r;
        float depthOk = gzDepthValid(depthSample);
        float dist = gzLinearDepth(depthSample, VeilCamera.NearPlane, VeilCamera.FarPlane);
        // Where the picture is dark enough to let the void through. Read off the SPLIT
        // colour, not the original, so the mask follows the tear.
        float shadow = 1.0 - smoothstep(SHADOW_LO, SHADOW_HI, gzLuma(color));
        // …and it opens further with distance: near-field mass stays solid, the far dark
        // dissolves. On a dead depth attachment this term is 0 and the luma mask carries
        // the layer alone (A0 hardening).
        float far = smoothstep(24.0, 140.0, dist) * depthOk;
        float openness = shadow * (0.45 + 0.55 * far);

        vec3 ray = viewDirFromUv(texCoord);
        vec3 anchor = mod(VeilCamera.CameraPosition, VOID_WRAP);
        float starFar = gzVoidStars((anchor + ray * FAR_DIST) / FAR_CELL, FAR_DENSITY, Time, detail);
        float starMid = gzVoidStars((anchor + ray * MID_DIST) / MID_CELL, MID_DENSITY, Time, detail);
        float stars = starFar * 0.55 + starMid;
        color += END_STAR * (stars * STAR_GAIN * openness * s * (0.55 + 0.45 * env));

        // --- [1] the carrier -------------------------------------------------------------
        // Fine luminance static over the whole frame. The temporal jitter is detail-gated,
        // so under reducedFx this is a fixed grain pattern rather than a boiling one.
        float grain = efxHash(gl_FragCoord.xy * 0.017 + fract(Time * CRACKLE_RATE) * detail
                * vec2(23.0, 41.0)) - 0.5;
        color += vec3(grain * 2.0 * GRAIN_MAX * s * env);

        // Banding guard: the shadow mask is a long smooth gradient in the dark range, which
        // is exactly where 8-bit output bands.
        color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0) * detail) * s);
    }

    fragColor = vec4(color, 1.0);
}
