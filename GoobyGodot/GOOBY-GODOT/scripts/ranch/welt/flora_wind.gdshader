// Flora-Billboard-Shader (VIS-1): texturierte Pflanzen-Quads (Korn,
// Lavendel) mit Alpha-Scissor und Wind-Wogen. Die Verschiebung wächst
// quadratisch mit der Halmhöhe (unten verwurzelt, oben schwingt), Phase
// kommt aus der Weltposition — Nachbarn wogen versetzt, kein Gleichtakt.
// `wind` treibt der RanchWetterController über WeltFlora.wind_materialien().
shader_type spatial;
render_mode cull_disabled, shadows_disabled, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float wind : hint_range(0.0, 2.0) = 0.35;
uniform float hoehe = 1.05;
// Leichter Farb-Multiplikator (Sorten-Tönung ohne eigene Textur).
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying float hoehe_anteil;

void vertex() {
	vec3 welt = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hoehe_anteil = clamp(VERTEX.y / max(hoehe, 0.001), 0.0, 1.0);
	float phase = welt.x * 0.21 + welt.z * 0.17;
	float schwung = sin(TIME * 1.5 + phase) + 0.4 * sin(TIME * 2.9 + phase * 1.7);
	float amp = (0.12 + wind * 0.2) * 0.5 * hoehe_anteil * hoehe_anteil;
	VERTEX.x += schwung * amp;
	VERTEX.z += cos(TIME * 1.1 + phase) * amp * 0.6;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * tint.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.42;
	ROUGHNESS = 0.92;
	// Beleuchtung wie der Boden darunter (Billboards haben keine echte
	// Flächennormale — Welt-Oben verhindert schwarze Rückseiten).
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
