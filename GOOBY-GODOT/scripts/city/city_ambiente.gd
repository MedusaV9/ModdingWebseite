class_name CityAmbiente
extends RefCounted
## Tag/Nacht-Lichtkurve + Ambient-Regeln der Stadt (W4-P3 POLISH-8, Doc E
## §1.4). PURE + headless-testbar — CityScene wendet das Profil auf
## Environment/Sonne/Laternen/Autolichter an. Ambient-SFX (Hupe/Vogel)
## werden hier nur GEPLANT; abgespielt wird über den AudioDirector von
## W4-P1 (Fallback ohne Autoload: leiser Verzicht).

## Laternen/Autolichter gehen in der Dämmerung an, nicht erst bei Nacht.
const LICHTER_AN_UNTER := 0.55

## Ambient-SFX-Planung: zufällige Pausen zwischen Hupe/Vogel-Momenten.
const SFX_PAUSE_MIN_S := 18.0
const SFX_PAUSE_MAX_S := 45.0

## Beinahe-Unfall (M3-Vorgriff „Hupe-Reaktionen/Near-Miss“): so nah darf ein
## Verkehrs-Gooby am Spielerauto vorbei, bevor er hupt …
const NEAR_MISS_M := 7.0
## … und so schnell muss der Spieler dabei mindestens sein (m/s).
const NEAR_MISS_TEMPO := 4.0
## Sperrzeit nach einer Hupe (s) — sonst hupt der ganze Block im Chor.
const NEAR_MISS_PAUSE_S := 4.0

## Geteilter Glow-Verlauf aller Ladenschilder (s. glow_textur()).
static var _glow_tex: GradientTexture2D = null


## Tageslicht 0..1 über die Uhrzeit (weiche Rampen morgens/abends).
static func tageslicht(stunde: float) -> float:
	var s := fposmod(stunde, 24.0)
	var auf := smoothstep(5.5, 8.0, s)
	var ab := 1.0 - smoothstep(18.0, 20.5, s)
	return clampf(minf(auf, ab), 0.0, 1.0)


static func ist_nacht(stunde: float) -> bool:
	return tageslicht(stunde) < 0.5


## Laternen + Autolichter an? (Dämmerung zählt schon.)
static func lichter_an(stunde: float) -> bool:
	return tageslicht(stunde) < LICHTER_AN_UNTER


## Komplettes Licht-Profil der Stadt zur Stunde (0..24, Bruchteile ok).
static func licht_profil(stunde: float) -> Dictionary:
	var licht := tageslicht(stunde)
	var nacht := 1.0 - licht
	var t := clampf((fposmod(stunde, 24.0) - 6.0) / 12.0, 0.0, 1.0)
	# Tag: Sonnenhöhe folgt der Uhrzeit; Nacht: Mond steht fest und fahl.
	var elevation := lerpf(34.0, lerpf(15.0, 55.0, sin(t * PI)), licht)
	var tag_farbe := Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.75, 0.55), absf(t - 0.5) * 2.0)
	var mond_farbe := Color(0.6, 0.68, 0.92)
	return {
		"sonnen_energie": lerpf(0.12, 1.0, licht),
		"sonnen_farbe": tag_farbe.lerp(mond_farbe, nacht),
		"elevation": elevation,
		"ambient_energie": lerpf(0.4, 1.1, licht),
		"himmel_oben": Color(0.35, 0.55, 0.85).lerp(Color(0.04, 0.06, 0.14), nacht),
		"himmel_horizont": Color(0.72, 0.83, 0.95).lerp(Color(0.12, 0.14, 0.26), nacht),
		"boden_horizont": Color(0.71, 0.82, 0.62).lerp(Color(0.1, 0.12, 0.18), nacht),
		"boden_unten": Color(0.46, 0.6, 0.4).lerp(Color(0.06, 0.08, 0.12), nacht),
		"lichter_an": lichter_an(stunde),
		"ist_nacht": ist_nacht(stunde),
	}


## Nächste Ambient-SFX-Pause in Sekunden (roll = injizierter Zufall 0..1).
static func sfx_pause_s(roll: float) -> float:
	return lerpf(SFX_PAUSE_MIN_S, SFX_PAUSE_MAX_S, clampf(roll, 0.0, 1.0))


## Welcher Ambient-SFX passt zur Stunde? Vögel nur am Tag, Hupen immer
## (roll = injizierter Zufall 0..1). Rückgabe: "vogel" | "hupe".
static func sfx_wahl(stunde: float, roll: float) -> String:
	if ist_nacht(stunde):
		return "hupe"
	return "vogel" if roll < 0.6 else "hupe"


## Schrift-/Leuchtfarbe der Ladenschilder: tagsüber Theme-Tinte, nachts das
## warme Neon über der Markise (W4-P3-Ambiente „Glow bei Ladenschildern“).
static func schild_farbe(lichter_an: bool) -> Color:
	return Color(1.0, 0.94, 0.76) if lichter_an else AcTokens.INK


## Beinahe-Unfall? Ein Verkehrs-Gooby hupt nur, wenn er wirklich knapp dran
## war UND der Spieler in Fahrt ist — Schrittgeschwindigkeit ist kein Drama.
static func ist_beinahe(abstand_m: float, tempo: float) -> bool:
	return abstand_m <= NEAR_MISS_M and absf(tempo) >= NEAR_MISS_TEMPO


## Warmes Emissiv-Material für Laternen-Birnen/Autolichter (unshaded, damit
## es auch ohne Glow-Postprocess nachts „leuchtet“).
static func leuchten_material(farbe: Color, energie := 1.6) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = farbe
	mat.emission_enabled = true
	mat.emission = farbe
	mat.emission_energy_multiplier = energie
	return mat


## Weicher radialer Alpha-Verlauf, EINMAL gebaut und von allen Schildern
## geteilt — der Ersatz für einen Fullscreen-Glow-Pass (mobil-Budget).
static func glow_textur() -> GradientTexture2D:
	if _glow_tex == null:
		var verlauf := Gradient.new()
		verlauf.set_offset(0, 0.0)
		verlauf.set_color(0, Color(1, 1, 1, 1))
		verlauf.set_offset(1, 1.0)
		verlauf.set_color(1, Color(1, 1, 1, 0))
		verlauf.add_point(0.45, Color(1, 1, 1, 0.72))
		var tex := GradientTexture2D.new()
		tex.gradient = verlauf
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex = tex
	return _glow_tex


## Material der Leucht-Tafel hinter einem Ladenschild: unshaded, radial
## ausblendend und OHNE Tiefenschreiben, damit die Schrift davor sauber
## bleibt (sonst z-fightet der Billboard-Quad mit dem Label3D).
static func schild_glow_material(farbe: Color) -> StandardMaterial3D:
	var mat := leuchten_material(farbe, 1.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = glow_textur()
	mat.emission_texture = glow_textur()
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.render_priority = -1
	return mat
