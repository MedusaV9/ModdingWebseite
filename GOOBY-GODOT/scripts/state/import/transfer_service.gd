extends RefCounted
## Spielstand-Uebertragung (FIX-6): die EINE Fach-API hinter dem
## Transfer-Screen und dem Auto-Import beim ersten Start.
##
## Drei Wege, ein Trichter — alles laeuft durch moving_box_import.import_text
## (roher v0–v4-JSON ODER GOOBY5-Code) und damit durch die volle
## Migrationskette + SaveSchema.normalize:
## 1. AUTO (iOS): probe_legacy() liest die NSUserDefaults-Spiegelung der
##    Alt-App (legacy_capacitor.gd, ohne Plugin) und liefert eine Vorschau.
## 2. EINFUEGEN/DATEI: preview_text()/preview_file() fuer den Screen.
## 3. GOOBY5-Code (Godot↔Godot-Geraetewechsel): gleicher Trichter.
##
## apply() sichert den AKTUELLEN Stand zuerst (user://save_v5.pre_import.json)
## und ersetzt erst dann via GameState.import_state() — der alte Stand ist
## also nie weg, auch wenn man versehentlich importiert.

const MovingBoxImport := preload("res://scripts/state/moving_box_import.gd")
const LegacyCapacitor := preload("res://scripts/state/import/legacy_capacitor.gd")

const SAVE_PATH := "user://save_v5.json"
const PRE_IMPORT_BACKUP := "user://save_v5.pre_import.json"
## Import-Dateien groesser als das sind sicher kein Gooby-Save (Web ~100 KB).
const MAX_FILE_BYTES := 8 * 1024 * 1024


## Alt-App-Spielstand suchen (iOS-Container; Tests: plist_override).
## {"found": bool, "json": String, "source": String, "preview": Dictionary,
##  "error": String} — preview ist das import_text-Resultat (ok/state/report).
static func probe_legacy(now_ms: int, plist_override := "") -> Dictionary:
	var read := LegacyCapacitor.read_save_json(plist_override)
	if not read["ok"]:
		return {
			"found": false,
			"json": "",
			"source": "",
			"preview": {},
			"error": str(read["error"]),
		}
	var preview := preview_text(str(read["json"]), now_ms)
	return {
		"found": preview["ok"],
		"json": str(read["json"]),
		"source": str(read["source"]),
		"preview": preview,
		"error": str(preview["error"]) if not preview["ok"] else "",
	}


## Eingefuegten Text pruefen (roher JSON oder GOOBY5-Code).
## Liefert das moving_box_import-Resultat {ok, state, error, report}.
static func preview_text(text: String, now_ms: int) -> Dictionary:
	return MovingBoxImport.import_text(text, now_ms)


## Datei laden + pruefen (Desktop-FileDialog des Transfer-Screens).
static func preview_file(path: String, now_ms: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "state": {}, "error": "Datei nicht gefunden", "report": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return {"ok": false, "state": {}, "error": "Datei nicht lesbar/zu gross", "report": {}}
	return preview_text(file.get_as_text(), now_ms)


## Migrierten State uebernehmen: erst Sicherung des alten Stands, dann
## GameState.import_state() (persistiert sofort). true = uebernommen.
static func apply(state: Dictionary, game_state: Object, save_path := SAVE_PATH) -> bool:
	if game_state == null or not game_state.has_method("import_state"):
		return false
	backup_current(save_path)
	game_state.import_state(state)
	return true


## Aktuellen Save nach .pre_import.json kopieren (best effort, idempotent
## pro Import — ueberschreibt eine aeltere Vorsicherung).
static func backup_current(save_path := SAVE_PATH) -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var raw := FileAccess.get_file_as_string(save_path)
	var backup := save_path.get_basename() + ".pre_import.json"
	var file := FileAccess.open(backup, FileAccess.WRITE)
	if file == null:
		push_warning("[transfer] Vorsicherung fehlgeschlagen: %s" % backup)
		return false
	file.store_string(raw)
	file.flush()
	return true


## Kurzzusammenfassung fuer die Vorschau ("Level 12, 3400 Muenzen, …").
static func report_summary(report: Dictionary) -> Dictionary:
	return {
		"level": int(report.get("level", 1)),
		"coins": int(report.get("coins", 0)),
		"stickers": int(report.get("stickers", 0)),
		"outfits": int(report.get("outfits", 0)),
		"furniture": int(report.get("furnitureBoxed", 0)),
		"from": str(report.get("importedFrom", "")),
	}
