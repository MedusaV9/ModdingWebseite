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
