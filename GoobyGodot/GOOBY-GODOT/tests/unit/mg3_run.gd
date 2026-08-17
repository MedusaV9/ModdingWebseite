extends SceneTree
## MG-3 Entwickler-Harness (KEIN Test): führt NUR die tests/unit/test_mg3_*.gd
## aus, damit der Batch-3-Port ohne den 90-s-Gesamtlauf iteriert werden kann.
## Der Haupt-Runner (tests/run_tests.gd) bleibt die verbindliche Quelle.
## godot --headless --path GOOBY-GODOT --script res://tests/unit/mg3_run.gd

const DIR := "res://tests/unit"


func _init() -> void:
	var files: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			if file.begins_with("test_mg3_") and file.ends_with(".gd"):
				files.append("%s/%s" % [DIR, file])
	files.sort()
	var total := 0
	var failed := 0
	for path in files:
		var script: GDScript = load(path)
		var case: TestCase = script.new()
		case.tree = self
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			case.begin_test()
			await case.call(name)
			var failures: PackedStringArray = case.take_failures()
			if failures.is_empty():
				print("  PASS %s::%s" % [path.get_file(), name])
			else:
				failed += 1
				for failure in failures:
					print("  FAIL %s::%s — %s" % [path.get_file(), name, failure])
	print("== mg3: %d Tests, %d Fehler ==" % [total, failed])
	quit(1 if failed > 0 else 0)
