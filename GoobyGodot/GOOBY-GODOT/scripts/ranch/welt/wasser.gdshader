// Wasser-Shader (VIS-1, Trailer-Review „Seen wirken wie flache blaue
// Kreise"): prozedurale Wellen (Sinus-Summen, KEINE Texturen/SSR — mobil-
// tauglich), Tiefenfarbverlauf über den Ufer-Anteil (Scheiben: UV.x radial
// 0=Mitte..1=Rand, Bach-Band: UV.x quer), wabernder Schaumsaum am Ufer,
// Glanz über niedrige Roughness + animierte Normale. `regen` (vom
// RanchWetterController) kräuselt die Fläche und streut Tropfen-Flecken.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec4 farbe_tief : source_color = vec4(0.09, 0.29, 0.42, 0.94);
uniform vec4 farbe_flach : source_color = vec4(0.4, 0.72, 0.74, 0.62);
uniform vec4 schaum_farbe : source_color = vec4(0.96, 1.0, 1.0, 0.85);
uniform float welle_staerke : hint_range(0.0, 2.0) = 1.0;
// Bach: schnellere Phase (fließt), Ufer-Anteil quer statt radial.
uniform float fliess_tempo : hint_range(0.0, 4.0) = 0.0;
uniform float band_modus : hint_range(0.0, 1.0) = 0.0;
uniform float regen : hint_range(0.0, 1.0) = 0.0;

varying vec3 welt;
varying float rand_anteil;

float wellen_hoehe(vec2 p, float t) {
	float h = sin(p.x * 0.5 + p.y * 0.21 + t * 1.1) * 0.5;
	h += sin(p.y * 0.43 - p.x * 0.17 - t * 0.9) * 0.5;
	h += sin(p.x * 1.1 + p.y * 0.7 + t * 1.6) * sin(p.y * 0.9 - p.x * 0.4 - t * 1.2) * 0.3;
	h += sin(p.x * 2.9 - t * 2.2) * sin(p.y * 2.5 + t * 1.8) * 0.12;
	return h;
}

void vertex() {
	welt = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Scheiben tragen den Ufer-Anteil (aus ECHTER Wassertiefe gebacken)
	// in COLOR.r; das Bach-Band misst quer über UV.x.
	rand_anteil = band_modus > 0.5 ? abs(UV.x * 2.0 - 1.0) : COLOR.r;
	// Am Ufer bleibt die Kante ruhig (kein Spalt zur Böschung).
	float frei = 1.0 - smoothstep(0.75, 0.98, rand_anteil);
	VERTEX.y += wellen_hoehe(welt.xz, TIME) * 0.04 * welle_staerke * frei;
}

void fragment() {
	float t = TIME * (1.0 + fliess_tempo * 0.5);
	vec2 p = welt.xz;
	float e = 0.35;
	float h0 = wellen_hoehe(p, t);
	float hx = wellen_hoehe(p + vec2(e, 0.0), t);
	float hz = wellen_hoehe(p + vec2(0.0, e), t);
	// Moiré-Bremse: Kräusel + Glitzer blenden mit der Sichtdistanz aus.
	float fern = clamp(1.0 - (length(VERTEX) - 30.0) / 120.0, 0.12, 1.0);
	float kraus = (0.32 + 0.28 * welle_staerke) * (1.0 + regen * 1.7) * fern;
	vec3 n_welt = normalize(vec3((h0 - hx) * kraus, 1.0, (h0 - hz) * kraus));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_welt, 0.0)).xyz);
	vec4 farbe = mix(farbe_tief, farbe_flach, smoothstep(0.35, 0.97, rand_anteil));
	float saum = rand_anteil + 0.03 * sin(p.x * 1.9 + t * 1.4) + 0.03 * sin(p.y * 2.3 - t * 1.1);
	float schaum = smoothstep(0.9, 0.975, saum);
	// Flache Bänke: Schaum in Wirbel-Schlieren auflösen statt Vollweiß.
	float wirbel = 0.5 + 0.5 * sin(p.x * 0.8 + t * 0.7) * sin(p.y * 1.05 - t * 0.5);
	schaum *= 0.5 + 0.5 * wirbel;
	float glitzer = smoothstep(0.86, 1.0, sin(p.x * 2.9 + t * 1.8) * sin(p.y * 3.3 - t * 1.5));
	float tropfen = regen * smoothstep(0.9, 1.0, sin(p.x * 9.1 + t * 9.0) * sin(p.y * 8.3 - t * 7.0));
	float weiss = clamp(schaum + (glitzer * 0.16 + tropfen * 0.5) * fern, 0.0, 1.0);
	ALBEDO = mix(farbe.rgb, schaum_farbe.rgb, weiss);
	ALPHA = clamp(mix(farbe.a, schaum_farbe.a, schaum), 0.0, 1.0);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.07, 0.4, schaum);
	SPECULAR = 0.62;
	RIM = 0.18;
}
