#version 330 core

// A0 shared vertex program for every eclipse custom_shader particle material.
// Mirrors photon:particle.vsh (instancing-aware via getParticleData()) and adds a
// viewZ varying (view-space depth in blocks) for SceneDepth comparisons downstream.

#moj_import <fog.glsl>
#moj_import <photon:particle.glsl>

uniform sampler2D Sampler2;

uniform mat4 ModelViewMat;
uniform mat4 ProjMat;
uniform int FogShape;

out float vertexDistance;
out vec2 texCoord0;
out vec4 vertexColor;
out float viewZ;

void main() {
    ParticleData data = getParticleData();

    vec4 viewPos = ModelViewMat * vec4(data.Position, 1.0);
    gl_Position = ProjMat * viewPos;

    vertexDistance = fog_distance(data.Position, FogShape);
    texCoord0 = data.UV;
    vertexColor = data.Color * texelFetch(Sampler2, data.LightUV / 16, 0);
    viewZ = -viewPos.z;
}
