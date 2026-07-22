// Limbo grade: desaturate toward violet + soft breathing vignette.
// Intensity is fed per frame by veilfx.VeilPostController (0 -> 1 fade over ~40 ticks).
uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float Intensity;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    vec4 c = texture(DiffuseSampler0, texCoord);
    float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    vec3 purple = mix(c.rgb, gray * vec3(0.75, 0.45, 1.1), 0.55);
    float d = distance(texCoord, vec2(0.5));
    purple *= 1.0 - smoothstep(0.45, 0.95, d) * 0.6;
    fragColor = vec4(mix(c.rgb, purple, Intensity), 1.0);
}
