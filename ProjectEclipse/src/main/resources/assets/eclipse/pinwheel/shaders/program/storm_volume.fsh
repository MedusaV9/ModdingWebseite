// eclipse:storm_volume — TRUE VOLUMETRIC storm mass for C8 SPHERE storms (STORM-VOL
// round; FEATURE priority). A single-storm raymarcher: analytic ray/ellipsoid entry,
// scene-depth-clamped Beer–Lambert march through a domain-warped fBm density field with
// differential rotation, log-spiral rainbands, an anvil/skirt height profile and a
// cauliflower tower term on the silhouette; lit by cheap single scattering (3-tap sun
// self-shadow + Henyey–Greenstein forward lobe + height-graded ambient) and the W-B
// intra-wall flash injected as emissive light INSIDE the mass. The opaque occluder dome
// keeps writing depth, so outside cameras march the entry→occluder band (the wall reads
// meters thick) and silhouette rays march the full chord (the rim reads as a lumpy ball
// of weather, not a shell). Composite is premultiplied-over: scene · transmittance +
// in-scatter. Uniforms are fed per frame by stormfx.StormVolumeFx through the
// VeilPostController row (never under an Iris shaderpack; StormWallRenderer's shell
// stack is the fallback there): VolCenter (camera-relative), VolRadius, VolYScale,
// Visibility, Strength, StepCount, Time, SunDir, Interior, FlashPos, FlashAmount.
#include eclipse:eclipse_volume
#include veil:space_helper

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform vec3 VolCenter;
uniform float VolRadius;
uniform float VolYScale;
uniform float Visibility;
uniform float Strength;
uniform float StepCount;
uniform float Time;
uniform vec3 SunDir;
uniform float Interior;
uniform vec3 FlashPos;
uniform float FlashAmount;

in vec2 texCoord;

out vec4 fragColor;

// Extinction per (density · block) — the dense band goes near-opaque over ~8–14 blocks.
const float ABSORB = 0.55;
// Overall density multiplier. Drives how heavy the mass reads from outside.
const float DENSITY_GAIN = 1.55;
// Base noise frequency in storm-normalized space (features ~ R/2.6 with octaves below).
const float NOISE_FREQ = 2.6;
// Differential rotation base speed (rad/s at stratum speed 1.0) — the churn read.
const float ROT_SPEED = 0.10;
// Upward scroll of the noise field (normalized units/s) — billows rise inside the mass.
const float UPDRAFT = 0.018;
// Self-shadow tap spacing in storm-normalized units. AUDITFIX-4: 3 taps at 0.12 keep the
// pre-audit ~0.36·R reach AND optical depth of the old 4 taps at 0.09 (the transmittance
// term multiplies the tap sum by this spacing), at 3/4 of the samples.
const float SHADOW_STEP_N = 0.12;
// Silhouette headroom beyond the nominal radius (anvil bulge + tower lumps live there).
// Must exceed max(rEff) · 1.05, otherwise the bounds sphere clips the lumps flat and
// prints back the perfectly round edge the lumps exist to break. Empty-space skipping
// pays for the extra slack.
const float BOUNDS_MARGIN = 1.55;
// Spiral rainband arm count and log-spiral winding factor.
const float ARMS = 3.0;
const float SPIRAL_WIND = 2.4;

// W-A §A3 stratum ladder as a smooth curve of normalized height: heavy slow base 0.6×,
// mid 1.0×, fast upper 1.5×, counter-rotating polar cap −0.8× — the wind strata read.
float stratumSpeed(float ny) {
    float s = mix(0.6, 1.0, smoothstep(0.00, 0.35, ny));
    s = mix(s, 1.5, smoothstep(0.35, 0.70, ny));
    return mix(s, -0.8, smoothstep(0.78, 0.98, ny));
}

// Storm density at u = (worldPos − centre) / R with y pre-divided by VolYScale.
// detail 1.0 = camera ray (5-octave fBm + curl warp), 0.0 = shadow ray (AUDITFIX-4 diet:
// 2-octave, UNWARPED — shadows need the coarse mass, not billow detail; skipping the
// warp saves its three evNoise3 evaluations per tap).
float stormDensity(vec3 u, float detail) {
    float ny = u.y;
    float lenH = length(u);
    if (lenH > BOUNDS_MARGIN || ny > 1.22 || ny < -0.20) {
        return 0.0;
    }
    // Differential rotation: angular velocity varies with height (stratum ladder) AND
    // radius (inner mass leads the rim) — sampling position, not geometry, rotates.
    float spin = Time * ROT_SPEED * stratumSpeed(clamp(ny, 0.0, 1.0))
            * (1.4 - 0.7 * clamp(lenH, 0.0, 1.0));
    float cs = cos(spin);
    float sn = sin(spin);
    vec3 q = vec3(cs * u.x - sn * u.z, u.y, sn * u.x + cs * u.z);

    // Silhouette shaping: cauliflower towers (hi-freq lumps gated to the outer band),
    // an anvil/overhang bulge near the top and a flared skirt near the base all modulate
    // the EFFECTIVE radius, so the outline is lumpy and towered — never a perfect ball.
    // Two scales of lump: big bulges that break the circle at a glance, plus cauliflower
    // detail on top. A ±10% ripple reads as a perfect ball from any real viewing distance,
    // so the coarse term carries most of the amplitude.
    float tower = evNoise3(q * 5.0 + vec3(0.0, -Time * 0.05, 0.0));
    float bulge = evNoise3(q * 1.7 + vec3(0.0, -Time * 0.02, 11.3));
    float anvil = smoothstep(0.45, 0.72, ny) * (1.0 - smoothstep(0.80, 1.00, ny));
    float skirt = 1.0 - smoothstep(0.00, 0.30, ny);
    float lumpGate = smoothstep(0.42, 0.92, lenH);
    float rEff = 1.0
            + 0.12 * anvil
            + 0.06 * skirt
            + 0.30 * (bulge - 0.42) * lumpGate
            + 0.17 * (tower - 0.38) * smoothstep(0.62, 0.98, lenH);
    float rl = lenH / max(rEff, 0.5);

    // Radial shell profile: a THICK density band peaking mid-wall, a hollow-ish eye at
    // the core (thin haze floor keeps it breathing) and a soft falloff past the rim.
    float band = smoothstep(0.30, 0.62, rl) * (1.0 - smoothstep(0.94, 1.05, rl));
    float prof = max(band, 0.10 * smoothstep(0.08, 0.30, rl));
    // Vertical profile: fade over the apex, cut below the ground skirt, thicken the base.
    prof *= 1.0 - smoothstep(0.92, 1.04, ny);
    prof *= smoothstep(-0.18, -0.06, ny);
    prof *= 1.0 + 0.5 * skirt * band;
    if (prof <= 0.003) {
        return 0.0;
    }

    // Log-spiral rainbands: 3 arms wind through the rotating frame (θ − k·ln r = const)
    // with a slight vertical wrap — the satellite-photo hurricane banding in 3D.
    float theta = atan(q.z, q.x);
    float sp = fract(theta * (ARMS / 6.2831853) + log(max(rl, 0.15)) * SPIRAL_WIND
            + ny * 0.35);
    float arm = smoothstep(0.15, 0.42, sp) * (1.0 - smoothstep(0.58, 0.85, sp));
    float armMul = 0.72 + 0.55 * arm;

    // Domain-warped fBm body: the warp folds the octaves into billowing curls (camera
    // rays only — shadow rays read the cheap unwarped 2-octave mass, see header).
    vec3 np = q * NOISE_FREQ + vec3(0.0, -Time * UPDRAFT * NOISE_FREQ, 0.0);
    float body;
    if (detail > 0.5) {
        body = evFbm5(np + evCurlWarp(np * 0.5, Time));
    } else {
        body = evFbm2(np);
    }
    // Remap so the noise CARVES holes through the profile instead of only dimming it.
    // DENSITY_GAIN keeps the mass heavy: at 1.0 the ball reads as thin haze from a
    // distance because the average sample sits well below the peak.
    return max(prof * armMul * (body * 1.5 - 0.35), 0.0) * DENSITY_GAIN;
}

// Single scattering at one sample: 3 cheap self-shadow taps toward the sun (AUDITFIX-4;
// same reach and optical depth as the old 4 — see SHADOW_STEP_N), forward-scatter phase
// (fed in), height-graded ambient (dark violet base → sick green top — the C8 sphere
// palette), and the intra-wall flash as emissive light inside the mass.
vec3 volumeLight(vec3 pos, vec3 u, float phase, float densMul) {
    vec3 sdir = normalize(SunDir + vec3(0.0, 1.0e-4, 0.0));
    vec3 us = vec3(sdir.x, sdir.y / max(VolYScale, 0.05), sdir.z) * SHADOW_STEP_N;
    float sh = stormDensity(u + us, 0.0);
    sh += stormDensity(u + us * 2.0, 0.0);
    sh += stormDensity(u + us * 3.0, 0.0);
    float lightT = exp(-sh * densMul * SHADOW_STEP_N * VolRadius * ABSORB);
    // Bone-white day sun → moon-silver night (the renderer's rim-scatter palette).
    float dayness = clamp(SunDir.y * 2.6, 0.0, 1.0);
    vec3 sunCol = mix(vec3(0.72, 0.76, 0.90) * 0.25, vec3(0.85, 0.82, 0.74), dayness);
    vec3 ambient = mix(vec3(0.052, 0.060, 0.082), vec3(0.088, 0.152, 0.120),
            clamp(u.y, 0.0, 1.0)) * (1.15 + 1.35 * dayness);
    // Multiple-scattering approximation: deep cloud is not black, light diffuses into it.
    // sqrt(lightT) with an isotropic lobe lifts the shadowed mass into readable grey so
    // the layering is visible from outside instead of crushing to a silhouette.
    // Keep the multi-scatter lift modest: too much and the whole ball flattens into a
    // uniform pale smudge with no lit/shaded read at all.
    float ms = lightT * sqrt(clamp(lightT, 0.0, 1.0));
    vec3 col = sunCol * (lightT * phase * 4.6 + ms * 0.20) + ambient;
    if (FlashAmount > 0.004) {
        float fd = length(pos - FlashPos);
        col += vec3(0.70, 0.58, 1.00)
                * (FlashAmount * 2.5 * exp(-fd / (0.30 * VolRadius)));
    }
    return col;
}

void main() {
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    float strength = clamp(Strength, 0.0, 1.0) * clamp(Visibility, 0.0, 1.0);
    if (strength <= 0.004 || VolRadius <= 1.0) {
        fragColor = vec4(scene, 1.0);
        return;
    }

    // Camera-relative world ray (VeilCamera local space; camera at the origin).
    vec3 rd = viewDirFromUv(texCoord);
    // Ellipsoid → sphere: squash y by VolYScale (spawn/dissipate vertical scale), then
    // solve the quadratic against the margin-padded radius. t stays in world blocks
    // because origin and direction are squashed consistently.
    vec3 oS = -VolCenter;
    oS.y /= VolYScale;
    vec3 dS = vec3(rd.x, rd.y / VolYScale, rd.z);
    float R = VolRadius * BOUNDS_MARGIN;
    float aq = dot(dS, dS);
    float bq = dot(oS, dS);
    float disc = bq * bq - aq * (dot(oS, oS) - R * R);
    if (disc <= 0.0) {
        fragColor = vec4(scene, 1.0); // early out: the ray misses the storm bounds
        return;
    }
    float sq = sqrt(disc);
    float t0 = max((-bq - sq) / aq, 0.0);
    float t1 = (-bq + sq) / aq;

    // Scene depth clamp: terrain (and the opaque occluder dome) correctly hides the
    // volume behind it. Depth ≥ ~1 is sky — no clamp (and no unstable reconstruction).
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    float sceneDist = depth >= 0.9999 ? 1.0e7
            : length(screenToLocalSpace(texCoord, depth).xyz);
    t1 = min(t1, sceneDist);
    if (t1 <= t0) {
        fragColor = vec4(scene, 1.0);
        return;
    }

    // Step budget from Java (AUDITFIX-4: config tier 64/40/24 × screen-coverage ramp,
    // hard-capped at 48 when the storm nearly fills the screen — StormVolumeFx.stepCount),
    // further reduced per pixel for distant entry points along this ray.
    float steps = clamp(StepCount, 12.0, 64.0);
    steps = clamp(steps * clamp(140.0 / max(t0, 1.0), 0.35, 1.0), 12.0, 64.0);
    float dt0 = (t1 - t0) / steps;
    // Interleaved-gradient-noise start dither + temporal drift — kills the shell banding
    // a fixed march start would print into the fog.
    float dith = fract(52.9829189
            * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715)))
            + fract(Time * 61.803));

    // Deep inside the storm the interior grade + pinched fog own the frame; the volume
    // eases off so the two systems hand over instead of stacking to black.
    float densMul = strength * (1.0 - 0.35 * clamp(Interior, 0.0, 1.0));
    float mu = dot(rd, normalize(SunDir + vec3(0.0, 1.0e-4, 0.0)));
    float phase = mix(0.0795775, evHgPhase(mu, 0.45), 0.72); // silver-lining lobe
    float invR = 1.0 / VolRadius;
    float invY = 1.0 / max(VolYScale, 0.05);

    float trans = 1.0;
    vec3 acc = vec3(0.0);
    float t = t0 + dith * dt0;
    for (int i = 0; i < 64; i++) {
        if (t >= t1 || trans < 0.01 || float(i) >= steps) {
            break; // early exits: segment done / mass opaque / step budget spent
        }
        float dt = dt0 * (1.0 + t * 0.0025); // step-size growth along the ray
        vec3 pos = rd * t;
        vec3 lp = pos - VolCenter;
        lp.y *= invY;
        vec3 u = lp * invR;
        float dens = stormDensity(u, 1.0) * densMul;
        if (dens < 0.004) {
            t += dt * 1.6; // empty-space acceleration through the eye / between towers
            continue;
        }
        float newTrans = trans * exp(-dens * dt * ABSORB);
        acc += volumeLight(pos, u, phase, densMul) * (trans - newTrans);
        trans = newTrans;
        t += dt;
    }

    // Premultiplied over: in-scatter is already weighted by per-step opacity.
    fragColor = vec4(scene * trans + acc, 1.0);
}
