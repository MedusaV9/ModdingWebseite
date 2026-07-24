// eclipse:eclipse_common — shared procedural helpers for every Eclipse post shader
// (P2 §3.3, FROZEN names). All effects use in-shader noise: zero textures required.
// Include with:  #include eclipse:eclipse_common

// Cheap 2D hash in [0,1).
float efxHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Smooth value noise in [0,1).
float efxNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = efxHash(i);
    float b = efxHash(i + vec2(1.0, 0.0));
    float c = efxHash(i + vec2(0.0, 1.0));
    float d = efxHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Chromatic sample helper: RGB split along dir (dir in UV units scaled by amt).
vec3 efxChroma(sampler2D sam, vec2 uv, vec2 dir, float amt) {
    return vec3(
            texture(sam, uv + dir * amt).r,
            texture(sam, uv).g,
            texture(sam, uv - dir * amt).b);
}

// Scanline/datamosh block helper: rows of seed-dependent height jump sideways.
// Returns a UV OFFSET to add to uv; amt 0..1 controls gate density and shift width.
vec2 efxBlockOffset(vec2 uv, float seed, float amt) {
    float rows = mix(12.0, 40.0, efxHash(vec2(seed, 3.7)));
    float row = floor(uv.y * rows);
    float gate = step(1.0 - 0.5 * clamp(amt, 0.0, 1.0), efxHash(vec2(row, seed)));
    float shift = (efxHash(vec2(row * 1.93, seed * 2.11)) - 0.5) * 2.0;
    return vec2(shift * amt * 0.12 * gate, 0.0);
}

// Luma tone tool: shadow-crushing curve (R3). Operates on the FINAL image, so it wins
// against the user's brightness/gamma option by construction.
vec3 efxCrush(vec3 c, float amt) {
    return mix(c, pow(max(c, vec3(0.0)), vec3(1.35)) * 0.42, clamp(amt, 0.0, 1.0));
}
