// Border glitch grade: chromatic aberration + horizontal displacement bands, scaled by
// how close the player is to the circular soft border. Proximity (0 far -> 1 touching)
// and Time (seconds) are fed per frame by veilfx.VeilPostController; the proximity value
// itself is computed by border.client.BorderFxRenderer from the synced ring radius.
uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float Proximity;
uniform float Time;

in vec2 texCoord;

out vec4 fragColor;

float hash(float n) {
    return fract(sin(n * 127.1) * 43758.5453123);
}

void main() {
    // Occasional horizontal displacement bands: a few screen-height stripes that jump
    // sideways for a frame or two, more often (and further) the closer the border is.
    float band = floor(texCoord.y * 24.0);
    float jitterSeed = hash(band + floor(Time * 14.0) * 31.0);
    float bandGate = step(1.0 - 0.35 * Proximity, jitterSeed);
    float shift = (hash(band * 3.7 + floor(Time * 14.0)) - 0.5) * 0.06 * Proximity * bandGate;
    vec2 uv = vec2(texCoord.x + shift, texCoord.y);

    // Chromatic aberration: split R/B away from the screen centre, growing with proximity.
    vec2 fromCenter = uv - vec2(0.5);
    float aberration = 0.012 * Proximity * (0.6 + 0.4 * sin(Time * 9.0));
    vec3 color;
    color.r = texture(DiffuseSampler0, uv + fromCenter * aberration).r;
    color.g = texture(DiffuseSampler0, uv).g;
    color.b = texture(DiffuseSampler0, uv - fromCenter * aberration).b;

    // Faint violet wash at the edges of the screen when practically touching the ring.
    float vignette = smoothstep(0.55, 0.95, length(fromCenter));
    color = mix(color, color * vec3(0.8, 0.55, 1.15), vignette * Proximity * 0.5);

    fragColor = vec4(color, 1.0);
}
