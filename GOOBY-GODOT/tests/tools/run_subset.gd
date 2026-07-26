extends SceneTree
## Fokus-Runner (Dev-Werkzeug, nicht Teil des Haupt-Runners): führt nur
## test_*-Dateien aus, deren Dateiname eines der Muster aus --filter=<a,b,c>
## enthält. Aufruf:
##   godot --headless --path GOOBY-GODOT \
##     --script res://tests/tools/run_subset.gd -- --filter=sticker,album
## Ohne Filter läuft nichts (bewusst — Vollauf gehört run_tests.gd).

const TESTS_DIR := "res://tests/unit"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var patterns: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			for part: String in arg.trim_prefix("--filter=").split(","):
				if not part.is_empty():
					patterns.append(part)
	if patterns.is_empty():
		print("run_subset: kein --filter=... angegeben.")
		quit(1)
		return
	var total := 0
	var failed := 0
	var dir := DirAccess.open(TESTS_DIR)
	var files := dir.get_files()
	files.sort()
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var hit := false
		for pattern: String in patterns:
			if file.contains(pattern):
				hit = true
		if not hit:
			continue
		var case: TestCase = (load(TESTS_DIR + "/" + file) as GDScript).new()
		case.tree = self
		print("-- %s" % file)
		for method: Dictionary in case.get_method_list():
			var name := str(method["name"])
			if not name.begins_with("test_"):
				continue
			total += 1
			case.begin_test()
			@warning_ignore("redundant_await")
			await case.call(name)
			var failures := case.take_failures()
			if failures.is_empty():
				print("  OK   %s" % name)
			else:
				failed += 1
				for failure: String in failures:
					print("  FAIL %s — %s" % [name, failure])
	print("== Subset: tests=%d, failed=%d ==" % [total, failed])
	quit(1 if failed > 0 else 0)
