// Gras-Wind-Shader der Ranch-Region (RW-1): Halme wogen abhängig von
// Weltposition + Zeit; `wind` kommt vom RanchWetterController (Böen).
// Billig: reine Vertex-Verschiebung, unbeleuchtete Pastell-Färbung über
// zwei Grüntöne entlang der Halmhöhe.
shader_type spatial;
render_mode cull_disabled, shadows_disabled, specular_disabled;

uniform vec4 farbe_unten : source_color = vec4(0.40, 0.58, 0.31, 1.0);
uniform vec4 farbe_oben : source_color = vec4(0.62, 0.79, 0.45, 1.0);
uniform float wind : hint_range(0.0, 2.0) = 0.35;
uniform float halm_hoehe = 0.5;

varying float hoehe_anteil;

void vertex() {
	vec3 welt = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hoehe_anteil = clamp(VERTEX.y / max(halm_hoehe, 0.001), 0.0, 1.0);
	float phase = welt.x * 0.13 + welt.z * 0.17;
	float schwung = sin(TIME * 1.7 + phase) + 0.45 * sin(TIME * 3.1 + phase * 2.3);
	float amp = wind * 0.22 * hoehe_anteil * hoehe_anteil;
	VERTEX.x += schwung * amp;
	VERTEX.z += cos(TIME * 1.3 + phase) * amp * 0.6;
}

void fragment() {
	ALBEDO = mix(farbe_unten.rgb, farbe_oben.rgb, hoehe_anteil);
	ROUGHNESS = 0.95;
}
