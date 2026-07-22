// Purple sun rim: depth-masked additive halo around the sun direction, sky pixels only
// (DiffuseDepthSampler >= 1.0). SunDirection is fed per frame from level.getSunAngle by
// veilfx.VeilPostController; screen -> world projection comes from the veil:camera buffer.
#include veil:space_helper

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform vec3 SunDirection;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    vec4 color = texture(DiffuseSampler0, texCoord);
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    if (depth >= 1.0) {
        vec3 viewDir = normalize(screenToWorldSpace(vec3(texCoord, 1.0)).xyz - VeilCamera.CameraPosition);
        vec3 sunDir = normalize(SunDirection);
        float alignment = max(dot(viewDir, sunDir), 0.0);
        // Tight bright rim plus a broad faint glow.
        float rim = pow(alignment, 400.0);
        float glow = pow(alignment, 24.0) * 0.15;
        color.rgb += vec3(0.6, 0.2, 1.0) * (rim + glow);
    }
    fragColor = vec4(color.rgb, 1.0);
}
