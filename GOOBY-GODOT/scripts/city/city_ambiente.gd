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
