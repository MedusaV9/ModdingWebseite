class_name PackLoaderService
extends Node
## Boot-Pack-Lader (Doc B §2.3/§2.5; W2b UPDATES). Autoload-Kandidat „PackLoader“
## (Request: handoffs/project-godot-requests.md — als ERSTES Autoload).
##
## Reihenfolge beim Boot:
##  1. Eingebaute Versionen aus res://content/*/pack.json lesen (VOR Overrides!).
##  2. Boot-Guard: attempts += 1 (sofort persistiert, user://boot_guard.json).
##  3. installed.json lesen; Guard-Entscheidung anwenden (2× → jüngstes Pack aus,
##     3× → Safe-Mode ohne Packs).
##  4. Stale-Cleanup: user-Version <= eingebaut → Datei löschen (nie „downgraden“);
##     min_native > App-Version → NIE laden (bleibt liegen bis zur neuen IPA).
##  5. ProjectSettings.load_resource_pack(...) in aufsteigender Priorität.
## Erfolgs-Boot (SceneRouter.travel_finished ODER Fallback-Timer) resettet den
## Guard und räumt `previous`-Dateien auf.

signal packs_loaded(loaded_ids: Array, boot_decision: int)
signal pack_disabled(pack_id: String, reason: String)
signal safe_mode_entered

const BOOT_OK_FALLBACK_SEC := 15.0

## Autoload-Betrieb: in _ready() laden + Erfolgs-Watch armieren. Tests: false setzen
## (VOR add_child) und die API direkt treiben.
var auto_boot := true
var packs_dir := "user://packs"
var guard_path := BootGuard.DEFAULT_PATH
var content_root := "res://content"
## Leer → ProjectSettings application/config/version (Fallback "5.0.0").
var app_version := ""
## Eingebaute Pack-Versionen, VOR dem ersten Override gecacht (für UpdateService).
var builtin_versions: Dictionary = {}
var boot_decision: int = BootGuard.Decision.NORMAL

var _guard: BootGuard
var _loaded_ids: Array[String] = []
var _boot_marked_ok := false


func _ready() -> void:
	if not auto_boot:
		return
	load_packs_at_boot()
	_arm_boot_success_watch()


func installed_path() -> String:
	return packs_dir + "/installed.json"


func resolve_app_version() -> String:
	if not app_version.is_empty():
		return app_version
	var from_project := str(ProjectSettings.get_setting("application/config/version", ""))
	return from_project if UpdatesManifest.is_semver(from_project) else "5.0.0"


func is_safe_mode() -> bool:
	return boot_decision == BootGuard.Decision.SAFE_MODE


func loaded_pack_ids() -> Array[String]:
	return _loaded_ids.duplicate()


## Kompletter Boot-Ladelauf. Rückgabe-Report:
## { "decision": int, "loaded": Array, "disabled": Array, "skipped": Array,
##   "cleaned": Array, "safe_mode": bool }
func load_packs_at_boot() -> Dictionary:
	_loaded_ids.clear()
	_boot_marked_ok = false
	builtin_versions = UpdatesManifest.read_builtin_versions(content_root)
	_guard = BootGuard.open(guard_path)
	boot_decision = _guard.begin_boot()
	var installed := UpdatesManifest.read_installed(installed_path())
	var report := {
		"decision": boot_decision,
		"loaded": [],
		"disabled": [],
		"skipped": [],
		"cleaned": [],
		"safe_mode": false,
	}
	if boot_decision == BootGuard.Decision.SAFE_MODE:
		_apply_safe_mode(installed, report)
	elif boot_decision == BootGuard.Decision.DISABLE_NEWEST:
		_disable_newest_pack(installed, report)
	if boot_decision != BootGuard.Decision.SAFE_MODE:
		_load_enabled_packs(installed, report)
	UpdatesManifest.write_installed(installed_path(), installed)
	packs_loaded.emit(report["loaded"], boot_decision)
	return report


## Hauptmenü erreicht: Guard nullen, überlebende Packs markieren, previous löschen.
func mark_boot_successful() -> void:
	if _boot_marked_ok:
		return
	_boot_marked_ok = true
	if _guard == null:
		_guard = BootGuard.open(guard_path)
	_guard.mark_boot_ok()
	var installed := UpdatesManifest.read_installed(installed_path())
	var packs: Dictionary = installed["packs"]
	for pack_id: String in _loaded_ids:
		if not packs.has(pack_id):
			continue
		var entry: Dictionary = packs[pack_id]
		entry["survived_boot"] = true
		var previous := str(entry.get("previous", ""))
		if not previous.is_empty():
			_remove_pack_file(previous)
			entry.erase("previous")
			entry.erase("previous_version")
	UpdatesManifest.write_installed(installed_path(), installed)


## W13C Soft-Restart (Doc B §2.4 / docs/UPDATES.md §5.5): user://-Packs neu
## mounten + Erfolgs-Watch neu armieren. Läuft BEWUSST durch den normalen
## Boot-Pfad inklusive Guard (attempts += 1): crasht die App mitten im
## Soft-Restart, greift beim nächsten Start dieselbe 2-Crash-Regel wie bei
## einem echten Boot — kein Sonderweg am Guard vorbei. Die erste danach
## abgeschlossene Router-Reise (bzw. der Fallback-Timer) nullt den Zähler
## wieder über mark_boot_successful().
func remount_for_soft_restart() -> Dictionary:
	var report := load_packs_at_boot()
	if is_inside_tree():
		_arm_boot_success_watch()
	return report


## „Erneut versuchen“-Banner nach Safe-Mode: alles wieder aktivieren + Guard nullen.
func reenable_all_packs() -> void:
	var installed := UpdatesManifest.read_installed(installed_path())
	for pack_id: String in installed["packs"]:
		installed["packs"][pack_id]["enabled"] = true
	UpdatesManifest.write_installed(installed_path(), installed)
	if _guard == null:
		_guard = BootGuard.open(guard_path)
	_guard.mark_boot_ok()


func _apply_safe_mode(installed: Dictionary, report: Dictionary) -> void:
	report["safe_mode"] = true
	for pack_id: String in installed["packs"]:
		var entry: Dictionary = installed["packs"][pack_id]
		if bool(entry.get("enabled", false)):
			entry["enabled"] = false
			report["disabled"].append(pack_id)
			pack_disabled.emit(pack_id, "safe_mode")
	safe_mode_entered.emit()


## 2. Crash: das zuletzt installierte, noch nicht bewährte Pack deaktivieren;
## existiert eine previous-Datei, wird darauf zurückgerollt (Doc B §2.5).
func _disable_newest_pack(installed: Dictionary, report: Dictionary) -> void:
	var newest_id := ""
	var newest_seq := -1
	for pack_id: String in installed["packs"]:
		var entry: Dictionary = installed["packs"][pack_id]
		if str(entry.get("type", "pck")) == "json":
			continue
		if not bool(entry.get("enabled", false)) or bool(entry.get("survived_boot", false)):
			continue
		var seq := int(entry.get("installed_seq", 0))
		if seq > newest_seq:
			newest_seq = seq
			newest_id = pack_id
	if newest_id.is_empty():
		return
	var suspect: Dictionary = installed["packs"][newest_id]
	var previous := str(suspect.get("previous", ""))
	if not previous.is_empty() and FileAccess.file_exists(packs_dir + "/" + previous):
		_remove_pack_file(str(suspect.get("file", "")))
		suspect["file"] = previous
		suspect["version"] = str(suspect.get("previous_version", "0.0.0"))
		suspect["sha256"] = str(suspect.get("previous_sha256", ""))
		suspect["survived_boot"] = true
		suspect.erase("previous")
		suspect.erase("previous_version")
		suspect.erase("previous_sha256")
	else:
		suspect["enabled"] = false
	report["disabled"].append(newest_id)
	pack_disabled.emit(newest_id, "boot_guard_rollback")


func _load_enabled_packs(installed: Dictionary, report: Dictionary) -> void:
	var version := resolve_app_version()
	var entries: Array[Dictionary] = []
	for pack_id: String in installed["packs"]:
		var entry: Dictionary = installed["packs"][pack_id]
		entry["id"] = pack_id
		entries.append(entry)
	entries.sort_custom(
		func(a, b): return UpdatesManifest.priority_of(a) < UpdatesManifest.priority_of(b)
	)
	for entry in entries:
		var pack_id := str(entry["id"])
		if str(entry.get("type", "pck")) == "json":
			continue
		if not bool(entry.get("enabled", false)):
			continue
		# Stale-Cleanup: neue IPA enthält den Content schon → alte Downloads löschen,
		# sonst „downgraden“ sie die App (klassischer Fehler, Doc B §2.3 Schritt 4).
		var builtin := str(builtin_versions.get(pack_id, "0.0.0"))
		if UpdatesManifest.semver_lte(str(entry.get("version", "0.0.0")), builtin):
			_remove_pack_file(str(entry.get("file", "")))
			_remove_pack_file(str(entry.get("previous", "")))
			installed["packs"].erase(pack_id)
			report["cleaned"].append(pack_id)
			continue
		# Native-Gate: Pack braucht neuere App → NIE laden (Anzeige macht das Panel).
		if UpdatesManifest.semver_gt(str(entry.get("min_native", "0.0.0")), version):
			report["skipped"].append(pack_id)
			continue
		var pack_path := packs_dir + "/" + str(entry.get("file", ""))
		var ok := ProjectSettings.load_resource_pack(
			ProjectSettings.globalize_path(pack_path), true
		)
		if ok:
			_loaded_ids.append(pack_id)
			report["loaded"].append(pack_id)
		else:
			entry["enabled"] = false
			report["disabled"].append(pack_id)
			pack_disabled.emit(pack_id, "load_failed")


func _remove_pack_file(file_name: String) -> void:
	if file_name.is_empty():
		return
	var path := packs_dir + "/" + file_name
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Erfolgs-Boot-Erkennung ohne fremde Dateien anzufassen: erste abgeschlossene
## SceneRouter-Reise ODER Fallback-Timer (App lief BOOT_OK_FALLBACK_SEC ohne Crash).
func _arm_boot_success_watch() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_signal("travel_finished"):
		router.travel_finished.connect(
			func(_target: StringName) -> void: mark_boot_successful(), CONNECT_ONE_SHOT
		)
	get_tree().create_timer(BOOT_OK_FALLBACK_SEC).timeout.connect(mark_boot_successful)
