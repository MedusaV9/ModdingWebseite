// eclipse:black_hole — F-056 black-hole finale post pass (FEATURE priority; registered
// by client.credits.CreditsBlackHolePostFx, driven by CreditsSkyFx.holeAmount).
// Layers, all scaled by Strength so the pass is a no-op at 0:
//   [b1] radial UV pull — every pixel is dragged toward the hole center (gravitational
//        lensing read; strongest inside ~35% screen radius, falls off smoothly)
//   [b2] swirl — the pulled UVs additionally rotate around the center (the accretion
//        drag), angle falling off with distance so the far frame stays stable
//   [b3] event horizon — pixels inside the core radius drain to pure black with a soft
//        edge; a thin warm-violet photon ring rides the rim (additive, Detail-gated)
//   [b4] desaturation + darkening — "Farben ergrauen": the whole frame drains toward
//        gray then black as Strength climbs (the slow all-black exit is the fade
//        overlay's job; this pass gets ~80% of the way there)
// Uniforms (fed per frame by CreditsBlackHolePostFx, no allocations):
//   Strength — eased 0..1 hole amount (CreditsSkyFx)
//   Hole     — hole center in UV space (SunTracker.worldToNdc remapped; offscreen-safe)
//   Aspect   — viewport width / height (keeps the swirl/ring circular)
//   Time     — pause-frozen seconds (subtle ring shimmer)
//   Detail   — 1 normal, 0 under reducedFx (drops the shimmer + photon ring)
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Strength;
uniform vec2 Hole;
uniform float Aspect;
uniform float Time;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

const vec3 LUMA_W = vec3(0.299, 0.587, 0.114);

void main() {
    float strength = clamp(Strength, 0.0, 1.0);
    if (strength <= 0.001) {
        fragColor = vec4(texture(DiffuseSampler0, texCoord).rgb, 1.0);
        return;
    }

    // Aspect-corrected frame so distances read circular on screen.
    vec2 toHole = (texCoord - Hole) * vec2(Aspect, 1.0);
    float dist = length(toHole);
    vec2 dir = toHole / max(dist, 1.0e-4);

    // [b1] radial pull: strongest near the hole, gone by ~65% of the screen.
    float pull = smoothstep(0.65, 0.05, dist) * 0.16 * strength;
    // [b2] swirl: rotation angle decays with distance (accretion drag).
    float swirl = smoothstep(0.55, 0.0, dist) * 1.35 * strength;
    float cs = cos(swirl);
    float sn = sin(swirl);
    vec2 swirled = vec2(toHole.x * cs - toHole.y * sn, toHole.x * sn + toHole.y * cs);
    vec2 warpedUv = Hole + (swirled - dir * pull * dist) / vec2(Aspect, 1.0);
    vec3 color = texture(DiffuseSampler0, clamp(warpedUv, vec2(0.001), vec2(0.999))).rgb;

    // [b4] desaturate + darken: the world grays out, then dims (never fully black here —
    // the sustained fade owns the final exit; 0.22 floor keeps the ring readable).
    float luma = dot(color, LUMA_W);
    color = mix(color, vec3(luma), 0.85 * strength);
    color *= 1.0 - 0.55 * strength;

    // [b3] event horizon: core drains to black; a thin photon ring rides the rim.
    float core = 0.06 + 0.10 * strength;
    float horizon = smoothstep(core * 1.6, core * 0.7, dist);
    color = mix(color, vec3(0.0), horizon * strength);
    float ringShimmer = 0.75 + 0.25 * efxNoise(vec2(atan(toHole.y, toHole.x) * 3.0, Time * 0.6));
    float ring = smoothstep(core * 2.2, core * 1.55, dist)
            * (1.0 - smoothstep(core * 1.55, core * 1.0, dist));
    color += vec3(0.85, 0.62, 1.05) * ring * ringShimmer * 0.6 * strength * Detail;

    // Output dither: the desaturated dark range bands at 8 bits otherwise.
    vec2 screenPx = texCoord * vec2(textureSize(DiffuseSampler0, 0));
    color += (efxHash(screenPx + vec2(mod(floor(Time * 4.0), 97.0))) - 0.5) * (1.0 / 255.0);

    fragColor = vec4(color, 1.0);
}
