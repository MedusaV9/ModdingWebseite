class_name DailyQuestCatalog
extends RefCounted
## Tagesquest-Katalog (REST-2): liest den Quest-Pool aus der ContentRegistry
## (Domain "quests", append-by-id — Packs können Quests ergänzen/ersetzen,
## Muster SoulService.defs_from_registry). Ohne Autoload (headless Tests)
## fällt der Loader auf die eingebaute Datei content/quests/data/quests.json
## zurück, damit Engine-Tests denselben Pool sehen wie das Spiel.
##
## Texte: Konvention quests.q.<id>.titel / quests.q.<id>.text — Packs können
## per `titel_key`/`text_key` im Def eigene Schlüssel mitbringen.

const DOMAIN := "quests"
const BUILTIN_PATH := "res://content/quests/data/quests.json"


## Gemergter Pool (Registry, sonst eingebaute Datei).
static func pool() -> Array:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
		if registry != null and registry.has_method("get_items"):
			var items: Array = registry.get_items(DOMAIN)
			if not items.is_empty():
				return items
	return builtin_pool()


## Eingebauter Pool direkt aus der Pack-Datei (Test-/Fallback-Pfad).
static func builtin_pool() -> Array:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(BUILTIN_PATH)) != OK:
		return []
	if not (json.data is Dictionary) or not (json.data.get("items") is Array):
		return []
	return json.data["items"]


static func title_key(def: Dictionary) -> String:
	var override := str(def.get("titel_key", ""))
	return override if not override.is_empty() else "quests.q.%s.titel" % str(def.get("id", ""))


static func text_key(def: Dictionary) -> String:
	var override := str(def.get("text_key", ""))
	return override if not override.is_empty() else "quests.q.%s.text" % str(def.get("id", ""))
