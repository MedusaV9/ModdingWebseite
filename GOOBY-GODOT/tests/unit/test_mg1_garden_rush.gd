extends TestCase
## Gießkannen-Wirbel (gardenRush) — Logik-Parität zum Web (MG-1, Batch 1).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/gardenRush.logic.js
## (simulateRushAutoplay) — sie sperren Welkfenster, Füllring-Zonen und den
## Sprinkler fest.

const Logic := preload("res://scripts/minigames/games/garden_rush/garden_rush_logic.gd")
const MANIFEST := "res://scripts/minigames/games/garden_rush/game.json"

## Web-Goldwerte: simulateRushAutoplay(seed, mode).score für Seeds 1..8.
const GOLD := {
	"easy": [69, 69, 66, 69, 66, 69, 69, 69],
	"normal": [69, 69, 66, 60, 66, 63, 69, 66],
	"hard": [63, 69, 69, 42, 60, 57, 66, 63],
	"endless": [18, 57, 15, 9, 33, 33, 18, 39],
}
const WEB_TARGET := 65


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.RUSH
	assert_almost(float(t["DURATION_SEC"]), 60.0)
	assert_eq(int(t["POTS"]), 8)
	assert_eq(int(t["START_POTS"]), 6)
	assert_almost(float(t["POT7_AT_SEC"]), 20.0)
	assert_almost(float(t["POT8_AT_SEC"]), 35.0)
	assert_almost(float(t["WILT_START_SEC"]), 6.0)
	assert_almost(float(t["WILT_END_SEC"]), 3.0)
	assert_almost(float(t["FILL_SEC"]), 0.8)
	assert_almost(float(t["PERFECT_ZONE"]), 0.25)
	assert_eq(int(t["PERFECT_PTS"]), 3)
	assert_eq(int(t["EARLY_PTS"]), 1)
	assert_eq(int(t["WILT_PTS"]), -2)
	assert_eq(int(t["WEED_PTS"]), -1)
	assert_almost(float(t["SPAWN_START_SEC"]), 3.1)
	assert_almost(float(t["SPAWN_END_SEC"]), 2.0)
	assert_almost(float(t["RESPAWN_SEC"]), 0.9)
	assert_almost(float(t["WEED_FROM_SEC"]), 12.0)
	assert_almost(float(t["WEED_CHANCE"]), 0.18)
	assert_almost(float(t["WEED_LIFE_SEC"]), 5.0)
	assert_almost(float(t["SPRINKLER_AT_SEC"]), 30.0)
	assert_almost(float(t["SPRINKLER_FILL_FRAC"]), 0.5)
	assert_eq(int(t["ENDLESS_WILTS"]), 3)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(13, mode), Logic.simulate_autoplay(13, mode), mode)
	assert_ne(
		int(Logic.simulate_autoplay(4, "hard")["score"]),
		int(Logic.simulate_autoplay(5, "hard")["score"])
	)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 21):
			sum += int(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = float(sum) / 20.0
	assert_true(means["easy"] >= means["normal"], "leicht ≥ normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_bot_scores_are_plausible() -> void:
	var best := 0
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "hard")
		assert_true(int(run["score"]) > 0, "Schwer-Bot punktet (seed %d)" % seed_value)
		# Deckel: höchstens 3 Punkte je Spawn in 60 s bei ≥2 s Kadenz.
		assert_true(int(run["score"]) <= 120, "Score bleibt plausibel (seed %d)" % seed_value)
		best = maxi(best, int(run["score"]))
	assert_true(best >= WEB_TARGET, "bester Schwer-Score %d < Ziel %d" % [best, WEB_TARGET])


func test_endless_ends_on_three_wilted_pots() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.RUSH, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.endless_should_end(2, tune))
	assert_true(Logic.endless_should_end(3, tune))
	assert_false(Logic.endless_should_end(99, Logic.RUSH), "getaktet gibt es kein Limit")
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "endless")
		assert_true(int(run["withered"]) >= 3, "Endlos endet am Welk-Limit (seed %d)" % seed_value)
	# Endlos rampt weiter, hat aber Böden für Kadenz und Welkfenster.
	assert_almost(Logic.spawn_interval_at(600.0, 60.0, tune), 1.0)
	assert_almost(Logic.wilt_window_at(600.0, 60.0, tune), 1.2)


func test_score_edges() -> void:
	# Letztes Viertel des Rings = perfekt, alles davor zahlt +1.
	assert_eq(Logic.release_points(1.0), 3)
	assert_eq(Logic.release_points(0.75), 3, "genau an der Zonengrenze")
	assert_eq(Logic.release_points(0.74), 1)
	assert_eq(Logic.release_points(0.0), 1)
	assert_true(Logic.in_perfect_zone(0.9))
	assert_false(Logic.in_perfect_zone(0.5))
	# Füllanteil kommt aus echter Haltedauer und ist geklemmt.
	assert_almost(Logic.hold_fill_fraction(0.4), 0.5)
	assert_almost(Logic.hold_fill_fraction(0.8), 1.0)
	assert_almost(Logic.hold_fill_fraction(9.0), 1.0)
	assert_almost(Logic.hold_fill_fraction(-1.0), 0.0)
	assert_eq(Logic.apply_points(1, -2), 0, "Score ist bei 0 gefloort")
	assert_eq(Logic.apply_points(10, -2), 8)
	assert_eq(Logic.apply_points(5, 3), 8)


func test_pot_and_window_ramps() -> void:
	assert_eq(Logic.active_pots_at(0.0), 6)
	assert_eq(Logic.active_pots_at(19.9), 6)
	assert_eq(Logic.active_pots_at(20.0), 7)
	assert_eq(Logic.active_pots_at(35.0), 8)
	assert_almost(Logic.wilt_window_at(0.0), 6.0)
	assert_almost(Logic.wilt_window_at(60.0), 3.0)
	assert_almost(Logic.spawn_interval_at(0.0), 3.1)
	assert_almost(Logic.spawn_interval_at(60.0), 2.0)
	# Unkraut kommt erst ab 12 s und dann mit 18 %.
	var rng := GoobyRng.new(2)
	for _i in 20:
		assert_false(Logic.roll_weed(rng, 11.9), "vor 12 s wächst kein Unkraut")
	var weeds := 0
	for _i in 200:
		if Logic.roll_weed(rng, 30.0):
			weeds += 1
	assert_true(weeds > 10 and weeds < 70, "Unkrautquote liegt bei ~18 %% (%d/200)" % weeds)


func test_sprinkler_fires_once_and_refills_half() -> void:
	assert_false(Logic.should_spawn_sprinkler(29.9, false))
	assert_true(Logic.should_spawn_sprinkler(30.0, false), "bei 30 s kommt der Sprinkler")
	assert_true(Logic.should_spawn_sprinkler(45.0, false), "auch ein Frame-Sprung fängt ihn")
	assert_false(Logic.should_spawn_sprinkler(59.0, true), "aber nur einmal pro Runde")
	# +50 % des Fensters, gedeckelt auf das volle Fenster.
	assert_almost(Logic.sprinkler_refill(1.0, 6.0), 4.0)
	assert_almost(Logic.sprinkler_refill(5.0, 6.0), 6.0)
	assert_almost(Logic.sprinkler_refill(0.0, 4.0), 2.0)
	assert_almost(Logic.sprinkler_refill(-1.0, 4.0), 2.0)


func test_manifest_matches_web_metadata() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_true(file != null, "game.json fehlt")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert_eq(str(manifest["id"]), "gardenRush")
	assert_eq(int(manifest["target"]), WEB_TARGET)
	assert_eq(str(manifest["orientation"]), "portrait")
	var coins: Dictionary = manifest["coin_table"]
	assert_eq(int(coins["divisor"]), 3)
	assert_eq(int(coins["min"]), 4)
	assert_eq(int(coins["max"]), 25)
	assert_true(ResourceLoader.exists(str(manifest["scene"])), "Szene fehlt")
