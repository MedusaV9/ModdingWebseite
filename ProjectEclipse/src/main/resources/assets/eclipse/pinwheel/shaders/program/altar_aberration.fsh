// eclipse:altar_aberration — chromatic-aberration gradient around the altar (P2 R9,
// FEATURE priority). Subtle at the spawn-area boundary, strongest at the altar center:
// client.AltarAberration computes the zone strength each tick (curve (1 − d/r)² · 0.85,
// anchor eclipse:altar_center via FxAnchors, spawn fallback) and feeds the frozen
// Aberration uniform per frame with a 0.3 Hz breathing modulation baked in (flattened
// to its mean under reducedFx — the breath is a pulsing overlay, the zone read is not).
//   - radial RGB split away from the screen center, up to ~10 px at the zone center
//   - ~1% barrel distortion easing in above Aberration ≈ 0.6
//   - faint cold-violet lift so the zone reads "not normal" — never nauseating
//
// v2 (FX team GRADE): sacred-tech. On top of the core:
//   [a1] glyph-flash ghosting on level-ups — the altar zone itself reacts to your
//        ascension: a brief rotated-and-contracted violet echo of the scene blooms and
//        dies over ~0.8 s (new GlyphFlash uniform, fed by the binder watching the same
//        skill-level state as LevelUpOverlay; respects levelUpCelebrations + reducedFx).
//   [a2] resonance rings — slow concentric interference rings crawling toward the
//        altar's screen center (±2% luminance, donut-masked so the aim point and the
//        screen edges stay clean): the zone hums.
//   [a3] two-tap prismatic split — a half-strength second sample per channel turns the
//        hard RGB double-image into a smooth spectral smear at high strengths.
// v2 additive uniforms (fed by the same client.AltarAberration feeder, same commit):
//   Time       — seconds on the feeder's 100 s wrap clock (shared with the breath)
//   GlyphFlash — 0..1 level-up flash envelope (0 unless a flash is live)
//   Detail     — 1 normal, 0 under reducedFx: gates the rings (the split/barrel core
//                is zone feedback and stays; the flash is already CPU-gated)
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Aberration;
uniform float Time;
uniform float GlyphFlash;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    float a = clamp(Aberration, 0.0, 1.0);
    // Perceptual response a·(2−a) (ease-out quad): the CPU zone curve is already quadratic
    // ((1 − d/r)² · 0.85), so a linear shader response left the outer half of the zone under
    // ~1 px of split — invisible. The ease-out doubles the fringe at the zone rim (still
    // subtle) while the center barely moves (~10 px max split preserved).
    float aResp = a * (2.0 - a);
    vec2 center = vec2(0.5);
    vec2 delta = texCoord - center;
    float r2 = dot(delta, delta);

    // Barrel distortion: off below ~0.55, ~1% edge pull at full strength.
    // Gated on the RAW amount — it must stay a near-the-altar-only feature.
    float barrel = smoothstep(0.55, 0.7, a) * 0.03;
    vec2 uv = center + delta * (1.0 - barrel * r2);

    // [a3] Radial RGB split from the screen center (grows outward; ~10 px at the screen
    // edge). Two taps per split channel — full and half strength — so the fringe is a
    // prismatic smear instead of a hard double-image where the split gets wide. The
    // 0.0145/0.35 pair keeps the smear CENTROID at the VFXPOLISH-1 tuned reach
    // (0.0145 · (0.65 + 0.35·0.5) ≈ 0.012): rim visibility and the ~10 px cap both hold.
    float split = 0.0145 * aResp;
    vec3 color;
    color.r = mix(texture(DiffuseSampler0, uv + delta * split).r,
            texture(DiffuseSampler0, uv + delta * split * 0.5).r, 0.35);
    color.g = texture(DiffuseSampler0, uv).g;
    color.b = mix(texture(DiffuseSampler0, uv - delta * split).b,
            texture(DiffuseSampler0, uv - delta * split * 0.5).b, 0.35);

    // [a2] Resonance rings: concentric interference crawling slowly INWARD (sacred hum,
    // pointing at the altar). Donut mask keeps the crosshair area and screen edges
    // clean; ±2% luminance at zone center, dead under reducedFx. A live glyph flash
    // surges the rings (amplitude AND floor) so the two layers read as one mechanism —
    // even at the zone rim, a level-up briefly summons the hum.
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
    float aspect = screenSize.x / max(screenSize.y, 1.0);
    float rr = length(delta * vec2(aspect, 1.0));
    float gf = clamp(GlyphFlash, 0.0, 1.0);
    float ringWave = sin(rr * 42.0 - Time * 1.3);
    float ringMask = smoothstep(0.08, 0.25, rr) * (1.0 - smoothstep(0.45, 0.72, rr));
    color *= 1.0 + ringWave * (0.02 + 0.03 * gf) * ringMask * max(aResp, gf * 0.5) * Detail;

    // [a1] Glyph-flash ghosting: a rotated (~3°) and contracted (~4.5%) violet echo of
    // the scene, luma-weighted, plus a brief 5% lift — the zone flashes WITH the
    // level-up glyph. The envelope pops on and eases out CPU-side (~0.8 s).
    if (gf > 0.001) {
        float ang = 0.05 * gf;
        float cs = cos(ang);
        float sn = sin(ang);
        vec2 echoDelta = mat2(cs, -sn, sn, cs) * delta * (1.0 - 0.045 * gf);
        vec3 echo = texture(DiffuseSampler0, clamp(center + echoDelta, vec2(0.0), vec2(1.0))).rgb;
        float echoLuma = dot(echo, vec3(0.299, 0.587, 0.114));
        color += vec3(0.68, 0.42, 1.05) * echoLuma * gf * 0.28;
        color *= 1.0 + 0.05 * gf;
    }

    // Faint cold-violet lift toward the zone center — "something is wrong with this place".
    // Rides the eased response so the tint fades in together with the fringe at the rim.
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 violet = mix(color, vec3(luma) * vec3(0.92, 0.85, 1.08), 0.25);
    color = mix(color, violet, aResp * 0.4);

    // Output dither (±0.5/255): the ring modulation and violet lift both write long
    // smooth gradients; slow reseed keeps the dither itself invisible.
    color += (efxHash(texCoord * screenSize + vec2(mod(floor(Time * 4.0), 89.0))) - 0.5) * (1.0 / 255.0);

    fragColor = vec4(color, 1.0);
}
