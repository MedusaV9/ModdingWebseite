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
##
## I/O-Fehlerpfade (EVAL-2026-08/C Befund 14): ALLE Datei-Operationen
## laufen über die injizierbare SaveIo-Fassade (unten; Produktion = direkte
## Godot-Aufrufe) und ihre Ergebnisse werden geprüft:
## - Scheitert Öffnen/Schreiben/Flush der .tmp (volle Platte, Permission),
##   bricht save_now VOR Rotation und Rename ab — halbgeschriebene Daten
##   erreichen weder die Hauptdatei noch die Backup-Kette.
## - Scheitert das finale Rename, bleibt die alte Hauptdatei (bzw. .tmp als
##   neuester voll geflushter Stand) erhalten — nie ein Zustand, in dem
##   weder alte noch neue Datei gültig ist.
## - Rotations-Fehler (remove/rename der .bakN) sind nicht fatal — der NEUE
##   Stand ist wichtiger als Backup-Generationen — aber sichtbar (Warnung).
## - Jeder Fehlschlag feuert save_fehlgeschlagen, steht in letzter_fehler()
##   und lässt den Zustand dirty: autosave_tick versucht es nach einem
##   weiteren Debounce-Fenster erneut (Retry statt stillem Datenverlust).

## Befund 14: sichtbarer Fehlerpfad — feuert bei JEDEM fehlgeschlagenen
## save_now() mit menschenlesbarem Grund (UI/Telemetrie können anhängen).
signal save_fehlgeschlagen(fehler: String)

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const MigrationV4 := preload("res://scripts/state/migration_v4.gd")

const BACKUP_GENERATIONS := 3
const DEFAULT_DEBOUNCE_MS := 800

var save_path := "user://save_v5.json"
var debounce_ms := DEFAULT_DEBOUNCE_MS
## I/O-Fassade (Befund 14): Produktionspfad bleibt der direkte Godot-Aufruf
## (eine Dispatch-Ebene, kein messbarer Overhead); Tests injizieren eine
## Unterklasse mit Fehlerhaken (volle Platte/Permission/Rename/Crash).
var io := SaveIo.new()

var _dirty_at_ticks := -1
var _letzter_fehler := ""


## Load the save. Never fails hard — always returns a usable state.
## Returns {"state", "fresh": bool, "recovered": bool, "source": String}.
func load_state(now_ms: int) -> Dictionary:
	if not io.existiert(save_path):
		return _recover_missing(now_ms)
	var raw := io.lese_string(save_path)
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
	if io.existiert(tmp):
		var tmp_parsed := _parse_and_normalize(io.lese_string(tmp), now_ms)
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
		if not io.existiert(bak):
			continue
		var bak_parsed := _parse_and_normalize(io.lese_string(bak), now_ms)
		if bak_parsed["ok"]:
			return {
				"state": bak_parsed["state"],
				"fresh": false,
				"recovered": true,
				"source": "bak%d" % gen,
			}
	return {}


## Persist immediately: atomic tmp+rename with backup rotation. Befund 14:
## Jeder I/O-Schritt wird geprüft; false = Save NICHT persistiert (Grund in
## letzter_fehler(), Signal gefeuert, Dateibestand konsistent — s. Kopf).
func save_now(state: Dictionary) -> bool:
	var json := JSON.stringify(state)
	var tmp := save_path + ".tmp"
	var f := io.oeffne_schreiben(tmp)
	if f == null:
		return _save_fehler(
			"kann %s nicht öffnen (%s)" % [tmp, error_string(io.letzter_open_fehler())]
		)
	var geschrieben := io.schreibe_string(f, json)
	var flush_fehler := io.flushe(f)
	f.close()
	if not geschrieben or flush_fehler != OK:
		# Halbgeschriebene .tmp (volle Platte) NIE zur Hauptdatei machen —
		# weder Rotation noch Rename anfassen, alter Save bleibt gültig.
		var detail := (
			error_string(flush_fehler)
			if flush_fehler != OK
			else "store_string unvollständig — volle Platte?"
		)
		return _save_fehler("Schreiben nach %s fehlgeschlagen (%s)" % [tmp, detail])
	_rotate_backups()
	var rename_fehler := io.benenne_um(tmp, save_path)
	if rename_fehler != OK:
		# Alte Hauptdatei existiert noch (oder .tmp ist der neueste voll
		# geflushte Stand und wird beim Laden bevorzugt) — konsistent.
		return _save_fehler(
			"rename %s → %s fehlgeschlagen (%s)" % [tmp, save_path, error_string(rename_fehler)]
		)
	_dirty_at_ticks = -1
	_letzter_fehler = ""
	return true


## Menschenlesbarer Grund des letzten fehlgeschlagenen save_now()
## ("" = letzter Save war erfolgreich).
func letzter_fehler() -> String:
	return _letzter_fehler


## Autosave-Debounce: mark the state dirty; autosave_tick() flushes once the
## debounce window elapsed (ticks_ms = monotonic Time.get_ticks_msec()).
func mark_dirty(ticks_ms: int) -> void:
	if _dirty_at_ticks < 0:
		_dirty_at_ticks = ticks_ms


func is_dirty() -> bool:
	return _dirty_at_ticks >= 0


## Returns true when a flush happened. Befund 14: Schlägt der Save fehl,
## bleibt der Zustand dirty und der nächste Versuch startet nach einem
## weiteren Debounce-Fenster (Retry statt I/O-Hämmern pro Tick).
func autosave_tick(state: Dictionary, ticks_ms: int) -> bool:
	if _dirty_at_ticks < 0 or ticks_ms - _dirty_at_ticks < debounce_ms:
		return false
	if save_now(state):
		return true
	_dirty_at_ticks = ticks_ms
	return false


## Flush pending changes (app quit / scene change). Befund 14: false bei
## I/O-Fehler — der Zustand bleibt dirty, der Aufrufer sieht den Fehlschlag.
func flush_if_dirty(state: Dictionary) -> bool:
	if _dirty_at_ticks < 0:
		return false
	return save_now(state)


func corrupt_path() -> String:
	return save_path + ".corrupt"


func _backup_path(generation: int) -> String:
	return "%s.bak%d" % [save_path, generation]


## Fehlschlag sichtbar machen (Befund 14): ERROR im Log, Grund abfragbar,
## Signal für UI/Telemetrie — und false für den Aufrufer.
func _save_fehler(grund: String) -> bool:
	_letzter_fehler = grund
	push_error("[save_manager] Save fehlgeschlagen: %s" % grund)
	save_fehlgeschlagen.emit(grund)
	return false


## Backup-Rotation .bak2→.bak3, .bak1→.bak2, save→.bak1. Fehler einzelner
## Schritte (remove/rename) sind nicht fatal — der NEUE Save ist wichtiger
## als Backup-Generationen, und das finale Rename in save_now überschreibt
## die Hauptdatei atomar (nie alte UND neue Datei ungültig) — aber jedes
## Problem wird als Warnung sichtbar statt still verschluckt (Befund 14).
func _rotate_backups() -> void:
	if not io.existiert(save_path):
		return
	var last := _backup_path(BACKUP_GENERATIONS)
	if io.existiert(last):
		var remove_fehler := io.entferne(last)
		if remove_fehler != OK:
			push_warning(
				"[save_manager] Rotation: remove %s (%s)" % [last, error_string(remove_fehler)]
			)
	for gen in range(BACKUP_GENERATIONS - 1, 0, -1):
		var from := _backup_path(gen)
		if io.existiert(from):
			var shift_fehler := io.benenne_um(from, _backup_path(gen + 1))
			if shift_fehler != OK:
				push_warning(
					(
						"[save_manager] Rotation: rename %s → %s (%s)"
						% [from, _backup_path(gen + 1), error_string(shift_fehler)]
					)
				)
	var bak1_fehler := io.benenne_um(save_path, _backup_path(1))
	if bak1_fehler != OK:
		push_warning(
			(
				"[save_manager] Rotation: rename %s → %s (%s) — Generation übersprungen"
				% [save_path, _backup_path(1), error_string(bak1_fehler)]
			)
		)


func _backup_corrupt(raw: String) -> void:
	var f := io.oeffne_schreiben(corrupt_path())
	if f == null:
		push_warning("[save_manager] .corrupt nicht schreibbar (%s)" % corrupt_path())
		return
	var ok := io.schreibe_string(f, raw)
	var flush_fehler := io.flushe(f)
	f.close()
	if not ok or flush_fehler != OK:
		push_warning("[save_manager] .corrupt unvollständig (%s)" % corrupt_path())


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


class SaveIo:
	extends RefCounted
	## I/O-Fassade des Save-Managers (Befund 14): Die Produktions-
	## Implementation ruft Godot direkt auf; Fault-Injection-Tests
	## (tests/tools/fake_save_io.gd) überschreiben einzelne Operationen,
	## um volle Platte, Permission-Fehler, Rename-Failure und Crash-Fenster
	## zwischen Rotationsschritten deterministisch zu simulieren.

	func existiert(pfad: String) -> bool:
		return FileAccess.file_exists(pfad)

	func lese_string(pfad: String) -> String:
		return FileAccess.get_file_as_string(pfad)

	func oeffne_schreiben(pfad: String) -> FileAccess:
		return FileAccess.open(pfad, FileAccess.WRITE)

	## Fehlgrund des letzten oeffne_schreiben-null (getrennt, damit Fakes
	## einen eigenen Grund liefern können — get_open_error ist global).
	func letzter_open_fehler() -> Error:
		return FileAccess.get_open_error()

	## true = vollständig geschrieben (store_string meldet volle Platte).
	func schreibe_string(f: FileAccess, text: String) -> bool:
		return f.store_string(text)

	func flushe(f: FileAccess) -> Error:
		f.flush()
		return f.get_error()

	func benenne_um(von: String, nach: String) -> Error:
		return DirAccess.rename_absolute(
			ProjectSettings.globalize_path(von), ProjectSettings.globalize_path(nach)
		)

	func entferne(pfad: String) -> Error:
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(pfad))
