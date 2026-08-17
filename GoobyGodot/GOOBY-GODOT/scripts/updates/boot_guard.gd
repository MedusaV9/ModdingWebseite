class_name BootGuard
extends RefCounted
## Boot-Guard-Statemaschine (Doc B §2.5, 2-Crash-Regel; W2b UPDATES).
##
## Persistierter Versuchszähler in user://boot_guard.json: `begin_boot()` zählt
## VOR dem Pack-Load hoch, `mark_boot_ok()` nullt nach erreichtem Hauptmenü.
## Ein Crash dazwischen hinterlässt attempts >= 1:
##   Versuch 1 → NORMAL (Zufalls-Crash, normaler Retry)
##   Versuch 2 → DISABLE_NEWEST (jüngstes nicht-bewährtes Pack deaktivieren)
##   Versuch >= 3 → SAFE_MODE (alle user-Packs aus, Spiel bleibt IMMER spielbar)
## Kein Crash-Handler nötig — Zähler + „sauber genullt“ ist die robuste Lösung.

enum Decision { NORMAL, DISABLE_NEWEST, SAFE_MODE }

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://boot_guard.json"

var path := DEFAULT_PATH
var attempts := 0
var last_ok_unix := 0


## Lädt (oder initialisiert) den Guard an einem Pfad. Tests injizieren eigene Pfade.
static func open(guard_path := DEFAULT_PATH) -> BootGuard:
	var guard := BootGuard.new()
	guard.path = guard_path
	guard.load_state()
	return guard


## Reine Entscheidungsfunktion (unit-testbar ohne Dateisystem).
static func decision_for_attempts(attempt_count: int) -> int:
	if attempt_count >= 3:
		return Decision.SAFE_MODE
	if attempt_count == 2:
		return Decision.DISABLE_NEWEST
	return Decision.NORMAL


func load_state() -> void:
	attempts = 0
	last_ok_unix = 0
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		push_warning("boot_guard.json kaputt — Zähler startet bei 0: %s" % path)
		return
	var data: Dictionary = json.data
	attempts = int(data.get("attempts", 0))
	last_ok_unix = int(data.get("last_ok_unix", 0))


## Boot-Versuch registrieren: Zähler +1, SOFORT persistieren, Entscheidung zurück.
func begin_boot() -> int:
	attempts += 1
	_persist()
	return decision_for_attempts(attempts)


## Erfolgs-Boot (Hauptmenü erreicht): Zähler nullen.
func mark_boot_ok(now_unix := -1) -> void:
	attempts = 0
	last_ok_unix = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	_persist()


func _persist() -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("boot_guard.json nicht schreibbar: %s" % path)
		return
	var data := {
		"schema": SCHEMA_VERSION,
		"attempts": attempts,
		"last_ok_unix": last_ok_unix,
	}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
