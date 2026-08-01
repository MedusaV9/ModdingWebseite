extends SceneTree
## GOOBY-Test-Runner (W1a; Mini-Runner nach Doc A §9 — bewusst KEIN Addon).
##
## Aufruf (nach einmaligem `godot --headless --path GOOBY-GODOT --import`):
##   godot --headless --path GOOBY-GODOT --script res://tests/run_tests.gd
##
## Entdeckt rekursiv res://tests/**/test_*.gd (Konvention: tests/unit/;
## test_case.gd ist ausgenommen), instanziert jede Datei (muss von TestCase
## erben) und ruft alle test_*-Methoden auf (async erlaubt — jede Methode
## wird awaited). Exit-Code: 0 = alles grün, 1 = Failures/Fehler.
## Diese Datei gehört W1a — andere Agents legen NUR eigene test_*.gd an.
## W4-P5 (INFRA, Plan §2.4-13 Runner-Robustheit): Watchdog pro Testmethode —
## eine hängende await-Kette (z. B. Signal, das nie feuert) blockiert nicht
## mehr den ganzen Lauf/CI-Job, sondern wird nach TEST_TIMEOUT_MS als FAIL
## gewertet und der Lauf geht weiter. Konventionen (FROZEN) unverändert.

const TESTS_ROOT := "res://tests"
const EXCLUDED_FILES: Array[String] = ["test_case.gd"]
## Watchdog pro test_*-Methode — reines Hänger-Netz, legitime Tests bleiben
## weit darunter (kompletter Lauf ~30 s für ~400 Tests).
const TEST_TIMEOUT_MS := 120_000


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await process_frame
	var scripts := _discover_test_scripts(TESTS_ROOT)
	scripts.sort()
	if scripts.is_empty():
		print("FEHLER: keine Tests unter %s gefunden." % TESTS_ROOT)
		quit(1)
		return
	print("== GOOBY-Tests: %d Testdateien ==" % scripts.size())
	var total := 0
	var failed := 0
	for script_path in scripts:
		var result := await _run_script(script_path)
		total += result["total"]
		failed += result["failed"]
	print("== Ergebnis: tests=%d, failed=%d ==" % [total, failed])
	quit(1 if failed > 0 else 0)


func _run_script(script_path: String) -> Dictionary:
	var total := 0
	var failed := 0
	var script: GDScript = load(script_path)
	if script == null:
		print("  FAIL %s — Skript lädt nicht." % script_path)
		return {"total": 1, "failed": 1}
	if not script.can_instantiate():
		# Parse-Fehler-Guard (W16/G4-Befund): load() liefert dann zwar ein
		# GDScript-Objekt, aber .new() darauf crasht die Runner-Coroutine VOR
		# quit() — der Prozess hängt dauerhaft (so geschehen, als eine
		# build()-Signatur wechselte und eine Bestands-Call-Site veraltete).
		# Deshalb: laut als FAIL zählen und weiterlaufen statt hängen.
		print("  FAIL %s — Skript kompiliert nicht (Parse-Fehler)." % script_path)
		return {"total": 1, "failed": 1}
	var case: Variant = script.new()
	if not (case is TestCase):
		# Fremd-Runner-Suiten (z. B. W1c-UI-Tests mit eigener Basisklasse) werden
		# hier übersprungen — die CI ruft deren Runner als eigenen Schritt auf.
		print("  SKIP %s — eigener Runner (nicht TestCase)." % script_path)
		if case is Object and not (case is RefCounted):
			case.free()
		return {"total": 0, "failed": 0}
	case.tree = self
	for method in _test_methods(script):
		total += 1
		case.begin_test()
		var finished := await _call_with_watchdog(case, method)
		var failures: PackedStringArray = case.take_failures()
		if not finished:
			failed += 1
			print(
				(
					"  FAIL %s::%s — TIMEOUT nach %d ms (hängende await-Kette?)"
					% [script_path.get_file(), method, TEST_TIMEOUT_MS]
				)
			)
			for failure in failures:
				print("  FAIL %s::%s — %s" % [script_path.get_file(), method, failure])
		elif failures.is_empty():
			print("  PASS %s::%s" % [script_path.get_file(), method])
		else:
			failed += 1
			for failure in failures:
				print("  FAIL %s::%s — %s" % [script_path.get_file(), method, failure])
	return {"total": total, "failed": failed}


## Startet die (potenziell asynchrone) Testmethode und wartet bis fertig ODER
## Timeout. true = Methode ist regulär zurückgekehrt. Nach einem Timeout läuft
## die Zombie-Coroutine ggf. weiter (GDScript kann sie nicht abbrechen) — der
## Lauf bricht aber nicht mehr ab, und der Fall wird laut gemeldet.
func _call_with_watchdog(case: TestCase, method: String) -> bool:
	var done := {"done": false}
	_invoke_test(case, method, done)
	var deadline := Time.get_ticks_msec() + TEST_TIMEOUT_MS
	while not done["done"] and Time.get_ticks_msec() < deadline:
		await process_frame
	return done["done"]


func _invoke_test(case: TestCase, method: String, done: Dictionary) -> void:
	await case.call(method)
	done["done"] = true


func _test_methods(script: GDScript) -> Array[String]:
	var names: Array[String] = []
	for method in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	names.sort()
	return names


func _discover_test_scripts(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := root + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				found.append_array(_discover_test_scripts(path))
		elif (
			entry.begins_with("test_") and entry.ends_with(".gd") and not EXCLUDED_FILES.has(entry)
		):
			found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
