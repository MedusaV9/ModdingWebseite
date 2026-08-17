extends TestCase
## Rohrpost (pipeFlow) — Logik-Parität zum Web (MG-1, Batch 1).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/pipeFlow.logic.js
## (generateBoard + simulatePipeAutoplay). Die Board-Zeilen sind der harte
## Beweis: Generator, V8-Shuffle-Replikat und Solver liefern Kachel für
## Kachel dasselbe Rätsel wie das Web.

const Logic := preload("res://scripts/minigames/games/pipe_flow/pipe_flow_logic.gd")
const MANIFEST := "res://scripts/minigames/games/pipe_flow/game.json"

## Web-Goldwerte: simulatePipeAutoplay(seed, mode).score für Seeds 1..8.
const GOLD := {
	"easy": [360, 335, 385, 335, 360, 360, 385, 335],
	"normal": [310, 310, 335, 310, 335, 310, 335, 310],
	"hard": [285, 285, 310, 260, 310, 285, 310, 260],
	"endless": [480, 455, 505, 430, 505, 480, 505, 455],
}
## Web-Goldbretter: generateBoard(seed) → src/goal-Spalte, Optimum, Kacheln.
## `rows` sind die fünf Gitterzeilen von oben nach unten (Form + Drehung).
const GOLD_BOARDS: Array[Dictionary] = [
	{
		"seed": 1,
		"srcCol": 0,
		"goalCol": 2,
		"optimalTaps": 10,
		"rows":
		[
			"tee3,bend3,straight2,bend2,bend1",
			"bend1,bend2,bend0,tee0,bend1",
			"bend3,bend2,tee3,straight2,tee1",
			"straight2,bend2,bend3,straight3,bend1",
			"tee0,straight0,bend0,bend0,bend3",
		],
	},
	{
		"seed": 3,
		"srcCol": 1,
		"goalCol": 2,
		"optimalTaps": 1,
		"rows":
		[
			"bend1,tee0,straight1,bend2,straight2",
			"straight2,straight1,bend0,bend0,bend0",
			"straight3,tee0,tee3,bend1,straight0",
			"tee2,tee2,tee3,bend2,tee0",
			"straight3,tee3,tee1,bend2,bend2",
		],
	},
	{
		"seed": 42,
		"srcCol": 0,
		"goalCol": 1,
		"optimalTaps": 10,
		"rows":
		[
			"straight0,bend0,bend2,bend0,bend3",
			"bend1,bend3,tee1,bend0,tee0",
			"bend2,bend2,bend1,bend0,straight0",
			"tee0,bend0,straight1,straight0,bend2",
			"tee3,tee2,bend2,straight3,bend3",
		],
	},
]
const WEB_TARGET := 100


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.PIPE
	assert_eq(int(t["GRID"]), 5)
	assert_almost(float(t["DURATION_SEC"]), 90.0)
	assert_eq(int(t["SOLVE_POINTS"]), 25)
	assert_eq(int(t["BONUS_MAX"]), 10)
	assert_eq(int(t["BONUS_FULL_EXTRA"]), 3)
	assert_eq(int(t["BONUS_ZERO_EXTRA"]), 15)
	assert_almost(float(t["TEE_CHANCE"]), 0.28)
	assert_eq(int(t["LEAK_FROM_PUZZLE"]), 3)
	assert_almost(float(t["LEAK_SEC"]), 25.0)
	assert_eq(int(t["LEAK_PENALTY"]), 5)
	assert_almost(float(t["ROTATE_SEC"]), 0.16)
	assert_almost(float(t["FILL_STEP_SEC"]), 0.09)
	assert_eq(int(t["ENDLESS_FAILURE_LIMIT"]), 3)
	assert_almost(float(Logic.DECOY_WEIGHTS["straight"]), 0.38)
	assert_almost(float(Logic.DECOY_WEIGHTS["bend"]), 0.42)
	assert_almost(float(Logic.DECOY_WEIGHTS["tee"]), 0.2)


func test_generated_boards_match_web() -> void:
	for gold in GOLD_BOARDS:
		var board: Dictionary = Logic.generate_board(int(gold["seed"]))
		assert_eq(int(board["srcCol"]), int(gold["srcCol"]), "srcCol seed %s" % gold["seed"])
		assert_eq(int(board["goalCol"]), int(gold["goalCol"]), "goalCol seed %s" % gold["seed"])
		assert_eq(
			int(board["optimalTaps"]), int(gold["optimalTaps"]), "Optimum seed %s" % gold["seed"]
		)
		var tiles := PackedStringArray()
		for tile: Dictionary in board["tiles"]:
			tiles.append("%s%d" % [str(tile["shape"]), int(tile["rot"])])
		var want: Array = gold["rows"]
		for row in want.size():
			var got := ",".join(tiles.slice(row * 5, row * 5 + 5))
			assert_eq(got, str(want[row]), "Zeile %d seed %s" % [row, gold["seed"]])


func test_solver_solves_generated_boards() -> void:
	for seed_value in [1, 2, 3, 7, 42]:
		var board: Dictionary = Logic.generate_board(seed_value)
		var solution: Dictionary = Logic.solve_board(board)
		assert_true(bool(solution["solvable"]), "Board %d ist lösbar" % seed_value)
		assert_eq(
			(solution["taps"] as Array).size(),
			int(board["optimalTaps"]),
			"Solver findet das Optimum (seed %d)" % seed_value
		)
		assert_false(Logic.is_solved(board), "frisches Board ist nicht schon gelöst")
		# Die Tap-Folge nachspielen muss das Wasser wirklich ins Ziel bringen.
		var tiles: Array = board["tiles"]
		for idx: int in solution["taps"]:
			tiles[idx] = Logic.rotate_tile(tiles[idx])
		assert_true(Logic.is_solved(board), "Tap-Folge löst das Board (seed %d)" % seed_value)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(6, mode), Logic.simulate_autoplay(6, mode), mode)
	assert_ne(
		int(Logic.simulate_autoplay(1, "normal")["score"]),
		int(Logic.simulate_autoplay(3, "normal")["score"])
	)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 11):
			sum += int(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = float(sum) / 10.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_bot_scores_are_plausible() -> void:
	var best := 0
	for seed_value in range(1, 11):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "hard")
		assert_true(int(run["solved"]) > 0, "Schwer-Bot löst Rätsel (seed %d)" % seed_value)
		assert_true(int(run["score"]) > 0, "Schwer-Bot punktet (seed %d)" % seed_value)
		best = maxi(best, int(run["score"]))
	assert_true(best >= WEB_TARGET, "bester Schwer-Score %d < Ziel %d" % [best, WEB_TARGET])


func test_endless_ends_on_three_failures() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.PIPE, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.endless_should_end(2, tune))
	assert_true(Logic.endless_should_end(3, tune))
	assert_false(Logic.endless_should_end(99, Logic.PIPE), "getaktet gibt es kein Limit")
	# Schwer/Endlos ziehen das Leck um ein Rätsel vor.
	assert_eq(int(tune["LEAK_FROM_PUZZLE"]), 2)
	assert_eq(int(Logic.apply_difficulty(Logic.PIPE, "easy")["LEAK_FROM_PUZZLE"]), 4)


func test_score_edges() -> void:
	assert_eq(Logic.pipe_score(0, 0, 0), 0, "ohne Lösung keine Punkte")
	# Optimal gelöst: 25 + voller Effizienzbonus.
	assert_eq(Logic.pipe_score(1, 10, 10), 35)
	assert_eq(Logic.pipe_score(1, 13, 10), 35, "bis optimal+3 bleibt der Bonus voll")
	assert_eq(Logic.pipe_score(1, 25, 10), 25, "ab optimal+15 gibt es keinen Bonus")
	assert_eq(Logic.tap_efficiency_bonus(19, 10), 5, "linear dazwischen")
	# Lecks kosten je 5 Punkte, der Score bleibt bei 0 gefloort.
	assert_eq(Logic.pipe_score(2, 20, 20, Logic.PIPE, 1), 55)
	assert_eq(Logic.pipe_score(1, 40, 10, Logic.PIPE, 9), 0)
	assert_true(Logic.leak_penalty_due(25.0, false))
	assert_false(Logic.leak_penalty_due(24.9, false), "vor 25 s tropft es nicht")
	assert_false(Logic.leak_penalty_due(99.0, true), "die Strafe fällt nur einmal")


func test_tile_geometry() -> void:
	assert_eq(Logic.opposite(Logic.DIR_N), Logic.DIR_S)
	assert_eq(Logic.opposite(Logic.DIR_E), Logic.DIR_W)
	# Ein gerades Rohr verbindet Nord/Süd und dreht auf Ost/West.
	var straight := {"shape": "straight", "rot": 0}
	assert_true(Logic.has_connection(straight, Logic.DIR_N))
	assert_true(Logic.has_connection(straight, Logic.DIR_S))
	assert_false(Logic.has_connection(straight, Logic.DIR_E))
	assert_true(Logic.has_connection(Logic.rotate_tile(straight), Logic.DIR_E))
	assert_eq(int(Logic.rotate_tile({"shape": "bend", "rot": 3})["rot"]), 0, "Drehung wickelt")
	assert_almost(Logic.min_taps_for(straight, [Logic.DIR_N]), 0.0)
	assert_almost(Logic.min_taps_for(straight, [Logic.DIR_E]), 1.0)
	assert_true(is_inf(Logic.min_taps_for(straight, [Logic.DIR_N, Logic.DIR_E])), "gerade ≠ Ecke")
	assert_almost(Logic.min_taps_for({"shape": "tee", "rot": 0}, [Logic.DIR_N, Logic.DIR_E]), 0.0)
	assert_almost(Logic.rotation_target(0), 0.0)
	assert_almost(Logic.rotation_target(2), -PI)


func test_manifest_matches_web_metadata() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_true(file != null, "game.json fehlt")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert_eq(str(manifest["id"]), "pipeFlow")
	assert_eq(int(manifest["target"]), WEB_TARGET)
	assert_eq(str(manifest["orientation"]), "portrait")
	var coins: Dictionary = manifest["coin_table"]
	assert_eq(int(coins["divisor"]), 5)
	assert_eq(int(coins["min"]), 4)
	assert_eq(int(coins["max"]), 25)
	assert_true(ResourceLoader.exists(str(manifest["scene"])), "Szene fehlt")
