// eclipse:glitch_invert — GLITCHZONE effect (TRANSITION priority): the palette flips
// negative in WAVES that run outward from the centre of vision and cannot hold themselves
// together.
//
// F-102 GLITCH-FAMILY POLISH "INVERT-PULSE". The wave-13 build inverted inside breathing fBm
// blotches — organic, but static in character: a still frame read as coloured patches, not as
// a PULSE, and nothing travelled anywhere. The mandate is travelling inversion waves from the
// centre, so the blot field is replaced by a radial wave engine (the fBm survives as the
// thing that makes the waves ragged):
//
//   [I1] CONCENTRIC WAVEFRONTS in aspect-corrected screen space: an asymmetric bell
//        (steep leading edge, long trailing decay) runs 0 -> corner every WAVE_PERIOD along
//        the radius, wavelength ~0.55 r-units, so 1-2 travelling rings are on screen at any
//        moment. Inside a band the image is NEGATIVE; between bands it is the un-flipped
//        scene under a mild grade — the contrast between flipped ring and normal world IS
//        the effect, and it reads instantly in a still.
//   [I2] RAGGED FRONTS: the radius is warped by the 4-octave fBm (slow 50 s circular domain
//        drift, the wave-13 orbit law) before the wave lookup, so the rings run corroded and
//        glitchy instead of compass-perfect — snap, never flow.
//   [I3] The wave phase never jumps: WAVE_PERIOD divides the 100 s Time wrap exactly, and
//        under reduced FX the ring field PARKS mid-frame (fixed phase) instead of running.
//   [I4] Hue snap and posterize are weighted BY the band, exactly like they were weighted by
//        the blot before — full corruption inside a wave, a fraction between waves.
//   [I5] The accent burns on the LEADING EDGE of each front (shipped violet, luma-matched to
//        any commanded colour), and the front REFRACTS: a small radial UV ripple rides the
//        rim, so the wavefront bends the world like a pressure wave (one extra tap).
//   [I6] A faint source glow sits at the centre of vision, pulsing with each launched wave —
//        the "where do they come from" anchor.
//
// Surviving shipped layers: unstable quantized hue snaps (22.5-degree detents with pops),
// posterize collapse, gated inversion "drops" (the negative almost recovers, then flips
// back — global on purpose: one broken signal, not blotches doing their own thing).
//
// Fed by client.GlitchZoneFx: Strength (0..1 ramp — no-op at 0), Time (wall-clock seconds),
// Detail (0 under reduced FX: waves park at a fixed phase, hue wander freezes at a fixed
// detent, drops stop, fronts stop refracting — the parked negative rings + posterize grade
// survive), AccentColor/AccentAmount (F-049: the front rim is the accent — shipped violet —
// plus a light wash over the negative so the whole frame leans that way).
//
// No value-less `return` in main() — see the glsl-processor note in umbral_veins.fsh.
#include eclipse:eclipse_common
#include eclipse:eclipse_glitch

uniform sampler2D DiffuseSampler0;
uniform float Strength;
uniform float Time;
uniform float Detail;
uniform vec3 AccentColor;
uniform float AccentAmount;

in vec2 texCoord;

out vec4 fragColor;

const float TAU = 6.28318530718;

// [I1] Wave engine. One front launches from the centre every WAVE_PERIOD (4 s divides the
// 100 s Time wrap: 25 whole cycles, no phase jump); WAVELENGTH is the ring spacing in
// aspect-corrected radius units (corner sits at r ~1.0, so ~0.55 keeps 1-2 rings visible).
const float WAVE_PERIOD = 4.0;
const float WAVELENGTH = 0.55;
// [I2] Ragged fronts: fBm domain frequency, warp depth in r-units, and the slow circular
// domain drift (a 50 s orbit divides the wrap and closes on itself — the wave-13 law).
const float RAGGED_FREQ = 3.1;
const float RAGGED_DEPTH = 0.10;
const float DRIFT_PERIOD = 50.0;
const float DRIFT_RADIUS = 0.7;
// [I5] Shipped rim colour (the seam violet), its additive gain, and the refraction depth of
// the leading edge in UV units.
const vec3 SEAM_VIOLET = vec3(0.35, 0.10, 0.45);
const float RIM_GAIN = 0.60;
const float RIPPLE_UV = 0.007;
// [I3] Parked wave phase under reduced FX (mid-run: one full ring on screen, readable).
const float PARK_PHASE = 0.35;

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    vec3 color = scene;

    if (s > 0.0005) { // else: idle — the scene passes through bit-identical
        float detail = clamp(Detail, 0.0, 1.0);
        float seed = floor(Time * 4.0);

        // --- [I1/I2] radial wave field ----------------------------------------------------
        vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
        float aspect = screenSize.x / max(screenSize.y, 1.0);
        vec2 qa = (texCoord - 0.5) * vec2(aspect, 1.0);
        float r = length(qa);
        // Radial direction, defined at the exact centre (the rim weight is ~0 there anyway).
        vec2 radial = qa / max(r, 1.0e-4);

        // Ragged radius: the fBm warps the wave lookup, so the fronts run corroded. Same
        // slow circular domain drift as the wave-13 blot field (50 s orbit, closes on the
        // 100 s wrap, frozen under reduced FX).
        float driftAngle = TAU * Time / DRIFT_PERIOD;
        vec2 drift = vec2(sin(driftAngle), cos(driftAngle)) * DRIFT_RADIUS * detail;
        float rw = r + (gzFbm(qa * RAGGED_FREQ + drift) - 0.5) * RAGGED_DEPTH;

        // [I3] Travelling phase; parked mid-run under reduced FX. As phase grows, a fixed
        // point on the bell sits at a growing radius — the wave runs OUTWARD from centre.
        float phase = mix(PARK_PHASE, fract(Time / WAVE_PERIOD), detail);
        float wv = fract(rw / WAVELENGTH - phase);
        // Asymmetric bell with the STEEP edge on the OUTSIDE: larger wv = larger radius, so
        // the leading edge of an outward wave is the top of the support (hard cut at 0.52)
        // and the long decay tail trails INWARD (soft rise from 0.12). Getting this backwards
        // puts the wake in front of the wave (iteration-1 finding). Support is ~40% of the
        // cycle, so flipped rings and normal world alternate readably in a still.
        float band = smoothstep(0.12, 0.42, wv) * (1.0 - smoothstep(0.45, 0.52, wv));
        // Narrow spike exactly on the leading edge — the accent rim and the refraction.
        float rim = smoothstep(0.36, 0.45, wv) * (1.0 - smoothstep(0.45, 0.53, wv));

        // [I5] The front refracts: one extra tap with a small radial ripple on the rim, so
        // the wavefront bends the world like a pressure wave. At rim 0 the coordinate is
        // texCoord and the tap is bit-identical to `scene` (branchless no-op).
        vec2 ruv = clamp(texCoord + radial * rim * RIPPLE_UV * s * detail,
                vec2(0.001), vec2(0.999));
        vec3 waveScene = texture(DiffuseSampler0, ruv).rgb;

        // --- unstable hue rotation --------------------------------------------------------
        // A slow noise wander sets the target angle; it locks to 16 detents (22.5-degree
        // steps) so the hue SNAPS between poses instead of cycling smoothly (glitch verbs:
        // snap, never flow), and every re-roll can pop one extra detent. Frozen at a fixed
        // detent under reduced FX.
        float wander = efxNoise(vec2(Time * 0.35, 3.7)) * 2.0 - 1.0;
        float pop = (step(0.8, efxHash(vec2(seed, 17.9))) * 2.0 - 1.0) * step(0.5, detail);
        float angle = mix(TAU * 0.125, floor((wander * 2.5 + pop) * 16.0) / 16.0 * TAU, detail);

        // --- inversion with gated drops -----------------------------------------------------
        // invPulse is 1 (full negative) most of the time; ~1 re-roll in 6 dips toward 0.35
        // for one pattern step — the image "almost recovers", then flips back. The drop is
        // deliberately GLOBAL: every ring loses the negative at once, so it still reads as
        // one broken signal rather than as rings doing their own thing.
        float drop = step(0.84, efxHash(vec2(seed, 41.3))) * detail;
        float invPulse = 1.0 - 0.65 * drop;
        vec3 negative = vec3(1.0) - waveScene;
        color = mix(waveScene, negative, s * invPulse * band);
        color = gzHueRotate(color, angle * s * mix(0.20, 1.0, band));

        // --- posterization steps ---------------------------------------------------------
        // Levels collapse with Strength (inside a wave ~5 per channel, ~14 between waves).
        // The banding is the point here, so no dither on this layer — the steps must read as
        // steps; only the smooth rim/band gradients below get a dither.
        float levels = mix(48.0, 5.0, s * mix(0.35, 1.0, band));
        color = mix(color, gzPosterize(color, levels), s * mix(0.25, 1.0, band));

        // --- accent wash --------------------------------------------------------------------
        // A light lean of the whole negative toward the commanded hue (identity at amount 0),
        // so a coloured invert zone is not just a violet rim on a neutral negative.
        color *= gzTint(AccentColor, AccentAmount * 0.35 * s);

        // --- [I5] front rim + [I6] source glow + wave grain ---------------------------------
        // The accent burns on the leading edge of every front.
        vec3 rimAccent = gzAccent(SEAM_VIOLET, AccentColor, AccentAmount);
        color += rimAccent * rim * RIM_GAIN * s;
        // [I6] Source glow: a soft anchor at the centre of vision that flares as each wave
        // launches (phase near 0) and settles between launches. Parked dim under reduced FX.
        float launch = 1.0 - smoothstep(0.0, 0.30, phase);
        color += rimAccent * exp(-r * 9.0) * (0.30 + 0.70 * launch) * 0.30 * s;
        // A breath of grain inside the waves so they read as corruption, not as vector art.
        color += vec3((efxHash(texCoord * vec2(717.0, 913.0) + fract(Time * 6.0)) - 0.5)
                * 0.06 * s * detail * band);
        // Banding guard for the smooth wave gradients (the posterize steps stay undithered).
        color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * max(rim, band) * s);

        color = clamp(color, 0.0, 1.0);
    }

    fragColor = vec4(color, 1.0);
}
