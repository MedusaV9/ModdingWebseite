class_name RanchEntdeckerKarte
extends RefCounted
## Entdecker-Karten-Modell der Ranch (W19) — PURE + headless-testbar.
## Baut aus RanchKarte (Zonen/Wege/Bach), RanchEntdeckungen (Fundorte) und
## dem Save (RanchWeltState: bereiste Zonen, `funde`) das komplette
## 2D-Datenmodell für den Karten-Screen: Fog-Zustände, „NEU“-Badges
## (Erst-Ansehen, additiver Unterschlüssel `karteGesehen` in `ranch.welt` —
## unbekannte Unterschlüssel überleben normalize_welt verbatim, geheilt
## wird beim LESEN, Muster RanchEntdeckungen.funde) und die
## „Dahin!“-Richtungshinweise. KEIN Szenen-Code hier — der Screen
## (RanchKarteScreen) ist nur Verdrahtung.

## Unterschlüssel in `ranch.welt`: Fundort-Ids, die auf der Karte schon
## einmal angesehen wurden (danach kein „NEU“-Badge mehr).
const GESEHEN_KEY := "karteGesehen"

## Raster für die GROBE Position unentdeckter Orte („?“-Pin als Hinweis,
## nie die exakte Stelle) — Quantisierung auf Zellmitten, deterministisch.
const GROB_RASTER_M := 180.0

## Fog-Fläche unentdeckter Zonen (grau-beiger „Nebel“).
const FOG_FARBE := Color("#E4DFD6")

## Pastell-Farben je Zonen-Stimmung (Gooby-Look; Welt-Farben wie
## RanchTerrain/RanchZonenDeko — UI-Chrome bleibt bei AcTokens).
const STIMMUNG_FARBEN := {
	"heimat": Color("#F2D8A7"),
	"weite": Color("#CDE8B5"),
	"schatten": Color("#A8CBA0"),
	"ruhe": Color("#BFE3EF"),
	"panorama": Color("#DCEAC2"),
	"frisch": Color("#C6E7E2"),
	"geheimnis": Color("#D9C7E8"),
	"fest": Color("#F7CBD8"),
	"dorf": Color("#F3D9C0"),
	"gipfel": Color("#E3E7F2"),
	"duft": Color("#E5D3F0"),
	"nebel": Color("#D3DAD8"),
	"sage": Color("#E8DAC4"),
	"ferien": Color("#FBE6C2"),
	"ernte": Color("#F5CFA8"),
	"gold": Color("#F3E3A9"),
}

## Kompass-Sektoren im Uhrzeigersinn ab Norden (rkarte.richtung.*).
const RICHTUNGEN: Array[String] = ["n", "no", "o", "so", "s", "sw", "w", "nw"]


## Das komplette Karten-Modell für den Screen (eine Abfrage pro Aufbau).
static func modell(gs: Object) -> Dictionary:
	var bereist := RanchWeltState.entdeckte_zonen(gs)
	return {
		"grenzen": RanchKarte.grenzen(),
		"zonen": zonen_modell(bereist),
		"wege": wege_modell(bereist),
		"fundorte": fundorte_modell(gs),
		"bach": bach_punkte(),
		"fortschritt": fortschritt(gs),
	}


## Zonen mit Fog-Zustand: bereiste Zonen farbig (Stimmungs-Pastell),
## unbereiste als Nebel-Silhouette. Wasser-Kreise (See/Bergsee/Bucht)
## kommen mit, damit der Screen sie zeichnen kann.
static func zonen_modell(bereist: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for zone: Dictionary in RanchKarte.zonen():
		var id := str(zone["id"])
		(
			out
			. append(
				{
					"id": id,
					"name_key": str(zone["name_key"]),
					"rect": RanchKarte.zone_rect(zone),
					"farbe": zonen_farbe(str(zone.get("stimmung", ""))),
					"entdeckt": bereist.has(id),
					"wasser": _wasser_kreise(zone),
				}
			)
		)
	return out


## Wege als 2D-Punktlisten; „bekannt“ sobald eine der beiden Zonen bereist
## ist (der Weg ins Unbekannte bleibt als zarter Hinweis sichtbar).
static func wege_modell(bereist: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for weg: Dictionary in RanchKarte.wege():
		var von := str(weg["von"])
		var nach := str(weg["nach"])
		var punkte: Array[Vector2] = []
		for paar: Array in weg["punkte"]:
			punkte.append(Vector2(float(paar[0]), float(paar[1])))
		(
			out
			. append(
				{
					"von": von,
					"nach": nach,
					"punkte": punkte,
					"bekannt": bereist.has(von) or bereist.has(nach),
				}
			)
		)
	return out


## Alle 16 Fundorte mit Fog-Zustand: entdeckte an ihrer echten Position,
## unentdeckte als „?“-Pin an GROBER Rasterposition (Hinweis, kein Spoiler).
static func fundorte_modell(gs: Object) -> Array[Dictionary]:
	var gefunden := RanchEntdeckungen.gefunden(gs)
	var neu := neue_funde(gs)
	var out: Array[Dictionary] = []
	for eintrag: Dictionary in RanchEntdeckungen.alle_orte():
		var id := str(eintrag["id"])
		var pos := RanchEntdeckungen.position_von(eintrag)
		var entdeckt := gefunden.has(id)
		(
			out
			. append(
				{
					"id": id,
					"name_key": str(eintrag["name_key"]),
					"pos": pos,
					"zeig_pos": pos if entdeckt else grobe_position(pos),
					"entdeckt": entdeckt,
					"neu": neu.has(id),
					"muenzen": maxi(0, int(eintrag.get("muenzen", 0))),
				}
			)
		)
	return out


## Bachlauf als 2D-Punktliste (blaue Linie auf der Karte).
static func bach_punkte() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for paar: Array in RanchKarte.karte()["bach"]["punkte"]:
		out.append(Vector2(float(paar[0]), float(paar[1])))
	return out


## Fortschritts-Kopf: „n/16 Orte entdeckt · m/16 Zonen bereist“ —
## Gesamtzahlen IMMER aus den Daten, nie hartkodiert.
static func fortschritt(gs: Object) -> Dictionary:
	return {
		"zonen": RanchWeltState.entdeckte_zonen(gs).size(),
		"zonen_gesamt": RanchKarte.zonen().size(),
		"funde": RanchEntdeckungen.gefunden(gs).size(),
		"funde_gesamt": RanchEntdeckungen.alle_orte().size(),
	}


## Pastell-Farbe einer Zonen-Stimmung (Fallback: Weide-Grün).
static func zonen_farbe(stimmung: String) -> Color:
	return STIMMUNG_FARBEN.get(stimmung, STIMMUNG_FARBEN["weite"])


## Grobe Rasterposition (Zellmitte) — deterministisch, in den Weltgrenzen.
static func grobe_position(pos: Vector2) -> Vector2:
	var grob := (pos / GROB_RASTER_M).floor() * GROB_RASTER_M
	grob += Vector2.ONE * (GROB_RASTER_M / 2.0)
	var grenzen := RanchKarte.grenzen().grow(-GROB_RASTER_M / 4.0)
	return grob.clamp(grenzen.position, grenzen.end)


## Kompass-Richtung von → nach ("" bei identischen Punkten). Welt: +x =
## Osten, +z = Süden — 0° = Norden, im Uhrzeigersinn.
static func richtung_key(von: Vector2, nach: Vector2) -> String:
	var d := nach - von
	if d.length() < 1.0:
		return ""
	var winkel := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
	return RICHTUNGEN[int(roundf(winkel / 45.0)) % RICHTUNGEN.size()]


## Zone an (oder am nächsten bei) einer Weltposition — für den
## „Dahin!“-Hinweis („… nahe Wäldchen“).
static func hinweis_zone(pos: Vector2) -> String:
	var direkt := RanchKarte.zone_bei(Vector3(pos.x, 0.0, pos.y))
	if not direkt.is_empty():
		return direkt
	var best := ""
	var best_d := INF
	for zone: Dictionary in RanchKarte.zonen():
		var rect := RanchKarte.zone_rect(zone)
		var d := pos.distance_to(pos.clamp(rect.position, rect.end))
		if d < best_d:
			best_d = d
			best = str(zone["id"])
	return best


## Startpunkt der „Dahin!“-Richtung: der Hof-Spawn (Zuhause der Ranch).
static func heimat_punkt() -> Vector2:
	var hof := RanchKarte.zone("hof")
	if hof.is_empty():
		return Vector2.ZERO
	var spawn: Array = hof["spawn"]
	return Vector2(float(spawn[0]), float(spawn[1]))


## ------------------------------------------------- „NEU“-Badge (Save)


## Auf der Karte bereits angesehene Fundort-Ids (geheilt beim Lesen).
static func gesehene_funde(gs: Object) -> Array[String]:
	var out: Array[String] = []
	if gs == null:
		return out
	var welt: Dictionary = RanchWeltState.welt_daten(gs)
	var roh: Variant = welt.get(GESEHEN_KEY)
	if roh is Array:
		for eintrag: Variant in roh:
			var id := str(eintrag)
			if not out.has(id) and not RanchEntdeckungen.fundort(id).is_empty():
				out.append(id)
	return out


## Entdeckt, aber noch nie auf der Karte angesehen → „NEU“-Badge.
static func neue_funde(gs: Object) -> Array[String]:
	var gesehen := gesehene_funde(gs)
	var out: Array[String] = []
	for id: String in RanchEntdeckungen.gefunden(gs):
		if not gesehen.has(id):
			out.append(id)
	return out


## Fundorte als angesehen markieren (idempotent, genau-einmal im Save).
static func markiere_funde_gesehen(gs: Object, ids: Array) -> void:
	if gs == null or ids.is_empty():
		return
	var gesehen := gesehene_funde(gs)
	var geaendert := false
	for eintrag: Variant in ids:
		var id := str(eintrag)
		if RanchEntdeckungen.fundort(id).is_empty() or gesehen.has(id):
			continue
		gesehen.append(id)
		geaendert = true
	if not geaendert:
		return
	var welt: Dictionary = RanchWeltState.welt_daten(gs)
	welt[GESEHEN_KEY] = gesehen
	gs.set_value(RanchWeltState.WELT_KEY, welt)


## ------------------------------------------------------------------ intern


## Wasser-Kreise einer Zone (See/Bergsee/Bucht) als {mitte, radius} —
## kleine handgezeichnete Akzente auf der Karte.
static func _wasser_kreise(zone: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for praefix: String in ["see", "bergsee", "bucht"]:
		var mitte: Variant = zone.get("%s_mitte" % praefix)
		var radius: Variant = zone.get("%s_radius" % praefix)
		if mitte is Array and (mitte as Array).size() >= 2 and radius != null:
			(
				out
				. append(
					{
						"mitte": Vector2(float(mitte[0]), float(mitte[1])),
						"radius": float(radius),
					}
				)
			)
	return out


## --------------------------------------------------------- Integrität


## Modell-Integrität (leere Liste = alles gut): jede Zone hat Name-Key +
## bekannte Stimmung, jeder Fundort liegt (echt UND grob) in den Grenzen
## und hat einen Beschreibungs-Key-tauglichen Namen.
static func probleme() -> Array[String]:
	var out: Array[String] = []
	var grenzen := RanchKarte.grenzen()
	for zone: Dictionary in RanchKarte.zonen():
		if str(zone.get("name_key", "")).is_empty():
			out.append("Zone %s ohne name_key" % zone.get("id"))
		if not STIMMUNG_FARBEN.has(str(zone.get("stimmung", ""))):
			out.append("Zone %s ohne Karten-Farbe (Stimmung?)" % zone.get("id"))
	for eintrag: Dictionary in RanchEntdeckungen.alle_orte():
		var pos := RanchEntdeckungen.position_von(eintrag)
		if not grenzen.has_point(pos):
			out.append("Fundort %s liegt außerhalb der Karte" % eintrag.get("id"))
		if not grenzen.has_point(grobe_position(pos)):
			out.append("Grobe Position von %s liegt außerhalb" % eintrag.get("id"))
	return out
