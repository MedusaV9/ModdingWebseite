shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Umfärbe-Shader für Wände/Böden/Fassade/Grundstück (HAUS-CUSTOM) — derselbe
// Ansatz wie `scripts/shop/furniture_variant.gdshader` (CONTENT-B): Helligkeit
// des Musters behalten, Farbton von der gewählten Palette nehmen. Zwei
// bewusste Abweichungen fürs Haus:
//   1. Das Muster wird in WELT-Koordinaten gekachelt (planar, Achse nach
//      dominanter Normale) — Wandsegmente sind unterschiedlich lange Boxen,
//      mit Mesh-UVs wären Streifen auf jedem Segment anders breit.
//   2. `strength` < 1 lässt Texturfarben durchscheinen (Wildblumenwiese).
// Kosten: EIN Textur-Lookup, kein Branching im Loop — mobiltauglich.

uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D muster_tex : source_color, hint_default_white, repeat_enable;
// Weltmeter je Textur-Wiederholung (Muster wählen ihre eigene Kachelgröße).
uniform float meter_pro_kachel = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
// Wie stark die Palette das Muster überschreibt (1.0 = voll umgefärbt).
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// Bezugshelligkeit (CustomizeMaterials.REFERENCE_LUMINANCE).
uniform float reference_luminance = 0.78;

varying vec3 welt_pos;
varying vec3 welt_normal;

void vertex() {
	welt_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	welt_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(welt_normal);
	vec2 uv;
	if (n.y >= n.x && n.y >= n.z) {
		uv = welt_pos.xz; // Boden/Decke: von oben betrachtet
	} else if (n.x >= n.z) {
		uv = vec2(welt_pos.z, -welt_pos.y); // O/W-Wände: Muster steht aufrecht
	} else {
		uv = vec2(welt_pos.x, -welt_pos.y); // N/S-Wände
	}
	vec4 source = texture(muster_tex, uv / max(meter_pro_kachel, 0.001));
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	float level = clamp(luminance / reference_luminance, 0.35, 1.15);
	vec3 recolored = tint.rgb * level;
	ALBEDO = mix(source.rgb, recolored, strength);
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
