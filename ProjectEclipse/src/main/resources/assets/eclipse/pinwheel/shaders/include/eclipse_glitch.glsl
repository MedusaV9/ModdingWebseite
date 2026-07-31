// eclipse:eclipse_glitch — shared helpers for the GLITCHZONE post shaders (glitch_outline,
// glitch_datamosh, glitch_scanlines, glitch_invert, glitch_void). Owned by the glitchzone
// feature; eclipse_common stays untouched (its efx* helpers are still used alongside).
// Buffer-free by design: depth linearization takes near/far as parameters so only the .fsh
// files that actually need the camera pull in veil:space_helper (VeilCamera block) -- that
// holds for the wave-13 additions too (hardening, fBm, the void lattice all take plain
// floats/vectors).
// Include with:  #include eclipse:eclipse_glitch

// Raw 0..1 depth-buffer sample -> world-space view distance in blocks (standard
// perspective inverse; pass VeilCamera.NearPlane / VeilCamera.FarPlane).
float gzLinearDepth(float depthSample, float near, float far) {
    float z = depthSample * 2.0 - 1.0;
    return 2.0 * near * far / (far + near - z * (far - near));
}

// Rec.601 luma (matches the efxCrush/storm_interior luma convention).
float gzLuma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

// Hue rotation in YIQ space. NaN-safe: the I/Q chroma plane is rotated with a plain 2x2
// rotation (no atan), so gray pixels (chroma 0) stay exactly gray for any angle.
vec3 gzHueRotate(vec3 color, float angle) {
    const mat3 toYiq = mat3(
            0.299, 0.596, 0.211,
            0.587, -0.274, -0.523,
            0.114, -0.322, 0.312);
    const mat3 fromYiq = mat3(
            1.0, 1.0, 1.0,
            0.956, -0.272, -1.106,
            0.621, -0.647, 1.703);
    vec3 yiq = toYiq * color;
    float cs = cos(angle);
    float sn = sin(angle);
    yiq.yz = mat2(cs, sn, -sn, cs) * yiq.yz;
    return fromYiq * yiq;
}

// Uniform colour quantization to `levels` steps per channel (posterization).
vec3 gzPosterize(vec3 color, float levels) {
    return floor(color * levels + 0.5) / max(levels, 1.0);
}

// --- degenerate-depth hardening (A0 session-0731 heuristic) ------------------------------
// A raw depth sample of EXACTLY 0.0 can never come from rendered geometry -- that would be
// ON the near plane. A depth attachment that never received its blit reads flat 0.0, which
// is not merely a cosmetic problem for the edge passes: all five reconstruction taps then
// land on the same view-space point, cross() becomes the zero vector and normalize()
// returns NaN, which survives every later clamp and paints the whole frame. Multiply every
// depth-DERIVED term by this and the pass degrades to its colour-only layers instead.
float gzDepthValid(float depthSample) {
    return step(1.0e-7, depthSample);
}

// normalize() that is defined for the zero vector. Used on the reconstructed view-normal
// cross products, which go degenerate on a dead depth buffer and on perfectly coplanar taps.
vec3 gzNormalizeSafe(vec3 v, vec3 fallback) {
    float len2 = dot(v, v);
    return len2 > 1.0e-12 ? v * inversesqrt(len2) : fallback;
}

// --- organic masks -------------------------------------------------------------------------
// 4-octave value-noise fBm, normalized to the same [0,1] range as efxNoise. Unrolled: the
// octave count is a hard budget (the wave-13 census caps organic masks at 4-5 octaves for
// llvmpipe), so a dynamic loop bound would only buy a branch.
float gzFbm(vec2 p) {
    return efxNoise(p) * 0.53333
            + efxNoise(p * 2.03 + vec2(11.7, 3.1)) * 0.26667
            + efxNoise(p * 4.11 + vec2(5.3, 19.9)) * 0.13333
            + efxNoise(p * 8.07 + vec2(27.1, 7.7)) * 0.06667;
}

// --- parallax void lattice (glitch_void) -----------------------------------------------------
// A 3-D star lattice sampled exactly ONE cell deep.
//
// The single-cell lookup is exact, not an approximation: the star centre is hashed into the
// middle 40% of its cell (0.5 +/- 0.2) and the halo radius is capped at 0.30, so
// 0.2 + 0.3 = 0.5 lands precisely on the cell boundary and a star can never be clipped by
// the cell it lives in. That removes the 8-neighbour search a classic 3-D starfield needs
// and puts the whole layer at ONE hash.
//
// The cell index is wrapped to a 32-cell period before hashing. efxHash is sin-based and its
// argument has to stay in the low hundreds to remain well-conditioned in fp32 (the efxDither
// note in eclipse_common is the house law here); 32 cells is far more lattice than a camera
// ever sees at once. Callers that anchor the lattice to a wrapped camera position keep the
// field seamless across that wrap by choosing a cell size whose wrap-quotient is a multiple
// of GZ_VOID_CELLS.
const float GZ_VOID_CELLS = 32.0;
const float GZ_STAR_CORE = 0.13;
const float GZ_STAR_HALO = 0.30;
/** Twinkle rate in rad/s: 4*pi/10 = one cycle per 5 s, a divisor of the 100 s Time wrap. */
const float GZ_TWINKLE_RATE = 1.25663706;

float gzHash3(vec3 cell) {
    vec3 w = mod(cell, GZ_VOID_CELLS);
    return efxHash(vec2(dot(w, vec3(1.0, 7.3, 13.1)), dot(w, vec3(17.7, 3.9, 5.1))));
}

// One parallax star layer. `density` is the share of cells that carry a star; `detail` gates
// the twinkle only (the stars themselves are the effect, not decoration, so reducedFx keeps
// a steady field). Returns an additive intensity in roughly [0,1.2].
float gzVoidStars(vec3 p, float density, float time, float detail) {
    vec3 cell = floor(p);
    float h = gzHash3(cell);
    float on = step(1.0 - density, h);
    // Three decorrelated sub-coordinates out of the one hash we already paid for.
    vec3 sub = 0.5 + (fract(h * vec3(37.1, 61.3, 97.7)) - 0.5) * 0.4;
    float d = length(p - cell - sub);
    float core = 1.0 - smoothstep(0.0, GZ_STAR_CORE, d);
    float halo = 1.0 - smoothstep(GZ_STAR_CORE, GZ_STAR_HALO, d);
    // Per-star twinkle phase from the hash, so neighbours never breathe together.
    float twinkle = 1.0 - 0.45 * detail
            * (0.5 + 0.5 * sin(time * GZ_TWINKLE_RATE + h * 39.0));
    return on * (core * core + halo * halo * 0.16)
            * (0.45 + 0.55 * fract(h * 13.7)) * twinkle;
}

// --- accent colour (F-049) -------------------------------------------------------------
// Every GLITCHZONE shader takes the uniform pair (AccentColor, AccentAmount) fed by
// client.GlitchZoneFx. AccentAmount is the "a colour was commanded" ramp: at 0 the helpers
// below return the effect's SHIPPED constant unchanged, so an uncoloured zone is bit-exact
// with the pre-F-049 build; at 1 the commanded hue owns the effect. The client eases the
// pair, so a repaint mid-zone slides.

// Hue swap that preserves how BRIGHT the effect reads: the commanded colour is rescaled to
// the shipped accent's luma before the mix. Use for accents that ARE the image (outline's
// phosphor, void's sonar, invert's seam) — a dark purple must not dim the readout.
//
// The gain is capped at HEADROOM on the brightest channel. Pure luma matching lifts a
// low-luma hue like purple by ~1.5x, which drives its blue past 1.7; the ring core then
// clips on two channels at once and the glow reads WHITE with a coloured skirt instead of
// reading purple. Capping trades a little brightness parity for keeping the hue.
const float GZ_ACCENT_HEADROOM = 1.25;

vec3 gzAccent(vec3 shipped, vec3 accent, float amount) {
    float peak = max(max(accent.r, accent.g), max(accent.b, 0.001));
    float gain = min(gzLuma(shipped) / max(gzLuma(accent), 0.001), GZ_ACCENT_HEADROOM / peak);
    return mix(shipped, accent * gain, clamp(amount, 0.0, 1.0));
}

// Multiplicative tint, exactly vec3(1.0) at amount 0: a luma-normalized accent to multiply
// an existing grade with. Use where the effect has no accent of its own and the colour is
// only allowed to lean the image (datamosh's wash, scanline phosphor, invert's negative).
vec3 gzTint(vec3 accent, float amount) {
    vec3 norm = accent / max(gzLuma(accent), 0.001);
    return mix(vec3(1.0), norm, clamp(amount, 0.0, 1.0));
}
