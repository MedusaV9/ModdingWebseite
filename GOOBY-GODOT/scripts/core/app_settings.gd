extends Node
## AppSettings — persistente, GameState-UNABHÄNGIGE App-Einstellungen (W1a).
##
## Speichert nach user://settings.json (JSON, atomar via tmp+rename).
## Contract nach W1 FROZEN (siehe /tmp/gooby-godot/handoffs/W1a-core.md):
## Keys: language ("de" Default), reduced_motion (bool), doors_animated (bool),
## orientation_mode ("auto"|"landscape"|"portrait"),
## audio.master / audio.music / audio.sfx (float 0..1).
## Verschachtelte Keys werden mit Punkt adressiert: get_setting("audio.music").
##
## RW-7 (Doc RANCH-DLC-IDEAS-4 §4.4): Schema-Version 2 ergänzt versionierte
## Gruppen graphics.* / display.* / controls.* / accessibility.* /
## notifications.* / game.* / dev.* plus audio.voice. Alle neuen Werte werden
## beim LESEN normalisiert (unbekannt/ungültig → sicherer Default), Version-1-
## Dateien laden unverändert weiter (fehlende Gruppen = Defaults). Die
## Wertebereiche sind in VALID_* dokumentiert; wer wirkt wohin steht im
## Anwendungs-Service `scripts/platform/quality_service.gd`.

signal setting_changed(key: String, value: Variant)

const DEFAULT_PATH := "user://settings.json"
const SCHEMA_VERSION := 2
const ORIENTATION_MODES: Array[String] = ["auto", "landscape", "portrait"]
## Erlaubte Aufzählungswerte pro Punkt-Pfad (Normalisierung beim Lesen;
## Index 0 = Default). Zahlenbereiche stehen in VALID_RANGES.
const VALID_ENUMS := {
	"graphics.preset": ["auto", "niedrig", "mittel", "hoch", "benutzerdefiniert"],
	"graphics.msaa": ["2x", "aus", "4x"],
	"graphics.shadows": ["hoch", "aus", "niedrig"],
	"graphics.post_fx": ["dezent", "aus", "hoch"],
	"controls.handedness": ["rechts", "links"],
	"controls.scheme": ["stick", "zuegel"],
	"controls.haptics": ["normal", "aus", "dezent", "stark"],
	"accessibility.color_vision": ["aus", "protan", "deutan", "tritan"],
	"accessibility.hint_duration": ["normal", "lang"],
}
## Zahlbereiche pro Punkt-Pfad: [min, max, default].
const VALID_RANGES := {
	"graphics.scale_3d": [0.5, 1.0, 1.0],
	"graphics.fps": [30.0, 120.0, 60.0],
	"graphics.draw_distance": [0.7, 1.0, 1.0],
	"graphics.particles": [0.0, 1.0, 1.0],
	"display.ui_scale": [0.85, 1.3, 1.0],
	"display.text_scale": [1.0, 1.5, 1.0],
	"display.safe_area_extra": [0.0, 24.0, 0.0],
	"notifications.quiet_from": [0.0, 23.0, 21.0],
	"notifications.quiet_to": [0.0, 23.0, 8.0],
}
## Erlaubte Bildraten (alles andere rundet auf den nächsten Eintrag).
const FPS_STEPS: Array[int] = [30, 60, 120]

var _path: String
var _data: Dictionary = {}


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path
	_data = _defaults()
	_load()


func get_setting(key: String, default_value: Variant = null) -> Variant:
	var node: Variant = _data
	for part in key.split("."):
		if node is Dictionary and (node as Dictionary).has(part):
			node = node[part]
		else:
			return default_value
	return node


func set_setting(key: String, value: Variant) -> void:
	var parts := key.split(".")
	var node: Dictionary = _data
	for i in range(parts.size() - 1):
		if not (node.get(parts[i]) is Dictionary):
			node[parts[i]] = {}
		node = node[parts[i]]
	node[parts[parts.size() - 1]] = value
	_save()
	setting_changed.emit(key, value)


func language() -> String:
	return String(get_setting("language", "de"))


func is_reduced_motion() -> bool:
	return bool(get_setting("reduced_motion", false))


func are_doors_animated() -> bool:
	return bool(get_setting("doors_animated", true))


## FIX-3 (User-Wunsch): Bestätigungs-Dialog vor Tür-Reisen im Haus —
## Default AN, im Settings-Screen abschaltbar.
func is_door_confirmation_enabled() -> bool:
	return bool(get_setting("door_confirmation", true))


func orientation_mode() -> String:
	var mode := String(get_setting("orientation_mode", "auto"))
	return mode if ORIENTATION_MODES.has(mode) else "auto"


func audio_level(bus: String) -> float:
	return clampf(float(get_setting("audio." + bus, 1.0)), 0.0, 1.0)


## RW-7: normalisierter Zugriff auf einen versionierten Wert (VALID_ENUMS/
## VALID_RANGES). Unbekannter Pfad → null + Fehler (Tippfehler-Schutz).
func value_of(key: String) -> Variant:
	if VALID_ENUMS.has(key):
		var allowed: Array = VALID_ENUMS[key]
		var raw := String(get_setting(key, allowed[0]))
		return raw if allowed.has(raw) else allowed[0]
	if VALID_RANGES.has(key):
		var range_def: Array = VALID_RANGES[key]
		var number: Variant = get_setting(key, range_def[2])
		if not (number is float or number is int):
			return float(range_def[2])
		if key == "graphics.fps":
			return float(_nearest_fps(int(number)))
		return clampf(float(number), float(range_def[0]), float(range_def[1]))
	push_error("AppSettings.value_of: unbekannter Key '%s'." % key)
	return null


## RW-7: Bool-Schalter mit Default aus den v2-Defaults (fehlend → Default).
func is_on(key: String) -> bool:
	var fallback: Variant = _default_at(key)
	return bool(get_setting(key, fallback if fallback != null else false))


## RW-7: Benachrichtigungs-Gate — Master UND Kategorie müssen an sein.
## Kategorien: pflege, warte, fohlen, turnier, freund.
func notify_allowed(category: String) -> bool:
	if not is_on("notifications.enabled"):
		return false
	return is_on("notifications." + category)


func is_dev_enabled() -> bool:
	return bool(get_setting("dev.enabled", false))


func settings_path() -> String:
	return _path


func reload() -> void:
	_data = _defaults()
	_load()


static func _defaults() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"language": "de",
		"reduced_motion": false,
		"doors_animated": true,
		"door_confirmation": true,
		"orientation_mode": "auto",
		"audio": {"master": 1.0, "music": 1.0, "sfx": 1.0, "voice": 1.0},
		"graphics":
		{
			"preset": "auto",
			"scale_3d": 1.0,
			"fps": 60,
			"msaa": "2x",
			"shadows": "hoch",
			"draw_distance": 1.0,
			"particles": 1.0,
			"post_fx": "dezent",
		},
		"display": {"ui_scale": 1.0, "text_scale": 1.0, "safe_area_extra": 0},
		"controls":
		{"handedness": "rechts", "scheme": "stick", "steering_assist": true, "haptics": "normal"},
		"accessibility": {"color_vision": "aus", "high_contrast": false, "hint_duration": "normal"},
		"notifications":
		{
			"enabled": true,
			"pflege": true,
			"warte": true,
			"fohlen": true,
			"turnier": true,
			"freund": true,
			"quiet_hours": true,
			"quiet_from": 21,
			"quiet_to": 8,
		},
		"game": {"autosave": true},
		"dev": {"enabled": false},
	}


func _default_at(key: String) -> Variant:
	var node: Variant = _defaults()
	for part in key.split("."):
		if node is Dictionary and (node as Dictionary).has(part):
			node = node[part]
		else:
			return null
	return node


func _nearest_fps(raw: int) -> int:
	var best: int = FPS_STEPS[0]
	for step in FPS_STEPS:
		if absi(raw - step) < absi(raw - best):
			best = step
	return best


func _load() -> void:
	if not FileAccess.file_exists(_path):
		return
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return
	# JSON-Instanz statt JSON.parse_string: loggt bei Korruption keinen
	# Engine-ERROR, wir degradieren kontrolliert auf die Defaults.
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		_merge_into_data(_data, json.data)
		_data["version"] = SCHEMA_VERSION
	else:
		push_warning("AppSettings: %s ist korrupt — Defaults bleiben aktiv." % _path)


## Tief mergen: Dictionaries aus den Defaults behalten fehlende Unterschlüssel
## (Version-1-Dateien bekommen so alle v2-Gruppen als Defaults dazu).
static func _merge_into_data(target: Dictionary, loaded: Dictionary) -> void:
	for key in loaded.keys():
		if target.get(key) is Dictionary and loaded[key] is Dictionary:
			_merge_into_data(target[key], loaded[key])
		else:
			target[key] = loaded[key]


func _save() -> void:
	var tmp_path := _path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("AppSettings: kann %s nicht schreiben." % tmp_path)
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(_path)
	)
	if err != OK:
		push_error("AppSettings: rename %s -> %s fehlgeschlagen (%d)." % [tmp_path, _path, err])
