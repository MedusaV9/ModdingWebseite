extends TestCase
## Blasen-Platzer (bubblePop) — Logik-Parität zum Web (MG-1, Batch 1).
## Die Goldwerte stammen aus `node` auf
## GOOBY/src/minigames/games/bubblePop.logic.js (simulateBubbleAutoplay) und
## beweisen, dass der GDScript-Port zahlengleich rechnet.

const Logic := preload("res://scripts/minigames/games/bubble_pop/bubble_pop_logic.gd")
const MANIFEST := "res://scripts/minigames/games/bubble_pop/game.json"

## Web-Goldwerte: simulateBubbleAutoplay(seed, mode).score für Seeds 1..8.
const GOLD := {
	"easy": [82, 96, 104, 108, 98, 104, 84, 108],
	"normal": [82, 96, 104, 108, 98, 104, 84, 108],
	"hard": [76, 96, 84, 92, 88, 112, 80, 92],
	"endless": [154, 156, 146, 154, 178, 186, 148, 170],
}
## §C6.1 #11 Ziel aus GOOBY/src/data/minigames.js.
const WEB_TARGET := 80


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.BUBBLE
	assert_almost(float(t["DURATION_SEC"]), 60.0)
	assert_almost(float(t["TARGET_ROTATE_SEC"]), 12.0)
	assert_eq(int(t["MATCH_PTS"]), 2)
	assert_eq(int(t["WRONG_PTS"]), -2)
	assert_eq(int(t["SPIKY_PTS"]), -1)
	assert_almost(float(t["STUN_SEC"]), 0.5)
	assert_almost(float(t["RISE_START"]), 0.62)
	assert_almost(float(t["RISE_END"]), 1.1)
	assert_almost(float(t["SPAWN_SEC_START"]), 0.9)
	assert_almost(float(t["SPAWN_SEC_END"]), 0.5)
	assert_almost(float(t["TARGET_CHANCE"]), 0.52)
	assert_almost(float(t["SPIKY_CHANCE"]), 0.15)
	assert_eq(int(t["CHAIN_COUNT"]), 3)
	assert_almost(float(t["CHAIN_WINDOW_SEC"]), 2.0)
	assert_almost(float(t["CHAIN_RADIUS"]), 1.25)
	assert_eq(int(t["ENDLESS_SPIKY_LIMIT"]), 3)
	assert_eq(Logic.FOODS.size(), 6)
	assert_eq(str(Logic.FOODS[0]), "carrot")


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(7, mode), Logic.simulate_autoplay(7, mode), mode)
		assert_ne(
			int(Logic.simulate_autoplay(7, mode)["score"]),
			int(Logic.simulate_autoplay(8, mode)["score"]),
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
		var score := int(Logic.simulate_autoplay(seed_value, "hard")["score"])
		assert_true(score > 0, "Schwer-Bot punktet (seed %d)" % seed_value)
		assert_true(score < 400, "Schwer-Bot bleibt plausibel (seed %d: %d)" % [seed_value, score])
		best = maxi(best, score)
	assert_true(best >= WEB_TARGET, "bester Schwer-Score %d < Ziel %d" % [best, WEB_TARGET])


func test_endless_ends_on_three_spiky_pops() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.BUBBLE, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.endless_should_end(2, tune), "2 Stachelblasen beenden nicht")
	assert_true(Logic.endless_should_end(3, tune), "3 Stachelblasen beenden")
	assert_false(Logic.endless_should_end(9, Logic.BUBBLE), "getaktet gibt es kein Limit")
	# Jeder Endlos-Lauf endet am Stachel-Limit ODER am 90-s-Sicherheitsnetz des
	# Bots — und terminiert immer, ohne das Limit zu überschreiten.
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "endless")
		assert_true(int(run["spikyPops"]) <= 3, "Endlos stoppt am Limit (seed %d)" % seed_value)
		var endless_score := int(run["score"])
		var timed_score := int(Logic.simulate_autoplay(seed_value, "normal")["score"])
		assert_true(endless_score > timed_score, "Endlos läuft länger (seed %d)" % seed_value)


func test_score_edges() -> void:
	assert_eq(int(Logic.pop_result({"kind": "food", "food": "apple"}, "apple")["delta"]), 2)
	assert_true(bool(Logic.pop_result({"kind": "food", "food": "apple"}, "apple")["pops"]))
	var wrong: Dictionary = Logic.pop_result({"kind": "food", "food": "apple"}, "carrot")
	assert_eq(int(wrong["delta"]), -2)
	assert_almost(float(wrong["stunSec"]), 0.5)
	var spiky: Dictionary = Logic.pop_result({"kind": "spiky", "food": ""}, "carrot")
	assert_eq(int(spiky["delta"]), -1)
	assert_false(bool(spiky["pops"]), "Stachelblasen platzen nie")
	# Score ist bei 0 gefloort — zwei Fehltipps aus dem Stand bleiben 0.
	assert_eq(Logic.apply_score(Logic.apply_score(0, -2), -2), 0)
	assert_eq(Logic.apply_score(3, -2), 1)
	assert_almost(Logic.touch_radius_for("spiky"), 0.6)
	assert_almost(Logic.touch_radius_for("food"), 0.42)


func test_chain_and_ramps() -> void:
	var chain: Dictionary = Logic.create_pop_chain()
	assert_false(bool(Logic.record_pop_chain(chain, "apple", 0.0)["triggered"]))
	assert_false(bool(Logic.record_pop_chain(chain, "apple", 0.5)["triggered"]))
	assert_true(bool(Logic.record_pop_chain(chain, "apple", 1.0)["triggered"]), "3 in 2 s zünden")
	# Zu spät: das Fenster ist zu, die Kette beginnt von vorn.
	assert_false(bool(Logic.record_pop_chain(chain, "apple", 9.0)["triggered"]))
	assert_almost(Logic.rise_speed_at(0.0), 0.62)
	assert_almost(Logic.rise_speed_at(60.0), 1.1)
	assert_almost(Logic.spawn_interval_at(0.0), 0.9)
	assert_almost(Logic.spawn_interval_at(60.0), 0.5)
	assert_eq(Logic.target_index_at(0.0), 0)
	assert_eq(Logic.target_index_at(11.9), 0)
	assert_eq(Logic.target_index_at(12.0), 1)
	# Die Zielreihenfolge wiederholt nie zweimal dasselbe Essen hintereinander.
	var order: Array = Logic.target_order(GoobyRng.new(3), 24)
	for i in range(1, order.size()):
		assert_ne(str(order[i]), str(order[i - 1]), "Ziel %d wiederholt sich" % i)


func test_manifest_matches_web_metadata() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_true(file != null, "game.json fehlt")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert_eq(str(manifest["id"]), "bubblePop")
	assert_eq(str(manifest["title_key"]), "mg.bubblePop.title")
	assert_eq(int(manifest["target"]), WEB_TARGET)
	assert_eq(str(manifest["orientation"]), "portrait")
	assert_true(bool(manifest["supports_endless"]))
	var coins: Dictionary = manifest["coin_table"]
	assert_eq(int(coins["divisor"]), 4)
	assert_eq(int(coins["min"]), 4)
	assert_eq(int(coins["max"]), 24)
	assert_true(ResourceLoader.exists(str(manifest["scene"])), "Szene fehlt")
