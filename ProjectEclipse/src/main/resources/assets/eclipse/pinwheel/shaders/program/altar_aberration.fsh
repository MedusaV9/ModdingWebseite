// eclipse:altar_aberration — chromatic-aberration gradient around the altar (P2 R9,
// FEATURE priority). Subtle at the spawn-area boundary, strongest at the altar center:
// client.AltarAberration computes the zone strength each tick (curve (1 − d/r)² · 0.85,
// anchor eclipse:altar_center via FxAnchors, spawn fallback) and feeds the ONE frozen
// uniform per frame with a 0.3 Hz breathing modulation already baked in (§3.3 keeps this
// shader single-uniform by design).
//   - radial RGB split away from the screen center, up to ~10 px at the zone center
//   - ~1% barrel distortion easing in above Aberration ≈ 0.6
//   - faint cold-violet lift so the zone reads "not normal" — never nauseating
uniform sampler2D DiffuseSampler0;
uniform float Aberration;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    float a = clamp(Aberration, 0.0, 1.0);
    vec2 center = vec2(0.5);
    vec2 delta = texCoord - center;
    float r2 = dot(delta, delta);

    // Barrel distortion: off below ~0.55, ~1% edge pull at full strength.
    float barrel = smoothstep(0.55, 0.7, a) * 0.03;
    vec2 uv = center + delta * (1.0 - barrel * r2);

    // Radial RGB split from the screen center (grows outward; ~10 px at the screen edge).
    float split = 0.012 * a;
    vec3 color;
    color.r = texture(DiffuseSampler0, uv + delta * split).r;
    color.g = texture(DiffuseSampler0, uv).g;
    color.b = texture(DiffuseSampler0, uv - delta * split).b;

    // Faint cold-violet lift toward the zone center — "something is wrong with this place".
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 violet = mix(color, vec3(luma) * vec3(0.92, 0.85, 1.08), 0.25);
    color = mix(color, violet, a * 0.4);

    fragColor = vec4(color, 1.0);
}
