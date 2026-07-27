// eclipse:chrono_grade — WOAH-03 Chrono-Stasis zone grade (GRADE priority; fed by
// woah.chronostasis.client.ChronoGradeFx). The frozen clearing reads as an instant held
// under glass: desaturated, cool, quietly vignetted, with a very fine additive "time
// dust" glitter hanging in the air. Every term scales with Amount (the 12-block eased
// edge ramp), so the grade is a no-op at 0 and eases in/out as one piece.
//
// Uniforms (plan §4.2):
//   Amount     eased inside 0..1 (idle-skips below 0.01 — the row is never fed at 0),
//   Time       pause-frozen tick clock / 20 (glitter shimmer + slow drift),
//   Tint       cool cast gains applied around luma (0.82, 0.90, 1.10),
//   Saturation TARGET saturation factor (0.55 = the scene keeps 55% of its chroma),
//   Contrast   gentle contrast around 0.5 luma (1.03),
//   Vignette   falloff scale (1.3 — heavier than the xbox_era default: the clearing
//              closes in on you),
//   Flash      discharge white kick 0..1 (a ~14-tick decay fed only during DISCHARGE —
//              one uniform pulse, deliberately NOT a second pass).
//
// The glitter is the xbox_era scan-band analogy re-cast as a star-hash: a sparse
// (~1/700 px) set of hash cells winks in and out on per-cell phases. Slow (0.4 Hz max
// per cell), tiny (≤ +3.5% luma), additive — felt, not seen; no photosensitivity budget.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform float Amount;
uniform float Time;
uniform vec3 Tint;
uniform float Saturation;
uniform float Contrast;
uniform float Vignette;
uniform float Flash;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    float amount = clamp(Amount, 0.0, 1.0);
    if (amount <= 0.001) {
        fragColor = vec4(color, 1.0);
        return;
    }

    // Desaturate toward the target factor: at Amount 1 the scene keeps `Saturation`
    // of its chroma (0.55 = time-drained but not monochrome).
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 graded = mix(color, mix(vec3(luma), color, Saturation), amount);

    // Cool cast: per-channel gains around the (post-desaturation) luma so the cast
    // shifts hue without dimming the image (Tint sums ≈ neutral by construction).
    graded *= mix(vec3(1.0), Tint, amount);

    // Gentle contrast around mid gray — frozen light reads a touch harder.
    graded = (graded - 0.5) * mix(1.0, Contrast, amount) + 0.5;
    graded = max(graded, vec3(0.0));

    // Time dust: sparse star-hash glitter. Cells of ~26 px; each cell has a hash phase
    // and only ~4% of cells host a mote; each mote winks on a slow per-cell sine.
    vec2 cell = floor(gl_FragCoord.xy / 26.0);
    float host = step(0.96, efxHash(cell * 1.31));
    float phase = efxHash(cell * 2.17) * 6.2831853;
    float wink = max(0.0, sin(Time * 2.2 + phase));
    // Position the mote inside its cell so it does not fill the whole square.
    vec2 inCell = fract(gl_FragCoord.xy / 26.0) - vec2(efxHash(cell * 3.7), efxHash(cell * 5.3));
    float mote = exp(-dot(inCell, inCell) * 90.0);
    graded += vec3(0.030, 0.033, 0.040) * host * wink * wink * mote * amount;

    // Vignette: radial falloff scaled by the plan's 1.3 — cool, never warm.
    float d = distance(texCoord, vec2(0.5));
    float corner = smoothstep(0.35, 0.85, d);
    graded *= 1.0 - corner * 0.10 * amount * Vignette;

    // Discharge white kick: additive lift toward white, strongest at screen center
    // (the bolt just discharged) — fed only during the ~14 ticks after the cue.
    float flash = clamp(Flash, 0.0, 1.0) * amount;
    float centerW = 1.0 - smoothstep(0.0, 0.7, d);
    graded = mix(graded, vec3(1.0), flash * (0.28 + 0.22 * centerW));

    // Banding guard for the vignette/desaturation gradients.
    graded += vec3(efxDither(gl_FragCoord.xy, 0.0) * (0.5 + 0.5 * amount));

    fragColor = vec4(graded, 1.0);
}
