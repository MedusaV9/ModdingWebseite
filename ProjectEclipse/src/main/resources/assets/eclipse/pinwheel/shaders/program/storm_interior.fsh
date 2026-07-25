// eclipse:storm_interior — the INSIDE of a fog storm (P2 W9, R14 interior; GRADE priority).
// Crushes and cools the frame, wipes the sky, layers procedural rain streaks and closes a
// soft vignette — together with the ViewportEvent fog clamp (~24 blocks) this is the "low
// visibility inside" read. Uniforms: Interior, RainAmount, Time (frozen §3.3) + Sphere
// (EVAL-POL-F #4: 1 inside a C8 site-sphere storm — the grade tints green-violet instead of
// the vortex blue-slate, so the fog color and the post grade stop fighting each other) +
// WallProx (FX-STORM: 0..1 wall proximity inside — drives the heat-shimmer refraction) +
// the STORM2 W-D quartet: EyeDim (0..1 under the apex eye — top god-light + vignette
// release), BandFlow (signed −1..1 stratum wind flow at camera height — the rain layers
// shear sideways with it, against each other), InnerFlash (W-B intra-wall flash-scheduler
// max envelope — violet-white edge-biased pulse) and WallBand (IDEAS-STORM-2 #5: symmetric
// wall-crossing scalar peaking mid-band — extra crush/near-mist/shimmer so passing THROUGH
// the wall reads as meters of mass; graded on BOTH sides, the Java predicate fires on it
// even at zero Interior) — all fed per frame by stormfx.StormInteriorFx through the
// VeilPostController row (never under an Iris shaderpack — the fog clamp and the wall
// geometry carry the interior look there).
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float Interior;
uniform float RainAmount;
uniform float Time;
uniform float Sphere;
uniform float WallProx;
uniform float EyeDim;
uniform float BandFlow;
uniform float InnerFlash;
uniform float WallBand;

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
    float rainOn = step(0.45, efxHash(vec2(col, cycle + seed)));
    float core = 1.0 - abs(fract(x) - 0.5) * 2.0;
    float y = fract(fall);
    // Descending ramp as 1-smoothstep(lo,hi,y): edge0>edge1 is undefined GLSL.
    float tail = (1.0 - smoothstep(0.55, 1.0, y)) * smoothstep(0.0, 0.08, y);
    return rainOn * pow(core, 6.0) * tail;
}

void main() {
    float amt = clamp(Interior, 0.0, 1.0);
    float band = clamp(WallBand, 0.0, 1.0);
    float eye = clamp(EyeDim, 0.0, 1.0) * amt;

    // Heat-shimmer refraction near the wall inside (FX-STORM): a slow RISING two-noise
    // wobble bends the frame by up to ~0.8% UV within the shimmer band; depth is sampled
    // at the SAME wobbled UV so the sky mask can never halo around bent geometry.
    // STORM2 (#5): +30% amplitude mid-crossing — the wall's own heat breathes hardest
    // exactly while pushing through it (WallProx is 0 under reducedFx, so this stays 0 too).
    vec2 uv = texCoord;
    float shimmer = clamp(WallProx, 0.0, 1.0) * amt * (1.0 + 0.3 * band);
    if (shimmer > 0.005) {
        float wobX = efxNoise(uv * 34.0 + vec2(Time * 0.9, -Time * 1.6));
        float wobY = efxNoise(uv * 21.0 + vec2(-Time * 1.1, Time * 0.7));
        uv += (vec2(wobX, wobY) - 0.5) * 0.008 * shimmer;
    }
    vec3 color = texture(DiffuseSampler0, uv).rgb;

    // Shadow crush + cold desaturation. Vortex interiors cool toward the storm blue-slate;
    // sphere interiors (Sphere = 1) grade green-violet to match the C8 fog identity — the
    // grade no longer desaturates the green fog back toward blue (EVAL-POL-F #4).
    color = efxCrush(color, amt * 0.7);
    // STORM2 (IDEAS-STORM-2 #5) wall-band crush: NOT scaled by Interior — it peaks
    // mid-band at r−2.5, where Interior is still 0 by construction (the interior feather
    // starts 2.5 blocks further in), so the two crushes hand over instead of stacking
    // and the deep-inside read stays owned by the frozen Interior look.
    color = efxCrush(color, band * 0.5);
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 desatTint = mix(vec3(0.86, 0.83, 1.05), vec3(0.84, 1.04, 0.93), Sphere);
    color = mix(color, vec3(luma) * desatTint, amt * 0.55);

    // The sky is gone inside: far-plane pixels sink into the storm palette (slate for the
    // vortex, deep green-violet for spheres).
    float depth = texture(DiffuseDepthSampler, uv).r;
    float sky = step(0.9999, depth);
    vec3 skySink = mix(vec3(0.05, 0.045, 0.075), vec3(0.040, 0.070, 0.056), Sphere);
    color = mix(color, skySink, sky * amt * 0.85);

    // Interior depth-fog with height gradient (FX-STORM): geometry sinks into a mist that
    // is densest LOW in the frame — the ground ahead drowns first, so the interior reads
    // like wading through standing fog. Depth window ≈ 10 → 56 blocks (hyperbolic depth,
    // near ≈ 0.05): it ramps across the pinched fog band and keeps working through the
    // 24→56 flash lift, so flash-revealed silhouettes stay smoky instead of popping clean.
    float depthFog = smoothstep(0.995, 0.9998, depth) * (1.0 - sky);
    float heightGrad = 1.0 - smoothstep(0.0, 0.75, texCoord.y);
    vec3 mist = mix(vec3(0.070, 0.062, 0.100), vec3(0.052, 0.092, 0.072), Sphere);
    // STORM2 (W-D D2) wall-side mist bias: the view INTO the wall drowns before the open
    // interior does — the mist gains weight with wall proximity (worst case 0.71 < 1).
    color = mix(color, mist, depthFog * amt * (0.18 + 0.38 * heightGrad + 0.15 * clamp(WallProx, 0.0, 1.0)));
    // STORM2 (#5) crossing mist: a much NEARER depth window (~4–18 blocks) keyed off
    // WallBand alone — mid-crossing the terrain drowns almost at arm's length on BOTH
    // sides of the wall, selling the meters of suspended mass. Sky pixels sink too (the
    // outside half of the crossing has sky; inside, the sky-sink above already owns it).
    if (band > 0.005) {
        float bandFog = smoothstep(0.9875, 0.9975, depth) * (1.0 - sky);
        color = mix(color, mist, max(bandFog, sky) * band * 0.45);
    }

    // Rain streak overlay (two layers, different densities/speeds, faint cool highlight).
    // STORM2 (W-D D2) band-flow shear: the layers drift sideways with the signed stratum
    // wind at the camera's height (strongest low in the frame, like the mist) and AGAINST
    // each other — inside the mass the weather visibly streams at band speed instead of
    // falling straight. BandFlow feeds 0 under reducedFx, collapsing to the frozen look.
    float rain = clamp(RainAmount, 0.0, 1.0) * amt;
    if (rain > 0.005) {
        float shear = Time * 0.05 * clamp(BandFlow, -1.0, 1.0) * heightGrad;
        float streaks = rainLayer(texCoord + vec2(shear, 0.0), Time, 90.0, 1.7, 3.1)
                + 0.6 * rainLayer(texCoord - vec2(shear * 0.7, 0.0), Time, 150.0, 2.4, 7.7);
        // Slight wind shear: offset the third sample sideways over time (+ band drift).
        streaks += 0.35 * rainLayer(texCoord + vec2(Time * 0.03 + shear * 0.4, 0.0), Time, 60.0, 1.2, 11.3);
        color += vec3(0.42, 0.47, 0.66) * streaks * rain * 0.30;
    }

    // STORM2 (W-D D2) eye god-light: standing under the apex eye, light falls from ABOVE —
    // a vertical top-glow toward the sphere flash palette, strongest at the frame top.
    // EyeDim is sphere-interior-only on the Java side, so the vortex grade never sees it.
    if (eye > 0.005) {
        float topGlow = smoothstep(0.35, 1.0, texCoord.y);
        color += vec3(0.50, 0.68, 0.54) * 0.10 * eye * topGlow;
    }

    // Storm pressure vignette. STORM2: EyeDim releases it mildly (the eye is the one calm,
    // luminous place inside) while WallBand clamps it back down mid-crossing (#5).
    float edge = smoothstep(0.35, 0.95, length(texCoord - 0.5) * 1.55);
    color *= 1.0 - amt * 0.28 * edge * (1.0 - 0.35 * eye);
    color *= 1.0 - band * 0.20 * edge;

    // STORM2 (W-D D2) intra-wall flash: W-B's scheduler envelope pulses the interior
    // violet-white, biased toward the frame EDGES — the wall is where the light lives.
    // Additive after the vignette so the pulse blooms against the darkened rim; stacks
    // safely with the fog-color flash lift (both are bounded, ≤ +0.18 here).
    float innerFlash = clamp(InnerFlash, 0.0, 1.0) * amt;
    if (innerFlash > 0.005) {
        color += vec3(0.60, 0.54, 0.78) * 0.18 * innerFlash * (0.35 + 0.65 * edge);
    }

    fragColor = vec4(color, 1.0);
}
