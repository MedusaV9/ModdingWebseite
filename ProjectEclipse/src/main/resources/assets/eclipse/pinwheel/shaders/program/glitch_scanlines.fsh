// eclipse:glitch_scanlines — GLITCHZONE effect (TRANSITION priority): reality plays back
// off a dying VHS tape through a CRT. Layers: vertical-hold jitter (the whole frame slips
// down in irregular jumps), a rolling bright scan bar with extra in-band displacement and
// noise, fine scanlines, chromatic aberration growing toward the frame edges, horizontal
// CHROMA BLEED (colour smears right while luma stays sharp — the tape look), tape static,
// and a warm-phosphor grade with corner vignette. Fed by client.GlitchZoneFx: Strength
// (0..1 ramp — no-op at 0), Time (wall-clock seconds), Detail (0 under reduced FX: hold
// jitter, rolling bar and static freeze; scanlines/aberration/bleed grade survives),
// AccentColor/AccentAmount (F-049: the tube's phosphor. A CRT has no accent object to
// recolour, so the colour leans the two things the tube itself emits — the phosphor grade
// and the scan bar's glow — through the luma-preserving gzTint, which is exactly
// vec3(1.0) at amount 0).
#include eclipse:eclipse_common
#include eclipse:eclipse_glitch

uniform sampler2D DiffuseSampler0;
uniform float Strength;
uniform float Time;
uniform float Detail;
uniform vec3 AccentColor;
uniform float AccentAmount;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    float s = clamp(Strength, 0.0, 1.0);
    if (s <= 0.0005) {
        fragColor = vec4(texture(DiffuseSampler0, texCoord).rgb, 1.0);
        return;
    }
    float detail = clamp(Detail, 0.0, 1.0);
    vec2 uv = texCoord;

    // --- vertical hold jitter ------------------------------------------------------------
    // The frame slips vertically in irregular gated jumps (~3 rolls/s window), like a CRT
    // losing sync; wraps via fract so the slipped band re-enters from the top.
    float holdSeed = floor(Time * 3.1);
    float holdGate = step(0.55, efxHash(vec2(holdSeed, 7.7))) * detail;
    uv.y = fract(uv.y + holdGate * (efxHash(vec2(holdSeed, 13.1)) - 0.5) * 0.06 * s);

    // --- rolling scan bar ------------------------------------------------------------------
    // The classic bright VHS bar rolling upward; rows inside it shove sideways slightly
    // and carry extra noise.
    float barPos = 1.0 - fract(Time * 0.20);
    float bar = exp(-abs(uv.y - barPos) * 55.0) * detail;
    uv.x += bar * (efxNoise(vec2(uv.y * 90.0, Time * 8.0)) - 0.5) * 0.03 * s;

    uv = clamp(uv, vec2(0.001), vec2(0.999));

    // --- chromatic aberration + chroma bleed -----------------------------------------------
    // Aberration grows toward the edges (CRT geometry); on top, chroma (colour minus
    // luma) is smeared rightward across ~3 taps while luma stays put — colour bleeding.
    vec2 fromCenter = uv - 0.5;
    float aber = (0.0012 + 0.004 * dot(fromCenter, fromCenter) * 4.0) * s;
    vec3 color = efxChroma(DiffuseSampler0, uv, normalize(vec2(fromCenter.x + 1.0e-4, fromCenter.y * 0.4)), aber);
    float luma = gzLuma(color);
    vec3 bleed = texture(DiffuseSampler0, clamp(uv - vec2(0.0045, 0.0) * s, vec2(0.001), vec2(0.999))).rgb
            + texture(DiffuseSampler0, clamp(uv - vec2(0.009, 0.0) * s, vec2(0.001), vec2(0.999))).rgb;
    vec3 bleedChroma = bleed * 0.5 - vec3(gzLuma(bleed * 0.5));
    color = mix(color, vec3(luma) + bleedChroma, 0.55 * s);

    // --- scanlines + aperture grille ----------------------------------------------------------
    float lines = 0.5 + 0.5 * sin(uv.y * 720.0 * 3.14159265);
    color *= 1.0 - (0.22 * lines + 0.05 * (0.5 + 0.5 * sin(uv.x * 1080.0 * 3.14159265))) * s;

    // --- static + bar highlight ---------------------------------------------------------------
    float static_ = (efxHash(uv * vec2(911.0, 631.0) + fract(Time * 11.0)) - 0.5) * 0.12 * s * detail;
    color += vec3(static_);
    vec3 tint = gzTint(AccentColor, AccentAmount);
    color += vec3(0.9, 0.95, 1.0) * tint * bar * 0.10 * s * (0.5 + 0.5 * efxNoise(vec2(uv.x * 40.0, Time * 12.0)));

    // --- phosphor grade + vignette ----------------------------------------------------------
    // Slight warm-green cast, mild desaturation, dark corners: the tube itself. The cast is
    // the commanded hue once a colour is set — a red tube, a cyan tube.
    color = mix(color, vec3(gzLuma(color)) * vec3(0.92, 1.04, 0.96) * tint, 0.30 * s);
    color *= 1.0 - 0.30 * smoothstep(0.40, 0.95, length(fromCenter) * 1.6) * s;

    color += vec3(efxDither(gl_FragCoord.xy, fract(Time * 3.0)) * s);

    fragColor = vec4(color, 1.0);
}
