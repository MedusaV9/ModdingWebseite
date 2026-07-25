extends TestCase
## Gemüse-Schnippler (veggieChop) — Logik-Parität zum Web (MG-1, Batch 1).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/veggieChop.logic.js
## (simulateChopAutoplay) — sie sperren Wellenrampe, Wisch-Kombo und die
## müllfreien Frenzy-Fenster fest.

const Logic := preload("res://scripts/minigames/games/veggie_chop/veggie_chop_logic.gd")
const MANIFEST := "res://scripts/minigames/games/veggie_chop/game.json"

## Web-Goldwerte: simulateChopAutoplay(seed, mode).score für Seeds 1..8.
const GOLD := {
	"easy": [116, 100, 112, 106, 124, 116, 116, 108],
	"normal": [98, 96, 106, 98, 108, 96, 106, 96],
	"hard": [102, 104, 106, 94, 112, 90, 104, 86],
	"endless": [18, 52, 46, 52, 34, 40, 44, 28],
}
const WEB_TARGET := 105


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.CHOP
	assert_almost(float(t["DURATION_SEC"]), 60.0)
	assert_eq(int(t["CHOP_PTS"]), 2)
	assert_eq(int(t["COMBO_BONUS"]), 1)
	assert_eq(int(t["JUNK_PTS"]), -3)
	assert_almost(float(t["STUN_SEC"]), 0.5)
	assert_eq(int(t["MAX_MISSES"]), 3)
	assert_almost(float(t["WAVE2_FROM_SEC"]), 20.0)
	assert_almost(float(t["WAVE3_FROM_SEC"]), 40.0)
	assert_almost(float(t["SPAWN_START_SEC"]), 2.3)
	assert_almost(float(t["SPAWN_END_SEC"]), 1.7)
	assert_almost(float(t["JUNK_CHANCE_START"]), 0.1)
	assert_almost(float(t["JUNK_CHANCE_END"]), 0.22)
	assert_almost(float(t["GRAVITY"]), 9.5)
	assert_almost(float(t["APEX_MIN_Y"]), -0.4)
	assert_almost(float(t["APEX_MAX_Y"]), 2.3)
	assert_almost(float(t["HIT_RADIUS"]), 0.42)
	assert_almost(float(t["FRENZY_EVERY_SEC"]), 25.0)
	assert_almost(float(t["FRENZY_DURATION_SEC"]), 3.0)
	assert_eq(int(t["FRENZY_ITEMS"]), 8)
	assert_eq(int(t["ENDLESS_JUNK_HITS"]), 3)
	assert_eq(Logic.VEGGIES.size(), 8)
	assert_eq(Logic.JUNK_ITEMS, ["soda", "boot"] as Array[String])


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(10, mode), Logic.simulate_autoplay(10, mode), mode)
		assert_ne(
			int(Logic.simulate_autoplay(1, mode)["score"]),
			int(Logic.simulate_autoplay(2, mode)["score"]),
			mode
		)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 21):
			sum += int(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = float(sum) / 20.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] >= means["hard"], "normal ≥ schwer (%s)" % means)
	assert_true(means["easy"] > means["hard"], "leicht > schwer (%s)" % means)


func test_bot_scores_are_plausible() -> void:
	var best := 0
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "hard")
		assert_true(int(run["score"]) > 0, "Schwer-Bot punktet (seed %d)" % seed_value)
		assert_true(int(run["score"]) < 400, "Score bleibt plausibel (seed %d)" % seed_value)
		assert_true(int(run["junkHits"]) == 0, "getakteter Bot schneidet keinen Müll")
		best = maxi(best, int(run["score"]))
	assert_true(best >= WEB_TARGET, "bester Schwer-Score %d < Ziel %d" % [best, WEB_TARGET])


func test_endless_ends_on_three_junk_cuts() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.CHOP, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.endless_should_end(2, tune))
	assert_true(Logic.endless_should_end(3, tune))
	assert_false(Logic.endless_should_end(99, Logic.CHOP), "getaktet gibt es kein Limit")
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "endless")
		assert_true(int(run["junkHits"]) >= 3, "Endlos endet am Müll-Limit (seed %d)" % seed_value)
	# Endlos rampt weiter, hat aber einen Kadenz-Boden.
	assert_almost(Logic.spawn_interval_at(600.0, 60.0, tune), 0.8)


func test_score_edges() -> void:
	assert_eq(Logic.chop_points(1), 2, "das erste Stück im Wisch zahlt 2")
	assert_eq(Logic.chop_points(2), 3, "jedes weitere 3")
	assert_eq(Logic.swipe_score(0), 0)
	assert_eq(Logic.swipe_score(1), 2)
	assert_eq(Logic.swipe_score(3), 8, "2·3 + 2 Kombo-Boni")
	# Müll bricht die Kombo sofort, Gemüse zählt sie hoch.
	assert_eq(Logic.combo_after_hit(4, "junk"), 0)
	assert_eq(Logic.combo_after_hit(4, "veggie"), 5)
	assert_eq(Logic.apply_points(2, -3), 0, "Score ist bei 0 gefloort")
	assert_eq(Logic.apply_points(10, -3), 7)
	# Der Turbo rundet genau einmal, am Rundenende.
	var turbo: Dictionary = Logic.apply_turbo(Logic.CHOP, 1.25, 1.5)
	assert_eq(Logic.final_score(11, turbo), 17)
	assert_almost(float(turbo["SPEED_MULT"]), 1.25)
	assert_eq(Logic.final_score(-5, Logic.CHOP), 0)


func test_wave_and_junk_ramps() -> void:
	assert_eq(Logic.max_wave_size_at(0.0), 1)
	assert_eq(Logic.max_wave_size_at(19.9), 1)
	assert_eq(Logic.max_wave_size_at(20.0), 2)
	assert_eq(Logic.max_wave_size_at(40.0), 3)
	assert_almost(Logic.spawn_interval_at(0.0), 2.3)
	assert_almost(Logic.spawn_interval_at(60.0), 1.7)
	assert_almost(Logic.junk_chance_at(0.0), 0.1)
	assert_almost(Logic.junk_chance_at(60.0), 0.22)
	assert_almost(Logic.junk_chance_at(600.0), 0.22, 1e-9, "Rampe ist gedeckelt")
	# Zwei Frenzys je 60-s-Runde, exakt 8 Gemüse in 3 s.
	assert_eq(Logic.frenzy_count_at(24.9), 0)
	assert_eq(Logic.frenzy_count_at(25.0), 1)
	assert_eq(Logic.frenzy_count_at(60.0), 2)
	assert_almost(Logic.frenzy_spawn_interval(), 0.375)
	# Ein Frenzy-Wurf ist immer Gemüse.
	var rng := GoobyRng.new(4)
	for _i in 20:
		assert_eq(str(Logic.roll_veggie(rng)["kind"]), "veggie")


func test_arc_physics_and_swipe_hits() -> void:
	var rng := GoobyRng.new(7)
	for _i in 12:
		var arc: Dictionary = Logic.make_arc(rng, 2.0, -0.9)
		var apex: Dictionary = Logic.arc_apex(arc)
		assert_true(float(apex["y"]) >= -0.45, "Scheitel liegt im Band (%s)" % apex["y"])
		assert_true(float(apex["y"]) <= 2.35, "Scheitel liegt im Band (%s)" % apex["y"])
		assert_true(absf(float(apex["x"])) <= 1.5, "Scheitel bleibt im Feld")
		# Der Bogen startet unten und kommt wieder unten an.
		assert_almost(Logic.arc_pos(arc, 0.0).y, -0.9)
		assert_true(Logic.arc_pos(arc, float(apex["t"]) * 2.0).y <= -0.85)
	# Wisch-Treffer: die Strecke muss den Kreis wirklich kreuzen.
	assert_true(Logic.segment_hits_circle(Vector2(-1, 0), Vector2(1, 0), Vector2(0, 0.2), 0.42))
	assert_false(Logic.segment_hits_circle(Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1.0), 0.42))
	# Low-FPS: ein schneller Wisch quer über den zurückgelegten Weg trifft auch.
	assert_true(
		Logic.segment_hits_moving_circle(
			Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(1, 1), 0.05
		)
	)
	assert_false(
		Logic.segment_hits_moving_circle(
			Vector2(-1, 5), Vector2(1, 5), Vector2(-1, -1), Vector2(1, -1), 0.42
		)
	)


func test_manifest_matches_web_metadata() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_true(file != null, "game.json fehlt")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert_eq(str(manifest["id"]), "veggieChop")
	assert_eq(int(manifest["target"]), WEB_TARGET)
	assert_eq(str(manifest["orientation"]), "portrait")
	var coins: Dictionary = manifest["coin_table"]
	assert_eq(int(coins["divisor"]), 5)
	assert_eq(int(coins["min"]), 4)
	assert_eq(int(coins["max"]), 26)
	assert_true(ResourceLoader.exists(str(manifest["scene"])), "Szene fehlt")
