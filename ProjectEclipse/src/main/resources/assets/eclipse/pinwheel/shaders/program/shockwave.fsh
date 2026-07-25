// eclipse:shockwave v3 — crisp expanding refraction ring (GLITCH team pass; v2 was
// VFXPOLISH-1's eased expansion + luma crest over the P2 R8 original). Renders the
// event-start submerge loop AND every world shockwave (eclipse:fx/shockwave →
// EclipseFxState.startShockwave: intro v3 storm burst, expansion structure slams, wand,
// altar milestones). Fed per frame by client.WaveOverlay.
//
// Uniforms (frozen §3.3, UNCHANGED — every v3 behavior derives from them):
//   ShockCenter   vec2 — ring origin in NDC ((0,0) for the submerge; world shockwaves pass
//                        the CPU-projected origin, parked at (10,10) behind the camera).
//   ShockProgress      — ring expansion 0..1 (loops during the submerge phases).
//   ShockStrength      — 0..~1 refraction/chroma amplitude. WaveOverlay scales it ×0.6
//                        under reducedFx, which also keeps big events below the ≥0.75
//                        double-pulse gate.
//
// v3 recipe:
//   • CRISP FRONT: one antisymmetric push/pull lobe at the blast front (the old broad
//     6-period sine train read as ripples, not a shock) + a short trailing wake INSIDE,
//   • chromatic fringe hugging the crisp front (tighter than v2),
//   • INNER PRESSURE DIMPLE: a band behind the front pulls the image back toward the
//     origin and dips brightness ~5% — the "air sucked out" read,
//   • DOUBLE-PULSE for big events: ShockStrength ≥ 0.75 (intro v3 1.0, wand 0.8) fires an
//     echo ring 0.16 progress behind at 45% amplitude,
//   • DISTANCE ATTENUATION: amplitude decays ~1/(1 + 0.7·expand) as the front travels —
//     bursts hard at the origin, dies like a real pressure wave (base amplitude raised
//     0.045 → 0.055 so the origin burst keeps its punch),
//   • temporal dither so the luma crest/dimple gradients cannot band on flat skies.
//
// v4 (VEIL-REPASS-1): MATERIAL-REACTIVE RING TINT — the crest's luma ride and the
// inside-the-ring desat both lean toward ShockTint, a luma-normalized (brightness
// budget unchanged) biome dust hint sampled at the blast origin by the feeder: a slam
// in a birch forest kicks a different dust than one in crimson badlands. Additive
// uniform + feeder in the same commit (the Kick/RiftCenter precedent); the submerge
// rings feed a cold slate (underwater read). Neutral (1,1,1) is a bit-exact no-op.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform vec2 ShockCenter;
uniform float ShockProgress;
uniform float ShockStrength;
uniform vec3 ShockTint;

in vec2 texCoord;

out vec4 fragColor;

// Max ring radius in aspect-corrected NDC units — reaches past the far corner of a 21:9
// frame from any onscreen origin, so a full expansion always clears the screen.
const float RING_MAX_RADIUS = 2.6;
const float PI = 3.14159265;

// One ring evaluation → x = displacement wave (signed), y = front intensity (chroma
// fringe), z = pressure-dimple mask. All terms carry the lifetime fade AND the v3 travel
// attenuation; a clamped-out progress (≤ 0 or ≥ 1) contributes nothing.
vec3 ringTerms(float dist, float progress) {
    float pr = clamp(progress, 0.0, 1.0);
    // Ease-out expansion: the front bursts outward and decelerates (VFXPOLISH-1).
    float expand = 1.0 - (1.0 - pr) * (1.0 - pr);
    float ring = dist - expand * RING_MAX_RADIUS;
    // Lifetime fade (raw progress, keeps the submerge loop cadence) × travel attenuation
    // (energy spreads over the growing circumference — the v3 distance falloff).
    float fade = (1.0 - pr * pr) / (1.0 + 0.7 * expand);
    // Crisp front: ONE antisymmetric push/pull lobe (sin clamped to its first period) under
    // a tight envelope…
    float phase = clamp(ring * PI * 9.0, -PI, PI);
    float wave = sin(phase) * exp(-abs(ring) * 16.0);
    // …plus a short trailing wake strictly INSIDE the ring (cutoff at exactly −1/9, a sine
    // zero, so the seam is continuous).
    wave += sin(ring * PI * 9.0) * exp(ring * 9.0) * step(ring, -1.0 / 9.0) * 0.35;
    float front = exp(-abs(ring) * 20.0);
    // Pressure dimple: the −0.34..0 band just behind the front.
    float dimple = smoothstep(-0.34, -0.10, ring) * (1.0 - smoothstep(-0.10, 0.0, ring));
    return vec3(wave, front, dimple) * fade;
}

void main() {
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
    float aspect = screenSize.x / max(screenSize.y, 1.0);

    // Aspect-corrected offset from the ring origin (NDC-y units, matches RING_MAX_RADIUS).
    vec2 delta = (texCoord * 2.0 - 1.0 - ShockCenter) * vec2(aspect, 1.0);
    float dist = length(delta);
    vec2 dir = dist > 1.0e-4 ? delta / dist : vec2(0.0);
    // dir lives in aspect space; displacements convert back to UV units through this.
    vec2 uvDir = vec2(dir.x / aspect, dir.y);

    float strength = clamp(ShockStrength, 0.0, 1.0);
    vec3 terms = ringTerms(dist, ShockProgress);
    // Double-pulse: big events fire an echo ring 0.16 progress behind at 45% amplitude.
    // The smoothstep gate keeps ≤0.72 strengths (and every ×0.6 reducedFx feed) single-
    // pulse; the birth ramp suppresses the degenerate radius-0 ring while the echo's
    // progress is still negative (no pulsing dot at the origin).
    float echoGate = smoothstep(0.72, 0.78, strength) * 0.45;
    float echoProgress = ShockProgress - 0.16;
    terms += ringTerms(dist, echoProgress) * (echoGate * smoothstep(0.0, 0.05, echoProgress));

    // Refraction (v3 base 0.055 — see header) + the dimple's inward pull.
    vec2 uv = texCoord + uvDir * (terms.x * ShockStrength * 0.055);
    uv -= uvDir * (terms.z * ShockStrength * 0.014);
    uv = clamp(uv, vec2(0.001), vec2(0.999));

    // Chromatic fringe hugging the crisp ring front.
    vec3 color = efxChroma(DiffuseSampler0, uv, uvDir, terms.y * ShockStrength * 0.022);

    // Day readability: the luma crest riding the wave (VFXPOLISH-1, ≤ ~10%)… v4: the
    // crest leans 40% toward the biome dust tint (luma-normalized, so the ≤10% budget
    // is untouched — the crest picks up COLOR, not extra brightness).
    color *= 1.0 + terms.x * strength * 0.10 * mix(vec3(1.0), ShockTint, 0.4);
    // …and the v3 pressure dip behind the front (≤ ~5%).
    color *= 1.0 - terms.z * strength * 0.05;

    // 8% desaturation inside the LEAD ring (frozen "pressure" read; main pulse only, so the
    // echo never double-desaturates). v4: the gray target leans 30% toward the dust tint —
    // the "air full of kicked-up material" hint.
    float pr = clamp(ShockProgress, 0.0, 1.0);
    float ring = dist - (1.0 - (1.0 - pr) * (1.0 - pr)) * RING_MAX_RADIUS;
    float inside = (1.0 - smoothstep(-0.08, 0.08, ring)) * strength;
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(color, vec3(luma) * mix(vec3(1.0), ShockTint, 0.3), inside * 0.08);

    // v3 banding guard: crest/dimple brightness gradients over flat skies — temporal ±1 LSB
    // dither (progress is the only animated uniform, so it supplies the jitter). Polish 2:
    // gated on local ring activity, so pixels the wave is not touching (and the whole frame
    // when the origin is parked behind the camera) stay bit-identical.
    float activity = smoothstep(0.0, 0.02, abs(terms.x) + terms.y + terms.z + inside);
    color += vec3(efxDither(gl_FragCoord.xy, fract(ShockProgress * 13.0)) * (0.5 + strength)) * activity;

    fragColor = vec4(color, 1.0);
}
