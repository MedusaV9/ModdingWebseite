#version 330 core

// A0 rgb_split_distort — screen-space glitch decal for the GLITCH palette. The quad
// samples SamplerSceneColor (the world snapshot taken before the Photon pass) through
// a wobbling UV field and splits the R/B channels apart (chromatic aberration). A
// procedural soft disc from the quad UVs masks the effect, so no texture is needed;
// particle alpha (colorOverLifetime) scales the whole distortion. GameTime is the
// vanilla day-fraction uniform — multiplied back to ticks for the wobble clock.

uniform sampler2D SamplerSceneColor;

uniform vec4 U_ViewPort;

uniform vec4 ColorModulator;
uniform float GameTime;
uniform float DiscardThreshold;
uniform float SplitStrength;
uniform float WobbleAmp;
uniform float WobbleSpeed;
uniform vec4 TintColor;

in float vertexDistance;
in vec2 texCoord0;
in vec4 vertexColor;
in float viewZ;

out vec4 fragColor;

void main() {
    // Procedural soft disc mask from the quad UVs (no texture dependency).
    vec2 p = texCoord0 * 2.0 - 1.0;
    float mask = 1.0 - smoothstep(0.55, 1.0, length(p));
    float alpha = mask * vertexColor.a * ColorModulator.a;
    if (alpha < DiscardThreshold) {
        discard;
    }

    float t = GameTime * 24000.0; // smooth tick clock (day fraction -> ticks)
    vec2 screenUV = (gl_FragCoord.xy - U_ViewPort.xy) / U_ViewPort.zw;

    // UV wobble: two crossed sine bands scrolling at offset rates.
    vec2 wobble = vec2(
        sin(screenUV.y * 42.0 + t * WobbleSpeed),
        cos(screenUV.x * 37.0 + t * WobbleSpeed * 0.7)) * (WobbleAmp * mask);

    // Chromatic aberration: R and B pushed apart along x, G stays put.
    vec2 split = vec2(SplitStrength * mask, 0.0);
    vec2 uv = clamp(screenUV + wobble, vec2(0.001), vec2(0.999));
    float r = texture(SamplerSceneColor, clamp(uv + split, vec2(0.001), vec2(0.999))).r;
    float g = texture(SamplerSceneColor, uv).g;
    float b = texture(SamplerSceneColor, clamp(uv - split, vec2(0.001), vec2(0.999))).b;

    vec3 scene = vec3(r, g, b) * mix(vec3(1.0), TintColor.rgb * vertexColor.rgb, TintColor.a * mask);
    fragColor = vec4(scene, alpha);
}
