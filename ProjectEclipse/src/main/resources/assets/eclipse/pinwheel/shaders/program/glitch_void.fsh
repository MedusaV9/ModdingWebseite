// eclipse:glitch_void — GLITCHZONE effect (TRANSITION priority): the world drains to
// near-black and the only light left is a SONAR read. A thin contour shell pulses OUTWARD
// from the impulse origin (an expanding equidistance shell, so the ping is a true 3D wave
// crawling over the terrain), leaving a fading afterglow ring behind it; faint static
// contours every few blocks keep a minimal sense of space between pings, and a whisper of
// silhouette edge keeps nearby mass readable. Sky is beyond the ping range: pure void.
//
// IMPULSE ORIGIN (F-048): OriginMode 0 = the shipped behaviour, the origin is the CAMERA
// and the range read is simply linearized depth. OriginMode 1 = the origin is the world
// point `Origin` (camera-relative, VeilCamera local space — the StormVolumeFx.VolCenter
// convention), so the wave leaves the ALTAR and washes over the player instead of leaving
// the player. Only the sonar range read moves; the distance ATTENUATIONS stay camera-based,
// because they model how far the camera can see, not how far the wave has travelled.
//
// ACCENT (F-049): the sonar green is the shipped accent; AccentColor/AccentAmount swap it
// luma-matched, which is where void_purple comes from.
//
// Fed by client.GlitchZoneFx: Strength (0..1 ramp — no-op at 0), Time (wall-clock seconds;
// drives the ping clock), Detail (0 under reduced FX: the sweep parks at a fixed radius —
// banded contours stay, nothing moves), AccentColor, AccentAmount, Origin, OriginMode.
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

// Ping: expands 0 -> PING_RANGE blocks over PING_PERIOD seconds, then re-fires.
const float PING_RANGE = 80.0;
const float PING_PERIOD = 4.5;
const vec3 SONAR = vec3(0.30, 0.95, 0.62);

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    vec3 scene = texture(DiffuseSampler0, texCoord).rgb;
    if (s <= 0.0005) {
        fragColor = vec4(scene, 1.0);
        return;
    }
    float detail = clamp(Detail, 0.0, 1.0);
    vec3 sonar = gzAccent(SONAR, AccentColor, AccentAmount);

    float depth = texture(DiffuseDepthSampler, texCoord).r;
    float sky = step(0.9999, depth);
    float dist = gzLinearDepth(depth, VeilCamera.NearPlane, VeilCamera.FarPlane);

    // Range read of the sonar: distance from the camera (shipped) or from the world origin.
    // The uniform branch is fully coherent across the frame, so the extra reconstruction
    // only costs anything in the frames that actually use a world origin.
    float range = dist;
    if (OriginMode > 0.5) {
        range = length(screenToLocalSpace(texCoord, depth).xyz - Origin);
    }

    // --- drained base ---------------------------------------------------------------------
    // Cold near-black: 5% luma with a blue-grey cast; the sky drains completely.
    vec3 base = vec3(gzLuma(scene)) * vec3(0.045, 0.05, 0.065) * (1.0 - sky);

    // --- sonar ping -----------------------------------------------------------------------
    // The live shell: bright, thin, with an exponential afterglow tail BEHIND the front
    // (terrain it already passed keeps glowing for a moment). Under reduced FX the sweep
    // parks at a fixed radius instead of expanding.
    float phase = fract(Time / PING_PERIOD);
    float sweep = mix(0.35 * PING_RANGE, phase * PING_RANGE, detail);
    float ring = exp(-abs(range - sweep) * 2.2);
    float behind = step(range, sweep) * exp(-(sweep - range) * 0.12);
    // The ping loses energy as it expands (and the parked reduced-FX shell holds ~60%).
    float energy = mix(0.6, 1.0 - 0.65 * phase, detail);
    float ping = (ring * 1.0 + behind * 0.22) * energy * (1.0 - sky) * step(range, PING_RANGE + 8.0);

    // --- static depth contours ---------------------------------------------------------------
    // Faint equidistance lines every 6 blocks (triangle-wave band around the contour),
    // fading with CAMERA distance — the minimal map that keeps the void navigable between
    // pings. Banded on the same range read as the ping, so the whole sonar map is one
    // coherent set of shells around the origin.
    float bandPos = abs(fract(range / 6.0) - 0.5) * 2.0;
    float contour = smoothstep(0.85, 1.0, bandPos) * (1.0 - sky)
            * (1.0 / (1.0 + dist * 0.06)) * 0.10;

    // --- silhouette whisper --------------------------------------------------------------------
    // Cheap depth-Laplacian edge (2 extra taps) so close mass keeps a readable rim even
    // mid-ping-cycle; normalized by distance, dead on the sky.
    vec2 texel = 1.0 / vec2(textureSize(DiffuseSampler0, 0));
    float dR = gzLinearDepth(texture(DiffuseDepthSampler, texCoord + vec2(texel.x, 0.0)).r, VeilCamera.NearPlane, VeilCamera.FarPlane);
    float dU = gzLinearDepth(texture(DiffuseDepthSampler, texCoord + vec2(0.0, texel.y)).r, VeilCamera.NearPlane, VeilCamera.FarPlane);
    float edge = smoothstep(0.10, 0.5, (abs(dR - dist) + abs(dU - dist)) / max(dist * 0.15, 0.5))
            * (1.0 - sky) * (1.0 / (1.0 + dist * 0.05));

    vec3 voided = base
            + sonar * ping * 0.85
            + sonar * contour
            + sonar * edge * 0.12;

    // Breathing black vignette: the void leans in at the frame edges.
    voided *= 1.0 - 0.45 * smoothstep(0.35, 0.95, length(texCoord - 0.5) * 1.55);

    // Ramp law: desaturation and the sonar read both ride Strength; 0 = passthrough.
    vec3 color = mix(scene, voided, s);
    color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s);

    fragColor = vec4(color, 1.0);
}
