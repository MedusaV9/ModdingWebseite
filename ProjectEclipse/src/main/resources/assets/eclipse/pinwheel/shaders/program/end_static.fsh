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
// F-102 GLITCH-FAMILY POLISH "WEISSRAUSCH-HORROR" — the pass crackled but never FAILED. Two
// escalations turn interference into signal death:
//   [4] STATIC VEIL. Coarse-cell white noise (2-physical-pixel cells, not per-texel powder)
//       MIXES over the image; the share rises with StaticStrength squared and rides the
//       crackle envelope, so far from the rift it is a faint film and close in every crackle
//       burst visibly washes the world in snow.
//   [5] SIGNAL-LOSS BEATS. A second, much slower slot train (4 s slots, ~1 in 3.5 fires,
//       25 slots per 100 s wrap — exact) drives a collapse envelope with a fast attack and
//       a ~1.5 s decay: the picture drops toward dark desaturated mush, the veil jumps
//       toward full snow, the frame slips vertically and rows tear sideways — one long
//       "the feed just died" moment, then it recovers. Under reduced FX ([law] above) the
//       beat train is HARD ZERO (a photosensitivity rule, the BackroomsFlickerOverlay law)
//       and the veil parks time-invariant at its floor.
//   [6] INTERFERENCE BANDS. Slow horizontal luma waves (7 bands, one crawl per ~2.9 s,
//       35 whole periods per wrap) between beats — the broadcast is never quite healthy.
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
/** [5] Signal-loss beats: slot rate (4 s slots; 100 s x 0.25 = 25 slots per wrap, exact),
    share of slots that fire, and the slot wrap for the per-slot hash re-rolls. */
const float BEAT_RATE = 0.25;
const float BEAT_DUTY = 0.28;
const float BEAT_WRAP = 25.0;
/** [4] Static veil: white-noise cell size in physical pixels, the mix floor that rides the
    crackle envelope, and the extra mix a signal-loss beat adds on top. */
const float VEIL_CELL = 2.0;
const float VEIL_BASE = 0.16;
const float VEIL_BEAT = 0.55;
/** [5] Collapse depths at beat peak: vertical frame slip (UV), row tear (UV), luma crush. */
const float SLIP_MAX = 0.05;
const float TEAR_MAX = 0.09;
/** [6] Interference bands: count down the frame and crawl rate (35 periods per wrap). */
const float BAND_COUNT = 7.0;
const float BAND_CRAWL = 0.35;

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

/**
 * [5] The signal-loss collapse envelope in [0,1]: fast attack over ~0.3 s, dead-signal hold,
 * ~1.1 s recovery — a collapse, not a strobe. HARD ZERO under reduced FX (detail 0): a
 * full-frame luma drop is exactly the kind of flash the photosensitivity law forbids.
 */
float endBeat(float time, float detail) {
    float slot = floor(time * BEAT_RATE);
    float fire = step(1.0 - BEAT_DUTY, efxHash(vec2(mod(slot, BEAT_WRAP), 3.17)));
    float within = fract(time * BEAT_RATE);
    float env = smoothstep(0.0, 0.08, within) * (1.0 - smoothstep(0.14, 0.42, within));
    return fire * env * detail;
}

void main() {
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    vec3 color = scene;
    float s = clamp(StaticStrength, 0.0, 1.0);

    if (s > 0.0005) { // else: idle — the scene passes through bit-identical
        float detail = clamp(Detail, 0.0, 1.0);
        float env = endCrackle(Time, detail);
        float beat = endBeat(Time, detail);
        // Slot index for the per-slot re-rolls, frozen under reducedFx and wrapped small
        // enough to keep every hash argument fp32-well-conditioned.
        float slot = mod(floor(Time * CRACKLE_RATE) * detail, BAND_SLOT_WRAP);

        // --- [5] beat displacement ---------------------------------------------------------
        // While the signal is down the whole frame slips vertically (wrapping via fract)
        // and coarse rows tear sideways on a fast re-roll. Exactly texCoord when beat = 0,
        // so between beats (and under reduced FX) this is a branchless identity.
        float beatSlot = mod(floor(Time * BEAT_RATE), BEAT_WRAP);
        vec2 suv = texCoord;
        suv.y = fract(suv.y
                + beat * (efxHash(vec2(beatSlot, 11.3)) - 0.5) * 2.0 * SLIP_MAX);
        float row = floor(suv.y * 96.0);
        suv.x += beat * (efxHash(vec2(row * 0.31, mod(floor(Time * 24.0), 200.0))) - 0.5)
                * TEAR_MAX;
        suv = clamp(suv, vec2(0.001), vec2(0.999));

        // --- [2] chromatic aberration ----------------------------------------------------
        vec2 q = texCoord * 2.0 - 1.0;
        float radial = dot(q, q);
        // inversesqrt on a floored length: dead centre (radial 0) would divide by zero and
        // the direction is arbitrary there anyway — the edge weight already kills it.
        vec2 dir = q * inversesqrt(max(radial, 1.0e-6));
        float edge = clamp(radial * 0.5, 0.0, 1.0); // 0 centre, 1 at the corners
        float band = efxNoise(vec2(texCoord.y * BAND_FREQ, slot * 0.37));
        float amount = ABERRATION_MAX * s * env * (0.25 + 0.75 * edge) * (0.45 + 0.90 * band);
        color = efxChroma(DiffuseSampler0, suv, dir, amount);

        // --- [6] interference bands ----------------------------------------------------------
        // Slow luma waves crawling down the frame, riding the crackle envelope so a healthy
        // moment is nearly flat. Fixed phase under reduced FX (the crawl freezes, the faint
        // banding stays). 35 whole periods per 100 s wrap — no jump.
        float wave = sin((texCoord.y * BAND_COUNT - mix(0.0, Time * BAND_CRAWL, detail))
                * 6.2831853);
        color *= 1.0 + wave * 0.045 * s * env;

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

        // --- [5] signal collapse + [4] static veil -------------------------------------------
        // During a beat the picture dies FIRST (dark, desaturated mush — colour is the first
        // thing a failing composite feed loses) …
        color = mix(color, vec3(gzLuma(color)) * 0.35, beat * 0.75);
        // … and the snow washes over what is left. Coarse cells (VEIL_CELL physical pixels
        // — per-texel powder reads as sensor noise, 2-px cells read as TV snow); the mix
        // share rises with s SQUARED so the veil stays a film at range and becomes a wash
        // at the rift lip. The temporal re-roll is detail-gated: reduced FX gets a STILL
        // film of snow, never a boil.
        float snow = efxHash(floor(gl_FragCoord.xy / VEIL_CELL) * 0.173
                + fract(Time * 13.0) * detail * vec2(19.0, 47.0));
        float veil = (VEIL_BASE * env + VEIL_BEAT * beat) * s * s;
        // The snow leans faintly violet (the dimension's cast, END_STAR heritage), and the
        // mix is capped at 0.78: a residual silhouette must survive the deepest beat —
        // horror needs something left to read, full white-out is just a loading screen.
        color = mix(color, vec3(snow) * vec3(0.99, 0.95, 1.06), clamp(veil, 0.0, 0.78));

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
