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
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Strength;
uniform vec2 Hole;
uniform float Aspect;
uniform float Time;
uniform float Detail;
uniform float Pulse;

in vec2 texCoord;

out vec4 fragColor;

const vec3 LUMA_W = vec3(0.299, 0.587, 0.114);
// Warm-violet finale palette (the ferryman2 law, mirrored from the Photon assets).
const vec3 RING_COLOR = vec3(0.85, 0.62, 1.05);
const vec3 DISC_COLOR = vec3(0.72, 0.52, 0.95);
const vec3 STREAK_COLOR = vec3(0.82, 0.72, 1.0);
const vec3 JET_COLOR = vec3(0.78, 0.68, 1.05);

void main() {
    float strength = clamp(Strength, 0.0, 1.0);
    if (strength <= 0.001) {
        fragColor = vec4(texture(DiffuseSampler0, texCoord).rgb, 1.0);
        return;
    }
    float pulse = clamp(Pulse, 0.0, 1.0) * Detail;

    // Aspect-corrected frame so distances read circular on screen.
    vec2 toHole = (texCoord - Hole) * vec2(Aspect, 1.0);
    float dist = length(toHole);
    vec2 dir = toHole / max(dist, 1.0e-4);
    float ang = atan(toHole.y, toHole.x);

    // F-068 lensing ramp: the eased square keeps the early scene subtle and lets the
    // late intensity steps visibly bend the whole frame.
    float lens = strength * strength * (3.0 - 2.0 * strength);

    // [b1] radial pull: smooth far-field falloff + a 1/r near-field term (the drag
    // steepens toward the hole instead of plateauing).
    float pull = smoothstep(0.7, 0.04, dist) * (0.10 + 0.13 * lens)
            + 0.05 * lens / (dist * 6.0 + 0.6);
    // [b2] swirl: rotation angle decays with distance (accretion drag).
    float swirl = smoothstep(0.58, 0.0, dist) * (0.85 + 0.95 * lens);
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

    // [b2b] chromatic aberration: RGB split along the radial direction, peaking in a
    // band around the photon ring and fading into the far frame (Detail-gated).
    vec2 dirUv = dir / vec2(Aspect, 1.0);
    float ringBand = smoothstep(coreR * 4.5, coreR * 1.6, dist)
            * smoothstep(coreR * 0.8, coreR * 1.4, dist);
    float caAmt = (0.0012 + 0.0035 * (0.35 + 0.65 * ringBand)) * lens * Detail;
    vec3 color = efxChroma(DiffuseSampler0, warpedUv, dirUv, caAmt);

    // [b4] desaturate + darken: the world grays out, then dims (never fully black here —
    // the sustained fade owns the final exit; the floor keeps the ring readable).
    // V3: the drain rides its own eased curve of strength — combined with the server's
    // 6-step intensity ladder the graying is one continuous slope, never a step.
    float luma = dot(color, LUMA_W);
    float gray = strength * strength * (3.0 - 2.0 * strength);
    color = mix(color, vec3(luma), 0.85 * gray);
    color *= 1.0 - 0.55 * gray;

    // [b3] event horizon: core drains to black with the shimmering edge.
    float horizon = smoothstep(coreR * 1.6, coreR * 0.7, dist);
    color = mix(color, vec3(0.0), horizon * strength);

    // Doppler beaming factor: the approaching (screen-right) limb burns brighter —
    // mirrors the display act's per-fragment brightness ladder (cos(theta) law).
    float doppler = 1.0 + 0.55 * (toHole.x / max(dist, 1.0e-4));

    // [b3] photon ring: thin, hot, shimmering, Doppler-beamed (Detail-gated); the Pulse
    // gulps flare it — the ring blazes when a cluster pours over the horizon.
    float ringShimmer = 0.75 + 0.25 * efxNoise(vec2(ang * 3.0, Time * 0.6));
    float ring = smoothstep(coreR * 2.2, coreR * 1.55, dist)
            * (1.0 - smoothstep(coreR * 1.55, coreR * 1.0, dist));
    color += RING_COLOR * ring * ringShimmer * doppler * (0.6 + 0.55 * pulse) * strength * Detail;

    // V3 [b3] sub-structure: the razor-thin TRUE Einstein ring inside the main glow,
    // carrying orbiting BEADS (angular noise cells circling with time — knots of lensed
    // light) and the same Doppler beaming; it flares hard on the gulps.
    float subD = abs(dist - coreR * 1.32);
    float subRing = 1.0 - smoothstep(0.0, coreR * 0.10, subD);
    float beads = 0.55 + 0.45 * efxNoise(vec2(ang * 6.0 + Time * 1.4, 3.7));
    color += RING_COLOR * subRing * beads * doppler * (0.85 + 0.9 * pulse) * strength * Detail;

    // [b3b] accretion glow: two soft elliptical bands in the display disc's squashed
    // frame (matches the act's 0.55 up-scale), Doppler-beamed, gently shimmering, and
    // (V3) brightening on the gulps.
    vec2 discP = vec2(toHole.x, toHole.y * 1.72);
    float dDisc = length(discP);
    float band1 = smoothstep(coreR * 3.4, coreR * 2.4, dDisc)
            * (1.0 - smoothstep(coreR * 2.4, coreR * 1.5, dDisc));
    float band2 = smoothstep(coreR * 5.6, coreR * 4.0, dDisc)
            * (1.0 - smoothstep(coreR * 4.0, coreR * 2.8, dDisc));
    float discShimmer = 0.8 + 0.2 * efxNoise(vec2(ang * 4.0 - Time * 0.35, dDisc * 9.0));
    color += DISC_COLOR * (band1 * 0.28 + band2 * 0.13) * doppler * discShimmer
            * (1.0 + 0.7 * pulse) * strength;

    // V3 [b3b] orbiting hotspots (Detail-gated): two bright knots riding the disc bands
    // on incommensurate orbits, each flaring on a slow cubed-sine clock and smearing
    // into a wide trailing lobe BEHIND its orbital motion (leading edge sharp, wake
    // long) — the flare-and-smear read of a feeding accretion disc.
    // NOTE: no anonymous {} scopes here — Veil's GLSL processor flattens them, so
    // sibling-block locals collide ("`dA' redeclared") and the whole pass dies black.
    if (Detail > 0.5 && (band1 + band2) > 0.003) {
        float angD = atan(discP.y, discP.x);
        float hot = 0.0;
        // hotspot 0 (prograde, faster)
        float dA0 = angD - (Time * 0.42 + 2.1);
        dA0 = atan(sin(dA0), cos(dA0));
        float widen0 = dA0 < 0.0 ? 2.6 : 1.0; // wake trails behind (negative side)
        float lobe0 = 1.0 - smoothstep(0.0, 0.55 * widen0, abs(dA0));
        float flare0 = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(Time * 0.83 + 1.3), 3.0);
        hot += lobe0 * flare0;
        // hotspot 1 (slower, de-phased)
        float dA1 = angD - (Time * 0.27 + 5.0);
        dA1 = atan(sin(dA1), cos(dA1));
        float widen1 = dA1 < 0.0 ? 2.2 : 1.0;
        float lobe1 = 1.0 - smoothstep(0.0, 0.5 * widen1, abs(dA1));
        float flare1 = 0.3 + 0.7 * pow(0.5 + 0.5 * sin(Time * 0.61 + 4.2), 3.0);
        hot += lobe1 * flare1;
        color += DISC_COLOR * hot * (band1 * 0.55 + band2 * 0.24) * doppler * strength;
    }

    // V3 [b5] polar jets: two opposed columns along the disc's minor axis, gated in by
    // the lensing ramp (the hole only ignites its jets once it feeds hard — from the
    // 0.7 intensity step up), pulse knots traveling OUTWARD, a slow sway, the upper
    // (approaching) jet Doppler-bright. Sheared, not rotated — one mad() per pixel.
    float jetGate = smoothstep(0.45, 0.8, strength) * Detail;
    if (jetGate > 0.003) {
        float sway = 0.05 * sin(Time * 0.21);
        vec2 jp = vec2(toHole.x + toHole.y * sway, toHole.y);
        float axial = abs(jp.y);
        float side = jp.y >= 0.0 ? 1.0 : -1.0;
        float width = coreR * 0.26 + axial * 0.05; // a gently opening cone
        float lateral = 1.0 - smoothstep(0.0, width, abs(jp.x));
        float along = smoothstep(coreR * 1.15, coreR * 2.1, axial)
                * (1.0 - smoothstep(0.42, 0.8, axial));
        float knots = 0.62 + 0.38 * sin(axial / max(coreR, 1.0e-3) * 7.0
                - Time * 2.4 + side * 1.9);
        float jetDoppler = side > 0.0 ? 1.18 : 0.74;
        color += JET_COLOR * lateral * lateral * along * knots * jetDoppler
                * (0.5 + 0.45 * pulse) * jetGate;
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
        float head = fract(dist * 1.7 + Time * flowSpeed + efxHash(vec2(bucket, 11.7)));
        float dash = smoothstep(0.0, 0.22, head) * (1.0 - smoothstep(0.4, 0.62, head));
        float radialWin = smoothstep(coreR * 2.0, coreR * 3.5, dist)
                * (1.0 - smoothstep(0.38, 0.7, dist));
        color += STREAK_COLOR * on * line * dash * radialWin * 0.33 * lens;

        // V3 [b6] lensed background starfield: procedural stars sampled at the SOURCE
        // radius of a point lens (r_src = r − 1.35·coreR²/r). Because coreR grows with
        // strength, the whole field visibly migrates outward around the hole as it
        // strengthens; the 1/r differential rotation makes the close stars crawl along
        // their arcs; near the ring the cell-space falloff is squeezed tangentially so
        // stars stretch into Einstein ARCS. Windowed to the hole's neighborhood (the
        // far sky already belongs to the space dome).
        float starWin = smoothstep(coreR * 1.15, coreR * 1.8, dist)
                * (1.0 - smoothstep(0.40, 0.62, dist));
        if (starWin > 0.003) {
            float srcR = dist - (coreR * coreR * 1.35) / max(dist, coreR * 0.5);
            float rot = 0.028 * Time / (dist + 0.15);
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
            float twinkle = 0.75 + 0.25 * sin(Time * 2.0 + h * 61.0);
            float star = step(0.86, h) * smoothstep(0.24, 0.03, d) * twinkle;
            color += STREAK_COLOR * star * starWin * (0.22 + 0.5 * lens);
        }
    }

    // Output dither: the desaturated dark range bands at 8 bits otherwise.
    vec2 screenPx = texCoord * vec2(textureSize(DiffuseSampler0, 0));
    color += (efxHash(screenPx + vec2(mod(floor(Time * 4.0), 97.0))) - 0.5) * (1.0 / 255.0);

    fragColor = vec4(color, 1.0);
}
