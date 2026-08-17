shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert_wrap, specular_disabled;

// VIS-2 Fell-Huelle fuer Gooby (Trailer-Review "Stilbruch: 3D-Modell glatt
// und texturlos gegen das flauschige Artwork"). Laeuft als next_pass auf dem
// GoobyToon-StandardMaterial — die Geometrie/Bones/Shape-Keys des GLB bleiben
// unangetastet, die Huelle wird nur im Vertex-Shader minimal entlang der
// Normalen aufgeblasen. Drei Wirkungen in EINEM Durchgang (Mobil-Budget:
// ein zusaetzlicher Draw ueber das Gooby-Mesh, eine 128er-Noise-Textur):
//   1. Fell-KORN: die Palettenfarbe wird pro Objekt-Position minimal auf-/
//      abgehellt (pseudo-triplanares Noise — die Paletten-UVs selbst sind
//      Farbzellen und tragen keine Ortsinfo).
//   2. FLAUM an der Silhouette: Fresnel-Saum, vom Noise zerfressen —
//      eine weiche, haarige Kante statt der harten Low-Poly-Silhouette.
//   3. Warmer LICHTSAUM (Rim) mit Rosa-Stich als Subsurface-Andeutung —
//      liest an den duennen Ohren am staerksten (funktioniert identisch im
//      Mobile- UND im gl_compatibility-Renderer, anders als BaseMaterial-
//      Rim/Backlight).

// filter_linear OHNE Mipmaps: die Palette besteht aus Farbzellen — Mip-
// Stufen wuerden Nachbarzellen ineinander bluten (Regenbogen-Flecken).
uniform sampler2D palette : source_color, filter_linear;
uniform sampler2D fell_noise : hint_default_white, repeat_enable;
// Gleiche Warm-Toenung wie das albedo_color des Basis-Materials —
// sonst hellt die Huelle die Creme-Toenung wieder auf.
uniform vec3 farbton : source_color = vec3(1.0);
// Huellen-Dicke in Metern (Flaum-Laenge an der Silhouette).
uniform float flaum_dicke : hint_range(0.0, 0.05) = 0.012;
// Deckkraft des Fell-Korns auf der Flaeche (0 = aus).
uniform float korn_deckung : hint_range(0.0, 1.0) = 0.35;
// Hell/Dunkel-Hub des Korns (relativ zur Basisfarbe).
uniform float korn_kontrast : hint_range(0.0, 0.5) = 0.16;
// Noise-Wiederholungen pro Meter (Objektraum).
uniform float noise_skala : hint_range(0.5, 40.0) = 9.0;
uniform vec3 rim_farbe : source_color = vec3(1.0, 0.87, 0.82);
uniform float rim_staerke : hint_range(0.0, 1.0) = 0.4;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
	// Nur zur Silhouette hin aufblasen: frontale Flaechen bleiben (fast)
	// auf der Oberflaeche — sonst verschieben sich die Paletten-Zonen
	// (Mund/Wangen/Bauch) sichtbar gegen das Basis-Mesh (Parallaxe-
	// Schlieren). 1 mm Grundabstand verhindert Z-Fighting.
	vec3 normal_welt = normalize(mat3(MODEL_MATRIX) * NORMAL);
	vec3 zur_kamera = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float kante = 1.0 - abs(dot(normal_welt, zur_kamera));
	float hub = 0.001 + flaum_dicke * smoothstep(0.25, 0.9, kante);
	VERTEX += NORMAL * hub;
}

void fragment() {
	vec3 basis = texture(palette, UV).rgb * farbton;
	float grob = texture(fell_noise, obj_pos.xy * noise_skala).r;
	float quer = texture(fell_noise, obj_pos.zy * noise_skala + vec2(0.37, 0.19)).r;
	float fein = texture(fell_noise, obj_pos.xz * noise_skala * 2.7 + vec2(0.71, 0.53)).r;
	float korn = mix(grob, quer, 0.5) * 0.6 + fein * 0.4;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	// 1) Korn: Basisfarbe minimal modulieren (kein Farbstich, Augen bleiben dunkel).
	vec3 fell = basis * (1.0 + korn_kontrast * (korn - 0.5) * 2.0);
	// 2) Flaum: Fresnel-Saum, vom Noise erodiert — haarige weiche Kante.
	float flaum = fresnel * smoothstep(0.32, 0.78, korn);
	// 3) Warm-rosiger Lichtsaum (SSS-Andeutung, an duennen Ohren am sichtbarsten).
	ALBEDO = fell + rim_farbe * fresnel * rim_staerke;
	ALPHA = clamp(korn_deckung * (1.0 - fresnel) + flaum, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
