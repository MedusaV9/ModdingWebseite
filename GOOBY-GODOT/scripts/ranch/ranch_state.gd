class_name RanchState
extends RefCounted
## Ranch-Slice-Anbindung (RANCH-1, Gooby-Ranch-DLC) ans GameState (W1d) —
## via Slice-Registry (W1d-Handoff §2), Muster = W3a CityState. Alle
## Funktionen static, `gs` = Duck-Typing (`/root/GameState` oder
## Test-Instanz). ADDITIV: neuer Slice `ranch` über register_slice,
## KEIN Save-Version-Bump.
##
## Slice-Struktur (Absprache mit RANCH-2, s. RANCH2-needs.md §1 — die
## Unterschlüssel `tiere`/`wirtschaft`/`spiele` gehören RANCH-2 und
## delegieren an RanchPlaySlices, damit es EINE Wahrheit gibt):
##   ranch.v,
##   ranch.gekauft (bool) + ranch.gekauftAm (ms, 0 = nie),
##   ranch.angebotGesehen (bool — das Angebot nach dem Rückblick lief),
##   ranch.angebotVerschoben (bool — „Später kaufen“ gedrückt),
##   ranch.hoftiere [] ({id, art, name_key, farbe} — Kühe/Schafe/Hühner
##     fürs Weltbild, kommen mit dem Kauf aus dem Content-Pack),
##   ranch.ausbau {stall, koppel, reitplatz} (Welt-Ausbaustufen, Start 1),
##   ranch.tiere {pferde, stall, lastTickAt} (RANCH-2: Pflege/Reiten),
##   ranch.wirtschaft / ranch.spiele (RANCH-2: Lager/Gear/Minispiele).

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const RanchPlaySlices := preload("res://scripts/ranch/data/ranch_play_slices.gd")

const SLICE_ID := "ranch"

static var _registered := false


## Registriert den ranch-Slice (idempotent, VOR GameState.initialize()).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {
		"v": 1,
		"gekauft": false,
		"gekauftAm": 0,
		"angebotGesehen": false,
		"angebotVerschoben": false,
		"hoftiere": [],
		"ausbau": {"stall": 1, "koppel": 1, "reitplatz": 1},
		"tiere": RanchPlaySlices.default_tiere(),
		"wirtschaft": RanchPlaySlices.default_wirtschaft(),
		"spiele": RanchPlaySlices.default_spiele(),
	}


## Self-Heal: Typen reparieren, gültige Daten VERBATIM erhalten (Muster
## CityState.normalize_slice — Alt-Saves ohne den Slice bekommen Defaults).
## RANCH-2-Unterschlüssel heilen deren eigene normalize-Funktionen.
static func normalize_slice(raw: Variant) -> Dictionary:
	var ranch: Dictionary = raw if raw is Dictionary else default_slice()
	ranch["v"] = maxi(1, int(ranch.get("v", 1)))
	ranch["gekauft"] = bool(ranch.get("gekauft", false))
	ranch["gekauftAm"] = maxi(0, int(ranch.get("gekauftAm", 0)))
	ranch["angebotGesehen"] = bool(ranch.get("angebotGesehen", false))
	ranch["angebotVerschoben"] = bool(ranch.get("angebotVerschoben", false))
	if not (ranch.get("hoftiere") is Array):
		ranch["hoftiere"] = []
	var ausbau: Variant = ranch.get("ausbau")
	if not (ausbau is Dictionary):
		ausbau = {}
	for stufe: String in ["stall", "koppel", "reitplatz"]:
		ausbau[stufe] = maxi(1, int(ausbau.get(stufe, 1)))
	ranch["ausbau"] = ausbau
	ranch["tiere"] = RanchPlaySlices.normalize_tiere(ranch.get("tiere"))
	ranch["wirtschaft"] = RanchPlaySlices.normalize_wirtschaft(ranch.get("wirtschaft"))
	ranch["spiele"] = RanchPlaySlices.normalize_spiele(ranch.get("spiele"))
	return ranch


## Ranch gekauft?
static func ist_gekauft(gs: Object) -> bool:
	return gs != null and bool(gs.get_value("ranch.gekauft", false))


## Level-Gate: ab diesem Level ist die Ranch freigeschaltet (Pack-Daten,
## Default 15 — RanchKatalog.freischalt_level).
static func ist_freigeschaltet(gs: Object) -> bool:
	if gs == null:
		return false
	var level := int(gs.get_value("progression.level", 1))
	return level >= RanchKatalog.freischalt_level()


## „Später kaufen“: Angebot gesehen + verschoben merken (bleibt über den
## Stadtausfahrt-Hinweis und RanchOffer.zeige erreichbar).
static func angebot_verschieben(gs: Object) -> void:
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var ranch: Dictionary = state[SLICE_ID]
			ranch["angebotGesehen"] = true
			ranch["angebotVerschoben"] = true
	)
	gs.notify_slice_changed(SLICE_ID)


## Angebot als gesehen markieren (ohne verschieben — „Jetzt losfahren“).
static func angebot_gesehen(gs: Object) -> void:
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var ranch: Dictionary = state[SLICE_ID]
			ranch["angebotGesehen"] = true
	)
	gs.notify_slice_changed(SLICE_ID)


## Hof-Tiere fürs Weltbild (Kühe/Schafe/Hühner; leer vor dem Kauf).
static func hoftiere(gs: Object) -> Array:
	if gs == null:
		return []
	var raw: Variant = gs.get_value("ranch.hoftiere", [])
	return raw if raw is Array else []


## Pferde-Bestand (RANCH-2-Struktur `ranch.tiere.pferde`: id → Pferd).
static func pferde(gs: Object) -> Dictionary:
	if gs == null:
		return {}
	var raw: Variant = gs.get_value("ranch.tiere.pferde", {})
	return raw if raw is Dictionary else {}


## Ausbaustufe einer Anlage (stall/koppel/reitplatz, Start 1).
static func ausbau_stufe(gs: Object, anlage: String) -> int:
	if gs == null:
		return 1
	return maxi(1, int(gs.get_value("ranch.ausbau.%s" % anlage, 1)))


## Nur für Tests: Registry-Status zurücksetzen.
static func reset_for_tests() -> void:
	_registered = false
