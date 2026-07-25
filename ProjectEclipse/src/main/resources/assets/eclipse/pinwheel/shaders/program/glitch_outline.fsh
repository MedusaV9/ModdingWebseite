// eclipse:glitch_outline — GLITCHZONE flagship (TRANSITION priority): the world renders
// BLACK and only GREEN EDGE OUTLINES remain, a wireframe/thermal-scanner readout. Edge
// signal = depth-Laplacian on LINEARIZED depth (silhouettes + creases; the second
// derivative is ~0 on flat surfaces at any slant, so grazing floors do not false-edge)
// + reconstructed view-space NORMAL disagreement (screenToViewSpace on the same 5 depth
// taps — surface-orientation breaks that share a depth plane) + a Roberts luminance term
// (texture/block boundaries, weighted low so geometry wins). Fed per frame by
// client.GlitchZoneFx through the VeilPostController row (never under an Iris
// shaderpack): Strength (0..1 zone ramp — MUST be a no-op at 0), Time (wall-clock
// seconds), Detail (0 under reduced FX: sweep bar, flicker and grain freeze/flatten;
// the scanner grade itself survives).
#include eclipse:eclipse_common
#include eclipse:eclipse_glitch
#include veil:space_helper

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float Strength;
uniform float Time;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

// Scanner phosphor palette.
const vec3 EDGE_GREEN = vec3(0.10, 1.00, 0.32);
const vec3 FILL_GREEN = vec3(0.04, 0.22, 0.09);

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    if (s <= 0.0005) {
        fragColor = vec4(scene, 1.0);
        return;
    }

    vec2 texel = 1.0 / vec2(textureSize(DiffuseSampler0, 0));
    float near = VeilCamera.NearPlane;
    float far = VeilCamera.FarPlane;

    // 5-tap cross: raw depth (for position reconstruction) + linearized (for edges).
    float dC = texture(DiffuseDepthSampler, texCoord).r;
    float dR = texture(DiffuseDepthSampler, texCoord + vec2(texel.x, 0.0)).r;
    float dL = texture(DiffuseDepthSampler, texCoord - vec2(texel.x, 0.0)).r;
    float dU = texture(DiffuseDepthSampler, texCoord + vec2(0.0, texel.y)).r;
    float dD = texture(DiffuseDepthSampler, texCoord - vec2(0.0, texel.y)).r;
    float lC = gzLinearDepth(dC, near, far);
    float lR = gzLinearDepth(dR, near, far);
    float lL = gzLinearDepth(dL, near, far);
    float lU = gzLinearDepth(dU, near, far);
    float lD = gzLinearDepth(dD, near, far);

    // Depth term: second derivative of linear depth, scale-normalized by the centre
    // distance. Silhouettes spike it; planar runs (even steep ones) stay near zero.
    float depthEdge = (abs(lR + lL - 2.0 * lC) + abs(lU + lD - 2.0 * lC)) / max(lC * 0.5, 0.5);
    depthEdge = smoothstep(0.06, 0.22, depthEdge);

    // Normal term: view-space normals from the reconstructed position cross products of
    // the right/up vs left/down tap pairs — corners and face changes disagree, flats agree.
    vec3 pC = screenToViewSpace(texCoord, dC).xyz;
    vec3 pR = screenToViewSpace(texCoord + vec2(texel.x, 0.0), dR).xyz;
    vec3 pL = screenToViewSpace(texCoord - vec2(texel.x, 0.0), dL).xyz;
    vec3 pU = screenToViewSpace(texCoord + vec2(0.0, texel.y), dU).xyz;
    vec3 pD = screenToViewSpace(texCoord - vec2(0.0, texel.y), dD).xyz;
    vec3 n1 = normalize(cross(pR - pC, pU - pC));
    vec3 n2 = normalize(cross(pC - pL, pC - pD));
    float normalEdge = smoothstep(0.10, 0.55, 1.0 - dot(n1, n2));

    // Luminance term (Roberts on the colour taps): block/texture boundaries as faint
    // secondary traces so the readout keeps detail inside large flat faces.
    float lumaEdge = abs(gzLuma(texture(DiffuseSampler0, texCoord + vec2(texel.x, 0.0)).rgb)
                    - gzLuma(texture(DiffuseSampler0, texCoord - vec2(texel.x, 0.0)).rgb))
            + abs(gzLuma(texture(DiffuseSampler0, texCoord + vec2(0.0, texel.y)).rgb)
                    - gzLuma(texture(DiffuseSampler0, texCoord - vec2(0.0, texel.y)).rgb));
    lumaEdge = smoothstep(0.12, 0.45, lumaEdge) * 0.35;

    float sky = step(0.9999, dC);
    // Sky pixels have no geometry: silhouette edges against sky come from the NEIGHBOR
    // taps (their depth Laplacian fires on the geometry side), so the sky itself stays
    // pure void. Distant edges thin out instead of dissolving into shimmer.
    float distanceFade = 1.0 / (1.0 + lC * 0.006);
    float edge = clamp(depthEdge + normalEdge + lumaEdge, 0.0, 1.0) * (1.0 - sky) * distanceFade;

    // Scanner readout: black world, a whisper of green-mapped luma so mass reads as mass,
    // phosphor edges on top. Detail layers: a slow sweep bar rolling down, per-line
    // flicker and a breath of static — all frozen/flattened under reduced FX.
    float detail = clamp(Detail, 0.0, 1.0);
    float flicker = mix(1.0, 0.82 + 0.18 * efxNoise(vec2(Time * 24.0, texCoord.y * 3.0)), detail);
    float sweepPos = fract(Time * 0.11) * 1.3 - 0.15;
    float sweep = exp(-abs(texCoord.y - sweepPos) * 40.0) * detail;
    float grain = (efxHash(texCoord * vec2(853.0, 997.0) + fract(Time * 7.0)) - 0.5) * 0.05 * detail;

    vec3 readout = FILL_GREEN * gzLuma(scene) * 0.30 * (1.0 - sky)
            + EDGE_GREEN * edge * (0.85 * flicker + 0.45 * sweep)
            + EDGE_GREEN * 0.02 * sweep
            + vec3(0.0, grain, grain * 0.4);

    // Soft scanner vignette so the readout sits inside a tube, not a flat page.
    float vign = 1.0 - 0.35 * smoothstep(0.45, 0.95, length(texCoord - 0.5) * 1.5);
    readout *= vign;

    // Ramp law: the scene sinks to black and the readout rises with Strength; at 0 the
    // pass is bit-exact passthrough (early-out above), at 1 the world is the readout.
    vec3 color = mix(scene, readout, s);
    color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s);

    fragColor = vec4(color, 1.0);
}
