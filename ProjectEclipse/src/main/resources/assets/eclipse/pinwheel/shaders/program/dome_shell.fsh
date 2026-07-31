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
// (tick-clock seconds), Detail (0 freezes the motion layers; grade survives),
// TouchPos/TouchAge/TouchStrength (W13-C3 touch-intersection pulse: the last
// player/projectile hull contact, camera-relative point + seconds since + envelope;
// TouchAge < 0 = no pulse live).
//
// F-102 GLITCH-FAMILY POLISH:
//   * The "hex/cell shimmer" was noise pretending to be cells. It is now a TRUE HEX
//     LATTICE on the sphere coordinates (gzHex — one mod-pair, pure ALU), TWO layers with
//     slightly different scales counter-drifting so their borders beat into a slow
//     interference moire crawling over the hull; each cell breathes on its own hash phase.
//     Longitude repeats are INTEGERS so the atan seam lands on whole lattice periods.
//   * The Fresnel rim (already the pass's backbone) now weights the hex borders 4:1 over
//     face-on cells — the lattice reads strongest exactly on the "Fresnel-Kante".
//   * The touch pulse REVEALS THE LATTICE: the expanding ring is brightest where it
//     crosses hex borders, so a hit lights the shell up cell by cell.
//   * All four value-less `return`s are gone (nested ifs). They compiled fine, but they
//     were latent glsl-processor landmines: one future hash character in any comment here
//     would have NPE'd the parser and silently unregistered the pipeline (the
//     umbral_veins/black_hole lesson).
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
uniform vec3 TouchPos;
uniform float TouchAge;
uniform float TouchStrength;

in vec2 texCoord;

out vec4 fragColor;

// The dome phosphor green (GlitchColors / DomeShellRenderer palette).
const vec3 DOME_GREEN = vec3(0.30, 0.95, 0.62);
// Hull-hit tolerance in blocks: the CPU shell writes depth at the analytic radius; the
// LOD sphere is a polyhedron, so its surface sits up to ~1.5% inside the true sphere.
const float HIT_TOLERANCE = 3.0;
// [F-102] Hex interference: primary/secondary lattice scales (longitude counts INTEGER —
// the seam law), border line widths in lattice units, and the counter-drift rates.
const float HEXA_LON = 26.0;
const float HEXA_LAT = 15.0;
const float HEXB_LON = 28.0;
const float HEXB_LAT = 16.0;
const float HEX_LINE = 0.07;

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    vec3 color = scene;

    // All gates are NESTED (no value-less returns — the glsl-processor landmine law).
    if (s > 0.0005 && DomeRadius > 1.0) {
        // Camera-relative world ray (camera at the origin — VeilCamera local space).
        vec3 rd = viewDirFromUv(texCoord);
        float bq = dot(DomeCenter, rd);
        float disc = bq * bq - (dot(DomeCenter, DomeCenter) - DomeRadius * DomeRadius);
        // Ray must hit the sphere, in front of the camera (a camera inside the bubble is
        // already Strength 0 from the feeder; tHit <= 0 covers the remaining sliver).
        if (disc > 0.0 && bq > 0.0) {
            float tHit = bq - sqrt(disc); // near intersection — the visible hull surface
            // Scene-depth gate: the effect lives ON the hull. Terrain in front of the
            // shell (sceneDist far below tHit) masks it; sky pixels never carry the hull.
            float depth = texture(DiffuseDepthSampler, texCoord).r;
            float sceneDist = depth >= 0.9999 ? 1.0e7
                    : length(screenToLocalSpace(texCoord, depth).xyz);
            float hitVis = 1.0 - smoothstep(HIT_TOLERANCE, HIT_TOLERANCE * 2.0,
                    max(tHit - sceneDist, 0.0));
            if (tHit > 0.0 && depth < 0.9999 && hitVis > 0.001) {
                // Hull-hit frame: outward normal, Fresnel rim, sphere coordinates.
                vec3 n = normalize(rd * tHit - DomeCenter);
                float rim = pow(1.0 - abs(dot(rd, n)), 2.0);
                float lon = atan(n.z, n.x) * 0.15915494 + 0.5; // 1/(2 pi)
                float lat = n.y * 0.5 + 0.5;
                float detail = clamp(Detail, 0.0, 1.0);
                float t = Time * detail; // Detail 0 freezes every motion layer in place

                // (a) Heat-shimmer distortion: screen-UV offset from sphere-normal glitch
                // noise — what you see THROUGH the rim band is the hull surface wobbling.
                vec2 wobble = vec2(
                        efxNoise(vec2(lon * 46.0 + t * 0.9, lat * 30.0)) - 0.5,
                        efxNoise(vec2(lat * 38.0 - t * 1.3, lon * 52.0 + 7.7)) - 0.5);
                vec2 duv = wobble * (0.0035 + 0.0110 * rim) * s * hitVis;
                vec2 uvD = clamp(texCoord + duv, vec2(0.001), vec2(0.999));

                // (b) Chromatic aberration at the rim (split along the wobble direction).
                float aber = (0.0008 + 0.0042 * rim) * s * hitVis;
                vec3 shell = efxChroma(DiffuseSampler0, uvD,
                        normalize(duv + vec2(1.0e-4, 0.0)), aber);

                // (c) [F-102] TRUE HEX INTERFERENCE on sphere coordinates: two lattices at
                // slightly different scales counter-drift in latitude, so their border sets
                // beat into a slow moire crawling over the hull. Cell hash -> per-cell
                // breathing phase; everything parks at Detail 0.
                vec2 hexA = gzHex(vec2(lon * HEXA_LON, lat * HEXA_LAT + t * 0.05));
                vec2 hexB = gzHex(vec2(lon * HEXB_LON, lat * HEXB_LAT - t * 0.04));
                float borderA = smoothstep(HEX_LINE, 0.0, hexA.x);
                float borderB = smoothstep(HEX_LINE * 1.3, 0.0, hexB.x);
                float cellPulse = 0.65 + 0.35 * sin(t * 1.3 + hexA.y * 39.0);
                float hexGlow = borderA * cellPulse + borderB * 0.45;

                // (d) Scanline flicker on latitude bands (the CPU shell's scroll, echoed).
                float lines = 0.5 + 0.5 * sin((lat * 90.0 - t * 1.6) * 6.2831853);
                float flicker = mix(1.0,
                        0.85 + 0.15 * efxHash(vec2(floor(t * 9.0), lat * 5.0)), detail);

                // (e) Touch-intersection pulse (W13-C3): an expanding Fresnel ring racing
                // away from the last contact point ON the hull — chord distance from the
                // hit point, front at 7 blocks/s, wake widening 1.4 -> ~3.6 blocks, 1.1 s
                // fade. [F-102] The ring now REVEALS THE LATTICE: brightest where it
                // crosses hex borders, so a hit lights the shell up cell by cell.
                float touch = 0.0;
                if (TouchAge >= 0.0 && TouchStrength > 0.001) {
                    float chord = distance(rd * tHit, TouchPos);
                    float front = 1.5 + TouchAge * 7.0;
                    float band = 1.4 + TouchAge * 2.0;
                    float ring = 1.0 - smoothstep(0.0, band, abs(chord - front));
                    float fade = 1.0 - smoothstep(0.0, 1.1, TouchAge);
                    touch = ring * fade * TouchStrength * (0.35 + 0.65 * rim)
                            * (0.45 + 0.85 * borderA);
                }

                // Composite: additive green energy over the opaque hull. The hex borders
                // are Fresnel-weighted 4:1 (edge-on vs face-on), so the lattice reads
                // strongest exactly on the rim — the mandate's "Fresnel-Kante".
                float energy = (0.10 + 0.55 * rim) * (0.6 + 0.4 * lines) * flicker
                        + 0.34 * hexGlow * (0.25 + 0.75 * rim);
                color = mix(scene, shell, clamp(s * hitVis * (0.35 + 0.65 * rim), 0.0, 1.0));
                color += DOME_GREEN * energy * s * hitVis * 0.5;
                color += DOME_GREEN * touch * s * hitVis * 0.85;
                color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s * hitVis);
            }
        }
    }

    fragColor = vec4(color, 1.0);
}
