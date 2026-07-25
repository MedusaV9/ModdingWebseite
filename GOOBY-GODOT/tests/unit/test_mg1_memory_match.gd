extends TestCase
## Memory-Match (memoryMatch) — Logik-Parität zum Web (MG-1, Batch 1).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/memoryMatch.logic.js
## (simulateMemoryAutoplay) — sie sperren Score-Formel und Zeitbonus fest.

const Logic := preload("res://scripts/minigames/games/memory_match/memory_match_logic.gd")
const MANIFEST := "res://scripts/minigames/games/memory_match/game.json"

## Web-Goldwerte: simulateMemoryAutoplay(seed, mode).score für Seeds 1..8.
const GOLD := {
	"easy": [47, 47, 48, 48, 48, 48, 48, 48],
	"normal": [47, 45, 48, 47, 46, 48, 48, 48],
	"hard": [47, 44, 47, 47, 46, 48, 47, 47],
	"endless": [47, 44, 47, 47, 46, 48, 47, 47],
}
const WEB_TARGET := 40


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.MEMORY
	assert_eq(int(t["SCORE_BASE"]), 20)
	assert_eq(int(t["CLEAR_BONUS"]), 20)
	assert_eq(int(t["TIME_BONUS_MAX"]), 8)
	assert_almost(float(t["TIME_BONUS_STEP_SEC"]), 5.0)
	assert_almost(float(t["PAR_SEC_SMALL"]), 48.0)
	assert_almost(float(t["PAR_SEC_BIG"]), 85.0)
	assert_almost(float(t["REVEAL_SEC"]), 0.85)
	assert_almost(float(t["FLIP_SEC"]), 0.28)
	assert_eq(int(t["PEEK_EARN_MATCHES"]), 3)
	assert_almost(float(t["PEEK_SEC"]), 1.0)
	assert_eq(int(t["ENDLESS_MISS_FLIPS"]), 12)
	assert_eq(int(Logic.SMALL["pairs"]), 8)
	assert_eq(int(Logic.BIG["pairs"]), 12)
	assert_eq(int(Logic.BIG_LAYOUT_LEVEL), 6)
	assert_eq(Logic.FACE_KEYS.size(), 12)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(4, mode), Logic.simulate_autoplay(4, mode), mode)
	# Über 20 Seeds muss der Bot streuen — sonst wäre der RNG wirkungslos.
	var seen := {}
	for seed_value in range(1, 21):
		seen[int(Logic.simulate_autoplay(seed_value, "hard")["score"])] = true
	assert_true(seen.size() > 1, "Seeds streuen (%s)" % [seen.keys()])


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 21):
			sum += int(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = float(sum) / 20.0
	assert_true(means["easy"] >= means["normal"], "leicht ≥ normal (%s)" % means)
	assert_true(means["normal"] >= means["hard"], "normal ≥ schwer (%s)" % means)
	assert_true(means["easy"] > means["hard"], "leicht > schwer (%s)" % means)


func test_bot_scores_are_plausible() -> void:
	var best := 0
	for seed_value in range(1, 21):
		var score := int(Logic.simulate_autoplay(seed_value, "hard")["score"])
		assert_true(score > 0, "Schwer-Bot punktet (seed %d)" % seed_value)
		# 20 Basis + 8 Zeitbonus + 20 Board-Bonus ist die harte Obergrenze.
		assert_true(score <= 48, "Score bleibt unter der Formel-Decke (seed %d)" % seed_value)
		best = maxi(best, score)
	assert_true(best >= WEB_TARGET, "bester Schwer-Score %d < Ziel %d" % [best, WEB_TARGET])


func test_endless_ends_on_twelve_misses() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.MEMORY, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.endless_should_end(11, tune), "11 Fehlgriffe ketten weiter")
	assert_true(Logic.endless_should_end(12, tune), "12 Fehlgriffe beenden")
	assert_false(Logic.endless_should_end(99, Logic.MEMORY), "getaktet gibt es kein Limit")


func test_score_edges() -> void:
	# Perfektes kleines Board unter Par: 20 + 8 + 20.
	assert_eq(Logic.memory_score(0, 10.0, Logic.SMALL), 48)
	# Jeder Fehlgriff kostet genau 1 Punkt.
	assert_eq(Logic.memory_score(5, 10.0, Logic.SMALL), 43)
	# Weit über Par fällt der Zeitbonus auf 0, aber nie ins Minus.
	assert_eq(Logic.time_bonus(1000.0, Logic.SMALL), 0)
	assert_eq(Logic.memory_score(999, 1000.0, Logic.SMALL), 0)
	# Par-Grenzen: exakt am Par voller Bonus, 5 s darüber einer weniger.
	assert_eq(Logic.time_bonus(48.0, Logic.SMALL), 8)
	assert_eq(Logic.time_bonus(53.0, Logic.SMALL), 7)
	assert_eq(Logic.time_bonus(85.0, Logic.BIG), 8)
	assert_eq(Logic.time_bonus(90.0, Logic.BIG), 7)
	assert_true(Logic.is_match(3, 3))
	assert_false(Logic.is_match(3, 4))


func test_layout_deck_and_peek() -> void:
	assert_eq(Logic.layout_for_level(1), Logic.SMALL)
	assert_eq(Logic.layout_for_level(5), Logic.SMALL)
	assert_eq(Logic.layout_for_level(6), Logic.BIG, "ab Level 6 kommt 4×6")
	var deck: Array = Logic.build_deck(8, GoobyRng.new(2))
	assert_eq(deck.size(), 16)
	var counts := {}
	for id: int in deck:
		counts[id] = int(counts.get(id, 0)) + 1
	assert_eq(counts.size(), 8, "8 verschiedene Paar-Ids")
	for id: int in counts:
		assert_eq(int(counts[id]), 2, "Paar %d kommt zweimal" % id)
	assert_eq(deck, Logic.build_deck(8, GoobyRng.new(2)), "Deck ist seed-stabil")
	# Spick-Blick: nach 3 sauberen Treffern verdient, danach genau einmal.
	var state := {"cleanMatches": 0, "peekReady": false, "peekUsed": false}
	for _i in 3:
		state = Logic.advance_peek_progress(state, true)
	assert_true(bool(state["peekReady"]))
	assert_true(Logic.can_use_peek(state))
	state["peekUsed"] = true
	assert_false(Logic.can_use_peek(state), "nur ein Spick-Blick pro Runde")
	# Ein Fehlgriff setzt die saubere Serie zurück.
	var broken := Logic.advance_peek_progress(
		{"cleanMatches": 2, "peekReady": false, "peekUsed": false}, false
	)
	assert_eq(int(broken["cleanMatches"]), 0)


func test_flip_gate_closes_double_taps() -> void:
	var base := {"phase": "play", "peeking": false, "pickedCount": 0, "cardState": "down"}
	assert_true(Logic.can_flip_card(base))
	var two := base.duplicate()
	two["pickedCount"] = 2
	assert_false(Logic.can_flip_card(two), "eine dritte Karte geht nicht")
	var peeking := base.duplicate()
	peeking["peeking"] = true
	assert_false(Logic.can_flip_card(peeking))
	var up := base.duplicate()
	up["cardState"] = "up"
	assert_false(Logic.can_flip_card(up))


func test_manifest_matches_web_metadata() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_true(file != null, "game.json fehlt")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert_eq(str(manifest["id"]), "memoryMatch")
	assert_eq(int(manifest["target"]), WEB_TARGET)
	assert_eq(str(manifest["orientation"]), "portrait")
	var coins: Dictionary = manifest["coin_table"]
	assert_eq(int(coins["divisor"]), 2)
	assert_eq(int(coins["min"]), 5)
	assert_eq(int(coins["max"]), 24)
	assert_true(ResourceLoader.exists(str(manifest["scene"])), "Szene fehlt")
