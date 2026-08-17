shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Farb-/Stoff-Variante eines Möbels (CONTENT-B). Ein reiner Albedo-Multiply
// funktioniert NICHT: die meisten Packs liefern getönte Texturatlanten oder
// satte Albedo-Farben, ein blaues Sofa × Rosé bleibt blau. Deshalb wird hier
// pro Pixel UMGEFÄRBT: Helligkeit des Originals behalten, Farbton von der
// Variante nehmen. Bei „natur“ wird das Originalmaterial wiederhergestellt,
// dieser Shader läuft dann gar nicht.

uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 emission_color : source_color = vec4(0.0);
uniform float emission_strength = 0.0;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
// Wie stark die Variante das Original überschreibt (1.0 = voll umgefärbt).
uniform float strength : hint_range(0.0, 1.0) = 0.9;
// Bezugshelligkeit (siehe FurnitureVariants.REFERENCE_LUMINANCE).
uniform float reference_luminance = 0.62;

void fragment() {
	vec4 source = texture(albedo_tex, UV) * base_color;
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	float level = clamp(luminance / reference_luminance, 0.35, 1.15);
	vec3 recolored = tint.rgb * level;
	ALBEDO = mix(source.rgb, recolored, strength);
	ALPHA = source.a;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	EMISSION = emission_color.rgb * emission_strength;
}
