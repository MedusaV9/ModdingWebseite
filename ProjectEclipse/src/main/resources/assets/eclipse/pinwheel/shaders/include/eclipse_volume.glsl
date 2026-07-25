// eclipse:eclipse_volume — shared 3D noise helpers for the STORM-VOL volumetric
// raymarcher (storm_volume.fsh). Deliberately a SEPARATE include: eclipse_common.glsl is
// shared by every post shader and owned by parallel work — nothing here shadows or
// redefines its 2D helpers (ev* prefix vs efx*).
// Include with:  #include eclipse:eclipse_volume

// Cheap 3D hash in [0,1) — the efxHash sin-dot pattern lifted to 3D. Inputs stay small
// (raymarch space is storm-radius-normalized, freq < ~40) so the sin argument remains
// well-conditioned in fp32.
float evHash3(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

// Smooth trilinear 3D value noise in [0,1) — the GLSL twin of the CPU-side
// StormWallRenderer.fvnoise3 (8 lattice hashes + smoothstep fades).
float evNoise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    float n000 = evHash3(i);
    float n100 = evHash3(i + vec3(1.0, 0.0, 0.0));
    float n010 = evHash3(i + vec3(0.0, 1.0, 0.0));
    float n110 = evHash3(i + vec3(1.0, 1.0, 0.0));
    float n001 = evHash3(i + vec3(0.0, 0.0, 1.0));
    float n101 = evHash3(i + vec3(1.0, 0.0, 1.0));
    float n011 = evHash3(i + vec3(0.0, 1.0, 1.0));
    float n111 = evHash3(i + vec3(1.0, 1.0, 1.0));
    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
            mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

// 5-octave fBm in [0,1) — the full-detail density workhorse (camera rays). Each octave
// is offset AND frequency-doubled so lattice planes never line up across octaves.
float evFbm5(vec3 p) {
    float sum = evNoise3(p);
    sum += 0.5 * evNoise3(p * 2.03 + vec3(19.7, 7.3, 5.1));
    sum += 0.25 * evNoise3(p * 4.11 + vec3(5.9, 27.1, 11.7));
    sum += 0.125 * evNoise3(p * 8.19 + vec3(13.3, 3.1, 31.9));
    sum += 0.0625 * evNoise3(p * 16.4 + vec3(7.7, 17.9, 23.3));
    return sum * (1.0 / 1.9375);
}

// 3-octave fBm in [0,1) — the cheap tier for self-shadow rays and warp fields.
float evFbm3(vec3 p) {
    float sum = evNoise3(p);
    sum += 0.5 * evNoise3(p * 2.03 + vec3(19.7, 7.3, 5.1));
    sum += 0.25 * evNoise3(p * 4.11 + vec3(5.9, 27.1, 11.7));
    return sum * (1.0 / 1.75);
}

// Curl-ish domain warp: three decorrelated low-frequency noise fields build an offset
// vector that rotates slowly in time, so the fBm lobes billow and fold into each other
// (cumulus cauliflower) instead of streaming along the lattice like plasma.
vec3 evCurlWarp(vec3 p, float t) {
    float n1 = evNoise3(p + vec3(0.0, t * 0.11, 0.0));
    float n2 = evNoise3(p + vec3(5.2, 1.3, -3.1) + vec3(-t * 0.07, 0.0, 0.0));
    float n3 = evNoise3(p + vec3(-1.7, 9.2, 4.8) + vec3(0.0, 0.0, t * 0.09));
    return (vec3(n1, n2, n3) - 0.5) * 1.6;
}

// Henyey–Greenstein phase function (normalized by 1/4π) — forward-scatter silver lining.
float evHgPhase(float mu, float g) {
    float g2 = g * g;
    return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * mu, 1.5) * 0.0795775;
}
