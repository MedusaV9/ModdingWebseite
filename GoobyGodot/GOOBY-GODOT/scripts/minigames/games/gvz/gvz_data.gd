class_name GvzData
extends RefCounted
## Daten-Lader für Goobys vs Zombies (W3b). Quelle der Wahrheit sind die
## Owned-JSONs unter data/; Balancing ist Content-Pack-updatebar über den
## Balance-Namespace "gvz" der W2b-ContentRegistry: ein Balance-Pack liefert
## `{"values": {"gvz": {...}}}` und überschreibt hier per Deep-Merge JEDE
## Zahl aus gvz_balance.json — ohne IPA (Doc G §4.7).
## Alle Zahlen werden nach dem Laden ganzzahlig gemacht (int-Determinismus,
## Doc G §R3); Sekunden-Zeiten der Level (t) bleiben float und werden erst
## in GvzLogic.new_run in Ticks umgerechnet.

const BALANCE_PATH := "res://scripts/minigames/games/gvz/data/gvz_balance.json"
const LEVELS_PATH := "res://scripts/minigames/games/gvz/data/gvz_levels.json"
const PVP_PATH := "res://scripts/minigames/games/gvz/data/gvz_pvp.json"
const BALANCE_NAMESPACE := "gvz"
## Schlüssel, deren Werte Sekunden sind und float bleiben dürfen.
const FLOAT_KEYS := ["t"]


## Effektive Balance: eingebautes JSON + Registry-Override (Namespace "gvz").
## registry=null → Autoload /root/ContentRegistry per Duck-Typing (fehlt es,
## z. B. in Pure-Tests, gilt der eingebaute Stand).
static func load_balance(registry: Object = null) -> Dictionary:
	var balance := read_json(BALANCE_PATH)
	var reg := registry if registry != null else _autoload_registry()
	if reg != null and reg.has_method("get_balance"):
		var overrides: Variant = reg.get_balance(BALANCE_NAMESPACE, {})
		if overrides is Dictionary and not (overrides as Dictionary).is_empty():
			_deep_merge(balance, overrides)
	return _intify(balance)


## Alle 15 Kampagnen-Level (Array[Dictionary], ids 1..15).
static func load_levels() -> Array:
	var doc := read_json(LEVELS_PATH)
	var levels: Variant = doc.get("levels", [])
	return _intify(levels) if levels is Array else []


## Level per Id (leeres Dictionary, wenn unbekannt).
static func level_by_id(levels: Array, id: int) -> Dictionary:
	for level: Variant in levels:
		if level is Dictionary and int(level.get("id", 0)) == id:
			return level
	return {}


## Strukturelle Validierung der Level-Daten gegen die Balance.
## Liefert eine (leere) Liste menschenlesbarer Fehler.
static func validate_levels(levels: Array, balance: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if levels.size() != 15:
		errors.append("erwartet 15 Level, gefunden %d" % levels.size())
	var towers: Dictionary = balance.get("towers", {})
	var zombies: Dictionary = balance.get("zombies", {})
	var prev_unlocks: Array = []
	for i in levels.size():
		var level: Dictionary = levels[i]
		var prefix := "L%02d" % int(level.get("id", -1))
		if int(level.get("id", -1)) != i + 1:
			errors.append("%s: id nicht fortlaufend" % prefix)
		var lanes: Array = level.get("lanes", [])
		if lanes.is_empty():
			errors.append("%s: keine aktiven Reihen" % prefix)
		var unlocks: Array = level.get("unlock_towers", [])
		for tower: Variant in unlocks:
			if not towers.has(tower):
				errors.append("%s: unbekannter Turm '%s'" % [prefix, tower])
		for tower: Variant in prev_unlocks:
			if not unlocks.has(tower):
				errors.append("%s: Freischaltung '%s' verloren" % [prefix, tower])
		for tower: Variant in level.get("new_towers", []):
			if not unlocks.has(tower) or prev_unlocks.has(tower):
				errors.append("%s: new_tower '%s' inkonsistent" % [prefix, tower])
		prev_unlocks = unlocks
		_validate_spawns(level, lanes, zombies, prefix, errors)
		if (
			level.get("mods", {}).get("conveyor", false)
			and not (level.get("conveyor") is Dictionary)
		):
			errors.append("%s: conveyor-Mod ohne conveyor-Daten" % prefix)
		var boss: Variant = level.get("boss")
		if boss is Dictionary and not zombies.has(str(boss.get("type", ""))):
			errors.append("%s: unbekannter Boss-Typ" % prefix)
	return errors


## JSON-Dictionary robust lesen (kaputt/fehlend → {}).
static func read_json(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_warning("[gvz] JSON kaputt oder fehlt: %s" % path)
		return {}
	return json.data


static func _validate_spawns(
	level: Dictionary, lanes: Array, zombies: Dictionary, prefix: String, errors: PackedStringArray
) -> void:
	var last_t := -1.0
	for spawn: Variant in level.get("spawns", []):
		if not (spawn is Dictionary):
			errors.append("%s: Spawn ist kein Dictionary" % prefix)
			continue
		var typ := str(spawn.get("type", ""))
		if not zombies.has(typ):
			errors.append("%s: unbekannter Zombie '%s'" % [prefix, typ])
		var lane := int(spawn.get("lane", -1))
		if lane != -1 and not lanes.has(lane):
			errors.append("%s: Spawn-Reihe %d inaktiv" % [prefix, lane])
		var t := float(spawn.get("t", -1.0))
		if t < last_t:
			errors.append("%s: Spawns nicht zeitlich sortiert" % prefix)
		last_t = t


static func _autoload_registry() -> Object:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var root := (loop as SceneTree).root
	if root == null:
		return null
	# Relativer Pfad: funktioniert auch außerhalb eines aktiven Baums (Tests).
	return root.get_node_or_null(NodePath("ContentRegistry"))


static func _deep_merge(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source:
		if source[key] is Dictionary and target.get(key) is Dictionary:
			_deep_merge(target[key], source[key])
		else:
			target[key] = source[key]


## JSON kennt nur double — ganze Zahlen werden rekursiv zu int
## (Sekunden-Zeiten "t" ausgenommen, s. FLOAT_KEYS).
static func _intify(value: Variant, key := "") -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if not FLOAT_KEYS.has(key) and f == floorf(f):
				return int(f)
			return f
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			for k: Variant in dict:
				dict[k] = _intify(dict[k], str(k))
			return dict
		TYPE_ARRAY:
			var arr: Array = value
			for i in arr.size():
				arr[i] = _intify(arr[i], key)
			return arr
		_:
			return value
