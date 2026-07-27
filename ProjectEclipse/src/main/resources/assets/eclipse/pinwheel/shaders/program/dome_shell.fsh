// eclipse:dome_shell — WOAH-01 mansion-dome OUTSIDE garnish (FEATURE priority): a thin
// full-screen pass that dresses the already-OPAQUE CPU shell (DomeShellRenderer) with
// per-pixel life — screen-UV heat-shimmer distortion driven by sphere-normal glitch
// noise, a hex/cell shimmer crawling on sphere coordinates, chromatic aberration at the
// rim and scanline flicker. Deliberately ANALYTIC (plan §12.9): ONE ray/sphere solve and
// zero march loops — storm_volume's fBm raymarch must NOT be copied here, the camera can
// stand right at the hull (near-fullscreen coverage). The pass is pure garnish: with it
// evicted/fused/Iris-gated the opaque hull still guarantees "you cannot see in".
//
// Fed per frame by woah.mansiondome.client.MansionDomeClient (allocation-free feeder):
// DomeCenter (CAMERA-RELATIVE — the VolCenter law, subtraction in doubles Java-side),
// DomeRadius (blocks), Strength (0..1: distance ramp 450→600 × visibility × collapse
// pulse; 0 inside the bubble and under reducedFx — the pass never runs there), Time
// (tick-clock seconds), Detail (0 freezes the motion layers; grade survives).
#include eclipse:eclipse_common
#include eclipse:eclipse_glitch
#include veil:space_helper

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform vec3 DomeCenter;
uniform float DomeRadius;
uniform float Strength;
uniform float Time;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

// The dome phosphor green (GlitchColors / DomeShellRenderer palette).
const vec3 DOME_GREEN = vec3(0.30, 0.95, 0.62);
// Hull-hit tolerance in blocks: the CPU shell writes depth at the analytic radius; the
// LOD sphere is a polyhedron, so its surface sits up to ~1.5% inside the true sphere.
const float HIT_TOLERANCE = 3.0;

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    if (s <= 0.0005 || DomeRadius <= 1.0) {
        fragColor = vec4(scene, 1.0);
        return;
    }

    // Camera-relative world ray (camera at the origin — VeilCamera local space).
    vec3 rd = viewDirFromUv(texCoord);
    float bq = dot(DomeCenter, rd);
    float disc = bq * bq - (dot(DomeCenter, DomeCenter) - DomeRadius * DomeRadius);
    if (disc <= 0.0 || bq <= 0.0) {
        fragColor = vec4(scene, 1.0); // ray misses the sphere / dome fully behind camera
        return;
    }
    float tHit = bq - sqrt(disc); // near intersection — the visible hull surface
    if (tHit <= 0.0) {
        fragColor = vec4(scene, 1.0); // camera inside (feeder already sends Strength 0)
        return;
    }

    // Scene-depth gate: the effect lives ON the hull. Terrain in front of the shell
    // (sceneDist ≪ tHit) masks it; sky pixels never carry the hull either.
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    float sceneDist = depth >= 0.9999 ? 1.0e7 : length(screenToLocalSpace(texCoord, depth).xyz);
    float hitVis = 1.0 - smoothstep(HIT_TOLERANCE, HIT_TOLERANCE * 2.0,
            max(tHit - sceneDist, 0.0));
    if (depth >= 0.9999 || hitVis <= 0.001) {
        fragColor = vec4(scene, 1.0);
        return;
    }

    // Hull-hit frame: outward normal, Fresnel rim, sphere coordinates.
    vec3 n = normalize(rd * tHit - DomeCenter);
    float rim = pow(1.0 - abs(dot(rd, n)), 2.0);
    float lon = atan(n.z, n.x) * 0.15915494 + 0.5; // 1/(2π)
    float lat = n.y * 0.5 + 0.5;
    float detail = clamp(Detail, 0.0, 1.0);
    float t = Time * detail; // Detail 0 freezes every motion layer in place

    // (a) Heat-shimmer distortion: screen-UV offset from sphere-normal glitch noise —
    // what you see THROUGH the rim band is the hull surface wobbling, not the interior.
    vec2 wobble = vec2(
            efxNoise(vec2(lon * 46.0 + t * 0.9, lat * 30.0)) - 0.5,
            efxNoise(vec2(lat * 38.0 - t * 1.3, lon * 52.0 + 7.7)) - 0.5);
    vec2 duv = wobble * (0.0035 + 0.0110 * rim) * s * hitVis;
    vec2 uvD = clamp(texCoord + duv, vec2(0.001), vec2(0.999));

    // (b) Chromatic aberration at the rim (efxChroma splits along the wobble direction).
    float aber = (0.0008 + 0.0042 * rim) * s * hitVis;
    vec3 shell = efxChroma(DiffuseSampler0, uvD,
            normalize(duv + vec2(1.0e-4, 0.0)), aber);

    // (c) Hex/cell shimmer crawling on sphere coordinates (slow yaw drift).
    float cells = efxNoise(vec2(lon * 60.0 + t * 0.05, lat * 34.0));
    float hex = smoothstep(0.55, 0.95, cells);

    // (d) Scanline flicker on latitude bands (the CPU shell's scroll, echoed per-pixel).
    float lines = 0.5 + 0.5 * sin((lat * 90.0 - t * 1.6) * 6.2831853);
    float flicker = mix(1.0, 0.85 + 0.15 * efxHash(vec2(floor(t * 9.0), lat * 5.0)), detail);

    // Composite: additive green energy over the opaque hull, rim-weighted.
    float energy = (0.10 + 0.55 * rim) * (0.6 + 0.4 * lines) * flicker
            + 0.30 * hex * (0.3 + 0.7 * rim);
    vec3 color = mix(scene, shell, clamp(s * hitVis * (0.35 + 0.65 * rim), 0.0, 1.0));
    color += DOME_GREEN * energy * s * hitVis * 0.5;
    color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s * hitVis);

    fragColor = vec4(color, 1.0);
}
