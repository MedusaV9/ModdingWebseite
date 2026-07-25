extends SceneTree
## TEMP (HAUS): Einzeldatei-Runner zum schnellen Iterieren. Vor Abgabe löschen.

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var path := "res://tests/unit/%s" % OS.get_environment("ONE")
	var script: GDScript = load(path)
	var case: Variant = script.new()
	case.tree = self
	var failed := 0
	var total := 0
	for method in script.get_script_method_list():
		var name: String = method["name"]
		if not name.begins_with("test_"):
			continue
		total += 1
		case.begin_test()
		await case.call(name)
		var failures: PackedStringArray = case.take_failures()
		if failures.is_empty():
			print("  PASS %s" % name)
		else:
			failed += 1
			for f in failures:
				print("  FAIL %s — %s" % [name, f])
	print("== %s: tests=%d failed=%d ==" % [path, total, failed])
	quit(1 if failed > 0 else 0)
