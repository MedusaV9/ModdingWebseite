class_name GardenCrops
extends RefCounted
## Pflanzen-Katalog des Gartens (Doc D §6.2) — Content-Pack-fähig über
## HomePackData. Rein statisch, headless-testbar.
##
## Normalisierte Keys: id, name_de, name_en, stufen (Wachstums-Stufen bis
## erntereif), minuten_pro_stufe, licht ("sonne"|"schatten"|"neutral"),
## preis (Basis-Verkaufspreis pro Stück — Wochenmarkt/Kompost rechnen darauf),
## ernte (Stück pro Ernte), exot (nur im Gewächshaus), food (Inventar-Id
## oder "" ), farbe (Vorschau-Tönung).

const FILE_NAME := "garden_crops.json"
const BASE_PATH := "res://scripts/home/data/garden_crops.json"
const LICHT_ARTEN: Array[String] = ["sonne", "schatten", "neutral"]

static var _crops: Dictionary = {}
static var _loaded := false


static func all() -> Dictionary:
	if not _loaded:
		_loaded = true
		_crops = HomePackData.merge_by_id(
			HomePackData.documents(BASE_PATH, FILE_NAME), "crops", _normalize
		)
	return _crops


static func crop(crop_id: String) -> Dictionary:
	return all().get(crop_id, {})


static func ids() -> Array:
	var out := all().keys()
	out.sort()
	return out


## Pflanzbar auf einem Beet: Exoten nur im Gewächshaus.
static func plantable(im_gewaechshaus: bool) -> Array:
	var out: Array = []
	for id: String in ids():
		var row: Dictionary = all()[id]
		if bool(row["exot"]) and not im_gewaechshaus:
			continue
		out.append(row)
	return out


static func display_name(crop_id: String, locale := "de") -> String:
	var row := crop(crop_id)
	if row.is_empty():
		return crop_id
	return str(row.get("name_en", row["name_de"]) if locale == "en" else row["name_de"])


## Basis-Verkaufspreis pro Stück (Wochenmarkt-Datenvertrag, ORTE-Agent).
static func base_price(crop_id: String) -> int:
	return int(crop(crop_id).get("preis", 0))


## Minuten bis erntereif ohne Faktoren (Anzeige „ca. 3 h“).
static func total_minutes(crop_id: String) -> int:
	var row := crop(crop_id)
	if row.is_empty():
		return 0
	return int(row["stufen"]) * int(row["minuten_pro_stufe"])


static func reset_cache() -> void:
	_crops = {}
	_loaded = false


static func _normalize(raw: Dictionary) -> Dictionary:
	var id := str(raw.get("id", ""))
	if id == "":
		push_error("Crop ohne id: %s" % str(raw))
		return {}
	var licht := str(raw.get("licht", "neutral"))
	if not LICHT_ARTEN.has(licht):
		licht = "neutral"
	return {
		"id": id,
		"name_de": str(raw.get("name_de", id)),
		"name_en": str(raw.get("name_en", raw.get("name_de", id))),
		"stufen": maxi(1, int(raw.get("stufen", 3))),
		"minuten_pro_stufe": maxi(1, int(raw.get("minuten_pro_stufe", 60))),
		"licht": licht,
		"preis": maxi(0, int(raw.get("preis", 0))),
		"ernte": maxi(1, int(raw.get("ernte", 1))),
		"exot": bool(raw.get("exot", false)),
		"food": str(raw.get("food", "")),
		"farbe": str(raw.get("farbe", "#8FD06C")),
	}
