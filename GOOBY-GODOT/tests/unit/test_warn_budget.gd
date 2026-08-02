extends TestCase
## W17/B11 WARN-SWEEP — Warn-Regressions-Wache: fährt den Boot-Smoke
## (godot --headless --quit, frisches user:// wie CI/preflight) als
## Subprozess und zählt WARNING:/ERROR:/SCRIPT ERROR:-Zeilen gegen das
## Budget in tests/fixtures/warn_budget.json (NICHT tests/expected/ — der
## Ordner ist exklusiv für Cross-Check-Fixtures, siehe test_w13c_crosscheck
## ::test_fixture_folder_has_no_orphans). Neue Godot-Meldungen im Boot
## fallen damit sofort auf, statt sich still anzusammeln (W13-Befund:
## 533 Warnungen). Budget anheben ist die AUSNAHME und gehört begründet
## in die Budget-Datei; der Normalweg ist: Ursache fixen.
##
## Läuft nur, wo /bin/bash existiert (Linux-CI/Dev) — sonst sauberer SKIP
## nach dem Muster von test_net_integration. Der Subprozess bekommt ein
## eigenes HOME/XDG-Verzeichnis (Muster tools/ci/run_godot_isolated.sh),
## damit weder das Test-user:// noch ein Dev-Profil den Boot verfälscht.

const BUDGET_PFAD := "res://tests/fixtures/warn_budget.json"
const BASH_BIN := "/bin/bash"
## Der Boot-Smoke braucht headless ~2 s; großzügiger Deckel gegen Hänger
## (OS.create_process + Poll statt blockierendem OS.execute, damit ein
## kaputter Boot den Runner-Watchdog nicht aushebelt).
const BOOT_TIMEOUT_MS := 90_000


func test_boot_smoke_haelt_das_warn_budget() -> void:
	if not FileAccess.file_exists(BASH_BIN):
		print("    SKIP (optional): %s fehlt — Warn-Budget-Wache nur auf Unix" % BASH_BIN)
		return
	var budget := _lade_budget()
	if budget.is_empty():
		fail_test("Budget-Datei fehlt/kaputt: %s" % BUDGET_PFAD)
		return
	var lauf := await _boot_smoke_ausgabe()
	if not bool(lauf["ok"]):
		fail_test(str(lauf["fehler"]))
		return
	var zeilen: PackedStringArray = lauf["zeilen"]
	var funde := {"WARNING:": [], "ERROR:": [], "SCRIPT ERROR:": []}
	for zeile: String in zeilen:
		for prefix: String in funde:
			if zeile.begins_with(prefix):
				(funde[prefix] as Array).append(zeile)
	var warn: Array = funde["WARNING:"]
	var err: Array = funde["ERROR:"]
	var script_err: Array = funde["SCRIPT ERROR:"]
	print(
		(
			"    Boot-Smoke-Meldungen: %d WARNING / %d ERROR / %d SCRIPT ERROR"
			% [warn.size(), err.size(), script_err.size()]
		)
	)
	_pruefe("WARNING", warn, int(budget["warnings_max"]))
	_pruefe("ERROR", err, int(budget["errors_max"]))
	_pruefe("SCRIPT ERROR", script_err, int(budget["script_errors_max"]))


func _pruefe(art: String, zeilen: Array, maximum: int) -> void:
	if zeilen.size() <= maximum:
		return
	for zeile: String in zeilen.slice(0, 10):
		print("      %s" % zeile)
	fail_test(
		(
			(
				"%d %s-Zeilen im Boot-Smoke, Budget erlaubt %d — neue Meldung(en) "
				+ "fixen statt ansammeln (Budget: tests/fixtures/warn_budget.json)."
			)
			% [zeilen.size(), art, maximum]
		)
	)


func _lade_budget() -> Dictionary:
	if not FileAccess.file_exists(BUDGET_PFAD):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUDGET_PFAD))
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("boot_smoke") is Dictionary):
		return {}
	var boot: Dictionary = (parsed as Dictionary)["boot_smoke"]
	for pflicht in ["warnings_max", "errors_max", "script_errors_max"]:
		if not boot.has(pflicht):
			return {}
	return boot


## Boot-Smoke isoliert starten und die komplette Ausgabe (stdout+stderr)
## einsammeln. {"ok": bool, "zeilen": PackedStringArray, "fehler": String}.
func _boot_smoke_ausgabe() -> Dictionary:
	var wurzel := "/tmp/gooby_warn_gate_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
	var log_pfad := wurzel + "/boot.log"
	var projekt := ProjectSettings.globalize_path("res://").rstrip("/")
	var godot := OS.get_executable_path()
	var cmd := (
		(
			"mkdir -p '%s/home' '%s/xdg-data' '%s/xdg-config' '%s/xdg-cache' && "
			% [wurzel, wurzel, wurzel, wurzel]
		)
		+ "HOME='%s/home' XDG_DATA_HOME='%s/xdg-data' " % [wurzel, wurzel]
		+ "XDG_CONFIG_HOME='%s/xdg-config' XDG_CACHE_HOME='%s/xdg-cache' " % [wurzel, wurzel]
		+ "'%s' --headless --path '%s' --quit > '%s' 2>&1" % [godot, projekt, log_pfad]
	)
	var pid := OS.create_process(BASH_BIN, ["-c", cmd])
	if pid <= 0:
		return {"ok": false, "zeilen": PackedStringArray(), "fehler": "Boot-Smoke startet nicht"}
	var fertig := await wait_until(
		func() -> bool: return not OS.is_process_running(pid), BOOT_TIMEOUT_MS
	)
	if not fertig:
		OS.kill(pid)
		return {
			"ok": false,
			"zeilen": PackedStringArray(),
			"fehler": "Boot-Smoke hängt (> %d ms) — Boot kaputt?" % BOOT_TIMEOUT_MS,
		}
	if not FileAccess.file_exists(log_pfad):
		return {"ok": false, "zeilen": PackedStringArray(), "fehler": "Boot-Log fehlt: " + log_pfad}
	var zeilen := FileAccess.get_file_as_string(log_pfad).split("\n")
	OS.create_process(BASH_BIN, ["-c", "rm -rf '%s'" % wurzel])
	return {"ok": true, "zeilen": zeilen, "fehler": ""}
