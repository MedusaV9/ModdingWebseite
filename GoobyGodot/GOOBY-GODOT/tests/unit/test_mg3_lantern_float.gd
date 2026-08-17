extends TestCase
## Sternenlaterne (lanternFloat) — Logik-Parität zum Web (MG-3, Batch 3).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/lanternFloat.logic.js.

const Logic := preload("res://scripts/minigames/games/lantern_float/lantern_float_logic.gd")

## Web-Goldwerte: simulateLanternAutoplay(mode, seed).score für Seeds 1..5.
const GOLD := {
	"easy": [86, 73, 86, 88, 79],
	"normal": [81, 68, 83, 76, 59],
	"hard": [81, 68, 90, 71, 69],
	"endless": [160, 259, 204, 101, 166],
}


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.LANTERN
	assert_eq(float(t["DURATION_SEC"]), 60.0)
	assert_almost(float(t["HALF_W"]), 3.1)
	assert_almost(float(t["RISE_SPEED"]), 2.6)
	assert_almost(float(t["RING_SPACING_START"]), 4.4)
	assert_almost(float(t["RING_SPACING_END"]), 3.4)
	assert_almost(float(t["RING_RADIUS"]), 0.56)
	assert_eq(int(t["GOLD_EVERY"]), 5)
	assert_eq(int(t["RING_PTS"]), 2)
	assert_eq(int(t["GOLD_PTS"]), 5)
	assert_eq(int(t["FIREFLY_PTS"]), 1)
	assert_almost(float(t["GUST_FIRST_SEC"]), 7.0)
	assert_almost(float(t["GUST_EVERY_SEC"]), 9.0)
	assert_almost(float(t["CLOUD_HALF_W"]), 0.85)
	assert_eq(int(t["BUMP_PENALTY"]), 3)
	assert_eq(int(t["ENDLESS_MAX_BUMPS"]), 3)


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


func test_difficulty_is_monotone() -> void:
	# ABWEICHUNG (auch im Web so): der ROH-Score ist NICHT monoton — Schwer
	# steigt schneller, schafft also mehr Ringe pro Runde und gleicht die
	# kleinere Trefferzone aus. Monoton ist die TREFFERQUOTE (hits/rings),
	# und genau die ist die Difficulty-Wirkung (RING_RADIUS ×1.25/×0.8).
	var rates := {}
	for mode: String in ["easy", "normal", "hard"]:
		var hits := 0
		var rings := 0
		for seed_value in range(1, 41):
			var run: Dictionary = Logic.simulate_autoplay(mode, seed_value)
			hits += int(run["hits"])
			rings += int(run["rings"])
		rates[mode] = float(hits) / float(rings)
	assert_true(rates["easy"] > rates["normal"], "leicht > normal (%s)" % rates)
	assert_true(rates["normal"] > rates["hard"], "normal > schwer (%s)" % rates)
	# Der Score ist zwischen leicht und normal trotzdem eindeutig.
	var easy_sum := 0
	var normal_sum := 0
	for seed_value in range(1, 41):
		easy_sum += int(Logic.simulate_autoplay("easy", seed_value)["score"])
		normal_sum += int(Logic.simulate_autoplay("normal", seed_value)["score"])
	assert_true(easy_sum > normal_sum, "leichter Score > normal")


func test_hard_bot_reaches_target() -> void:
	var best := 0
	for seed_value in range(1, 6):
		best = maxi(best, int(Logic.simulate_autoplay("hard", seed_value)["score"]))
	assert_true(best >= 75, "bester Schwer-Score %d < Ziel 75" % best)


func test_ring_roll_matches_web() -> void:
	# Web mit Seed 1: fünf Ringe aus demselben RNG-Strom, danach drei Wolken.
	var rng := GoobyRng.new(1)
	var xs := [
		-1.6183361273724586,
		1.7592626011930406,
		0.31916830441914495,
		1.5951317572267725,
		-1.427109271939844
	]
	for i in 5:
		var ring := Logic.roll_ring(rng, i, Logic.LANTERN)
		assert_almost(float(ring["x"]), float(xs[i]), 1e-12, "Ring %d" % i)
		assert_eq(bool(ring["gold"]), i == 4, "jeder 5. golden")
		assert_eq(int(ring["points"]), 5 if i == 4 else 2)
	var c0 := Logic.roll_cloud(rng, 0, Logic.LANTERN)
	assert_false(bool(c0["present"]), "vor CLOUD_MIN_INDEX nie eine Wolke")
	assert_almost(float(c0["x"]), 0.195718479831703, 1e-12)
	var c1 := Logic.roll_cloud(rng, 3, Logic.LANTERN)
	assert_false(bool(c1["present"]))
	var c2 := Logic.roll_cloud(rng, 4, Logic.LANTERN)
	assert_true(bool(c2["present"]))
	assert_almost(float(c2["x"]), 2.010006224643439, 1e-12)


func test_gust_schedule_matches_web() -> void:
	var want := [
		[7.0, 8.1, 9.5, 1],
		[16.0, 17.1, 18.5, -1],
		[25.0, 26.1, 27.5, -1],
		[34.0, 35.1, 36.5, 1],
		[43.0, 44.1, 45.5, 1],
		[52.0, 53.1, 54.5, -1],
	]
	for i in want.size():
		var g := Logic.gust_at(i, Logic.LANTERN)
		assert_almost(float(g["startSec"]), float(want[i][0]), 1e-9, "start %d" % i)
		assert_almost(float(g["pushSec"]), float(want[i][1]), 1e-9, "push %d" % i)
		assert_almost(float(g["endSec"]), float(want[i][2]), 1e-9, "ende %d" % i)
		assert_eq(int(g["dir"]), int(want[i][3]), "richtung %d" % i)
	assert_eq(str(Logic.gust_phase_at(0.0, Logic.LANTERN)["phase"]), "idle")
	assert_eq(str(Logic.gust_phase_at(7.0, Logic.LANTERN)["phase"]), "telegraph")
	assert_eq(str(Logic.gust_phase_at(8.5, Logic.LANTERN)["phase"]), "push")
	var after := Logic.gust_phase_at(9.5, Logic.LANTERN)
	assert_eq(str(after["phase"]), "idle")
	assert_eq(int((after["gust"] as Dictionary)["index"]), 1, "nach dem Ende zählt die nächste")


func test_steer_and_spacing() -> void:
	assert_almost(Logic.steer_target_from(0.0), 0.0)
	assert_almost(Logic.steer_target_from(1.0), 3.875)
	assert_almost(Logic.steer_target_from(-1.0), -3.875)
	assert_almost(Logic.steer_target_from(2.0), 3.875, 1e-9, "geklemmt")
	assert_almost(Logic.clamp_lantern_x(9.0), 3.1)
	assert_almost(Logic.clamp_lantern_x(-9.0), -3.1)
	assert_almost(Logic.ring_spacing_at(0.0), 4.4)
	assert_almost(Logic.ring_spacing_at(30.0), 3.9, 1e-9)
	assert_almost(Logic.ring_spacing_at(60.0), 3.4)
	assert_almost(Logic.ring_spacing_at(90.0), 3.4, 1e-9, "Rampe deckelt")


func test_difficulty_rows() -> void:
	var easy: Dictionary = Logic.apply_difficulty(Logic.LANTERN, "easy")
	assert_almost(float(easy["DURATION_SEC"]), 72.0)
	assert_almost(float(easy["RISE_SPEED"]), 2.08)
	assert_almost(float(easy["RING_RADIUS"]), 0.7, 1e-9)
	var hard: Dictionary = Logic.apply_difficulty(Logic.LANTERN, "hard")
	assert_almost(float(hard["RISE_SPEED"]), 3.12, 1e-9)
	assert_almost(float(hard["RING_RADIUS"]), 0.448, 1e-9)
	assert_eq(Logic.apply_difficulty(Logic.LANTERN, "normal"), Logic.LANTERN)


func test_endless_ends_on_three_bumps() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.LANTERN, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.endless_should_end(2, tune))
	assert_true(Logic.endless_should_end(3, tune))
	assert_false(Logic.endless_should_end(9, Logic.LANTERN))
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay("endless", seed_value)
		var by_bumps := int(run["bumps"]) >= 3
		var by_guard := float(run["elapsed"]) >= 600.0
		assert_true(by_bumps or by_guard, "Endlos terminiert (seed %d)" % seed_value)


func test_score_edges() -> void:
	assert_eq(Logic.apply_score(0, 2), 2)
	assert_eq(Logic.apply_score(2, -3), 0, "Rempler gehen nie ins Minus")
	assert_eq(Logic.apply_score(10, -3), 7)
	# Endlos zieht KEINE Punkte ab (nur Strikes) — Beleg aus dem Bot.
	var run: Dictionary = Logic.simulate_autoplay("endless", 1)
	assert_eq(int(run["bumps"]), 3)
	assert_true(int(run["score"]) > 0)
	assert_true(Logic.ring_hit(0.5, {"x": 0.2}), "innerhalb RING_RADIUS")
	assert_false(Logic.ring_hit(1.0, {"x": 0.2}), "außerhalb")
	assert_true(Logic.cloud_hit(0.5, {"x": 0.0}))
	assert_false(Logic.cloud_hit(1.0, {"x": 0.0}))
