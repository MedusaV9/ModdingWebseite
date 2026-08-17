class_name CraftRecipes
extends RefCounted
## Rezept-/Bauplan-Katalog (Doc D §5.2) — Content-Pack-fähig wie der
## Möbelkatalog (HomePackData: Basis → content/ → user://packs, Merge per id).
##
## Normalisierte Rezept-Keys:
##   id, output {item, count}, materialien {materialId: menge},
##   station (Default "werkbank"), bauplan ("" = frei verfügbar),
##   craft_sek (Fortschrittsdauer in Sekunden).

const FILE_NAME := "craft_recipes.json"
const BASE_PATH := "res://scripts/home/data/craft_recipes.json"
const STATION_WERKBANK := "werkbank"

static var _recipes: Dictionary = {}
static var _loaded := false


static func all() -> Dictionary:
	if not _loaded:
		_loaded = true
		_recipes = HomePackData.merge_by_id(
			HomePackData.documents(BASE_PATH, FILE_NAME), "recipes", _normalize
		)
	return _recipes


static func recipe(recipe_id: String) -> Dictionary:
	return all().get(recipe_id, {})


static func ids() -> Array:
	var out := all().keys()
	out.sort()
	return out


## Rezepte einer Station in stabiler Reihenfolge (UI-Liste).
static func for_station(station := STATION_WERKBANK) -> Array:
	var out: Array = []
	for id: String in ids():
		if all()[id]["station"] == station:
			out.append(all()[id])
	return out


## Alle Bauplan-Ids, die überhaupt vorkommen (Baumarkt-Sortiment-Abgleich).
static func blueprint_ids() -> Array:
	var seen: Dictionary = {}
	for id: String in ids():
		var bp: String = all()[id]["bauplan"]
		if bp != "":
			seen[bp] = true
	var out := seen.keys()
	out.sort()
	return out


static func reset_cache() -> void:
	_recipes = {}
	_loaded = false


static func _normalize(raw: Dictionary) -> Dictionary:
	var id := str(raw.get("id", ""))
	var output: Variant = raw.get("output", {})
	if id == "" or not (output is Dictionary) or str(output.get("item", "")) == "":
		push_error("Rezept ungültig: %s" % str(raw))
		return {}
	var materialien: Dictionary = {}
	var raw_materials: Variant = raw.get("materialien", {})
	if raw_materials is Dictionary:
		for key: Variant in raw_materials:
			var amount := maxi(0, int(raw_materials[key]))
			if amount > 0:
				materialien[str(key)] = amount
	return {
		"id": id,
		"output": {"item": str(output["item"]), "count": maxi(1, int(output.get("count", 1)))},
		"materialien": materialien,
		"station": str(raw.get("station", STATION_WERKBANK)),
		"bauplan": str(raw.get("bauplan", "") if raw.get("bauplan") != null else ""),
		"craft_sek": maxf(0.0, float(raw.get("craft_sek", 3.0))),
	}
