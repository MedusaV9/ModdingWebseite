extends TestCase
## Korbjagd (basketBounce) — Logik-Parität zum Web (MG-2, Batch 2).
## Die Goldwerte stammen aus `node` auf
## GOOBY/src/minigames/games/basketBounce.logic.js (simulateBasketAutoplay /
## simulateShot) — sie beweisen, dass der GDScript-Port zahlengleich rechnet.

const Logic := preload("res://scripts/minigames/games/basket_bounce/basket_bounce_logic.gd")

## Web-Goldwerte: simulateBasketAutoplay(mode, seed).score für Seeds 1..5.
const GOLD := {
	"easy": [127, 120, 118, 157, 137],
	"normal": [110, 96, 109, 125, 115],
	"hard": [95, 89, 56, 97, 92],
	"endless": [502, 408, 149, 21, 194],
}


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.BASKET
	assert_eq(float(t["DURATION_SEC"]), 60.0)
	assert_eq(int(t["POINTS_BASKET"]), 3)
	assert_eq(int(t["POINTS_BANK_EXTRA"]), 2)
	assert_eq(int(t["POINTS_SWISH_EXTRA"]), 2)
	assert_eq(int(t["SWISH_STREAK_FROM"]), 2)
	assert_eq(int(t["SLIDE_AFTER_BASKETS"]), 10)
	assert_eq(int(t["MOVING_SWISH_MULT"]), 2)
	assert_almost(float(t["DIST_START"]), 5.2)
	assert_almost(float(t["DIST_PER_BASKET"]), 0.35)
	assert_almost(float(t["DIST_MAX"]), 8.0)
	assert_almost(float(t["RIM_R"]), 0.46)
	assert_almost(float(t["RIM_Y"]), 2.6)
	assert_almost(float(t["GRAVITY"]), 9.8)
	assert_eq(int(t["ENDLESS_CONSECUTIVE_MISSES"]), 3)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(mode, i + 1)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		var a: Dictionary = Logic.simulate_autoplay(mode, 7)
		var b: Dictionary = Logic.simulate_autoplay(mode, 7)
		assert_eq(a, b, mode)
		assert_ne(a["score"], Logic.simulate_autoplay(mode, 8)["score"])


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 41):
			sum += int(Logic.simulate_autoplay(mode, seed_value)["score"])
		means[mode] = float(sum) / 40.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_hard_bot_reaches_target() -> void:
	# §G5.4: der Schwer-Bot muss das Ziel 65 in mindestens einem von 5 Seeds
	# schaffen — sonst wäre die Difficulty unbeatbar getunt.
	var best := 0
	for seed_value in range(1, 6):
		best = maxi(best, int(Logic.simulate_autoplay("hard", seed_value)["score"]))
	assert_true(best >= 65, "bester Schwer-Score %d < Ziel 65" % best)


func test_endless_ends_on_three_misses() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.BASKET, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.is_round_over(999.0, 2, tune), "2 Fehlwürfe beenden nicht")
	assert_true(Logic.is_round_over(0.0, 3, tune), "3 Fehlwürfe beenden")
	# Jeder Endlos-Lauf endet am Fehlwurf-Limit ODER am 240-s-Sicherheitsnetz
	# des Bots (nie durch eine Rundenuhr) — und terminiert immer.
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay("endless", seed_value)
		var by_misses := int(run["missStreak"]) >= 3
		var by_guard := float(run["elapsed"]) >= 240.0
		assert_true(by_misses or by_guard, "Endlos terminiert (seed %d)" % seed_value)


func test_timed_mode_ends_on_duration() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.BASKET, "normal")
	assert_false(Logic.is_round_over(59.9, 9, tune))
	assert_true(Logic.is_round_over(60.0, 0, tune))
	var easy: Dictionary = Logic.apply_difficulty(Logic.BASKET, "easy")
	assert_almost(float(easy["DURATION_SEC"]), 72.0)


func test_score_edges() -> void:
	var t: Dictionary = Logic.BASKET
	assert_eq(int(Logic.score_shot({"basket": false}, 5, false, t)["points"]), 0)
	assert_eq(int(Logic.score_shot({"basket": false}, 5, false, t)["swishStreak"]), 0)
	# Erster Swish: nur +3 (Serie beginnt bei 1, Bonus ab 2).
	var first: Dictionary = Logic.score_shot({"basket": true, "swish": true}, 0, false, t)
	assert_eq(int(first["points"]), 3)
	assert_eq(int(first["swishStreak"]), 1)
	# Zweiter Swish: +3 +2.
	assert_eq(int(Logic.score_shot({"basket": true, "swish": true}, 1, false, t)["points"]), 5)
	# Brettwurf: +3 +2.
	assert_eq(int(Logic.score_shot({"basket": true, "bank": true}, 0, false, t)["points"]), 5)
	# Wander-Ring verdoppelt NUR Swishes.
	assert_eq(int(Logic.score_shot({"basket": true, "swish": true}, 1, true, t)["points"]), 10)
	assert_eq(int(Logic.score_shot({"basket": true, "bank": true}, 0, true, t)["points"]), 5)


func test_hoop_ramp_and_slide() -> void:
	var t: Dictionary = Logic.BASKET
	assert_almost(Logic.hoop_distance(0, t), 5.2)
	assert_almost(Logic.hoop_distance(4, t), 6.6)
	assert_almost(Logic.hoop_distance(99, t), 8.0, 1e-9, "Distanz gedeckelt")
	assert_eq(Logic.hoop_slide_x(1.0, 9, t), 0.0, "vor Korb 10 steht der Ring")
	assert_true(absf(Logic.hoop_slide_x(0.9, 10, t)) > 0.1, "ab Korb 10 wandert er")
	assert_true(Logic.is_moving_hoop(10, t))
	assert_false(Logic.is_moving_hoop(9, t))


func test_flick_mapping() -> void:
	var t: Dictionary = Logic.BASKET
	assert_true(Logic.flick_to_velocity(0.0, -100.0, t).is_empty(), "zu schwach")
	var v: Dictionary = Logic.flick_to_velocity(200.0, -1600.0, t)
	assert_almost(float(v["y"]), 6.72)
	assert_almost(float(v["z"]), -4.8)
	assert_almost(float(v["x"]), 0.7)
	# Deckel: eine extreme Geste bleibt bei MAX_SPEED.
	var fast: Dictionary = Logic.flick_to_velocity(0.0, -9000.0, t)
	var speed := sqrt(
		pow(float(fast["x"]), 2.0) + pow(float(fast["y"]), 2.0) + pow(float(fast["z"]), 2.0)
	)
	assert_almost(speed, 13.5, 1e-9)


func test_simulate_shot_matches_web() -> void:
	# Web: simulateShot({x:0,y:7.2,z:-4.1},{x:0,z:-0.6}) → basket, bank, 1.80833…
	var shot: Dictionary = Logic.simulate_shot(
		{"x": 0.0, "y": 7.2, "z": -4.1}, {"x": 0.0, "z": -0.6}
	)
	assert_eq(str(shot["result"]), "basket")
	assert_true(bool(shot["bank"]))
	assert_false(bool(shot["swish"]))
	assert_almost(float(shot["flightSec"]), 1.8083333333333294, 1e-9)


func test_solver_finds_a_basket() -> void:
	var t: Dictionary = Logic.BASKET
	for baskets in [0, 5, 12]:
		var spawn: Dictionary = t["SPAWN"]
		var hoop := {"x": 0.0, "z": float(spawn["z"]) - Logic.hoop_distance(baskets, t)}
		var vel: Dictionary = Logic.solve_basket_velocity(hoop, GoobyRng.new(baskets + 1), t)
		assert_false(vel.is_empty(), "Solver findet Wurf bei %d Körben" % baskets)
		assert_eq(str(Logic.simulate_shot(vel, hoop, t)["result"]), "basket")
