class_name AchievementsCatalog
extends RefCounted
## Erfolgs-Katalog-Sicht (REST-1, EVAL-VOLLSTAENDIGKEIT Rang 3): liest die
## 44 Erfolge der Web-Vorlage aus der W2b-ContentRegistry (Domain
## "achievements", Pack `content/achievements/`) und bietet pure Helfer für
## Screen, Engine und Tests. Namen/Beschreibungen liegen NICHT im Pack,
## sondern unter `achievements.defs.<id>.name/.desc` in den Strings —
## so prüft das DE/EN-Paritäts-Tor beide Sprachen automatisch mit.
##
## Katalog-Eintrag (content/achievements/data/achievements.json):
##   {id, cat, order, coins, cond{type:"counter"|"special", key, count}}

## Kategorien in Anzeige-Reihenfolge (Screen-Chips; Strings:
## achievements.kategorie.<id>).
const CATEGORIES: Array[String] = ["pflege", "spiel", "garten", "sammeln", "reisen", "fortschritt"]
const COND_TYPES: Array[String] = ["counter", "special"]
const FALLBACK_PATH := "res://content/achievements/data/achievements.json"


## Alle Erfolge, nach `order` sortiert. Ohne Registry-Autoload (nackte
## Logik-Tests) fällt die Sicht auf die eingebaute Pack-Datei zurück.
static func all() -> Array:
	var items := _registry_items("achievements")
	if items.is_empty():
		items = _fallback_items()
	items.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("order", 0)) < int(b.get("order", 0))
	)
	return items


static func by_id(items: Array, id: String) -> Dictionary:
	for def: Variant in items:
		if def is Dictionary and str(def.get("id", "")) == id:
			return def
	return {}


## Erfolge einer Kategorie (Katalog-Reihenfolge).
static func by_category(items: Array, cat: String) -> Array:
	var result: Array = []
	for def: Variant in items:
		if def is Dictionary and str(def.get("cat", "")) == cat:
			result.append(def)
	return result


## Summe aller Münz-Belohnungen (Web: exakt 3410).
static func total_coins(items: Array) -> int:
	var sum := 0
	for def: Variant in items:
		if def is Dictionary:
			sum += int(def.get("coins", 0))
	return sum


## Katalog-Validierung (Tests + Boot-Warnung): liefert Fehlermeldungen.
static func validate(items: Array) -> Array:
	var errors: Array = []
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
		if not CATEGORIES.has(str(def.get("cat", ""))):
			errors.append("%s: unbekannte Kategorie '%s'" % [id, def.get("cat")])
		if int(def.get("coins", 0)) <= 0:
			errors.append("%s: coins fehlt/<= 0" % id)
		var cond: Variant = def.get("cond")
		if not (cond is Dictionary) or not COND_TYPES.has(str(cond.get("type", ""))):
			errors.append("%s: cond fehlt/unbekannter type" % id)
		elif str(cond.get("key", "")).is_empty():
			errors.append("%s: cond.key fehlt" % id)
		elif int(cond.get("count", 0)) <= 0:
			errors.append("%s: cond.count fehlt/<= 0" % id)
	return errors


static func _registry_items(domain: String) -> Array:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return []
	var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	if registry == null or not registry.has_method("get_items"):
		return []
	return registry.get_items(domain)


static func _fallback_items() -> Array:
	if not FileAccess.file_exists(FALLBACK_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FALLBACK_PATH))
	if parsed is Dictionary and parsed.get("items") is Array:
		return (parsed["items"] as Array).duplicate(true)
	return []
