// GOOBY-Himmel (FB-2): prozeduraler Sky-Shader für alle Welten — weiche
// Pastell-Verläufe, Sonnenscheibe mit Glow, Wolkenbänder aus Value-Noise,
// Sternfeld für die Nacht. Alle Stimmungen entstehen NUR über Uniforms
// (HimmelStimmungen mischt auf der CPU) — dadurch blendet jede Tageszeit/
// Wetterlage stufenlos, ohne Panorama-Texturen (0 Textur-Speicher, wichtig
// fürs Mobile-Budget). Sonnenrichtung kommt aus LIGHT0 (DirectionalLight).
shader_type sky;

uniform vec4 zenit_farbe : source_color = vec4(0.48, 0.67, 0.90, 1.0);
uniform vec4 horizont_farbe : source_color = vec4(0.80, 0.89, 0.97, 1.0);
uniform vec4 boden_farbe : source_color = vec4(0.62, 0.74, 0.58, 1.0);
uniform float dunst_staerke : hint_range(0.0, 1.0) = 0.25;
uniform vec4 sonnen_farbe : source_color = vec4(1.0, 0.96, 0.85, 1.0);
uniform float sonnen_groesse : hint_range(0.0, 0.2) = 0.035;
uniform float sonnen_glow : hint_range(0.0, 1.0) = 0.35;
uniform vec4 wolken_farbe : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wolken_menge : hint_range(0.0, 1.0) = 0.2;
uniform float wolken_tempo = 0.006;
uniform float sterne_staerke : hint_range(0.0, 1.0) = 0.0;

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

// Zwei Oktaven reichen für weiche Pastell-Wolkenbänder (Mobil-Kosten).
float wolken_noise(vec2 p) {
	return 0.65 * wert_rauschen(p) + 0.35 * wert_rauschen(p * 2.3 + 17.7);
}

void sky() {
	float y = EYEDIR.y;
	// Himmelsverlauf: Horizontband (Dunst) -> Zenit.
	float t = clamp(y, 0.0, 1.0);
	float verlauf = pow(t, mix(0.85, 0.45, dunst_staerke));
	vec3 farbe = mix(horizont_farbe.rgb, zenit_farbe.rgb, verlauf);
	// Unter dem Horizont: weicher Übergang in die Bodenfarbe.
	float unten = smoothstep(0.0, -0.06, y);
	farbe = mix(farbe, boden_farbe.rgb, unten);
	// Sonne: Scheibe + weiter Glow, Richtung aus dem DirectionalLight.
	if (LIGHT0_ENABLED) {
		float cosang = dot(EYEDIR, LIGHT0_DIRECTION);
		float rand_innen = cos(sonnen_groesse);
		float rand_aussen = cos(sonnen_groesse * 1.6 + 0.001);
		float scheibe = smoothstep(rand_aussen, rand_innen, cosang);
		float glow = pow(max(cosang, 0.0), 5.0) * sonnen_glow;
		farbe += sonnen_farbe.rgb * (scheibe + glow) * (1.0 - unten);
	}
	// Sternfeld: Punktgitter auf der Himmelskuppel, leichtes Funkeln.
	if (sterne_staerke > 0.001 && y > 0.02) {
		vec2 sp = EYEDIR.xz / (y + 0.35) * 36.0;
		vec2 zelle = floor(sp);
		vec2 innen = fract(sp) - 0.5;
		float h = hash21(zelle);
		vec2 versatz = vec2(hash21(zelle + 3.1), hash21(zelle + 7.7)) - 0.5;
		float d = length(innen - versatz * 0.7);
		float stern = smoothstep(0.09, 0.01, d) * step(0.72, h);
		float funkeln = 0.75 + 0.25 * sin(TIME * (1.0 + h * 3.0) + h * 40.0);
		farbe += vec3(1.0, 0.98, 0.92) * stern * funkeln * sterne_staerke * smoothstep(0.02, 0.25, y);
	}
	// Wolkenbänder: Noise auf der Himmels-Ebene, zum Horizont ausblendend.
	if (wolken_menge > 0.001 && y > 0.015) {
		vec2 wp = EYEDIR.xz / (y + 0.22) * 1.35;
		wp += vec2(TIME * wolken_tempo, TIME * wolken_tempo * 0.35);
		float n = wolken_noise(wp * 2.0);
		float schwelle = 1.0 - wolken_menge * 0.95;
		float deckung = smoothstep(schwelle, schwelle + 0.28, n);
		deckung *= smoothstep(0.015, 0.16, y);
		farbe = mix(farbe, wolken_farbe.rgb, deckung * wolken_farbe.a);
	}
	COLOR = farbe;
}
