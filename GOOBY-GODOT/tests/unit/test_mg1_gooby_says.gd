extends TestCase
## Gooby sagt (goobySays) — Logik-Parität zum Web (MG-1, Batch 1).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/goobySays.logic.js
## (simulateSaysAutoplay) — sie sperren Sequenzwachstum, Tempo-Rampe und
## Speed-Bonus fest.

const Logic := preload("res://scripts/minigames/games/gooby_says/gooby_says_logic.gd")
const MANIFEST := "res://scripts/minigames/games/gooby_says/game.json"

## Web-Goldwerte: simulateSaysAutoplay(seed, mode).score für Seeds 1..8.
## Alle vier Zeilen sind gleich — der Bot tappt mit 250 ms immer in den vollen
## Speed-Bonus, nur die Fehlerrampe (botErrorMult) trennt die Modi.
const GOLD := {
	"easy": [28, 48, 108, 38, 78, 68, 58, 48],
	"normal": [28, 48, 108, 38, 78, 68, 58, 48],
	"hard": [28, 48, 108, 38, 78, 68, 58, 48],
	"endless": [28, 48, 108, 38, 78, 68, 58, 48],
}
const WEB_TARGET := 70


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.SAYS
	assert_eq(int(t["PADS"]), 4)
	assert_eq(int(t["START_LEN"]), 3)
	assert_eq(int(t["GROW_PER_ROUND"]), 1)
	assert_eq(int(t["ROUND_POINTS"]), 10)
	assert_almost(float(t["STEP_DECAY_PCT"]), 0.05)
	assert_almost(float(t["STEP_BASE_MS"]), 600.0)
	assert_almost(float(t["STEP_FLOOR_MS"]), 320.0)
	assert_eq(int(t["SPEED_BONUS_MAX"]), 8)
	assert_almost(float(t["REACTION_FULL_MS"]), 500.0)
	assert_almost(float(t["REACTION_ZERO_MS"]), 1500.0)
	assert_almost(float(t["INPUT_TIMEOUT_MS"]), 5000.0)
	assert_eq(int(t["CHORD_FROM_ROUND"]), 6)
	assert_almost(float(t["CHORD_WINDOW_MS"]), 250.0)
	assert_almost(float(t["AUTOPLAY_ERR_RAMP"]), 0.0025)
	assert_almost(float(t["AUTOPLAY_ERR_CAP"]), 0.08)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(5, mode), Logic.simulate_autoplay(5, mode), mode)
		assert_ne(
			int(Logic.simulate_autoplay(3, mode)["rounds"]),
			int(Logic.simulate_autoplay(4, mode)["rounds"]),
			mode
		)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 21):
			sum += int(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = float(sum) / 20.0
	assert_true(means["easy"] >= means["normal"], "leicht ≥ normal (%s)" % means)
	assert_true(means["normal"] >= means["hard"], "normal ≥ schwer (%s)" % means)
	assert_true(means["easy"] > means["hard"], "leicht > schwer (%s)" % means)


func test_bot_scores_are_plausible() -> void:
	var best := 0
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "hard")
		assert_true(int(run["rounds"]) >= 1, "Bot schafft mindestens eine Runde")
		assert_true(int(run["rounds"]) <= 40, "Bot bleibt im 40-Runden-Netz")
		assert_true(int(run["score"]) > 0, "Bot punktet (seed %d)" % seed_value)
		best = maxi(best, int(run["score"]))
	assert_true(best >= WEB_TARGET, "bester Schwer-Score %d < Ziel %d" % [best, WEB_TARGET])


func test_endless_ends_on_first_mistake() -> void:
	assert_false(Logic.endless_should_end("endless", 0))
	assert_true(Logic.endless_should_end("endless", 1), "Endlos endet beim ersten Fehler")
	assert_false(Logic.endless_should_end("normal", 3), "getaktet läuft die Runde weiter")
	var tune: Dictionary = Logic.apply_difficulty(Logic.SAYS, "endless")
	assert_almost(float(tune["STEP_FLOOR_MS"]), 0.0, 1e-9, "Endlos kennt keinen Tempo-Boden")


func test_score_edges() -> void:
	assert_eq(Logic.round_score(0, 250.0), 0, "ohne Runde keine Punkte")
	assert_eq(Logic.round_score(1, 250.0), 18, "10 + voller Speed-Bonus")
	assert_eq(Logic.round_score(3, 1500.0), 30, "zu langsam: kein Bonus")
	assert_eq(Logic.speed_bonus(500.0), 8, "genau an der Bonusgrenze")
	assert_eq(Logic.speed_bonus(1000.0), 4, "linear in der Mitte")
	assert_eq(Logic.speed_bonus(1500.0), 0)
	assert_eq(Logic.speed_bonus(INF), 0, "kein Tap: kein Bonus")


func test_sequence_growth_and_tempo() -> void:
	assert_eq(Logic.seq_length_at(1), 3)
	assert_eq(Logic.seq_length_at(2), 4)
	assert_eq(Logic.seq_length_at(10), 12)
	assert_almost(Logic.step_ms_at(1), 600.0)
	assert_almost(Logic.step_ms_at(2), 570.0)
	# −5 % je Runde, aber nie unter den Boden.
	assert_almost(Logic.step_ms_at(99), 320.0)
	assert_almost(Logic.autoplay_err_at(1), 0.0, 1e-9, "Runde 1 ist fehlerfrei")
	assert_almost(Logic.autoplay_err_at(5), 0.01)
	assert_almost(Logic.autoplay_err_at(999), 0.08, 1e-9, "Fehlerrampe ist gedeckelt")


func test_chords_start_at_round_six() -> void:
	var rng := GoobyRng.new(11)
	var early: Array = Logic.extend_sequence([], rng, 5)
	assert_false(Logic.is_chord_step(early[0]), "vor Runde 6 nur Einzel-Pads")
	var late: Array = Logic.extend_sequence([], rng, 6)
	assert_true(Logic.is_chord_step(late[0]), "ab Runde 6 kommen Akkorde")
	var chord: Array = late[0]
	assert_ne(int(chord[0]), int(chord[1]), "ein Akkord nutzt zwei Pads")
	# Bewertung: beide Pads in beliebiger Reihenfolge, im Fenster.
	assert_eq(Logic.chord_tap_result(chord, int(chord[1]), -1), "waiting")
	assert_eq(Logic.chord_tap_result(chord, int(chord[1]), int(chord[0]), 100.0), "complete")
	assert_eq(Logic.chord_tap_result(chord, int(chord[0]), int(chord[1]), 400.0), "late")
	assert_eq(Logic.chord_tap_result(chord, int(chord[0]), int(chord[0]), 10.0), "wrong")
	assert_true(Logic.giggle_round(5))
	assert_false(Logic.giggle_round(4))


func test_manifest_matches_web_metadata() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_true(file != null, "game.json fehlt")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert_eq(str(manifest["id"]), "goobySays")
	assert_eq(int(manifest["target"]), WEB_TARGET)
	assert_eq(str(manifest["orientation"]), "portrait")
	var coins: Dictionary = manifest["coin_table"]
	assert_eq(int(coins["divisor"]), 5)
	assert_eq(int(coins["min"]), 4)
	assert_eq(int(coins["max"]), 24)
	assert_true(ResourceLoader.exists(str(manifest["scene"])), "Szene fehlt")
