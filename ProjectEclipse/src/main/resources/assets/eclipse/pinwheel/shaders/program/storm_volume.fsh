// eclipse:storm_volume — TRUE VOLUMETRIC storm mass for C8 SPHERE storms (STORM-VOL
// round; FEATURE priority). A single-storm raymarcher: analytic ray/ellipsoid entry,
// scene-depth-clamped Beer–Lambert march through a domain-warped fBm density field with
// differential rotation, log-spiral rainbands, an anvil/skirt height profile and a
// cauliflower tower term on the silhouette; lit by cheap single scattering (2/3-tap sun
// self-shadow + dual-lobe Henyey–Greenstein phase + height-graded ambient; STORM-MASS
// B1/B5 add Beer-powder edges, density-graded albedo, radial ambient occlusion and an
// analytic sun-hemisphere macro shadow — all pure math on samples the march already
// pays for) and the W-B intra-wall flash injected as emissive light INSIDE the mass.
// The opaque occluder dome
// keeps writing depth, so outside cameras march the entry→occluder band (the wall reads
// meters thick) and silhouette rays march the full chord (the rim reads as a lumpy ball
// of weather, not a shell).
//
// F-030 OPT: this pass now marches at HALF RESOLUTION into the pipeline's `volume_half`
// RGBA16F target and outputs PREMULTIPLIED in-scatter (rgb) + transmittance (a); the
// sibling eclipse:storm_volume_upsample stage bilateral-upsamples that against the
// full-res depth buffer and composites scene · a + rgb. Per-ray budget cuts on top:
// adaptive empty-space stepping with isosurface step-back refinement, the IGN start
// dither (kills banding at the lower step counts), an earlier transmittance early-out
// (< 0.02), an explicit distance LOD (steps halve as the entry point runs 160→320
// blocks out) and ShadowTaps 3 → 2 on low quality tiers (spacing rescaled so shadow
// reach AND optical depth are preserved). Uniforms are fed per frame by
// stormfx.StormVolumeFx through the VeilPostController row (never under an Iris
// shaderpack; StormWallRenderer's shell stack is the fallback there): VolCenter
// (camera-relative), VolRadius, VolYScale, Visibility, Strength, StepCount, ShadowTaps,
// DetailTier, Time, SunDir, Interior, FlashPos, FlashAmount, Flash2Pos, Flash2Amount,
// FlashSeed, SiegeChurn, ChurnTime, CoreFade.
//
// STORM-MASS (B2/B3): the density field is now TWO shells — the outer band carved by
// the fBm body, plus an inner counter-clocked shell (rl 0.16–0.50) built from the
// ANTI-PHASE body, so holes in the outer wall reveal a darker layer turning behind
// them — under a height profile v2 (wallcloud base ring, convection towers that raise
// the ceiling locally, a body-frayed anvil top). STORM-MASS (B4/B6): on tier 2 the
// curl warp gains a time-rotor + a second warp plane (billows FOLD instead of
// scrolling), and the intra-wall flash is now two independent cells lighting veiny
// filaments of the mass (all tiers, paid only while a flash is live).
#include eclipse:eclipse_volume
#include veil:space_helper

uniform sampler2D DiffuseDepthSampler;
uniform vec3 VolCenter;
uniform float VolRadius;
uniform float VolYScale;
uniform float Visibility;
uniform float Strength;
uniform float StepCount;
uniform float ShadowTaps;
uniform float Time;
uniform vec3 SunDir;
uniform float Interior;
uniform vec3 FlashPos;
uniform float FlashAmount;
// STORM-MASS B6 flash v2: a SECOND independent intra-wall flash cell (own scheduler
// slot in StormWeatherFx — volume-only: no point light, no serial, no Photon vein),
// plus the vein seed shared by both cells. F3: no shader clock flickers the veins —
// the pattern re-rolls from Java (innerFlashSerial % 64) with every fresh flash.
uniform vec3 Flash2Pos;
uniform float Flash2Amount;
uniform float FlashSeed;
// STORM-MASS B9 foundation: effective quality tier (0/1/2, StormVolumeFx.effectiveTier)
// — the in-shader gate for tier-priced density terms. Live gates: B3 convection cells
// (tier ≥ 1), B2 inner-shell cells (tier ≥ 2). Contract: tier 0 = cheapest look.
uniform float DetailTier;
// STORM-MASS B7 combat uniforms (F-031/F-032 mirror, all client-derived):
// SiegeChurn 0..1 = the siege growth ramp — drives warp turbulence (amplitude-safe).
uniform float SiegeChurn;
// ChurnTime = ∫ SiegeChurn dt (seconds, Java-integrated) — added to Time it escalates
// rotation/updraft RATES with a continuous angle; multiplying the rates by
// (1 + k·churn) directly would scrub the whole field on every churn change.
uniform float ChurnTime;
// CoreFade 0..1 mirrors the F-032 occluder-core dissolve: the band's inner edge and
// the inner shell thin out so the combat arena opens in the volume too.
uniform float CoreFade;

in vec2 texCoord;

out vec4 fragColor;

// Extinction per (density · block) — the dense band goes near-opaque over ~8–14 blocks.
const float ABSORB = 0.55;
// Overall density multiplier. Counter-intuitive knob: raising it does NOT make the storm
// look heavier. Past ~1.2 the ray saturates within the first optical depth, so the camera
// only ever sees the outermost isosurface — the lumps, banding and interior layering all
// disappear behind a smooth, solid-looking shell. Contrast belongs in the lighting model,
// not here. Measured on this scene: 1.0 reads as a churning anvil cloud, 1.55 as a dome.
const float DENSITY_GAIN = 1.05;
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
// Silhouette headroom beyond the nominal radius (anvil bulge + tower lumps + B3
// convection towers live there). Must exceed max(rEff) · 1.05, otherwise the bounds
// sphere clips the lumps flat and prints back the perfectly round edge the lumps exist
// to break. B3 balance: max rEff ≈ 1.478 (bulge 0.174 + tower 0.105 + anvil/conv ridge
// ≈ 0.199), ×1.05 = 1.552 < 1.70. MUST mirror StormVolumeFx.BOUNDS_MARGIN. The Y-slab
// clip + empty-space skipping pay for the extra slack.
const float BOUNDS_MARGIN = 1.70;
// STORM-MASS B9: the density field only lives inside this normalized-height slab while
// the bounds SPHERE spans ±BOUNDS_MARGIN vertically — clipping the march segment
// against the two horizontal planes up front reclaims 15–30% of the chord for
// elevated/top-down viewpoints at ~6 ALU. The top sits above the current 1.22 profile
// cut on purpose: it already covers the planned B3 convection-tower ceiling (ny 1.42),
// so raising the height profile later needs no bounds change here.
const float SLAB_NY_MIN = -0.25;
const float SLAB_NY_MAX = 1.45;
// Spiral rainband arm count and log-spiral winding factor.
const float ARMS = 3.0;
const float SPIRAL_WIND = 2.4;
// F-030d: quit the march once the mass is this opaque — the remaining chord contributes
// < 2% of the pixel and the upsample pass hides the cut entirely.
const float TRANS_EARLY_OUT = 0.02;
// F-030e distance LOD: per-pixel step budget scales 1.0 → 0.5 as the ray's ENTRY point
// runs from DIST_LOD_START to DIST_LOD_END blocks out (a far wall covers few pixels and
// the IGN dither eats the residual banding).
const float DIST_LOD_START = 160.0;
const float DIST_LOD_END = 320.0;
// F-030b adaptive stepping: while samples read empty the step multiplier grows by
// SKIP_GROWTH per miss up to SKIP_MAX; the first HIT after a long skip steps BACK half
// a stride and resamples, so the isosurface is refined instead of overshot.
const float SKIP_GROWTH = 1.22;
const float SKIP_MAX = 2.2;

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
// rlOut reports the radial profile coordinate rl = |u| / rEff of the sample — the
// lighting model reuses it for the B5 radial ambient occlusion instead of re-deriving
// the silhouette terms (they are already paid for here; the export is free).
float stormDensity(vec3 u, float detail, out float rlOut) {
    float ny = u.y;
    float lenH = length(u);
    rlOut = lenH;
    // B3: the vertical cut rises 1.22 → 1.42 so convection towers (ceiling up to 1.30)
    // never hit a hard lid; the Y-slab clip (1.45) still brackets it.
    if (lenH > BOUNDS_MARGIN || ny > 1.42 || ny < -0.20) {
        return 0.0;
    }
    // B7: siege escalation rides the INTEGRATED churn clock — d(spinT)/dt = 1 + 1.6·churn,
    // so rotation runs up to 2.6× under full siege while the angle stays continuous.
    float spinT = Time + 1.6 * ChurnTime;
    // Differential rotation: angular velocity varies with height (stratum ladder) AND
    // radius (inner mass leads the rim) — sampling position, not geometry, rotates.
    float spin = spinT * ROT_SPEED * stratumSpeed(clamp(ny, 0.0, 1.0))
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
    // B3 convection cells: a vertically COHERENT column field (the sample is y-free, so
    // a cell reads identically over the whole height — that is what makes it a tower
    // instead of a blob). Tier 0 and shadow rays take the midline: the v2 profile SHAPE
    // stays, only the per-column variation is a paid tier-≥1 camera feature.
    float towerCol = 0.5;
    if (detail > 0.5 && DetailTier > 0.5) {
        towerCol = smoothstep(0.55, 0.85,
                evNoise3(vec3(q.x * 3.2, Time * 0.02, q.z * 3.2))); // +1 N (tier ≥ 1)
    }
    float rEff = 1.0
            + 0.08 * anvil // B3: reduced from 0.12 — the towers own the top silhouette now
            + 0.06 * skirt
            + 0.30 * (bulge - 0.42) * lumpGate
            + 0.17 * (tower - 0.38) * smoothstep(0.62, 0.98, lenH)
            + 0.14 * towerCol * smoothstep(0.55, 0.90, ny); // B3: towers break the top edge
    float rl = lenH / max(rEff, 0.5);
    rlOut = rl;

    // Radial shell profile: a THICK density band peaking mid-wall, a hollow-ish eye at
    // the core (thin haze floor keeps it breathing) and a soft falloff past the rim.
    float band = smoothstep(0.30, 0.62, rl) * (1.0 - smoothstep(0.94, 1.05, rl));
    float prof = max(band, 0.10 * smoothstep(0.08, 0.30, rl));
    // B3 vertical profile v2: the ceiling rises locally where a convection tower stands
    // (0.95 → up to 1.30 BEFORE VolYScale squashes it) instead of one flat apex fade;
    // the base cut below the ground skirt is unchanged. The envelope is kept separate
    // (vert) because the B2 inner shell shares it.
    float towerTop = 0.95 + 0.35 * towerCol;
    float vert = (1.0 - smoothstep(towerTop - 0.14, towerTop, ny))
            * smoothstep(-0.18, -0.06, ny);
    prof *= vert;
    // B3 wallcloud: a lowered, THICKENED base ring (ny < 0.30, outer radii) — the heavy
    // dark foot every big storm hangs from (replaces the old skirt×band boost).
    float wallCloud = smoothstep(0.30, 0.10, ny) * smoothstep(0.55, 0.80, rl);
    prof *= 1.0 + 0.55 * wallCloud;

    // B2 inner-shell skeleton: a second radial band rl 0.16–0.50 under the same
    // vertical envelope — cheap enough to evaluate before the early-out so holes in
    // the outer band cannot skip real inner substance.
    float band2 = smoothstep(0.16, 0.34, rl) * (1.0 - smoothstep(0.44, 0.56, rl));
    float innerProf = band2 * vert;
    if (max(prof, innerProf) <= 0.003) {
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
    // B7: the updraft scroll rides the churn clock (up to 3× under full siege) and the
    // warp AMPLITUDE grows with churn — capped so the total stays ≤ 1.9 (beyond that
    // the billows tear and the noise lattice shows through).
    vec3 np = q * NOISE_FREQ
            + vec3(0.0, -(Time + 2.0 * ChurnTime) * UPDRAFT * NOISE_FREQ, 0.0);
    float body;
    if (detail > 0.5) {
        vec3 w1 = evCurlWarp(np * 0.5, Time);
        float wm = 1.0 + 0.18 * SiegeChurn;
        if (DetailTier > 1.5) {
            // B4 warp v2 (tier 2 only): a slow time-rotor turns the warp VECTOR about
            // Y, so the billows FOLD into each other instead of scrolling along the
            // lattice, and a second higher-frequency warp plane modulates the warp
            // amplitude ±17.5% — pockets of calm next to violently kneaded ones.
            float wa = Time * 0.04;
            float wc = cos(wa);
            float ws = sin(wa);
            w1.xz = vec2(wc * w1.x - ws * w1.z, ws * w1.x + wc * w1.z);
            float w2 = evNoise3(np * 1.7 + vec3(Time * 0.05)); // +1 N (tier 2)
            // Tear cap: evCurlWarp peaks at 1.6, and the B7 churn (×1.18) and B4 w2
            // (×1.175) factors MULTIPLY — clamp the combined multiplier at 1.1875 so
            // the effective amplitude never exceeds 1.6 · 1.1875 = 1.9.
            wm = min(wm * (1.0 + 0.35 * (w2 - 0.5)), 1.1875);
        }
        body = evFbm5(np + w1 * wm);
    } else {
        body = evFbm2(np);
    }
    // Outer field: remap so the noise CARVES holes through the profile instead of only
    // dimming it. DENSITY_GAIN keeps the mass heavy: at 1.0 the ball reads as thin haze
    // from a distance because the average sample sits well below the peak.
    float outer = max(prof * armMul * (body * 1.5 - 0.35), 0.0);
    // B2 inner shell: leads the outer rotation by 0.35 rad plus its own 0.035 rad/s
    // clock, and takes the ANTI-PHASE body (1 − body): where the outer carve opens a
    // hole, the inner layer has substance — the "there is more behind it" read.
    // Combined via max AFTER the carve (never a sum — F8): sharing the outer remap
    // would multiply the inner shell by the very hole that is supposed to reveal it.
    float inner = 0.0;
    if (innerProf > 0.003) {
        float cellMul = 0.775; // midline — the cell field is a tier-2 camera luxury
        if (detail > 0.5 && DetailTier > 1.5) {
            float spin2 = spin + 0.35 + spinT * 0.035;
            float cs2 = cos(spin2);
            float sn2 = sin(spin2);
            vec3 q2 = vec3(cs2 * u.x - sn2 * u.z, u.y, sn2 * u.x + cs2 * u.z);
            cellMul = 0.55
                    + 0.45 * evNoise3(q2 * 3.4 + vec3(0.0, -Time * 0.03, 7.7)); // +1 N (tier 2)
        }
        inner = innerProf * max((1.0 - body) * 1.4 - 0.30, 0.0) * cellMul * 0.62;
    }
    float dens = max(outer, inner);
    // B3 fray: the anvil ceiling shreds along the body instead of ending in a clean
    // line (0 N — body is already paid). The inner shell barely reaches ny > 0.72, so
    // applying it to the combined field is visually identical to outer-only.
    dens *= mix(1.0, smoothstep(0.30, 0.62, body), smoothstep(0.72, 1.0, ny));
    // B7/F-032 mirror: while the occluder core dissolves for combat sight, the band's
    // inner edge and the whole inner shell thin away — the arena opens in the volume
    // in sync with the geometry instead of hiding the fight behind fog.
    dens *= 1.0 - CoreFade * (1.0 - smoothstep(0.35, 0.62, rl));
    return dens * DENSITY_GAIN;
}

// Shadow-tap variant: the sun taps only need the density, not the profile coordinate.
float stormDensity(vec3 u, float detail) {
    float rl;
    return stormDensity(u, detail, rl);
}

// Single scattering at one sample: 2/3 cheap self-shadow taps toward the sun (F-030f:
// ShadowTaps drops 3 → 2 on low quality tiers; the spacing widens by 3/taps so the
// ~0.36·R reach AND the optical depth of the 3-tap ladder are both preserved — the
// transmittance term multiplies the tap sum by the spacing), dual-lobe phase (fed in),
// height-graded ambient (dark violet base → sick green top — the C8 sphere palette),
// and the intra-wall flash as emissive light inside the mass. STORM-MASS B1/B5 depth
// terms (all pure math, 0 extra noise): Beer-powder edge, density-graded albedo,
// radial ambient occlusion on rl and an analytic sun-hemisphere macro shadow.
// dens is the PREMULTIPLIED camera-sample density (raw × densMul), rl its radial
// profile coordinate — both already paid for by the march.
vec3 volumeLight(vec3 pos, vec3 u, float rl, float dens, float phase, float densMul) {
    float taps = clamp(ShadowTaps, 2.0, 3.0);
    float spacing = SHADOW_STEP_N * (3.0 / taps);
    vec3 sdir = normalize(SunDir + vec3(0.0, 1.0e-4, 0.0));
    vec3 us = vec3(sdir.x, sdir.y / max(VolYScale, 0.05), sdir.z) * spacing;
    float sh = stormDensity(u + us, 0.0);
    sh += stormDensity(u + us * 2.0, 0.0);
    if (taps > 2.5) {
        sh += stormDensity(u + us * 3.0, 0.0);
    }
    // B5 analytic large-scale sun depth: project the sample onto the sun axis — the
    // sun-facing hemisphere stays lit, the far side falls off smoothly. The local taps
    // only reach ~0.36·R, so without this term both halves of the ball read equally
    // bright from outside; with it the whole mass carries one big lit/shaded gradient.
    float sunSide = clamp(dot(u, sdir) * 0.5 + 0.5, 0.0, 1.0);
    float macroShadow = mix(0.45, 1.0, sunSide);
    float lightT = exp(-sh * densMul * spacing * VolRadius * ABSORB) * macroShadow;
    // Bone-white day sun → moon-silver night (the renderer's rim-scatter palette).
    float dayness = clamp(SunDir.y * 2.6, 0.0, 1.0);
    vec3 sunCol = mix(vec3(0.72, 0.76, 0.90) * 0.25, vec3(0.85, 0.82, 0.74), dayness);
    // B5 radial ambient occlusion: a sample near the core sits behind metres of mass in
    // EVERY direction, so sky light cannot reach it — ambient falls from the rim toward
    // the eye. This is what makes holes in the outer band read as "mass behind", not fog.
    float radialAo = mix(0.30, 1.0, smoothstep(0.15, 0.85, rl));
    vec3 ambient = mix(vec3(0.052, 0.060, 0.082), vec3(0.088, 0.152, 0.120),
            clamp(u.y, 0.0, 1.0)) * (1.15 + 1.35 * dayness) * radialAo;
    // Multiple-scattering approximation: deep cloud is not black, light diffuses into it.
    // sqrt(lightT) with an isotropic lobe lifts the shadowed mass into readable grey so
    // the layering is visible from outside instead of crushing to a silhouette.
    // Keep the multi-scatter lift modest: too much and the whole ball flattens into a
    // uniform pale smudge with no lit/shaded read at all.
    float ms = lightT * sqrt(clamp(lightT, 0.0, 1.0));
    // B1 Beer-powder (Horizon/Nubis): freshly lit thin edges scatter bright, thick
    // pockets absorb their own in-scatter before it exits — dark bellies + sugar-bright
    // rims, the classic "this is a mass, not haze" cumulus read.
    float powder = 1.0 - exp(-dens * 14.0);
    // B1 density-graded albedo: optically thick pockets tip into the dark slate-green
    // of the C8 palette, so a dense slab and a thin veil no longer share one colour per
    // transmittance slice. Dark point reached at dens ≥ ~0.45.
    vec3 albedo = mix(vec3(1.0), vec3(0.62, 0.68, 0.66), clamp(dens * 2.2, 0.0, 1.0));
    vec3 col = albedo * (sunCol * (lightT * phase * 4.6 * powder + ms * 0.20) + ambient);
    // STORM-MASS B6 flash v2: up to two simultaneous cells, each an emissive glow
    // (added AFTER the albedo grade — emission, not scattering) modulated by a vein
    // field on the UNROTATED storm frame: filaments of the mass glim up instead of
    // one radial bulb. The vein noise is hoisted so a double flash still costs one
    // evNoise3 (+1 N, only while a flash is live); mean vein = 1.0 keeps the W-B
    // glow energy unchanged.
    if (FlashAmount > 0.004 || Flash2Amount > 0.004) {
        float vein = 0.55 + 0.90 * evNoise3(u * 9.0 + vec3(FlashSeed * 17.0)); // +1 N
        vec3 flashCol = vec3(0.70, 0.58, 1.00);
        if (FlashAmount > 0.004) {
            float fd = length(pos - FlashPos);
            col += flashCol * (FlashAmount * 2.5 * vein * exp(-fd / (0.30 * VolRadius)));
        }
        if (Flash2Amount > 0.004) {
            float fd2 = length(pos - Flash2Pos);
            col += flashCol * (Flash2Amount * 2.5 * vein * exp(-fd2 / (0.30 * VolRadius)));
        }
    }
    return col;
}

void main() {
    // F-030a: this stage renders into the half-res `volume_half` target — output is
    // premultiplied in-scatter (rgb) + transmittance (a); "no storm on this ray" is
    // vec4(0, 0, 0, 1), which the upsample stage composites as an untouched scene.
    float strength = clamp(Strength, 0.0, 1.0) * clamp(Visibility, 0.0, 1.0);
    if (strength <= 0.004 || VolRadius <= 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
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
        fragColor = vec4(0.0, 0.0, 0.0, 1.0); // early out: the ray misses the bounds
        return;
    }
    float sq = sqrt(disc);
    float t0 = max((-bq - sq) / aq, 0.0);
    float t1 = (-bq + sq) / aq;

    // B9 Y-slab clip: the density profile cuts hard outside ny ∈ [SLAB_NY_MIN,
    // SLAB_NY_MAX] but the bounds sphere spans ±BOUNDS_MARGIN vertically — intersect
    // the ray with the two horizontal planes (squashed space, so the slab tracks
    // VolYScale) and shrink the march segment to the part that can hold density. The
    // reclaimed chord goes straight into finer dt at the same step budget.
    if (abs(dS.y) > 1.0e-5) {
        float invDy = 1.0 / dS.y;
        float ta = (SLAB_NY_MIN * VolRadius - oS.y) * invDy;
        float tb = (SLAB_NY_MAX * VolRadius - oS.y) * invDy;
        t0 = max(t0, min(ta, tb));
        t1 = min(t1, max(ta, tb));
    } else if (oS.y < SLAB_NY_MIN * VolRadius || oS.y > SLAB_NY_MAX * VolRadius) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0); // level ray entirely outside the slab
        return;
    }
    if (t1 <= t0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0); // slab and sphere don't overlap this ray
        return;
    }

    // Scene depth clamp: terrain (and the opaque occluder dome) correctly hides the
    // volume behind it. Depth ≥ ~1 is sky — no clamp (and no unstable reconstruction).
    // The full-res depth buffer is sampled at this half-res pixel's center; the
    // upsample stage weights its 4 taps against the SAME centers, so depth edges stay
    // consistent between the two passes.
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    float sceneDist = depth >= 0.9999 ? 1.0e7
            : length(screenToLocalSpace(texCoord, depth).xyz);
    t1 = min(t1, sceneDist);
    if (t1 <= t0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Step budget from Java (AUDITFIX-4: config tier 64/40/24 × screen-coverage ramp,
    // hard-capped when the storm nearly fills the screen — StormVolumeFx.stepCount),
    // further halved per pixel as the entry point runs out (F-030e distance LOD).
    float steps = clamp(StepCount, 12.0, 64.0);
    steps = clamp(steps * (1.0 - 0.5 * smoothstep(DIST_LOD_START, DIST_LOD_END, t0)),
            12.0, 64.0);
    float dt0 = (t1 - t0) / steps;
    // F-030c: interleaved-gradient-noise start dither + temporal drift — kills the
    // shell banding a fixed march start would print into the fog at low step counts.
    // gl_FragCoord is in half-res pixels here, which keeps the IGN lattice intact.
    float dith = fract(52.9829189
            * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715)))
            + fract(Time * 61.803));

    // Deep inside the storm the interior grade + pinched fog own the frame; the volume
    // eases off so the two systems hand over instead of stacking to black.
    float densMul = strength * (1.0 - 0.35 * clamp(Interior, 0.0, 1.0));
    float mu = dot(rd, normalize(SunDir + vec3(0.0, 1.0e-4, 0.0)));
    // B1 dual-lobe phase: a strong forward lobe (g 0.60 — the silver lining when the
    // sun sits behind the mass) plus a weak backscatter lobe (g −0.22 — retroreflective
    // fill when the sun is behind the camera), over an isotropic floor so no viewing
    // angle ever goes fully dark.
    float phase = mix(evHgPhase(mu, 0.60), evHgPhase(mu, -0.22), 0.32);
    phase = mix(0.0795775, phase, 0.78);
    float invR = 1.0 / VolRadius;
    float invY = 1.0 / max(VolYScale, 0.05);

    float trans = 1.0;
    vec3 acc = vec3(0.0);
    float t = t0 + dith * dt0;
    float skipMul = 1.0; // F-030b adaptive stride (grows through empty space)
    for (int i = 0; i < 64; i++) {
        if (t >= t1 || trans < TRANS_EARLY_OUT || float(i) >= steps) {
            break; // early exits: segment done / mass opaque (F-030d) / budget spent
        }
        float dt = dt0 * (1.0 + t * 0.0025) * skipMul; // grows along the ray AND while empty
        vec3 pos = rd * t;
        vec3 lp = pos - VolCenter;
        lp.y *= invY;
        vec3 u = lp * invR;
        float rl; // radial profile coordinate, exported free for the B5 ambient AO
        float dens = stormDensity(u, 1.0, rl) * densMul;
        if (dens < 0.004) {
            // Empty-space acceleration through the eye / between towers: each miss
            // widens the stride up to SKIP_MAX × the base 1.6.
            t += dt * 1.6;
            skipMul = min(skipMul * SKIP_GROWTH, SKIP_MAX);
            continue;
        }
        if (skipMul > 1.35) {
            // A long skip just crossed the isosurface — step back half the (grown)
            // stride and resample at the base rate, so lumps keep their crisp fronts
            // instead of being aliased away by the wide stride that found them.
            t -= dt * 0.5;
            skipMul = 1.0;
            continue;
        }
        skipMul = 1.0;
        float newTrans = trans * exp(-dens * dt * ABSORB);
        acc += volumeLight(pos, u, rl, dens, phase, densMul) * (trans - newTrans);
        trans = newTrans;
        t += dt;
    }

    // Premultiplied half-res output; the upsample stage owns the scene composite.
    fragColor = vec4(acc, trans);
}
