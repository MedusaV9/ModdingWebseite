extends TestCase
## Schneckenpost (snailMail) — Logik-Parität zum Web (MG-3, Batch 3).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/snailMail.logic.js
## (inkl. des dort importierten goobyWelt-Spline-Werkzeugkastens).

const Logic := preload("res://scripts/minigames/games/snail_mail/snail_mail_logic.gd")

## Web: simulateSnailAutoplay(mode, seed) → [score, deliveries, splashes, flowers].
const GOLD := {
	"easy":
	[[123, 16, 0, 27], [126, 16, 0, 30], [127, 16, 0, 31], [119, 15, 0, 29], [125, 16, 0, 29]],
	"normal":
	[[102, 14, 1, 20], [114, 15, 2, 28], [111, 14, 1, 29], [103, 14, 1, 21], [112, 14, 1, 30]],
	"hard":
	[[98, 14, 4, 22], [97, 14, 5, 23], [126, 16, 1, 32], [115, 15, 3, 31], [100, 14, 5, 26]],
	"endless": [[60, 9, 3, 12], [22, 4, 3, 4], [231, 30, 3, 57], [81, 11, 3, 21], [76, 10, 3, 22]],
}


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.SNAIL
	assert_almost(float(t["DURATION_SEC"]), 60.0)
	assert_almost(float(t["FIELD_HALF_W"]), 2.2)
	assert_almost(float(t["POST_Y"]), -2.35)
	assert_eq(t["HOUSE_SLOTS_X"], [-1.5, 0.0, 1.5])
	assert_almost(float(t["DOOR_OFFSET_Y"]), 0.32)
	assert_almost(float(t["SPEED"]), 2.1)
	assert_almost(float(t["SPEED_EASE_DIST"]), 0.45)
	assert_almost(float(t["SPEED_MIN_FRAC"]), 0.4)
	assert_almost(float(t["SNAIL_RADIUS"]), 0.16)
	assert_almost(float(t["RESAMPLE_STEP"]), 0.22)
	assert_almost(float(t["START_RADIUS"]), 0.8)
	assert_almost(float(t["DELIVER_RADIUS"]), 0.55)
	assert_eq(int(t["PUDDLES_START"]), 2)
	assert_eq(int(t["PUDDLES_MAX"]), 5)
	assert_eq(int(t["PUDDLE_RAMP_EVERY"]), 2)
	assert_eq(int(t["FLOWERS_PER_ROUND"]), 3)
	assert_almost(float(t["FLOWER_PICK_RADIUS"]), 0.42)
	assert_eq(int(t["DELIVER_PTS"]), 4)
	assert_eq(int(t["DRY_BONUS"]), 2)
	assert_eq(int(t["FLOWER_PTS"]), 1)
	assert_almost(float(t["RETREAT_SEC"]), 2.0)
	assert_eq(int(t["ENDLESS_MAX_SPLASHES"]), 3)
	assert_eq(Logic.ARC_SAMPLES_PER_SEG, 32, "goobyWelt-Werkzeugkasten")


func test_difficulty_rows_match_web() -> void:
	var easy: Dictionary = Logic.apply_difficulty(Logic.SNAIL, "easy")
	assert_almost(float(easy["DURATION_SEC"]), 72.0, 1e-9)
	assert_almost(float(easy["SPEED"]), 1.785, 1e-9)
	assert_almost(float(easy["PUDDLE_EDGE"]), 0.85)
	assert_almost(float(easy["BOT_WET_RATE"]), 0.03)
	var hard: Dictionary = Logic.apply_difficulty(Logic.SNAIL, "hard")
	assert_almost(float(hard["SPEED"]), 2.52, 1e-9)
	assert_almost(float(hard["PUDDLE_EDGE"]), 1.12)
	assert_almost(float(hard["BOT_WET_RATE"]), 0.3)
	assert_true(bool(Logic.apply_difficulty(Logic.SNAIL, "endless")["ENDLESS"]))
	assert_eq(Logic.apply_difficulty(Logic.SNAIL, "normal"), Logic.SNAIL)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var run: Dictionary = Logic.simulate_autoplay(mode, i + 1)
			var row: Array = want[i]
			assert_eq(int(run["score"]), int(row[0]), "%s seed %d score" % [mode, i + 1])
			assert_eq(int(run["deliveries"]), int(row[1]), "%s seed %d liefer" % [mode, i + 1])
			assert_eq(int(run["splashes"]), int(row[2]), "%s seed %d nass" % [mode, i + 1])
			assert_eq(int(run["flowersPicked"]), int(row[3]), "%s seed %d blumen" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(mode, 3), Logic.simulate_autoplay(mode, 3), mode)


func test_difficulty_is_monotone() -> void:
	# ABWEICHUNG (auch im Web so): der Score ist zwischen normal und schwer
	# fast gleich — Schwer läuft SCHNELLER (mehr Runden pro Minute) und gleicht
	# die höhere Nassquote aus. Eindeutig monoton sind (a) leicht > normal und
	# (b) die Nass-Quote (splashes/deliveries) über alle drei Stufen.
	var means := {}
	var wet_rate := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		var wet := 0
		var runs := 0
		for seed_value in range(1, 41):
			var run: Dictionary = Logic.simulate_autoplay(mode, seed_value)
			sum += int(run["score"])
			wet += int(run["splashes"])
			runs += int(run["deliveries"])
		means[mode] = float(sum) / 40.0
		wet_rate[mode] = float(wet) / float(runs)
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)
	assert_true(wet_rate["easy"] < wet_rate["normal"], "Nassquote steigt (%s)" % wet_rate)
	assert_true(wet_rate["normal"] < wet_rate["hard"], "Nassquote steigt (%s)" % wet_rate)


func test_hard_bot_reaches_target() -> void:
	var best := 0
	for seed_value in range(1, 6):
		best = maxi(best, int(Logic.simulate_autoplay("hard", seed_value)["score"]))
	assert_true(best >= 80, "bester Schwer-Score %d < Ziel 80" % best)


func test_endless_ends_on_three_splashes() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.SNAIL, "endless")
	assert_false(Logic.endless_should_end(2, tune))
	assert_true(Logic.endless_should_end(3, tune))
	assert_false(Logic.endless_should_end(9, Logic.SNAIL), "Zeitmodus endet nie daran")
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay("endless", seed_value)
		var by_splash := int(run["splashes"]) >= 3
		var by_guard := float(run["elapsed"]) >= 600.0
		assert_true(by_splash or by_guard, "Endlos terminiert (seed %d)" % seed_value)


func test_puddle_ramp_and_edges() -> void:
	var want := [2, 2, 3, 3, 4, 4, 5, 5, 5, 5]
	var rounds := [0, 1, 2, 3, 4, 5, 6, 7, 8, 20]
	for i in rounds.size():
		assert_eq(Logic.puddles_for_round(int(rounds[i])), int(want[i]), "Runde %d" % rounds[i])
	assert_almost(Logic.puddle_eff_r({"r": 0.4}), 0.56, 1e-12)
	var hard: Dictionary = Logic.apply_difficulty(Logic.SNAIL, "hard")
	assert_almost(Logic.puddle_eff_r({"r": 0.4}, hard), 0.608, 1e-12)
	# Striktes `<`: die exakte Kante ist noch trocken.
	var puddles := [{"x": 0.0, "y": 0.0, "r": 0.4}]
	assert_eq(Logic.puddle_hit_at(0.0, 0.0, puddles), 0)
	assert_eq(Logic.puddle_hit_at(0.56, 0.0, puddles), -1, "Kante ist sicher")
	assert_eq(Logic.puddle_hit_at(0.5599, 0.0, puddles), 0)
	assert_true(Logic.starts_at_post({"x": 0.0, "y": -2.35}))
	assert_true(Logic.starts_at_post({"x": 0.7, "y": -2.35}))
	assert_false(Logic.starts_at_post({"x": 0.9, "y": -2.35}))


func test_speed_ramp_and_scoring() -> void:
	var want := [0.84, 1.4, 2.1, 2.1, 2.1, 1.26, 0.84]
	var samples := [0.0, 0.2, 0.45, 1.0, 2.0, 2.45, 2.6]
	for i in samples.size():
		assert_almost(
			Logic.speed_at(float(samples[i]), 2.6), float(want[i]), 1e-12, "s=%s" % samples[i]
		)
	# Die Rampe stallt nie → jeder Lauf terminiert.
	assert_true(Logic.speed_at(0.0, 9.9) > 0.0)
	assert_almost(Logic.advance_arc(2.59, 1.0, 2.6), 2.6, 1e-12, "am Ende geklemmt")
	assert_eq(Logic.delivery_points(false, 0), 6)
	assert_eq(Logic.delivery_points(true, 0), 4, "nass = kein Trocken-Bonus")
	assert_eq(Logic.delivery_points(false, 3), 9)
	assert_eq(Logic.delivery_points(true, 2), 6)
	assert_eq(Logic.apply_score(0, 6), 6)
	assert_eq(Logic.apply_score(3, -9), 0, "nie negativ")


func test_smooth_path_matches_web() -> void:
	var raw := [
		{"x": 0.0, "y": -2.35},
		{"x": 0.2, "y": -1.8},
		{"x": 0.55, "y": -1.0},
		{"x": 0.3, "y": 0.2},
		{"x": -0.2, "y": 1.1},
		{"x": 0.0, "y": 1.9},
	]
	var path := Logic.smooth_path(raw)
	assert_false(path.is_empty())
	assert_almost(float(path["length"]), 4.564878739113, 1e-9)
	var pts: Array = path["pts"]
	assert_eq(pts.size(), 22)
	assert_almost(float(pts[0]["x"]), 0.0, 1e-12)
	assert_almost(float(pts[0]["y"]), -2.35, 1e-12)
	assert_almost(float(pts[11]["x"]), 0.394902892977, 1e-9)
	assert_almost(float(pts[11]["y"]), -0.090845972707, 1e-9)
	assert_almost(float(pts[21]["x"]), 0.0, 1e-9)
	assert_almost(float(pts[21]["y"]), 1.9, 1e-9)
	var pose := Logic.follow_at(path, 1.5)
	assert_almost(float(pose["x"]), 0.548663511581, 1e-9)
	assert_almost(float(pose["y"]), -0.965969999672, 1e-9)
	assert_almost(float(pose["angle"]), 1.447110089788, 1e-9)
	# Zu wenig unterscheidbare Punkte → kein Pfad.
	assert_true(Logic.smooth_path([{"x": 0.0, "y": 0.0}]).is_empty())


func test_generate_level_matches_web() -> void:
	var rng := GoobyRng.new(11)
	var want_targets := [2, 2, 0]
	var want_puddle_counts := [2, 2, 3]
	var want_first_house_x := [-1.598057232676, -1.552797613889, -1.676857098518]
	var want_route_len := [4.115773589953, 4.639753579775, 4.607610546817]
	var want_flowers := [[2], [2], [0]]
	for round_index in 3:
		var level := Logic.generate_level(rng, round_index)
		assert_eq(int(level["targetIdx"]), int(want_targets[round_index]), "Ziel %d" % round_index)
		var houses: Array = level["houses"]
		assert_eq(houses.size(), 3)
		assert_eq(str(houses[1]["kind"]), "burrow", "mittlerer Slot ist der Bau")
		assert_almost(float(houses[0]["x"]), float(want_first_house_x[round_index]), 1e-9, "Haus 0")
		var puddles: Array = level["puddles"]
		assert_eq(puddles.size(), int(want_puddle_counts[round_index]), "Pfützen %d" % round_index)
		assert_eq((level["flowers"] as Array).size(), 3)
		var route := Logic.auto_route(level)
		assert_true(bool(route["ok"]), "Runde %d ist lösbar" % round_index)
		assert_almost(
			float((route["smooth"] as Dictionary)["length"]),
			float(want_route_len[round_index]),
			1e-9,
			"Routenlänge %d" % round_index
		)
		assert_eq(
			Logic.flowers_on_path(route["smooth"], level["flowers"]),
			want_flowers[round_index],
			"Blumen %d" % round_index
		)


func test_generated_levels_are_always_solvable() -> void:
	# Der Generator darf NIE eine unlösbare Runde liefern (auch bei 5 Pfützen).
	for seed_value in range(1, 13):
		var rng := GoobyRng.new(seed_value)
		for round_index in [0, 4, 8]:
			var level := Logic.generate_level(rng, round_index)
			var route := Logic.auto_route(level)
			assert_true(bool(route["ok"]), "seed %d Runde %d" % [seed_value, round_index])
			var smooth: Dictionary = route["smooth"]
			assert_true(Logic.path_clear(smooth["pts"], level["puddles"]), "Route ist pfützenfrei")
			assert_true(
				Logic.starts_at_post((smooth["pts"] as Array)[0]), "Route startet am Briefkasten"
			)
			assert_eq(Logic.end_house(smooth, level), int(level["targetIdx"]))


func test_end_house_and_flowers() -> void:
	var level := {
		"post": {"x": 0.0, "y": -2.35},
		"houses": [{"x": -1.5, "y": 2.0}, {"x": 0.0, "y": 2.0}, {"x": 1.5, "y": 2.0}],
		"targetIdx": 1,
		"puddles": [],
		"flowers": [{"x": 0.0, "y": 0.0}, {"x": 1.9, "y": 0.0}],
	}
	var on_door := Logic.smooth_path([{"x": 0.0, "y": -2.35}, {"x": 0.0, "y": 1.68}])
	assert_eq(Logic.end_house(on_door, level), 1)
	assert_eq(Logic.flowers_on_path(on_door, level["flowers"]), [0], "nur die Blume am Weg")
	var open_garden := Logic.smooth_path([{"x": 0.0, "y": -2.35}, {"x": 0.0, "y": 0.4}])
	assert_eq(Logic.end_house(open_garden, level), -1, "Strich endet im Garten")
