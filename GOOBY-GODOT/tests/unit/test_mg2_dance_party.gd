extends TestCase
## Tanzparty (danceParty) — Logik-Parität zum Web (MG-2, Batch 2).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/danceParty.logic.js.

const Logic := preload("res://scripts/minigames/games/dance_party/dance_party_logic.gd")

## Web-Goldwerte: simulateDanceAutoplay(seed, mode).score für Seeds 1..5.
const GOLD := {
	"easy": [214, 218, 186, 204, 196],
	"normal": [212, 218, 152, 228, 182],
	"hard": [208, 206, 140, 192, 172],
	"endless": [208, 206, 140, 192, 172],
}

## Web: generatePattern() — die ersten sechs Noten als [Zeit, Bahn].
const GOLD_HEAD := [
	[7.199999999999999, 0],
	[7.8, 0],
	[8.4, 0],
	[9.0, 1],
	[9.6, 1],
	[10.2, 0],
]


func test_constants_match_web() -> void:
	var d: Dictionary = Logic.DANCE
	assert_almost(float(d["BPM"]), 100.0)
	assert_eq(int(d["PATTERN_SEED"]), 1002026)
	assert_almost(float(d["DURATION_SEC"]), 75.0)
	assert_eq(int(d["LANES"]), 3)
	assert_almost(float(d["PERFECT_MS"]), 70.0)
	assert_almost(float(d["GOOD_MS"]), 140.0)
	assert_eq(int(d["PERFECT_PTS"]), 4)
	assert_eq(int(d["GOOD_PTS"]), 2)
	assert_eq(int(d["MISS_PENALTY"]), 2)
	var t: Dictionary = Logic.DANCE_TUNING
	assert_almost(float(t["LEAD_IN_SEC"]), 2.4)
	assert_almost(float(t["NOTE_TRAVEL_SEC"]), 1.6)
	assert_eq(int(t["SLOTS_PER_BEAT"]), 2)
	assert_almost(float(t["MIN_GAP_SEC"]), 0.3)
	assert_almost(float(t["LANE_GAP_SEC"]), 0.6)
	assert_almost(float(t["DENSITY_START"]), 0.3)
	assert_almost(float(t["DENSITY_END"]), 0.55)
	assert_almost(float(t["OFFBEAT_MULT"]), 0.5)
	assert_eq(int(t["START_BEAT"]), 4)
	assert_almost(float(t["TAIL_SEC"]), 2.0)
	assert_almost(float(t["LANE_REPEAT_CHANCE"]), 0.3)
	assert_eq(t["TIER_COMBOS"], [4, 8, 16])
	assert_eq(int(t["ENCORE_PERFECTS"]), 5)
	assert_almost(float(t["ENCORE_SEC"]), 5.0)
	assert_eq(int(t["ENDLESS_BREAK_LIMIT"]), 3)
	assert_almost(float(Logic.DANCE_JUICE["BURST_LIFE_SEC"]), 0.32)
	assert_almost(float(Logic.DANCE_JUICE["BALL_SPIN_BASE"]), 0.9)


func test_pattern_matches_web_chart() -> void:
	var notes := Logic.generate_pattern()
	assert_eq(notes.size(), 78, "78 Noten im Standard-Chart")
	for i in GOLD_HEAD.size():
		var want: Array = GOLD_HEAD[i]
		assert_almost(float(notes[i]["time"]), float(want[0]), 1e-12, "Note %d Zeit" % i)
		assert_eq(int(notes[i]["lane"]), int(want[1]), "Note %d Bahn" % i)
	var last: Dictionary = notes[notes.size() - 1]
	assert_almost(float(last["time"]), 72.3, 1e-12)
	assert_eq(int(last["lane"]), 1)
	# Abstandsregeln (§C6.1): global ≥ 0.3 s, je Bahn ≥ 0.6 s.
	var last_lane_time := [-INF, -INF, -INF]
	var previous := -INF
	for n in notes:
		var time := float(n["time"])
		assert_true(time - previous >= 0.3 - 1e-9, "Mindestabstand bei %f" % time)
		assert_true(
			time - float(last_lane_time[int(n["lane"])]) >= 0.6 - 1e-9, "Bahnabstand bei %f" % time
		)
		previous = time
		last_lane_time[int(n["lane"])] = time
	assert_eq(Logic.generate_pattern(), notes, "gleicher Seed = gleiches Chart")


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])
	var run: Dictionary = Logic.simulate_autoplay(3, "normal")
	var tally: Dictionary = run["tally"]
	assert_eq(int(tally["perfect"]), 36)
	assert_eq(int(tally["good"]), 23)
	assert_eq(int(tally["miss"]), 19)
	assert_eq(int(tally["maxCombo"]), 14)


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(
			Logic.simulate_autoplay(7, mode)["score"],
			Logic.simulate_autoplay(7, mode)["score"],
			mode
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
	var easy: Dictionary = Logic.apply_difficulty(Logic.DANCE_TUNING, "easy")
	assert_almost(float(easy["DENSITY_START"]), 0.255, 1e-12)
	assert_almost(float(easy["DENSITY_END"]), 0.4675, 1e-12)
	assert_almost(float(easy["NOTE_TRAVEL_SEC"]), 1.8823529411764708, 1e-12)
	assert_almost(float(easy["PERFECT_MS"]), 87.5)
	assert_almost(float(easy["GOOD_MS"]), 175.0)
	assert_eq(int(easy["RAMP_FLOOR_STEP"]), 0)
	var hard: Dictionary = Logic.apply_difficulty(Logic.DANCE_TUNING, "hard")
	assert_almost(float(hard["DENSITY_START"]), 0.345, 1e-12)
	assert_almost(float(hard["NOTE_TRAVEL_SEC"]), 1.3913043478260871, 1e-12)
	assert_almost(float(hard["PERFECT_MS"]), 56.0)
	assert_almost(float(hard["GOOD_MS"]), 112.0)
	assert_eq(int(hard["RAMP_FLOOR_STEP"]), -1)
	assert_eq(Logic.apply_difficulty(Logic.DANCE_TUNING, "unsinn"), Logic.DANCE_TUNING)
	# Dichte wirkt sich direkt auf die Notenzahl aus.
	assert_eq(Logic.generate_pattern(1002026, hard).size(), 89)
	assert_eq(Logic.generate_pattern(1002026, easy).size(), 65)


func test_hard_bot_reaches_target() -> void:
	# §G5.4-Ziel für danceParty ist 140.
	for seed_value in range(1, 6):
		var score: int = int(Logic.simulate_autoplay(seed_value, "hard")["score"])
		assert_true(score >= 140, "Schwer-Score %d < Ziel 140 (seed %d)" % [score, seed_value])


func test_endless_ends_after_three_broken_sections() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.DANCE_TUNING, "endless")
	assert_true(bool(tune["ENDLESS"]))
	var state: Dictionary = Logic.create_endless_state()
	assert_false(Logic.record_section(state, false))
	assert_false(Logic.record_section(state, true))
	assert_false(Logic.record_section(state, true))
	assert_true(Logic.record_section(state, true))
	assert_eq(int(state["breaks"]), 3)
	assert_true(bool(state["ended"]))
	# Abschnitte sind 12-Sekunden-Blöcke, Segment-Seeds folgen dem Web.
	assert_eq(Logic.section_index(0.0), 0)
	assert_eq(Logic.section_index(11.9), 0)
	assert_eq(Logic.section_index(12.0), 1)
	assert_eq(Logic.section_index(37.5), 3)
	assert_eq(Logic.segment_seed(0), 1002026)
	assert_eq(Logic.segment_seed(1), 2655437787)
	assert_eq(Logic.segment_seed(2), 1014906252)
	assert_eq(Logic.segment_seed(3), 3669342013)


func test_judgment_windows_and_score_edges() -> void:
	assert_eq(Logic.classify_hit(0.07), "perfect")
	assert_eq(Logic.classify_hit(0.0701), "good")
	assert_eq(Logic.classify_hit(0.14), "good")
	assert_eq(Logic.classify_hit(0.1401), "")
	assert_eq(Logic.classify_hit(-0.05), "perfect", "Vorzeichen egal")
	var tally: Dictionary = Logic.create_tally()
	Logic.apply_judgment(tally, "perfect")
	Logic.apply_judgment(tally, "good")
	Logic.apply_judgment(tally, "miss")
	Logic.apply_judgment(tally, "perfect")
	assert_eq(int(tally["perfect"]), 2)
	assert_eq(int(tally["good"]), 1)
	assert_eq(int(tally["miss"]), 1)
	assert_eq(int(tally["combo"]), 1, "Fehler setzt die Serie zurück")
	assert_eq(int(tally["maxCombo"]), 2)
	assert_eq(Logic.dance_score(tally), 8)
	var only_misses: Dictionary = Logic.create_tally()
	for i in 9:
		Logic.apply_judgment(only_misses, "miss")
	assert_eq(Logic.dance_score(only_misses), 0, "nie negativ")
	assert_eq(Logic.combo_tier(0), 0)
	assert_eq(Logic.combo_tier(3), 0)
	assert_eq(Logic.combo_tier(4), 1)
	assert_eq(Logic.combo_tier(8), 2)
	assert_eq(Logic.combo_tier(16), 3)
	assert_eq(Logic.combo_tier(99), 3)


func test_fever_chain_and_encore() -> void:
	var chain: Dictionary = Logic.create_fever_chain()
	for i in 4:
		var step: Dictionary = Logic.advance_fever_chain(chain, "perfect", 20, 10.0 + i * 0.1)
		assert_false(bool(step["active"]), "Zugabe erst beim fünften Perfekten")
	var started: Dictionary = Logic.advance_fever_chain(chain, "perfect", 20, 10.4)
	assert_true(bool(started["started"]))
	assert_almost(float(chain["encoreUntil"]), 15.4)
	assert_eq(int(chain["encores"]), 1)
	# Eine laufende Zugabe kann sich nicht selbst nachtriggern.
	var again: Dictionary = Logic.advance_fever_chain(chain, "perfect", 20, 10.5)
	assert_true(bool(again["active"]))
	assert_false(bool(again["started"]))
	assert_true(Logic.encore_active(chain, 15.39))
	assert_false(Logic.encore_active(chain, 15.4))
	# Unter Fieberstufe 3 sammelt die Kette nicht.
	var low: Dictionary = Logic.create_fever_chain()
	for i in 9:
		Logic.advance_fever_chain(low, "perfect", 5, 1.0 + i)
	assert_eq(int(low["encores"]), 0)
	assert_eq(Logic.encore_bonus("perfect", true), 4)
	assert_eq(Logic.encore_bonus("good", true), 2)
	assert_eq(Logic.encore_bonus("miss", true), 0)
	assert_eq(Logic.encore_bonus("perfect", false), 0)


func test_tap_judging_and_lifecycle() -> void:
	var notes: Array[Dictionary] = [
		{"time": 1.0, "lane": 0}, {"time": 1.1, "lane": 1}, {"time": 1.3, "lane": 0}
	]
	assert_eq(Logic.judge_tap(notes, 0, 1.05), 0)
	assert_eq(Logic.judge_tap(notes, 0, 1.25), 2)
	assert_eq(Logic.judge_tap(notes, 2, 1.0), -1, "leere Bahn")
	assert_eq(Logic.judge_tap(notes, 1, 1.5), -1, "außerhalb des Fensters")
	notes[0]["hit"] = true
	assert_eq(Logic.judge_tap(notes, 0, 1.02), -1, "getroffene Noten sind tabu")
	assert_eq(Logic.note_lifecycle(10.0, 8.0), "future")
	assert_eq(Logic.note_lifecycle(10.0, 8.5), "visible")
	assert_eq(Logic.note_lifecycle(10.0, 10.15), "expired")
	# Hitbox-Modifier verbreitert nur die Fenster.
	var wide: Dictionary = Logic.with_hitbox(Logic.DANCE_TUNING, 1.5)
	assert_almost(float(wide["PERFECT_MS"]), 105.0)
	assert_almost(float(wide["GOOD_MS"]), 210.0)
	assert_eq(Logic.with_hitbox(Logic.DANCE_TUNING, 1.0), Logic.DANCE_TUNING)
	assert_eq(Logic.with_hitbox(Logic.DANCE_TUNING, -2.0), Logic.DANCE_TUNING)
