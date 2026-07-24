// eclipse:xbox_era v2 — CONSOLE-ERA color grade for the Xbox tutorial dimensions (C17,
// GRADE priority; GLITCH team pass over the "fix 4" original). Single frozen uniform:
// Amount — the 30-tick eased 0..1 from client.xbox.XboxEraFx (0 under reducedFx — the
// whole row deactivates below 0.003, so every tap here is dimension-local). Every term
// scales with Amount: the grade eases in/out as one piece and is a no-op at 0.
//
// v2 recipe — "lovingly authentic, comfy not gimmicky":
//   • 720p-ERA SOFT RESOLVE: a 4-tap diagonal blur (~1.3 px) is blended in and a share of
//     the lost high frequency is added back — the soft-yet-edge-enhanced look of an era
//     game resolving 720p onto a 1080p panel,
//   • X360 GAMMA: brightened mids (pow 0.90) + gentle black lift (the console/TV default
//     gamma wash), kept from v1,
//   • SATURATION BLOOM: the same blur taps double as a bloom source — bright SATURATED
//     regions glow softly (luma² × saturation weight), the era's blown TV colors,
//   • ERA "LUT" FEEL: three-zone procedural grade (cool shadows / warm mids / cream
//     highlights) replacing v1's single flat warm cast,
//   • CRT-ADJACENT VIGNETTE, deliberately NO scanlines: v1's pillarbox side shade + radial
//     corner falloff, plus a faint warm lift inside the falloff (phosphor glow — the
//     corners dim but never go cold),
//   • static ±1 LSB dither so the lifted blacks + vignette gradients cannot band.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Amount;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    float amount = clamp(Amount, 0.0, 1.0);
    if (amount <= 0.001) {
        fragColor = vec4(color, 1.0);
        return;
    }

    // 4-tap diagonal blur (~1.3 px) — shared by the soft resolve and the saturation bloom.
    vec2 px = 1.3 / vec2(textureSize(DiffuseSampler0, 0));
    vec3 blur = 0.25 * (texture(DiffuseSampler0, texCoord + px).rgb
            + texture(DiffuseSampler0, texCoord - px).rgb
            + texture(DiffuseSampler0, texCoord + vec2(px.x, -px.y)).rgb
            + texture(DiffuseSampler0, texCoord + vec2(-px.x, px.y)).rgb);

    // 720p-era soft resolve: soften, then add back part of the lost detail (blur+sharpen).
    vec3 high = color - blur;
    vec3 graded = mix(color, blur, 0.55 * amount) + high * 0.30 * amount;

    // Slight saturation lift (~12% — v1 had 14%; the bloom below adds the rest of the
    // era's punchy TV color, so the flat lift can back off a touch).
    float luma = dot(graded, vec3(0.299, 0.587, 0.114));
    graded = mix(vec3(luma), graded, 1.0 + 0.12 * amount);

    // X360-era gamma curve: brightened mids (exponent < 1) + a small black lift so shadows
    // read washed like an old console's default gamma, without clipping whites.
    graded = pow(max(graded, vec3(0.0)), vec3(mix(1.0, 0.90, amount)));
    vec3 lift = vec3(0.022, 0.024, 0.018) * amount;
    graded = graded * (1.0 - lift) + lift;

    // Saturation bloom: bright saturated regions of the blur glow softly on top.
    float bloomLuma = dot(blur, vec3(0.299, 0.587, 0.114));
    float bloomSat = max(max(blur.r, blur.g), blur.b) - min(min(blur.r, blur.g), blur.b);
    graded += blur * (bloomLuma * bloomLuma * clamp(bloomSat, 0.0, 1.0) * 0.35 * amount);

    // Era "LUT" feel: cool shadows / warm mids / cream highlights (zone weights sum to 1;
    // channel gains stay within ~±6% — v1's flat warm cast already sat at −6% blue — so it
    // reads as a period grade, not a filter). Polish 2: zones classify on the POST-gamma
    // luma, i.e. the value the grade actually lands on, not the pre-lift input.
    float zoneLuma = dot(graded, vec3(0.299, 0.587, 0.114));
    float shadowW = 1.0 - smoothstep(0.12, 0.42, zoneLuma);
    float highW = smoothstep(0.55, 0.85, zoneLuma);
    float midW = 1.0 - shadowW - highW;
    vec3 lut = vec3(0.985, 1.000, 1.035) * shadowW
            + vec3(1.040, 1.015, 0.940) * midW
            + vec3(1.020, 1.005, 0.965) * highW;
    graded *= mix(vec3(1.0), lut, amount);

    // 4:3-era vignette hint: shade the strips a pillarbox would sit on…
    float side = smoothstep(0.36, 0.5, abs(texCoord.x - 0.5));
    graded *= 1.0 - side * 0.10 * amount;
    // …plus the CRT corner falloff with a faint warm phosphor lift inside it (comfy: the
    // corners dim toward warm, never toward cold black). Still no scanlines, on purpose.
    float d = distance(texCoord, vec2(0.5));
    float corner = smoothstep(0.40, 0.90, d);
    graded *= 1.0 - corner * 0.09 * amount;
    graded += vec3(0.012, 0.008, 0.004) * corner * amount;

    // Static spatial dither (Amount is constant while inside the dimension, so no temporal
    // jitter is needed): kills banding from the black lift + vignette gradients.
    graded += vec3(efxDither(gl_FragCoord.xy, 0.0) * (0.5 + 0.5 * amount));

    fragColor = vec4(graded, 1.0);
}
