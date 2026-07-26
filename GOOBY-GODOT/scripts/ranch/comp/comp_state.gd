class_name RanchCompState
extends RefCounted
## Save-Anbindung der Wettbewerbe (RW-5) — ADDITIV im bestehenden
## `ranch`-Slice unter `ranch.comp`, KEIN Version-Bump. Fremde Schlüssel
## überleben RanchState/RanchPlaySlices.normalize verbatim; dieses Modul
## heilt seine Daten deshalb beim LESEN (Self-Heal-Muster RanchWeltState).
##
## Struktur:
##   ranch.comp = {
##     v, klasse,                       # Liga-Klasse (steigt NUR)
##     punkte: {holz: int, ...},        # Liga-Punkte je Klasse
##     schleifen: {"springen_holz": 1}, # bester Platz (1..3) je Disz×Klasse
##     trophaeen: ["pokal_holz", ...],  # Ranch-Trophäen (einmalig)
##     teilnahmen, siege,               # Karriere-Zähler
##     geister: {disz: {b64, wert, zeit_s, datum, pferd}},   # bester Lauf
##     arcade: {spiel: {stars: {k1..}, best: {}, cleared: {}}},
##   }

const Katalog := preload("res://scripts/ranch/comp/comp_katalog.gd")

const KEY := "ranch.comp"
const ARCADE_SPIELE: Array[String] = ["tonnen", "zeit"]
const ARCADE_LEVEL := 10


static func default_comp() -> Dictionary:
	var punkte := {}
	for klasse in Katalog.KLASSEN:
		punkte[klasse] = 0
	return {
		"v": 1,
		"klasse": "holz",
		"punkte": punkte,
		"schleifen": {},
		"trophaeen": [],
		"teilnahmen": 0,
		"siege": 0,
		"geister": {},
		"arcade": _default_arcade(),
	}


## Geheilte Comp-Daten aus dem Save (gs = GameState oder Test-Double).
static func lese(gs: Object) -> Dictionary:
	if gs == null:
		return default_comp()
	return normalize(gs.get_value(KEY, null))


static func schreibe(gs: Object, comp: Dictionary) -> void:
	if gs != null:
		gs.set_value(KEY, comp)


## Self-Heal: Typen reparieren, Klasse validieren, nichts verlieren.
static func normalize(raw: Variant) -> Dictionary:
	var comp: Dictionary = raw.duplicate(true) if raw is Dictionary else default_comp()
	comp["v"] = maxi(1, int(_num(comp.get("v"), 1.0)))
	if not Katalog.KLASSEN.has(str(comp.get("klasse", ""))):
		comp["klasse"] = "holz"
	var punkte_roh: Dictionary = comp.get("punkte") if comp.get("punkte") is Dictionary else {}
	var punkte := {}
	for klasse in Katalog.KLASSEN:
		punkte[klasse] = maxi(0, int(_num(punkte_roh.get(klasse), 0.0)))
	comp["punkte"] = punkte
	var schleifen_roh: Dictionary = (
		comp.get("schleifen") if comp.get("schleifen") is Dictionary else {}
	)
	var schleifen := {}
	for key: Variant in schleifen_roh.keys():
		var platz := int(_num(schleifen_roh[key], 0.0))
		if platz >= 1 and platz <= 3:
			schleifen[str(key)] = platz
	comp["schleifen"] = schleifen
	var trophaeen: Array = comp.get("trophaeen") if comp.get("trophaeen") is Array else []
	var sauber: Array = []
	for id: Variant in trophaeen:
		if id is String and not sauber.has(id):
			sauber.append(id)
	comp["trophaeen"] = sauber
	comp["teilnahmen"] = maxi(0, int(_num(comp.get("teilnahmen"), 0.0)))
	comp["siege"] = maxi(0, int(_num(comp.get("siege"), 0.0)))
	comp["geister"] = _normalize_geister(comp.get("geister"))
	comp["arcade"] = _normalize_arcade(comp.get("arcade"))
	return comp


## ---------------------------------------------------------- Geisterläufe


## Bester eigener Lauf einer Disziplin ({} = noch keiner).
static func geist(gs: Object, disziplin: String) -> Dictionary:
	var geister: Dictionary = lese(gs).get("geister", {})
	return geister.get(disziplin, {}) if geister.get(disziplin) is Dictionary else {}


## Geist NUR speichern, wenn der Lauf besser ist (zeit_gewinnt beachtet).
## true = neuer Bestlauf gespeichert.
static func geist_speichern(
	gs: Object, disziplin: String, eintrag: Dictionary, zeit_gewinnt: bool
) -> bool:
	if gs == null or str(eintrag.get("b64", "")) == "":
		return false
	var alt := geist(gs, disziplin)
	if not alt.is_empty():
		var alt_wert := _num(alt.get("wert"), 0.0)
		var neu_wert := _num(eintrag.get("wert"), 0.0)
		var besser := neu_wert < alt_wert if zeit_gewinnt else neu_wert > alt_wert
		if not besser:
			return false
	var comp := lese(gs)
	(comp["geister"] as Dictionary)[disziplin] = {
		"b64": str(eintrag.get("b64", "")),
		"wert": _num(eintrag.get("wert"), 0.0),
		"zeit_s": _num(eintrag.get("zeit_s"), 0.0),
		"datum": str(eintrag.get("datum", "")),
		"pferd": str(eintrag.get("pferd", "")),
	}
	schreibe(gs, comp)
	return true


## ------------------------------------------------------- Arcade-Progress


## Fortschritt der RW-5-Arcade-Spiele (ranchTonnen/ranchZeit) — eigener
## Speicher unter ranch.comp.arcade (RanchSpieleProgress-Form, aber ohne
## fremde Schlüssel anzufassen).
static func arcade_stars(gs: Object, spiel: String, level_id: int) -> int:
	return int(_num(_arcade_feld(gs, spiel, "stars").get("k%d" % level_id), 0.0))


static func arcade_best(gs: Object, spiel: String, level_id: int) -> int:
	return int(_num(_arcade_feld(gs, spiel, "best").get("k%d" % level_id), 0.0))


static func arcade_cleared(gs: Object, spiel: String, level_id: int) -> bool:
	return bool(_arcade_feld(gs, spiel, "cleared").get("k%d" % level_id, false))


## Höchstes spielbares Level (alles bis zum ersten offenen; 1 immer offen).
static func arcade_max_unlocked(gs: Object, spiel: String) -> int:
	for id in range(1, ARCADE_LEVEL + 1):
		if not arcade_cleared(gs, spiel, id):
			return id
	return ARCADE_LEVEL


## Sieg verbuchen (Sterne/Best nur verbessern). best_kleiner = Zeitspiele.
## → {"first_clear": bool, "new_best": bool}.
static func arcade_win(
	gs: Object, spiel: String, level_id: int, stars: int, score: int, best_kleiner := false
) -> Dictionary:
	var first := not arcade_cleared(gs, spiel, level_id)
	var best_alt := arcade_best(gs, spiel, level_id)
	var new_best := score < best_alt if best_kleiner and best_alt > 0 else score > best_alt
	if gs == null:
		return {"first_clear": false, "new_best": false}
	var comp := lese(gs)
	var eintrag: Dictionary = (comp["arcade"] as Dictionary)[spiel]
	var key := "k%d" % level_id
	(eintrag["cleared"] as Dictionary)[key] = true
	(eintrag["stars"] as Dictionary)[key] = maxi(arcade_stars(gs, spiel, level_id), stars)
	if new_best or best_alt == 0:
		(eintrag["best"] as Dictionary)[key] = score
	schreibe(gs, comp)
	return {"first_clear": first, "new_best": new_best}


## ---------------------------------------------------------------- intern


static func _default_arcade() -> Dictionary:
	var arcade := {}
	for spiel in ARCADE_SPIELE:
		arcade[spiel] = {"stars": {}, "best": {}, "cleared": {}}
	return arcade


static func _normalize_arcade(raw: Variant) -> Dictionary:
	var arcade: Dictionary = raw if raw is Dictionary else {}
	for spiel in ARCADE_SPIELE:
		var eintrag: Dictionary = arcade.get(spiel) if arcade.get(spiel) is Dictionary else {}
		for feld in ["stars", "best", "cleared"]:
			if not (eintrag.get(feld) is Dictionary):
				eintrag[feld] = {}
		arcade[spiel] = eintrag
	return arcade


static func _normalize_geister(raw: Variant) -> Dictionary:
	var geister: Dictionary = raw if raw is Dictionary else {}
	var sauber := {}
	for disziplin: Variant in geister.keys():
		var eintrag: Variant = geister[disziplin]
		if not (eintrag is Dictionary):
			continue
		# Erlaubt: Turnier-Disziplinen + Arcade-Zeitrennen ("zeit_k<N>" je Lauf).
		if not Katalog.DISZIPLINEN.has(str(disziplin)) and not str(disziplin).begins_with("zeit"):
			continue
		if str((eintrag as Dictionary).get("b64", "")) == "":
			continue
		sauber[str(disziplin)] = eintrag
	return sauber


static func _arcade_feld(gs: Object, spiel: String, feld: String) -> Dictionary:
	var arcade: Dictionary = lese(gs).get("arcade", {})
	var eintrag: Dictionary = arcade.get(spiel) if arcade.get(spiel) is Dictionary else {}
	return eintrag.get(feld) if eintrag.get(feld) is Dictionary else {}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
