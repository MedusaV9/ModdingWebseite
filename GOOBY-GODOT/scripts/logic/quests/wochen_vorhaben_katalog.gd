class_name WochenVorhabenKatalog
extends RefCounted
## Wochen-Vorhaben-Katalog (G8 IDEA-WOCHE): liest die Bögen aus der
## ContentRegistry (Domain "vorhaben", append-by-id — Packs können Vorhaben
## ergänzen/ersetzen, Muster DailyQuestCatalog). Ohne Autoload (headless
## Tests) fällt der Loader auf die eingebaute Datei
## content/quests/data/vorhaben.json zurück.
##
## Texte: Konvention vorhaben.b.<id>.titel / .finale sowie pro Schritt
## vorhaben.b.<id>.s<index>.text (Aufgabe) und .zwischen (Goobys warme
## Zeile, solange der Schritt aktiv ist).

const DOMAIN := "vorhaben"
const BUILTIN_PATH := "res://content/quests/data/vorhaben.json"


## Gemergter Katalog (Registry, sonst eingebaute Datei).
static func pool() -> Array:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
		if registry != null and registry.has_method("get_items"):
			var items: Array = registry.get_items(DOMAIN)
			if not items.is_empty():
				return items
	return builtin_pool()


## Eingebauter Katalog direkt aus der Pack-Datei (Test-/Fallback-Pfad).
static func builtin_pool() -> Array:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(BUILTIN_PATH)) != OK:
		return []
	if not (json.data is Dictionary) or not (json.data.get("items") is Array):
		return []
	return json.data["items"]


static func def_by_id(id: String) -> Dictionary:
	for def: Variant in pool():
		if def is Dictionary and str((def as Dictionary).get("id", "")) == id:
			return def
	return {}


static func title_key(def: Dictionary) -> String:
	return "vorhaben.b.%s.titel" % str(def.get("id", ""))


static func finale_key(def: Dictionary) -> String:
	return "vorhaben.b.%s.finale" % str(def.get("id", ""))


static func schritt_text_key(def: Dictionary, index: int) -> String:
	return "vorhaben.b.%s.s%d.text" % [str(def.get("id", "")), index]


static func schritt_zwischen_key(def: Dictionary, index: int) -> String:
	return "vorhaben.b.%s.s%d.zwischen" % [str(def.get("id", "")), index]
