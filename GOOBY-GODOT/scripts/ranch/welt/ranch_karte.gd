class_name RanchKarte
extends RefCounted
## Karten-API der zusammenhängenden Ranch-Region (RW-1) — PURE, datengetrieben
## aus `res://scripts/ranch/welt/ranch_karte.json`. DIE eine Quelle für Zonen,
## Wege, Spawn-Punkte, Begehbarkeit und Bodenhöhe; andere Agents fragen
## Positionen HIER ab (Vertrag: /tmp/gooby-godot/handoffs/RW1-welt-api.md).
##
## Koordinaten: Region-Weltkoordinaten in Metern, deckungsgleich mit dem
## bestehenden Hof-Plan (RanchWelt.hof_plan — Hof-Zone liegt am Ursprung).
## Höhe kommt aus RanchGelaende; `punkt(x, z)` liefert fertige Vector3.

const KARTE_PFAD := "res://scripts/ranch/welt/ranch_karte.json"

## Radius, in dem Furt/Brücke das Wasser begehbar machen.
const QUERUNG_RADIUS_M := 14.0

static var _cache: Dictionary = {}


## Rohdaten der Karte (einmal geladen, dann gecacht). Tests können mit
## `reset_for_tests()` neu laden.
static func karte() -> Dictionary:
	if _cache.is_empty():
		_cache = _lade()
	return _cache


static func reset_for_tests() -> void:
	_cache = {}


## Welt-Seed (deterministische Streuung/Wetter-Basis).
static func seed_wert() -> int:
	return int(karte()["seed"])


## Begehbare Weltgrenzen als Rect2 (x/z).
static func grenzen() -> Rect2:
	var g: Dictionary = karte()["grenzen"]
	return Rect2(
		float(g["min_x"]),
		float(g["min_z"]),
		float(g["max_x"]) - float(g["min_x"]),
		float(g["max_z"]) - float(g["min_z"])
	)


## ------------------------------------------------------------------ Zonen


static func zonen() -> Array:
	return karte()["zonen"]


static func zonen_ids() -> Array[String]:
	var ids: Array[String] = []
	for zone: Dictionary in zonen():
		ids.append(str(zone["id"]))
	return ids


## Zonen-Daten zu einer Id ({} wenn unbekannt).
static func zone(id: String) -> Dictionary:
	for eintrag: Dictionary in zonen():
		if str(eintrag["id"]) == id:
			return eintrag
	return {}


## Zonen-Rect (x/z) aus dem Karten-Array [min_x, min_z, breite, tiefe].
static func zone_rect(zone_daten: Dictionary) -> Rect2:
	var r: Array = zone_daten["rect"]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


## In welcher Zone liegt die Position? "" = freies Land zwischen den Zonen.
static func zone_bei(pos: Vector3) -> String:
	var p := Vector2(pos.x, pos.z)
	for eintrag: Dictionary in zonen():
		if zone_rect(eintrag).has_point(p):
			return str(eintrag["id"])
	return ""


## Spawn-Punkt einer Zone (auf Bodenhöhe; Vector3.ZERO wenn unbekannt).
static func spawn_punkt(zone_id: String) -> Vector3:
	var daten := zone(zone_id)
	if daten.is_empty():
		return Vector3.ZERO
	var s: Array = daten["spawn"]
	return punkt(float(s[0]), float(s[1]))


## ------------------------------------------------------------------- Wege


static func wege() -> Array:
	return karte()["wege"]


## Wegpunkte zwischen zwei Zonen (auf Bodenhöhe), in Laufrichtung von →
## nach. Auch die Gegenrichtung wird gefunden; [] wenn kein direkter Weg.
static func wegpunkte(von_zone: String, nach_zone: String) -> Array[Vector3]:
	for weg: Dictionary in wege():
		var von := str(weg["von"])
		var nach := str(weg["nach"])
		if von == von_zone and nach == nach_zone:
			return _als_punkte(weg["punkte"], false)
		if von == nach_zone and nach == von_zone:
			return _als_punkte(weg["punkte"], true)
	return []


## Direkt verbundene Nachbar-Zonen.
static func nachbarn(zone_id: String) -> Array[String]:
	var out: Array[String] = []
	for weg: Dictionary in wege():
		if str(weg["von"]) == zone_id:
			out.append(str(weg["nach"]))
		elif str(weg["nach"]) == zone_id:
			out.append(str(weg["von"]))
	return out


## ------------------------------------------------------------- Abfragen


## Fertiger Weltpunkt auf Bodenhöhe.
static func punkt(x: float, z: float) -> Vector3:
	return Vector3(x, RanchGelaende.hoehe(x, z), z)


## Bodenhöhe an (x, z) — Kurzform für RanchGelaende.hoehe.
static func hoehe(x: float, z: float) -> float:
	return RanchGelaende.hoehe(x, z)


## Ist die Position für Reiter/Tiere begehbar? Blockiert sind: außerhalb
## der Grenzen und tiefes Wasser (See/Bach) — AUSSER im Querungs-Radius
## von Furt und Brücke.
static func ist_begehbar(pos: Vector3) -> bool:
	var p := Vector2(pos.x, pos.z)
	if not grenzen().has_point(p):
		return false
	if not RanchGelaende.ist_wasser(pos.x, pos.z):
		return true
	var bach: Dictionary = karte()["bach"]
	for querung: String in ["furt", "bruecke"]:
		var q: Array = bach[querung]
		if p.distance_to(Vector2(float(q[0]), float(q[1]))) <= QUERUNG_RADIUS_M:
			return true
	return false


## --------------------------------------------------------- Integrität


## Karten-Integrität (leere Liste = alles gut): Pflichtzonen vorhanden,
## Zonen disjunkt + in den Grenzen, Spawns begehbar in ihrer Zone, Wege
## verbinden ihre Zonen mit begehbaren Punkten, Bach/Furt/Brücke gesetzt.
static func probleme() -> Array[String]:
	var out: Array[String] = []
	_pruefe_zonen(out)
	_pruefe_wege(out)
	_pruefe_bach(out)
	return out


static func _pruefe_zonen(out: Array[String]) -> void:
	var pflicht: Array[String] = [
		"hof",
		"weidetal",
		"waeldchen",
		"see",
		"huegelkamm",
		"bachlauf",
		"scheune_alt",
		"turnierplatz",
		"hufingen",
	]
	var ids := zonen_ids()
	for zone_id: String in pflicht:
		if not ids.has(zone_id):
			out.append("Pflichtzone fehlt: %s" % zone_id)
	var rects: Array[Rect2] = []
	var welt := grenzen()
	for eintrag: Dictionary in zonen():
		var rect := zone_rect(eintrag)
		if not welt.encloses(rect):
			out.append("Zone %s ragt aus der Welt" % eintrag["id"])
		for andere in rects:
			if rect.intersects(andere):
				out.append("Zone %s überlappt eine andere" % eintrag["id"])
		rects.append(rect)
		var spawn := spawn_punkt(str(eintrag["id"]))
		if not zone_rect(eintrag).has_point(Vector2(spawn.x, spawn.z)):
			out.append("Spawn von %s liegt außerhalb der Zone" % eintrag["id"])
		if not ist_begehbar(spawn):
			out.append("Spawn von %s ist nicht begehbar" % eintrag["id"])


static func _pruefe_wege(out: Array[String]) -> void:
	for weg: Dictionary in wege():
		var von := zone(str(weg["von"]))
		var nach := zone(str(weg["nach"]))
		if von.is_empty() or nach.is_empty():
			out.append("Weg %s verbindet unbekannte Zonen" % weg["id"])
			continue
		var punkte: Array[Vector3] = _als_punkte(weg["punkte"], false)
		if punkte.size() < 2:
			out.append("Weg %s hat zu wenige Punkte" % weg["id"])
			continue
		var erster := punkte[0]
		var letzter := punkte[punkte.size() - 1]
		if not zone_rect(von).has_point(Vector2(erster.x, erster.z)):
			out.append("Weg %s startet nicht in %s" % [weg["id"], weg["von"]])
		if not zone_rect(nach).has_point(Vector2(letzter.x, letzter.z)):
			out.append("Weg %s endet nicht in %s" % [weg["id"], weg["nach"]])
		for p in punkte:
			if not ist_begehbar(p):
				out.append("Wegpunkt (%.0f, %.0f) auf %s blockiert" % [p.x, p.z, weg["id"]])


static func _pruefe_bach(out: Array[String]) -> void:
	var bach: Dictionary = karte()["bach"]
	if (bach["punkte"] as Array).size() < 3:
		out.append("Bach braucht mindestens 3 Punkte")
	for querung: String in ["furt", "bruecke"]:
		var q: Array = bach[querung]
		var pos := punkt(float(q[0]), float(q[1]))
		if not ist_begehbar(pos):
			out.append("Bach-Querung %s ist nicht begehbar" % querung)


## ------------------------------------------------------------------ intern


static func _als_punkte(roh: Array, umgekehrt: bool) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for paar: Array in roh:
		out.append(punkt(float(paar[0]), float(paar[1])))
	if umgekehrt:
		out.reverse()
	return out


static func _lade() -> Dictionary:
	var text := FileAccess.get_file_as_string(KARTE_PFAD)
	var daten: Variant = JSON.parse_string(text)
	if daten is Dictionary:
		return daten
	push_error("ranch_karte.json ist nicht lesbar — leere Karte.")
	return {
		"version": 1,
		"seed": 0,
		"wasser_hoehe": RanchGelaende.WASSER_HOEHE,
		"grenzen": {"min_x": -100.0, "max_x": 100.0, "min_z": -100.0, "max_z": 100.0},
		"zonen": [],
		"wege": [],
		"bach": {"breite": 6.0, "tiefe": 1.0, "punkte": [], "furt": [0, 0], "bruecke": [0, 0]},
		"pfuetzen": [],
	}
