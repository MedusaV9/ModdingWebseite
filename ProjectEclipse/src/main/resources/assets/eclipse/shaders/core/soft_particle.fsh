#version 330 core

// A0 soft_particle — SceneDepth-faded billboard: alpha ramps to zero where the quad
// approaches world geometry (no more hard intersection cuts through blocks) and,
// symmetrically, where the camera approaches the quad (NearFade blocks). Keeps the
// house hdr_particle HDR/DiscardThreshold contract so bloom stacking laws carry over.
// MainTexture is a user-assignable sampler (persisted per material in the .fx).
//
// Degenerate-scene-sampler hardening (A0 follow-up): on drivers where Photon's
// depth+color scene blit errors out (Mesa rejects the blit when the main target's
// depth was stencil-reallocated — see A0_SHADER_FOUNDATION.md §7), SamplerSceneDepth
// stays at 0.0 everywhere. A raw sample of exactly 0.0 can never come from rendered
// geometry (that would sit ON the near plane), so we treat it as "no scene depth"
// and let the soft term collapse to 1.0 — the particle renders as a normal alpha
// quad instead of being discarded wholesale. SceneDepthValid (default 1.0) is a
// manual kill switch for the depth read, settable per material via fxlib uniforms.

#moj_import <fog.glsl>

uniform sampler2D MainTexture;
uniform sampler2D SamplerSceneDepth;

uniform mat4 U_InverseProjectionMatrix;
uniform vec4 U_ViewPort;

uniform vec4 ColorModulator;
uniform float FogStart;
uniform float FogEnd;
uniform vec4 FogColor;
uniform float DiscardThreshold;
uniform vec4 HDR;
uniform int HDRMode;
uniform float SoftDistance;
uniform float NearFade;
uniform float SceneDepthValid;

in float vertexDistance;
in vec2 texCoord0;
in vec4 vertexColor;
in float viewZ;

out vec4 fragColor;

// Depth sample -> view-space depth in blocks (positive into the screen).
float sceneViewZFromDepth(float depth, vec2 screenUV) {
    vec4 ndc = vec4(screenUV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = U_InverseProjectionMatrix * ndc;
    return -view.z / view.w;
}

// Soft-fade term against scene geometry; 1.0 (= no fade) whenever the scene depth
// is unusable: manual kill switch, or raw sample exactly 0.0 (dead scene copy).
float softTerm(vec2 screenUV) {
    if (SceneDepthValid < 0.5) {
        return 1.0;
    }
    float depth = texture(SamplerSceneDepth, screenUV).r;
    if (depth <= 0.0) {
        return 1.0;
    }
    return clamp((sceneViewZFromDepth(depth, screenUV) - viewZ) / max(SoftDistance, 1.0e-4), 0.0, 1.0);
}

void main() {
    vec4 color = texture(MainTexture, texCoord0) * vertexColor * ColorModulator;

    vec2 screenUV = (gl_FragCoord.xy - U_ViewPort.xy) / U_ViewPort.zw;
    float soft = softTerm(screenUV);
    float near = clamp(viewZ / max(NearFade, 1.0e-4), 0.0, 1.0);
    color.a *= smoothstep(0.0, 1.0, soft) * smoothstep(0.0, 1.0, near);

    if (color.a < DiscardThreshold) {
        discard;
    }
    if (HDRMode == 0) {
        color.rgb += HDR.a * HDR.rgb;
    } else {
        color.rgb *= HDR.a * HDR.rgb;
    }
    fragColor = linear_fog(color, vertexDistance, FogStart, FogEnd, FogColor);
}
