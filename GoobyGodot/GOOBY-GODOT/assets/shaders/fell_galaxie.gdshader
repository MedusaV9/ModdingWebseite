shader_type spatial;
render_mode blend_mix, cull_back, specular_disabled;

// GALAXIE-Fell (W13B, H §4): Premium-Fellfarbe als EIN Shader-Material auf
// Surface 0 des Gooby-Meshes — ersetzt das Palette-Override der normalen
// Fellfarben NUR bei ausgerüsteter Galaxie-Farbe (cosmetic_attach.apply_fell).
//
// Look: tiefdunkles Blauviolett mit langsam driftendem Nebel-Schimmer und
// funkelnden Sternen. Mobile-Budget bewusst klein gehalten:
//   - KEINE Partikel, keine Zusatz-Textur: Nebel = 2 Oktaven Value-Noise,
//     Sterne = ein Hash-Punktgitter (beides Muster aus gooby_himmel.gdshader).
//   - Die Paletten-UVs tragen keine Ortsinfo (Farbzellen, s. gooby_flaum) —
//     Nebel/Sterne rechnen deshalb über die OBJEKT-Position.
//   - Nur die drei FELL-Zellen der Palette (body/belly/earInner = Zellen
//     0-2, oberste Reihe) bekommen Galaxie; Augen/Nase/Wangen bleiben die
//     Farben der (umgefärbten) Palette.
//   - Reduced-Motion: `bewegung = 0.0` friert Drift UND Funkeln ein —
//     das Fell bleibt sichtbar „Galaxie“, nur eben statisch.

// filter_linear OHNE Mipmaps — Farbzellen würden sonst ineinander bluten.
uniform sampler2D palette : source_color, filter_linear;
// 1.0 = Nebel driftet + Sterne funkeln; 0.0 = komplett statisch.
uniform float bewegung : hint_range(0.0, 1.0) = 1.0;
// Nebel-Schimmer: zwei Tönungen, zwischen denen der Noise wandert.
uniform vec3 nebel_farbe_a : source_color = vec3(0.16, 0.10, 0.34);
uniform vec3 nebel_farbe_b : source_color = vec3(0.42, 0.22, 0.58);
uniform float nebel_staerke : hint_range(0.0, 1.0) = 0.55;
uniform float nebel_skala : hint_range(0.5, 20.0) = 4.5;
uniform float drift_tempo : hint_range(0.0, 0.2) = 0.03;
// Sternen-Funkeln: Punktgitter-Dichte, Deckel + Funkel-Geschwindigkeit.
uniform vec3 stern_farbe : source_color = vec3(0.95, 0.93, 1.0);
uniform float stern_dichte : hint_range(2.0, 60.0) = 22.0;
uniform float stern_anteil : hint_range(0.0, 1.0) = 0.22;
uniform float funkel_tempo : hint_range(0.0, 8.0) = 1.6;

varying vec3 obj_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float wert_rauschen(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Ein Sternfeld auf einer 2D-Ebene: Punktgitter, pro Zelle max. ein Stern
// mit Hash-Versatz und eigenem Funkel-Rhythmus (statisch bei bewegung=0).
float sternfeld(vec2 p, float zeit) {
	vec2 zelle = floor(p);
	vec2 innen = fract(p) - 0.5;
	float h = hash21(zelle);
	vec2 versatz = vec2(hash21(zelle + 3.1), hash21(zelle + 7.7)) - 0.5;
	float d = length(innen - versatz * 0.7);
	float stern = smoothstep(0.16, 0.02, d) * step(1.0 - stern_anteil, h);
	float funkeln = 0.65 + 0.35 * sin(zeit * (1.0 + h * 3.0) + h * 40.0);
	return stern * funkeln;
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 basis = texture(palette, UV).rgb;
	// Fell-Zellen der 4x4-Palette: oberste Reihe, Spalten 0-2 (body/belly/
	// earInner — cosmetic_attach.FELL_ZELLEN). Alles andere bleibt Palette.
	float zone = (UV.y < 0.25 && UV.x < 0.75) ? 1.0 : 0.0;
	float zeit = TIME * bewegung;
	// Nebel: 2 Oktaven Value-Noise über die Objekt-Position, langsam
	// driftend — pseudo-triplanar gemischt wie im Flaum-Shader.
	vec2 drift = vec2(zeit * drift_tempo, zeit * drift_tempo * 0.6);
	float grob = wert_rauschen(obj_pos.xy * nebel_skala + drift);
	float quer = wert_rauschen(obj_pos.zy * nebel_skala - drift + vec2(11.3, 4.7));
	float nebel = 0.65 * grob + 0.35 * quer;
	vec3 nebel_ton = mix(nebel_farbe_a, nebel_farbe_b, nebel);
	vec3 galaxie = mix(basis, nebel_ton, nebel_staerke * nebel);
	// Sterne: zwei gefaltete Ebenen, damit keine Streifen entstehen.
	vec2 sp = obj_pos.xy * stern_dichte + vec2(obj_pos.z * 7.3, obj_pos.z * 3.1);
	vec2 sq = obj_pos.zy * stern_dichte * 0.8 + vec2(obj_pos.x * 5.1, 13.7);
	float sterne = max(sternfeld(sp, zeit * funkel_tempo), sternfeld(sq, zeit * funkel_tempo + 2.4));
	ALBEDO = mix(basis, galaxie, zone);
	// Sterne leuchten selbst (auch im Schatten sichtbar) + ein Hauch
	// Nebel-Glimmer, damit das dunkle Fell nicht absäuft.
	EMISSION = (stern_farbe * sterne + nebel_ton * 0.08) * zone;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
