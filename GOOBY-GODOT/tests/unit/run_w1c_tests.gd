extends SceneTree
## W1c-Test-Runner (eigenständig, bis der W1a-Runner integriert ist):
## `godot --headless --script res://tests/unit/run_w1c_tests.gd`
## Entdeckt alle `res://tests/unit/test_ui_*.gd`, führt `test_*`-Methoden
## (auch async) aus und beendet mit Exit-Code 0/1. Ausgabe endet mit
## `failed: <n>` — kompatibel zur W1a-Konvention.

const TEST_DIR := "res://tests/unit"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var total_checks := 0
	var all_failures: Array[String] = []
	var files := _discover()
	files.sort()
	for path in files:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			# can_instantiate-Guard (W16/G4): .new() auf einem Skript mit
			# Parse-Fehler crasht die Coroutine vor quit() → Prozess hängt.
			all_failures.append("Testdatei lädt/kompiliert nicht: %s" % path)
			continue
		var inst: Variant = script.new()
		if not (inst is W1cTestCase):
			# Falsche Basisklasse (gehört in run_tests.gd): laut melden statt
			# am harten typed-Cast zu sterben.
			all_failures.append("Keine W1cTestCase-Suite: %s" % path)
			if inst is Object and not (inst is RefCounted):
				inst.free()
			continue
		var case: W1cTestCase = inst
		case.tree = self
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var before := case.failures.size()
			@warning_ignore("redundant_await")
			await case.call(method_name)
			var status := "OK" if case.failures.size() == before else "FAIL"
			print("  [%s] %s :: %s" % [status, path.get_file(), method_name])
		total_checks += case.checks
		all_failures.append_array(case.failures)
	print("")
	for failure in all_failures:
		printerr("FEHLER: %s" % failure)
	print("checks: %d" % total_checks)
	print("failed: %d" % all_failures.size())
	quit(0 if all_failures.is_empty() else 1)


func _discover() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.begins_with("test_ui_") and file.ends_with(".gd"):
			result.append("%s/%s" % [TEST_DIR, file])
	return result
