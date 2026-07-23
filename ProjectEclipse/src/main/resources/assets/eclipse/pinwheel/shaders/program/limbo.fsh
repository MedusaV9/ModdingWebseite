// eclipse:limbo v2 — the Limbo grade (P2-W3, R5, GRADE priority).
// v1 kept: desaturate toward violet + soft breathing vignette. v2 adds the "much more":
//   * CausticsAmount — animated voronoi-ish caustic web (procedural, efxNoise: ridged
//     two-layer counter-scroll) + violet lift + glint sparkle on the WATER: masked to
//     non-sky pixels that are dark (the limbo ocean is near-black; the lantern-lit ship
//     reads bright and stays clean), weighted toward the lower screen half — the
//     horizon-line approximation that stays robust at every camera pitch. Water pixels
//     also get a subtle liquid refraction wobble.
//   * GodrayDir (vec2) — NDC of the zenith eclipse point (one source of truth with the
//     sky-pass disc, fed from LimboSpecialEffects.zenithWorldPoint via SunTracker).
//     12-tap radial blur of the bright-pass toward that point; strength ramps as the
//     player looks up (the point nears screen center) and dies offscreen — the CPU pushes
//     (10,10) while the zenith is behind the camera.
//   * A faint dreamlike radial chroma fringe at the screen edge (≤ ~2.5 px).
// Uniforms (frozen §3.3): Intensity, GodrayDir (vec2), CausticsAmount, Time — fed per
// frame by veilfx.LimboAmbience (Intensity/CausticsAmount ease in over ~2 s after
// entering limbo, Time wraps hourly).
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float Intensity;
uniform vec2 GodrayDir;
uniform float CausticsAmount;
uniform float Time;

in vec2 texCoord;

out vec4 fragColor;

// Ridged two-layer counter-scrolling value noise: bright cell-boundary webs (voronoi-ish).
float causticWeb(vec2 p, float t) {
    float n1 = efxNoise(p + vec2(t * 0.35, t * 0.22));
    float n2 = efxNoise(p * 1.7 - vec2(t * 0.28, t * 0.40));
    float r1 = 1.0 - abs(2.0 * n1 - 1.0);
    float r2 = 1.0 - abs(2.0 * n2 - 1.0);
    float web = r1 * r2;
    return web * web;
}

void main() {
    vec2 uv = texCoord;
    float depth = texture(DiffuseDepthSampler, uv).r;
    float sky = step(0.9999, depth);
    vec3 base = texture(DiffuseSampler0, uv).rgb;
    float baseLuma = dot(base, vec3(0.299, 0.587, 0.114));

    // ---- water mask: non-sky, dark (the black ocean), biased below mid-screen ----------
    float water = (1.0 - sky) * smoothstep(0.42, 0.05, baseLuma);
    water *= 0.35 + 0.65 * smoothstep(0.85, 0.30, uv.y);
    water *= CausticsAmount;

    // Fake perspective: the non-linear depth term pushes distant water toward a finer,
    // calmer pattern so the shimmer recedes instead of reading as a flat screen decal.
    float band = pow(clamp(depth, 0.0, 1.0), 48.0);
    float scale = mix(7.0, 26.0, band);
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
    float aspect = screenSize.x / max(screenSize.y, 1.0);
    vec2 wp = uv * vec2(aspect, 1.0) * scale;

    // Liquid refraction wobble for water pixels only.
    vec2 wobble = vec2(
            efxNoise(wp * 0.9 + vec2(Time * 0.50, 0.0)) - 0.5,
            efxNoise(wp * 0.9 + vec2(31.7, Time * 0.43)) - 0.5) * 0.012 * water;

    // ---- base sample with wobble + edge chroma fringe (≤ ~2.5 px, dreamlike) ------------
    float d = distance(uv, vec2(0.5));
    float edge = smoothstep(0.35, 0.75, d) * Intensity;
    vec2 radial = normalize(uv - 0.5 + vec2(1.0e-5));
    vec3 color = efxChroma(DiffuseSampler0, uv + wobble, radial * (2.5 / screenSize), edge);

    // ---- v1 grade kept: desaturate toward violet + soft breathing vignette --------------
    float gray = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 purple = mix(color, gray * vec3(0.75, 0.45, 1.1), 0.55);
    float breathe = 0.6 + 0.05 * sin(Time * 0.7);
    purple *= 1.0 - smoothstep(0.45, 0.95, d) * breathe;
    color = mix(color, purple, Intensity);

    // ---- crazier purple water: violet lift + shimmering caustic web + glints ------------
    float web = causticWeb(wp, Time);
    float sparkle = pow(causticWeb(wp * 2.3 + vec2(17.0), Time * 1.6), 2.0);
    color += (vec3(0.10, 0.03, 0.17)
            + vec3(0.42, 0.16, 0.80) * web
            + vec3(0.55, 0.30, 1.00) * sparkle * 0.6) * water;

    // ---- screen-space radial god rays from the zenith disc ------------------------------
    float lookUp = 1.0 - smoothstep(0.9, 2.6, length(GodrayDir));
    float rayStrength = lookUp * Intensity;
    if (rayStrength > 0.001) {
        vec2 centerUv = GodrayDir * 0.5 + 0.5;
        vec2 stepUv = (centerUv - uv) / 12.0;
        vec2 suv = uv;
        float illum = 0.0;
        float weight = 1.0;
        for (int i = 0; i < 12; i++) {
            suv += stepUv;
            vec3 s = texture(DiffuseSampler0, clamp(suv, vec2(0.0), vec2(1.0))).rgb;
            illum += max(dot(s, vec3(0.299, 0.587, 0.114)) - 0.16, 0.0) * weight;
            weight *= 0.84;
        }
        float flicker = 0.9 + 0.1 * sin(Time * 2.3 + uv.y * 4.0);
        color += vec3(0.60, 0.30, 1.00) * illum * 0.16 * rayStrength * flicker;
    }

    fragColor = vec4(color, 1.0);
}
