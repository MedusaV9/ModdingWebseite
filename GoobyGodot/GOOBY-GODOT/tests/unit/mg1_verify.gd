extends SceneTree
## MG-1 Entwickler-Harness (KEIN Test): vergleicht die portierten Bots gegen
## die Web-Goldwerte aus /tmp/gooby-godot/mg1/expected.json.
## godot --headless --path GOOBY-GODOT --script res://tests/unit/mg1_verify.gd

const EXPECTED := "/tmp/gooby-godot/mg1/expected.json"

var _fails := 0
var _checked := 0
var _only := ""


func _init() -> void:
	var file := FileAccess.open(EXPECTED, FileAccess.READ)
	if file == null:
		print("expected.json fehlt")
		quit(1)
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	_only = OS.get_environment("MG1_ONLY")
	_check(
		"bubblePop",
		data,
		BubblePopLogic.BUBBLE,
		BubblePopLogic.simulate_autoplay,
		BubblePopLogic.apply_difficulty
	)
	_check(
		"memoryMatch",
		data,
		MemoryMatchLogic.MEMORY,
		MemoryMatchLogic.simulate_autoplay,
		MemoryMatchLogic.apply_difficulty
	)
	_check(
		"goobySays",
		data,
		GoobySaysLogic.SAYS,
		GoobySaysLogic.simulate_autoplay,
		GoobySaysLogic.apply_difficulty
	)
	_check(
		"carrotGuard",
		data,
		CarrotGuardLogic.GUARD,
		CarrotGuardLogic.simulate_autoplay,
		CarrotGuardLogic.apply_difficulty
	)
	_check(
		"bunnyHop",
		data,
		BunnyHopLogic.HOP,
		BunnyHopLogic.simulate_autoplay,
		BunnyHopLogic.apply_difficulty
	)
	_check(
		"trampoline",
		data,
		TrampolineLogic.TRAMP,
		TrampolineLogic.simulate_autoplay,
		TrampolineLogic.apply_difficulty
	)
	_check(
		"veggieChop",
		data,
		VeggieChopLogic.CHOP,
		VeggieChopLogic.simulate_autoplay,
		VeggieChopLogic.apply_difficulty
	)
	_check(
		"gardenRush",
		data,
		GardenRushLogic.RUSH,
		GardenRushLogic.simulate_autoplay,
		GardenRushLogic.apply_difficulty
	)
	_check(
		"pipeFlow",
		data,
		PipeFlowLogic.PIPE,
		PipeFlowLogic.simulate_autoplay,
		PipeFlowLogic.apply_difficulty
	)
	if _only.is_empty() or _only == "pipeFlow":
		_check_pipe_boards(data)
	print("== mg1_verify: %d Vergleiche, %d Abweichungen ==" % [_checked, _fails])
	quit(1 if _fails > 0 else 0)


func _check(
	game: String, data: Dictionary, base: Dictionary, sim: Callable, apply: Callable
) -> void:
	if not data.has(game):
		print("%s: keine Golddaten" % game)
		return
	if not _only.is_empty() and _only != game:
		return
	var block: Dictionary = data[game]
	var tunes: Dictionary = block["tune"]
	for mode: String in tunes:
		var want: Dictionary = tunes[mode]
		var got: Dictionary = apply.call(base, mode)
		for key: String in want:
			if not got.has(key):
				continue
			_compare("%s tune[%s].%s" % [game, mode, key], got[key], want[key])
	var runs: Dictionary = block["runs"]
	for mode: String in runs:
		for entry: Dictionary in runs[mode]:
			var got: Dictionary = sim.call(int(entry["seed"]), mode)
			for key: String in entry:
				if key == "seed" or key == "mode" or not got.has(key):
					continue
				_compare(
					"%s[%s/%d].%s" % [game, mode, int(entry["seed"]), key], got[key], entry[key]
				)


func _check_pipe_boards(data: Dictionary) -> void:
	var boards: Array = data["pipeFlow"].get("boards", [])
	for entry: Dictionary in boards:
		var board := PipeFlowLogic.generate_board(int(entry["seed"]))
		var tiles := PackedStringArray()
		for tile: Dictionary in board["tiles"]:
			tiles.append("%s%d" % [tile["shape"], int(tile["rot"])])
		var tag := "pipe board %d" % int(entry["seed"])
		_compare("%s.srcCol" % tag, board["srcCol"], entry["srcCol"])
		_compare("%s.goalCol" % tag, board["goalCol"], entry["goalCol"])
		_compare("%s.optimalTaps" % tag, board["optimalTaps"], entry["optimalTaps"])
		_compare_text("%s.tiles" % tag, ",".join(tiles), str(entry["tiles"]))


func _compare(tag: String, got: Variant, want: Variant) -> void:
	_checked += 1
	if want is bool:
		if bool(got) != bool(want):
			_fail("%s got=%s want=%s" % [tag, got, want])
		return
	if absf(float(got) - float(want)) > 1e-9:
		_fail("%s got=%s want=%s" % [tag, got, want])


func _compare_text(tag: String, got: String, want: String) -> void:
	_checked += 1
	if got != want:
		_fail("%s\n    got =%s\n    want=%s" % [tag, got, want])


func _fail(message: String) -> void:
	_fails += 1
	if _fails <= 24:
		print("  ABW " + message)
