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

// Macroblock grid (columns x rows) — coarse enough to read as codec blocks at 1080p.
const vec2 GRID = vec2(48.0, 27.0);

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    if (s <= 0.0005) {
        fragColor = vec4(texture(DiffuseSampler0, texCoord).rgb, 1.0);
        return;
    }
    float detail = clamp(Detail, 0.0, 1.0);
    // Re-roll the corruption pattern ~5x/s: blocks pop to new stale sources, they never slide.
    float seed = floor(Time * 5.0) * 0.618 + 1.0;

    // --- macroblock smear ------------------------------------------------------------
    vec2 block = floor(texCoord * GRID);
    float gate = step(1.0 - 0.45 * s, efxHash(block + seed)) * detail;
    // Whole-block motion vector (quantized to block units, up to ~5 blocks) — the stale
    // "reference frame" read; scaled by Strength so edge-band corruption barely twitches.
    vec2 mv = vec2(
            floor((efxHash(block * 1.31 + seed) - 0.5) * 11.0),
            floor((efxHash(block * 2.17 + seed * 1.7) - 0.5) * 7.0));
    vec2 uv = texCoord + gate * mv / GRID * s;

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
    vec2 chromaDir = normalize(vec2(1.0, 0.25) + mv * 0.2);
    float chromaAmt = (0.0015 + 0.006 * (gate + inTear)) * s;
    vec3 color = efxChroma(DiffuseSampler0, uv, chromaDir, chromaAmt);

    // --- DCT crunch ----------------------------------------------------------------------
    // A subset of gated blocks quantizes hard (fake compression ring); a gentle global
    // posterize rides Strength so the whole zone looks one generation overcompressed.
    float crunch = step(0.55, efxHash(block * 3.7 + seed * 2.3)) * gate;
    vec3 crunched = gzPosterize(color, mix(24.0, 6.0, s));
    color = mix(color, crunched, max(crunch, 0.25 * s));

    // --- accent bias ---------------------------------------------------------------------
    // Where the decode failed (gated blocks + tear bands) the channels drift toward the
    // commanded hue — the bias is strongest exactly on the corruption, which is what a
    // colour-broken codec looks like. Identity at AccentAmount 0.
    float broken = max(gate, inTear);
    color *= gzTint(AccentColor, AccentAmount * s * (0.15 + 0.55 * broken));

    // --- static floor --------------------------------------------------------------------
    float static_ = (efxHash(texCoord * vec2(1021.0, 787.0) + fract(Time * 9.0)) - 0.5)
            * 0.10 * s * detail * (0.3 + 0.7 * broken);
    color += vec3(static_) * gzTint(AccentColor, AccentAmount);

    // Banding guard for the posterize/chroma gradients (temporal dither, house rule).
    color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s);

    fragColor = vec4(color, 1.0);
}
