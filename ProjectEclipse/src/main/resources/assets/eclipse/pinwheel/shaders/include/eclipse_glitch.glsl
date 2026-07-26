// eclipse:eclipse_glitch — shared helpers for the GLITCHZONE post shaders (glitch_outline,
// glitch_datamosh, glitch_scanlines, glitch_invert, glitch_void). Owned by the glitchzone
// feature; eclipse_common stays untouched (its efx* helpers are still used alongside).
// Buffer-free by design: depth linearization takes near/far as parameters so only the .fsh
// files that actually need the camera pull in veil:space_helper (VeilCamera block).
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
