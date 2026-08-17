class_name UpdatesManifest
extends RefCounted
## manifest.json-Parser/-Validator + semver-Vergleich + installed.json-Buchführung
## (Doc B §1.4/§2.2, W2b UPDATES). Reine statische Logik — keine Nodes, kein Netz.
##
## Schema (Release-Tag `updates`, siehe docs/UPDATES.md §3):
##   { "schema": 1, "latest_native": "5.1.0", "notes_de": "…", "packs": [
##       { "id", "version", "url", "sha256", "min_native", "priority"?, "type"?, "size"?, … } ] }

const SCHEMA_VERSION := 1
const INSTALLED_SCHEMA_VERSION := 1
## Default-Prioritäten der 7 Packs (Doc B §1.1) — Manifest-`priority` gewinnt.
const DEFAULT_PRIORITIES := {
	"core": 100,
	"balance": 200,
	"events": 300,
	"cosmetics": 400,
	"stickers": 500,
	"codes": 600,
	"config": 700,
}
const _REQUIRED_PACK_FIELDS: Array[String] = ["id", "version", "url", "sha256", "min_native"]


## Parst "1.2.3" (optional "v"-Präfix, optional "-prerelease"-Suffix).
## Rückgabe: [major, minor, patch] — leer bei ungültigem Format.
static func parse_semver(text: Variant) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if not (text is String):
		return empty
	var raw: String = text
	raw = raw.strip_edges()
	if raw.begins_with("v"):
		raw = raw.substr(1)
	var dash := raw.find("-")
	if dash >= 0:
		raw = raw.substr(0, dash)
	var parts := raw.split(".")
	if parts.size() != 3:
		return empty
	var nums := PackedInt32Array()
	for part in parts:
		if part.is_empty() or not part.is_valid_int() or part.begins_with("+"):
			return empty
		var value := int(part)
		if value < 0:
			return empty
		nums.append(value)
	return nums


static func is_semver(text: Variant) -> bool:
	return not parse_semver(text).is_empty()


## Klassischer Dreiwege-Vergleich: -1 (a<b), 0, 1 (a>b).
## Ungültige Versionen zählen als "0.0.0" (defensiv; Validator fängt sie vorher).
static func compare_semver(a: Variant, b: Variant) -> int:
	var va := parse_semver(a)
	var vb := parse_semver(b)
	if va.is_empty():
		va = PackedInt32Array([0, 0, 0])
	if vb.is_empty():
		vb = PackedInt32Array([0, 0, 0])
	for i in 3:
		if va[i] != vb[i]:
			return -1 if va[i] < vb[i] else 1
	# Numerisch gleich: Release > Prerelease ("1.2.3" > "1.2.3-beta").
	var pre_a := _has_prerelease(a)
	var pre_b := _has_prerelease(b)
	if pre_a == pre_b:
		return 0
	return -1 if pre_a else 1


static func semver_gt(a: Variant, b: Variant) -> bool:
	return compare_semver(a, b) > 0


static func semver_lte(a: Variant, b: Variant) -> bool:
	return compare_semver(a, b) <= 0


## Parst + validiert einen manifest.json-Text. Rückgabe:
## { "ok": bool, "manifest": Dictionary, "error": String }
static func parse(json_text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return _err("manifest.json ist kein gültiges JSON: %s" % json.get_error_message())
	var data: Variant = json.data
	if not (data is Dictionary):
		return _err("manifest.json muss ein Objekt sein.")
	var problem := validate(data)
	if not problem.is_empty():
		return _err(problem)
	return {"ok": true, "manifest": data, "error": ""}


## Leerer String = valide; sonst die erste Fehlermeldung.
static func validate(data: Dictionary) -> String:
	if int(data.get("schema", -1)) != SCHEMA_VERSION:
		return (
			"Unbekanntes Manifest-Schema: %s (erwartet %d)." % [data.get("schema"), SCHEMA_VERSION]
		)
	if not is_semver(data.get("latest_native")):
		return "latest_native fehlt oder ist kein semver: %s" % [data.get("latest_native")]
	if not (data.get("packs") is Array):
		return "packs fehlt oder ist kein Array."
	var seen_ids := {}
	for entry: Variant in data["packs"]:
		if not (entry is Dictionary):
			return "packs[]-Eintrag ist kein Objekt."
		for field in _REQUIRED_PACK_FIELDS:
			if not entry.has(field):
				return "Pack '%s': Pflichtfeld '%s' fehlt." % [entry.get("id", "?"), field]
		if not is_semver(entry["version"]):
			return "Pack '%s': version ist kein semver: %s" % [entry["id"], entry["version"]]
		if not is_semver(entry["min_native"]):
			return "Pack '%s': min_native ist kein semver: %s" % [entry["id"], entry["min_native"]]
		var sha := str(entry["sha256"]).to_lower()
		if sha.length() != 64 or not sha.is_valid_hex_number():
			return "Pack '%s': sha256 ist kein 64-stelliger Hex-String." % entry["id"]
		if str(entry["url"]).is_empty():
			return "Pack '%s': url ist leer." % entry["id"]
		if seen_ids.has(entry["id"]):
			return "Pack-Id doppelt im Manifest: %s" % entry["id"]
		seen_ids[entry["id"]] = true
	return ""


## Priorität eines Manifest-/installed-Eintrags (Manifest-Feld > Default-Tabelle > 900).
static func priority_of(entry: Dictionary) -> int:
	if entry.has("priority"):
		return int(entry["priority"])
	return int(DEFAULT_PRIORITIES.get(str(entry.get("id", "")), 900))


## Liest user://packs/installed.json (fehlend/kaputt → frische Struktur).
static func read_installed(path: String) -> Dictionary:
	var fresh := {"schema": INSTALLED_SCHEMA_VERSION, "packs": {}}
	if not FileAccess.file_exists(path):
		return fresh
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_warning("installed.json kaputt — starte mit leerem Stand: %s" % path)
		return fresh
	var data: Dictionary = json.data
	if not (data.get("packs") is Dictionary):
		data["packs"] = {}
	data["schema"] = INSTALLED_SCHEMA_VERSION
	return data


## Schreibt installed.json atomar (tmp + rename).
static func write_installed(path: String, data: Dictionary) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("installed.json nicht schreibbar: %s" % tmp_path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(path)
	)
	return err == OK


## Effektiv installierte Version eines Packs = max(eingebaut, user-installiert&enabled).
static func effective_version(
	pack_id: String, installed: Dictionary, builtin_versions: Dictionary
) -> String:
	var version := str(builtin_versions.get(pack_id, "0.0.0"))
	var packs: Dictionary = installed.get("packs", {})
	var entry: Dictionary = packs.get(pack_id, {})
	if not entry.is_empty() and bool(entry.get("enabled", false)):
		var user_version := str(entry.get("version", "0.0.0"))
		if semver_gt(user_version, version):
			version = user_version
	return version


## Vergleichslogik „Suche nach Updates“ (Doc B §2.1 Schritt 2/3). Rückgabe:
## { "to_install": Array[Dictionary], "gated": Array[Dictionary],
##   "native_update": bool, "up_to_date": bool }
static func plan_updates(
	manifest: Dictionary,
	installed: Dictionary,
	builtin_versions: Dictionary,
	app_version: String,
) -> Dictionary:
	var to_install: Array[Dictionary] = []
	var gated: Array[Dictionary] = []
	var native_update := semver_gt(manifest.get("latest_native", "0.0.0"), app_version)
	for entry: Dictionary in manifest.get("packs", []):
		var pack_id := str(entry["id"])
		var have := effective_version(pack_id, installed, builtin_versions)
		if not semver_gt(entry["version"], have):
			continue
		if semver_gt(entry["min_native"], app_version):
			gated.append(entry)
			continue
		to_install.append(entry)
	to_install.sort_custom(func(a, b): return priority_of(a) < priority_of(b))
	return {
		"to_install": to_install,
		"gated": gated,
		"native_update": native_update,
		"up_to_date": to_install.is_empty() and gated.is_empty() and not native_update,
	}


## Liest die eingebauten Pack-Versionen aus <content_root>/*/pack.json.
## MUSS vor dem ersten load_resource_pack passieren (Packs überschatten die Dateien).
static func read_builtin_versions(content_root: String) -> Dictionary:
	var versions := {}
	var dir := DirAccess.open(content_root)
	if dir == null:
		return versions
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var meta := read_pack_meta("%s/%s/pack.json" % [content_root, entry])
			if not meta.is_empty():
				versions[str(meta.get("id", entry))] = str(meta.get("version", "0.0.0"))
		entry = dir.get_next()
	dir.list_dir_end()
	return versions


## Liest eine pack.json (leer bei fehlend/kaputt — Ordner ohne pack.json sind
## KEINE Packs, z. B. content/base/ anderer Wellen).
static func read_pack_meta(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		push_warning("pack.json kaputt: %s" % path)
		return {}
	return json.data


static func _has_prerelease(text: Variant) -> bool:
	return text is String and (text as String).find("-") >= 0


static func _err(message: String) -> Dictionary:
	return {"ok": false, "manifest": {}, "error": message}
