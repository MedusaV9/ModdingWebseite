class_name McGoobyState
extends RefCounted
## McGooby-Slice-Anbindung ans GameState (Welle A+B) — via FROZEN Slice-Registry,
## Muster RanchState/CityState. Alle Funktionen static, `gs` = Duck-Typing
## (`/root/GameState` oder Test-Double mit get_value/set_value). ADDITIV:
## neuer Slice `mcgooby` über register_slice, KEIN Save-Version-Bump
## (Doc §10.1: additive Unterschlüssel mit normalize-Self-Heal).
##
## Slice-Struktur:
##   mcgooby.v,
##   mcgooby.introGesehen (bool — Eröffnungs-Hook-Karte lief, Doc §1.3),
##   mcgooby.schichten { gespielt (int), bestwert (int Punkte) }.
## Welle B (G6/MCGOOBY-B) ADDITIV:
##   mcgooby.gekauft / gekauftAm / angebotGesehen / angebotVerschoben
##     (Kauf-Gate, Doc §6.2 — atomar gebucht über McGoobyKauf),
##   mcgooby.buehne { auftritte (int) } (Maskottchen-Bühne, 1×/Schicht).

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "mcgooby"

static var _registered := false


## Registriert den mcgooby-Slice (idempotent, VOR GameState.initialize()).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {
		"v": 1,
		"introGesehen": false,
		"gekauft": false,
		"gekauftAm": 0,
		"angebotGesehen": false,
		"angebotVerschoben": false,
		"schichten": {"gespielt": 0, "bestwert": 0},
		"buehne": {"auftritte": 0},
	}


## Self-Heal: Typen reparieren, gültige Daten VERBATIM erhalten (Muster
## RanchState.normalize_slice — Alt-Saves ohne Slice bekommen Defaults,
## Welle-A-Saves bekommen die Welle-B-Schlüssel dazu).
static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else default_slice()
	slice["v"] = maxi(1, int(slice.get("v", 1)))
	slice["introGesehen"] = bool(slice.get("introGesehen", false))
	slice["gekauft"] = bool(slice.get("gekauft", false))
	slice["gekauftAm"] = maxi(0, int(slice.get("gekauftAm", 0)))
	slice["angebotGesehen"] = bool(slice.get("angebotGesehen", false))
	slice["angebotVerschoben"] = bool(slice.get("angebotVerschoben", false))
	var schichten: Dictionary = (
		slice.get("schichten") if slice.get("schichten") is Dictionary else {}
	)
	schichten["gespielt"] = maxi(0, int(schichten.get("gespielt", 0)))
	schichten["bestwert"] = maxi(0, int(schichten.get("bestwert", 0)))
	slice["schichten"] = schichten
	var buehne: Dictionary = slice.get("buehne") if slice.get("buehne") is Dictionary else {}
	buehne["auftritte"] = maxi(0, int(buehne.get("auftritte", 0)))
	slice["buehne"] = buehne
	return slice


## Eröffnungs-Hook schon gesehen? (Erststart-Erkennung der Schicht-Szene.)
static func ist_intro_gesehen(gs: Object) -> bool:
	return gs != null and bool(gs.get_value("mcgooby.introGesehen", false))


static func setze_intro_gesehen(gs: Object) -> void:
	if gs != null:
		gs.set_value("mcgooby.introGesehen", true)


## Laden gekauft? (Kauf-Gate Welle B — die Probeschicht bleibt davor frei.)
static func ist_gekauft(gs: Object) -> bool:
	return gs != null and bool(gs.get_value("mcgooby.gekauft", false))


## Kauf-Level-Gate (Doc §6.2): gilt NUR für den Kauf, nie für die Demo.
static func ist_freigeschaltet(gs: Object) -> bool:
	if gs == null:
		return false
	var level := int(gs.get_value("progression.level", 1))
	return level >= McGoobyKatalog.freischalt_level()


## „Später kaufen“: Angebot gesehen + verschoben merken (Muster GoobyeState).
static func angebot_verschieben(gs: Object) -> void:
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var mcgooby := ensure_mcgooby(state)
			mcgooby["angebotGesehen"] = true
			mcgooby["angebotVerschoben"] = true
	)
	_notify(gs)


## Angebot als gesehen markieren (ohne verschieben).
static func angebot_gesehen(gs: Object) -> void:
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var mcgooby := ensure_mcgooby(state)
			mcgooby["angebotGesehen"] = true
	)
	_notify(gs)


## Schicht verbuchen: Zähler hoch, Bestwert = Maximum (nie runter).
static func schicht_verbuchen(gs: Object, punkte: int) -> void:
	if gs == null:
		return
	var gespielt := int(gs.get_value("mcgooby.schichten.gespielt", 0))
	gs.set_value("mcgooby.schichten.gespielt", gespielt + 1)
	var bestwert := int(gs.get_value("mcgooby.schichten.bestwert", 0))
	gs.set_value("mcgooby.schichten.bestwert", maxi(bestwert, maxi(0, punkte)))


## Bühnen-Auftritt verbuchen (Welle B: Statistik fürs spätere Sticker-Set).
static func buehne_verbuchen(gs: Object) -> void:
	if gs == null:
		return
	var auftritte := int(gs.get_value("mcgooby.buehne.auftritte", 0))
	gs.set_value("mcgooby.buehne.auftritte", auftritte + 1)


## Ensure-Muster (random_events.gd): fehlende Schlüssel im update-Block
## anlegen/heilen — robust, auch wenn der Slice erst NACH initialize()
## registriert wurde (Alt-Saves, isolierte Tests). Für atomare Buchungen
## (McGoobyKauf) gedacht.
static func ensure_mcgooby(state: Dictionary) -> Dictionary:
	state[SLICE_ID] = normalize_slice(state.get(SLICE_ID))
	return state[SLICE_ID]


static func reset_for_tests() -> void:
	_registered = false


## Slice-Änderung melden, wenn der GameState das Signal kennt (Duck-Typing:
## leichte Test-Doubles haben kein notify_slice_changed).
static func _notify(gs: Object) -> void:
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed(SLICE_ID)
