extends SceneTree
## POLISH-A Probe: führt NUR die test_feel_*-Dateien aus (schneller Zyklus,
## der Haupt-Runner bleibt unangetastet). Aufruf:
##   godot --headless --path GOOBY-GODOT --script res://tests/unit/probe_feel_runner.gd

const FILES: Array[String] = [
	"res://tests/unit/test_feel_sfx.gd",
	"res://tests/unit/test_feel_juice.gd",
]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var total := 0
	var failed := 0
	for path in FILES:
		var script: GDScript = load(path)
		var case: Variant = script.new()
		case.tree = self
		var names: Array[String] = []
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if method_name.begins_with("test_") and not names.has(method_name):
				names.append(method_name)
		names.sort()
		for method in names:
			total += 1
			case.begin_test()
			await case.call(method)
			var failures: PackedStringArray = case.take_failures()
			if failures.is_empty():
				print("  PASS %s::%s" % [path.get_file(), method])
			else:
				failed += 1
				for failure in failures:
					print("  FAIL %s::%s — %s" % [path.get_file(), method, failure])
	print("== Feel-Probe: tests=%d, failed=%d ==" % [total, failed])
	quit(1 if failed > 0 else 0)
