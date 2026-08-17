extends TestCase
## Guck-guck-Garten (hideSeek) — Logik-Parität zum Web (MG-3, Batch 3).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/hideSeek.logic.js
## (simulateSeekAutoplay / rollHiders) — sie beweisen den zahlengleichen Port.

const Logic := preload("res://scripts/minigames/games/hide_seek/hide_seek_logic.gd")

## Web-Goldwerte: simulateSeekAutoplay(mode, seed).score für Seeds 1..5.
const GOLD := {
	"easy": [135, 126, 130, 126, 128],
	"normal": [109, 102, 104, 98, 102],
	"hard": [95, 81, 97, 86, 97],
	"endless": [155, 81, 133, 313, 196],
}


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.SEEK
	assert_eq(float(t["DURATION_SEC"]), 60.0)
	assert_eq(int(t["COLS"]), 3)
	assert_eq(int(t["ROWS"]), 4)
	assert_eq(int(t["WAVE_HIDERS_START"]), 3)
	assert_eq(int(t["WAVE_HIDERS_MAX"]), 5)
	assert_eq(int(t["WAVE_RAMP_WAVES"]), 4)
	assert_eq(int(t["FIND_PTS"]), 2)
	assert_eq(int(t["WAVE_BONUS"]), 3)
	assert_almost(float(t["WAVE_SEC_START"]), 13.0)
	assert_almost(float(t["WAVE_SEC_END"]), 9.0)
	assert_almost(float(t["PEEK_EVERY_SEC"]), 2.4)
	assert_almost(float(t["PEEK_DURATION_SEC"]), 0.75)
	assert_eq(int(t["ENDLESS_MAX_EXPIRED"]), 3)
	assert_eq(Logic.spot_count(t), 12)


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
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 41):
			sum += int(Logic.simulate_autoplay(mode, seed_value)["score"])
		means[mode] = float(sum) / 40.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_hard_bot_reaches_target() -> void:
	# §G5.4: der Schwer-Bot muss das Ziel 80 in mindestens einem von 5 Seeds
	# erreichen — sonst wäre die Difficulty unbeatbar getunt.
	var best := 0
	for seed_value in range(1, 6):
		best = maxi(best, int(Logic.simulate_autoplay("hard", seed_value)["score"]))
	assert_true(best >= 80, "bester Schwer-Score %d < Ziel 80" % best)


func test_wave_ramps() -> void:
	assert_eq(Logic.hiders_for_wave(0), 3)
	assert_eq(Logic.hiders_for_wave(1), 4)
	assert_eq(Logic.hiders_for_wave(2), 4)
	assert_eq(Logic.hiders_for_wave(3), 5)
	assert_eq(Logic.hiders_for_wave(4), 5)
	assert_eq(Logic.hiders_for_wave(99), 5, "Rampe deckelt")
	assert_almost(Logic.wave_sec_for(0), 13.0)
	assert_almost(Logic.wave_sec_for(2), 11.0)
	assert_almost(Logic.wave_sec_for(4), 9.0)
	assert_almost(Logic.wave_sec_for(99), 9.0, 1e-9, "Uhr deckelt")


func test_roll_hiders_matches_web() -> void:
	# Web: rollHiders(rng(seed 1), 0) → [2,7,10]; direkt danach Welle 4 →
	# [1,3,6,7,9] (derselbe RNG-Strom).
	var rng := GoobyRng.new(1)
	assert_eq(Logic.roll_hiders(rng, 0), [2, 7, 10] as Array[int])
	assert_eq(Logic.roll_hiders(rng, 4), [1, 3, 6, 7, 9] as Array[int])
	# Eindeutig + im Raster, egal welcher Seed.
	for seed_value in range(1, 25):
		var spots := Logic.roll_hiders(GoobyRng.new(seed_value), 9)
		assert_eq(spots.size(), 5, "Welle 9 versteckt 5")
		var seen := {}
		for s in spots:
			assert_true(s >= 0 and s < 12, "Index im Raster")
			assert_false(seen.has(s), "keine Doppel")
			seen[s] = true


func test_difficulty_rows() -> void:
	var easy: Dictionary = Logic.apply_difficulty(Logic.SEEK, "easy")
	assert_almost(float(easy["DURATION_SEC"]), 72.0)
	assert_almost(float(easy["WAVE_SEC_START"]), 16.25)
	assert_almost(float(easy["AUTOPLAY_FIND_RATE"]), 0.97)
	var hard: Dictionary = Logic.apply_difficulty(Logic.SEEK, "hard")
	assert_almost(float(hard["WAVE_SEC_START"]), 10.4)
	assert_almost(float(hard["PEEK_EVERY_SEC"]), 3.0)
	assert_false(bool(hard["ENDLESS"]))
	# `normal` liefert die unveränderte Basis-Tabelle (§G5.3).
	assert_eq(Logic.apply_difficulty(Logic.SEEK, "normal"), Logic.SEEK)


func test_endless_ends_on_three_expired() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.SEEK, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.endless_should_end(2, tune))
	assert_true(Logic.endless_should_end(3, tune))
	assert_false(Logic.endless_should_end(9, Logic.SEEK), "Zeitmodus kennt kein Strike-Ende")
	# Jeder Endlos-Lauf terminiert: an 3 Strikes ODER am 600-s-Sicherheitsnetz.
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay("endless", seed_value)
		var by_strikes := int(run["expired"]) >= 3
		var by_guard := float(run["elapsed"]) >= 600.0
		assert_true(by_strikes or by_guard, "Endlos terminiert (seed %d)" % seed_value)


func test_score_edges() -> void:
	assert_eq(Logic.apply_score(0, 2), 2)
	assert_eq(Logic.apply_score(1, -5), 0, "nie negativ")
	assert_eq(Logic.apply_score(10, 0), 10)
