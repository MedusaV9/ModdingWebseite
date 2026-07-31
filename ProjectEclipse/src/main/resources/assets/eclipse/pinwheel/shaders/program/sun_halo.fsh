// eclipse:sun_halo — pure screen-space radial halo around the CPU-projected sun point
// (P2 R2 rewrite, FEATURE priority). THE misalignment fix: the old shader reconstructed a
// per-pixel world ray from Veil's veil:camera block, whose modelview deliberately strips
// view bobbing — so the halo and the sky-pass sun quad (rendered WITH bobbing) disagreed
// every frame while walking. Now veilfx.SunTracker projects the sun ONCE per frame on the
// CPU using the exact RenderLevelStageEvent matrices and feeds it here as SunScreen; the
// sky quad rotates from the same SunTracker angle, so both are locked by construction.
//
// v2 (FX team GRADE): the halo goes volumetric.
//   [s1] multi-ring diffraction corona — three gaussian rings with a spectral
//        progression (violet-white → magenta → deep blue-violet), spread growing
//        slightly with HaloStrength: the eclipse corona gains optical structure.
//   [s2] anamorphic streak option — a thin horizontal violet-white streak, gated to
//        high-strength moments (eclipse boost) and off under reducedFx.
//   [s3] occlusion-aware fade — 5-tap soft depth probe around the sun point (fraction,
//        not a binary step) + the CPU now EASES RimOnly over ~6 ticks: walking behind a
//        tree line fades the glow instead of popping it.
//   [s4] azimuthal shimmer — ring intensity breathes around the circle (living
//        diffraction), reducedFx-gated.
//   [s5] chromatic glow dispersion — per-channel glow radii: the skirt of the glow
//        drifts magenta while the core stays violet-white. Pure math, no extra taps.
//   [s6] halo-local dither — kills exp-gradient banding on dark skies.
//   [s7] volumetric breath — the glow radius swells ~±3% on an incommensurate double
//        sine (gas, not decal); reducedFx-gated like every animated layer here.
//
// v3 (VEIL-REPASS-1):
//   [s8] occlusion-aware anamorphic EVOLUTION — the streak's horizontal reach now grows
//        with HaloStrength past the gate (a totality streak stretches ~1.5× the gate-
//        threshold streak) and COLLAPSES with occlusion: partial cover shortens the
//        streak toward a stub instead of leaving a dim full-width line floating over
//        the treeline (reach ∝ visibility, brightness already faded via glowVis).
//   [s9] altar-level color temperature — AltarWarmth (synced altar ladder, 0..1) warms
//        the halo tint WITHIN the violet family (more red, less blue — never gold: the
//        style guide reserves gold for reward beats, and this pass is ambient all day).
//        A maxed altar makes the star burn a hotter magenta-violet. Static state
//        feedback, so it survives reducedFx like the rings.
//
// Uniforms (frozen §3.3):
//   SunScreen    vec4 — xy = NDC pos, z = 1 when in front of camera else 0,
//                        w = sun angular radius in NDC-y units (tan(5°)·Proj[1][1])
//   HaloStrength      — 0..~1.4; grows with the eclipse (glow radius up to ~0.55 NDC),
//                        permanent-rim floor 0.15 after the intro
//   RimOnly           — CPU occlusion: now the ~6-tick EASED 0..1 amount (was a binary
//                        flag; the shader always clamped, so semantics only widened)
// v2 additive uniforms (fed by the same VeilPostController feeder, same commit):
//   Time   — seconds, hourly wrap (limbo clock pattern); ring shimmer clock
//   Detail — 1 normal, 0 under reducedFx: gates streak + shimmer (rings/glow stay)
// v3 additive uniform (same feeder, same commit — the additive rule):
//   AltarWarmth — clamp(ClientStateCache.altarLevel, 0, 5) / 5 (the established
//                 client altar-ladder normalization); halo temperature shift driver
//
// v4 (FX-13 A9): the black-sun snap.
//   [s10] at the exact totality crest the sun snaps into a black hole for ~1.5 s: the
//        disc interior collapses toward black, a thin bright corona ring hugs the
//        silhouette with ONE hot diamond bead, and a few faint radial streamers escape —
//        then everything blends softly back to the ordinary totality halo.
// v4 additive uniform (same feeder, same commit — the additive rule):
//   SunSnap — 0..1 envelope from TotalityPeakFx.snapAmount (hard 3-tick snap-in,
//             25-tick black hold, 30-tick soft release), armed by the SAME rising crest
//             that spawns the Photon diamond ring. 0 = bit-identical frame.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform vec4 SunScreen;
uniform float HaloStrength;
uniform float RimOnly;
uniform float Time;
uniform float Detail;
uniform float AltarWarmth;
uniform float SunSnap;

in vec2 texCoord;

out vec4 fragColor;

// Diffraction ring radii (× sunRadius × spread) / gaussian widths (× sunRadius).
const vec3 RING_RADII = vec3(2.2, 3.6, 5.4);
const vec3 RING_WIDTHS = vec3(0.55, 0.75, 1.00);
const vec3 RING_WEIGHTS = vec3(0.20, 0.12, 0.07);

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    if (SunScreen.z < 0.5 || HaloStrength <= 0.001) {
        fragColor = vec4(color, 1.0);
        return;
    }

    // Aspect-corrected distance to the sun point, in NDC-y units (matches SunScreen.w).
    vec2 screenSize = vec2(textureSize(DiffuseSampler0, 0));
    float aspect = screenSize.x / max(screenSize.y, 1.0);
    vec2 delta = (texCoord * 2.0 - 1.0 - SunScreen.xy) * vec2(aspect, 1.0);
    float dist = length(delta);
    float sunRadius = max(SunScreen.w, 1.0e-4);

    // [s3] Occlusion: 5-tap soft probe (center + 4 diagonals at 0.6·sunRadius) gives a
    // visibility FRACTION, OR'd with the CPU-eased RimOnly — partial cover (leaves,
    // fence posts) now dims the glow proportionally instead of snapping it off.
    vec2 sunUv = clamp(SunScreen.xy * 0.5 + 0.5, vec2(0.0), vec2(1.0));
    vec2 probeUv = vec2(0.3 * sunRadius / aspect, 0.3 * sunRadius);
    float visible =
            step(0.9999, texture(DiffuseDepthSampler, sunUv).r)
            + step(0.9999, texture(DiffuseDepthSampler, clamp(sunUv + probeUv, vec2(0.0), vec2(1.0))).r)
            + step(0.9999, texture(DiffuseDepthSampler, clamp(sunUv - probeUv, vec2(0.0), vec2(1.0))).r)
            + step(0.9999, texture(DiffuseDepthSampler, clamp(sunUv + vec2(probeUv.x, -probeUv.y), vec2(0.0), vec2(1.0))).r)
            + step(0.9999, texture(DiffuseDepthSampler, clamp(sunUv - vec2(probeUv.x, -probeUv.y), vec2(0.0), vec2(1.0))).r);
    float occluded = clamp(max(clamp(RimOnly, 0.0, 1.0), 1.0 - visible * 0.2), 0.0, 1.0);

    // Tight rim hugging the disc edge (bright ring at ~the quad's silhouette).
    // Descending ramps written as 1-smoothstep(lo,hi,x): edge0>edge1 is undefined GLSL.
    float rim = (1.0 - smoothstep(sunRadius * 0.95, sunRadius * 1.15, dist))
            * (1.0 - (1.0 - smoothstep(sunRadius * 0.55, sunRadius * 0.95, dist)) * 0.35);

    // Wide glow whose radius grows with HaloStrength (eclipse boost up to ~0.55 NDC).
    // [s5] Per-channel radii: the outer skirt drifts magenta, the core stays violet.
    // Volumetric breath: the radius swells ~±3% on an incommensurate double sine — the
    // halo reads as gas, not as a decal. Dies with Detail (reducedFx: perfectly steady).
    float glowRadius = 0.12 + 0.43 * clamp((HaloStrength - 0.15) / 1.05, 0.0, 1.0);
    glowRadius *= 1.0 + (0.022 * sin(Time * 0.55) + 0.012 * sin(Time * 0.83 + 2.1)) * Detail;
    vec3 glow3 = vec3(
            exp(-dist / (glowRadius * 1.07) * 3.0),
            exp(-dist / (glowRadius * 0.93) * 3.0),
            exp(-dist / glowRadius * 3.0));

    // Sky pixels take the full effect; solid geometry only catches a soft 20% spill.
    // (Hoisted sky flag: [s10] reuses the same depth sample — the spill math is unchanged.)
    float skyHere = step(0.9999, texture(DiffuseDepthSampler, texCoord).r);
    float spill = mix(0.2, 1.0, skyHere);

    float rimVis = mix(1.0, 0.35, occluded);          // occluded: faint rim silhouette
    float glowVis = 1.0 - smoothstep(0.10, 0.85, occluded); // occluded: glow fades out

    // [s1] Diffraction rings: spread widens slightly as the halo strengthens.
    // [s4] Azimuthal shimmer makes the diffraction live (reducedFx: perfectly still).
    float spread = 1.0 + 0.22 * clamp(HaloStrength / 1.4, 0.0, 1.0);
    // Epsilon: atan(0, 0) is undefined in GLSL — the exact sun-center pixel must not
    // depend on driver mercy (shimmer is irrelevant there, but NaN would propagate).
    float azimuth = atan(delta.y, delta.x + 1.0e-6);
    float shimmer = 1.0 + 0.16 * sin(azimuth * 6.0 + Time * 0.35) * Detail;
    vec3 h1 = (dist - RING_RADII * sunRadius * spread) / (RING_WIDTHS * sunRadius);
    vec3 ringGauss = exp(-h1 * h1);
    vec3 ringColor = vec3(0.80, 0.55, 1.05) * ringGauss.x * RING_WEIGHTS.x
            + vec3(0.85, 0.30, 0.95) * ringGauss.y * RING_WEIGHTS.y
            + vec3(0.45, 0.25, 1.00) * ringGauss.z * RING_WEIGHTS.z;
    ringColor *= shimmer * glowVis;

    // [s2]+[s8] Anamorphic streak: thin in y, wide in x, only at high strength (the
    // eclipse boost), fading before the screen edge so it never hard-clips. Off under
    // reducedFx. v3 EVOLUTION: the horizontal reach grows with strength past the gate
    // (2.0× → ~3.5× glowRadius toward totality) and collapses with occlusion — a half-
    // covered sun keeps a short bright stub at the disc instead of a dim full-width
    // line hovering over the treeline (brightness was already glowVis-faded; now the
    // GEOMETRY agrees with the cover).
    float streakGate = smoothstep(0.55, 0.90, HaloStrength) * Detail * glowVis;
    float sy = delta.y / (sunRadius * 0.55);
    float streakReach = glowRadius * (2.0 + 1.5 * smoothstep(0.55, 1.30, HaloStrength))
            * (0.35 + 0.65 * glowVis);
    float streak = exp(-sy * sy) * exp(-abs(delta.x) / streakReach) * streakGate;
    float edgeFade = smoothstep(0.0, 0.08, texCoord.x) * (1.0 - smoothstep(0.92, 1.0, texCoord.x));
    streak *= edgeFade;

    // [s9] Temperature shift within the violet family: a leveled altar heats the star
    // toward magenta-violet (never gold — ambient pass, style-guide gold restriction).
    vec3 haloTint = mix(vec3(0.62, 0.24, 1.00), vec3(0.74, 0.28, 0.88), AltarWarmth * 0.45);
    vec3 streakTint = mix(vec3(0.75, 0.45, 1.05), vec3(0.85, 0.44, 0.95), AltarWarmth * 0.45);

    vec3 halo = (haloTint * (rim * 0.9 * rimVis + glow3 * 0.85 * glowVis)
            + ringColor
            + streakTint * streak * 0.5)
            * HaloStrength * spill;

    // [s6] Dither scaled into existence only where the halo actually is — masks the
    // exp-gradient banding on dark skies without touching the rest of the frame.
    float haloLuma = dot(halo, vec3(0.299, 0.587, 0.114));
    float dither = (efxHash(texCoord * screenSize + vec2(mod(floor(Time * 4.0), 97.0))) - 0.5)
            * (2.0 / 255.0) * smoothstep(0.002, 0.05, haloLuma);

    color += halo + vec3(dither);

    // [s10] FX-13 A9 black-sun snap (TotalityPeakFx crest timeline): the hole is applied
    // AFTER the halo add so the glow core inside the disc collapses with it. The interior
    // crushes to 5% (a hole, not a decal — some scene response survives), sky-gated so a
    // treeline in front of the disc is never darkened; the thin corona ring, its one hot
    // diamond bead (upper-right rim, the Photon ring's screen-side memory) and the faint
    // 7-fold radial streamers ride snapVis = SunSnap × glowVis, so mid-snap occlusion
    // fades the whole beat instead of popping it. Zero uniform = bit-identical frame.
    if (SunSnap > 0.001) {
        float snapVis = clamp(SunSnap, 0.0, 1.0) * glowVis;
        float hole = (1.0 - smoothstep(sunRadius * 0.78, sunRadius * 1.02, dist))
                * snapVis * skyHere;
        color = mix(color, color * 0.05, hole);
        float ringH = (dist - sunRadius * 1.05) / (sunRadius * 0.085);
        float corona = exp(-ringH * ringH);
        float accH = azimuth - 0.85;
        float accent = exp(-accH * accH / 0.14);
        float spokes = pow(abs(sin(azimuth * 7.0 + 0.4)), 18.0)
                * exp(-max(dist - sunRadius, 0.0) / (sunRadius * 1.6));
        vec3 snapColor = vec3(0.94, 0.86, 1.08)
                * (corona * (0.55 + 0.75 * accent) + spokes * 0.18);
        color += snapColor * snapVis * spill;
    }

    fragColor = vec4(color, 1.0);
}
