extends SceneTree
## SEELE-2-Arbeitsrunner (KEIN test_-Präfix — der Hauptrunner ignoriert
## diese Datei): führt nur die test_seele2_*-Dateien aus, damit die
## Iteration nicht jedes Mal die komplette Suite (~2200 Tests) kostet.
## Aufruf:
##   xvfb-run -a godot --headless --path . --audio-driver Dummy \
##     --script res://tests/unit/seele2_runner.gd

const FILES: Array[String] = [
	"res://tests/unit/test_seele2_stimmung.gd",
	"res://tests/unit/test_seele2_ausdruck.gd",
	"res://tests/unit/test_seele2_gedaechtnis.gd",
	"res://tests/unit/test_seele2_absicht.gd",
	"res://tests/unit/test_seele2_stimme.gd",
]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var total := 0
	var failed := 0
	for path in FILES:
		var script: GDScript = load(path)
		var case: TestCase = script.new()
		case.tree = self
		var methods: Array[String] = []
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if method_name.begins_with("test_") and not methods.has(method_name):
				methods.append(method_name)
		methods.sort()
		for method in methods:
			total += 1
			case.begin_test()
			await case.call(method)
			var failures := case.take_failures()
			if failures.is_empty():
				print("  PASS %s::%s" % [path.get_file(), method])
			else:
				failed += 1
				for failure in failures:
					print("  FAIL %s::%s — %s" % [path.get_file(), method, failure])
	print("== SEELE2: tests=%d, failed=%d ==" % [total, failed])
	quit(1 if failed > 0 else 0)
