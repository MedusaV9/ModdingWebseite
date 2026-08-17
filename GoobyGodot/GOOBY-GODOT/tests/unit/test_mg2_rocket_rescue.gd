extends TestCase
## Raketen-Rettung (rocketRescue) — Logik-Parität zum Web (MG-2, Batch 2).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/rocketRescue.logic.js.

const Logic := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_logic.gd")
const Lander := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_engine.gd")
const Bot := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_bot.gd")

## Web-Goldwerte: simulateRocketAutoplay(mode, seed).score für Seeds 1..5.
const GOLD := {
	"easy": [210, 228, 218, 228, 201],
	"normal": [195, 215, 218, 228, 199],
	"hard": [190, 185, 168, 193, 164],
	"endless": [255, 245, 240, 200, 270],
}

## Web: createLayout(mulberry32(5)) — Plattform-Mittelpunkte in Metern.
const GOLD_PLATFORMS := [
	[3.523798712, 4.083904179],
	[-3.084565579, 5.292720828],
	[5.52397296, 6.79833107],
	[-5.527934622, 2.656304794],
	[5.413754073, 8.401401708],
]


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.ROCKET
	assert_almost(float(t["DURATION_SEC"]), 120.0)
	assert_almost(float(t["WORLD_HALF_W"]), 8.0)
	assert_almost(float(t["CEILING_Y"]), 11.0)
	assert_almost(float(t["GRAVITY"]), 2.4)
	assert_almost(float(t["THRUST_ACCEL"]), 5.6)
	assert_almost(float(t["TILT_MAX_RAD"]), 0.5)
	assert_almost(float(t["TILT_RATE"]), 3.2)
	assert_almost(float(t["WALL_RESTITUTION"]), 0.3)
	assert_almost(float(t["FUEL_MAX"]), 100.0)
	assert_almost(float(t["FUEL_BURN_PER_SEC"]), 8.0)
	assert_eq(int(t["FUEL_PICKUP_COUNT"]), 8)
	assert_almost(float(t["FUEL_PICKUP_AMOUNT"]), 30.0)
	assert_almost(float(t["FUEL_PICKUP_RADIUS"]), 0.85)
	assert_almost(float(t["FUEL_RESPAWN_SEC"]), 9.0)
	assert_eq(int(t["PLATFORM_COUNT"]), 5)
	assert_almost(float(t["PLATFORM_HALF_W"]), 1.05)
	assert_almost(float(t["PAD_HALF_W"]), 1.6)
	assert_almost(float(t["LAND_MAX_VY"]), 1.2)
	assert_almost(float(t["SOFT_MAX_VY"]), 0.5)
	assert_eq(int(t["RESCUE_POINTS"]), 30)
	assert_eq(int(t["SOFT_LANDING_BONUS"]), 5)
	assert_almost(float(t["FUEL_SCORE_DIVISOR"]), 2.0)
	assert_almost(float(t["DEPART_CLEAR_M"]), 0.4)
	assert_almost(float(t["HARD_FUEL_PENALTY"]), 10.0)
	assert_almost(float(t["BOUNCE_RESTITUTION"]), 0.45)
	assert_eq(int(t["WIND_FROM_RESCUES"]), 2)
	assert_almost(float(t["WIND_TELEGRAPH_SEC"]), 1.0)
	assert_almost(float(t["WIND_GUST_SEC"]), 1.6)
	assert_almost(float(t["WIND_ACCEL"]), 1.7)
	assert_almost(float(t["WIND_EVERY_MIN_SEC"]), 6.0)
	assert_almost(float(t["WIND_EVERY_MAX_SEC"]), 10.0)
	assert_almost(float(t["TOW_SPEED"]), 3.4)
	assert_almost(float(t["MAX_DT"]), 0.05)
	assert_almost(float(t["ENDLESS_THIN_PER_RESCUE"]), 0.1)
	assert_almost(float(Logic.ROCKET_JUICE["TOUCH_SQUASH"]), 0.82)
	assert_almost(float(Logic.ROCKET_JUICE["BEACON_POP_SCALE"]), 2.1)


func test_hypot_matches_v8() -> void:
	# Ein naives sqrt(x²+y²) weicht bei ~36 % der Eingaben im letzten Bit ab —
	# über 7200 Bot-Frames reicht das, um die Runde zu verändern.
	assert_almost(Logic.hypot(3.0, 4.0), 5.0, 0.0)
	assert_almost(Logic.hypot(0.0, 0.0), 0.0, 0.0)
	assert_almost(Logic.hypot(-6.0, 0.0), 6.0, 0.0)
	assert_almost(Logic.hypot(0.1, 0.2), 0.223606797749979, 0.0)
	assert_almost(Logic.hypot(1.7976931348623157e308, 1.0), 1.7976931348623157e308, 0.0)
	assert_true(is_inf(Logic.hypot(INF, 3.0)))


func test_layout_matches_web_stream() -> void:
	var rng := GoobyRng.new(5)
	var layout: Dictionary = Logic.create_layout(func() -> float: return rng.next())
	var platforms: Array = layout["platforms"]
	assert_eq(platforms.size(), 5)
	for i in GOLD_PLATFORMS.size():
		var p: Dictionary = platforms[i]
		var want: Array = GOLD_PLATFORMS[i]
		assert_almost(float(p["x"]), float(want[0]), 1e-9, "Plattform %d x" % i)
		assert_almost(float(p["y"]), float(want[1]), 1e-9, "Plattform %d y" % i)
		assert_true(bool(p["bunny"]), "jede Plattform startet mit einem Hasen")
	assert_eq((layout["fuelPickups"] as Array).size(), 8)
	var first: Dictionary = (layout["fuelPickups"] as Array)[0]
	assert_almost(float(first["x"]), -5.488685122, 1e-9)
	assert_almost(float(first["y"]), 9.960706343, 1e-9)
	assert_eq(layout["pad"], {"x": 0.0, "y": 0.0, "halfW": 1.6})


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Bot.simulate_autoplay(mode, i + 1)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])
	# Detailwerte des Web-Laufs (5 gerettet, 10 Sanftlandungen, 0 harte).
	var run: Dictionary = Bot.simulate_autoplay("normal", 3)
	assert_eq(int(run["rescued"]), 5)
	assert_eq(int(run["softLandings"]), 10)
	assert_eq(int(run["hardLandings"]), 0)
	assert_eq(str(run["endReason"]), "complete")
	assert_almost(float(run["fuelLeft"]), 37.86666666666371, 1e-9)
	assert_almost(float(run["elapsed"]), 113.31666666666152, 1e-9)


func test_autoplay_is_deterministic() -> void:
	assert_eq(Bot.simulate_autoplay("normal", 4), Bot.simulate_autoplay("normal", 4))
	assert_eq(Bot.simulate_autoplay("endless", 2), Bot.simulate_autoplay("endless", 2))


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 13):
			sum += int(Bot.simulate_autoplay(mode, seed_value)["score"])
		means[mode] = float(sum) / 12.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)
	var easy: Dictionary = Logic.apply_difficulty(Logic.ROCKET, "easy")
	assert_almost(float(easy["LAND_MAX_VY"]), 1.5)
	assert_almost(float(easy["SOFT_MAX_VY"]), 0.625)
	assert_almost(float(easy["PLATFORM_HALF_W"]), 1.3125)
	assert_false(bool(easy["ENDLESS"]))
	var hard: Dictionary = Logic.apply_difficulty(Logic.ROCKET, "hard")
	assert_almost(float(hard["LAND_MAX_VY"]), 0.96)
	assert_almost(float(hard["SOFT_MAX_VY"]), 0.4)
	assert_almost(float(hard["PLATFORM_HALF_W"]), 0.8400000000000001, 1e-12)
	assert_eq(Logic.apply_difficulty(Logic.ROCKET, "unsinn"), Logic.ROCKET)


func test_hard_bot_reaches_target() -> void:
	# §G5.4-Ziel für rocketRescue ist 115.
	for seed_value in range(1, 6):
		var score: int = int(Bot.simulate_autoplay("hard", seed_value)["score"])
		assert_true(score >= 115, "Schwer-Score %d < Ziel 115 (seed %d)" % [score, seed_value])


func test_endless_thins_fuel_and_terminates() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.ROCKET, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_almost(float(tune["LAND_MAX_VY"]), 0.96, 1e-12, "Endlos erbt Schwer-Toleranzen")
	for seed_value in range(1, 4):
		var run: Dictionary = Bot.simulate_autoplay("endless", seed_value)
		assert_eq(
			str(run["endReason"]), "fuel", "Endlos endet am leeren Tank (seed %d)" % seed_value
		)
		assert_true(int(run["rescued"]) >= 5, "Endlos räumt mindestens ein Feld leer")


func test_scoring_and_landing_edges() -> void:
	assert_eq(Logic.classify_landing(0.5), "soft")
	assert_eq(Logic.classify_landing(0.51), "ok")
	assert_eq(Logic.classify_landing(1.2), "ok")
	assert_eq(Logic.classify_landing(1.21), "hard")
	assert_eq(Logic.round_score(0, 0.0, 0), 0)
	assert_eq(Logic.round_score(5, 100.0, 10), 250)
	assert_eq(Logic.round_score(3, 77.0, 4), 148, "Sprit/2 wird abgerundet")
	assert_eq(Logic.round_score(0, -5.0, 0), 0, "negativer Sprit zählt als 0")
	assert_eq(Logic.round_score(1, 7.0, 0), 33)
	# Bildschirmdrittel-Steuerung.
	assert_eq(Logic.tilt_command_for(0.0, false), 0, "kein Finger = geradestellen")
	assert_eq(Logic.tilt_command_for(-0.4), -1)
	assert_eq(Logic.tilt_command_for(-1.0 / 3.0), 0, "Grenze gehört zur Mitte")
	assert_eq(Logic.tilt_command_for(0.34), 1)
	assert_eq(Logic.tilt_command_for(0.0), 0)


func test_modifier_only_touches_canisters() -> void:
	var boosted: Dictionary = Logic.apply_modifier(
		Logic.ROCKET, {"type": "muenzregen", "coinRate": 1.5}
	)
	assert_eq(int(boosted["FUEL_PICKUP_COUNT"]), 12)
	assert_almost(float(boosted["FUEL_RESPAWN_SEC"]), 6.0)
	assert_almost(float(boosted["PICKUP_RATE"]), 1.5)
	assert_almost(float(boosted["GRAVITY"]), 2.4, 1e-12, "Physik bleibt unberührt")
	assert_eq(Logic.apply_modifier(Logic.ROCKET, {}), Logic.ROCKET)
	assert_eq(Logic.apply_modifier(Logic.ROCKET, {"type": "zeitlupe"}), Logic.ROCKET)


func test_engine_events_and_never_death() -> void:
	var rng := GoobyRng.new(1)
	var engine := Lander.new(func() -> float: return rng.next())
	var types := PackedStringArray()
	for i in 240:
		for event in engine.step({"thrust": i < 90, "tiltDir": 0}, 1.0 / 60.0):
			types.append(str(event["type"]))
	assert_eq(types, PackedStringArray(["liftoff", "fuelPickup"]))
	assert_almost(float(engine.state["y"]), 8.09, 1e-6)
	assert_almost(float(engine.state["fuel"]), 98.13333333333324, 1e-9)
	assert_false(bool(engine.state["ended"]), "ein Sturz beendet die Runde NIE")
	# Weiterfallen bis zum Aufschlag: harte Landung prallt ab, tötet aber nicht.
	var saw_hard := false
	for i in 600:
		for event in engine.step({"thrust": false, "tiltDir": 0}, 1.0 / 60.0):
			if str(event["type"]) == "hardLanding":
				saw_hard = true
	assert_true(saw_hard, "freier Fall endet in einer harten Landung")
	assert_true(int(engine.state["hardLandings"]) >= 1)
	assert_false(bool(engine.state["ended"]))


func test_round_ends_on_time_without_input() -> void:
	var rng := GoobyRng.new(9)
	var engine := Lander.new(func() -> float: return rng.next())
	var reason := ""
	for i in 8000:
		for event in engine.step({"thrust": false, "tiltDir": 0}, 1.0 / 60.0):
			if str(event["type"]) == "ended":
				reason = str(event["reason"])
		if bool(engine.state["ended"]):
			break
	assert_eq(reason, "time")
	assert_true(float(engine.state["elapsed"]) >= 120.0)
	assert_eq(engine.step({"thrust": true, "tiltDir": 1}, 1.0 / 60.0), [] as Array[Dictionary])
