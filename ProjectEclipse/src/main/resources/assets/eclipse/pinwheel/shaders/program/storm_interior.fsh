// eclipse:storm_interior — the INSIDE of a fog storm (P2 W9, R14 interior; GRADE priority).
// Crushes and cools the frame, wipes the sky, layers procedural rain streaks and closes a
// soft vignette — together with the ViewportEvent fog clamp (~24 blocks) this is the "low
// visibility inside" read. Uniforms (frozen §3.3): Interior, RainAmount, Time — fed per frame
// by stormfx.StormInteriorFx through the VeilPostController row. Active only while
// EclipseFxState.stormInterior() > 0.01 (and never under an Iris shaderpack — the fog clamp
// and the wall geometry carry the interior look there).
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float Interior;
uniform float RainAmount;
uniform float Time;

in vec2 texCoord;

out vec4 fragColor;

// One layer of thin, fast rain streaks: columns gated per fall cycle so sheets churn
// instead of tiling. Returns streak brightness 0..1.
float rainLayer(vec2 uv, float t, float density, float speed, float seed) {
    float x = uv.x * density;
    float col = floor(x);
    float h = efxHash(vec2(col, seed));
    float fall = uv.y * (1.1 + 0.5 * h) + t * speed * (0.8 + 0.6 * h) + h * 17.0;
    float cycle = floor(fall);
    float active = step(0.45, efxHash(vec2(col, cycle + seed)));
    float core = 1.0 - abs(fract(x) - 0.5) * 2.0;
    float y = fract(fall);
    float tail = smoothstep(1.0, 0.55, y) * smoothstep(0.0, 0.08, y);
    return active * pow(core, 6.0) * tail;
}

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    float amt = clamp(Interior, 0.0, 1.0);

    // Shadow crush + cold desaturation toward storm slate.
    color = efxCrush(color, amt * 0.7);
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(color, vec3(luma) * vec3(0.86, 0.83, 1.05), amt * 0.55);

    // The sky is gone inside: far-plane pixels sink into the storm slate.
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    float sky = step(0.9999, depth);
    color = mix(color, vec3(0.05, 0.045, 0.075), sky * amt * 0.85);

    // Rain streak overlay (two layers, different densities/speeds, faint cool highlight).
    float rain = clamp(RainAmount, 0.0, 1.0) * amt;
    if (rain > 0.005) {
        float streaks = rainLayer(texCoord, Time, 90.0, 1.7, 3.1)
                + 0.6 * rainLayer(texCoord, Time, 150.0, 2.4, 7.7);
        // Slight wind shear: offset the second sample sideways over time.
        streaks += 0.35 * rainLayer(texCoord + vec2(Time * 0.03, 0.0), Time, 60.0, 1.2, 11.3);
        color += vec3(0.42, 0.47, 0.66) * streaks * rain * 0.30;
    }

    // Storm pressure vignette.
    float edge = smoothstep(0.35, 0.95, length(texCoord - 0.5) * 1.55);
    color *= 1.0 - amt * 0.28 * edge;

    fragColor = vec4(color, 1.0);
}
