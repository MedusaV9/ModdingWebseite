// eclipse:glitch_datamosh — GLITCHZONE effect (TRANSITION priority): the frame decodes
// like a video stream with shot motion vectors. Macroblocks (a coarse 16:9-ish grid)
// gate on and hold STALE content — each gated block resamples from a whole-block offset
// that re-rolls at ~5 Hz, so patches of reality smear/repeat instead of updating; hard
// blocks additionally posterize (fake DCT crunch). On top: chroma shift along the block
// displacement, sparse full-frame tear lines that shove and duplicate a row band, and a
// low static floor. Fed by client.GlitchZoneFx: Strength (0..1 ramp — no-op at 0), Time
// (wall-clock seconds), Detail (0 under reduced FX: tears, block motion and static
// collapse; a mild chroma/posterize grade remains so the zone still reads corrupted),
// AccentColor/AccentAmount (F-049: a broken codec has no accent object either, so the
// colour lands where a real bad decode shows its bias — the corrupted BLOCKS and the tear
// bands get a luma-preserving wash, and the static floor is tinted with it. Both terms are
// scaled by AccentAmount, so an uncoloured datamosh zone is untouched).
//
// WAVE-13 B4 touched ONE thing here: main() no longer holds a value-less `return`. See the
// glsl-processor note in umbral_veins.fsh — a stray hash character anywhere in this file, a
// hex colour in a comment included, arms a parser NPE that silently unregisters the pipeline.
//
// F-102 GLITCH-FAMILY POLISH — the shipped pass moved blocks as CLEAN COPIES, which reads as
// a sliding puzzle in a still frame, not as a broken decode. Four additions fix the still:
//   [D1] SLAB TIER. A second, COARSE macroblock grid (12x7) on its own slower re-roll clock
//        (1.25 Hz) with displacement up to 3 slab units — the huge dislocated plates that
//        make a datamosh screenshot readable at a glance. The fine 48x27 tier rides on top.
//   [D2] MOTION SMEAR. Gated blocks no longer copy — they SMEAR: two extra taps back along
//        the block's own motion vector, weighted toward the head. A still frame now shows
//        directional streaking inside corrupted blocks (the actual mosh read).
//   [D3] BLOCKING SEAMS. Corrupted regions get a one-texel dark seam on their macroblock
//        boundaries (fract-based, zero taps) — the MPEG block lattice becomes visible
//        exactly where the decode failed, nowhere else.
//   [D4] DC TILT. A subset of gated blocks takes a flat additive colour push (green/magenta
//        split by hash, the classic wrong-DC-coefficient block); a commanded accent replaces
//        the split so datamosh_red tilts its broken blocks red.
// Tap budget: 1 base + 3 chroma + 2 smear = 6 per pixel, no loops, no dynamic branches.
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

// Fine macroblock grid (columns x rows) — coarse enough to read as codec blocks at 1080p.
const vec2 GRID = vec2(48.0, 27.0);
// [D1] Coarse slab grid and its clock. 12x7 keeps a slab ~90 px tall at 1080p — a plate,
// not a block; 1.25 Hz divides the fine tier's 5 Hz clock so the two never beat.
const vec2 SLAB_GRID = vec2(12.0, 7.0);
const float SLAB_RATE = 1.25;
// Share of slabs corrupted at full strength. Deliberately low: the grid is 12x7 = 84 slabs
// on screen, so 0.07 means ~5 dislocated plates per re-roll — drama, not soup (0.16 was 13
// plates, iteration-1 finding).
const float SLAB_SHARE = 0.07;
// [D4] The two DC-tilt colours a real decoder shows (green-heavy / magenta-heavy).
const vec3 DC_GREEN = vec3(-0.06, 0.10, -0.04);
const vec3 DC_MAGENTA = vec3(0.09, -0.07, 0.08);

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;

    if (s > 0.0005) { // else: idle — the scene passes through bit-identical
        float detail = clamp(Detail, 0.0, 1.0);
        // Re-roll the corruption pattern ~5x/s: blocks pop to new stale sources, never slide.
        float seed = floor(Time * 5.0) * 0.618 + 1.0;

        // --- [D1] coarse slab tier ---------------------------------------------------------
        // Big dislocated plates on their own slow clock. The slab displacement is applied
        // FIRST so the fine tier corrupts the already-dislocated image — two generations of
        // decode failure, like a real mosh.
        float slabSeed = floor(Time * SLAB_RATE) * 0.618 + 7.0;
        vec2 slab = floor(texCoord * SLAB_GRID);
        float slabGate = step(1.0 - SLAB_SHARE * s, efxHash(slab + slabSeed)) * detail;
        vec2 slabMv = vec2(
                floor((efxHash(slab * 1.73 + slabSeed) - 0.5) * 7.0),
                floor((efxHash(slab * 2.41 + slabSeed * 1.3) - 0.5) * 5.0));
        vec2 uv = texCoord + slabGate * slabMv / SLAB_GRID * s;

        // --- fine macroblock tier ------------------------------------------------------------
        vec2 block = floor(texCoord * GRID);
        float gate = step(1.0 - 0.45 * s, efxHash(block + seed)) * detail;
        // Whole-block motion vector (quantized to block units, up to ~5 blocks) — the stale
        // "reference frame" read; scaled by Strength so edge-band corruption barely twitches.
        vec2 mv = vec2(
                floor((efxHash(block * 1.31 + seed) - 0.5) * 11.0),
                floor((efxHash(block * 2.17 + seed * 1.7) - 0.5) * 7.0));
        uv += gate * mv / GRID * s;

        // --- full-frame tear lines ---------------------------------------------------------
        // Occasionally (per re-roll) one horizontal band tears: rows inside shove sideways
        // and collapse onto the band's top row — the classic interlace/slice failure.
        float tearOn = step(0.72, efxHash(vec2(seed, 5.3))) * step(0.35, s) * detail;
        float tearY = efxHash(vec2(seed * 3.7, 11.1));
        float tearH = 0.015 + 0.05 * efxHash(vec2(seed, 23.7));
        float inTear = tearOn * step(tearY, texCoord.y) * step(texCoord.y, tearY + tearH);
        uv.x += inTear * (efxHash(vec2(seed, 31.7)) - 0.5) * 0.35 * s;
        uv.y = mix(uv.y, tearY, inTear * 0.85);

        uv = clamp(uv, vec2(0.001), vec2(0.999));

        // --- chroma shift ------------------------------------------------------------------
        // RGB planes desync along the local displacement (blocks/tears split hardest); a
        // small global split keeps even untouched regions slightly out of register.
        // The `* detail` on the motion vector is a reducedFx fix: `mv` re-rolls at 5 Hz and
        // was the ONE term here not gated by Detail, so under reducedFx the residual global
        // split kept flipping direction five times a second — a small but real flicker on a
        // toggle that exists to remove exactly that. At Detail 1 this is unchanged.
        vec2 chromaDir = normalize(vec2(1.0, 0.25) + mv * 0.2 * detail);
        float chromaAmt = (0.0015 + 0.006 * (gate + inTear)) * s;
        color = efxChroma(DiffuseSampler0, uv, chromaDir, chromaAmt);

        // --- [D2] motion smear ----------------------------------------------------------------
        // Two taps back along the pixel's TOTAL displacement (slab + block), weighted toward
        // the head. Inside corrupted blocks the copy becomes a directional streak; untouched
        // pixels have displacement 0, so the taps degenerate to the base sample and the mix
        // is a no-op there (branchless).
        vec2 smearVec = (slabGate * slabMv / SLAB_GRID + gate * mv / GRID) * s;
        float smeared = max(gate, slabGate);
        vec3 smear1 = texture(DiffuseSampler0,
                clamp(uv - smearVec * 0.35, vec2(0.001), vec2(0.999))).rgb;
        vec3 smear2 = texture(DiffuseSampler0,
                clamp(uv - smearVec * 0.70, vec2(0.001), vec2(0.999))).rgb;
        color = mix(color, color * 0.5 + smear1 * 0.3 + smear2 * 0.2, smeared * 0.75);

        // --- DCT crunch ----------------------------------------------------------------------
        // A subset of gated blocks quantizes hard (fake compression ring); a gentle global
        // posterize rides Strength so the whole zone looks one generation overcompressed.
        float crunch = step(0.55, efxHash(block * 3.7 + seed * 2.3)) * gate;
        vec3 crunched = gzPosterize(color, mix(24.0, 6.0, s));
        color = mix(color, crunched, max(crunch, 0.25 * s));

        // --- [D3] blocking seams + [D4] DC tilt ------------------------------------------------
        // Corruption mask first: gated fine blocks, dislocated slabs, and tear rows all count.
        float broken = max(max(gate, slabGate), inTear);
        // One-texel-ish dark seam on the fine macroblock lattice, only where the decode
        // failed — the lattice must not be a global overlay grid.
        vec2 bf = abs(fract(texCoord * GRID) - 0.5);
        float seam = smoothstep(0.44, 0.5, max(bf.x, bf.y));
        color *= 1.0 - seam * broken * 0.35 * s;
        // Flat wrong-DC push on a subset of gated blocks; hash picks green vs magenta. A
        // commanded accent replaces the split (luma-neutralized signed tilt), so
        // datamosh_red tilts its broken blocks red instead of green/magenta.
        float dcRoll = efxHash(block * 5.3 + seed * 3.1);
        float dcOn = step(0.70, dcRoll) * max(gate, slabGate);
        vec3 dcShip = mix(DC_GREEN, DC_MAGENTA, step(0.85, dcRoll));
        vec3 dcAccent = (AccentColor / max(gzLuma(AccentColor), 0.001) - 1.0) * 0.09;
        color += mix(dcShip, dcAccent, clamp(AccentAmount, 0.0, 1.0)) * dcOn * s;

        // --- accent bias ---------------------------------------------------------------------
        // Where the decode failed (gated blocks + tear bands) the channels drift toward the
        // commanded hue — the bias is strongest exactly on the corruption, which is what a
        // colour-broken codec looks like. Identity at AccentAmount 0.
        color *= gzTint(AccentColor, AccentAmount * s * (0.15 + 0.55 * broken));

        // --- static floor --------------------------------------------------------------------
        float static_ = (efxHash(texCoord * vec2(1021.0, 787.0) + fract(Time * 9.0)) - 0.5)
                * 0.10 * s * detail * (0.3 + 0.7 * broken);
        color += vec3(static_) * gzTint(AccentColor, AccentAmount);

        // Banding guard for the posterize/chroma gradients (temporal dither, house rule).
        color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s);
    }

    fragColor = vec4(color, 1.0);
}
