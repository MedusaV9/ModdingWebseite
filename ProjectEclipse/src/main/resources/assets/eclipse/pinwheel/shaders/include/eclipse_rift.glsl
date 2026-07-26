// eclipse:eclipse_rift — shared helpers of the RIFT-FX volumetric tear raymarcher
// (eclipse:rift_volume). Deliberately self-contained (fresh er* names): the storm team
// owns eclipse_volume.glsl and this include must never couple to it. Value-noise fBm,
// a cheap curl-style domain warp, interleaved-gradient start dither and the rift
// palette ramp live here; the density field itself stays in rift_volume.fsh.

// --- value noise / fBm -----------------------------------------------------------

float erHash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Trilinear value noise in [0, 1].
float erNoise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = erHash(i);
    float n100 = erHash(i + vec3(1.0, 0.0, 0.0));
    float n010 = erHash(i + vec3(0.0, 1.0, 0.0));
    float n110 = erHash(i + vec3(1.0, 1.0, 0.0));
    float n001 = erHash(i + vec3(0.0, 0.0, 1.0));
    float n101 = erHash(i + vec3(1.0, 0.0, 1.0));
    float n011 = erHash(i + vec3(0.0, 1.0, 1.0));
    float n111 = erHash(i + vec3(1.0, 1.0, 1.0));
    return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
               mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// 4-octave fBm in [0, 1] — the camera-ray detail field.
float erFbm4(vec3 p) {
    float a = 0.5;
    float s = 0.0;
    for (int i = 0; i < 4; i++) {
        s += a * erNoise3(p);
        p = p * 2.03 + vec3(11.31, 7.17, 5.71);
        a *= 0.5;
    }
    return s;
}

// 2-octave fBm — the cheap field for secondary lookups (edge licks, throat wobble).
float erFbm2(vec3 p) {
    return 0.6667 * erNoise3(p) + 0.3333 * erNoise3(p * 2.03 + vec3(11.31, 7.17, 5.71));
}

// Cheap curl-flavored warp: offsets the fBm domain so octaves fold into tendrils
// instead of reading as static fog. Not a true curl — three decorrelated lobes.
vec3 erWarp(vec3 p, float time) {
    return vec3(
        erNoise3(p + vec3(0.0, time * 0.11, 0.0)) - 0.5,
        erNoise3(p + vec3(5.2, 1.3, time * 0.09)) - 0.5,
        erNoise3(p + vec3(time * 0.10, 9.1, 2.8)) - 0.5) * 1.6;
}

// Interleaved-gradient noise: per-pixel march start dither (kills shell banding).
float erDither(vec2 fragCoord, float time) {
    return fract(52.9829189
            * fract(dot(fragCoord, vec2(0.06711056, 0.00583715)))
            + fract(time * 61.803));
}

// Rift emission ramp: heat in [0, 1] (0 = outer wisp, 1 = throat core) blended through
// the tear palette (dim void → mid saturation → hot near-white core). The mid/hot pairs
// are the frozen RiftFx palettes (violet default, wax-gold backrooms).
vec3 erPalette(float heat, vec3 dimCol, vec3 midCol, vec3 hotCol) {
    vec3 c = mix(dimCol, midCol, smoothstep(0.05, 0.55, heat));
    return mix(c, hotCol, smoothstep(0.62, 0.97, heat));
}
