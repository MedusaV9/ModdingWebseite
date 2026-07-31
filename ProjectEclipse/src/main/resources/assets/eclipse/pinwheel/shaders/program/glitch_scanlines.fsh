// eclipse:glitch_scanlines — GLITCHZONE effect (TRANSITION priority): reality plays back
// off a dying VHS tape through a CRT.
//
// WAVE-13 B4 "PHOSPHOR-LOOK". Three additions, all of them computable without a history
// buffer (Veil post has no frame feedback target here — see the report for what a true
// persistence pass would cost):
//
//   [S1] PHOSPHOR DECAY instead of a symmetric line mask. A CRT line does not glow evenly
//        around the beam: it is STRUCK and then decays. The mask is now exp(-t) down each
//        line with a hot leading edge, and the raster is resolution-aware (one line per two
//        physical pixels, capped at the shipped 360) so it stops aliasing into moire at the
//        window sizes this actually runs at.
//   [S3] The rolling bar leaves an AFTERGLOW. The bar rolls upward, so the rows it has
//        already struck are the ones above it; they keep glowing over ~14 % of the frame
//        height and then fall back to the tube floor. This is the part of "Zeilen glimmen
//        nach" that IS temporal — the bar knows its own history from Time alone.
//   [S4] BLOOM STREAKS. Four horizontal taps, luma-thresholded so only real highlights
//        bloom (a full-frame blur would just fog the picture); phosphor-tinted, so bright
//        pixels bleed sideways along the line the way an over-driven tube does.
//   [S5] ROLLING SYNC DISTURBANCE. A soft band rolls down the frame on its own 5 s clock and
//        pulls the rows inside it sideways with a sawtooth — the horizontal-oscillator
//        hunting of a worn control track — and one re-roll in five loses sync hard.
//
// Surviving shipped layers: vertical-hold jitter (the whole frame slips down in irregular
// jumps), the rolling bright bar with in-band displacement and noise, chromatic aberration
// growing toward the frame edges, horizontal CHROMA BLEED (colour smears while luma stays
// sharp — the tape look), tape static, warm-phosphor grade and corner vignette.
//
// F-102 GLITCH-FAMILY POLISH — the pass had the tape but not the TUBE. Two additions:
//   [S6] BARREL CURVATURE, pure UV trick: sample coordinates bow outward with K*r^2 (the
//        classic CRT face), scaled by Strength so the zone edge is flat and deep inside the
//        zone the picture visibly bulges. Where the curved lookup leaves the frame the tube
//        ends — a soft BLACK BEZEL with rounded corners takes over. Every layer downstream
//        (hold jitter, sync, bar, scanline mask) lives in the curved space, so the raster
//        lines follow the glass like they do on a real tube. This is the one addition that
//        makes a STILL frame read "CRT" from across the room.
//   [S7] RGB TRIAD SHADOW MASK: the neutral aperture grille becomes a 3-phase subpixel
//        mask (r/g/b columns offset by a third of a cell) — one cos() per channel, and up
//        close the picture decomposes into phosphor triads.
// Iteration note: the triad replaces the old 0.05 luma grille (running both doubles the
// vertical striping and moires at small windows); the afterglow gain rises 0.11 -> 0.15 so
// the bar's wake survives the triad's mean darkening.
//
// Fed by client.GlitchZoneFx: Strength (0..1 ramp — no-op at 0), Time (wall-clock seconds),
// Detail (0 under reduced FX: hold jitter, rolling bar, sync roll, afterglow and static
// freeze; the scanline/phosphor/aberration/bleed grade survives), AccentColor/AccentAmount
// (F-049: the tube's phosphor. A CRT has no accent object to recolour, so the colour leans
// the things the tube itself emits — the phosphor grade, the bar glow, the afterglow and the
// bloom — through the luma-preserving gzTint, which is exactly vec3(1.0) at amount 0).
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

const float PI = 3.14159265;
// [S1] Decay constant down one phosphor line and how deep the trough goes. LINE_DEPTH is
// picked so the raster's MEAN darkening matches the symmetric sine mask it replaces
// (mean of exp(-3.2t) over a line is 0.30, so mean darkening is 0.20 * 0.70 = 0.14 against
// the shipped 0.11+0.025) — the look changes, the exposure does not.
const float PHOSPHOR_DECAY = 3.2;
const float LINE_DEPTH = 0.20;
// [S3] Persistence window behind the rolling bar, as a fraction of the frame height.
const float BAR_PERSIST = 0.14;
// [S4] Bloom tap offsets in UV, their weights (summing to 1 over the four taps), the
// highlight knee and the additive gain.
const float BLOOM_NEAR = 0.0035;
const float BLOOM_WIDE = 0.0085;
const float BLOOM_KNEE = 0.62;
const float BLOOM_GAIN = 0.55;
// [S5] Sync roll period (a divisor of the 100 s Time wrap), band tightness, sawtooth
// frequency and skew depth. SYNC_TIGHT 14 puts the band at ~14 % of the frame height, and
// SYNC_HUNT 30 fits ~4 sawtooth periods inside it — fewer and the band reads as one smooth
// bend rather than as rows fighting for sync.
const float SYNC_PERIOD = 5.0;
const float SYNC_TIGHT = 14.0;
const float SYNC_HUNT = 30.0;
const float SYNC_SKEW = 0.020;
// [S6] Tube face curvature (UV bow per squared radius) and the bezel edge feather. K 0.18
// bows the frame edge midpoints by ~2% and pulls the corners ~9% inward — a mid-90s
// consumer tube, not a fishbowl.
const float CURVE_K = 0.18;
const float BEZEL_FEATHER = 0.012;
// [S7] Triad mask depth: how far the three phosphor columns modulate their own channel.
// 0.18, not deeper: the line mask already costs ~14% mean brightness, and at 0.22 the two
// together pushed night scenes past the point where the tape content stays readable
// (iteration-1 finding; mean cost of the triad is depth/2).
const float TRIAD_DEPTH = 0.18;

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;

    if (s > 0.0005) { // else: idle — the scene passes through bit-identical
        float detail = clamp(Detail, 0.0, 1.0);

        // --- [S6] barrel curvature -----------------------------------------------------
        // The tube face: UVs bow outward by K*r^2, ramped by Strength (flat at the zone
        // edge). Where the curved lookup falls outside the frame, the picture ends and the
        // bezel begins; the mask is applied at the very end so every layer in between can
        // simply keep sampling the clamped coordinate.
        vec2 qc = texCoord - 0.5;
        vec2 uv = 0.5 + qc * (1.0 + CURVE_K * dot(qc, qc) * s);
        vec2 outside = max(abs(uv - 0.5) - 0.5, 0.0);
        float bezel = smoothstep(0.0, BEZEL_FEATHER, max(outside.x, outside.y));

        // --- vertical hold jitter ------------------------------------------------------
        // The frame slips vertically in irregular gated jumps (~3 rolls/s window), like a CRT
        // losing sync; wraps via fract so the slipped band re-enters from the top.
        float holdSeed = floor(Time * 3.1);
        float holdGate = step(0.55, efxHash(vec2(holdSeed, 7.7))) * detail;
        uv.y = fract(uv.y + holdGate * (efxHash(vec2(holdSeed, 13.1)) - 0.5) * 0.06 * s);

        // --- [S5] rolling sync disturbance -----------------------------------------------
        // Wrapped distance to the rolling band centre, so the band re-enters seamlessly at
        // the frame edge. Inside it the rows are pulled sideways by a sawtooth (the classic
        // horizontal-oscillator hunt), and one band pass in five is a hard sync loss.
        float syncPos = fract(Time / SYNC_PERIOD);
        float syncBand = exp(-abs(fract(uv.y - syncPos + 0.5) - 0.5) * SYNC_TIGHT);
        float syncHard = 1.0 + 3.2 * step(0.80, efxHash(vec2(floor(Time / SYNC_PERIOD), 29.3)));
        uv.x += syncBand * syncHard * (fract(uv.y * SYNC_HUNT) - 0.5) * SYNC_SKEW * s * detail;

        // --- rolling scan bar --------------------------------------------------------------
        // The classic bright VHS bar rolling upward; rows inside it shove sideways slightly
        // and carry extra noise.
        float barPos = 1.0 - fract(Time * 0.20);
        float bar = exp(-abs(uv.y - barPos) * 55.0) * detail;
        uv.x += bar * (efxNoise(vec2(uv.y * 90.0, Time * 8.0)) - 0.5) * 0.03 * s;

        // [S3] Phosphor persistence behind the bar. The bar's y DECREASES over time, so a row
        // was struck when the bar was at its own height — rows ABOVE the bar are the recent
        // ones, and fract() picks the wrapped "how long ago" without a branch.
        float afterglow = exp(-fract(uv.y - barPos) / BAR_PERSIST) * detail;

        uv = clamp(uv, vec2(0.001), vec2(0.999));

        // --- chromatic aberration + chroma bleed -------------------------------------------
        // Aberration grows toward the edges (CRT geometry); on top, chroma (colour minus
        // luma) is smeared rightward across ~3 taps while luma stays put — colour bleeding.
        vec2 fromCenter = uv - 0.5;
        float aber = (0.0012 + 0.004 * dot(fromCenter, fromCenter) * 4.0) * s;
        color = efxChroma(DiffuseSampler0, uv, normalize(vec2(fromCenter.x + 1.0e-4, fromCenter.y * 0.4)), aber);
        float luma = gzLuma(color);
        vec3 bleed = texture(DiffuseSampler0, clamp(uv - vec2(0.0045, 0.0) * s, vec2(0.001), vec2(0.999))).rgb
                + texture(DiffuseSampler0, clamp(uv - vec2(0.009, 0.0) * s, vec2(0.001), vec2(0.999))).rgb;
        vec3 bleedChroma = bleed * 0.5 - vec3(gzLuma(bleed * 0.5));
        color = mix(color, vec3(luma) + bleedChroma, 0.55 * s);

        vec3 tint = gzTint(AccentColor, AccentAmount);

        // --- [S4] bloom streaks --------------------------------------------------------------
        // Four horizontal taps around the (already displaced) sample point. The knee keeps
        // this on highlights only: below it the term is exactly zero, so midtones are not
        // fogged and the pass stays a CRT rather than a soft-focus filter.
        vec3 bloom = (texture(DiffuseSampler0, clamp(uv + vec2(BLOOM_NEAR, 0.0), vec2(0.001), vec2(0.999))).rgb
                        + texture(DiffuseSampler0, clamp(uv - vec2(BLOOM_NEAR, 0.0), vec2(0.001), vec2(0.999))).rgb) * 0.34
                + (texture(DiffuseSampler0, clamp(uv + vec2(BLOOM_WIDE, 0.0), vec2(0.001), vec2(0.999))).rgb
                        + texture(DiffuseSampler0, clamp(uv - vec2(BLOOM_WIDE, 0.0), vec2(0.001), vec2(0.999))).rgb) * 0.16;
        color += bloom * smoothstep(BLOOM_KNEE, 1.0, gzLuma(bloom)) * BLOOM_GAIN * tint * s;

        // --- [S1] phosphor raster ------------------------------------------------------------
        // Resolution-aware line/grille counts: at the window sizes this runs at, the shipped
        // 360-line raster is far past Nyquist and turns into moire instead of lines.
        vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
        float lineCount = clamp(screenSize.y * 0.5, 120.0, 360.0);
        float grilleCount = clamp(screenSize.x * 0.5, 180.0, 540.0);
        // The strike is hot at the top of each line and decays down it — glowing after,
        // instead of a symmetric sine that reads as a static grid.
        float strike = exp(-fract(uv.y * lineCount) * PHOSPHOR_DECAY);
        color *= 1.0 - LINE_DEPTH * (1.0 - strike) * s;
        // [S7] RGB triad shadow mask, replacing the old neutral grille (running both would
        // double the vertical striping and moire at small windows): three phosphor columns
        // per grille cell, each channel dimmed by its own phase — up close the picture
        // decomposes into triads, at distance the mean is an even (1 - depth/2) on all
        // three channels, so the mask is luma- and hue-neutral from afar.
        float phase = uv.x * grilleCount;
        vec3 triad = 1.0 - TRIAD_DEPTH
                * (0.5 + 0.5 * cos((vec3(phase) - vec3(0.0, 0.3333, 0.6667)) * 2.0 * PI));
        color *= mix(vec3(1.0), triad, s);

        // --- static, bar highlight + afterglow ---------------------------------------------
        float static_ = (efxHash(uv * vec2(911.0, 631.0) + fract(Time * 11.0)) - 0.5) * 0.12 * s * detail;
        color += vec3(static_);
        color += vec3(0.9, 0.95, 1.0) * tint * bar * 0.10 * s * (0.5 + 0.5 * efxNoise(vec2(uv.x * 40.0, Time * 12.0)));
        // The afterglow is the tube's own emission, so it wears the commanded phosphor and
        // rides the same line raster it decays inside. Gain 0.15 (was 0.11): the triad mask
        // costs the picture ~11% mean brightness and the wake has to stay readable over it.
        color += vec3(0.62, 0.78, 0.68) * tint * afterglow * strike * 0.15 * s;

        // --- phosphor grade + vignette ------------------------------------------------------
        // Slight warm-green cast, mild desaturation, dark corners: the tube itself. The cast
        // is the commanded hue once a colour is set — a red tube, a cyan tube.
        color = mix(color, vec3(gzLuma(color)) * vec3(0.92, 1.04, 0.96) * tint, 0.30 * s);
        color *= 1.0 - 0.30 * smoothstep(0.40, 0.95, length(fromCenter) * 1.6) * s;

        color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s);

        // [S6] Tube bezel — the final word: where the curved face left the frame the tube
        // is dark glass with a whisper of the phosphor tint. Multiplied by s so a weak zone
        // shows soft corner shading rather than hard black corners popping in.
        color = mix(color, vec3(0.004, 0.010, 0.007) * tint, bezel * s);
    }

    fragColor = vec4(color, 1.0);
}
