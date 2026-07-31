// eclipse:glitch_void — GLITCHZONE effect (TRANSITION priority): the world drains to
// near-black and the only light left is a SONAR read plus the VOID BEHIND IT. A thin contour
// shell pulses OUTWARD from the impulse origin (an expanding equidistance shell, so the ping
// is a true 3D wave crawling over the terrain), leaving a fading afterglow ring behind it;
// faint static contours every few blocks keep a minimal sense of space between pings, and a
// whisper of silhouette edge keeps nearby mass readable.
//
// WAVE-13 B4 "PARALLAXE" — the sky is no longer an empty black plate. Three star lattices
// are sampled at 21 / 68 / 300 blocks ALONG THE VIEW RAY and anchored to the camera position,
// and they show through the drained world wherever it has gone dark. That is the "Loch in die
// Unendlichkeit": the black stops being paint and becomes depth.
//
//   WHY THIS IS REAL PARALLAX, NOT A SCROLL TRICK: a lattice point sampled at distance D
//   along the ray shifts by exactly dx/D radians for a camera step dx — the physically
//   correct parallax of a star at D. Walking one block therefore slides the 21-block layer
//   14x further than the 300-block layer, and head rotation is exact because the sample
//   point rides the ray direction. The stars effectively sit on shells around the camera:
//   depth without an end, which is the read the effect is named for.
//
//   COST: ONE hash per layer. The star centre is hashed into the middle 40 % of its cell and
//   the halo radius is capped so a star can never cross its own cell boundary, which makes a
//   single-cell lookup exact and removes the 8-neighbour search a 3-D starfield usually
//   needs (see gzVoidStars in eclipse_glitch).
//
//   WRAP: the lattice is anchored to mod(CameraPosition, VOID_WRAP) to keep the sin-hash
//   argument small in fp32 (the efxDither note in eclipse_common is the law). All three cell
//   sizes divide the wrap into a multiple of the 32-cell hash period, so the field is
//   seamless across it — no pop when the camera crosses a 512-block multiple.
//
// IMPULSE ORIGIN (F-048): OriginMode 0 = the shipped behaviour, the origin is the CAMERA
// and the range read is simply linearized depth. OriginMode 1 = the origin is the world
// point `Origin` (camera-relative, VeilCamera local space — the StormVolumeFx.VolCenter
// convention), so the wave leaves the ALTAR and washes over the player instead of leaving
// the player. Only the sonar range read moves; the distance ATTENUATIONS stay camera-based,
// because they model how far the camera can see, not how far the wave has travelled.
//
// ACCENT (F-049): the sonar green is the shipped accent; AccentColor/AccentAmount swap it
// luma-matched, which is where void_purple comes from. The star field runs through the same
// helper against a cold-white shipped constant, so a purple zone has purple stars.
//
// F-102 GLITCH-FAMILY POLISH "SOG" — the pass was a scanner, not a maw. Two additions give
// the void PULL:
//   [V2] EVENT-HORIZON RING. A stationary glow shell at a fixed WORLD distance
//        (HORIZON_R blocks) around the impulse origin, on the same range read the sonar
//        already pays for — with the altar origin it is a standing ring around the altar;
//        with the camera origin you carry your own horizon. On the shell the accent burns
//        with a slow noise shimmer; INSIDE it even the drained wash dies out, so the sphere
//        around the origin reads "past this line the light does not come back".
//   [V3] RADIAL INFALL. The world origin is projected to a screen-space SINK (frame centre
//        when the origin is the camera or sits behind it) and the drained image is built
//        from two taps pulled toward that sink — the residual mass streaks INWARD, which is
//        the suction read in a still frame. Time-invariant by construction (no flicker to
//        gate for reduced FX); cost is 2 extra colour taps.
//
// HARDENING: on a dead depth attachment (flat 0.0 — the A0 session-0731 heuristic) the sonar,
// the contours and the edge whisper all switch off and the pass degrades to the pure star
// field, which needs only the ray direction. Black screen was the old failure mode.
//
// Fed by client.GlitchZoneFx: Strength (0..1 ramp — no-op at 0), Time (wall-clock seconds;
// drives the ping clock and the twinkle), Detail (0 under reduced FX: the sweep parks at a
// fixed radius and the twinkle freezes — banded contours and stars stay, nothing moves),
// AccentColor, AccentAmount, Origin, OriginMode.
//
// No value-less `return` in main() — see the glsl-processor note in umbral_veins.fsh.
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

// Ping: expands 0 -> PING_RANGE blocks over PING_PERIOD seconds, then re-fires. The period
// was 4.5 s and is now 5.0 — GlitchZoneFx wraps Time at 100 s, and 100/4.5 is not an integer,
// so the ping used to skip mid-flight once every wrap. 5.0 divides the wrap exactly.
const float PING_RANGE = 80.0;
const float PING_PERIOD = 5.0;
const vec3 SONAR = vec3(0.30, 0.95, 0.62);

// Parallax layers: sample distance along the ray (blocks) and lattice cell size (blocks).
// Angular cell size is CELL/DIST, so far = finest, near = coarsest; the near layer is the
// sparsest and the far layer the densest, which is what reads as depth.
const float FAR_DIST = 300.0;
const float FAR_CELL = 16.0;
const float MID_DIST = 68.0;
const float MID_CELL = 8.0;
const float NEAR_DIST = 21.0;
const float NEAR_CELL = 4.0;
// Camera-anchor wrap. Every cell size divides this into a multiple of GZ_VOID_CELLS (32):
// 512/16 = 32, 512/8 = 64, 512/4 = 128 — so the lattice is continuous across the wrap.
const float VOID_WRAP = 512.0;
// Cold white: the shipped star colour, luma-matched to any commanded accent.
const vec3 STAR_COLD = vec3(0.72, 0.80, 1.00);
const float STAR_GAIN = 0.90;
// [V2] Event horizon: shell distance in blocks, shell softness (blocks of falloff), and
// how dead the inside goes. 14 blocks sits well inside the altar zone's 28-block radius,
// so the standing ring is on screen for anyone near the altar.
const float HORIZON_R = 14.0;
const float HORIZON_W = 1.6;
const float SWALLOW = 0.85;
// [V3] Infall: peak UV pull toward the sink and the tail spread of the second tap.
const float SUCTION_UV = 0.028;

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    vec3 color = scene;

    if (s > 0.0005) { // else: idle — the scene passes through bit-identical
        float detail = clamp(Detail, 0.0, 1.0);
        vec3 sonar = gzAccent(SONAR, AccentColor, AccentAmount);

        float depth = texture(DiffuseDepthSampler, texCoord).r;
        float depthOk = gzDepthValid(depth);
        float sky = step(0.9999, depth);
        float dist = gzLinearDepth(depth, VeilCamera.NearPlane, VeilCamera.FarPlane);

        // Range read of the sonar: distance from the camera (shipped) or from the world
        // origin. The uniform branch is fully coherent across the frame, so the extra
        // reconstruction only costs anything in the frames that actually use a world origin.
        float range = dist;
        if (OriginMode > 0.5) {
            range = length(screenToLocalSpace(texCoord, depth).xyz - Origin);
        }

        // --- [V3] radial infall ---------------------------------------------------------
        // Screen-space sink: the projected impulse origin (fully coherent uniform branch),
        // or the frame centre for the camera origin. An origin behind the camera (clip.w
        // small/negative) also falls back to the centre — the pull direction is undefined
        // there and the centre keeps the read stable while the player turns.
        vec2 sinkUv = vec2(0.5);
        if (OriginMode > 0.5) {
            vec4 clip = VeilCamera.ProjMat * (VeilCamera.ViewMat * vec4(Origin, 1.0));
            if (clip.w > 0.1) {
                // Clamped one half-frame out: an off-screen origin still pulls sideways
                // without degenerate UV magnitudes.
                sinkUv = clamp(clip.xy / clip.w * 0.5 + 0.5, vec2(-0.5), vec2(1.5));
            }
        }
        vec2 toSink = sinkUv - texCoord;
        float sinkDist = length(toSink);
        vec2 sinkDir = toSink / max(sinkDist, 1.0e-4);
        // Pull grows toward the sink and keeps a floor at the frame edge, so the whole
        // frame leans inward, not just a bullseye. Time-invariant: nothing to freeze.
        float pull = SUCTION_UV * s * (0.35 + 0.65 * exp(-sinkDist * 2.0));
        vec3 drawn1 = texture(DiffuseSampler0,
                clamp(texCoord + sinkDir * pull, vec2(0.001), vec2(0.999))).rgb;
        vec3 drawn2 = texture(DiffuseSampler0,
                clamp(texCoord + sinkDir * pull * 2.3, vec2(0.001), vec2(0.999))).rgb;
        vec3 sucked = scene * 0.40 + drawn1 * 0.35 + drawn2 * 0.25;

        // --- drained base ---------------------------------------------------------------
        // Cold near-black: 5% luma with a blue-grey cast; the sky drains completely. Built
        // from the infall-smeared image, so the residual mass streaks toward the sink.
        vec3 base = vec3(gzLuma(sucked)) * vec3(0.045, 0.05, 0.065) * (1.0 - sky);

        // --- sonar ping -------------------------------------------------------------------
        // The live shell: bright, thin, with an exponential afterglow tail BEHIND the front
        // (terrain it already passed keeps glowing for a moment). Under reduced FX the sweep
        // parks at a fixed radius instead of expanding.
        float phase = fract(Time / PING_PERIOD);
        float sweep = mix(0.35 * PING_RANGE, phase * PING_RANGE, detail);
        float ring = exp(-abs(range - sweep) * 2.2);
        // max() before the exp: everything beyond the shell feeds a POSITIVE exponent, and at
        // a long far plane (a 1024-block view distance is enough) that overflows to +inf in
        // fp32, so the step() that is supposed to cut the tail off multiplies 0 * inf = NaN.
        // Same guard as the outline trace tail.
        float behind = step(range, sweep) * exp(-max(sweep - range, 0.0) * 0.12);
        // The ping loses energy as it expands (and the parked reduced-FX shell holds ~60%).
        float energy = mix(0.6, 1.0 - 0.65 * phase, detail);
        float ping = (ring * 1.0 + behind * 0.22) * energy * (1.0 - sky)
                * step(range, PING_RANGE + 8.0) * depthOk;

        // --- [V2] event horizon ------------------------------------------------------------
        // Standing shell at HORIZON_R blocks from the origin, on the range read the ping
        // already paid for. The shell shimmers slowly (frozen to a steady glow under
        // reduced FX); inside it the drained wash dies out — light does not come back.
        float horizon = exp(-abs(range - HORIZON_R) / HORIZON_W) * (1.0 - sky) * depthOk;
        float shimmer = mix(0.9, 0.72 + 0.28 * efxNoise(vec2(Time * 5.0, range * 0.9)), detail);
        float swallow = (1.0 - smoothstep(HORIZON_R * 0.5, HORIZON_R, range)) * depthOk;
        base *= 1.0 - SWALLOW * swallow;

        // --- static depth contours ---------------------------------------------------------
        // Faint equidistance lines every 6 blocks (triangle-wave band around the contour),
        // fading with CAMERA distance — the minimal map that keeps the void navigable between
        // pings. Banded on the same range read as the ping, so the whole sonar map is one
        // coherent set of shells around the origin.
        float bandPos = abs(fract(range / 6.0) - 0.5) * 2.0;
        float contour = smoothstep(0.85, 1.0, bandPos) * (1.0 - sky)
                * (1.0 / (1.0 + dist * 0.06)) * 0.10 * depthOk;

        // --- silhouette whisper ----------------------------------------------------------
        // Cheap depth-Laplacian edge (2 extra taps) so close mass keeps a readable rim even
        // mid-ping-cycle; normalized by distance, dead on the sky.
        vec2 texel = 1.0 / vec2(textureSize(DiffuseSampler0, 0));
        float dR = gzLinearDepth(texture(DiffuseDepthSampler, texCoord + vec2(texel.x, 0.0)).r, VeilCamera.NearPlane, VeilCamera.FarPlane);
        float dU = gzLinearDepth(texture(DiffuseDepthSampler, texCoord + vec2(0.0, texel.y)).r, VeilCamera.NearPlane, VeilCamera.FarPlane);
        float edge = smoothstep(0.10, 0.5, (abs(dR - dist) + abs(dU - dist)) / max(dist * 0.15, 0.5))
                * (1.0 - sky) * (1.0 / (1.0 + dist * 0.05)) * depthOk;

        // --- parallax void layers -----------------------------------------------------------
        // Three lattices along the same view ray at three distances (see the header). The
        // near layer is weighted heaviest and the far layer lightest, which is the aerial
        // perspective that makes the separation read as depth rather than as three overlaid
        // noise fields.
        vec3 ray = viewDirFromUv(texCoord);
        vec3 anchor = mod(VeilCamera.CameraPosition, VOID_WRAP);
        float starFar = gzVoidStars((anchor + ray * FAR_DIST) / FAR_CELL, 0.42, Time, detail);
        float starMid = gzVoidStars((anchor + ray * MID_DIST) / MID_CELL, 0.26, Time, detail);
        float starNear = gzVoidStars((anchor + ray * NEAR_DIST) / NEAR_CELL, 0.11, Time, detail);
        float stars = starFar * 0.34 + starMid * 0.62 + starNear;

        // Where the void shows through. Full in the sky; on geometry it opens up as the
        // drained image darkens AND recedes, so near-field mass stays solid and the far dark
        // dissolves into star field. On a dead depth buffer the whole frame opens up.
        float thin = mix((1.0 - smoothstep(0.02, 0.30, gzLuma(sucked)))
                * smoothstep(18.0, 90.0, dist) * 0.65, 1.0, sky);
        thin = max(thin, 1.0 - depthOk);
        // [V2] Inside the event horizon the swallowed ground DECAYS INTO STARS: the near-
        // field distance gate above would keep the void closed there, but the horizon
        // interior is precisely where the world should already be a hole into infinity
        // (the mandate's "Sternenreste"). swallow is 0 on the sky by construction.
        thin = max(thin, swallow * 0.40);
        // The ping owns the frame while it passes: stars duck under it instead of competing.
        stars *= thin * (1.0 - 0.55 * clamp(ping, 0.0, 1.0));

        vec3 voided = base
                + sonar * ping * 0.85
                + sonar * horizon * shimmer * 0.70
                + sonar * contour
                + sonar * edge * 0.12
                + gzAccent(STAR_COLD, AccentColor, AccentAmount) * stars * STAR_GAIN;

        // Breathing black vignette: the void leans in at the frame edges.
        voided *= 1.0 - 0.45 * smoothstep(0.35, 0.95, length(texCoord - 0.5) * 1.55);

        // Ramp law: desaturation and the sonar read both ride Strength; 0 = passthrough.
        color = mix(scene, voided, s);
        color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s);
    }

    fragColor = vec4(color, 1.0);
}
