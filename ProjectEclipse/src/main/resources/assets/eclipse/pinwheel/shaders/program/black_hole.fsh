// eclipse:black_hole — F-056 black-hole finale post pass (FEATURE priority; registered
// by client.credits.CreditsBlackHolePostFx, driven by CreditsSkyFx.holeAmount).
// F-068 polish pass: the lensing RAMPS with the sky intensity ladder, the horizon
// shimmers, an accretion glow with Doppler beaming and infalling star streaks joined.
// F-072 (V3) pass: photon-ring SUBSTRUCTURE (razor Einstein ring with orbiting beads),
// a gravitationally LENSED background starfield (stars sampled in the point-lens source
// frame — they crawl along arcs and smear tangentially into Einstein arcs near the
// ring), orbiting accretion HOTSPOTS that flare and smear backwards, two polar JETS
// with traveling pulse knots, and the Pulse uniform (the server's "Schluck" gulps) that
// makes the event horizon BREATHE and the rings flare when a cluster pours over it.
// Layers, all scaled by Strength so the pass is a no-op at 0:
//   [b1] radial UV pull — every pixel is dragged toward the hole center (gravitational
//        lensing read); eased Strength ramp + a near-field 1/r term
//   [b2] swirl — the pulled UVs additionally rotate around the center (accretion drag)
//   [b2b] chromatic aberration (Detail-gated) — RGB split radially, strongest hugging
//        the photon ring
//   [b3] event horizon — core drains to pure black with a soft shimmering edge; V3: the
//        core radius additionally BREATHES on the Pulse gulps (+5% swell). The main
//        photon ring rides it Doppler-beamed; V3 adds the thin coreR*1.32 Einstein
//        SUB-RING with orbiting noise beads (knots of lensed light circling the hole)
//   [b3b] accretion glow — two soft elliptical Doppler-beamed bands in the display
//        disc's squashed frame; V3: two orbiting HOTSPOTS ride the bands, flaring on
//        slow cubed-sine clocks and smearing into a wide trailing lobe behind their
//        orbital motion (matches CreditsBlackHoleAct's heat-glow ladder)
//   [b3c] star streaks (Detail-gated) — thin radial dashes flowing INWARD
//   [b5] polar jets (V3) — two opposed luminous columns along the disc's minor axis,
//        gated in by the lensing ramp (they only ignite once the hole feeds hard),
//        pulse knots traveling OUTWARD along each column, slow sway, the approaching
//        (upper) jet Doppler-bright, the receding one dim
//   [b6] lensed starfield (V3, Detail-gated) — procedural background stars sampled at
//        the point-lens SOURCE radius (r_src = r − k·coreR²/r): as Strength ramps the
//        stars visibly migrate outward around the hole; near the ring their cell-space
//        falloff is squeezed tangentially so they stretch into Einstein ARCS, and a
//        1/r differential rotation makes the close field crawl along its orbits
//   [b7] redshift FREEZE (wave-13 C5) — the last two rungs of the server's intensity
//        ladder (0.91 / 1.0 of CreditsSequence.FINALE_SKY_STEP_INTENSITY) arm a
//        Schwarzschild dilation d(r) = sqrt(1 − r_s/r) about the DRAWN rim r_s = coreR·1.6
//        (FREEZE_RS — the outer edge of [b3]'s blackout, so "motion stops" lands exactly
//        where the image dies rather than buried inside the black core). It is spent in
//        three places, each in the only form that is safe there:
//          - TEMPORAL, uniform. Every near-field clock — photon-ring shimmer, sub-ring
//            beads, disc shimmer, hotspot orbits and flares, dash flow, starfield rotation
//            and twinkle — runs on Time·FREEZE_DILATION, one CONSTANT factor. The clock is
//            not per-fragment on purpose; see the long note at freezeTime for the aliasing
//            that killed the per-fragment version.
//          - RADIAL, spatial. The star dashes' phase coordinate is stretched near the rim
//            (FREEZE_WARP_L), so a dash's inward drift falls to ~1/4.5 of its far-field
//            rate as it approaches — an asymptotic stop with a Time-independent gradient.
//            Their inner window slides onto the rim too, so they are still drawn where
//            they pile up instead of being cut off at 2·coreR just before they get there.
//          - RADIAL, chromatic. The frame bleeds to ember red over the per-fragment 1−d
//            gradient, weighted by cos(theta) so the receding (screen-left) limb reddens
//            1.9x harder than the approaching one, deepened by the Pulse gulps. Colour
//            cannot alias, so this one keeps the exact sqrt curve.
//        The hard "scene → black" step at the horizon therefore becomes scene → red →
//        black. TWO clocks deliberately stay on raw Time, and both would be bugs otherwise:
//          - the horizon `wobble`, because coreR is derived FROM it and r_s from coreR —
//            slowing it closes a circular dependency;
//          - the polar jets, because a jet is an OUTFLOW escaping along the axis. Freezing
//            an outflow against the rim it is leaving is the wrong physics and would also
//            smear the traveling knots, whose phase is already a function of axial reach.
//        Gated on Strength ALONE: below 0.84 freezeArm is exactly 0, so every term above
//        collapses to an identity (Time·1, mix(x, y, 0), log-term ×0) and rungs 1–4 stay
//        bit-for-bit their pre-C5 selves — verified by frame diff, not by inspection.
//   [b4] desaturation + darkening — "Farben ergrauen"; V3: rides an EASED curve of
//        Strength (with the 6-step server ladder the drain is one continuous slope,
//        never a visible step)
// Uniforms (fed per frame by CreditsBlackHolePostFx, no allocations):
//   Strength — eased 0..1 hole amount (CreditsSkyFx; the server's intensity ladder)
//   Hole     — hole center in UV space (SunTracker.worldToNdc remapped; offscreen-safe)
//   Aspect   — viewport width / height (keeps the swirl/ring circular)
//   Time     — pause-frozen seconds (ring shimmer, streak flow, hotspot orbits)
//   Detail   — 1 normal, 0 under reducedFx (drops shimmer, rings, streaks, aberration,
//              hotspots, jets and the lensed starfield — the cheap core read stays)
//   Pulse    — 0..1 gulp envelope (V3; CreditsSkyFx.holePulse ← S2CCreditsPulsePayload,
//              sent by CreditsSequence.devourPulse / the horizon flashes). 0 = no-op.
//   JetPulse — 0..1 jet-burst envelope (F-090/F-093; CreditsSkyFx.jetPulse ←
//              S2CCreditsJetPayload, sent when a shredded sub-plate sprays along the
//              jet axis): the jet columns FLARE (×(1 + 1.4·jetP)), the knot phase
//              speed doubles and the axial window lengthens to (0.5, 0.95) — the jets
//              visibly STROBE with the display spray. Detail-gated like the jets;
//              strict no-op at 0.
//
// PARSER LAW — the mine this file stepped on, and which of the two halves actually
// disarms it (autopsy in B4_GLITCH_REPORT.md section 0.1, live proof in
// run/logs/latest.log; the ablation below is wave-13 C5, run against glsl-processor
// 0.2.3 with the real Veil parser):
//   1. NO value-less `return;` — THIS is the load-bearing rule. The processor gives
//      GlslReturnNode a null value for it and NPEs in hashCode the moment anything
//      hashes the tree, which the emitter's own function-marker map lookup does.
//   2. A stray hash character INSIDE A FUNCTION BODY (comments included) is what makes
//      that marker map non-empty, i.e. it is the detonator, not the charge.
// Measured, four builds of this file, all otherwise identical:
//      body-hash + bare return  -> EMIT-FAIL, NPE in GlslReturnNode.hashCode
//      body-hash, no return     -> OK
//      header-hash + bare return-> OK   (a hash above `#include`, outside every function
//                                        body, never registers a marker — which is why
//                                        the `#include` mention two lines above is safe)
//      neither                  -> OK
// So rule 1 alone is sufficient and rule 2 alone is not: keep the nested if/else in
// main() and the file stays immune even if a hash creeps back into a body comment.
// Wave-13 C5 found both halves present at once (a `return;` in the idle gate plus
// "FXWAVE-9 <hash>4" twice inside main()), so Veil logged "Couldn't parse shader
// eclipse:black_hole", never registered the program, and the whole finale pass silently
// no-oped at runtime. glslangValidator CANNOT see any of this — it compiles the broken
// file happily, which is why the round-trip check is a separate gate.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Strength;
uniform vec2 Hole;
uniform float Aspect;
uniform float Time;
uniform float Detail;
uniform float Pulse;
uniform float JetPulse;

in vec2 texCoord;

out vec4 fragColor;

const vec3 LUMA_W = vec3(0.299, 0.587, 0.114);
// Warm-violet finale palette (the ferryman2 law, mirrored from the Photon assets).
const vec3 RING_COLOR = vec3(0.85, 0.62, 1.05);
const vec3 DISC_COLOR = vec3(0.72, 0.52, 0.95);
const vec3 STREAK_COLOR = vec3(0.82, 0.72, 1.0);
const vec3 JET_COLOR = vec3(0.78, 0.68, 1.05);
// [b7] The redshift freeze arms across the gap between ladder rungs 4 (0.8) and 5 (0.91),
// so it is exactly 0 on rungs 1-4 and fully lit on the final 1.0.
const float FREEZE_ARM_LO = 0.84;
const float FREEZE_ARM_HI = 0.98;
// [b7] Ember the frame bleeds to at the rim: a luma-preserving red with a live green
// shoulder, so the bleed reads as heat rather than as a flat red filter.
const vec3 REDSHIFT_EMBER = vec3(1.55, 0.34, 0.10);
// [b7] r_s for the dilation is the DRAWN rim, not coreR. [b3] blacks the frame out over
// smoothstep(coreR*1.6, coreR*0.7, dist), so coreR*1.6 is the outermost radius at which
// anything is still visible. Anchoring d(r) there puts "motion stops" exactly on the edge
// where the image dies — with r_s = coreR the whole d < 0.5 shell would have been buried
// INSIDE the blackout, i.e. the freeze would have been mathematically present and visually
// invisible, and the surviving band would have been squeezed into ~0.4 coreR of screen.
const float FREEZE_RS = 1.6;
// [b7] The clocks are slowed by a CONSTANT (see freezeTime for why it cannot be a function
// of r), so the constant is d(r) sampled once at the radius each group of features
// actually occupies — not one blanket number for the whole frame.
//   RIM   d = 0.25 at r = 1.71·core: the photon ring, the sub-ring beads, the dash
//         pile-up band and the inner lensed starfield all live in that shell. A 4x
//         slowdown is what makes it read as a stop rather than as a slight drag; 0.68
//         (the disc figure) was measurably indistinguishable from no freeze at all.
//   DISC  d = 0.60 at r = 2.5·core, where the inner accretion band peaks. The disc and its
//         hotspots are much wider than the rim shell, so freezing them as hard as the rim
//         would stall the whole picture instead of the edge of it.
const float FREEZE_DILATION_RIM = 0.25;
const float FREEZE_DILATION_DISC = 0.60;
// [b7] Radial stretch of the star-dash PHASE coordinate. The dash phase is
// warp(r)·1.7 + t·flowSpeed, so constant-phase dashes drift inward at a rate
// proportional to 1/warp'(r); with warp' = 1 + L/(r − r_s) that rate falls off to a stop
// against the rim while the phase GRADIENT stays bounded and, crucially, independent of
// Time. This is where the radial half of the freeze lives.
const float FREEZE_WARP_L = 0.35;
// Floor on (r − r_s) in units of coreR: caps warp' at 1 + 0.35/0.10 = 4.5, so the dash
// phase can never slide more than ~0.016 per pixel and cannot alias into hash.
const float FREEZE_WARP_FLOOR = 0.10;

void main() {
    float strength = clamp(Strength, 0.0, 1.0);
    vec3 color;

    if (strength > 0.001) {
        float pulse = clamp(Pulse, 0.0, 1.0) * Detail;

        // Aspect-corrected frame so distances read circular on screen.
        vec2 toHole = (texCoord - Hole) * vec2(Aspect, 1.0);
        float dist = length(toHole);
        vec2 dir = toHole / max(dist, 1.0e-4);
        float ang = atan(toHole.y, toHole.x);

        // F-068 lensing ramp: the eased square keeps the early scene subtle and lets the
        // late intensity steps visibly bend the whole frame.
        // FXWAVE-9 item 4: the Pulse gulps now also PUNCH the lensing itself (+35% warp
        // reach on a full-strength swallow) — a heavy plate going over visibly bends the
        // whole starfield for a beat, not just the horizon radius.
        float lens = strength * strength * (3.0 - 2.0 * strength);
        float lensPulse = 1.0 + 0.35 * pulse;

        // [b1] radial pull: smooth far-field falloff + a 1/r near-field term (the drag
        // steepens toward the hole instead of plateauing).
        float pull = (smoothstep(0.7, 0.04, dist) * (0.10 + 0.13 * lens)
                + 0.05 * lens / (dist * 6.0 + 0.6)) * lensPulse;
        // [b2] swirl: rotation angle decays with distance (accretion drag).
        float swirl = smoothstep(0.58, 0.0, dist) * (0.85 + 0.95 * lens) * lensPulse;
        float cs = cos(swirl);
        float sn = sin(swirl);
        vec2 swirled = vec2(toHole.x * cs - toHole.y * sn, toHole.x * sn + toHole.y * cs);
        vec2 warpedUv = clamp(Hole + (swirled - dir * pull * dist) / vec2(Aspect, 1.0),
                vec2(0.001), vec2(0.999));

        // Event-horizon geometry first (the aberration band needs the ring radius).
        float core = 0.06 + 0.10 * strength;
        // [b3] shimmer: the horizon breathes ±4% on angular noise (Detail-gated); V3: the
        // Pulse gulps swell it a further +5% — the hole visibly heaves as it swallows.
        float wobble = (efxNoise(vec2(ang * 2.3 + 7.0, Time * 0.7)) - 0.5) * 0.08 * Detail;
        float coreR = core * (1.0 + wobble + 0.05 * pulse);

        // [b7] REDSHIFT FREEZE, armed only on the last two rungs of the server ladder.
        // freezeArm is an exact 0 below FREEZE_ARM_LO, which is what makes every term
        // below an identity on rungs 1-4 (see the PARSER LAW block's neighbour, the
        // idle-law note at the top of this file).
        float freezeArm = smoothstep(FREEZE_ARM_LO, FREEZE_ARM_HI, strength);
        // Schwarzschild dilation about the DRAWN rim, d(r) = sqrt(1 − r_s/r): 0 there,
        // 1 far out, falling off as 1/r all by itself so the far frame needs no second
        // window to hold it out. Used per-fragment ONLY for the redshift colour below;
        // the clocks use the constant form (see the next block for why).
        // NOTE the radius here is `core`, NOT `coreR`: coreR carries the horizon `wobble`,
        // which is a function of Time. Deriving the freeze geometry from it fed Time back
        // into the dash PHASE through the warp below, so the horizon's own ±4% shimmer
        // jittered the whole dash field radially — the freeze added motion instead of
        // removing it, and the dash layer measured WORSE than with no freeze at all.
        // The freeze geometry must be time-invariant; `core` is the un-wobbled base.
        float rs = core * FREEZE_RS;
        float dilate = sqrt(clamp(1.0 - rs / max(dist, rs), 0.0, 1.0));
        float dilation = mix(1.0, dilate, freezeArm);
        // THE CLOCK IS SPATIALLY CONSTANT, AND THAT IS NOT A SIMPLIFICATION — it is the
        // only form that survives this pass's own Time uniform. CreditsBlackHolePostFx
        // feeds Time = (fxTicks % 72000)/20, and fxTicks counts from world join, so Time
        // routinely arrives in the HUNDREDS or low THOUSANDS of seconds. A per-fragment
        // clock Time·d(r) then has a radial phase gradient of Time·d'(r), which grows
        // without bound as Time does: measured at only Time = 20 s the lensed starfield's
        // phase already slid more than HALF A CELL PER PIXEL near the rim, so the "frozen"
        // field decayed into scintillating hash and its temporal correlation came out
        // LOWER than with no freeze at all. sqrt(1 − r_s/r) is the worst offender because
        // its slope at the rim is infinite. So: one constant clock for every phase, and
        // the RADIAL half of the freeze is carried by terms that cannot alias — the dash
        // space-warp below (Time-independent by construction), the dash window slide, and
        // the redshift bleed (a colour, not a phase).
        float freezeTime = Time * mix(1.0, FREEZE_DILATION_RIM, freezeArm);
        float discTime = Time * mix(1.0, FREEZE_DILATION_DISC, freezeArm);
        // 1 - d is the same gradient read as colour. The receding (screen-left, -x) limb
        // reddens 1.3/0.7 = 1.9x harder than the approaching one; the gulps deepen it.
        float rsWeight = (1.0 - 0.30 * (toHole.x / max(dist, 1.0e-4))) * (1.0 + 0.45 * pulse);
        float bleed = clamp((1.0 - dilation) * rsWeight * 1.55, 0.0, 1.0);

        // [b2b] chromatic aberration: RGB split along the radial direction, peaking in a
        // band around the photon ring and fading into the far frame (Detail-gated).
        vec2 dirUv = dir / vec2(Aspect, 1.0);
        float ringBand = smoothstep(coreR * 4.5, coreR * 1.6, dist)
                * smoothstep(coreR * 0.8, coreR * 1.4, dist);
        // FXWAVE-9 item 4: aberration spikes +50% on the gulp — the RGB fringe flinches
        // with it.
        float caAmt = (0.0012 + 0.0035 * (0.35 + 0.65 * ringBand)) * lens * Detail
                * (1.0 + 0.5 * pulse);
        color = efxChroma(DiffuseSampler0, warpedUv, dirUv, caAmt);

        // [b4] desaturate + darken: the world grays out, then dims (never fully black here
        // — the sustained fade owns the final exit; the floor keeps the ring readable).
        // V3: the drain rides its own eased curve of strength — combined with the server's
        // 6-step intensity ladder the graying is one continuous slope, never a step.
        float luma = dot(color, LUMA_W);
        float gray = strength * strength * (3.0 - 2.0 * strength);
        color = mix(color, vec3(luma), 0.85 * gray);
        color *= 1.0 - 0.55 * gray;

        // [b7] the bleed goes in HERE, on top of the gray drain: rungs 1-4 gray the world
        // out, and then the last two rungs push the colour that the graying took back in
        // as heat, hard against the rim. Luma-locked, so the bleed re-tints without
        // re-brightening. Not Detail-gated (it is time-invariant and it is the cheap core
        // read that reducedFx keeps) — but it IS zero below the arm.
        color = mix(color, dot(color, LUMA_W) * REDSHIFT_EMBER, bleed);

        // [b3] event horizon: core drains to black with the shimmering edge.
        float horizon = smoothstep(coreR * 1.6, coreR * 0.7, dist);
        color = mix(color, vec3(0.0), horizon * strength);

        // Doppler beaming factor: the approaching (screen-right) limb burns brighter —
        // mirrors the display act's per-fragment brightness ladder (cos(theta) law).
        float doppler = 1.0 + 0.55 * (toHole.x / max(dist, 1.0e-4));

        // [b3] photon ring: thin, hot, shimmering, Doppler-beamed (Detail-gated); the
        // Pulse gulps flare it — the ring blazes when a cluster pours over the horizon.
        float ringShimmer = 0.75 + 0.25 * efxNoise(vec2(ang * 3.0, freezeTime * 0.6));
        float ring = smoothstep(coreR * 2.2, coreR * 1.55, dist)
                * (1.0 - smoothstep(coreR * 1.55, coreR * 1.0, dist));
        color += RING_COLOR * ring * ringShimmer * doppler * (0.6 + 0.55 * pulse)
                * strength * Detail;

        // V3 [b3] sub-structure: the razor-thin TRUE Einstein ring inside the main glow,
        // carrying orbiting BEADS (angular noise cells circling with time — knots of
        // lensed light) and the same Doppler beaming; it flares hard on the gulps.
        // [b7]: the beads ride freezeTime, so on the last rungs they crawl instead of
        // circling — the ring's substructure grinds down with everything else.
        float subD = abs(dist - coreR * 1.32);
        float subRing = 1.0 - smoothstep(0.0, coreR * 0.10, subD);
        float beads = 0.55 + 0.45 * efxNoise(vec2(ang * 6.0 + freezeTime * 1.4, 3.7));
        color += RING_COLOR * subRing * beads * doppler * (0.85 + 0.9 * pulse)
                * strength * Detail;

        // [b3b] accretion glow: two soft elliptical bands in the display disc's squashed
        // frame (matches the act's 0.55 up-scale), Doppler-beamed, gently shimmering, and
        // (V3) brightening on the gulps.
        vec2 discP = vec2(toHole.x, toHole.y * 1.72);
        float dDisc = length(discP);
        float band1 = smoothstep(coreR * 3.4, coreR * 2.4, dDisc)
                * (1.0 - smoothstep(coreR * 2.4, coreR * 1.5, dDisc));
        float band2 = smoothstep(coreR * 5.6, coreR * 4.0, dDisc)
                * (1.0 - smoothstep(coreR * 4.0, coreR * 2.8, dDisc));
        float discShimmer = 0.8
                + 0.2 * efxNoise(vec2(ang * 4.0 - discTime * 0.35, dDisc * 9.0));
        color += DISC_COLOR * (band1 * 0.28 + band2 * 0.13) * doppler * discShimmer
                * (1.0 + 0.7 * pulse) * strength;

        // V3 [b3b] orbiting hotspots (Detail-gated): two bright knots riding the disc bands
        // on incommensurate orbits, each flaring on a slow cubed-sine clock and smearing
        // into a wide trailing lobe BEHIND its orbital motion (leading edge sharp, wake
        // long) — the flare-and-smear read of a feeding accretion disc.
        // NOTE: no anonymous {} scopes here — Veil's GLSL processor flattens them, so
        // sibling-block locals collide ("`dA' redeclared") and the whole pass dies black.
        // [b7]: both orbits and both flare clocks read discTime, so a hotspot slows as
        // a unit. This one is load-bearing rather than incidental: a per-fragment clock
        // here turned the whole-object flare sin(t·0.83) into concentric ripple BANDS
        // across the disc, because the lobes are radially wide.
        if (Detail > 0.5 && (band1 + band2) > 0.003) {
            float angD = atan(discP.y, discP.x);
            float hot = 0.0;
            // hotspot 0 (prograde, faster)
            float dA0 = angD - (discTime * 0.42 + 2.1);
            dA0 = atan(sin(dA0), cos(dA0));
            float widen0 = dA0 < 0.0 ? 2.6 : 1.0; // wake trails behind (negative side)
            float lobe0 = 1.0 - smoothstep(0.0, 0.55 * widen0, abs(dA0));
            float flare0 = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(discTime * 0.83 + 1.3), 3.0);
            hot += lobe0 * flare0;
            // hotspot 1 (slower, de-phased)
            float dA1 = angD - (discTime * 0.27 + 5.0);
            dA1 = atan(sin(dA1), cos(dA1));
            float widen1 = dA1 < 0.0 ? 2.2 : 1.0;
            float lobe1 = 1.0 - smoothstep(0.0, 0.5 * widen1, abs(dA1));
            float flare1 = 0.3 + 0.7 * pow(0.5 + 0.5 * sin(discTime * 0.61 + 4.2), 3.0);
            hot += lobe1 * flare1;
            color += DISC_COLOR * hot * (band1 * 0.55 + band2 * 0.24) * doppler * strength;
        }

        // V3 [b5] polar jets: two opposed columns along the disc's minor axis, gated in by
        // the lensing ramp (the hole only ignites its jets once it feeds hard — from the
        // 0.7 intensity step up), pulse knots traveling OUTWARD, a slow sway, the upper
        // (approaching) jet Doppler-bright. Sheared, not rotated — one mad() per pixel.
        // F-090/F-093 JetPulse strobe: on a jet burst the columns flare ×(1 + 1.4·jetP),
        // the knot phase speed doubles and the axial window lengthens to (0.5, 0.95) —
        // the screen jets surge exactly while the display spray rides the same axis.
        float jetGate = smoothstep(0.45, 0.8, strength) * Detail;
        float jetP = clamp(JetPulse, 0.0, 1.0) * Detail;
        if (jetGate > 0.003) {
            float sway = 0.05 * sin(Time * 0.21);
            vec2 jp = vec2(toHole.x + toHole.y * sway, toHole.y);
            float axial = abs(jp.y);
            float side = jp.y >= 0.0 ? 1.0 : -1.0;
            float width = coreR * 0.26 + axial * 0.05; // a gently opening cone
            float lateral = 1.0 - smoothstep(0.0, width, abs(jp.x));
            float along = smoothstep(coreR * 1.15, coreR * 2.1, axial)
                    * (1.0 - smoothstep(mix(0.42, 0.5, jetP), mix(0.8, 0.95, jetP), axial));
            float knots = 0.62 + 0.38 * sin(axial / max(coreR, 1.0e-3) * 7.0
                    - Time * 2.4 * (1.0 + jetP) + side * 1.9);
            float jetDoppler = side > 0.0 ? 1.18 : 0.74;
            color += JET_COLOR * lateral * lateral * along * knots * jetDoppler
                    * (0.5 + 0.45 * pulse) * (1.0 + 1.4 * jetP) * jetGate;
        }

        // [b3c] star streaks: hashed angular buckets carry thin dashes flowing INWARD
        // (phase dist*k + Time — constant-phase points move to smaller dist over time).
        if (Detail > 0.5) {
            float buckets = 48.0;
            float bucketF = (ang / 3.14159265 + 1.0) * 0.5 * buckets;
            float bucket = floor(bucketF);
            float on = step(0.80, efxHash(vec2(bucket, 7.3)));
            float line = smoothstep(0.5, 0.08, abs(fract(bucketF) - 0.5));
            float flowSpeed = 0.22 + 0.18 * efxHash(vec2(bucket, 3.1));
            // [b7]: the infall stalls asymptotically against the rim — and it is done in
            // SPACE, by stretching the phase coordinate, not by scaling the clock. A
            // constant-phase dash drifts inward at 1/warpD' , which the L term drives to
            // ~1/4.5 at the rim and back to ~1 in the far field. Because warpD has no
            // Time in it, the radial phase gradient is fixed for all time — this is the
            // formulation that does NOT alias as the pass's Time uniform grows.
            float rr = max(dist - rs, core * FREEZE_WARP_FLOOR);
            float warpD = dist + freezeArm * FREEZE_WARP_L * core
                    * log(rr / (core * FREEZE_WARP_FLOOR));
            float head = fract(warpD * 1.7 + freezeTime * flowSpeed
                    + efxHash(vec2(bucket, 11.7)));
            float dash = smoothstep(0.0, 0.22, head) * (1.0 - smoothstep(0.4, 0.62, head));
            // [b7]: and the inner cutoff slides from 2·coreR down onto the rim, so the
            // stalled dashes are still DRAWN where they pile up instead of being windowed
            // away just before they get there. The target band [1.5, 2.1]·coreR is chosen
            // against BOTH neighbours: dilation there is 0.00-0.49 (so the pile-up lands
            // in the frozen shell) while [b3]'s blackout is still under 13% (so it is
            // actually on screen).
            float winLo = mix(coreR * 2.0, coreR * 1.50, freezeArm);
            float winHi = mix(coreR * 3.5, coreR * 2.10, freezeArm);
            float radialWin = smoothstep(winLo, winHi, dist)
                    * (1.0 - smoothstep(0.38, 0.7, dist));
            color += STREAK_COLOR * on * line * dash * radialWin * 0.33 * lens;

            // V3 [b6] lensed background starfield: procedural stars sampled at the SOURCE
            // radius of a point lens (r_src = r − 1.35·coreR²/r). Because coreR grows with
            // strength, the whole field visibly migrates outward around the hole as it
            // strengthens; the 1/r differential rotation makes the close stars crawl along
            // their arcs; near the ring the cell-space falloff is squeezed tangentially so
            // stars stretch into Einstein ARCS. Windowed to the hole's neighborhood (the
            // far sky already belongs to the space dome).
            // [b7]: both clocks here are freezeTime, so the census read — "the starfield
            // freezes in the last gulp" — lands on the rotation AND on the twinkle. The
            // rotation keeps its OWN 1/r differential (that term is spatial, not temporal,
            // so it is safe); what it must not also carry is a 1/r factor that multiplies
            // Time, which is exactly the aliasing this file used to have here.
            float starWin = smoothstep(coreR * 1.15, coreR * 1.8, dist)
                    * (1.0 - smoothstep(0.40, 0.62, dist));
            if (starWin > 0.003) {
                float srcR = dist - (coreR * coreR * 1.35) / max(dist, coreR * 0.5);
                float rot = 0.028 * freezeTime / (dist + 0.15);
                vec2 srcP = vec2(cos(ang + rot), sin(ang + rot)) * srcR;
                vec2 g = srcP * 110.0;
                vec2 id = floor(g);
                vec2 f = fract(g) - 0.5;
                float h = efxHash(id);
                vec2 sp = vec2(efxHash(id + 3.1), efxHash(id + 7.7)) - 0.5;
                vec2 rel = f - sp * 0.7;
                float ringProx = 1.0 - smoothstep(coreR * 1.2, coreR * 2.6, dist);
                vec2 tanv = vec2(-dir.y, dir.x);
                float dr = dot(rel, dir);
                float dt = dot(rel, tanv) / (1.0 + 7.0 * ringProx);
                float d = length(vec2(dr, dt));
                float twinkle = 0.75 + 0.25 * sin(freezeTime * 2.0 + h * 61.0);
                float star = step(0.86, h) * smoothstep(0.24, 0.03, d) * twinkle;
                color += STREAK_COLOR * star * starWin * (0.22 + 0.5 * lens);
            }
        }

        // Output dither: the desaturated dark range bands at 8 bits otherwise.
        vec2 screenPx = texCoord * vec2(textureSize(DiffuseSampler0, 0));
        color += (efxHash(screenPx + vec2(mod(floor(Time * 4.0), 97.0))) - 0.5) * (1.0 / 255.0);
    } else {
        // Idle: strict no-op. The scene passes through bit-identical — no dither, no
        // warp, no tap of anything but the source pixel. This is the else arm that
        // replaced the value-less `return;` (see the PARSER LAW block above).
        color = texture(DiffuseSampler0, texCoord).rgb;
    }

    fragColor = vec4(color, 1.0);
}
