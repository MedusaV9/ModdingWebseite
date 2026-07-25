class_name StickerCatalog
extends RefCounted
## Sticker-Katalog-Sicht (W3d CONTENT, Doc H §3): liest den gemergten
## Katalog aus der W2b-ContentRegistry (Domains "stickers" +
## "sticker_pages") und bietet pure Helfer für Album-UI und Tests.
##
## Katalog-Eintrag (content/stickers/data/stickers.json):
##   {id, name_de, flavor_de, hint_de, set, page, rarity, image, cond,
##    secret?} — rarity ∈ haeufig/selten/episch/geheim (H §3.4);
##   cond ∈ {type:"counter"|"special"|"event"|"code", key, count?, sub?}.
## Seiten-Eintrag: {id, title_de, icon, tint, order}.

const RARITIES: Array[String] = ["haeufig", "selten", "episch", "geheim"]
const COND_TYPES: Array[String] = ["counter", "special", "event", "code"]


## Alle Sticker aus der Registry (leer ohne Autoload — Tests injizieren).
static func all() -> Array:
	return _registry_items("stickers")


## Seiten-Katalog, nach `order` sortiert.
static func pages() -> Array:
	var result := _registry_items("sticker_pages")
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("order", 0)) < int(b.get("order", 0))
	)
	return result


## Sticker nach Seite gruppiert: page_id -> Array[def] (Katalog-Reihenfolge).
static func by_page(items: Array) -> Dictionary:
	var grouped: Dictionary = {}
	for def: Variant in items:
		if not (def is Dictionary):
			continue
		var page := str(def.get("page", ""))
		if not grouped.has(page):
			grouped[page] = []
		(grouped[page] as Array).append(def)
	return grouped


static func by_id(items: Array, id: String) -> Dictionary:
	for def: Variant in items:
		if def is Dictionary and str(def.get("id", "")) == id:
			return def
	return {}


## Nicht-geheime Sticker (der n/N-Zähler — Geheim-Sticker zählen nicht,
## H §3.4 „+💗“-Prinzip).
static func regular_count(items: Array) -> int:
	var count := 0
	for def: Variant in items:
		if def is Dictionary and not bool(def.get("secret", false)):
			count += 1
	return count


## Katalog-Validierung (Tests + Boot-Warnung): liefert Fehlermeldungen.
static func validate(items: Array, page_defs: Array) -> Array:
	var errors: Array = []
	var page_ids := {}
	for page: Variant in page_defs:
		if page is Dictionary:
			page_ids[str(page.get("id", ""))] = true
	var seen := {}
	for def: Variant in items:
		if not (def is Dictionary):
			errors.append("Eintrag ist kein Objekt")
			continue
		var id := str(def.get("id", ""))
		if id.is_empty():
			errors.append("Eintrag ohne id")
			continue
		if seen.has(id):
			errors.append("%s: doppelte id" % id)
		seen[id] = true
		for field in ["name_de", "flavor_de", "hint_de", "image", "page"]:
			if str(def.get(field, "")).is_empty():
				errors.append("%s: Feld '%s' fehlt" % [id, field])
		if not RARITIES.has(str(def.get("rarity", ""))):
			errors.append("%s: unbekannte rarity '%s'" % [id, def.get("rarity")])
		if not page_ids.has(str(def.get("page", ""))):
			errors.append("%s: unbekannte Seite '%s'" % [id, def.get("page")])
		var cond: Variant = def.get("cond")
		if not (cond is Dictionary) or not COND_TYPES.has(str(cond.get("type", ""))):
			errors.append("%s: cond fehlt/unbekannter type" % id)
		elif str(cond.get("key", "")).is_empty():
			errors.append("%s: cond.key fehlt" % id)
	return errors


static func _registry_items(domain: String) -> Array:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return []
	var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	if registry == null or not registry.has_method("get_items"):
		return []
	return registry.get_items(domain)
