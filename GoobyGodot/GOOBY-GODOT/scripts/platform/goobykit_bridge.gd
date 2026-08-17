class_name GoobyKitBridge
extends RefCounted
## iOS-WIDGETS (Plugin-Anbindung) — die GDScript-Haelfte des goobykit-iOS-
## Plugins (GOOBY-GODOT/ios/plugins/goobykit/). API exakt wie beauftragt:
## set_widget_data / start_live_activity / update_live_activity /
## end_live_activity / is_supported.
##
## TRANSPORT (bewusste Architektur-Entscheidung, s. docs/godot-rewrite/
## IOS-WIDGETS.md §2): Die Befehle laufen als DATEI-OUTBOX durch
## user://goobykit/ (auf iOS = <App>/Documents/goobykit/). Die native
## Swift-Seite (GoobyKitBridge.swift, per CI ins App-Target injiziert)
## beobachtet den Ordner per DispatchSource + App-Lifecycle und spiegelt:
##  - widget_snapshot.json  → App-Group-NSUserDefaults
##    (group.com.permissionmaxed.gooby.shared) + WidgetCenter.reload
##  - live_activity.json    → ActivityKit start/update/end (iOS 16.2+)
## WARUM keine Engine-Singleton-Methodenaufrufe: ein .gdip-Static-Lib mit
## Godot-Objekt-Registrierung muesste gegen die internen Engine-C++-Header
## kompiliert werden (voller Godot-Source-Checkout + Header-Generierung in
## der CI) UND ActivityKit/WidgetKit sind Swift-only — die Swift-Seite im
## App-Target braucht es so oder so. Die Datei-Outbox ist genauso schnell
## (DispatchSource feuert in Millisekunden), crash-sicher (deklarativer
## Soll-Zustand statt verlierbarer Kommandos) und headless voll testbar.
##
## Auf Nicht-iOS-Plattformen ist alles ein No-op (is_supported() == false);
## Tests instanziieren mit force_enabled + eigenem Basis-Ordner.

const OUTBOX_DIR := "user://goobykit"
const SNAPSHOT_FILE := "widget_snapshot.json"
const LIVE_ACTIVITY_FILE := "live_activity.json"

var base_dir := OUTBOX_DIR

var _enabled := false
## Monoton steigende Start-Sequenz: die Swift-Seite startet eine NEUE
## Activity nur bei neuer seq (Update behaelt sie) — uebersteht App-Restarts,
## weil die letzte seq beim Init aus der Datei zurueckgelesen wird.
var _seq := 0
var _active := false


func _init(base_dir_override := "", force_enabled := false) -> void:
	if not base_dir_override.is_empty():
		base_dir = base_dir_override
	_enabled = force_enabled or OS.get_name() == "iOS"
	if _enabled:
		_restore_from_outbox()


## Gibt es auf dieser Plattform eine native Widget-/Live-Activity-Seite?
func is_supported() -> bool:
	return _enabled


## Widget-Snapshot (JSON-String aus WidgetSnapshot.build) in die Outbox
## schreiben. true = geschrieben (false = No-op/Fehler).
func set_widget_data(json: String) -> bool:
	if not _enabled:
		return false
	return _write_atomic(SNAPSHOT_FILE, json)


## Neue Live Activity starten (payload = WidgetSnapshot.live_activity_plan).
func start_live_activity(json: String) -> bool:
	if not _enabled:
		return false
	_seq += 1
	_active = true
	return _write_live_activity(json)


## Laufende Live Activity aktualisieren (gleiche seq, neuer Inhalt).
## Ohne laufende Activity ein Start (deklarativer Soll-Zustand).
func update_live_activity(json: String) -> bool:
	if not _enabled:
		return false
	if not _active:
		return start_live_activity(json)
	return _write_live_activity(json)


## Laufende Live Activity beenden (Soll-Zustand: keine Activity).
func end_live_activity() -> bool:
	if not _enabled:
		return false
	_active = false
	return _write_live_activity("{}")


## Letzter geschriebener Soll-Zustand (Tests/Debug).
func live_activity_state() -> Dictionary:
	return {"seq": _seq, "active": _active}


## --- intern ------------------------------------------------------------------


func _write_live_activity(payload_json: String) -> bool:
	var parsed: Variant = JSON.parse_string(payload_json)
	var envelope := {
		"seq": _seq,
		"active": _active,
		"payload": parsed if parsed is Dictionary else {},
	}
	return _write_atomic(LIVE_ACTIVITY_FILE, JSON.stringify(envelope))


## Atomar schreiben (tmp + rename — Muster save_manager.gd), damit die
## Swift-Seite nie eine halbe Datei liest.
func _write_atomic(file_name: String, contents: String) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("[goobykit] Outbox-Ordner fehlgeschlagen: %s" % error_string(err))
		return false
	var path := base_dir.path_join(file_name)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("[goobykit] %s nicht schreibbar (%s)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(contents)
	f.flush()
	f = null
	var rename_err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)
	)
	if rename_err != OK:
		push_warning("[goobykit] Rename fehlgeschlagen: %s" % error_string(rename_err))
		return false
	return true


## seq/active aus einer frueheren Sitzung zuruecklesen (App-Restart darf die
## Sequenz nie zuruecksetzen, sonst ignoriert Swift den naechsten Start).
func _restore_from_outbox() -> void:
	var path := base_dir.path_join(LIVE_ACTIVITY_FILE)
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return
	var seq: Variant = (parsed as Dictionary).get("seq")
	if typeof(seq) == TYPE_INT or typeof(seq) == TYPE_FLOAT:
		_seq = maxi(_seq, int(seq))
	var active: Variant = (parsed as Dictionary).get("active")
	_active = active is bool and active
