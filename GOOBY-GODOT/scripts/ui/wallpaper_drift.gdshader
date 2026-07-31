// AC-2.0 Drift-Wallpaper — ersetzt das komplette `--thm-drift`-CSS des Webs
// (styles.css Z. 5600 ff.). Eine Pattern-Kachel wandert langsam schräg über
// den Screen: Guardrails 80–120 s pro Kachelperiode, Deckkraft ≤ 6 %.
// `motion_scale` = Reduced-Motion-Schalter (0.0 stoppt den Drift komplett).
shader_type canvas_item;

uniform sampler2D tile: repeat_enable, filter_linear_mipmap;
// Kacheln/Sekunde, schräg — Default (-0.010, 0.007) ≈ 100 s pro Kachel.
uniform vec2 drift = vec2(-0.010, 0.007);
uniform float tile_count = 3.0; // Kacheln über die BREITE des Rects
// LAYER-Deckkraft (Web .screen::before 0.45 / --thm-pattern-opacity 0.85).
// Der ≤-6-%-Guardrail gilt für den EFFEKTIVEN Glyph-Kontrast: die Kacheln
// backen ihr geringes Luminanz-Delta selbst ein (UICOZY-Fehllesart behoben).
uniform float opacity: hint_range(0.0, 1.0) = 0.45;
uniform vec4 wash: source_color = vec4(1.0, 0.965, 0.925, 1.0); // BG_CREAM
uniform vec2 rect_size = vec2(1280.0, 720.0); // vom Control gesetzt (Aspect)
uniform float motion_scale: hint_range(0.0, 1.0) = 1.0; // 0 = Reduced Motion
// W13-C: Gyro-/Pointer-Parallax (gyro_parallax.gd) — additiver UV-Schub.
uniform vec2 parallax_uv = vec2(0.0);

void fragment() {
	float aspect = rect_size.y / max(rect_size.x, 1.0);
	vec2 uv = UV * tile_count * vec2(1.0, aspect);
	uv += TIME * drift * motion_scale + parallax_uv * motion_scale;
	vec4 c = texture(tile, uv);
	COLOR = vec4(mix(wash.rgb, c.rgb, c.a * opacity), wash.a);
}
