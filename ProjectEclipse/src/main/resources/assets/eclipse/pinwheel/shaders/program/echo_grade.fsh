// eclipse:echo_grade — WOAH-05 Echo-Grove zone grade (GRADE priority; fed by
// client.echo.EchoGroveFx). The misty hollow reads COLD at rest — shadows lifted
// toward slate blue (#6C7A8F), 15% desaturated, gently vignetted — and turns
// GOLDEN (#E8C878 lean, +10% exposure) while a memory flood shows the past.
// Every term scales with Amount (the 70→90-block eased edge ramp), so the grade
// is a no-op at 0 and eases in/out as one piece.
//
// Uniforms (plan §4.1):
//   Amount         eased inside 0..1 (never fed at 0 — the row idle-skips),
//   Warmth         flood/finale warmth 0..1 (cue-latched, eased in EchoGroveFx),
//   AfterglowFloor 0, or 0.18 once the finale ran — the grove stays a touch
//                  warmer forever (plan §7.4),
//   Time           pause-frozen tick clock / 20 (mote glitter),
//   Detail         reducedFx gate for the glitter term (world_grade convention).
//
// The glitter is the chrono_grade star-hash re-tuned: sparse cells, slow winks,
// and it warms with the flood — cold silver dust at rest, gold sparks mid-flood.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Amount;
uniform float Warmth;
uniform float AfterglowFloor;
uniform float Time;
uniform float Detail;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    float amount = clamp(Amount, 0.0, 1.0);
    if (amount <= 0.001) {
        fragColor = vec4(color, 1.0);
        return;
    }
    float warmth = clamp(max(Warmth, AfterglowFloor), 0.0, 1.0);

    // Cold base: desaturate 15% at full Amount…
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 graded = mix(color, mix(vec3(luma), color, 0.85), amount);

    // …and lift the SHADOWS toward slate blue (#6C7A8F): the lift fades out by
    // mid-tones so highlights keep their color — mist, not a blue filter.
    vec3 coldLift = vec3(0.424, 0.478, 0.561);
    float shadowW = 1.0 - smoothstep(0.0, 0.55, luma);
    vec3 cold = graded + (coldLift - graded) * 0.22 * shadowW;

    // Warm target: golden lean (#E8C878 gains around luma) + 10% exposure.
    vec3 warmGain = vec3(1.10, 0.98, 0.80);
    vec3 warm = graded * warmGain * 1.10;
    // Warm shadows breathe amber instead of slate.
    warm += (vec3(0.55, 0.44, 0.28) - warm) * 0.10 * shadowW;

    // The whole cold↔golden move rides Warmth; both ends ride Amount.
    graded = mix(graded, mix(cold, warm, warmth), amount);
    graded = max(graded, vec3(0.0));

    // Memory motes (Detail-gated): the chrono star-hash, sparser (~3% of 30 px
    // cells), slow winks; silver at rest, gold while warm.
    if (Detail > 0.5) {
        vec2 cell = floor(gl_FragCoord.xy / 30.0);
        float host = step(0.97, efxHash(cell * 1.31));
        float phase = efxHash(cell * 2.17) * 6.2831853;
        float wink = max(0.0, sin(Time * 1.8 + phase));
        vec2 inCell = fract(gl_FragCoord.xy / 30.0) - vec2(efxHash(cell * 3.7), efxHash(cell * 5.3));
        float mote = exp(-dot(inCell, inCell) * 90.0);
        vec3 moteTint = mix(vec3(0.026, 0.030, 0.038), vec3(0.046, 0.036, 0.016), warmth);
        graded += moteTint * host * wink * wink * mote * amount;
    }

    // Gentle vignette — the hollow holds you; eases slightly OPEN while warm
    // (the past feels wider than the present).
    float d = distance(texCoord, vec2(0.5));
    float corner = smoothstep(0.35, 0.85, d);
    graded *= 1.0 - corner * 0.085 * amount * (1.0 - 0.35 * warmth);

    // Banding guard for the lift/vignette gradients.
    graded += vec3(efxDither(gl_FragCoord.xy, 0.0) * (0.5 + 0.5 * amount));

    fragColor = vec4(graded, 1.0);
}
