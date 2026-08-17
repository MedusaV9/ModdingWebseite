class_name GobnomData
extends RefCounted
## Daten-Lader für GOB NOM (Doc G §5). Quelle der Wahrheit sind die
## Owned-JSONs unter data/; Balancing ist Content-Pack-updatebar über den
## Balance-Namespace "gobnom" der W2b-ContentRegistry (Muster = GvzData):
## ein Balance-Pack liefert `{"values": {"gobnom": {...}}}` und überschreibt
## per Deep-Merge jede Zahl aus gobnom_balance.json — neue Level-Packs ohne
## IPA (Doc G §5.4 "Level-Daten Content-Pack-updatebar").
## Anders als GvZ bleibt hier ALLES float (kontinuierliche 2D-Physik).

const BALANCE_PATH := "res://scripts/minigames/games/gobnom/data/gobnom_balance.json"
const LEVELS_PATH := "res://scripts/minigames/games/gobnom/data/gobnom_levels.json"
const BALANCE_NAMESPACE := "gobnom"

const CAMPAIGN_COUNT := 15
const COOP_COUNT := 10

## Element-Einführungs-Plan der Kampagne (Doc G §5.3-Tabelle, Fenster-Logik).
const CAMPAIGN_INTRO := {
	1: "rope",
	2: "ropes",
	3: "timing",
	4: "bubble",
	5: "bubble_rope",
	6: "cushion",
	7: "cushion_combo",
	8: "slider",
	9: "shooter",
	10: "spikes",
	11: "fan",
	12: "cloud",
	13: "all",
	14: "cut_limit",
	15: "finale",
}


## Effektive Balance: eingebautes JSON + Registry-Override (Namespace
## "gobnom"). registry=null → Autoload /root/ContentRegistry (Duck-Typing;
## fehlt es, z. B. in Pure-Tests, gilt der eingebaute Stand).
static func load_balance(registry: Object = null) -> Dictionary:
	var balance := read_json(BALANCE_PATH)
	var reg := registry if registry != null else _autoload_registry()
	if reg != null and reg.has_method("get_balance"):
		var overrides: Variant = reg.get_balance(BALANCE_NAMESPACE, {})
		if overrides is Dictionary and not (overrides as Dictionary).is_empty():
			_deep_merge(balance, overrides)
	return balance


## Alle Kampagnen-Level (Array[Dictionary], ids 1..15, kind "campaign").
static func load_campaign() -> Array:
	return _load_track("campaign")


## Alle Coop-Level (ids 1..10, kind "coop", mit split-Metadaten).
static func load_coop() -> Array:
	return _load_track("coop")


## Level per Track + Id (leeres Dictionary, wenn unbekannt).
static func level_by_id(levels: Array, id: int) -> Dictionary:
	for level: Variant in levels:
		if level is Dictionary and int(level.get("id", 0)) == id:
			return level
	return {}


## Strukturelle Validierung beider Tracks gegen die Balance.
## Liefert eine (leere) Liste menschenlesbarer Fehler.
static func validate_levels(campaign: Array, coop: Array, balance: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if campaign.size() != CAMPAIGN_COUNT:
		errors.append(
			"erwartet %d Kampagnen-Level, gefunden %d" % [CAMPAIGN_COUNT, campaign.size()]
		)
	if coop.size() != COOP_COUNT:
		errors.append("erwartet %d Coop-Level, gefunden %d" % [COOP_COUNT, coop.size()])
	var world: Dictionary = balance.get("world", {})
	for i in campaign.size():
		var level: Dictionary = campaign[i]
		var prefix := "L%02d" % int(level.get("id", -1))
		if int(level.get("id", -1)) != i + 1:
			errors.append("%s: id nicht fortlaufend" % prefix)
		if str(level.get("intro", "")) != str(CAMPAIGN_INTRO.get(i + 1, "")):
			errors.append("%s: intro-Tag weicht von der Doc-G-§5.3-Tabelle ab" % prefix)
		_validate_level(level, world, prefix, false, errors)
	for i in coop.size():
		var level: Dictionary = coop[i]
		var prefix := "CN%d" % int(level.get("id", -1))
		if int(level.get("id", -1)) != i + 1:
			errors.append("%s: id nicht fortlaufend" % prefix)
		_validate_level(level, world, prefix, true, errors)
	return errors


## JSON-Dictionary robust lesen (kaputt/fehlend → {}).
static func read_json(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_warning("[gobnom] JSON kaputt oder fehlt: %s" % path)
		return {}
	return json.data


static func _load_track(key: String) -> Array:
	var doc := read_json(LEVELS_PATH)
	var levels: Variant = doc.get(key, [])
	if not (levels is Array):
		return []
	for level: Variant in levels:
		if level is Dictionary:
			level["kind"] = key
	return levels


static func _validate_level(
	level: Dictionary, world: Dictionary, prefix: String, coop: bool, errors: PackedStringArray
) -> void:
	if not (level.get("candy") is Dictionary):
		errors.append("%s: candy fehlt" % prefix)
	if not (level.get("mouth") is Dictionary):
		errors.append("%s: mouth fehlt" % prefix)
	var jars: Array = level.get("jars", [])
	if jars.size() != 3:
		errors.append("%s: genau 3 Nutella-Gläser erwartet (sind %d)" % [prefix, jars.size()])
	var solution: Dictionary = level.get("solution", {})
	if (solution.get("actions", []) as Array).is_empty():
		errors.append("%s: Lösungs-Plan fehlt (Lösbarkeits-Beweis!)" % prefix)
	_validate_positions(level, world, prefix, errors)
	if not coop:
		return
	var split: Dictionary = level.get("split", {})
	if split.is_empty() or not ["x", "y"].has(str(split.get("axis", ""))):
		errors.append("%s: Coop ohne split_axis" % prefix)
	# Explizite owner-Tags müssen a/b sein (ohne Tag gilt die Bildschirmhälfte).
	for key in ["ropes", "cushions", "fans", "shooters"]:
		for row: Dictionary in level.get(key, []):
			if row.has("owner") and not ["a", "b"].has(str(row["owner"])):
				errors.append("%s: %s-owner muss a/b sein" % [prefix, key])
	# Die echte Coop-Invariante: der Lösungs-Plan braucht BEIDE Spieler
	# (Doc G §5.4 geteilte Kontrolle — kein Level ist allein lösbar gedacht).
	var players := {}
	for action: Dictionary in level.get("solution", {}).get("actions", []):
		players[str(action.get("player", ""))] = true
	if not (players.has("a") and players.has("b")):
		errors.append("%s: Lösung braucht Aktionen von Spieler a UND b" % prefix)


static func _validate_positions(
	level: Dictionary, world: Dictionary, prefix: String, errors: PackedStringArray
) -> void:
	var w := float(world.get("w", 960.0))
	var h := float(world.get("h", 540.0))
	for key in ["ropes", "bubbles", "cushions", "fans", "shooters", "jars"]:
		for row: Dictionary in level.get(key, []):
			var x := float(row.get("x", 0.0))
			var y := float(row.get("y", 0.0))
			if x < 0.0 or x > w or y < 0.0 or y > h:
				errors.append("%s: %s außerhalb der Welt (%d,%d)" % [prefix, key, x, y])


static func _autoload_registry() -> Object:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var root := (loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null(NodePath("ContentRegistry"))


static func _deep_merge(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source:
		if source[key] is Dictionary and target.get(key) is Dictionary:
			_deep_merge(target[key], source[key])
		else:
			target[key] = source[key]
