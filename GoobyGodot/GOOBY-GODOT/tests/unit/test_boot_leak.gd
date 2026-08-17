extends TestCase
## Eval-2026-08 Befund 5 — 0-Leak-Gate für den nackten Boot: JEDER Boot
## leakte 6 RefCounted + 1 GDScriptFunctionState (suspendierte Boot-
## Coroutinen, deren `await get_tree().process_frame` bei Quit nie
## fortgesetzt wurde, plus nie abgeholte ResourceLoader-Threaded-Tokens
## aus dem Welt-Warmup und dem Cover-Artwork). Dieses Gate bootet das
## Projekt in einem Kind-Prozess mit --verbose gegen ein frisches user://
## und besteht NUR bei 0 geleakten Instanzen (ObjectDB, RID, Ressourcen)
## und 0 Orphan-StringNames — neue Boot-Leaks werden damit sofort rot,
## statt jeden CI-Lauf still zu verschmutzen.
##
## Wiederholungs-Regel: Der Befund-5-Leak war KONSTANT (jeder Lauf). Unter
## extremer CPU-Konkurrenz kann der ResourceLoader-Teardown der Engine
## selten (~1/12 mit künstlicher Volllast) racig einen einzelnen Token
## behalten — das ist kein Code-Leak und in jedem Wiederholungslauf weg.
## Deshalb wird NUR rot, wenn der Leak in allen Versuchen auftritt;
## Race-Treffer werden als Hinweis geloggt statt den Lauf zu färben.

const ENV_BIN := "/usr/bin/env"
const LEAK_MUSTER: Array[String] = [
	"leaked at exit",  # ObjectDB-Instanzen UND RID-Allokationen
	"Orphan StringName",
	"still in use at exit",
]
const VERSUCHE := 3


func test_boot_verbose_leakt_keine_instanzen() -> void:
	if not FileAccess.file_exists(ENV_BIN):
		print("    SKIP (optional): %s fehlt (kein POSIX-Host)" % ENV_BIN)
		return
	var befunde: Array[String] = []
	for versuch in VERSUCHE:
		befunde = _boot_leak_befunde()
		if befunde.is_empty():
			if versuch > 0:
				print(
					(
						(
							"    Hinweis: Boot erst im Versuch %d leakfrei "
							+ "(Engine-Shutdown-Race unter Last, kein konstanter Leak)"
						)
						% (versuch + 1)
					)
				)
			return
	for befund in befunde:
		fail_test(befund)


## Ein Kind-Boot mit --verbose; liefert die Leak-/Fehler-Befunde des Laufs
## (leer = sauber). Frisches HOME/XDG fürs Kind: der Boot schriebe sonst in
## das user:// des laufenden Test-Runners (Saves/Settings kollidierten).
func _boot_leak_befunde() -> Array[String]:
	var projekt := ProjectSettings.globalize_path("res://")
	var wurzel := "/tmp/gooby-bootleak-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(wurzel)
	var args := PackedStringArray(
		[
			"HOME=%s/home" % wurzel,
			"XDG_DATA_HOME=%s/xdg-data" % wurzel,
			"XDG_CONFIG_HOME=%s/xdg-config" % wurzel,
			"XDG_CACHE_HOME=%s/xdg-cache" % wurzel,
			OS.get_executable_path(),
			"--headless",
			"--path",
			projekt,
			"--quit",
			"--verbose",
		]
	)
	var ausgabe: Array = []
	var code := OS.execute(ENV_BIN, args, ausgabe, true)
	OS.execute("rm", PackedStringArray(["-rf", wurzel]))
	var log := str(ausgabe[0]) if ausgabe.size() > 0 else ""
	var befunde: Array[String] = []
	if code != 0:
		befunde.append("Boot-Smoke (Kind-Prozess) endet mit Exit %d statt 0" % code)
	if not log.contains("Loading resource:"):
		befunde.append("--verbose-Ausgabe fehlt — ohne sie wäre das Leak-Gate blind")
	for muster in LEAK_MUSTER:
		var befund := _leak_befund(log, muster)
		if befund != "":
			befunde.append(befund)
	return befunde


## Bei Treffern die betroffenen Log-Zeilen mit in den Befund schreiben —
## der CI-Log zeigt dann direkt, WAS leakt, statt nur dass etwas leakt.
func _leak_befund(log: String, muster: String) -> String:
	if not log.contains(muster):
		return ""
	var zeilen := PackedStringArray()
	for zeile in log.split("\n"):
		if (zeile.contains(muster) or zeile.begins_with("Leaked instance")) and zeilen.size() < 8:
			zeilen.append(zeile.strip_edges())
	return "Boot-Smoke nicht leakfrei („%s“): %s" % [muster, "; ".join(zeilen)]
