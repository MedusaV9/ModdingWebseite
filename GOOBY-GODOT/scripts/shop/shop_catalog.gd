class_name ShopCatalog
extends RefCounted
## Verkaufs-Sicht auf den Möbelkatalog (CONTENT-B) = Basis-Katalog aus W2a
## PLUS nachgelieferte Pack-Möbel, angereichert um die Varianten-Liste.
##
## Warum eine eigene Schicht?
##  - `FurnitureCatalog` (W2a, wird NICHT angefasst) normalisiert Defs und
##    verwirft dabei alle unbekannten Keys — auch `variants`. Die Basis-Defs
##    werden hier deshalb VERBATIM übernommen und nur um `variants` ergänzt.
##  - Zusätzliche Möbel kommen ohne App-Update über den Auto-Updater:
##    `content/furniture/data/furniture_extra.json` → ContentRegistry-Domain
##    `furniture_extra` (append-by-id) → hier normalisiert und eingemischt.
##    Ein Pack-Eintrag mit bekannter id gewinnt (gleiche Regel wie in der
##    Registry), sodass Balancing-Fixes nachlieferbar bleiben.
##
## Konsumenten-Vertrag = der von FurnitureCatalog (siehe dort) + zusätzlich:
##   variants: Array[String] (mind. ["natur"]), pack: bool (aus einem Pack).

const CATALOG_PATH := "res://scripts/home/data/furniture_catalog.json"
const PACK_DOMAIN := "furniture_extra"

## Tests injizieren hier eine Registry-Attrappe (null = Autoload benutzen).
static var registry_override: Object = null

static var _defs: Dictionary = {}
static var _loaded := false


## id -> angereicherte Def (gecacht).
static func defs() -> Dictionary:
	if not _loaded:
		_defs = _build()
		_loaded = true
	return _defs


static func def(item_id: String) -> Dictionary:
	return defs().get(item_id, {})


static func ids() -> Array:
	var out := defs().keys()
	out.sort()
	return out


## Alle belegten Kategorien, alphabetisch (Filter-Chips der Ausstellung).
static func categories() -> Array:
	var seen := {}
	for id: String in ids():
		seen[str(defs()[id]["kategorie"])] = true
	var out := seen.keys()
	out.sort()
	return out


static func by_category(kategorie: String) -> Array:
	return filter("", kategorie)


## Steht das Möbel im Laden? Preis 0 heißt „nur craftbar“ (Werkstatt-Möbel
## aus M2) — die dürfen hier nicht gratis über die Theke gehen.
static func sellable(item_def: Dictionary) -> bool:
	return int(item_def.get("preis", 0)) > 0


## Regal-Reihenfolge der Ausstellung: optional nach Kategorie gefiltert und
## nach Suchtext (DE- ODER EN-Name, case-insensitive) gesiebt. Leere
## Kategorie = alles. Sortiert nach Preis, damit Günstiges vorn liegt.
static func filter(query: String, kategorie := "") -> Array:
	var needle := query.strip_edges().to_lower()
	var out: Array = []
	for id: String in ids():
		var item: Dictionary = defs()[id]
		if not sellable(item):
			continue
		if kategorie != "" and str(item["kategorie"]) != kategorie:
			continue
		if needle != "" and not _matches(item, needle):
			continue
		out.append(item)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["preis"]) == int(b["preis"]):
				return str(a["id"]) < str(b["id"])
			return int(a["preis"]) < int(b["preis"])
	)
	return out


## Belegte Grid-Fläche als „X×Y“ (Doc D: „Grid-Felder-Bedarf sichtbar“).
static func footprint_text(item_def: Dictionary) -> String:
	var fp: Vector2i = item_def.get("footprint", Vector2i.ONE)
	return "%d×%d" % [fp.x, fp.y]


## Cache leeren (Tests, Pack-Hot-Reload nach einem Update).
static func reset_cache() -> void:
	_defs = {}
	_loaded = false


static func _matches(item: Dictionary, needle: String) -> bool:
	for key in ["name_de", "name_en", "id"]:
		if str(item.get(key, "")).to_lower().contains(needle):
			return true
	return false


static func _build() -> Dictionary:
	var out: Dictionary = {}
	var variants := _variant_lists()
	for id: String in FurnitureCatalog.defs():
		var item: Dictionary = (FurnitureCatalog.defs()[id] as Dictionary).duplicate(true)
		item["variants"] = FurnitureVariants.ids_for({"variants": variants.get(id, [])})
		item["pack"] = false
		out[id] = item
	for raw: Variant in _pack_items():
		if not (raw is Dictionary):
			continue
		var item := _normalize_pack_def(raw)
		if not item.is_empty():
			out[item["id"]] = item
	return out


## `variants`-Listen aus dem ROH-JSON (FurnitureCatalog wirft sie beim
## Normalisieren weg — es ist ein W2a-Vertrag, der nicht erweitert wird).
static func _variant_lists() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(CATALOG_PATH):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not (parsed is Dictionary) or not (parsed["items"] is Array):
		return out
	for entry: Variant in parsed["items"]:
		if entry is Dictionary and (entry as Dictionary).get("variants") is Array:
			out[str(entry["id"])] = entry["variants"]
	return out


static func _pack_items() -> Array:
	var registry: Object = registry_override
	if registry == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			registry = (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	if registry == null or not registry.has_method("get_items"):
		return []
	return registry.get_items(PACK_DOMAIN)


## Pack-Eintrag → Def im FurnitureCatalog-Format. Bewusst dieselben
## Defaults/Clamps; `test_shop_catalog.gd` vergleicht Basis-Defs 1:1 gegen
## FurnitureCatalog und schlägt Alarm, falls der Vertrag auseinanderläuft.
static func _normalize_pack_def(raw: Dictionary) -> Dictionary:
	var id := str(raw.get("id", ""))
	var layer_name := str(raw.get("layer", ""))
	if id == "" or not FurnitureCatalog.LAYER_NAMES.has(layer_name):
		push_warning("Pack-Möbel ungültig (übersprungen): %s" % str(raw))
		return {}
	var fp_raw: Array = raw.get("footprint", [1, 1])
	var layer: int = FurnitureCatalog.LAYER_NAMES[layer_name]
	var footprint := Vector2i(maxi(1, int(fp_raw[0])), maxi(1, int(fp_raw[1])))
	return {
		"id": id,
		"name_de": str(raw.get("name_de", id)),
		"name_en": str(raw.get("name_en", raw.get("name_de", id))),
		"glb": str(raw.get("glb", "")),
		"footprint": footprint,
		"layer": layer,
		"preis": maxi(0, int(raw.get("preis", 0))),
		"lagerwert": clampi(int(raw.get("lagerwert", 1)), 1, 4),
		"pflicht": str(raw.get("pflicht", "")),
		"kategorie": str(raw.get("kategorie", "deko")),
		"surface": bool(raw.get("surface", false)),
		"blocks_movement": bool(raw.get("blocks_movement", layer == GridData.Layer.FLOOR)),
		"can_toggle_light": bool(raw.get("can_toggle_light", false)),
		"wall_size": maxi(1, int(raw.get("wall_size", footprint.x))),
		"fill": clampf(float(raw.get("fill", FurnitureCatalog.DEFAULT_FILL)), 0.5, 1.0),
		"verkaufswert": maxi(0, int(raw.get("verkaufswert", 0))),
		"exterior": bool(raw.get("exterior", false)),
		"vista": str(raw.get("vista", "")),
		"proc": str(raw.get("proc", "")),
		"variants": FurnitureVariants.ids_for(raw),
		"pack": true,
	}
