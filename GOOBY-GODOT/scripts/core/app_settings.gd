extends Node
## AppSettings — persistente, GameState-UNABHÄNGIGE App-Einstellungen (W1a).
##
## Speichert nach user://settings.json (JSON, atomar via tmp+rename).
## Contract nach W1 FROZEN (siehe /tmp/gooby-godot/handoffs/W1a-core.md):
## Keys: language ("de" Default), reduced_motion (bool), doors_animated (bool),
## orientation_mode ("auto"|"landscape"|"portrait"),
## audio.master / audio.music / audio.sfx (float 0..1).
## Verschachtelte Keys werden mit Punkt adressiert: get_setting("audio.music").

signal setting_changed(key: String, value: Variant)

const DEFAULT_PATH := "user://settings.json"
const ORIENTATION_MODES: Array[String] = ["auto", "landscape", "portrait"]

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


func settings_path() -> String:
	return _path


func reload() -> void:
	_data = _defaults()
	_load()


static func _defaults() -> Dictionary:
	return {
		"version": 1,
		"language": "de",
		"reduced_motion": false,
		"doors_animated": true,
		"door_confirmation": true,
		"orientation_mode": "auto",
		"audio": {"master": 1.0, "music": 1.0, "sfx": 1.0},
	}


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
		_merge_into_data(json.data)
	else:
		push_warning("AppSettings: %s ist korrupt — Defaults bleiben aktiv." % _path)


func _merge_into_data(loaded: Dictionary) -> void:
	for key in loaded.keys():
		if key == "audio" and loaded[key] is Dictionary:
			for bus in (loaded[key] as Dictionary).keys():
				_data["audio"][bus] = loaded[key][bus]
		else:
			_data[key] = loaded[key]


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
