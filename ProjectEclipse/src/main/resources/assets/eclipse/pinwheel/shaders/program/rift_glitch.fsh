// eclipse:rift_glitch — rift/portal/loading transition pass (P2 R13/R17, TRANSITION
// priority). Two independent knobs, fed per frame by veilfx.TransitionFx:
//   GlitchAmount — digital tearing: datamosh block displacement + fine row jitter +
//                  chromatic tear + 2-frame invert pops + scanline shimmer.
//   FadeAmount   — fade-to-black as a closing iris with a violet edge bleed at the front
//                  (0 = clear, 1 = fully black; the portal hold keeps it at 1 while the
//                  dimension change happens behind it).
//   Time         — wall-clock seconds (keeps animating while client ticks stall during a
//                  dimension change).
// Uniform names are frozen (§3.3). GUI-side loading visuals are P3's; this pass only
// touches the world frame.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float GlitchAmount;
uniform float FadeAmount;
uniform float Time;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    float g = clamp(GlitchAmount, 0.0, 1.0);
    float f = clamp(FadeAmount, 0.0, 1.0);

    // Re-seed the artifact pattern ~12x/s — blocks pop instead of sliding.
    float seed = floor(Time * 12.0) * 0.618 + 1.0;

    // Coarse datamosh rows jump sideways; a sparse set of fine rows jitters on top.
    vec2 uv = texCoord + efxBlockOffset(texCoord, seed, g);
    float row = floor(uv.y * 90.0);
    uv.x += (efxHash(vec2(row, seed * 1.37)) - 0.5) * 0.02 * g
            * step(0.82, efxHash(vec2(row * 0.71, seed)));

    // Chromatic tear along the displacement axis (~15 px at 1080p when fully glitched).
    vec3 color = efxChroma(DiffuseSampler0, uv, vec2(1.0, 0.35), g * 0.008);

    // 2-frame invert pops once the glitch is violent (gated by the re-seed hash so a pop
    // lasts exactly one seed frame ≈ 2 render frames).
    float pop = step(0.9, efxHash(vec2(seed, 17.3))) * step(0.55, g);
    color = mix(color, vec3(1.0) - color, pop);

    // Scanline shimmer.
    color *= 1.0 - 0.10 * g * (0.5 + 0.5 * sin(texCoord.y * 420.0 + Time * 28.0));

    // Fade-to-black iris: the black front closes from the screen edges toward the center;
    // pixels just inside the front bleed violet (R13's "fade-to-black with violet edge
    // bleed"). At f=1 the whole frame is exactly black (front radius is past the center).
    vec2 p = texCoord * 2.0 - 1.0;
    float r = length(p * vec2(1.15, 1.0));
    float front = 1.62 - f * 2.1;
    float black = smoothstep(front, front + 0.28, r);
    float bleed = smoothstep(front - 0.30, front, r) * (1.0 - black);
    vec3 violet = vec3(0.30, 0.08, 0.52) * (0.35 + 0.65 * efxNoise(p * 5.0 + vec2(Time, -Time)));
    color = mix(color, color * 0.35 + violet, bleed * min(1.0, f * 2.0));
    color *= 1.0 - black;

    fragColor = vec4(color, 1.0);
}
