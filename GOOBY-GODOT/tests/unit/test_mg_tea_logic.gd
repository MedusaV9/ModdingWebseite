extends TestCase
## teaParty-Bot-Zertifizierung: 4 Modi × 50 Seeds gegen die Web-Logik
## (tests/expected/teaParty.json aus tools/cross_check.mjs). score/cups/
## spills exakt, elapsed mit 1e-9 (JSON-Roundtrip); Tune-Parität pro Key.


func test_bot_certification_matches_web() -> void:
	var fixture: Variant = JsonFixtures.load_json("res://tests/expected/teaParty.json")
	assert_true(fixture is Dictionary, "teaParty.json fehlt — tools/cross_check.mjs laufen lassen")
	if not (fixture is Dictionary):
		return
	var modes: Dictionary = fixture["modes"]
	var runs := 0
	for mode: String in modes:
		for entry: Dictionary in modes[mode]:
			var got := TeaPartyLogic.simulate_autoplay(mode, int(entry["seed"]))
			var tag := "%s seed=%d" % [mode, int(entry["seed"])]
			assert_eq(got["score"], int(entry["score"]), "%s score" % tag)
			assert_eq(got["cups"], int(entry["cups"]), "%s cups" % tag)
			assert_eq(got["spills"], int(entry["spills"]), "%s spills" % tag)
			assert_almost(got["elapsed"], float(entry["elapsed"]), 1e-9, "%s elapsed" % tag)
			runs += 1
	assert_true(runs >= 200, "erwartet 4x50 Bot-Laeufe, war %d" % runs)


func test_tune_parity_normal_and_hard() -> void:
	var fixture: Variant = JsonFixtures.load_json("res://tests/expected/teaParty.json")
	if not (fixture is Dictionary):
		fail_test("teaParty.json fehlt")
		return
	var tunes: Dictionary = fixture["tune"]
	for mode: String in tunes:
		var want: Dictionary = tunes[mode]
		var got := TeaPartyLogic.apply_difficulty(TeaPartyLogic.TEA, mode)
		for key: String in want:
			var wv: Variant = want[key]
			if wv is bool:
				assert_eq(got[key], wv, "tune[%s].%s (bool)" % [mode, key])
			else:
				assert_almost(float(got[key]), float(wv), 1e-12, "tune[%s].%s" % [mode, key])


func test_pour_mechanics() -> void:
	var band := {"center": 0.7, "half": 0.075, "perfectHalf": 0.028}
	assert_eq(TeaPartyLogic.pour_result(0.7, band)["result"], "perfect")
	assert_eq(TeaPartyLogic.pour_result(0.75, band)["result"], "good")
	assert_eq(TeaPartyLogic.pour_result(0.5, band)["result"], "miss")
	var over := TeaPartyLogic.pour_result(1.0, band)
	assert_eq(over["result"], "miss", "Overflow ist immer miss")
	assert_true(over["overflow"])
	assert_eq(TeaPartyLogic.streak_bonus_at(3), 2)
	assert_eq(TeaPartyLogic.streak_bonus_at(4), 0)
	assert_eq(TeaPartyLogic.streak_bonus_at(6), 2)
	assert_eq(TeaPartyLogic.apply_score(1, -5), 0, "Score floort bei 0")
	assert_almost(TeaPartyLogic.fill_after(0.2, 0.5), 0.45, 1e-12)
	assert_almost(TeaPartyLogic.serve_interval_at(0.0), 1.7, 1e-12)
	assert_almost(TeaPartyLogic.serve_interval_at(60.0), 1.1, 1e-12)


func test_endless_ends_on_third_spill() -> void:
	var tune := TeaPartyLogic.apply_difficulty(TeaPartyLogic.TEA, "endless")
	assert_false(TeaPartyLogic.endless_should_end(2, tune))
	assert_true(TeaPartyLogic.endless_should_end(3, tune))
	assert_false(TeaPartyLogic.endless_should_end(3, TeaPartyLogic.TEA), "Timed endet nie so")
