// eclipse:glitch_invert — GLITCHZONE effect (TRANSITION priority): the palette flips
// negative and cannot hold itself together.
//
// WAVE-13 B4 "fBm-FLECKEN". The inversion is no longer a full-screen uniform pop. It lives
// in organic blotches that GROW and SHRINK:
//
//   [I1] One 4-octave fBm (the census octave budget for llvmpipe) in aspect-corrected screen
//        space, so the patches are round instead of letterboxed, with a slow domain drift so
//        they crawl as well as breathe.
//   [I2] The THRESHOLD is the growth knob, not the amplitude: a high threshold leaves a few
//        small islands, a low one lets the islands merge into a continent. Two incommensurate
//        clocks (12.5 s breath, 25 s swell — both divisors of the 100 s Time wrap, so neither
//        jumps) keep the coverage off an obvious beat, and Strength slides the whole breathing
//        band downward, so the zone edge shows a couple of patches while deep inside the frame
//        is nearly taken. It stays a takeover; it just stops being a rectangle.
//   [I4] Everything else is weighted BY the blot: the negative, the hue snap and the
//        posterize all run at full inside a blot and at a fraction outside, so the contrast
//        between corrupted and merely-degraded pixels is the effect.
//   [I5] The accent burns on the blot ISO-CONTOUR — a boundary layer where the negative is
//        tearing into the positive. This replaces the shipped posterize-band seam shimmer:
//        same role (the accent lives on an edge), stronger read, and it derives from the fBm
//        field that is already in a register, so it is a texture tap cheaper.
//
// Surviving shipped layers: the hue keeps ROTATING in unstable quantized snaps (a drifting
// wander that locks to ~22.5-degree detents and occasionally pops a whole detent), the
// posterize collapses toward a handful of levels, and brief gated inversion "drops" let the
// negative collapse back toward positive for a re-roll — film slipping in the gate.
//
// Fed by client.GlitchZoneFx: Strength (0..1 ramp — no-op at 0), Time (wall-clock seconds),
// Detail (0 under reduced FX: hue wander freezes at a fixed angle, the drops stop, and the
// patches hold still at mid-growth instead of breathing — the static negative + posterize
// grade inside them survives), AccentColor/AccentAmount (F-049: the blot rim is the accent —
// shipped violet, luma-matched to any commanded colour — plus a light wash over the negative
// so the whole frame leans that way).
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

// [I1] Patch field: fBm cells across the frame height, and the domain drift. The drift is a
// slow CIRCLE, not a straight line: Time wraps at 100 s, so a linear drift would snap the
// whole field back by the accumulated offset once per wrap. A 50 s orbit divides the wrap
// and closes on itself, and at this radius it still reads as crawling.
const float PATCH_FREQ = 2.6;
const float PATCH_DRIFT_PERIOD = 50.0;
const float PATCH_DRIFT_RADIUS = 0.7;
// [I3] Width of the threshold ramp. Narrow enough that a blot has an EDGE (the whole point),
// wide enough not to alias on the diagonal.
const float PATCH_BAND = 0.055;
// [I5] Shipped rim colour (the old seam violet) and its additive gain.
const vec3 SEAM_VIOLET = vec3(0.35, 0.10, 0.45);
const float RIM_GAIN = 0.45;

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    vec3 color = scene;

    if (s > 0.0005) { // else: idle — the scene passes through bit-identical
        float detail = clamp(Detail, 0.0, 1.0);
        float seed = floor(Time * 4.0);

        // --- [I1/I2/I3] organic inversion patches --------------------------------------
        vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
        float aspect = screenSize.x / max(screenSize.y, 1.0);
        float driftAngle = TAU * Time / PATCH_DRIFT_PERIOD;
        vec2 drift = vec2(sin(driftAngle), cos(driftAngle)) * PATCH_DRIFT_RADIUS * detail;
        vec2 patchUv = vec2(texCoord.x * aspect, texCoord.y) * PATCH_FREQ + drift;
        float field = gzFbm(patchUv);

        float breath = 0.5 + 0.5 * sin(TAU * Time / 12.5);
        float swell = 0.5 + 0.5 * sin(TAU * Time / 25.0 + 1.7);
        // Frozen at mid-growth under reduced FX: the patches stay, the breathing stops.
        float grow = mix(0.5, mix(breath, swell, 0.45), detail);
        float threshold = mix(mix(0.70, 0.52, s), mix(0.60, 0.30, s), grow);
        float blot = smoothstep(threshold, threshold + PATCH_BAND, field);

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
        // deliberately GLOBAL: every blot loses the negative at once, so it still reads as
        // one broken signal rather than as blotches doing their own thing.
        float drop = step(0.84, efxHash(vec2(seed, 41.3))) * detail;
        float invPulse = 1.0 - 0.65 * drop;
        vec3 negative = vec3(1.0) - scene;
        color = mix(scene, negative, s * invPulse * blot);
        color = gzHueRotate(color, angle * s * mix(0.25, 1.0, blot));

        // --- posterization steps ---------------------------------------------------------
        // Levels collapse with Strength (deep inside a blot ~5 per channel, ~14 outside).
        // The banding is the point here, so no dither on this layer — the steps must read as
        // steps; only the smooth blot rim below gets a dither.
        float levels = mix(48.0, 5.0, s * mix(0.35, 1.0, blot));
        color = mix(color, gzPosterize(color, levels), s * mix(0.30, 1.0, blot));

        // --- accent wash --------------------------------------------------------------------
        // A light lean of the whole negative toward the commanded hue (identity at amount 0),
        // so a coloured invert zone is not just a violet rim on a neutral negative.
        color *= gzTint(AccentColor, AccentAmount * 0.35 * s);

        // --- [I5] blot rim + [I6] blot grain -------------------------------------------
        // The rim peaks exactly on the 0.5 iso-line of the blot mask, so its width tracks
        // PATCH_BAND and it can never drift off the blotch it belongs to.
        float rim = 1.0 - abs(blot - 0.5) * 2.0;
        rim *= rim;
        color += gzAccent(SEAM_VIOLET, AccentColor, AccentAmount) * rim * RIM_GAIN * s;
        // A breath of grain inside the patches so they read as corruption, not as vector art.
        color += vec3((efxHash(texCoord * vec2(717.0, 913.0) + fract(Time * 6.0)) - 0.5)
                * 0.06 * s * detail * blot);
        // Banding guard for the rim gradient only (the posterize steps stay undithered).
        color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * rim * s);

        color = clamp(color, 0.0, 1.0);
    }

    fragColor = vec4(color, 1.0);
}
