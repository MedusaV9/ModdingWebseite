// W13B/STICKER (H §3.4) — Gold-Schimmer für epische Sticker im Album.
// Mobile-günstig: eine diagonale Glanzbahn + zwei pulsierende Funkelpunkte,
// rein prozedural (keine Textur-Lookups, keine Partikel im Grid).
// `motion_scale` = Reduced-Motion-Schalter wie beim Drift-Wallpaper:
// 0.0 friert Bahn und Funkeln ein → statischer Glanz statt Animation.
shader_type canvas_item;

uniform float motion_scale: hint_range(0.0, 1.0) = 1.0; // 0 = Reduced Motion
uniform float speed = 0.35; // Bahn-Durchläufe pro Sekunde
uniform float intensity: hint_range(0.0, 1.0) = 0.28; // max. Deckkraft
uniform vec4 tint: source_color = vec4(1.0, 0.86, 0.45, 1.0); // Gold

void fragment() {
	float t = TIME * motion_scale;
	// Diagonale Glanzbahn, wandert über die Karte (statisch bei t = 0).
	float lauf = fract(UV.x * 0.7 + UV.y * 0.3 - t * speed + 0.25);
	float bahn = smoothstep(0.40, 0.50, lauf) * (1.0 - smoothstep(0.50, 0.60, lauf));
	// Zwei kleine Funkelpunkte mit versetztem Puls.
	float puls1 = 0.5 + 0.5 * sin(t * 2.6);
	float puls2 = 0.5 + 0.5 * sin(t * 2.6 + 2.4);
	float funkel1 = max(0.0, 1.0 - length(UV - vec2(0.22, 0.24)) * 12.0) * puls1;
	float funkel2 = max(0.0, 1.0 - length(UV - vec2(0.76, 0.58)) * 12.0) * puls2;
	float glanz = clamp(bahn + funkel1 + funkel2, 0.0, 1.0);
	COLOR = vec4(tint.rgb, glanz * intensity * tint.a);
}
