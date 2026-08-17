// Rim-Puls fuers Interaktions-Auge (W13/HUD-WIRES, Doc F §5 / P5-F11):
// additiver Fresnel-Saum als material_overlay auf den Meshes der
// Interactables — nicht-destruktiv (die GLB-Materialien bleiben unberuehrt)
// und mit EINEM geteilten ShaderMaterial pro Raum (gleiche Puls-Phase).
// Reduced Motion: puls_anteil = 0.0 → konstanter, ruhiger Saum ohne Puls.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform vec4 farbe : source_color = vec4(0.349, 0.788, 0.725, 1.0);
uniform float staerke : hint_range(0.0, 2.0) = 0.85;
uniform float puls_anteil : hint_range(0.0, 1.0) = 0.45;
uniform float puls_tempo : hint_range(0.0, 10.0) = 2.6;

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
	float puls = 1.0 - puls_anteil * (0.5 + 0.5 * sin(TIME * puls_tempo));
	ALBEDO = farbe.rgb;
	ALPHA = clamp(rim * staerke * puls, 0.0, 1.0);
}
