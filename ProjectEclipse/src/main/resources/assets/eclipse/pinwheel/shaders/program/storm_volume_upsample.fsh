// eclipse:storm_volume_upsample — F-030a stage 2 of the storm_volume pipeline: joint
// bilateral upsample of the half-resolution raymarch target (`volume_half`, RGBA16F —
// premultiplied in-scatter rgb + transmittance a) against the FULL-resolution depth
// buffer, then the premultiplied-over composite the old single-pass shader did:
// scene · transmittance + in-scatter.
//
// Weighting: the 4 half-res texels around this pixel get bilinear weights × a depth
// similarity term comparing the full-res pixel's linear view depth against the depth
// at each half-texel CENTER (exactly what the march saw there — the march clamps its
// ray to that depth sample, so agreeing depths mean an agreeing volume result). At
// silhouette edges (storm rim against terrain) the mismatched taps drop out and the
// edge stays pixel-crisp instead of haloing — the classic half-res fog artifact.
#include veil:space_helper

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform sampler2D VolumeSampler;
uniform float Strength;
uniform float Visibility;

in vec2 texCoord;

out vec4 fragColor;

// Depth-similarity falloff per block of linear-depth disagreement: 3 blocks off →
// weight ~0.5. Soft on purpose — the volume is fog, and an over-sharp kernel prints
// the half-res texel grid back into smooth gradients.
const float DEPTH_SHARPNESS = 0.35;
// Linear-depth clamp so sky (depth 1.0) stays finite and all-sky neighborhoods keep
// their bilinear behavior instead of dividing by garbage.
const float Z_CLAMP = 60000.0;

// Standard perspective inverse: NDC depth → linear view-space distance along -Z.
float linearZ(float depth) {
    float ndc = depth * 2.0 - 1.0;
    float denom = ndc + VeilCamera.ProjMat[2][2];
    if (abs(denom) < 1.0e-6) {
        return Z_CLAMP;
    }
    return clamp(abs(VeilCamera.ProjMat[3][2] / denom), 0.0, Z_CLAMP);
}

void main() {
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    float strength = clamp(Strength, 0.0, 1.0) * clamp(Visibility, 0.0, 1.0);
    if (strength <= 0.004) {
        fragColor = vec4(scene, 1.0); // idle frame: pass the scene through untouched
        return;
    }

    ivec2 halfSize = textureSize(VolumeSampler, 0);
    vec2 halfTexel = 1.0 / vec2(halfSize);
    // This pixel in half-res texel space; base = the top-left tap of the 2×2 footprint.
    vec2 p = texCoord * vec2(halfSize) - 0.5;
    vec2 base = floor(p);
    vec2 f = p - base;
    float refZ = linearZ(texture(DiffuseDepthSampler, texCoord).r);

    vec4 sum = vec4(0.0);
    float wsum = 0.0;
    for (int j = 0; j <= 1; j++) {
        for (int i = 0; i <= 1; i++) {
            ivec2 tc = clamp(ivec2(base) + ivec2(i, j), ivec2(0), halfSize - ivec2(1));
            vec4 tap = texelFetch(VolumeSampler, tc, 0);
            // Depth the march saw at this tap: the full-res buffer sampled at the
            // half-texel center (see the march shader's depth-clamp comment).
            vec2 tapUv = (vec2(tc) + 0.5) * halfTexel;
            float tapZ = linearZ(texture(DiffuseDepthSampler, tapUv).r);
            float bilinear = (i == 0 ? 1.0 - f.x : f.x) * (j == 0 ? 1.0 - f.y : f.y);
            float similarity = 1.0 / (1.0 + abs(tapZ - refZ) * DEPTH_SHARPNESS);
            float w = bilinear * similarity + 1.0e-5;
            sum += tap * w;
            wsum += w;
        }
    }
    vec4 vol = sum / wsum;

    // Premultiplied over: in-scatter is already weighted by per-step opacity.
    fragColor = vec4(scene * vol.a + vol.rgb, 1.0);
}
