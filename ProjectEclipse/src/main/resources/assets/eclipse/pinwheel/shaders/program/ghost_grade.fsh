// eclipse:ghost_grade — spectral screen grade for 0-lives ghost players (P2 R18(c),
// GRADE priority, W10). Recipe frozen in the plan: 70% desaturation, cold blue-violet
// lift, 12% vignette, 1.5 px chromatic fringe, subtle 0.2 Hz breathing.
// Uniform (frozen §3.3): Ghost — the 30-tick eased 0..1 amount from EclipseFxState with
// the breathing premultiplied CPU-side by client.GhostGradeFx (the frozen uniform list is
// Ghost ONLY, so the breath rides the scalar instead of a Time uniform). Every term below
// scales with Ghost, so the grade eases in/out as one piece and is a no-op at 0.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Ghost;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    float ghost = clamp(Ghost, 0.0, 1.0);
    if (ghost <= 0.001) {
        fragColor = vec4(color, 1.0);
        return;
    }

    // 1.5 px chromatic fringe, radial from screen center (texel-accurate at any
    // resolution; the epsilon keeps normalize() defined on the exact center pixel).
    vec2 texel = 1.0 / vec2(textureSize(DiffuseSampler0, 0));
    vec2 fromCenter = texCoord - vec2(0.5);
    vec2 chromaDir = normalize(fromCenter + vec2(1.0e-5)) * texel * 1.5;
    vec3 graded = efxChroma(DiffuseSampler0, texCoord, chromaDir, ghost);

    // 70% desaturation — the world drains toward a spectral gray.
    float luma = dot(graded, vec3(0.299, 0.587, 0.114));
    graded = mix(graded, vec3(luma), 0.70 * ghost);

    // Cold blue-violet: a shadow lift (raises blacks without clipping whites)…
    vec3 lift = vec3(0.020, 0.030, 0.075) * ghost;
    graded = graded * (1.0 - lift) + lift;
    // …plus a gentle cool cast over the whole frame.
    graded *= mix(vec3(1.0), vec3(0.86, 0.92, 1.10), ghost);

    // 12% vignette (limbo.fsh falloff shape, capped at 0.12).
    float d = distance(texCoord, vec2(0.5));
    graded *= 1.0 - smoothstep(0.30, 0.85, d) * 0.12 * ghost;

    fragColor = vec4(graded, 1.0);
}
