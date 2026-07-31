extends RefCounted
## Save-Manager (W1d/STATE): user://save_v5.json — atomar (tmp+rename),
## Autosave-Debounce, 3-Generationen-Backup-Rotation, Korruptions-Recovery.
##
## Design (Port der Web-save.js-Garantien auf Dateien):
## - save_now(): schreibt nach <path>.tmp, flusht, benennt dann atomar um.
##   Vor dem Rename rotiert der alte Save durch .bak1 → .bak2 → .bak3
##   (eine "Generation" == ein erfolgreicher Flush).
## - load_state(): parse → (v<5: Migrationskette via migration_v4.gd) →
##   SaveSchema.normalize. Jeder Fehler ist NICHT fatal: die Rohdatei wird
##   nach <path>.corrupt gesichert und .bak1..3 werden der Reihe nach
##   probiert; wenn alles scheitert → frischer Default-State (recovered=true,
##   wie web load() — bootet IMMER).
## - FEHLT die Hauptdatei (Crash/App-Kill im save_now()-Fenster zwischen
##   Backup-Rotation und Rename): erst .tmp probieren (voll geflusht = der
##   NEUESTE Stand), dann .bak1..3; erst wenn alles fehlt/kaputt ist, gilt
##   der Boot als echter Erststart (fresh=true).
##   Existiert die Hauptdatei dagegen, wird ein liegengebliebenes .tmp
##   bewusst ignoriert (nicht unterscheidbar von einem Teil-Schreibrest;
##   der nächste save_now() überschreibt es ohnehin per Truncate).
## - Debounce: mark_dirty() + autosave_tick(state, ticks_ms) — der Aufrufer
##   (GameState._process) pumpt monotone Ticks; Zeitlogik bleibt headless
##   testbar ohne Frames.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const MigrationV4 := preload("res://scripts/state/migration_v4.gd")

const BACKUP_GENERATIONS := 3
const DEFAULT_DEBOUNCE_MS := 800

var save_path := "user://save_v5.json"
var debounce_ms := DEFAULT_DEBOUNCE_MS

var _dirty_at_ticks := -1


## Load the save. Never fails hard — always returns a usable state.
## Returns {"state", "fresh": bool, "recovered": bool, "source": String}.
func load_state(now_ms: int) -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return _recover_missing(now_ms)
	var raw := FileAccess.get_file_as_string(save_path)
	var parsed := _parse_and_normalize(raw, now_ms)
	if parsed["ok"]:
		return {"state": parsed["state"], "fresh": false, "recovered": false, "source": "save"}
	push_warning("[save_manager] corrupt save (%s) — trying backups" % parsed["error"])
	_backup_corrupt(raw)
	var from_backup := _recover_from_backups(now_ms)
	if not from_backup.is_empty():
		return from_backup
	return {
		"state": SaveSchema.default_state(now_ms),
		"fresh": false,
		"recovered": true,
		"source": "fresh",
	}


## Hauptdatei fehlt = Crash-Fenster von save_now(): die Rotation hat den
## alten Save schon nach .bak1 geschoben, der Rename .tmp → save kam nicht
## mehr. .tmp ist dann der NEUESTE voll geflushte Stand — zuerst probieren,
## danach .bak1..N. Erst wenn ALLES fehlt/kaputt ist: echter Erststart.
func _recover_missing(now_ms: int) -> Dictionary:
	var tmp := save_path + ".tmp"
	if FileAccess.file_exists(tmp):
		var tmp_parsed := _parse_and_normalize(FileAccess.get_file_as_string(tmp), now_ms)
		if tmp_parsed["ok"]:
			push_warning("[save_manager] save fehlt — aus .tmp wiederhergestellt")
			return {
				"state": tmp_parsed["state"], "fresh": false, "recovered": true, "source": "tmp"
			}
	var from_backup := _recover_from_backups(now_ms)
	if not from_backup.is_empty():
		push_warning("[save_manager] save fehlt — aus %s wiederhergestellt" % from_backup["source"])
		return from_backup
	return {
		"state": SaveSchema.default_state(now_ms),
		"fresh": true,
		"recovered": false,
		"source": "fresh",
	}


## Probiert .bak1..N der Reihe nach (parse+normalize wie der Korrupt-Pfad).
## Leeres Dict, wenn keine Generation brauchbar ist.
func _recover_from_backups(now_ms: int) -> Dictionary:
	for gen in range(1, BACKUP_GENERATIONS + 1):
		var bak := _backup_path(gen)
		if not FileAccess.file_exists(bak):
			continue
		var bak_parsed := _parse_and_normalize(FileAccess.get_file_as_string(bak), now_ms)
		if bak_parsed["ok"]:
			return {
				"state": bak_parsed["state"],
				"fresh": false,
				"recovered": true,
				"source": "bak%d" % gen,
			}
	return {}


## Persist immediately: atomic tmp+rename with backup rotation.
func save_now(state: Dictionary) -> bool:
	_dirty_at_ticks = -1
	var json := JSON.stringify(state)
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("[save_manager] cannot open %s (%s)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(json)
	f.flush()
	f = null  # closes the file
	_rotate_backups()
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_path)
	)
	if err != OK:
		push_warning("[save_manager] rename failed: %s" % error_string(err))
		return false
	return true


## Autosave-Debounce: mark the state dirty; autosave_tick() flushes once the
## debounce window elapsed (ticks_ms = monotonic Time.get_ticks_msec()).
func mark_dirty(ticks_ms: int) -> void:
	if _dirty_at_ticks < 0:
		_dirty_at_ticks = ticks_ms


func is_dirty() -> bool:
	return _dirty_at_ticks >= 0


## Returns true when a flush happened.
func autosave_tick(state: Dictionary, ticks_ms: int) -> bool:
	if _dirty_at_ticks < 0 or ticks_ms - _dirty_at_ticks < debounce_ms:
		return false
	return save_now(state)


## Flush pending changes (app quit / scene change).
func flush_if_dirty(state: Dictionary) -> bool:
	if _dirty_at_ticks < 0:
		return false
	return save_now(state)


func corrupt_path() -> String:
	return save_path + ".corrupt"


func _backup_path(generation: int) -> String:
	return "%s.bak%d" % [save_path, generation]


func _rotate_backups() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var last := _backup_path(BACKUP_GENERATIONS)
	if FileAccess.file_exists(last):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(last))
	for gen in range(BACKUP_GENERATIONS - 1, 0, -1):
		var from := _backup_path(gen)
		if FileAccess.file_exists(from):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(from),
				ProjectSettings.globalize_path(_backup_path(gen + 1))
			)
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(_backup_path(1))
	)


func _backup_corrupt(raw: String) -> void:
	var f := FileAccess.open(corrupt_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(raw)
		f.flush()


## parse → migrate (v<5) → normalize. {"ok", "state", "error"}.
func _parse_and_normalize(raw: String, now_ms: int) -> Dictionary:
	var json := JSON.new()
	if json.parse(raw) != OK:
		return {"ok": false, "state": {}, "error": "invalid JSON: %s" % json.get_error_message()}
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return {"ok": false, "state": {}, "error": "save is not an object"}
	var v: Variant = parsed.get("v")
	var v_is_num := typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
	if v == null or (v_is_num and int(v) < SaveSchema.SCHEMA_VERSION):
		var migrated := MigrationV4.migrate_any(parsed, now_ms)
		if not migrated["ok"]:
			return {"ok": false, "state": {}, "error": migrated["error"]}
		parsed = migrated["state"]
	return SaveSchema.normalize(parsed, now_ms)
