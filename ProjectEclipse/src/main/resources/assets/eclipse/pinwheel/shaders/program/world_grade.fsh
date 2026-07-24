// eclipse:world_grade — consolidated night/eclipse screen grade (P2 R3/R16, GRADE priority).
// THE "sky never darkens" fix: there was no darkness treatment at all before — perceived
// night brightness was whatever the user's gamma made of the vanilla lightmap. This pass
// crushes the FINAL image, so it defeats gamma without touching options.
// Uniforms (frozen §3.3): EclipseAmount, NightAmount, DesatAmount, ExposureMul — fed per
// frame by veilfx.VeilPostController (NightAmount = (1 - dayFactor) * 0.55, eclipse state
// from EclipseFxState). Active only while NightAmount > 0.01 || EclipseAmount > 0.01.
#include eclipse:eclipse_common

uniform sampler2D DiffuseSampler0;
uniform sampler2D DiffuseDepthSampler;
uniform float EclipseAmount;
uniform float NightAmount;
uniform float DesatAmount;
uniform float ExposureMul;

in vec2 texCoord;

out vec4 fragColor;

void main() {
    vec3 color = texture(DiffuseSampler0, texCoord).rgb;
    // 0.55 cap keeps a full eclipse readable (dark violet dusk, not black) — the
    // cinematic flight and the approach walk both happen at EclipseAmount == 1.
    float crush = max(NightAmount, EclipseAmount * 0.55);

    // Shadow-crushing tone curve (robust against user gamma — operates on the final frame).
    color = efxCrush(color, crush);

    // Desaturate toward violet as the eclipse deepens.
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 violet = luma * vec3(0.82, 0.62, 1.10);
    color = mix(color, mix(vec3(luma), violet, 0.7), clamp(DesatAmount, 0.0, 1.0));

    // Sky-region extra dim: pixels at the far plane are pure sky — pull them down further
    // so the dome reads dark even where fog/sky colors fight the grade.
    float depth = texture(DiffuseDepthSampler, texCoord).r;
    float sky = step(0.9999, depth);
    color *= 1.0 - sky * crush * 0.25;

    // Exposure dip (0.62 during eclipse TOTAL, eased CPU-side over 60 ticks — the old
    // 0.35 target rendered totality near-black on top of the crush; see EclipseFxState).
    color *= ExposureMul;

    fragColor = vec4(color, 1.0);
}
