// eclipse:sun_halo — pure screen-space radial halo around the CPU-projected sun point
// (P2 R2 rewrite, FEATURE priority). THE misalignment fix: the old shader reconstructed a
// per-pixel world ray from Veil's veil:camera block, whose modelview deliberately strips
// view bobbing — so the halo and the sky-pass sun quad (rendered WITH bobbing) disagreed
// every frame while walking. Now veilfx.SunTracker projects the sun ONCE per frame on the
// CPU using the exact RenderLevelStageEvent matrices and feeds it here as SunScreen; the
// sky quad rotates from the same SunTracker angle, so both are locked by construction.
//
// Uniforms (frozen §3.3):
//   SunScreen    vec4 — xy = NDC pos, z = 1 when in front of camera else 0,
//                        w = sun angular radius in NDC-y units (tan(5°)·Proj[1][1])
//   HaloStrength      — 0..~1.4; grows with the eclipse (glow radius up to ~0.55 NDC),
//                        permanent-rim floor 0.15 after the intro
//   RimOnly           — 1 when the CPU probe says the sun is occluded (glow off, faint rim)
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform vec4 SunScreen;
uniform float HaloStrength;
uniform float RimOnly;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    if (SunScreen.z < 0.5 || HaloStrength <= 0.001) {
        fragColor = vec4(color, 1.0);
        return;
    }

    // Aspect-corrected distance to the sun point, in NDC-y units (matches SunScreen.w).
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
    float aspect = screenSize.x / max(screenSize.y, 1.0);
    vec2 delta = (texCoord * 2.0 - 1.0 - SunScreen.xy) * vec2(aspect, 1.0);
    float dist = length(delta);
    float sunRadius = max(SunScreen.w, 1.0e-4);

    // Occlusion: one depth sample at the sun's screen point, OR'd with the CPU RimOnly flag.
    vec2 sunUv = clamp(SunScreen.xy * 0.5 + 0.5, vec2(0.0), vec2(1.0));
    float occluded = max(clamp(RimOnly, 0.0, 1.0),
            1.0 - step(0.9999, texture(DiffuseDepthSampler, sunUv).r));

    // Tight rim hugging the disc edge (bright ring at ~the quad's silhouette).
    float rim = smoothstep(sunRadius * 1.15, sunRadius * 0.95, dist)
            * (1.0 - smoothstep(sunRadius * 0.95, sunRadius * 0.55, dist) * 0.35);

    // Wide glow whose radius grows with HaloStrength (eclipse boost up to ~0.55 NDC).
    float glowRadius = 0.12 + 0.43 * clamp((HaloStrength - 0.15) / 1.05, 0.0, 1.0);
    float glow = exp(-dist / glowRadius * 3.0);

    // Sky pixels take the full effect; solid geometry only catches a soft 20% spill.
    float spill = mix(0.2, 1.0, step(0.9999, texture(DiffuseDepthSampler, texCoord).r));

    float rimVis = mix(1.0, 0.35, occluded);           // occluded: faint rim silhouette
    float glowVis = 1.0 - occluded;                    // occluded: no fullscreen glow
    float halo = (rim * 0.9 * rimVis + glow * 0.85 * glowVis) * HaloStrength * spill;

    color += vec3(0.62, 0.24, 1.0) * halo;
    fragColor = vec4(color, 1.0);
}
