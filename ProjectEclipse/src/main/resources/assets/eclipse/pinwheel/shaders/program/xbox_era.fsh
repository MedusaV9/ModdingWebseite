// eclipse:xbox_era — CONSOLE-ERA color grade for the Xbox tutorial dimensions (C17,
// GRADE priority). Recipe per PLAN-C C17 fix 4: slight saturation lift + an X360-era
// gamma curve (brightened mids, gently lifted blacks — the old console/TV output look)
// + a subtle warm yellow-green cast + a 4:3-era vignette HINT (side shading where the
// pillarbox would sit, plus a faint radial corner falloff).
// Uniform: Amount — the 30-tick eased 0..1 amount from client.xbox.XboxEraFx (zero under
// reducedFx — the whole pipeline row deactivates). Every term scales with Amount, so the
// grade eases in/out as one piece and is a no-op at 0.

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

    // Slight saturation lift (~14% at full strength) — the era's punchy TV colors.
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 graded = mix(vec3(luma), color, 1.0 + 0.14 * amount);

    // X360-era gamma curve: brightened mids (exponent < 1) + a small black lift so
    // shadows read washed like an old console's default gamma, without clipping whites.
    graded = pow(max(graded, vec3(0.0)), vec3(mix(1.0, 0.90, amount)));
    vec3 lift = vec3(0.022, 0.024, 0.018) * amount;
    graded = graded * (1.0 - lift) + lift;

    // Gentle warm yellow-green cast (the classic X360 composite look).
    graded *= mix(vec3(1.0), vec3(1.03, 1.02, 0.94), amount);

    // 4:3-era vignette hint: shade the strips a pillarbox would cover…
    float side = smoothstep(0.36, 0.5, abs(texCoord.x - 0.5));
    graded *= 1.0 - side * 0.10 * amount;
    // …plus a faint radial corner falloff (CRT corner shadow).
    float d = distance(texCoord, vec2(0.5));
    graded *= 1.0 - smoothstep(0.42, 0.85, d) * 0.08 * amount;

    fragColor = vec4(graded, 1.0);
}
