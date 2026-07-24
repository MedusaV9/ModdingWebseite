// eclipse:shockwave — expanding refractive shockwave ring (P2 R8, FEATURE priority, W5).
// Replaces the v1 flat tiled wave texture for the event-start submerge AND renders every
// world shockwave (eclipse:fx/shockwave → EclipseFxState.startShockwave: intro v3 storm
// burst, expansion structure slams). Fed per frame by client.WaveOverlay:
//
// Uniforms (frozen §3.3):
//   ShockCenter   vec2 — ring origin in NDC. (0,0) = screen center for the submerge
//                        immersion; world shockwaves pass the CPU-projected origin
//                        (SunTracker.worldToNdc — may sit far offscreen when behind the
//                        camera, in which case the falloff kills the effect naturally).
//   ShockProgress      — ring expansion 0..1 (loops during the submerge phases).
//   ShockStrength      — 0..~1 refraction/chroma amplitude.
//
// Refraction per the frozen R8 design:
//   uv' = uv + dir · sin((d − ShockProgress·R)·π·6) · falloff · ShockStrength
// plus a chromatic split on the ring front and an 8% desaturation inside the ring.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform vec2 ShockCenter;
uniform float ShockProgress;
uniform float ShockStrength;

in vec2 texCoord;

out vec4 fragColor;

// Max ring radius in aspect-corrected NDC units — reaches past the far corner of a 21:9
// frame from any onscreen origin, so a full expansion always clears the screen.
const float RING_MAX_RADIUS = 2.6;

void main() {
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
    float aspect = screenSize.x / max(screenSize.y, 1.0);

    // Aspect-corrected offset from the ring origin (NDC-y units, matches RING_MAX_RADIUS).
    vec2 delta = (texCoord * 2.0 - 1.0 - ShockCenter) * vec2(aspect, 1.0);
    float dist = length(delta);
    vec2 dir = dist > 1.0e-4 ? delta / dist : vec2(0.0);
    // dir lives in aspect space; displacements convert back to UV units through this.
    vec2 uvDir = vec2(dir.x / aspect, dir.y);

    // Ease-out expansion: a blast front bursts outward and decelerates. The previous
    // linear ShockProgress·R crawl read mechanical, especially on the 45-tick submerge
    // loop. Falloff/front strengths stay on the RAW progress so lifetime is unchanged.
    float expand = 1.0 - (1.0 - ShockProgress) * (1.0 - ShockProgress);
    float ring = dist - expand * RING_MAX_RADIUS;
    // Strongest at the ring front, dying off as the expansion completes (so looping submerge
    // rings breathe: fire at the center, fade before the next one).
    float falloff = exp(-abs(ring) * 7.0) * (1.0 - ShockProgress * ShockProgress);
    float wave = sin(ring * 3.14159265 * 6.0);
    vec2 uv = clamp(texCoord + uvDir * (wave * falloff * ShockStrength * 0.045),
            vec2(0.001), vec2(0.999));

    // Chromatic split hugging the ring front.
    float front = exp(-abs(ring) * 12.0) * (1.0 - ShockProgress);
    vec3 color = efxChroma(DiffuseSampler0, uv, uvDir, front * ShockStrength * 0.02);

    // Day readability: pure refraction vanishes over flat bright regions (noon sky), so a
    // faint brightness crest/trough rides the wave itself — ≤ ~10% at full strength and
    // dying with the same falloff, so night/dusk scenes keep their subtle glassy read.
    color *= 1.0 + wave * falloff * clamp(ShockStrength, 0.0, 1.0) * 0.10;

    // 8% desaturation inside the ring (the "pressure" read of the frozen design).
    float inside = (1.0 - smoothstep(-0.08, 0.08, ring)) * clamp(ShockStrength, 0.0, 1.0);
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(color, vec3(luma), inside * 0.08);

    fragColor = vec4(color, 1.0);
}
