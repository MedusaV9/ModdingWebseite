extends TestCase
## carrotCatch-Bot-Zertifizierung: 4 Modi × 50 Seeds gegen die Web-Logik
## (tests/expected/carrotCatch.json aus tools/cross_check.mjs).


func test_bot_certification_matches_web() -> void:
	var fixture: Variant = JsonFixtures.load_json("res://tests/expected/carrotCatch.json")
	assert_true(
		fixture is Dictionary, "carrotCatch.json fehlt — tools/cross_check.mjs laufen lassen"
	)
	if not (fixture is Dictionary):
		return
	var modes: Dictionary = fixture["modes"]
	var runs := 0
	for mode: String in modes:
		for entry: Dictionary in modes[mode]:
			var got := CarrotCatchLogic.simulate_autoplay(mode, int(entry["seed"]))
			var tag := "%s seed=%d" % [mode, int(entry["seed"])]
			assert_eq(got["score"], int(entry["score"]), "%s score" % tag)
			assert_eq(got["missedCarrots"], int(entry["missedCarrots"]), "%s missed" % tag)
			assert_almost(got["elapsed"], float(entry["elapsed"]), 1e-9, "%s elapsed" % tag)
			runs += 1
	assert_true(runs >= 200, "erwartet 4x50 Bot-Laeufe, war %d" % runs)


func test_tune_parity_normal_and_hard() -> void:
	var fixture: Variant = JsonFixtures.load_json("res://tests/expected/carrotCatch.json")
	if not (fixture is Dictionary):
		fail_test("carrotCatch.json fehlt")
		return
	var tunes: Dictionary = fixture["tune"]
	for mode: String in tunes:
		var want: Dictionary = tunes[mode]
		var got := CarrotCatchLogic.apply_difficulty(CarrotCatchLogic.CATCH, mode)
		for key: String in want:
			var wv: Variant = want[key]
			if wv is bool or wv is String:
				assert_eq(got.get(key), wv, "tune[%s].%s" % [mode, key])
			else:
				assert_almost(float(got[key]), float(wv), 1e-12, "tune[%s].%s" % [mode, key])


func test_roll_item_and_scoring() -> void:
	# Deterministische Stichprobe: Verteilung plausibel + Werte im Kontrakt.
	var rng := GoobyRng.new(1)
	var kinds := {"good": 0, "junk": 0, "rotten": 0}
	for _i in 400:
		var item := CarrotCatchLogic.roll_item(rng, 30.0)
		kinds[item["kind"]] = int(kinds[item["kind"]]) + 1
		if item["kind"] == "good":
			assert_true(int(item["value"]) >= 1 and int(item["value"]) <= 3)
		else:
			assert_eq(int(item["value"]), -2)
	assert_true(int(kinds["good"]) > 250, "gutes Essen dominiert (%s)" % [kinds])
	assert_true(int(kinds["junk"]) + int(kinds["rotten"]) > 30, "Junk kommt vor (%s)" % [kinds])
	assert_eq(CarrotCatchLogic.apply_catch(1, -2), 0, "Score floort bei 0")
	assert_eq(CarrotCatchLogic.apply_catch(5, 3), 8)
	var st := CarrotCatchLogic.apply_catch_state(
		{"score": 4, "combo": 2}, {"kind": "good", "value": 2}
	)
	assert_eq(st["combo"], 3, "good verlaengert Combo")
	st = CarrotCatchLogic.apply_catch_state(
		{"score": 4, "combo": 3}, {"kind": "rotten", "value": -2}
	)
	assert_eq(st["combo"], 0, "faule Moehre bricht Combo")
	assert_true(CarrotCatchLogic.combo_milestone(5))
	assert_false(CarrotCatchLogic.combo_milestone(4))


func test_ramps_and_geometry() -> void:
	assert_almost(CarrotCatchLogic.junk_ratio_at(0.0), 0.1, 1e-12)
	assert_almost(CarrotCatchLogic.junk_ratio_at(60.0), 0.3, 1e-12)
	assert_almost(CarrotCatchLogic.fall_speed_mult_at(9.9), 1.0, 1e-12, "vor 10 s keine Stufe")
	assert_almost(CarrotCatchLogic.fall_speed_mult_at(10.0), 1.08, 1e-12)
	assert_almost(CarrotCatchLogic.spawn_interval_at(0.0), 1.05, 1e-12)
	assert_true(
		CarrotCatchLogic.spawn_interval_at(60.0) < CarrotCatchLogic.spawn_interval_at(0.0),
		"Kadenz zieht an"
	)
	assert_true(CarrotCatchLogic.basket_catches_x(0.0, 0.6))
	assert_false(CarrotCatchLogic.basket_catches_x(0.0, 0.7))
	assert_almost(CarrotCatchLogic.spawn_x_for_roll(0.5, 3.0), 0.0, 1e-12)
	assert_almost(CarrotCatchLogic.spawn_x_for_roll(1.0, 3.0), 2.5, 1e-12)
	var over := CarrotCatchLogic.is_catch_round_over({"elapsed": 60.0, "missedCarrots": 0})
	assert_true(over, "Timed endet bei DURATION_SEC")
	var endless := CarrotCatchLogic.apply_difficulty(CarrotCatchLogic.CATCH, "endless")
	assert_false(
		CarrotCatchLogic.is_catch_round_over({"elapsed": 999.0, "missedCarrots": 2}, endless)
	)
	assert_true(CarrotCatchLogic.is_catch_round_over({"elapsed": 1.0, "missedCarrots": 3}, endless))


func test_turbo_modifier() -> void:
	var tuned := CarrotCatchLogic.apply_modifier(
		CarrotCatchLogic.CATCH, {"type": "turbo", "speedMult": 2.0, "scoreMult": 0.5}
	)
	assert_almost(float(tuned["FALL_BASE_SPEED"]), 4.6, 1e-12)
	assert_almost(float(tuned["SPAWN_BASE_SEC"]), 0.525, 1e-12)
	assert_eq(CarrotCatchLogic.final_catch_score(9, tuned), 5, "9 * 0.5 rundet auf 5 (JS-Regel)")
	var same := CarrotCatchLogic.apply_modifier(CarrotCatchLogic.CATCH, {"type": "anders"})
	assert_eq(same, CarrotCatchLogic.CATCH, "fremde Modifier aendern nichts")
