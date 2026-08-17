extends TestCase
## Trampolin-Tricks (trampoline) — Logik-Parität zum Web (MG-1, Batch 1).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/trampoline.logic.js
## (simulateTrampolineAutoplay) — sie sperren Landefenster, Sprungkette und
## den Dreierpack-Bonus fest.

const Logic := preload("res://scripts/minigames/games/trampoline/trampoline_logic.gd")
const MANIFEST := "res://scripts/minigames/games/trampoline/game.json"

## Web-Goldwerte: simulateTrampolineAutoplay(seed, mode).score für Seeds 1..8.
const GOLD := {
	"easy": [273, 645, 405, 146, 242, 126, 297, 569],
	"normal": [273, 344, 405, 91, 235, 112, 247, 320],
	"hard": [261, 344, 199, 91, 127, 112, 32, 172],
	"endless": [261, 344, 199, 91, 127, 112, 32, 172],
}
const WEB_TARGET := 105


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.TRAMP
	assert_almost(float(t["DURATION_SEC"]), 60.0)
	assert_almost(float(t["TIER2_APEX"]), 2.1)
	assert_almost(float(t["TIER3_APEX"]), 3.3)
	assert_almost(float(t["WINDOW_BASE_SEC"]), 0.3)
	assert_almost(float(t["WINDOW_SHRINK_PER_WU"]), 0.045)
	assert_almost(float(t["WINDOW_MIN_SEC"]), 0.1)
	assert_almost(float(t["JUDGE_ZONE_SEC"]), 0.5)
	assert_almost(float(t["GRAVITY"]), 9.0)
	assert_almost(float(t["BASE_VY"]), 5.0)
	assert_almost(float(t["BOOST_MULT"]), 1.16)
	assert_almost(float(t["BOOST_ADD"]), 0.35)
	assert_almost(float(t["MAX_VY"]), 8.6)
	assert_almost(float(t["DECAY_MULT"]), 0.94)
	assert_almost(float(t["MIN_VY"]), 4.2)
	assert_almost(float(t["TRICK_MIN_AIR_SEC"]), 0.35)
	assert_eq(int(t["COMBO_TRICKS"]), 3)
	assert_eq(int(t["COMBO_FLIP_POINTS"]), 12)
	assert_almost(float(t["BUTT_STAGGER_SEC"]), 1.1)
	assert_eq(int(t["ENDLESS_FAILURE_LIMIT"]), 3)
	assert_eq(int(Logic.TRICK_PTS["flip"]), 2)
	assert_eq(int(Logic.TRICK_PTS["spin"]), 2)
	assert_eq(int(Logic.TRICK_PTS["twist"]), 3)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(8, mode), Logic.simulate_autoplay(8, mode), mode)
		assert_ne(
			int(Logic.simulate_autoplay(2, mode)["score"]),
			int(Logic.simulate_autoplay(3, mode)["score"]),
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
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_bot_scores_are_plausible() -> void:
	var best := 0
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "hard")
		assert_true(int(run["score"]) > 0, "Schwer-Bot punktet (seed %d)" % seed_value)
		assert_true(int(run["score"]) < 2000, "Score bleibt plausibel (seed %d)" % seed_value)
		best = maxi(best, int(run["score"]))
	assert_true(best >= WEB_TARGET, "bester Schwer-Score %d < Ziel %d" % [best, WEB_TARGET])


func test_endless_ends_on_three_butt_landings() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.TRAMP, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.endless_should_end(2, tune))
	assert_true(Logic.endless_should_end(3, tune))
	assert_false(Logic.endless_should_end(99, Logic.TRAMP), "getaktet gibt es kein Limit")
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "endless")
		assert_true(int(run["failures"]) <= 3, "Endlos stoppt am Limit (seed %d)" % seed_value)


func test_score_edges() -> void:
	assert_eq(Logic.trick_points("flip", 1), 2)
	assert_eq(Logic.trick_points("twist", 1), 3)
	assert_eq(Logic.trick_points("twist", 3), 9, "Höhe multipliziert die Trickpunkte")
	assert_eq(Logic.trampoline_score([2, 3, 12]), 17)
	assert_eq(Logic.trampoline_score([]), 0)
	assert_eq(Logic.height_multiplier(0.0), 1)
	assert_eq(Logic.height_multiplier(2.1), 2)
	assert_eq(Logic.height_multiplier(3.3), 3)
	assert_eq(Logic.height_multiplier(2.09), 1, "knapp drunter zählt nicht")
	# Dreierpack: erst Salto+Drehung+Schraube zahlt +12, und nur einmal.
	var chain: Dictionary = Logic.create_trick_chain()
	assert_false(bool(Logic.record_trick(chain, "flip")["triggered"]))
	assert_false(
		bool(Logic.record_trick(chain, "flip")["triggered"]), "gleicher Trick zählt einmal"
	)
	assert_false(bool(Logic.record_trick(chain, "spin")["triggered"]))
	var third: Dictionary = Logic.record_trick(chain, "twist")
	assert_true(bool(third["triggered"]))
	assert_eq(int(third["bonus"]), 12)
	assert_false(bool(Logic.record_trick(chain, "flip")["triggered"]), "Bonus nur einmal je Flug")


func test_landing_window_and_bounce_chain() -> void:
	assert_almost(Logic.window_sec_for(0.0), 0.3)
	assert_almost(Logic.window_sec_for(2.0), 0.21)
	assert_almost(Logic.window_sec_for(99.0), 0.1, 1e-9, "das Fenster hat einen Boden")
	assert_true(Logic.window_sec_for(3.0) < Logic.window_sec_for(1.0), "höher heißt schwerer")
	assert_eq(Logic.classify_landing_tap(0.05, 0.0), "boost")
	assert_eq(Logic.classify_landing_tap(0.45, 0.0), "butt", "zu früh in der Urteilszone")
	assert_eq(Logic.classify_landing_tap(1.2, 0.0), "ignore", "weit weg passiert nichts")
	# Sprungkette: Boost steigt bis MAX_VY, ohne Tap zerfällt sie bis MIN_VY.
	assert_almost(Logic.next_bounce_vy(5.0, "boost"), 6.15)
	assert_almost(Logic.next_bounce_vy(8.5, "boost"), 8.6, 1e-9, "gedeckelt")
	assert_almost(Logic.next_bounce_vy(5.0, "none"), 4.7)
	assert_almost(Logic.next_bounce_vy(4.3, "none"), 4.2, 1e-9, "Boden der Kette")
	assert_almost(Logic.next_bounce_vy(8.0, "butt"), 5.0, 1e-9, "Po-Landung setzt zurück")
	assert_almost(Logic.apex_for(6.0), 2.0)
	assert_almost(Logic.air_time_for(9.0), 2.0)
	assert_almost(Logic.time_to_impact(0.0, 0.0), 0.0)
	assert_almost(Logic.time_to_impact(2.0, 0.0), sqrt(4.0 / 9.0))
	# `vy` ist VORZEICHENBEHAFTET (Web: `timeToImpact(h, vy)`): im Fallen ist es
	# negativ und verkürzt die Restzeit. Mit gedrehtem Vorzeichen kam hier rund
	# 1 s heraus statt 1/9 s — dann liefert classify_landing_tap immer "ignore"
	# und der Boost wäre unerreichbar.
	assert_almost(Logic.time_to_impact(0.5, -4.0), 1.0 / 9.0)
	assert_true(
		Logic.time_to_impact(0.5, -4.0) < Logic.time_to_impact(0.5, 0.0),
		"im Fallen ist die Matte näher als im Scheitel"
	)
	assert_eq(
		Logic.classify_landing_tap(Logic.time_to_impact(0.5, -4.0), Logic.apex_for(5.0)),
		"boost",
		"ein normaler Fall erreicht das Boost-Fenster"
	)


func test_trick_gate_and_mat_crossing() -> void:
	assert_true(Logic.can_trick(true, 1.0, false))
	assert_false(Logic.can_trick(false, 1.0, false), "am Boden kein Trick")
	assert_false(Logic.can_trick(true, 0.2, false), "kurz vor der Matte kein Trick")
	assert_false(Logic.can_trick(true, 1.0, true), "kein Trick im Trick")
	assert_true(Logic.crossed_mat(0.2, -0.01, -3.0))
	assert_false(Logic.crossed_mat(0.2, 0.1, -3.0), "noch in der Luft")
	assert_false(Logic.crossed_mat(-0.1, -0.2, -3.0), "unter der Matte zählt nicht doppelt")
	assert_false(Logic.crossed_mat(0.2, -0.01, 3.0), "nur die fallende Flanke")
	# Eine scharfgestellte Landung wird genau einmal verbraucht.
	var consumed: Dictionary = Logic.consume_landing_action("boost")
	assert_eq(str(consumed["action"]), "boost")
	assert_eq(str(consumed["armed"]), "")
	assert_eq(str(Logic.consume_landing_action("")["action"]), "none")


func test_manifest_matches_web_metadata() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_true(file != null, "game.json fehlt")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert_eq(str(manifest["id"]), "trampoline")
	assert_eq(int(manifest["target"]), WEB_TARGET)
	assert_eq(str(manifest["orientation"]), "portrait")
	var coins: Dictionary = manifest["coin_table"]
	assert_eq(int(coins["divisor"]), 5)
	assert_eq(int(coins["min"]), 4)
	assert_eq(int(coins["max"]), 26)
	assert_true(ResourceLoader.exists(str(manifest["scene"])), "Szene fehlt")
