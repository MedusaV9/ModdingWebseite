class_name ContentRegistryService
extends Node
## ContentRegistry (Doc B §4.2; W2b UPDATES). Autoload-Kandidat „ContentRegistry“.
##
## Merged Sicht auf alle Content-Domains aus EINGEBAUTEN Daten (content/-Ordner,
## wird mit der IPA gebaut) + geladenen Packs (deren Dateien überschatten die
## eingebauten unter res://content/<id>/ — Pack-Daten gewinnen also per id+version
## automatisch auf Dateiebene; Domain-Merge über Packs hinweg passiert hier).
##
## Merge-Regeln pro Domain:
##  - append-by-id (cosmetics, stickers, codes, events): gleiche Content-Id →
##    höhere Pack-Priorität gewinnt + Warnung im Log.
##  - deep-merge-override (balance): values über Defaults.
##  - last-writer-wins (config): user://packs/config.json (Remote-Download)
##    gewinnt IMMER über den eingebauten Stand.
## Spiel-Systeme lesen NUR aus der Registry, nie direkt aus Dateien.

signal content_reloaded

const LIST_DOMAINS: Array[String] = ["cosmetics", "stickers", "codes", "events"]
## Ehrlicher Offline-Default. Release-CI ersetzt ihn fail-closed durch den
## konfigurierten öffentlichen WSS-Endpunkt; localhost ist nie Produkt-Default.
const NET_DEFAULTS := {"host": "", "port": 443, "tls": true}

## Autoload-Betrieb: in _ready() laden. Tests: false setzen (VOR add_child) und
## reload() nach dem Injizieren der Pfade selbst rufen.
var auto_reload := true
var content_root := "res://content"
var packs_dir := "user://packs"

var _domains: Dictionary = {}
var _pack_versions: Dictionary = {}
var _loaded := false


func _ready() -> void:
	if auto_reload:
		reload()


## Baut die Merge-Sicht neu auf (Boot nach PackLoader; nach Update-Downloads;
## Soft-Restart). Reihenfolge = Pack-Priorität aufsteigend (höher = gewinnt).
func reload() -> void:
	_domains = {}
	_pack_versions = {}
	for meta in _sorted_pack_metas():
		var pack_id := str(meta["id"])
		_pack_versions[pack_id] = str(meta.get("version", "0.0.0"))
		_merge_pack_data(pack_id)
	_overlay_user_config()
	_loaded = true
	content_reloaded.emit()


func get_cosmetics() -> Array:
	return get_items("cosmetics")


func get_stickers() -> Array:
	return get_items("stickers")


func get_codes() -> Array:
	return get_items("codes")


## Liste einer append-by-id-Domain (leeres Array, wenn nichts geliefert wurde).
func get_items(domain: String) -> Array:
	_ensure_loaded()
	var data: Variant = _domains.get(domain)
	return data.duplicate(true) if data is Array else []


## Balance-Wert per Punkt-Pfad (z. B. "zahnbuersten_bruch_chance").
func get_balance(key: String, default_value: Variant = null) -> Variant:
	_ensure_loaded()
	return _dig(_domains.get("balance", {}), key, default_value)


## Config-Wert per Punkt-Pfad (z. B. "manifest_url", "net.host", "flags.xyz").
func get_config(key: String, default_value: Variant = null) -> Variant:
	_ensure_loaded()
	return _dig(_domains.get("config", {}), key, default_value)


## Netz-Konfiguration für W2d-NetClient — Keys garantiert (Defaults s. NET_DEFAULTS).
## Kontrakt: handoffs/W2b-config-api.md. Bei jedem Connect frisch abrufen!
func get_net_config() -> Dictionary:
	var net := NET_DEFAULTS.duplicate(true)
	var configured: Variant = get_config("net", {})
	if configured is Dictionary:
		for key: String in configured:
			net[key] = configured[key]
	net["port"] = int(net["port"])
	return net


## Version eines Packs in der aktuellen Sicht ("0.0.0" wenn unbekannt).
func version_of(pack_id: String) -> String:
	_ensure_loaded()
	return str(_pack_versions.get(pack_id, "0.0.0"))


func known_pack_ids() -> Array:
	_ensure_loaded()
	var ids := _pack_versions.keys()
	ids.sort()
	return ids


func _ensure_loaded() -> void:
	if not _loaded:
		reload()


## Bekannte Packs = eingebaute Ordner mit pack.json ∪ Ids aus installed.json
## (so kann ein per Update NEU eingeführtes Pack ohne IPA ankommen, Doc B §4.2).
func _sorted_pack_metas() -> Array[Dictionary]:
	var metas: Array[Dictionary] = []
	var seen := {}
	var dir := DirAccess.open(content_root)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				var meta := UpdatesManifest.read_pack_meta(
					"%s/%s/pack.json" % [content_root, entry]
				)
				if not meta.is_empty() and meta.has("id"):
					metas.append(meta)
					seen[str(meta["id"])] = true
			entry = dir.get_next()
		dir.list_dir_end()
	var installed := UpdatesManifest.read_installed(packs_dir + "/installed.json")
	for pack_id: String in installed["packs"]:
		if seen.has(pack_id) or not bool(installed["packs"][pack_id].get("enabled", false)):
			continue
		var meta := UpdatesManifest.read_pack_meta("%s/%s/pack.json" % [content_root, pack_id])
		if not meta.is_empty():
			metas.append(meta)
	metas.sort_custom(
		func(a, b):
			var pa := UpdatesManifest.priority_of(a)
			var pb := UpdatesManifest.priority_of(b)
			if pa == pb:
				return str(a.get("id", "")) < str(b.get("id", ""))
			return pa < pb
	)
	return metas


func _merge_pack_data(pack_id: String) -> void:
	var data_dir := "%s/%s/data" % [content_root, pack_id]
	var dir := DirAccess.open(data_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			var domain := entry.get_basename()
			_merge_domain_file(pack_id, domain, "%s/%s" % [data_dir, entry])
		entry = dir.get_next()
	dir.list_dir_end()


func _merge_domain_file(pack_id: String, domain: String, path: String) -> void:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		push_warning("Content-Datei kaputt (übersprungen): %s" % path)
		return
	var data: Dictionary = json.data
	if LIST_DOMAINS.has(domain) or data.get("items") is Array:
		_merge_items(pack_id, domain, data.get("items", []))
	elif domain == "balance":
		_merge_deep(_domain_dict("balance"), data.get("values", {}))
	elif domain == "config":
		_merge_shallow(_domain_dict("config"), data)
	else:
		_merge_deep(_domain_dict(domain), data)


## append-by-id: späterer (= höher priorisierter) Pack ersetzt gleiche Ids.
func _merge_items(pack_id: String, domain: String, items: Variant) -> void:
	if not (items is Array):
		return
	if not (_domains.get(domain) is Array):
		_domains[domain] = []
	var merged: Array = _domains[domain]
	for item: Variant in items:
		if not (item is Dictionary) or not item.has("id"):
			push_warning("%s: Eintrag ohne id im Pack '%s' übersprungen." % [domain, pack_id])
			continue
		var replaced := false
		for i in merged.size():
			if merged[i].get("id") == item["id"]:
				push_warning(
					(
						"%s: Id '%s' aus Pack '%s' überschreibt früheren Eintrag."
						% [domain, item["id"], pack_id]
					)
				)
				merged[i] = item
				replaced = true
				break
		if not replaced:
			merged.append(item)


func _overlay_user_config() -> void:
	var path := packs_dir + "/config.json"
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		push_warning("user-config.json kaputt — eingebauter Stand bleibt aktiv: %s" % path)
		return
	_merge_shallow(_domain_dict("config"), json.data)


func _domain_dict(domain: String) -> Dictionary:
	if not (_domains.get(domain) is Dictionary):
		_domains[domain] = {}
	return _domains[domain]


func _merge_shallow(target: Dictionary, source: Variant) -> void:
	if not (source is Dictionary):
		return
	for key: String in source:
		if key == "schema":
			continue
		target[key] = source[key]


func _merge_deep(target: Dictionary, source: Variant) -> void:
	if not (source is Dictionary):
		return
	for key: String in source:
		if key == "schema":
			continue
		if source[key] is Dictionary and target.get(key) is Dictionary:
			_merge_deep(target[key], source[key])
		else:
			target[key] = source[key]


func _dig(data: Variant, key: String, default_value: Variant) -> Variant:
	var current: Variant = data
	for part in key.split("."):
		if not (current is Dictionary) or not current.has(part):
			return default_value
		current = current[part]
	return current
