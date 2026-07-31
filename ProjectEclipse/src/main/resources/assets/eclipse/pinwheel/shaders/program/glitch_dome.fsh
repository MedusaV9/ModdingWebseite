// eclipse:glitch_dome — WOAH-01 mansion-dome INTERIOR (TRANSITION priority, driven by
// the persistent "dome" glitch zone): the glitch_outline scanner readout (depth-Laplacian
// + view-normal disagreement + Roberts luma, phosphor palette, accent mechanics) PLUS the
// glitch_scanlines CRT layers on top of that readout — fine scanlines, vertical-hold
// jitter, a rolling bar and tape static at 0.4× the scanlines strength. MERGE LAW (plan
// §12.6): the outline readout is built FIRST on the UNSHIFTED texCoord (the depth taps
// must match the geometry, or the edges swim against the world); the CRT layers then act
// on the finished readout only — the hold jitter and bar displacement shift PATTERN UVs,
// never the depth taps. Fed per frame by client.GlitchZoneFx through the automatic
// VeilPostController row (frozen uniform contract, identical to the 5 sibling effects):
// Strength (0..1, no-op at 0, early-out ≤ 0.0005), Time (wall-clock seconds), Detail
// (0 under reduced FX: hold jitter, roll bar, sweep, flicker and static freeze — the
// scanner grade survives), AccentColor/AccentAmount (F-049), Origin/OriginMode
// (declared per the row-uniform feeder contract, unused by this effect).
//
// WAVE-13 B4 touched only the two SAFETY items here — the WOAH-01 look is unchanged, because
// the dome deliberately mirrors the glitch_outline readout AS SHIPPED, not the wave-13
// depth-trace version:
//   1. main() no longer holds a value-less `return` (glsl-processor NPE landmine — see the
//      note in umbral_veins.fsh; a stray hash character in a comment is enough to arm it).
//   2. The reconstructed view normals go through gzNormalizeSafe and every depth-derived term
//      is gated by gzDepthValid. On a dead depth attachment all five taps collapse onto one
//      point, cross() is the zero vector, and a raw normalize() would paint NaN over the
//      whole dome interior.
//
// F-102 GLITCH-FAMILY POLISH "HEX-SCHALE": the dome INTERFACE becomes visible from inside.
// The dome zone carries no world origin (MansionDomeService arms it originAtCentre = false),
// so the layer is built on the VIEW RAY alone: a hex lattice on the ray's sphere coordinates
// (longitude scaled by an INTEGER so the atan seam lands on a whole lattice period) painted
// where the world is FAR — a distance gate at 30..70 blocks catches the opaque hull (shell
// radius is clamped to 48..72) and the sky, and leaves the mansion interior clean. A Fresnel
// band brightens the hexes toward the horizon (grazing view = dome equator), which is the
// "Fresnel-Kante" of the mandate; each cell breathes on its own hash phase, on the shared
// 5 s twinkle divisor of the 100 s wrap. On a dead depth buffer the linearized distance
// collapses to the near plane and the gate closes the layer — no NaN path, no garbage.
#include eclipse:eclipse_common
#include eclipse:eclipse_glitch
#include veil:space_helper

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float Strength;
uniform float Time;
uniform float Detail;
uniform vec3 AccentColor;
uniform float AccentAmount;
uniform vec3 Origin;
uniform float OriginMode;

in vec2 texCoord;

out vec4 fragColor;

// Scanner phosphor palette (glitch_outline heritage).
const vec3 EDGE_GREEN = vec3(0.10, 1.00, 0.32);
const vec3 FILL_GREEN = vec3(0.04, 0.22, 0.09);
// CRT layer gain relative to the outline readout (plan: static/bar at 0.4×).
const float CRT_WEIGHT = 0.4;
// [F-102] Hex shell: integer longitude repeat (seam law), latitude scale, edge line width
// in lattice units, and the far-distance gate that finds the hull (shell radius 48..72).
const float HEX_LON = 26.0;
const float HEX_LAT = 15.0;
const float HEX_LINE = 0.07;
const float HEX_NEAR = 30.0;
const float HEX_FAR = 70.0;

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    vec3 color = scene;

    if (s > 0.0005) { // else: idle — the scene passes through bit-identical
        float detail = clamp(Detail, 0.0, 1.0);

        // ===================== 1) OUTLINE READOUT — unshifted texCoord =====================
        vec2 texel = 1.0 / vec2(textureSize(DiffuseSampler0, 0));
        float near = VeilCamera.NearPlane;
        float far = VeilCamera.FarPlane;

        // 5-tap cross: raw depth (position reconstruction) + linearized (edges).
        float dC = texture(DiffuseDepthSampler, texCoord).r;
        float dR = texture(DiffuseDepthSampler, texCoord + vec2(texel.x, 0.0)).r;
        float dL = texture(DiffuseDepthSampler, texCoord - vec2(texel.x, 0.0)).r;
        float dU = texture(DiffuseDepthSampler, texCoord + vec2(0.0, texel.y)).r;
        float dD = texture(DiffuseDepthSampler, texCoord - vec2(0.0, texel.y)).r;
        float depthOk = gzDepthValid(dC);
        float lC = gzLinearDepth(dC, near, far);
        float lR = gzLinearDepth(dR, near, far);
        float lL = gzLinearDepth(dL, near, far);
        float lU = gzLinearDepth(dU, near, far);
        float lD = gzLinearDepth(dD, near, far);

        // Depth term: second derivative of linear depth (silhouettes + creases).
        float depthEdge = (abs(lR + lL - 2.0 * lC) + abs(lU + lD - 2.0 * lC)) / max(lC * 0.5, 0.5);
        depthEdge = smoothstep(0.06, 0.22, depthEdge);

        // Normal term: reconstructed view-space normal disagreement.
        vec3 pC = screenToViewSpace(texCoord, dC).xyz;
        vec3 pR = screenToViewSpace(texCoord + vec2(texel.x, 0.0), dR).xyz;
        vec3 pL = screenToViewSpace(texCoord - vec2(texel.x, 0.0), dL).xyz;
        vec3 pU = screenToViewSpace(texCoord + vec2(0.0, texel.y), dU).xyz;
        vec3 pD = screenToViewSpace(texCoord - vec2(0.0, texel.y), dD).xyz;
        vec3 n1 = gzNormalizeSafe(cross(pR - pC, pU - pC), vec3(0.0, 0.0, 1.0));
        vec3 n2 = gzNormalizeSafe(cross(pC - pL, pC - pD), vec3(0.0, 0.0, 1.0));
        float normalEdge = smoothstep(0.10, 0.55, 1.0 - dot(n1, n2));

        // Luminance term (Roberts): texture/block boundaries as faint secondary traces, and
        // the only term left standing on a dead depth buffer.
        float lumaEdge = abs(gzLuma(texture(DiffuseSampler0, texCoord + vec2(texel.x, 0.0)).rgb)
                        - gzLuma(texture(DiffuseSampler0, texCoord - vec2(texel.x, 0.0)).rgb))
                + abs(gzLuma(texture(DiffuseSampler0, texCoord + vec2(0.0, texel.y)).rgb)
                        - gzLuma(texture(DiffuseSampler0, texCoord - vec2(0.0, texel.y)).rgb));
        lumaEdge = smoothstep(0.12, 0.45, lumaEdge) * 0.35;

        float sky = step(0.9999, dC);
        float distanceFade = 1.0 / (1.0 + lC * 0.006);
        float edge = clamp((depthEdge + normalEdge) * depthOk + lumaEdge, 0.0, 1.0)
                * (1.0 - sky) * distanceFade;

        // Sweep bar + flicker + grain (outline heritage, frozen under reduced FX).
        float flicker = mix(1.0, 0.82 + 0.18 * efxNoise(vec2(Time * 24.0, texCoord.y * 3.0)), detail);
        float sweepPos = fract(Time * 0.11) * 1.3 - 0.15;
        float sweep = exp(-abs(texCoord.y - sweepPos) * 40.0) * detail;
        float grain = (efxHash(texCoord * vec2(853.0, 997.0) + fract(Time * 7.0)) - 0.5) * 0.05 * detail;

        // Accent mechanics (F-049) — identical derivation to glitch_outline.
        vec3 edgeAccent = gzAccent(EDGE_GREEN, AccentColor, AccentAmount);
        vec3 fillAccent = mix(FILL_GREEN, edgeAccent * (gzLuma(FILL_GREEN) / gzLuma(EDGE_GREEN)),
                clamp(AccentAmount, 0.0, 1.0));
        vec3 grainAccent = mix(vec3(0.0, 1.0, 0.4), edgeAccent / max(gzLuma(edgeAccent), 0.001) * 0.65,
                clamp(AccentAmount, 0.0, 1.0));

        vec3 readout = fillAccent * gzLuma(scene) * 0.30 * (1.0 - sky)
                + edgeAccent * edge * (0.85 * flicker + 0.45 * sweep)
                + edgeAccent * 0.02 * sweep
                + grainAccent * grain;

        // ================ 1b) HEX SHELL — the dome interface (F-102) ======================
        // View-ray sphere coordinates; the longitude repeat is an integer so the atan seam
        // is invisible. Painted only where the world is far (the hull / the sky) — the
        // mansion around the player stays a clean scanner readout.
        vec3 ray = viewDirFromUv(texCoord);
        float lon = atan(ray.z, ray.x) * 0.15915494 + 0.5;
        vec2 hex = gzHex(vec2(lon * HEX_LON, ray.y * HEX_LAT));
        float hexEdge = smoothstep(HEX_LINE, 0.0, hex.x);
        // Per-cell breathing on the shared 5 s twinkle divisor; parked mid-glow at Detail 0.
        float cellPulse = mix(0.75, 0.60 + 0.40 * sin(Time * GZ_TWINKLE_RATE + hex.y * 39.0), detail);
        // Fresnel toward the horizon: grazing rays hit the dome equator — the bright edge.
        float fresnel = pow(1.0 - clamp(abs(ray.y), 0.0, 1.0), 3.0);
        // Far gate: sky counts as infinitely far; a dead depth buffer collapses lC to the
        // near plane and closes the gate.
        float shellVis = max(smoothstep(HEX_NEAR, HEX_FAR, lC) * depthOk, sky);
        readout += edgeAccent * hexEdge * cellPulse * (0.10 + 0.35 * fresnel) * shellVis
                + fillAccent * (0.35 + 0.65 * fresnel) * 0.30 * shellVis;

        // ================= 2) CRT LAYERS — pattern UVs only, readout input =================
        // Vertical-hold jitter: irregular gated frame slips (~3 rolls/s window). Shifts the
        // PATTERN space the scanline mask/static live in — the depth readout above already
        // happened on the true texCoord (merge law).
        vec2 crtUv = texCoord;
        float holdSeed = floor(Time * 3.1);
        float holdGate = step(0.55, efxHash(vec2(holdSeed, 7.7))) * detail;
        crtUv.y = fract(crtUv.y + holdGate * (efxHash(vec2(holdSeed, 13.1)) - 0.5) * 0.06 * s);

        // Rolling scan bar (upward) with in-band sideways pattern shove.
        float barPos = 1.0 - fract(Time * 0.20);
        float bar = exp(-abs(crtUv.y - barPos) * 55.0) * detail;
        crtUv.x += bar * (efxNoise(vec2(crtUv.y * 90.0, Time * 8.0)) - 0.5) * 0.03 * s;

        // Fine scanlines + aperture grille on the readout (the line mask is the CRT read).
        float lines = 0.5 + 0.5 * sin(crtUv.y * 720.0 * 3.14159265);
        readout *= 1.0 - (0.22 * lines + 0.05 * (0.5 + 0.5 * sin(crtUv.x * 1080.0 * 3.14159265))) * s;

        // Tape static + bar glow, both at 0.4× the scanlines-effect strength (plan §4.3a).
        float static_ = (efxHash(crtUv * vec2(911.0, 631.0) + fract(Time * 11.0)) - 0.5)
                * 0.12 * s * detail * CRT_WEIGHT;
        readout += grainAccent * static_;
        readout += edgeAccent * bar * 0.10 * s * CRT_WEIGHT
                * (0.5 + 0.5 * efxNoise(vec2(crtUv.x * 40.0, Time * 12.0)));

        // Scanner vignette: the readout sits inside a tube.
        float vign = 1.0 - 0.35 * smoothstep(0.45, 0.95, length(texCoord - 0.5) * 1.5);
        readout *= vign;

        // Ramp law: bit-exact passthrough at 0 (idle branch), full readout at 1.
        color = mix(scene, readout, s);
        color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s);
    }

    fragColor = vec4(color, 1.0);
}
