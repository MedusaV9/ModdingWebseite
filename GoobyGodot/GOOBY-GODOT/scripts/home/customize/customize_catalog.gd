class_name CustomizeCatalog
extends RefCounted
## Katalog des Gestalten-Modus (HAUS-CUSTOM, User-Wunsch: „Man soll alles,
## also auch den Haus-Stil, Farbe und Gras/Boden etc. anpassen können").
## Lädt `data/wall_floor_catalog.json` (Tapeten/Böden je Raum) und
## `data/house_styles.json` (Haus-Außenstil + Grundstück) — statisch,
## gecacht, headless-testbar. Preise sind DATEN: verkauft wird im
## IKEA-/Baumarkt-Screen anderer Agents über `HouseStyleState.kaufen`.
##
## Jede kaufbare Kategorie heißt hier „Art": wand, boden, dachForm,
## hausnummer, briefkasten, vordach, grundBoden, weg, zaun. Freie
## Farbflächen (nur Palette, kein Kauf) sind fassade/dach/tuer/fenster.

const WALLFLOOR_PATH := "res://scripts/home/data/wall_floor_catalog.json"
const HOUSE_PATH := "res://scripts/home/data/house_styles.json"

## Alle kaufbaren Arten (Reihenfolge = Anzeige-Reihenfolge im Screen).
const OPTION_ARTEN: Array[String] = [
	"wand",
	"boden",
	"dachForm",
	"hausnummer",
	"briefkasten",
	"vordach",
	"grundBoden",
	"weg",
	"zaun",
]
## Bereiche, in denen NUR eine Farbe gewählt wird (immer im Besitz).
const FARB_BEREICHE: Array[String] = ["fassade", "dach", "tuer", "fenster"]

static var _wallfloor: Dictionary = {}
static var _house: Dictionary = {}
static var _default_ids: Dictionary = {}
static var _loaded := false


## Optionsliste einer Art (Dictionaries mit id/name_de/name_en/preis/farben).
static func optionen(art: String) -> Array:
	_ensure_loaded()
	match art:
		"wand":
			return _wallfloor.get("waende", [])
		"boden":
			return _wallfloor.get("boeden", [])
		"dachForm":
			return _house.get("dach", {}).get("formen", [])
		"hausnummer":
			return _house.get("hausnummer", [])
		"briefkasten":
			return _house.get("briefkasten", [])
		"vordach":
			return _house.get("vordach", [])
		"grundBoden":
			return _house.get("grundstueck", {}).get("boeden", [])
		"weg":
			return _house.get("grundstueck", {}).get("wege", [])
		"zaun":
			return _house.get("grundstueck", {}).get("zaeune", [])
	return []


static func ids(art: String) -> Array:
	var out: Array = []
	for entry: Dictionary in optionen(art):
		out.append(str(entry.get("id", "")))
	return out


## Def einer Option ({} = unbekannt — nie ein Absturz).
static func def(art: String, id: String) -> Dictionary:
	for entry: Dictionary in optionen(art):
		if str(entry.get("id", "")) == id:
			return entry
	return {}


static func preis(art: String, id: String) -> int:
	return maxi(0, int(def(art, id).get("preis", 0)))


## Farbvarianten einer Option (Palette-IDs, s. CustomizeMaterials.PALETTE).
static func farben(art: String, id: String) -> Array:
	var raw: Variant = def(art, id).get("farben", [])
	return raw if raw is Array else []


## Freie Farbwahl eines Bereichs (fassade/dach/tuer/fenster).
static func farb_wahl(bereich: String) -> Array:
	_ensure_loaded()
	var raw: Variant = _house.get(bereich, {})
	if raw is Dictionary:
		var farben_raw: Variant = (raw as Dictionary).get("farben", [])
		return farben_raw if farben_raw is Array else []
	return []


## Standard-Außenstil (fehlende Save-Werte fallen hierauf zurück).
static func default_haus() -> Dictionary:
	_ensure_loaded()
	var out: Dictionary = _house.get("defaults", {}).get("haus", {}).duplicate(true)
	# JSON-Zahlen sind Floats — die Zahl kanonisch als int (wie normalize).
	out["hausnummerZahl"] = int(out.get("hausnummerZahl", 5))
	return out


static func default_grundstueck() -> Dictionary:
	_ensure_loaded()
	return _house.get("defaults", {}).get("grundstueck", {}).duplicate(true)


## Standard-Wand/-Boden eines Raums (angelehnt an die rooms.json-Farben,
## damit Alt-Stände unverändert aussehen). Unbekannte Räume → Basis-Raum.
static func raum_default(room_id: String) -> Dictionary:
	_ensure_loaded()
	var defaults: Dictionary = _house.get("defaults", {})
	var raeume: Dictionary = defaults.get("raeume", {})
	var raw: Variant = raeume.get(room_id, defaults.get("raum", {}))
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


## Ist die Option Teil des Start-Looks (Haus-/Grundstücks-/Raum-Defaults)?
## Solche Optionen gelten IMMER als gekauft: der Startzustand eines Spielstands
## muss ohne Münzen wieder herstellbar sein (Migration + „Zurücksetzen").
static func ist_default(art: String, id: String) -> bool:
	_ensure_loaded()
	if _default_ids.is_empty():
		_sammle_default_ids()
	return (_default_ids.get(art, []) as Array).has(id)


## Anzeigename einer Option-Def (DE führend, EN-Fallback).
static func display_name(option_def: Dictionary, locale := "de") -> String:
	var name_de := str(option_def.get("name_de", ""))
	var name_en := str(option_def.get("name_en", name_de))
	return name_en if locale == "en" and name_en != "" else name_de


## Cache leeren (Tests / Pack-Hot-Reload).
static func reset_cache() -> void:
	_wallfloor = {}
	_house = {}
	_default_ids = {}
	_loaded = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_wallfloor = _load_json(WALLFLOOR_PATH)
	_house = _load_json(HOUSE_PATH)
	_loaded = true


## Default-IDs je Art einsammeln (Haus, Grundstück, Basis-Raum + alle Räume).
static func _sammle_default_ids() -> void:
	var ids_je_art: Dictionary = {}
	for art: String in OPTION_ARTEN:
		ids_je_art[art] = []
	var haus := default_haus()
	var haus_keys := {
		"dachForm": "dachForm",
		"hausnummer": "hausnummer",
		"briefkasten": "briefkasten",
		"vordach": "vordach",
	}
	for key: String in haus_keys:
		_merke_default(ids_je_art, haus_keys[key], str(haus.get(key, "")))
	var grund := default_grundstueck()
	_merke_default(ids_je_art, "grundBoden", str(grund.get("boden", "")))
	_merke_default(ids_je_art, "weg", str(grund.get("weg", "")))
	_merke_default(ids_je_art, "zaun", str(grund.get("zaun", "")))
	var raum_quellen: Array = [_house.get("defaults", {}).get("raum", {})]
	var raeume: Variant = _house.get("defaults", {}).get("raeume", {})
	if raeume is Dictionary:
		for room_id: Variant in raeume:
			raum_quellen.append(raeume[room_id])
	for quelle: Dictionary in raum_quellen:
		_merke_default(ids_je_art, "wand", str(quelle.get("wand", "")))
		_merke_default(ids_je_art, "boden", str(quelle.get("boden", "")))
	_default_ids = ids_je_art


static func _merke_default(ids_je_art: Dictionary, art: String, id: String) -> void:
	if id != "" and not (ids_je_art[art] as Array).has(id):
		(ids_je_art[art] as Array).append(id)


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Gestalten-Katalog fehlt: %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("Gestalten-Katalog kaputt: %s (%s)" % [path, json.get_error_message()])
		return {}
	return json.data if json.data is Dictionary else {}
