// eclipse:rift_glitch v2 — transition pass + ambient rift-proximity corruption (GLITCH
// team pass over the P2 R13/R17 original, TRANSITION priority). Fed by veilfx.TransitionFx:
//   GlitchAmount — digital tearing (transition envelope / rift open-close pulses / loading
//                  pulse): datamosh blocks + fine row jitter + chromatic tear + 2-frame
//                  invert pops + scanline shimmer. Contract unchanged (§3.3 frozen name).
//   FadeAmount   — fade-to-black closing iris with violet edge bleed (0 = clear, 1 = black;
//                  the portal hold keeps it at 1 during the dimension change). Unchanged.
//   Time         — wall-clock seconds (keeps animating while client ticks stall).
//   RiftCenter   — v2 ADDITION: NDC position of the nearest live rift tear (parked just
//                  offscreen on the rift's side when it is behind the camera,
//                  border_glitch-style, so turning away softens instead of snapping).
//   RiftAmount   — v2 ADDITION: 0..1 ambient "corrupted spacetime" amount from rift
//                  proximity (RiftFx → TransitionFx.setRiftAmbient; capped 0.6, ALWAYS 0
//                  under reducedFx). Drives three new layers: voxel-sort streaks, mirror-
//                  shard refraction around RiftCenter, and a time-jitter echo ghost.
// NOTE on the echo: this is a single-stage veil:blit pipeline with NO history buffer, so
// the "previous-frame ghost" is faked by re-sampling the CURRENT frame at a jitter offset
// that re-rolls at ~8 Hz — the stale-looking displaced copy sells the same beat without a
// second render target.
//
// v3 (VEIL-REPASS-1): QUANTIZED SPIRAL WARP near the center. The v2 team REJECTED a
// "slow UV swirl" as a water/portal cliché that fights the shard layer; this is the
// fresh-eyes re-answer to the same ambition with both objections addressed: the twist is
// QUANTIZED into ~2° angular steps (space shears in discrete rings — a glitch snap per
// the FX style guide's GLITCH verbs, nothing flows like water), it is STATIC in time
// (the angle tracks proximity only; nothing rotates over time, so no motion-sickness
// vector), and it lives INSIDE the shard disc at sub-shard amplitude (≤ ~0.16 rad at
// the very center) so the shards keep owning the read. Rides RiftAmount, which is 0
// under reducedFx at the source.
//
// v4 (F-102 RIFT-MASSE): DEPTH FAKE — the tear stops being a flat screen decal and
// reads as a HOLE with an edge. Three layers, all riding RiftAmount (0 under reducedFx):
//   * INTERIOR PARALLAX SHELVES — the disc interior is sliced into discrete lensDist
//     rings (the screen-space twin of day_rift_maw's stacked throat shells); every shelf
//     re-samples the scene pushed radially OUTWARD by a per-shelf depth amount (concave
//     minification: the interior visibly recedes like a pit) plus a slow per-shelf
//     radial breath and an ALTERNATING tangential drift (counter-rotating strata). The
//     shelf offsets differ in a single still frame — depth without any motion — and the
//     drift is bounded sin(Time) oscillation, no unbounded smear, no swirl cliché.
//   * SEAM REFRACTION — a narrow annulus just outside the shard disc bends the scene
//     outward like the edge of a thick lens; the strength is raggedized by noise on the
//     rim DIRECTION (continuous across the atan wrap) crawling slowly with Time, so the
//     rim is a torn, slightly boiling edge instead of a compass circle.
//   * CHROMATIC SEAM FRINGES — in that same annulus the RGB split re-aims RADIALLY and
//     swells with the shared raggedness: the rim splits into prism fringes exactly
//     where the fake lens bends hardest (the classic thick-glass depth cue).
// Still one pass, no history buffer, no new uniforms — Time stays the Java-fed feed.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float GlitchAmount;
uniform float FadeAmount;
uniform float Time;
uniform vec2 RiftCenter;
uniform float RiftAmount;

in vec2 texCoord;

out vec4 fragColor;

// 60° mirror shards around the rift center.
const float SHARD_WIDTH = 1.0471976;

void main() {
    float g = clamp(GlitchAmount, 0.0, 1.0);
    float f = clamp(FadeAmount, 0.0, 1.0);
    float rift = clamp(RiftAmount, 0.0, 1.0);
    // Shared "spacetime corruption" driver: full near a rift; heavy transitions inherit a
    // share so portal enters speak the same streak/echo vocabulary as standing at a tear.
    float corr = max(rift, g * 0.55);

    // Re-seed the artifact pattern ~12x/s — blocks pop instead of sliding.
    float seed = floor(Time * 12.0) * 0.618 + 1.0;

    // Aspect-corrected space (shards must be round on any resolution) + the rift lens.
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
    float aspect = screenSize.x / max(screenSize.y, 1.0);
    vec2 p = (texCoord * 2.0 - 1.0) * vec2(aspect, 1.0);
    vec2 lens = clamp(RiftCenter, vec2(-2.5), vec2(2.5)) * vec2(aspect, 1.0);
    vec2 fromLens = p - lens;
    float lensDist = length(fromLens);

    // Coarse datamosh rows jump sideways; a sparse set of fine rows jitters on top.
    vec2 uv = texCoord + efxBlockOffset(texCoord, seed, g);
    float row = floor(uv.y * 90.0);
    uv.x += (efxHash(vec2(row, seed * 1.37)) - 0.5) * 0.02 * g
            * step(0.82, efxHash(vec2(row * 0.71, seed)));

    // v2 — VOXEL-SORT streaks: narrow lanes perpendicular to the away-from-rift axis drag
    // outward by random QUANTIZED lengths (the pixel-sorting read, faked as a directional
    // smear — a true sort needs unbounded taps). Lane layout re-rolls with the 12 Hz seed.
    // Polish 3 note: with no rift near, RiftCenter defaults to (0, −1.9) below the screen,
    // so pure-transition streaks (corr = g·0.55) drag VERTICALLY — the classic pixel-sort
    // orientation. Deliberate, keep the default park at the bottom edge.
    vec2 axis = lensDist > 1.0e-4 ? fromLens / lensDist : vec2(0.0, 1.0);
    vec2 axisUv = normalize(vec2(axis.x / aspect, axis.y));
    float lane = floor(dot(p, vec2(-axis.y, axis.x)) * 34.0);
    float laneGate = step(1.0 - 0.30 * corr, efxHash(vec2(lane, seed * 2.23)));
    float laneLen = floor(efxHash(vec2(lane * 1.31, seed)) * 5.0) * 0.012;
    uv -= axisUv * (laneLen * laneGate * corr);

    // v3 — QUANTIZED SPIRAL WARP (see header): space around the tear is wound up in
    // discrete ~2° shear rings, tightest at the center, dead by lensDist 0.45. Applied
    // as an ADDITIVE offset so the datamosh/streak layers survive underneath; the shard
    // branch below still mixes TOWARD its mirror copies where gated, so shards keep
    // winning their sectors and the wind-up shows through the ungated ones.
    // No atan here — only cos/sin of a bounded angle, so no degenerate-center risk; the
    // epsilon guard just skips dead work at the exact center (offset → 0 there anyway).
    float twistZone = (1.0 - smoothstep(0.05, 0.45, lensDist)) * rift;
    if (twistZone > 0.003 && lensDist > 1.0e-4) {
        float spiral = twistZone * twistZone * 0.45;
        float spiralQ = floor(spiral * 28.0) * (1.0 / 28.0);
        float cs = cos(spiralQ);
        float sn = sin(spiralQ);
        vec2 wound = lens + mat2(cs, -sn, sn, cs) * fromLens;
        uv += (wound - p) / vec2(aspect, 1.0) * 0.5;
    }

    // v4 — INTERIOR PARALLAX SHELVES (see header): discrete depth rings, deeper = a
    // bigger outward re-sample (concave pit read). Each shelf breathes radially at its
    // own hashed rate and drifts tangentially with an alternating sign — bounded
    // oscillation, so a still frame keeps the stepped depth read and a moving frame
    // adds counter-rotating strata on top. Quantization (floor) is deliberate: the
    // shelf SEAMS are the depth edges the eye reads, per the house glitch verbs.
    float depthZone = (1.0 - smoothstep(0.08, 0.52, lensDist)) * rift;
    if (depthZone > 0.003 && lensDist > 1.0e-4) {
        float shelf = floor(lensDist * 9.0);
        float shelfDepth = 1.0 - shelf * (1.0 / 9.0); // 1 at the center, 0 at the rim
        float breath = 1.0 + 0.18 * sin(Time * (0.5 + 0.6 * efxHash(vec2(shelf, 7.7)))
                + shelf * 2.4);
        float spinDir = mod(shelf, 2.0) * 2.0 - 1.0;   // alternating shelves counter-drift
        vec2 tangUv = vec2(-axisUv.y, axisUv.x);
        uv += axisUv * (shelfDepth * shelfDepth * 0.020 * breath * depthZone)
                + tangUv * (spinDir * 0.006 * shelfDepth
                        * sin(Time * 0.7 + shelf * 1.9) * depthZone);
    }

    // v4 — SEAM REFRACTION: a narrow annulus outside the shard disc bends the scene
    // outward like the edge of a thick lens. Raggedness is noise on the rim DIRECTION
    // (unit vector — continuous across the atan wrap) crawling slowly with Time; it is
    // shared with the chromatic fringes below so the bend and the color split ride the
    // exact same torn edge.
    float seamZone = (smoothstep(0.42, 0.60, lensDist) - smoothstep(0.62, 0.88, lensDist)) * rift;
    float seamRag = 0.0;
    if (seamZone > 0.003 && lensDist > 1.0e-4) {
        seamRag = 0.25 + 0.75 * efxNoise(axis * 2.6 + vec2(Time * 0.25, -Time * 0.19));
        uv += axisUv * (seamZone * seamRag * 0.014);
    }

    // v2 — MIRROR-SHARD refraction near the rift center: the disc around RiftCenter splits
    // into 60° shards; gated shards resample the scene reflected across their bisector
    // (kaleidoscope-lite) — space around the tear looks reassembled from shattered copies.
    // lensDist epsilon guard: at the exact center atan(0,0) is undefined (NaN would
    // propagate through floor/cos/sin into the sampled UV); the mirror displacement is
    // proportional to lensDist there anyway, so skipping the branch is visually identical.
    float shardZone = (1.0 - smoothstep(0.18, 0.62, lensDist)) * rift;
    if (shardZone > 0.003 && lensDist > 1.0e-4) {
        float ang = atan(fromLens.y, fromLens.x);
        float sector = floor(ang / SHARD_WIDTH);
        float shardGate = step(0.35, efxHash(vec2(sector, seed * 3.1)));
        float mirrored = 2.0 * (sector * SHARD_WIDTH + SHARD_WIDTH * 0.5) - ang;
        vec2 mirrorP = lens + vec2(cos(mirrored), sin(mirrored)) * lensDist;
        vec2 mirrorUv = (mirrorP / vec2(aspect, 1.0) + 1.0) * 0.5;
        uv = mix(uv, clamp(mirrorUv, vec2(0.001), vec2(0.999)), shardZone * shardGate * 0.65);
    }
    uv = clamp(uv, vec2(0.001), vec2(0.999));

    // Chromatic tear along the displacement axis (~15 px at 1080p fully glitched); ambient
    // rift corruption feeds a smaller share so idle proximity stays a simmer (~4 px).
    // v4 — CHROMATIC SEAM FRINGES: in the seam annulus the split re-aims RADIALLY (the
    // prism edge of the fake lens) and swells with the refraction's own raggedness, so
    // the fringes sit exactly on the torn rim rather than smearing the whole frame.
    // Iteration 2: 0.006 → 0.008 — with the ambient cap (RiftAmount ≤ 0.6 at the
    // source) the fringe peaked at ~4 px @1080p, too timid for a still frame on the
    // llvmpipe VM; ~5–6 px reads without wrecking edge legibility.
    vec2 chromaDir = mix(vec2(1.0, 0.35), axisUv, clamp(seamZone * 1.5, 0.0, 1.0));
    float seamFringe = seamZone * seamRag * 0.008;
    vec3 color = efxChroma(DiffuseSampler0, uv, chromaDir,
            g * 0.008 + rift * 0.0035 + seamFringe);

    // v2 — TIME-JITTER ECHO: the faked previous-frame ghost (see header). The offset
    // re-rolls at ~8 Hz; max() keeps the ghost additive-bright, like an undecayed phosphor
    // copy of a frame that never got replaced.
    float echoAmt = corr * 0.16;
    if (echoAmt > 0.003) {
        float echoSeed = floor(Time * 8.0);
        vec2 echoOff = vec2(efxHash(vec2(echoSeed, 4.7)) - 0.5,
                efxHash(vec2(echoSeed * 1.7, 9.2)) - 0.5) * 0.018;
        vec3 echo = texture(DiffuseSampler0, clamp(uv + echoOff, vec2(0.001), vec2(0.999))).rgb;
        color = mix(color, max(color, echo), echoAmt);
    }

    // 2-frame invert pops once the glitch is violent — TRANSITION envelope only (g), never
    // the ambient rift feed: standing near a tear must not strobe (R11 spirit).
    float pop = step(0.9, efxHash(vec2(seed, 17.3))) * step(0.55, g);
    color = mix(color, vec3(1.0) - color, pop);

    // Scanline shimmer (the ambient rift contributes a half share).
    color *= 1.0 - 0.10 * max(g, rift * 0.5) * (0.5 + 0.5 * sin(texCoord.y * 420.0 + Time * 28.0));

    // Fade-to-black iris (contract unchanged): the black front closes from the screen edges
    // toward the center; pixels just inside the front bleed violet. At f=1 the whole frame
    // is exactly black (front radius is past the center).
    vec2 q = texCoord * 2.0 - 1.0;
    float r = length(q * vec2(1.15, 1.0));
    float front = 1.62 - f * 2.1;
    float black = smoothstep(front, front + 0.28, r);
    float bleed = smoothstep(front - 0.30, front, r) * (1.0 - black);
    vec3 violet = vec3(0.30, 0.08, 0.52) * (0.35 + 0.65 * efxNoise(q * 5.0 + vec2(Time, -Time)));
    color = mix(color, color * 0.35 + violet, bleed * min(1.0, f * 2.0));
    color *= 1.0 - black;

    // v2 banding guard: violet bleed / echo / shard-zone gradients — temporal ±1 LSB dither
    // (scaled up while the pass is actually doing something). Polish 2: multiplied by
    // (1 − black) so the f = 1 portal hold stays EXACTLY black (frozen R13 contract) —
    // the bleed gradient still gets dithered because black < 1 there.
    color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * (0.5 + corr + f)) * (1.0 - black);

    fragColor = vec4(color, 1.0);
}
