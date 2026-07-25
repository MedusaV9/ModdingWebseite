extends TestCase
## Pfannkuchenturm (pancakeTower) — Logik-Parität zum Web (MG-2, Batch 2).
## Goldwerte aus `node` auf
## GOOBY/src/minigames/games/pancakeTower.logic.js (simulatePancakeAutoplay).

const Logic := preload("res://scripts/minigames/games/pancake_tower/pancake_tower_logic.gd")

## Web-Goldwerte: simulatePancakeAutoplay(mode, seed).score für Seeds 1..5.
const GOLD := {
	"easy": [192, 192, 192, 192, 192],
	"normal": [168, 166, 170, 150, 168],
	"hard": [150, 148, 152, 134, 154],
	"endless": [448, 450, 434, 414, 466],
}


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.PANCAKE
	assert_almost(float(t["BASE_WIDTH"]), 1.5)
	assert_almost(float(t["LAYER_HEIGHT"]), 0.16)
	assert_almost(float(t["PERFECT_EPS"]), 0.045)
	assert_eq(int(t["PERFECT_POINTS"]), 2)
	assert_almost(float(t["PERFECT_RESTORE_PCT"]), 0.1)
	assert_eq(int(t["TOPPING_EVERY"]), 5)
	assert_eq(int(t["TOPPING_POINTS"]), 4)
	assert_eq(int(t["POINTS_PER_LAYER"]), 2)
	assert_almost(float(t["END_WIDTH_FRAC"]), 0.2)
	assert_almost(float(t["MAX_LAYERS"]), 40.0)
	assert_almost(float(t["SLIDE_AMPLITUDE"]), 1.05)
	assert_almost(float(t["SLIDE_PERIOD_START"]), 2.6)
	assert_almost(float(t["SLIDE_PERIOD_STEP"]), 0.055)
	assert_almost(float(t["SLIDE_PERIOD_MIN"]), 1.15)
	assert_almost(float(t["FALL_SPEED"]), 7.0)
	assert_eq(int(t["WOBBLE_START_LAYER"]), 8)
	assert_almost(float(t["WOBBLE_MAX_RAD"]), 0.16)
	assert_almost(float(t["FALLEN_DESPAWN_SEC"]), 1.4)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(mode, i + 1)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(mode, 11), Logic.simulate_autoplay(mode, 11), mode)


func test_difficulty_is_monotone() -> void:
	# Leicht streut enger (0.055) als Mittel (0.065) als Schwer (0.075), und die
	# Perfect-Toleranz skaliert mit — der Bot muss in dieser Reihenfolge fallen.
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 41):
			sum += int(Logic.simulate_autoplay(mode, seed_value)["score"])
		means[mode] = float(sum) / 40.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_hard_bot_reaches_target() -> void:
	# §G5.4-Ziel für pancakeTower ist 45 — der Schwer-Bot muss es klar schaffen.
	for seed_value in range(1, 11):
		var score: int = int(Logic.simulate_autoplay("hard", seed_value)["score"])
		assert_true(score >= 45, "Schwer-Score %d < Ziel 45 (seed %d)" % [score, seed_value])


func test_endless_has_no_layer_cap_but_terminates() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.PANCAKE, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_eq(float(tune["MAX_LAYERS"]), INF)
	assert_false(Logic.is_tower_done(1.5, 40, tune), "Endlos deckelt nicht bei 40")
	assert_true(Logic.is_tower_done(0.29, 3, tune), "Endlos endet an der Breite")
	# Der Endlos-Bot läuft gegen den 120-Lagen-Sicherheitsdeckel des Simulators.
	for seed_value in range(1, 16):
		var run: Dictionary = Logic.simulate_autoplay("endless", seed_value)
		assert_true(int(run["layers"]) <= 120, "Endlos terminiert (seed %d)" % seed_value)


func test_timed_end_conditions() -> void:
	var t: Dictionary = Logic.PANCAKE
	assert_true(Logic.is_tower_done(0.2999, 1, t), "Breite < 20 % beendet")
	assert_false(Logic.is_tower_done(0.3001, 1, t))
	assert_true(Logic.is_tower_done(1.5, 40, t), "40 Lagen beenden")
	assert_false(Logic.is_tower_done(1.5, 39, t))


func test_perfect_drop_restores_width() -> void:
	var t: Dictionary = Logic.PANCAKE
	var drop: Dictionary = Logic.resolve_drop({"center": 0.0, "width": 1.0}, 0.02, false, t)
	assert_true(bool(drop["perfect"]))
	assert_almost(float(drop["width"]), 1.15, 1e-9, "+10 % der Basisbreite")
	assert_almost(float(drop["center"]), 0.0, 1e-9, "rastet auf die Mitte")
	assert_eq(int(drop["points"]), 2)
	# Deckel: nie breiter als BASE_WIDTH.
	var full: Dictionary = Logic.resolve_drop({"center": 0.0, "width": 1.45}, 0.0, false, t)
	assert_almost(float(full["width"]), 1.5)


func test_slice_and_total_miss() -> void:
	var t: Dictionary = Logic.PANCAKE
	var cut: Dictionary = Logic.resolve_drop({"center": 0.0, "width": 1.0}, 0.4, false, t)
	assert_true(bool(cut["landed"]))
	assert_false(bool(cut["perfect"]))
	assert_almost(float(cut["width"]), 0.6, 1e-9, "Überlappung bleibt")
	assert_almost(float(cut["center"]), 0.2, 1e-9)
	assert_almost(float((cut["cut"] as Dictionary)["size"]), 0.4, 1e-9)
	assert_eq(int((cut["cut"] as Dictionary)["side"]), 1)
	var miss: Dictionary = Logic.resolve_drop({"center": 0.0, "width": 1.0}, 1.4, false, t)
	assert_false(bool(miss["landed"]))
	assert_eq(int(miss["points"]), 0)


func test_topping_layers_never_shrink() -> void:
	var t: Dictionary = Logic.PANCAKE
	assert_true(Logic.is_topping_layer(5, t))
	assert_true(Logic.is_topping_layer(10, t))
	assert_false(Logic.is_topping_layer(4, t))
	assert_false(Logic.is_topping_layer(0, t))
	var drop: Dictionary = Logic.resolve_drop({"center": 0.0, "width": 1.0}, 0.3, true, t)
	assert_almost(float(drop["width"]), 1.0, 1e-9, "Topping schrumpft nie")
	assert_true((drop["cut"] as Dictionary).is_empty())
	assert_eq(int(drop["points"]), 4)
	assert_eq(int(Logic.resolve_drop({"center": 0.0, "width": 1.0}, 0.0, true, t)["points"]), 6)


func test_slide_ramp() -> void:
	var t: Dictionary = Logic.PANCAKE
	assert_almost(Logic.slide_period(1, t), 2.6)
	assert_almost(Logic.slide_period(11, t), 2.05)
	assert_almost(Logic.slide_period(30, t), 1.15, 1e-9, "Periode gedeckelt")
	assert_almost(Logic.slide_x(0.0, 1, 0.0, t), 0.0, 1e-9)
	assert_almost(Logic.slide_x(0.5, 1, 0.0, t), 0.9817670548196855, 1e-9)


func test_wobble_starts_at_layer_eight() -> void:
	var t: Dictionary = Logic.PANCAKE
	var state: Dictionary = Logic.initial_wobble_state()
	for i in 200:
		state = Logic.step_wobble(state, 1.0 / 60.0, 3, t)
	assert_almost(float(state["angle"]), 0.0, 1e-6, "unter Lage 8 steht der Turm")
	var swaying: Dictionary = Logic.initial_wobble_state()
	for i in 200:
		swaying = Logic.step_wobble(swaying, 1.0 / 60.0, 20, t)
	assert_true(absf(float(swaying["angle"])) > 0.001, "ab Lage 8 schwankt er")
	assert_true(absf(float(swaying["angle"])) <= float(t["WOBBLE_MAX_RAD"]) + 1e-9, "gedeckelt")
	# Perfekte Abwürfe beruhigen — im Endlos-Modus ab Lage 8 aber nicht mehr.
	var damped: Dictionary = Logic.damp_wobble(swaying, t, 20)
	assert_almost(float(damped["angle"]), float(swaying["angle"]) * 0.4, 1e-9)
	var endless: Dictionary = Logic.apply_difficulty(Logic.PANCAKE, "endless")
	assert_almost(
		float(Logic.damp_wobble(swaying, endless, 20)["angle"]), float(swaying["angle"]), 1e-9
	)


func test_wobble_projection_roundtrip() -> void:
	var angle := 0.12
	var world := Logic.wobble_top_x(0.3, 2.0, angle)
	assert_almost(Logic.wobble_local_x(world, 2.0, angle), 0.3, 1e-9)


func test_score_and_despawn_edges() -> void:
	var t: Dictionary = Logic.PANCAKE
	assert_eq(Logic.tower_score(0, 0, t), 0)
	assert_eq(Logic.tower_score(10, 6, t), 26)
	assert_eq(Logic.tower_score(0, -99, t), 0, "nie negativ")
	assert_false(Logic.is_fallen_expired(1.39, t))
	assert_true(Logic.is_fallen_expired(1.4, t))
