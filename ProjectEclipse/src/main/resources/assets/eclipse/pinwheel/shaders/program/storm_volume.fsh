// eclipse:storm_volume — TRUE VOLUMETRIC storm mass for C8 SPHERE storms (STORM-VOL
// round; FEATURE priority). A single-storm raymarcher: analytic ray/ellipsoid entry,
// scene-depth-clamped Beer–Lambert march through a domain-warped fBm density field with
// differential rotation, log-spiral rainbands, an anvil/skirt height profile and a
// cauliflower tower term on the silhouette; lit by cheap single scattering (4-tap sun
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
// Base noise frequency in storm-normalized space (features ~ R/2.6 with octaves below).
const float NOISE_FREQ = 2.6;
// Differential rotation base speed (rad/s at stratum speed 1.0) — the churn read.
const float ROT_SPEED = 0.10;
// Upward scroll of the noise field (normalized units/s) — billows rise inside the mass.
const float UPDRAFT = 0.018;
// Self-shadow tap spacing in storm-normalized units (4 taps → ~0.4·R reach).
const float SHADOW_STEP_N = 0.09;
// Silhouette headroom beyond the nominal radius (anvil bulge + tower lumps live there).
const float BOUNDS_MARGIN = 1.18;
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
// detail 1.0 = camera ray (5-octave fBm), 0.0 = shadow ray (3-octave).
float stormDensity(vec3 u, float detail) {
    float ny = u.y;
    float lenH = length(u);
    if (lenH > BOUNDS_MARGIN || ny > 1.06 || ny < -0.20) {
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
    float tower = evNoise3(q * 5.0 + vec3(0.0, -Time * 0.05, 0.0));
    float anvil = smoothstep(0.45, 0.72, ny) * (1.0 - smoothstep(0.80, 1.00, ny));
    float skirt = 1.0 - smoothstep(0.00, 0.30, ny);
    float rEff = 1.0
            + 0.10 * anvil
            + 0.06 * skirt
            + 0.16 * (tower - 0.35) * smoothstep(0.62, 0.95, lenH);
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

    // Domain-warped fBm body: the warp folds the octaves into billowing curls.
    vec3 np = q * NOISE_FREQ + vec3(0.0, -Time * UPDRAFT * NOISE_FREQ, 0.0);
    vec3 warp = evCurlWarp(np * 0.5, Time);
    float body = detail > 0.5 ? evFbm5(np + warp) : evFbm3(np + warp);
    // Remap so the noise CARVES holes through the profile instead of only dimming it.
    return max(prof * armMul * (body * 1.5 - 0.35), 0.0);
}

// Single scattering at one sample: 4 cheap self-shadow taps toward the sun, forward-
// scatter phase (fed in), height-graded ambient (dark violet base → sick green top —
// the C8 sphere palette), and the intra-wall flash as emissive light inside the mass.
vec3 volumeLight(vec3 pos, vec3 u, float phase, float densMul) {
    vec3 sdir = normalize(SunDir + vec3(0.0, 1.0e-4, 0.0));
    vec3 us = vec3(sdir.x, sdir.y / max(VolYScale, 0.05), sdir.z) * SHADOW_STEP_N;
    float sh = stormDensity(u + us, 0.0);
    sh += stormDensity(u + us * 2.0, 0.0);
    sh += stormDensity(u + us * 3.0, 0.0);
    sh += stormDensity(u + us * 4.0, 0.0);
    float lightT = exp(-sh * densMul * SHADOW_STEP_N * VolRadius * ABSORB);
    // Bone-white day sun → moon-silver night (the renderer's rim-scatter palette).
    float dayness = clamp(SunDir.y * 2.6, 0.0, 1.0);
    vec3 sunCol = mix(vec3(0.72, 0.76, 0.90) * 0.25, vec3(0.85, 0.82, 0.74), dayness);
    vec3 ambient = mix(vec3(0.052, 0.060, 0.082), vec3(0.088, 0.152, 0.120),
            clamp(u.y, 0.0, 1.0)) * (0.45 + 0.55 * dayness);
    vec3 col = sunCol * (lightT * phase * 2.4) + ambient;
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

    // Quality-tier step count (64/40/24 from Java), further reduced for distant storms
    // (they cover few pixels AND need less depth resolution per pixel).
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
