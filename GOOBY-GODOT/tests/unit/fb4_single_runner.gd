extends SceneTree
## FB4-Einzeldatei-Runner (KEIN Test): führt genau EINE TestCase-Datei aus —
## der Haupt-Runner (tests/run_tests.gd) kennt keinen Filter und braucht für
## die volle Suite mehrere Minuten. Aufruf:
##   godot --headless --path GOOBY-GODOT \
##     --script res://tests/unit/fb4_single_runner.gd -- test_gvz_game [...]
## Argumente sind Dateinamen unter res://tests/unit/ (mit oder ohne .gd).

const TEST_TIMEOUT_MS := 120_000


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var failed := 0
	var total := 0
	for arg in OS.get_cmdline_user_args():
		var file := str(arg)
		if not file.ends_with(".gd"):
			file += ".gd"
		var result := await _run_script("res://tests/unit/" + file)
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
		print("  SKIP %s — kein TestCase." % script_path)
		return {"total": 0, "failed": 0}
	case.tree = self
	for method in _test_methods(script):
		total += 1
		case.begin_test()
		var finished := await _call_with_watchdog(case, method)
		var failures: PackedStringArray = case.take_failures()
		if not finished:
			failed += 1
			print("  FAIL %s::%s — TIMEOUT" % [script_path.get_file(), method])
		elif failures.is_empty():
			print("  PASS %s::%s" % [script_path.get_file(), method])
		else:
			failed += 1
			for failure in failures:
				print("  FAIL %s::%s — %s" % [script_path.get_file(), method, failure])
	return {"total": total, "failed": failed}


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
