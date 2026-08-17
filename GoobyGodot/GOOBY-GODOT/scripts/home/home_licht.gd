class_name HomeLicht
extends RefCounted
## Raum-Licht-Profile (W4-P3 POLISH-6, Doc A §6/§7): pro Raum ein
## abgestimmtes, warmes Licht-Setup + Tageszeit-Lerp. PURE + headless-testbar
## — RoomBase wendet das Profil auf Environment/Lichter an. Schatten kommen
## NICHT von der Sonne (teuer auf Mobile): Gooby kriegt einen Blob-Shadow
## (GoobyHome), Möbel bleiben im weichen Ambient.

## Grunddaten pro Raum: Stimmung über Ambient-/Sonnen-/Füll-Farben.
## Werte bewusst unter 1.0 halten — die Wände (#FFF6EC) überstrahlen sonst
## (Vorher-Artefakt: ausgewaschene Wände bei ambient 0.4 + sun 0.7).
## `kontext` = Exposure-Kontext der GLOBALEN Kette (LichtKalibrierung) —
## das Bad läuft wegen der Weiß-auf-Weiß-Palette über „innen_kuehl“.
const RAUM_PROFILE := {
	"living":
	{
		"ambient_farbe": Color(1.0, 0.93, 0.84),
		"sonnen_farbe": Color(1.0, 0.9, 0.74),
		"fuell_farbe": Color(1.0, 0.85, 0.62),
		"hintergrund": Color(0.98, 0.92, 0.83),
		"waerme": 1.0,
		"kontext": "innen",
	},
	"kitchen":
	{
		"ambient_farbe": Color(1.0, 0.96, 0.88),
		"sonnen_farbe": Color(1.0, 0.95, 0.84),
		"fuell_farbe": Color(1.0, 0.92, 0.72),
		"hintergrund": Color(0.99, 0.95, 0.87),
		"waerme": 0.85,
		"kontext": "innen",
	},
	"bathroom":
	{
		"ambient_farbe": Color(0.9, 0.97, 1.0),
		"sonnen_farbe": Color(0.95, 0.99, 1.0),
		"fuell_farbe": Color(0.85, 0.95, 1.0),
		"hintergrund": Color(0.9, 0.96, 0.99),
		"waerme": 0.35,
		"kontext": "innen_kuehl",
	},
	"bedroom":
	{
		"ambient_farbe": Color(1.0, 0.89, 0.86),
		"sonnen_farbe": Color(1.0, 0.86, 0.76),
		"fuell_farbe": Color(1.0, 0.8, 0.68),
		"hintergrund": Color(0.97, 0.9, 0.87),
		"waerme": 1.0,
		"kontext": "innen",
	},
	"garden":
	{
		"ambient_farbe": Color(0.92, 0.97, 1.0),
		"sonnen_farbe": Color(1.0, 0.98, 0.9),
		"fuell_farbe": Color(0.95, 1.0, 0.9),
		"hintergrund": Color(0.75, 0.89, 0.95),
		"waerme": 0.5,
		"kontext": "draussen",
	},
}

## W13/WETTER-FX: Blitz-Flash durchs Fenster (Dioramen) — Dauer und
## kühle Blitzfarbe zentral, damit alle Fenster gleich flackern.
const BLITZ_DAUER_S := 0.22
const BLITZ_FARBE := Color(0.95, 0.96, 1.0)

## Basis-Energien (Tag, drinnen) — folgen dem GLOBALEN Energie-Budget der
## Belichtungskette (LichtKalibrierung, EVAL-2026-08 Lens B Befund 6).
const AMBIENT_TAG := LichtKalibrierung.BUDGET_AMBIENT_TAG
const SONNE_TAG := LichtKalibrierung.BUDGET_SONNE_TAG
const FUELL_TAG := LichtKalibrierung.BUDGET_FUELL_TAG
const NACHT_FAKTOR_INNEN := 0.72
const FENSTER_TAG := 0.8
const FENSTER_NACHT := 0.12


## Tageslicht 0..1 über die Uhrzeit (weiche Rampen morgens/abends).
static func tageslicht(stunde: float) -> float:
	var s := fposmod(stunde, 24.0)
	var auf := smoothstep(5.5, 8.5, s)
	var ab := 1.0 - smoothstep(17.5, 20.5, s)
	return clampf(minf(auf, ab), 0.0, 1.0)


## W13/WETTER-FX: Abkling-Kurve des Fenster-Blitzes (PURE) — 1.0 beim
## Zünden, linear auf 0 über BLITZ_DAUER_S. Die Dioramen treiben damit die
## Deckung ihrer Flash-Tafel.
static func blitz_faktor(rest_s: float, dauer_s := BLITZ_DAUER_S) -> float:
	if dauer_s <= 0.0:
		return 0.0
	return clampf(rest_s / dauer_s, 0.0, 1.0)


## Sonnenhöhe in Grad über die Uhrzeit (für draußen; Nacht = Mondstand).
static func sonnen_elevation(stunde: float) -> float:
	var licht := tageslicht(stunde)
	if licht <= 0.0:
		return 34.0
	var t := clampf((fposmod(stunde, 24.0) - 6.0) / 12.0, 0.0, 1.0)
	return lerpf(14.0, 55.0, sin(t * PI))


## Komplettes Licht-Profil eines Raums zur Stunde (0..24, Bruchteile ok).
static func profil(room_id: String, outdoor: bool, stunde: float) -> Dictionary:
	var basis: Dictionary = RAUM_PROFILE.get(room_id, RAUM_PROFILE["living"])
	var licht := tageslicht(stunde)
	if outdoor:
		return _profil_draussen(basis, stunde, licht)
	return _profil_drinnen(basis, licht)


static func _profil_drinnen(basis: Dictionary, licht: float) -> Dictionary:
	# Drinnen bleibt es IMMER gemütlich hell (Spielbarkeit) — nachts wird
	# es nur wärmer/gedimmter, die Füll-Lampe übernimmt das Wohngefühl.
	var nacht := 1.0 - licht
	var faktor := lerpf(1.0, NACHT_FAKTOR_INNEN, nacht)
	var abendton := Color(1.0, 0.87, 0.7)
	return {
		"hintergrund": (basis["hintergrund"] as Color).darkened(nacht * 0.22),
		"ambient_farbe": (basis["ambient_farbe"] as Color).lerp(abendton, nacht * 0.5),
		"ambient_energie": AMBIENT_TAG * faktor,
		"sonnen_farbe": (basis["sonnen_farbe"] as Color).lerp(abendton, nacht * 0.6),
		"sonnen_energie": SONNE_TAG * faktor,
		"sonnen_rotation": Vector3(-52.0, -28.0, 0.0),
		"fuell_farbe": basis["fuell_farbe"],
		"fuell_energie": FUELL_TAG * lerpf(1.0, 1.7, nacht),
		"fenster_energie": lerpf(FENSTER_NACHT, FENSTER_TAG, licht),
		"kontext": str(basis.get("kontext", "innen")),
	}


static func _profil_draussen(basis: Dictionary, stunde: float, licht: float) -> Dictionary:
	var nacht := 1.0 - licht
	var t := clampf((fposmod(stunde, 24.0) - 6.0) / 12.0, 0.0, 1.0)
	var daemmerton := Color(1.0, 0.76, 0.56)
	var tag_farbe := (basis["sonnen_farbe"] as Color).lerp(daemmerton, absf(t - 0.5) * 2.0)
	var mond_farbe := Color(0.62, 0.7, 0.92)
	var nacht_himmel := Color(0.09, 0.11, 0.2)
	return {
		"hintergrund": (basis["hintergrund"] as Color).lerp(nacht_himmel, nacht),
		"ambient_farbe": (basis["ambient_farbe"] as Color).lerp(Color(0.45, 0.52, 0.72), nacht),
		"ambient_energie":
		lerpf(0.18, LichtKalibrierung.BUDGET_DRAUSSEN_AMBIENT_TAG, licht) + nacht * 0.08,
		"sonnen_farbe": tag_farbe.lerp(mond_farbe, nacht),
		"sonnen_energie": lerpf(0.16, LichtKalibrierung.BUDGET_DRAUSSEN_SONNE_TAG, licht),
		"sonnen_rotation": Vector3(-sonnen_elevation(stunde), -28.0, 0.0),
		"fuell_farbe": basis["fuell_farbe"],
		"fuell_energie": lerpf(0.22, 0.12, licht),
		"fenster_energie": lerpf(FENSTER_NACHT, FENSTER_TAG, licht),
		"kontext": str(basis.get("kontext", "draussen")),
	}
