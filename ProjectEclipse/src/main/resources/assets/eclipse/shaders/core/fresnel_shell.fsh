#version 330 core

// A0 fresnel_shell — force-field look on a plain Billboard quad, no texture needed.
// The quad is shaded as a sphere impostor (z = sqrt(1 - r^2) from the UVs): facing
// area stays near-transparent (FaceAlpha), the silhouette edge glows with a fresnel
// ramp, and wherever the shell passes near world geometry a SceneDepth seam highlight
// lights up (the official Photon force-field tutorial recipe). RimHDRColor.rgb *
// RimHDRColor.a feeds bloom on the rim/seam only, so the face never blooms.
//
// Degenerate-scene-sampler hardening: if the scene depth copy is dead (raw sample
// exactly 0.0, see A0_SHADER_FOUNDATION.md §7) or SceneDepthValid is set to 0.0,
// the seam term is dropped (0.0) instead of glowing at the bogus near-plane
// distance — the fresnel rim and face are unaffected and keep the design intact.

#moj_import <fog.glsl>

uniform sampler2D SamplerSceneDepth;

uniform mat4 U_InverseProjectionMatrix;
uniform vec4 U_ViewPort;

uniform vec4 ColorModulator;
uniform float FogStart;
uniform float FogEnd;
uniform vec4 FogColor;
uniform float DiscardThreshold;
uniform vec4 ShellColor;
uniform vec4 RimHDRColor;
uniform float FresnelPower;
uniform float FaceAlpha;
uniform float IntersectWidth;
uniform float SceneDepthValid;

in float vertexDistance;
in vec2 texCoord0;
in vec4 vertexColor;
in float viewZ;

out vec4 fragColor;

float sceneViewZFromDepth(float depth, vec2 screenUV) {
    vec4 ndc = vec4(screenUV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = U_InverseProjectionMatrix * ndc;
    return -view.z / view.w;
}

// Geometry-intersection seam; 0.0 (= no seam) whenever the scene depth is unusable.
float seamTerm(vec2 screenUV) {
    if (SceneDepthValid < 0.5) {
        return 0.0;
    }
    float depth = texture(SamplerSceneDepth, screenUV).r;
    if (depth <= 0.0) {
        return 0.0;
    }
    float seam = 1.0 - clamp(abs(sceneViewZFromDepth(depth, screenUV) - viewZ)
                             / max(IntersectWidth, 1.0e-4), 0.0, 1.0);
    return seam * seam;
}

void main() {
    // Sphere impostor from the quad UVs: p in [-1,1]^2, shell z = sqrt(1 - r^2).
    vec2 p = texCoord0 * 2.0 - 1.0;
    float r2 = dot(p, p);
    if (r2 > 1.0) {
        discard;
    }
    float shellZ = sqrt(1.0 - r2);

    // Fresnel: transparent face, glowing silhouette edge.
    float fresnel = pow(1.0 - shellZ, max(FresnelPower, 0.01));

    // Intersection seam: highlight where the shell meets world geometry (flat-quad
    // depth approximation — good enough for the "touching the ground" ring read).
    vec2 screenUV = (gl_FragCoord.xy - U_ViewPort.xy) / U_ViewPort.zw;
    float seam = seamTerm(screenUV);

    float glow = max(fresnel, seam);
    vec4 color = ShellColor * vertexColor * ColorModulator;
    color.a *= mix(FaceAlpha, 1.0, glow);
    if (color.a < DiscardThreshold) {
        discard;
    }
    color.rgb += RimHDRColor.rgb * (RimHDRColor.a * glow);
    fragColor = linear_fog(color, vertexDistance, FogStart, FogEnd, FogColor);
}
