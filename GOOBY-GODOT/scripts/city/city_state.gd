class_name CityState
extends RefCounted
## City-Slice-Anbindung (W3a CITY) ans GameState (W1d) — via Slice-Registry
## (W1d-Handoff §2). Alle Funktionen static, `gs` = Duck-Typing
## (`/root/GameState` oder Test-Instanz), Muster = W2a HomeState.
##
## Slice-Struktur:
##   city.v, city.flags{} (z. B. rezept_tropfen — Arzt-Rezept, Doc E §2.4),
##   city.taxi{} (TaxiLogic-Slice, Timestamps, Doc E §4),
##   city.gooberando{} (GooberandoLogic-Slice, Doc E §5),
##   city.autoTile [r, c] (letzte Parkposition in der Stadt, [] = zuhause).

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "city"
const FLAG_REZEPT := "rezept_tropfen"

static var _registered := false


## Registriert den city-Slice (idempotent, VOR GameState.initialize()).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {
		"v": 1,
		"flags": {},
		"taxi": TaxiLogic.default_slice(),
		"gooberando": GooberandoLogic.default_slice(),
		"autoTile": [],
	}


## Self-Heal: Typen reparieren, gültige Daten VERBATIM erhalten.
static func normalize_slice(raw: Variant) -> Dictionary:
	var city: Dictionary = raw if raw is Dictionary else default_slice()
	city["v"] = maxi(1, int(city.get("v", 1)))
	if not (city.get("flags") is Dictionary):
		city["flags"] = {}
	city["taxi"] = TaxiLogic.normalize_slice(city.get("taxi"))
	city["gooberando"] = GooberandoLogic.normalize_slice(city.get("gooberando"))
	if not (city.get("autoTile") is Array):
		city["autoTile"] = []
	return city


static func flag(gs: Object, name: String) -> bool:
	return bool(gs.get_value("city.flags.%s" % name, false))


static func set_flag(gs: Object, name: String, value: bool) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var flags: Dictionary = state[SLICE_ID].get("flags", {})
			if value:
				flags[name] = true
			else:
				flags.erase(name)
			state[SLICE_ID]["flags"] = flags
	)
	gs.notify_slice_changed(SLICE_ID)


static func taxi_slice(gs: Object) -> Dictionary:
	return TaxiLogic.normalize_slice(gs.get_value("city.taxi", {}))


static func save_taxi_slice(gs: Object, taxi: Dictionary) -> void:
	gs.set_value("city.taxi", taxi)
	gs.notify_slice_changed(SLICE_ID)


static func gooberando_slice(gs: Object) -> Dictionary:
	return GooberandoLogic.normalize_slice(gs.get_value("city.gooberando", {}))


static func save_gooberando_slice(gs: Object, goob: Dictionary) -> void:
	gs.set_value("city.gooberando", goob)
	gs.notify_slice_changed(SLICE_ID)


## Nur für Tests: Registry-Status zurücksetzen.
static func reset_for_tests() -> void:
	_registered = false
