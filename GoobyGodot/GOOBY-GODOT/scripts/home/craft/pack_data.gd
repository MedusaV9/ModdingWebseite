class_name HomePackData
extends RefCounted
## Content-Pack-fähiger JSON-Loader für die Haus-Datenkataloge (Doc D §1.3).
##
## Ein Katalog besteht aus einer Basis-Datei (mit der App ausgeliefert) plus
## beliebig vielen Pack-Dateien, die per `id` überschreiben:
##   1. `res://scripts/home/data/<name>.json`   (Basis)
##   2. `res://content/*/home/<name>.json`      (eingebaute Content-Packs)
##   3. `user://packs/*/home/<name>.json`       (nachgeladene Packs, §B)
## Späteres gewinnt. Kaputte/fehlende Pack-Dateien werden übersprungen —
## der Basis-Katalog muss immer laden, sonst gäbe es kein Spiel.

const CONTENT_ROOT := "res://content"
const USER_PACK_ROOT := "user://packs"
const PACK_SUBDIR := "home"


## Alle Katalog-Dokumente eines Namens in Merge-Reihenfolge (Basis zuerst).
static func documents(base_path: String, file_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base := load_json(base_path)
	if not base.is_empty():
		out.append(base)
	for dir_path in [CONTENT_ROOT, USER_PACK_ROOT]:
		for pack_dir in _subdirs(dir_path):
			var path := "%s/%s/%s/%s" % [dir_path, pack_dir, PACK_SUBDIR, file_name]
			var doc := load_json(path)
			if not doc.is_empty():
				out.append(doc)
	return out


## Merged eine Listen-Domain per `id` (späterer Eintrag ersetzt früheren).
## `normalizer` bekommt den Roh-Eintrag und liefert {} für „verwerfen“.
static func merge_by_id(
	docs: Array[Dictionary], list_key: String, normalizer: Callable
) -> Dictionary:
	var out: Dictionary = {}
	for doc: Dictionary in docs:
		var raw_list: Variant = doc.get(list_key)
		if not (raw_list is Array):
			continue
		for entry: Variant in raw_list:
			if not (entry is Dictionary):
				continue
			var normalized: Dictionary = normalizer.call(entry)
			if normalized.is_empty():
				continue
			out[normalized["id"]] = normalized
	return out


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("Haus-Daten kaputt: %s (%s)" % [path, json.get_error_message()])
		return {}
	return json.data if json.data is Dictionary else {}


static func _subdirs(root: String) -> PackedStringArray:
	var dir := DirAccess.open(root)
	if dir == null:
		return PackedStringArray()
	var found := dir.get_directories()
	found.sort()
	return found
