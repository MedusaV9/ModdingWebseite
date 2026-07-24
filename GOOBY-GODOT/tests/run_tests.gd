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

const TESTS_ROOT := "res://tests"
const EXCLUDED_FILES: Array[String] = ["test_case.gd"]


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
		await case.call(method)
		var failures: PackedStringArray = case.take_failures()
		if failures.is_empty():
			print("  PASS %s::%s" % [script_path.get_file(), method])
		else:
			failed += 1
			for failure in failures:
				print("  FAIL %s::%s — %s" % [script_path.get_file(), method, failure])
	return {"total": total, "failed": failed}


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
