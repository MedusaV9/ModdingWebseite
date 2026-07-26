extends SceneTree
## RW-5 Wegwerf-Runner: nur tests/unit/test_rcomp_*.gd (schnelle Iteration;
## der Haupt-Runner res://tests/run_tests.gd bleibt die Wahrheit).

const UNIT_DIR := "res://tests/unit"


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await process_frame
	var dir := DirAccess.open(UNIT_DIR)
	var scripts: Array[String] = []
	for datei in dir.get_files():
		if datei.begins_with("test_rcomp_") and datei.ends_with(".gd"):
			scripts.append("%s/%s" % [UNIT_DIR, datei])
	scripts.sort()
	var total := 0
	var failed := 0
	for script_path in scripts:
		var script: GDScript = load(script_path)
		var case: Variant = script.new()
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
	print("== rcomp-Subset: tests=%d, failed=%d ==" % [total, failed])
	quit(1 if failed > 0 else 0)


func _test_methods(script: GDScript) -> Array[String]:
	var out: Array[String] = []
	for info in script.get_script_method_list():
		var name := str(info.get("name", ""))
		if name.begins_with("test_") and not out.has(name):
			out.append(name)
	return out
