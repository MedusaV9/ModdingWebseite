extends TestCase
## Gooby Runner — Logik-Parität zum Web (MG-3, Batch 3).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/runner.logic.js.

const Logic := preload("res://scripts/minigames/games/runner/runner_logic.gd")

## Web-Goldwerte: simulateRunnerAutoplay(mode, seed).score für Seeds 1..5.
const GOLD := {
	"easy": [3091, 2842, 2998, 2963, 3051],
	"normal": [2453, 392, 1110, 3832, 699],
	"hard": [1521, 293, 1036, 135, 659],
	"endless": [1577, 2562, 2717, 395, 3194],
}
## Web: simulateRunnerAutoplay(...).hits für dieselben Seeds.
const GOLD_HITS := {
	"easy": [1, 2, 1, 1, 2],
	"normal": [2, 2, 2, 1, 2],
	"hard": [2, 2, 2, 2, 2],
	"endless": [3, 3, 3, 3, 3],
}


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.RUNNER
	assert_eq(int(t["LANES"]), 3)
	assert_eq(t["LANE_X"], [-1.1, 0.0, 1.1])
	assert_almost(float(t["BASE_SPEED"]), 6.0)
	assert_almost(float(t["SPEED_RAMP_PCT"]), 0.05)
	assert_almost(float(t["SPEED_RAMP_EVERY_SEC"]), 10.0)
	assert_almost(float(t["MAX_SPEED"]), 13.0)
	assert_almost(float(t["LANE_CHANGE_SEC"]), 0.16)
	assert_almost(float(t["JUMP_SEC"]), 0.62)
	assert_almost(float(t["JUMP_HEIGHT"]), 1.0)
	assert_almost(float(t["SLIDE_SEC"]), 0.65)
	assert_almost(float(t["SLIDE_HEIGHT"]), 0.5)
	assert_almost(float(t["PLAYER_HALF_DEPTH"]), 0.28)
	assert_almost(float(t["DIFFICULTY_FULL_SEC"]), 90.0)
	assert_eq(int(t["COIN_SCORE_BONUS"]), 2)
	assert_eq(t["COMBO_STEPS"], [0, 10, 22])
	assert_eq(int(t["COMBO_MAX_MULT"]), 3)
	assert_eq(int(t["COIN_LINE"]), 3)
	assert_almost(float(t["COIN_LINE_CHANCE"]), 0.75)
	assert_almost(float(t["STUMBLE_INVULN_SEC"]), 1.6)
	assert_eq(int(t["MAX_HITS"]), 2)
	assert_almost(float(t["MAX_SWEEP_STEP_M"]), 0.35)
	assert_almost(float(t["BOT_MISS_CHANCE"]), 0.025)
	var gap: Dictionary = t["ROW_GAP_M"]
	assert_almost(float(gap["start"]), 13.0)
	assert_almost(float(gap["end"]), 8.5)
	var dbl: Dictionary = t["DOUBLE_BLOCK_CHANCE"]
	assert_almost(float(dbl["start"]), 0.25)
	assert_almost(float(dbl["end"]), 0.62)
	assert_eq(
		(t["KIND_WEIGHTS"] as Dictionary).keys(), ["cone", "box", "barrier", "overhead", "car"]
	)
	var cone: Dictionary = (t["OBSTACLES"] as Dictionary)["cone"]
	assert_almost(float(cone["clearY"]), 0.45)
	assert_almost(float(cone["halfDepth"]), 0.22)
	var over: Dictionary = (t["OBSTACLES"] as Dictionary)["overhead"]
	assert_almost(float(over["gapY"]), 0.72)
	assert_almost(float((t["OBSTACLES"] as Dictionary)["car"]["halfDepth"]), 0.95)


func test_difficulty_rows_match_web() -> void:
	var easy: Dictionary = Logic.apply_difficulty(Logic.RUNNER, "easy")
	assert_almost(float(easy["BASE_SPEED"]), 5.1, 1e-9)
	assert_almost(float(easy["MAX_SPEED"]), 11.05, 1e-9)
	assert_almost(float((easy["ROW_GAP_M"] as Dictionary)["start"]), 15.294117647058824, 1e-12)
	assert_almost(float((easy["ROW_GAP_M"] as Dictionary)["end"]), 10.0, 1e-12)
	assert_eq(int(easy["MAX_HITS"]), 3)
	assert_almost(float(easy["BOT_MISS_CHANCE"]), 0.008)
	var hard: Dictionary = Logic.apply_difficulty(Logic.RUNNER, "hard")
	assert_almost(float(hard["BASE_SPEED"]), 7.2, 1e-9)
	assert_almost(float(hard["MAX_SPEED"]), 15.6, 1e-9)
	assert_eq(int(hard["MAX_HITS"]), 2)
	var endless: Dictionary = Logic.apply_difficulty(Logic.RUNNER, "endless")
	assert_almost(float(endless["MAX_SPEED"]), 18.2, 1e-9)
	assert_eq(int(endless["MAX_HITS"]), 3)
	assert_true(bool(endless["ENDLESS"]))
	assert_eq(Logic.apply_difficulty(Logic.RUNNER, "normal"), Logic.RUNNER)
	# Die Basis-Tabelle darf durch abgeleitete Modi NIE mutieren.
	assert_almost(float((Logic.RUNNER["ROW_GAP_M"] as Dictionary)["start"]), 13.0)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		var want_hits: Array = GOLD_HITS[mode]
		for i in want.size():
			var run: Dictionary = Logic.simulate_autoplay(mode, i + 1)
			assert_eq(int(run["score"]), int(want[i]), "%s seed %d score" % [mode, i + 1])
			assert_eq(int(run["hits"]), int(want_hits[i]), "%s seed %d hits" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(mode, 11), Logic.simulate_autoplay(mode, 11), mode)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 41):
			sum += int(Logic.simulate_autoplay(mode, seed_value)["score"])
		means[mode] = float(sum) / 40.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_bot_reaches_target() -> void:
	# Ziel 380 (difficultyTargets.runner) — der Bot muss es auf Mittel schaffen.
	var best := 0
	for seed_value in range(1, 6):
		best = maxi(best, int(Logic.simulate_autoplay("normal", seed_value)["score"]))
	assert_true(best >= 380, "bester Mittel-Score %d < Ziel 380" % best)


func test_endless_terminates() -> void:
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay("endless", seed_value)
		var by_hits := int(run["hits"]) >= 3
		var by_guard := float(run["elapsed"]) >= 180.0
		assert_true(by_hits or by_guard, "Endlos terminiert (seed %d)" % seed_value)


func test_speed_and_difficulty_ramp() -> void:
	assert_almost(Logic.speed_at(0.0), 6.0, 1e-12)
	assert_almost(Logic.speed_at(5.0), 6.0, 1e-12)
	assert_almost(Logic.speed_at(10.0), 6.3, 1e-12)
	assert_almost(Logic.speed_at(25.0), 6.615, 1e-12)
	assert_almost(Logic.speed_at(60.0), 8.040573844, 1e-9)
	assert_almost(Logic.speed_at(200.0), 13.0, 1e-12, "MAX_SPEED deckelt")
	assert_almost(Logic.difficulty_at(0.0), 0.0)
	assert_almost(Logic.difficulty_at(45.0), 0.5)
	assert_almost(Logic.difficulty_at(200.0), 1.0, 1e-12, "Rampe deckelt")
	assert_almost(Logic.row_gap_at(0.0), 13.0, 1e-12)
	assert_almost(Logic.row_gap_at(0.5), 10.75, 1e-12)
	assert_almost(Logic.row_gap_at(1.0), 8.5, 1e-12)


func test_combo_and_score_edges() -> void:
	assert_eq(Logic.combo_multiplier(0), 1)
	assert_eq(Logic.combo_multiplier(9), 1)
	assert_eq(Logic.combo_multiplier(10), 2)
	assert_eq(Logic.combo_multiplier(21), 2)
	assert_eq(Logic.combo_multiplier(22), 3)
	assert_eq(Logic.combo_multiplier(100), 3, "COMBO_MAX_MULT deckelt")
	assert_eq(Logic.runner_score(123.9, 40.4), 163)
	assert_eq(Logic.final_runner_score(123.9, 40.4), 163)
	assert_eq(Logic.runner_score(-5.0, 0.0), 0, "nie negativ")
	assert_eq(Logic.mystery_coin_points(1, false), 2)
	assert_eq(Logic.mystery_coin_points(2, true), 8)
	assert_eq(Logic.mystery_coin_points(3, false), 6)
	assert_eq(Logic.crossed_runner_milestone(98.0, 103.0), 100)
	assert_eq(Logic.crossed_runner_milestone(101.0, 105.0), 0)
	# COIN_RATE 1 verbraucht KEINEN rng-Zug (Bernoulli nur bei Bruchteil).
	var rng := GoobyRng.new(4)
	assert_eq(Logic.coin_line_count(rng), 3)
	assert_eq(Logic.coin_line_count(rng), 3)


func test_collision_windows() -> void:
	assert_true(Logic.hits_obstacle({"lane": 1, "y": 0.0, "sliding": false}, _obs(1, "cone")))
	assert_false(Logic.hits_obstacle({"lane": 1, "y": 0.5, "sliding": false}, _obs(1, "cone")))
	assert_false(Logic.hits_obstacle({"lane": 1, "y": 0.0, "sliding": true}, _obs(1, "overhead")))
	assert_true(Logic.hits_obstacle({"lane": 1, "y": 0.0, "sliding": false}, _obs(1, "overhead")))
	assert_false(Logic.hits_obstacle({"lane": 0, "y": 0.0, "sliding": false}, _obs(1, "car")))
	assert_true(Logic.hits_obstacle({"lane": 1, "y": 3.0, "sliding": false}, _obs(1, "car")))
	assert_true(Logic.action_passes("cone", "jump"))
	assert_false(Logic.action_passes("cone", "slide"))
	assert_true(Logic.action_passes("overhead", "slide"))
	assert_false(Logic.action_passes("car", "jump"))
	# Anti-Tunneling: ein 4-m-Sprung über das Fenster wird trotzdem erkannt.
	var far := {"lane": 1, "kind": "cone", "z": 2.0}
	assert_true(Logic.sweep_hits_obstacle({"lane": 1, "y": 0.0, "sliding": false}, far, -4.0))


func test_pattern_survivability() -> void:
	assert_eq(Logic.max_lane_shift(13.0, 6.0), 2)
	assert_eq(Logic.max_lane_shift(8.5, 13.0), 1)
	assert_eq(Logic.max_lane_shift(4.0, 13.0), 0)
	var blocked := {"lanes": ["car", "car", "car"], "gap": 13.0}
	assert_false(Logic.is_pattern_survivable([blocked], 6.0), "alle Spuren zu = unmöglich")
	var jumpable := {"lanes": ["cone", "cone", "cone"], "gap": 13.0}
	assert_true(Logic.is_pattern_survivable([jumpable], 6.0), "springbar bleibt möglich")
	var far_left := {"lanes": [null, "car", "car"], "gap": 3.0}
	var far_right := {"lanes": ["car", "car", null], "gap": 3.0}
	assert_false(
		Logic.is_pattern_survivable([far_left, far_right], 13.0), "2 Spuren in 3 m sind zu weit"
	)
	assert_true(Logic.is_pattern_survivable([far_left, far_right], 3.0), "langsam reicht die Zeit")
	assert_eq(Logic.passable_lanes({"lanes": [null, "car", "overhead"]}), [true, false, true])


func test_generate_row_matches_web() -> void:
	# Web mit demselben mulberry32-Strom (Seed 7): sechs Zeilen in Folge.
	var want_lanes := [
		[null, null, "barrier"],
		["box", null, null],
		[null, "cone", "overhead"],
		["barrier", null, null],
		["cone", null, null],
		["overhead", null, null],
	]
	var want_gap := [
		13.007052319, 14.384606612, 12.502556915, 13.781987139, 14.312334368, 12.453290634
	]
	var rng := GoobyRng.new(7)
	var rows: Array = []
	for i in want_lanes.size():
		var row: Dictionary = Logic.generate_row(rng, i * 2.0, rows)
		rows.append(row)
		assert_eq(row["lanes"], want_lanes[i], "Zeile %d" % i)
		assert_almost(float(row["gap"]), float(want_gap[i]), 1e-8, "Abstand %d" % i)
	# Erzeugte Zeilen sind IMMER überlebbar (§C6.1 #6).
	var rng2 := GoobyRng.new(23)
	var chain: Array = []
	for i in 60:
		chain.append(Logic.generate_row(rng2, i * 1.5, chain))
	assert_true(
		Logic.is_pattern_survivable(chain, Logic.speed_at(90.0)), "60 Zeilen bleiben überlebbar"
	)


func test_lane_order_shuffle_matches_v8() -> void:
	# V8s TimSort verbraucht 2–4 rng-Züge; der Verbrauch MUSS stimmen, sonst
	# laufen alle folgenden Würfe auseinander. Goldwerte aus Node.
	var seen := {}
	var rng := GoobyRng.new(5)
	for _i in 400:
		var order: Array = Logic.shuffle_lane_order(rng)
		assert_eq(order.size(), 3)
		var key := str(order)
		seen[key] = int(seen.get(key, 0)) + 1
	assert_true(seen.size() >= 4, "mehrere Permutationen (%s)" % seen)
	for key: String in seen:
		var order: Array = str_to_var(key)
		order.sort()
		assert_eq(order, [0, 1, 2], "Permutation bleibt vollständig: %s" % key)


func test_mystery_powers() -> void:
	var rng := GoobyRng.new(3)
	var got: Array[String] = []
	for _i in 6:
		got.append(Logic.roll_mystery_power(rng))
	assert_eq(got, ["shield", "x2", "magnet", "magnet", "magnet", "shield"])
	var state := {"magnetT": 0.0, "x2T": 0.0, "shield": false}
	assert_almost(float(Logic.activate_mystery_power(state, "magnet")["magnetT"]), 4.0)
	assert_almost(float(Logic.activate_mystery_power(state, "x2")["x2T"]), 6.0)
	assert_true(bool(Logic.activate_mystery_power(state, "shield")["shield"]))
	assert_true(Logic.magnet_collects(Vector3(0, 0, 2), Vector3.ZERO, true))
	assert_false(Logic.magnet_collects(Vector3(0, 0, 4), Vector3.ZERO, true))
	assert_false(Logic.magnet_collects(Vector3(0, 0, 2), Vector3.ZERO, false))


func test_hit_resolution() -> void:
	var fresh := {"hits": 0, "shield": false, "invulnT": 0.0}
	var first: Dictionary = Logic.resolve_runner_hit(fresh)
	assert_eq(str(first["outcome"]), "stumble")
	assert_eq(int(first["hits"]), 1)
	assert_almost(float(first["invulnT"]), 1.6)
	var second: Dictionary = Logic.resolve_runner_hit({"hits": 1, "shield": false, "invulnT": 0.0})
	assert_eq(str(second["outcome"]), "wipeout")
	var shielded: Dictionary = Logic.resolve_runner_hit({"hits": 1, "shield": true, "invulnT": 0.0})
	assert_eq(str(shielded["outcome"]), "shielded")
	assert_eq(int(shielded["hits"]), 1, "Schild kostet keinen Treffer")
	assert_false(bool(shielded["shield"]), "Schild verbraucht sich")
	var ignored: Dictionary = Logic.resolve_runner_hit({"hits": 1, "shield": false, "invulnT": 0.9})
	assert_eq(str(ignored["outcome"]), "ignored")
	assert_eq(int(ignored["hits"]), 1)
	# Leicht hält einen Treffer mehr aus.
	var easy: Dictionary = Logic.apply_difficulty(Logic.RUNNER, "easy")
	assert_eq(
		str(
			Logic.resolve_runner_hit({"hits": 1, "shield": false, "invulnT": 0.0}, easy)["outcome"]
		),
		"stumble"
	)


func test_modifier_hooks() -> void:
	var turbo: Dictionary = Logic.apply_modifier(
		Logic.RUNNER, {"type": "turbo", "speedMult": 1.5, "scoreMult": 2.0}
	)
	assert_almost(float(turbo["BASE_SPEED"]), 9.0, 1e-9)
	assert_almost(float(turbo["MAX_SPEED"]), 19.5, 1e-9)
	assert_eq(Logic.final_runner_score(100.0, 0.0, turbo), 200)
	var rain: Dictionary = Logic.apply_modifier(
		Logic.RUNNER, {"type": "muenzregen", "coinRate": 1.5}
	)
	assert_almost(float(rain["COIN_RATE"]), 1.5)
	# 4.5 erwartete Münzen = 4 sicher + Bernoulli auf 0.5.
	var counts := {}
	var rng := GoobyRng.new(9)
	for _i in 200:
		var n := Logic.coin_line_count(rng, rain)
		counts[n] = int(counts.get(n, 0)) + 1
	assert_eq(counts.keys().size(), 2, "nur 4 oder 5 (%s)" % counts)
	assert_true(int(counts.get(4, 0)) > 50 and int(counts.get(5, 0)) > 50, "%s" % counts)
	var giant: Dictionary = Logic.apply_modifier(
		Logic.RUNNER, {"type": "riesenGooby", "hitboxMult": 1.5, "scale": 1.4}
	)
	assert_almost(float(giant["PLAYER_HALF_DEPTH"]), 0.42, 1e-9)
	assert_almost(float(giant["RENDER_SCALE_MULT"]), 1.4)
	assert_eq(Logic.apply_modifier(Logic.RUNNER, {}), Logic.RUNNER)


func _obs(lane: int, kind: String) -> Dictionary:
	return {"lane": lane, "kind": kind, "z": 0.0}
