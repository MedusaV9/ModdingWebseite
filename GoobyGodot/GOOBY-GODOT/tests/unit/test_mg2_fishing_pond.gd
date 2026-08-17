extends TestCase
## Angelteich (fishingPond) — Logik-Parität zum Web (MG-2, Batch 2).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/fishingPond.logic.js.

const Logic := preload("res://scripts/minigames/games/fishing_pond/fishing_pond_logic.gd")

## Web-Goldwerte: simulateFishingAutoplay(seed, mode).score für Seeds 1..5.
const GOLD := {
	"easy": [126, 110, 139, 119, 144],
	"normal": [92, 81, 100, 70, 92],
	"hard": [67, 56, 82, 65, 72],
	"endless": [88, 89, 103, 86, 102],
}


func _stream(seed_value: int) -> Callable:
	var rng := GoobyRng.new(seed_value)
	return func() -> float: return rng.next()


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.FISHING
	assert_almost(float(t["DURATION_SEC"]), 90.0)
	assert_eq(int(t["VALUES"]["S"]), 2)
	assert_eq(int(t["VALUES"]["M"]), 3)
	assert_eq(int(t["VALUES"]["L"]), 5)
	assert_eq(int(t["VALUES"]["boot"]), -3)
	assert_eq(int(t["REEL_TAPS"]), 5)
	assert_almost(float(t["REEL_WINDOW_SEC"]), 2.0)
	assert_almost(float(t["REEL_MAX_FRAME_SEC"]), 0.1)
	assert_almost(float(t["CATCH_RADIUS"]), 0.55)
	assert_almost(float(t["MAX_DEPTH"]), 3.9)
	assert_almost(float(t["LOWER_SPEED"]), 2.1)
	assert_almost(float(t["RAISE_SPEED"]), 3.4)
	assert_eq(int(t["FISH_COUNT"]), 7)
	assert_almost(float(t["RESPAWN_SEC"]), 1.2)
	assert_almost(float(t["BOOT_MIN_GAP_SEC"]), 14.0)
	assert_almost(float(t["BOOT_CHANCE"]), 0.6)
	assert_eq(int(t["SIZES"]["S"]["weight"]), 45)
	assert_eq(int(t["SIZES"]["M"]["weight"]), 35)
	assert_eq(int(t["SIZES"]["L"]["weight"]), 20)
	assert_almost(Logic.GOLDEN_FISH_CHANCE, 0.02)
	assert_eq(Logic.RARE_SET_BONUS, 15)


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
			Logic.simulate_autoplay(13, mode)["score"], Logic.simulate_autoplay(14, mode)["score"]
		)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 41):
			sum += int(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = float(sum) / 40.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)
	var easy: Dictionary = Logic.apply_difficulty(Logic.FISHING, "easy")
	assert_almost(float(easy["DURATION_SEC"]), 108.0)
	assert_almost(float(easy["RESPAWN_SEC"]), 1.44)
	assert_almost(float(easy["BOOT_MIN_GAP_SEC"]), 16.8)
	assert_almost(float(easy["REEL_WINDOW_SEC"]), 2.5)
	assert_almost(float(easy["CATCH_RADIUS"]), 0.6875)
	var hard: Dictionary = Logic.apply_difficulty(Logic.FISHING, "hard")
	assert_almost(float(hard["DURATION_SEC"]), 90.0)
	assert_almost(float(hard["RESPAWN_SEC"]), 1.02)
	assert_almost(float(hard["BOOT_MIN_GAP_SEC"]), 11.9)
	assert_almost(float(hard["REEL_WINDOW_SEC"]), 1.6)
	assert_almost(float(hard["CATCH_RADIUS"]), 0.44000000000000006)
	assert_eq(Logic.apply_difficulty(Logic.FISHING, "quatsch"), Logic.FISHING)


func test_hard_bot_reaches_target() -> void:
	# §G5.4-Ziel für fishingPond ist 65.
	var best := 0
	for seed_value in range(1, 6):
		best = maxi(best, int(Logic.simulate_autoplay(seed_value, "hard")["score"]))
	assert_true(best >= 65, "bester Schwer-Score %d < Ziel 65" % best)


func test_endless_ends_on_three_failures() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.FISHING, "endless")
	assert_true(bool(tune["ENDLESS"]))
	var state: Dictionary = Logic.create_endless_state()
	assert_eq(int(state["limit"]), 3)
	assert_false(Logic.record_failure(state, "smallFish"), "gute Fänge zählen nicht")
	assert_false(Logic.record_failure(state, "lineBreak"))
	assert_false(Logic.record_failure(state, "boot"))
	assert_true(Logic.record_failure(state, "lineBreak"), "dritter Fehlschlag beendet")
	assert_eq(int(state["failures"]), 3)
	# Nach dem Ende zählt nichts mehr hoch.
	Logic.record_failure(state, "boot")
	assert_eq(int(state["failures"]), 3)


func test_hook_and_catch_radius() -> void:
	var t: Dictionary = Logic.FISHING
	assert_almost(Logic.lower_depth(0.0, 1.0, t), 2.1)
	assert_almost(Logic.lower_depth(3.8, 1.0, t), 3.9, 1e-9, "gedeckelt")
	var items: Array = [
		{"x": 0.6, "depth": 1.0}, {"x": 0.1, "depth": 1.1}, {"x": 5.0, "depth": 1.0}
	]
	assert_eq(Logic.nearest_catch(items, 0.0, 1.0), 1, "nächster im Radius")
	assert_eq(Logic.nearest_catch(items, 0.0, 1.0, 0.05), -1, "nichts in Reichweite")
	assert_eq(Logic.nearest_catch([], 0.0, 1.0), -1)


func test_reel_window() -> void:
	assert_eq(Logic.reel_resolve(5, 1.0), "caught")
	assert_eq(Logic.reel_resolve(2, 2.5), "escaped")
	assert_eq(Logic.reel_resolve(2, 1.0), "reeling")
	assert_eq(Logic.reel_resolve(5, 9.0), "caught", "genug Taps schlagen das Fenster")
	# Ruckelschutz: ein langer Frame kostet höchstens 0.1 s.
	assert_almost(Logic.advance_reel_elapsed(0.0, 0.5), 0.1)
	assert_almost(Logic.advance_reel_elapsed(0.0, 0.02), 0.02)
	assert_almost(Logic.advance_reel_elapsed(1.0, -5.0), 1.0)
	assert_true(Logic.needs_reel("L"))
	assert_false(Logic.needs_reel("S"))
	assert_false(Logic.needs_reel("boot"))


func test_scoring_edges() -> void:
	assert_eq(Logic.catch_value("S"), 2)
	assert_eq(Logic.catch_value("M"), 3)
	assert_eq(Logic.catch_value("L"), 5)
	assert_eq(Logic.catch_value("boot"), -3)
	assert_eq(Logic.apply_catch(0, -3), 0, "nie unter null")
	assert_eq(Logic.apply_catch(2, -3), 0)
	assert_eq(Logic.apply_catch(10, 5), 15)


func test_rolls_match_web_stream() -> void:
	# Gleicher mulberry32-Strom wie im Web (Seed 5) → gleiche Würfe.
	var rng := _stream(5)
	var kinds := ""
	for i in 12:
		kinds += Logic.roll_fish_kind(rng)
	assert_eq(kinds, "LSSSLSSMMMSS")
	var speeds := _stream(5)
	assert_almost(Logic.fish_speed_for("M", speeds), 0.5793259122408927, 1e-9)
	assert_almost(Logic.fish_speed_for("M", speeds), 0.3965050910227001, 1e-9)
	# Stiefel: erst nach der Mindestpause zulässig.
	assert_false(Logic.should_spawn_boot(_stream(1), 5.0), "zu früh für einen Stiefel")
	var boots := _stream(12)
	var seen := PackedStringArray()
	for i in 6:
		seen.append("1" if Logic.should_spawn_boot(boots, 20.0) else "0")
	assert_eq("".join(seen), "101101")


func test_species_rolls_match_web() -> void:
	var night := _stream(3)
	var got := PackedStringArray()
	for i in 6:
		got.append(str(Logic.roll_species_detail("L", night, true)["species"]))
	assert_eq(
		got,
		PackedStringArray(
			["nightEel", "bigWhopper", "nightEel", "nightEel", "nightEel", "nightEel"]
		)
	)
	var day := _stream(4)
	var mids := PackedStringArray()
	for i in 6:
		mids.append(str(Logic.roll_species_detail("M", day, false)["species"]))
	assert_eq(
		mids,
		PackedStringArray(
			["stripeBass", "pinkKoi", "stripeBass", "stripeBass", "stripeBass", "pinkKoi"]
		)
	)
	var golden := _stream(11)
	var l_day := PackedStringArray()
	for i in 5:
		l_day.append(Logic.roll_species("L", golden))
	assert_eq(
		l_day,
		PackedStringArray(["bigWhopper", "bigWhopper", "goldenFish", "bigWhopper", "bigWhopper"])
	)


func test_rare_set_and_colors() -> void:
	assert_eq(Logic.species_collection_id("gildedWhopper"), "goldenFish")
	assert_eq(Logic.species_collection_id("pinkKoi"), "pinkKoi")
	assert_eq(Logic.rare_set_bonus(["pearlMinnow", "sunsetKoi", "gildedWhopper"]), 15)
	assert_eq(Logic.rare_set_bonus(["pearlMinnow", "pearlMinnow", "sunsetKoi"]), 0)
	assert_eq(Logic.rare_set_bonus([]), 0)
	assert_eq(Logic.species_color("goldenFish"), Color("#FFD24A"))
	assert_eq(Logic.species_color("unbekannt"), Color("#9FB2C8"), "Fallback")
