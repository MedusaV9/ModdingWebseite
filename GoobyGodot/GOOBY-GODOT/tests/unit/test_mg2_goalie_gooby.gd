extends TestCase
## Torwart-Gooby (goalieGooby) — Logik-Parität zum Web (MG-2, Batch 2).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/goalieGooby.logic.js.

const Logic := preload("res://scripts/minigames/games/goalie_gooby/goalie_gooby_logic.gd")

## Web-Goldwerte: simulateAutoplay(seed, mode).score für Seeds 1..5.
const GOLD := {
	"easy": [220, 228, 232, 148, 232],
	"normal": [164, 168, 164, 136, 172],
	"hard": [124, 68, 180, 124, 188],
	"endless": [132, 68, 160, 116, 224],
}


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.GOALIE
	assert_almost(float(t["DURATION_SEC"]), 60.0)
	assert_eq(int(t["LANES"]), 5)
	assert_almost(float(t["TELEGRAPH_START_SEC"]), 0.9)
	assert_almost(float(t["TELEGRAPH_END_SEC"]), 0.45)
	assert_almost(float(t["TELEGRAPH_RAMP_SEC"]), 60.0)
	assert_eq(int(t["SAVE_PTS"]), 4)
	assert_eq(int(t["SUPER_PTS"]), 2)
	assert_almost(float(t["SUPER_WINDOW_SEC"]), 0.15)
	assert_eq(int(t["MAX_GOALS"]), 3)
	assert_eq(int(t["CHEER_EVERY_SAVES"]), 10)
	assert_almost(float(t["CHEER_SPEED_MULT"]), 1.1)
	assert_almost(float(t["MIX_FROM_SEC"]), 8.0)
	assert_almost(float(t["LOB_CHANCE"]), 0.22)
	assert_almost(float(t["ROLLER_CHANCE"]), 0.22)
	assert_almost(float(t["FLIGHT_SEC"]), 0.55)
	assert_almost(float(t["GAP_SEC"]), 0.8)
	assert_almost(float(t["DIVE_HOLD_SEC"]), 0.45)
	assert_almost(float(t["LANE_INNER_DEG"]), 18.0)
	assert_almost(float(t["LANE_OUTER_DEG"]), 54.0)
	assert_almost(float(t["SHOOTOUT_START_SEC"]), 50.0)
	assert_eq(int(t["SHOOTOUT_SHOTS"]), 5)
	assert_eq(int(t["SHOOTOUT_SAVE_MULT"]), 2)
	assert_almost(float(Logic.GOALIE_JUICE["RING_LIFE_SEC"]), 0.38)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])
	# Detailwerte eines Laufs (Web: 33 Paraden, 1 Gegentor, 60.25 s).
	var run: Dictionary = Logic.simulate_autoplay(3, "normal")
	assert_eq(int(run["saves"]), 33)
	assert_eq(int(run["goals"]), 1)
	assert_almost(float(run["elapsed"]), 60.25118963350744, 1e-9)


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(6, mode), Logic.simulate_autoplay(6, mode), mode)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 41):
			sum += int(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = float(sum) / 40.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)
	var easy: Dictionary = Logic.apply_difficulty(Logic.GOALIE, "easy")
	assert_almost(float(easy["DURATION_SEC"]), 72.0)
	assert_almost(float(easy["GAP_SEC"]), 0.96)
	assert_almost(float(easy["TELEGRAPH_START_SEC"]), 1.125)
	assert_almost(float(easy["TELEGRAPH_END_SEC"]), 0.5625)
	assert_almost(float(easy["DIVE_HOLD_SEC"]), 0.5625)
	assert_almost(float(easy["SHOOTOUT_TELEGRAPH_SEC"]), 0.475)
	assert_almost(float(easy["AUTOPLAY_SKILL_MULT"]), 0.08)
	var hard: Dictionary = Logic.apply_difficulty(Logic.GOALIE, "hard")
	assert_almost(float(hard["GAP_SEC"]), 0.68)
	assert_almost(float(hard["TELEGRAPH_START_SEC"]), 0.7200000000000001)
	assert_almost(float(hard["TELEGRAPH_END_SEC"]), 0.36000000000000004)
	assert_almost(float(hard["SHOOTOUT_TELEGRAPH_SEC"]), 0.35, 1e-12, "Boden 0.35 s")
	assert_almost(float(hard["AUTOPLAY_SKILL_MULT"]), 0.2)
	assert_eq(Logic.apply_difficulty(Logic.GOALIE, "unsinn"), Logic.GOALIE)


func test_hard_bot_reaches_target() -> void:
	# §G5.4-Ziel für goalieGooby ist 65.
	for seed_value in range(1, 6):
		var score: int = int(Logic.simulate_autoplay(seed_value, "hard")["score"])
		assert_true(score >= 65, "Schwer-Score %d < Ziel 65 (seed %d)" % [score, seed_value])


func test_endless_ends_on_three_goals() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.GOALIE, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.endless_should_end(2, tune))
	assert_true(Logic.endless_should_end(3, tune))
	assert_false(Logic.endless_should_end(9, Logic.GOALIE), "nur im Endlos-Modus")
	# Kein Elfmeterfinale im Endlos-Modus, und jeder Lauf terminiert.
	assert_false(Logic.is_shootout_at(55.0, tune))
	for seed_value in range(1, 16):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "endless")
		assert_true(
			int(run["goals"]) >= 3 or float(run["elapsed"]) >= 600.0,
			"Endlos terminiert (seed %d)" % seed_value
		)


func test_telegraph_and_speed_ramp() -> void:
	assert_almost(Logic.telegraph_sec_at(0.0), 0.9)
	assert_almost(Logic.telegraph_sec_at(15.0), 0.7875)
	assert_almost(Logic.telegraph_sec_at(30.0), 0.675)
	assert_almost(Logic.telegraph_sec_at(60.0), 0.45)
	assert_almost(Logic.telegraph_sec_at(99.0), 0.45, 1e-9, "gedeckelt")
	assert_almost(Logic.telegraph_sec_at(-5.0), 0.9, 1e-9, "unten gedeckelt")
	assert_almost(Logic.speed_mult_at(0), 1.0)
	assert_almost(Logic.speed_mult_at(1), 1.1)
	assert_almost(Logic.speed_mult_at(3), 1.3310000000000004)
	assert_almost(Logic.speed_mult_at(-4), 1.0, 1e-9)
	assert_almost(Logic.flight_sec_at(2), 0.45454545454545453, 1e-12)
	assert_eq(Logic.cheers_at(0), 0)
	assert_eq(Logic.cheers_at(9), 0)
	assert_eq(Logic.cheers_at(10), 1)
	assert_eq(Logic.cheers_at(25), 2)
	assert_eq(Logic.cheers_at(-3), 0)


func test_swipe_mapping() -> void:
	assert_eq(Logic.lane_from_swipe(0.0, -100.0), 2, "gerade nach oben = Mitte")
	assert_eq(Logic.lane_from_swipe(-30.0, -100.0), 2)
	assert_eq(Logic.lane_from_swipe(-100.0, -100.0), 1)
	assert_eq(Logic.lane_from_swipe(-400.0, -100.0), 0)
	assert_eq(Logic.lane_from_swipe(100.0, -30.0), 4)
	assert_eq(Logic.lane_from_swipe(30.0, -100.0), 2)
	assert_eq(Logic.lane_from_swipe(0.0, 0.0), 2, "Tippen = Mitte")
	assert_eq(Logic.v_kind_from_swipe(-30.0), "up")
	assert_eq(Logic.v_kind_from_swipe(0.0), "mid")
	assert_eq(Logic.v_kind_from_swipe(30.0), "down")
	assert_eq(Logic.v_kind_from_swipe(-24.0), "up", "Grenze zählt")
	assert_eq(Logic.v_kind_from_swipe(24.0), "down")


func test_save_matching_and_windows() -> void:
	var t: Dictionary = Logic.GOALIE
	assert_true(Logic.save_matches({"lane": 2, "kind": "straight"}, {"lane": 2, "v": "mid"}))
	assert_false(Logic.save_matches({"lane": 2, "kind": "straight"}, {"lane": 3, "v": "mid"}))
	assert_true(Logic.save_matches({"lane": 1, "kind": "lob"}, {"lane": 1, "v": "up"}))
	assert_false(Logic.save_matches({"lane": 1, "kind": "lob"}, {"lane": 1, "v": "mid"}))
	assert_true(Logic.save_matches({"lane": 4, "kind": "roller"}, {"lane": 4, "v": "down"}))
	assert_false(Logic.save_matches({"lane": 4, "kind": "roller"}, {"lane": 4, "v": "up"}))
	# Haltefenster + Superfenster (inkl. Float-Rand).
	assert_true(Logic.dive_covers(10.0, 10.45, t), "Grenze 0.45 s")
	assert_false(Logic.dive_covers(10.0, 10.46, t))
	assert_false(Logic.dive_covers(10.5, 10.0, t), "zu spät gehechtet")
	assert_true(Logic.is_super_save(10.0, 10.15, t), "Grenze 0.15 s")
	assert_false(Logic.is_super_save(10.0, 10.2, t))


func test_score_edges_and_shootout() -> void:
	assert_eq(Logic.save_points(false), 4)
	assert_eq(Logic.save_points(true), 6)
	assert_eq(Logic.save_points(false, true), 8, "Finale verdoppelt")
	assert_eq(Logic.save_points(true, true), 12)
	assert_false(Logic.is_shootout_at(49.9))
	assert_true(Logic.is_shootout_at(50.0))
	assert_true(Logic.is_shootout_at(60.0))
	assert_false(Logic.is_shootout_at(61.0))
	assert_almost(Logic.shootout_shot_at(0), 50.0)
	assert_almost(Logic.shootout_shot_at(1), 51.08)
	assert_almost(Logic.shootout_shot_at(4), 54.32)
	assert_almost(Logic.shootout_shot_at(-3), 50.0, 1e-9)


func test_kick_rolls_match_web_stream() -> void:
	var rng := GoobyRng.new(9)
	var stream := func() -> float: return rng.next()
	var got := PackedStringArray()
	for i in 6:
		var kick: Dictionary = Logic.roll_kick(stream, 20.0)
		got.append("%d%s" % [int(kick["lane"]), str(kick["kind"]).substr(0, 1)])
	assert_eq(got, PackedStringArray(["1s", "3s", "0s", "3s", "1s", "0s"]))
	# Vor Sekunde 8 gibt es ausschließlich flache Schüsse.
	var intro := GoobyRng.new(2)
	for i in 20:
		var kick: Dictionary = Logic.roll_kick(func() -> float: return intro.next(), 3.0)
		assert_eq(str(kick["kind"]), "straight")
		assert_true(int(kick["lane"]) >= 0 and int(kick["lane"]) <= 4)


func test_bot_error_ramp_and_riesen_gooby() -> void:
	assert_almost(Logic.autoplay_err_at(0.9), 0.07)
	assert_almost(Logic.autoplay_err_at(0.7), 0.28333333333333344, 1e-12)
	assert_almost(Logic.autoplay_err_at(0.45), 0.55)
	assert_almost(Logic.autoplay_err_at(0.2), 0.55, 1e-9, "gedeckelt")
	assert_almost(Logic.autoplay_err_at(0.9, Logic.GOALIE, 0.5), 0.035)
	var riesen: Dictionary = Logic.apply_riesen_gooby(
		Logic.GOALIE, {"scale": 1.6, "hitboxMult": 1.4}
	)
	assert_almost(float(riesen["RENDER_SCALE"]), 1.6)
	assert_almost(float(riesen["HITBOX_MULT"]), 1.4)
	assert_almost(float(riesen["DIVE_HOLD_SEC"]), 0.63)
	var plain: Dictionary = Logic.apply_riesen_gooby(Logic.GOALIE, {"scale": 0.2})
	assert_almost(float(plain["RENDER_SCALE"]), 1.0, 1e-9, "nie kleiner als 1")
