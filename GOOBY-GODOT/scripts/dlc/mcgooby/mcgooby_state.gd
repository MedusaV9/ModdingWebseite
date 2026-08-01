class_name McGoobyState
extends RefCounted
## McGooby-Slice-Anbindung ans GameState (Welle A) — via FROZEN Slice-Registry,
## Muster RanchState/CityState. Alle Funktionen static, `gs` = Duck-Typing
## (`/root/GameState` oder Test-Double mit get_value/set_value). ADDITIV:
## neuer Slice `mcgooby` über register_slice, KEIN Save-Version-Bump
## (Doc §10.1: additive Unterschlüssel mit normalize-Self-Heal).
##
## Slice-Struktur Welle A (bewusst klein — Besitz/Menü/Team kommen mit dem
## Kauf-Gate späterer Wellen):
##   mcgooby.v,
##   mcgooby.introGesehen (bool — Eröffnungs-Hook-Karte lief, Doc §1.3),
##   mcgooby.schichten { gespielt (int), bestwert (int Punkte) }.

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
		"schichten": {"gespielt": 0, "bestwert": 0},
	}


## Self-Heal: Typen reparieren, gültige Daten VERBATIM erhalten (Muster
## RanchState.normalize_slice — Alt-Saves ohne Slice bekommen Defaults).
static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else default_slice()
	slice["v"] = maxi(1, int(slice.get("v", 1)))
	slice["introGesehen"] = bool(slice.get("introGesehen", false))
	var schichten: Dictionary = (
		slice.get("schichten") if slice.get("schichten") is Dictionary else {}
	)
	schichten["gespielt"] = maxi(0, int(schichten.get("gespielt", 0)))
	schichten["bestwert"] = maxi(0, int(schichten.get("bestwert", 0)))
	slice["schichten"] = schichten
	return slice


## Eröffnungs-Hook schon gesehen? (Erststart-Erkennung der Schicht-Szene.)
static func ist_intro_gesehen(gs: Object) -> bool:
	return gs != null and bool(gs.get_value("mcgooby.introGesehen", false))


static func setze_intro_gesehen(gs: Object) -> void:
	if gs != null:
		gs.set_value("mcgooby.introGesehen", true)


## Schicht verbuchen: Zähler hoch, Bestwert = Maximum (nie runter).
static func schicht_verbuchen(gs: Object, punkte: int) -> void:
	if gs == null:
		return
	var gespielt := int(gs.get_value("mcgooby.schichten.gespielt", 0))
	gs.set_value("mcgooby.schichten.gespielt", gespielt + 1)
	var bestwert := int(gs.get_value("mcgooby.schichten.bestwert", 0))
	gs.set_value("mcgooby.schichten.bestwert", maxi(bestwert, maxi(0, punkte)))


static func reset_for_tests() -> void:
	_registered = false
