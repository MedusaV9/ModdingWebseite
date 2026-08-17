extends TestCase
## Hafen-Hopser — Logik-Parität zum Web (MG-3, Batch 3).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/harborHopper.logic.js.

const Logic := preload("res://scripts/minigames/games/harbor_hopper/harbor_hopper_logic.gd")

## Web: simulateHarborAutoplay(mode, seed).score für Seeds 1..5.
const GOLD_SCORE := {
	"easy": [97, 110, 102, 94, 91],
	"normal": [66, 108, 82, 83, 70],
	"hard": [107, 98, 124, 103, 71],
	"endless": [65, 109, 71, 89, 47],
}
## Dieselben Läufe: Kisten / Bumps / Meter.
const GOLD_CRATES := {
	"easy": [21, 24, 18, 22, 20],
	"normal": [13, 24, 15, 18, 13],
	"hard": [24, 20, 26, 24, 17],
	"endless": [16, 24, 16, 20, 12],
}
const GOLD_BUMPS := {
	"easy": [1, 0, 0, 2, 1],
	"normal": [2, 0, 0, 1, 0],
	"hard": [1, 2, 2, 1, 5],
	"endless": [3, 3, 3, 3, 3],
}
const GOLD_DIST := {
	"easy": [798, 804, 798, 791, 787],
	"normal": [755, 788, 777, 770, 781],
	"hard": [932, 917, 913, 932, 909],
	"endless": [666, 994, 689, 839, 404],
}
## Web: Mittelwert über Seeds 1..40.
const GOLD_MEAN := {"easy": 102.325, "normal": 84.175, "hard": 96.6}
## Web: rowReachability(applyDifficulty(HARBOR, mode)).
const GOLD_REACH := {
	"easy": 2.2700304390445236,
	"normal": 1.9295258731878449,
	"hard": 1.6079382276565377,
	"endless": 1.2059536707424032,
}


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.HARBOR
	assert_almost(float(t["DURATION_SEC"]), 120.0)
	assert_almost(float(t["BASE_SPEED"]), 6.0)
	assert_almost(float(t["CHANNEL_HALF_W"]), 3.2)
	assert_eq(int(t["LANES"]), 3)
	assert_almost(float(t["STEER_ACCEL"]), 6.5)
	assert_almost(float(t["STEER_DAMPING"]), 2.6)
	assert_almost(float(t["MAX_LATERAL_SPEED"]), 3.4)
	assert_eq(int(t["CRATE_POINTS"]), 4)
	assert_eq(int(t["RING_POINTS"]), 2)
	assert_almost(float(t["CRATE_RADIUS"]), 0.8)
	assert_almost(float(t["RING_RADIUS"]), 0.85)
	assert_eq(int(t["BUMP_PENALTY"]), -3)
	assert_almost(float(t["HITBOX_SCALE"]), 0.7)
	assert_almost(float(t["BUOY_RADIUS"]), 0.75)
	assert_almost(float(t["BOAT_RADIUS"]), 0.6)
	assert_almost(float(t["PIER_REACH_M"]), 2.1)
	assert_almost(float(t["PIER_DEPTH_M"]), 1.1)
	assert_almost(float(t["SLOW_FACTOR"]), 0.55)
	assert_almost(float(t["SLOW_SEC"]), 1.4)
	assert_almost(float(t["BUMP_IFRAMES_SEC"]), 1.0)
	assert_almost(float(t["BUMP_SHOVE"]), 2.2)
	assert_almost(float((t["ROW_GAP_M"] as Dictionary)["min"]), 11.0)
	assert_almost(float((t["ROW_GAP_M"] as Dictionary)["max"]), 15.0)
	assert_almost(float(t["CRATE_CHANCE"]), 0.44)
	assert_almost(float(t["RING_CHANCE"]), 0.2)
	assert_almost(float(t["BUOY_CHANCE"]), 0.26)
	assert_almost(float((t["PIER_EVERY_M"] as Dictionary)["min"]), 70.0)
	assert_almost(float((t["PIER_EVERY_M"] as Dictionary)["max"]), 110.0)
	assert_almost(float(t["LOOKAHEAD_M"]), 60.0)
	assert_almost(float(t["WAVE_EVERY_SEC"]), 6.0)
	assert_almost(float(t["WAVE_SPEED"]), 2.5)
	assert_almost(float(t["WAVE_SPAWN_AHEAD_M"]), 34.0)
	assert_almost(float(t["SWEET_HALF_W"]), 1.05)
	assert_almost(float(t["BOOST_FACTOR"]), 1.3)
	assert_almost(float(t["BOOST_SEC"]), 2.0)
	assert_almost(float(t["GULL_IDLE_SEC"]), 4.0)
	assert_almost(float(t["GULL_WARN_SEC"]), 1.5)
	assert_eq(int(t["HORN_CHARGES"]), 2)
	assert_almost(float(t["HORN_CONE_M"]), 6.0)
	assert_almost(float(t["HORN_CONE_BASE"]), 0.9)
	assert_almost(float(t["HORN_CONE_SPREAD"]), 0.45)
	assert_almost(float(t["MAX_DT"]), 1.0 / 20.0)
	assert_eq(int(t["ENDLESS_BUMP_LIMIT"]), 3)
	assert_almost(float(t["ENDLESS_ACCEL_PER_M"]), 0.004)
	assert_almost(float(t["ENDLESS_MAX_SPEED"]), 9.6)
	assert_almost(float(t["VALIDATOR_REACT_SEC"]), 0.35)
	assert_almost(float(t["VALIDATOR_DODGE_MARGIN_M"]), 0.35)
	assert_almost(float(t["BOT_GULL_DODGE_AT_SEC"]), 4.6)
	assert_almost(float(Logic.HARBOR_JUICE["CRATE_POP_SEC"]), 0.35)


func test_difficulty_rows_match_web() -> void:
	assert_true(Logic.apply_difficulty(Logic.HARBOR, "normal") == Logic.HARBOR)
	var easy := Logic.apply_difficulty(Logic.HARBOR, "easy")
	assert_almost(float(easy["BASE_SPEED"]), 6.0 * 0.85)
	assert_almost(float(easy["DURATION_SEC"]), 144.0)
	assert_almost(float(easy["BUOY_CHANCE"]), 0.26 * 0.85)
	assert_almost(float((easy["PIER_EVERY_M"] as Dictionary)["min"]), 70.0 / 0.85)
	assert_almost(float(easy["BOT_LAPSE_EVERY_SEC"]), 34.0)
	assert_false(bool(easy["ENDLESS"]))
	var hard := Logic.apply_difficulty(Logic.HARBOR, "hard")
	assert_almost(float(hard["BASE_SPEED"]), 6.0 * 1.2)
	assert_almost(float(hard["BUOY_CHANCE"]), 0.26 * 1.15)
	assert_almost(float(hard["BOT_LAPSE_EVERY_SEC"]), 12.5)
	assert_false(bool(hard["ENDLESS"]))
	var endless := Logic.apply_difficulty(Logic.HARBOR, "endless")
	assert_true(bool(endless["ENDLESS"]))
	# Unbekannter Modus fällt auf die Basis-Tabelle zurück.
	assert_true(Logic.apply_difficulty(Logic.HARBOR, "quatsch") == Logic.HARBOR)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD_SCORE:
		var scores: Array = GOLD_SCORE[mode]
		for i in scores.size():
			var run: Dictionary = Logic.simulate_autoplay(mode, i + 1)
			var tag := "%s seed %d" % [mode, i + 1]
			assert_eq(int(run["score"]), int(scores[i]), tag + " score")
			assert_eq(int(run["crates"]), int(GOLD_CRATES[mode][i]), tag + " crates")
			assert_eq(int(run["bumps"]), int(GOLD_BUMPS[mode][i]), tag + " bumps")
			assert_eq(int(run["distanceM"]), int(GOLD_DIST[mode][i]), tag + " meters")


func test_simulate_round_matches_web_gold() -> void:
	var run := Logic.simulate_round(7)
	assert_eq(int(run["score"]), 78)
	assert_eq(int(run["crates"]), 14)
	assert_eq(int(run["rings"]), 11)
	assert_eq(int(run["bumps"]), 0)
	assert_eq(int(run["boosts"]), 19)
	assert_eq(int(run["distanceM"]), 788)
	assert_eq(int(run["hornsUsed"]), 2)


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(mode, 9), Logic.simulate_autoplay(mode, 9), mode)


func test_difficulty_means_match_web() -> void:
	# Zahlengleichheit ist die Messlatte: Leicht > Mittel; Schwer liegt höher,
	# weil der schnellere Kanal in derselben Rundenzeit mehr Meter (und damit
	# mehr Reihen) liefert — exakt wie im Web.
	for mode: String in GOLD_MEAN:
		var sum := 0
		for seed_value in range(1, 41):
			sum += int(Logic.simulate_autoplay(mode, seed_value)["score"])
		assert_almost(float(sum) / 40.0, float(GOLD_MEAN[mode]), 1e-9, mode)
	assert_true(float(GOLD_MEAN["easy"]) > float(GOLD_MEAN["normal"]))


func test_bot_reaches_target() -> void:
	# Coin-Ziel 110: der Bot muss im Mittel in Reichweite liegen.
	var sum := 0
	for seed_value in range(1, 21):
		sum += int(Logic.simulate_autoplay("normal", seed_value)["score"])
	assert_true(float(sum) / 20.0 >= 60.0, "Bot-Mittel %f" % (float(sum) / 20.0))


func test_endless_terminates_on_three_bumps() -> void:
	for seed_value in range(1, 13):
		var run := Logic.simulate_autoplay("endless", seed_value, 900.0)
		assert_eq(int(run["bumps"]), 3, "seed %d" % seed_value)
		assert_true(float(run["elapsed"]) < 900.0, "seed %d beendet" % seed_value)


func test_row_reachability_matches_web() -> void:
	for mode: String in GOLD_REACH:
		var tune := Logic.apply_difficulty(Logic.HARBOR, mode)
		var got := Logic.row_reachability(tune)
		assert_almost(got, float(GOLD_REACH[mode]), 1e-12, mode)
		assert_true(got >= 1.0, "%s immer ausweichbar" % mode)


func test_scoring_edges() -> void:
	assert_eq(Logic.apply_score(0, -3), 0)
	assert_eq(Logic.apply_score(2, -3), 0)
	assert_eq(Logic.apply_score(10, 4), 14)
	assert_eq(Logic.hopper_score({"score": 41}), 41)
	var turbo := Logic.apply_modifier(
		Logic.HARBOR, {"type": "turbo", "speedMult": 1.25, "scoreMult": 1.5}
	)
	assert_eq(Logic.hopper_score({"score": 41}, turbo), 62)
	assert_almost(float(turbo["BASE_SPEED"]), 7.5)


func test_lane_and_speed() -> void:
	assert_eq(Logic.lane_of(-3.2), 0)
	assert_eq(Logic.lane_of(-1.2), 0)
	assert_eq(Logic.lane_of(0.0), 1)
	assert_eq(Logic.lane_of(1.2), 2)
	assert_eq(Logic.lane_of(99.0), 2)
	var idle := {"boostT": 0.0, "slowT": 0.0, "z": 0.0}
	assert_almost(Logic.speed_of(idle), 6.0)
	assert_almost(Logic.speed_of({"boostT": 1.0, "slowT": 0.0, "z": 0.0}), 7.8)
	assert_almost(Logic.speed_of({"boostT": 0.0, "slowT": 1.0, "z": 0.0}), 3.3)
	var endless := Logic.apply_difficulty(Logic.HARBOR, "endless")
	assert_almost(Logic.speed_of({"boostT": 0.0, "slowT": 0.0, "z": 250.0}, endless), 8.2)
	assert_almost(Logic.speed_of({"boostT": 0.0, "slowT": 0.0, "z": 9000.0}, endless), 9.6)


func test_hitboxes() -> void:
	var boat := {"x": 0.0, "z": 0.0}
	var crate_r: float = float(Logic.HARBOR["CRATE_RADIUS"]) + float(Logic.HARBOR["BOAT_RADIUS"])
	assert_true(Logic.hits(boat, {"x": 1.2, "z": 0.0}, crate_r, false))
	assert_false(Logic.hits(boat, {"x": 1.5, "z": 0.0}, crate_r, false))
	# Hindernisse bekommen 70 % Kulanz — dieselbe Distanz trifft NICHT mehr.
	var buoy_r: float = float(Logic.HARBOR["BUOY_RADIUS"]) + float(Logic.HARBOR["BOAT_RADIUS"])
	assert_true(Logic.hits(boat, {"x": 1.1, "z": 0.0}, buoy_r, false))
	assert_false(Logic.hits(boat, {"x": 1.1, "z": 0.0}, buoy_r, true))
	# Mole: erst innerhalb der Reichweite von ihrer Seite.
	var pier := {"side": -1, "z": 0.0}
	assert_true(Logic.hits_pier({"x": -2.0, "z": 0.0}, pier))
	assert_false(Logic.hits_pier({"x": 0.0, "z": 0.0}, pier))
	assert_false(Logic.hits_pier({"x": -3.0, "z": 4.0}, pier))
	assert_true(Logic.hits_pier({"x": 2.0, "z": 0.0}, {"side": 1, "z": 0.0}))
	# Hornkegel weitet sich nach vorn auf.
	assert_true(Logic.in_horn_cone(boat, {"x": 0.5, "z": 1.0}))
	assert_true(Logic.in_horn_cone(boat, {"x": 2.8, "z": 5.0}))
	assert_false(Logic.in_horn_cone(boat, {"x": 2.8, "z": 1.0}))
	assert_false(Logic.in_horn_cone(boat, {"x": 0.0, "z": 7.0}))
	assert_false(Logic.in_horn_cone(boat, {"x": 0.0, "z": -1.0}))


func test_engine_events_and_gull() -> void:
	var engine := Logic.HarborEngine.new(GoobyRng.new(3))
	# Reihen sind vorab erzeugt und liegen im Kanal.
	assert_true(engine.items.size() > 0)
	for item: Dictionary in engine.items:
		assert_true(absf(float(item["x"])) <= float(Logic.HARBOR["CHANNEL_HALF_W"]) - 0.55 + 1e-9)
	# Kiste per Hand vor den Bug legen → Aufsammel-Ereignis + 4 Punkte.
	engine.items.append({"type": "crate", "x": float(engine.state["x"]), "z": 0.4, "gone": false})
	var picked := false
	for _i in 6:
		for ev: Dictionary in engine.step({"targetX": null}, 1.0 / 60.0):
			if str(ev["type"]) == "crate":
				picked = true
	assert_true(picked, "Kiste aufgesammelt")
	assert_eq(int(engine.state["score"]), 4)
	# Möwe: > 4 s in derselben Spur mit Fracht → Warnung, dann Diebstahl.
	var warned := false
	var stolen := false
	for _i in 400:
		for ev: Dictionary in engine.step({"targetX": 0.0}, 1.0 / 60.0):
			if str(ev["type"]) == "gullWarn":
				warned = true
			if str(ev["type"]) == "gullSteal":
				stolen = true
		if stolen:
			break
	assert_true(warned, "Warnruf zuerst")
	assert_true(stolen, "Kiste geklaut")


func test_horn_clears_buoys() -> void:
	var engine := Logic.HarborEngine.new(GoobyRng.new(5))
	engine.items.clear()
	engine.items.append({"type": "buoy", "x": 0.2, "z": 3.0, "gone": false})
	engine.items.append({"type": "buoy", "x": 3.0, "z": 3.0, "gone": false})
	var events := engine.step({"targetX": null, "horn": true}, 1.0 / 60.0)
	var cleared := -1
	for ev: Dictionary in events:
		if str(ev["type"]) == "buoyCleared":
			cleared = int(ev["count"])
	assert_eq(cleared, 1, "nur die Boje im Kegel")
	assert_eq(int(engine.state["hornCharges"]), 1)
	engine.step({"targetX": null, "horn": true}, 1.0 / 60.0)
	assert_eq(int(engine.state["hornCharges"]), 0)
	var empty := false
	for ev: Dictionary in engine.step({"targetX": null, "horn": true}, 1.0 / 60.0):
		if str(ev["type"]) == "hornEmpty":
			empty = true
	assert_true(empty, "dritter Hornstoß ist leer")


func test_modifier_hooks() -> void:
	assert_true(Logic.apply_modifier(Logic.HARBOR, {}) == Logic.HARBOR)
	var rain := Logic.apply_modifier(Logic.HARBOR, {"type": "muenzregen", "coinRate": 1.5})
	assert_almost(float(rain["PICKUP_RATE"]), 1.5)
	var base_pickups := 0
	for item: Dictionary in Logic.HarborEngine.new(GoobyRng.new(2)).items:
		if str(item["type"]) != "buoy":
			base_pickups += 1
	var rain_pickups := 0
	for item: Dictionary in Logic.HarborEngine.new(GoobyRng.new(2), rain).items:
		if str(item["type"]) != "buoy":
			rain_pickups += 1
	assert_true(rain_pickups > base_pickups, "Münzregen legt Reihen nach")
	var giant := Logic.apply_modifier(Logic.HARBOR, {"type": "riesenGooby", "hitboxMult": 1.4})
	assert_almost(float(giant["CRATE_RADIUS"]), 0.8 * 1.4)
	assert_almost(float(giant["PICKUP_RADIUS_MULT"]), 1.4)
	# Auch mit Turbo bleibt die Reihen-Erreichbarkeit ≥ 1 (§G5.3-Leitplanke).
	var turbo := Logic.apply_modifier(
		Logic.apply_difficulty(Logic.HARBOR, "endless"),
		{"type": "turbo", "speedMult": 1.25, "scoreMult": 1.5}
	)
	assert_true(Logic.row_reachability(turbo) >= 1.0)
