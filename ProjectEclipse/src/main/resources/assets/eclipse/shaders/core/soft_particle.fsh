#version 330 core

// A0 soft_particle — SceneDepth-faded billboard: alpha ramps to zero where the quad
// approaches world geometry (no more hard intersection cuts through blocks) and,
// symmetrically, where the camera approaches the quad (NearFade blocks). Keeps the
// house hdr_particle HDR/DiscardThreshold contract so bloom stacking laws carry over.
// MainTexture is a user-assignable sampler (persisted per material in the .fx).

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

in float vertexDistance;
in vec2 texCoord0;
in vec4 vertexColor;
in float viewZ;

out vec4 fragColor;

// Scene depth sample -> view-space depth in blocks (positive into the screen).
float sceneViewZ(vec2 screenUV) {
    float depth = texture(SamplerSceneDepth, screenUV).r;
    vec4 ndc = vec4(screenUV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = U_InverseProjectionMatrix * ndc;
    return -view.z / view.w;
}

void main() {
    vec4 color = texture(MainTexture, texCoord0) * vertexColor * ColorModulator;

    vec2 screenUV = (gl_FragCoord.xy - U_ViewPort.xy) / U_ViewPort.zw;
    float soft = clamp((sceneViewZ(screenUV) - viewZ) / max(SoftDistance, 1.0e-4), 0.0, 1.0);
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
