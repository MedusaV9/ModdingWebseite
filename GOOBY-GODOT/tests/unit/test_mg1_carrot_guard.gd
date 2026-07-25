extends TestCase
## Karotten-Wache (carrotGuard) — Logik-Parität zum Web (MG-1, Batch 1).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/carrotGuard.logic.js
## (simulateGuardAutoplay) — sie sperren Kadenz-Rampe, Kombo-Bonus und die
## König-Maulwurf-Ausschüttung fest.

const Logic := preload("res://scripts/minigames/games/carrot_guard/carrot_guard_logic.gd")
const MANIFEST := "res://scripts/minigames/games/carrot_guard/game.json"

## Web-Goldwerte: simulateGuardAutoplay(seed, mode).score für Seeds 1..8.
const GOLD := {
	"easy": [78, 82, 79, 80, 67, 71, 85, 75],
	"normal": [78, 77, 75, 75, 67, 66, 81, 75],
	"hard": [82, 50, 80, 43, 75, 67, 62, 78],
	"endless": [34, 26, 23, 2, 10, 11, 22, 12],
}
const WEB_TARGET := 70


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.GUARD
	assert_almost(float(t["DURATION_SEC"]), 45.0)
	assert_eq(int(t["GRID"]), 3)
	assert_eq(int(t["CARROTS"]), 10)
	assert_almost(float(t["UP_TIME_START"]), 0.9)
	assert_almost(float(t["UP_TIME_END"]), 0.5)
	assert_eq(int(t["HIT_POINTS"]), 1)
	assert_eq(int(t["COMBO_BONUS_AT"]), 5)
	assert_eq(int(t["COMBO_BONUS"]), 3)
	assert_almost(float(t["SPAWN_START_SEC"]), 1.3)
	assert_almost(float(t["SPAWN_END_SEC"]), 0.75)
	assert_almost(float(t["DOUBLE_CHANCE_END"]), 0.35)
	assert_eq(int(t["KING_EVERY_BONKS"]), 20)
	assert_eq(int(t["KING_TAPS"]), 3)
	assert_eq(int(t["KING_POINTS"]), 8)
	assert_eq(int(t["KING_COIN_DROP"]), 2)
	assert_eq(int(t["KING_SCORE_PER_COIN"]), 3)
	assert_eq(int(t["ENDLESS_STOLEN"]), 3)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(9, mode), Logic.simulate_autoplay(9, mode), mode)
		assert_ne(
			int(Logic.simulate_autoplay(2, mode)["score"]),
			int(Logic.simulate_autoplay(4, mode)["score"]),
			mode
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
		assert_true(int(run["score"]) < 300, "Score bleibt plausibel (seed %d)" % seed_value)
		# Entweder die Uhr oder die Karotten beenden die Runde — nie das Netz.
		var by_clock := float(run["elapsed"]) >= 45.0
		var by_carrots := int(run["stolen"]) >= 10
		assert_true(by_clock or by_carrots, "Runde endet regulär (seed %d)" % seed_value)
		best = maxi(best, int(run["score"]))
	assert_true(best >= WEB_TARGET, "bester Schwer-Score %d < Ziel %d" % [best, WEB_TARGET])


func test_endless_ends_on_three_stolen_carrots() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.GUARD, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.is_round_over({"elapsed": 999.0, "carrots": 8}, 45.0, tune), "2 geklaute")
	assert_true(Logic.is_round_over({"elapsed": 0.0, "carrots": 7}, 45.0, tune), "3 geklaute")
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "endless")
		assert_true(
			int(run["stolen"]) >= 3, "Endlos endet am Karotten-Limit (seed %d)" % seed_value
		)


func test_timed_round_ends_on_clock_or_empty_bed() -> void:
	assert_false(Logic.is_round_over({"elapsed": 44.9, "carrots": 4}))
	assert_true(Logic.is_round_over({"elapsed": 45.0, "carrots": 4}), "die Uhr beendet")
	assert_true(Logic.is_round_over({"elapsed": 1.0, "carrots": 0}), "leeres Beet beendet")
	assert_almost(float(Logic.apply_difficulty(Logic.GUARD, "easy")["DURATION_SEC"]), 54.0)


func test_score_edges() -> void:
	var state := {"score": 0, "combo": 0}
	for i in 4:
		state = Logic.apply_bonk(state)
		assert_eq(int(state["score"]), i + 1, "jeder Treffer zahlt genau 1")
	# Der 5. Treffer in Serie zahlt zusätzlich +3.
	state = Logic.apply_bonk(state)
	assert_eq(int(state["score"]), 8)
	assert_eq(int(state["combo"]), 5)
	assert_eq(Logic.combo_bonus(10), 3, "der Bonus zahlt bei JEDEM Vielfachen von 5")
	assert_eq(Logic.combo_bonus(7), 0)
	assert_eq(Logic.combo_bonus(0), 0)
	# Entwischt: Karotte weg, Kombo weg, aber keine Minuspunkte.
	var escaped: Dictionary = Logic.apply_escape({"carrots": 3, "combo": 9})
	assert_eq(int(escaped["carrots"]), 2)
	assert_eq(int(escaped["combo"]), 0)
	assert_eq(int(Logic.apply_escape({"carrots": 0, "combo": 1})["carrots"]), 0, "nie negativ")
	assert_eq(int(Logic.apply_whiff({"combo": 6})["combo"]), 0)
	assert_true(Logic.accepts_tap_after(0.08))
	assert_false(Logic.accepts_tap_after(0.05), "Doppel-Tap wird entprellt")


func test_king_mole_payout() -> void:
	assert_false(Logic.is_king_due(19, 0))
	assert_true(Logic.is_king_due(20, 0), "nach 20 Treffern kommt der König")
	assert_false(Logic.is_king_due(20, 1), "erst der nächste Block zählt")
	assert_true(Logic.is_king_due(40, 1))
	# Zwei Taps schaden nur, der dritte zahlt 8 + 2 Münzen × 3.
	var first: Dictionary = Logic.apply_king_tap({"score": 0, "combo": 0, "hp": 3})
	assert_false(bool(first["complete"]))
	assert_eq(int(first["score"]), 0)
	var second: Dictionary = Logic.apply_king_tap({"score": 0, "combo": 0, "hp": 2})
	assert_false(bool(second["complete"]))
	var third: Dictionary = Logic.apply_king_tap({"score": 0, "combo": 0, "hp": 1})
	assert_true(bool(third["complete"]))
	assert_eq(int(third["gained"]), 14)
	assert_eq(int(third["score"]), 14)
	# Landet der König auf einem Kombo-Vielfachen, kommen +3 obendrauf.
	var comboed: Dictionary = Logic.apply_king_tap({"score": 10, "combo": 4, "hp": 1})
	assert_eq(int(comboed["gained"]), 17)


func test_ramps_move_the_right_way() -> void:
	assert_almost(Logic.up_time_at(0.0), 0.9)
	assert_almost(Logic.up_time_at(45.0), 0.5)
	assert_almost(Logic.spawn_interval_at(0.0), 1.3)
	assert_almost(Logic.spawn_interval_at(45.0), 0.75)
	assert_almost(Logic.double_chance_at(0.0), 0.0)
	assert_almost(Logic.double_chance_at(45.0), 0.35)
	assert_almost(Logic.double_chance_at(90.0), 0.35, 1e-9, "Rampe ist gedeckelt")


func test_manifest_matches_web_metadata() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_true(file != null, "game.json fehlt")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert_eq(str(manifest["id"]), "carrotGuard")
	assert_eq(int(manifest["target"]), WEB_TARGET)
	assert_eq(str(manifest["orientation"]), "portrait")
	var coins: Dictionary = manifest["coin_table"]
	assert_eq(int(coins["divisor"]), 3)
	assert_eq(int(coins["min"]), 4)
	assert_eq(int(coins["max"]), 25)
	assert_true(ResourceLoader.exists(str(manifest["scene"])), "Szene fehlt")
