extends TestCase
## Sternenhüpfer (starHopper) — Logik-Parität zum Web (MG-2, Batch 2).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/starHopper.logic.js.

const Logic := preload("res://scripts/minigames/games/star_hopper/star_hopper_logic.gd")
const Bot := preload("res://scripts/minigames/games/star_hopper/star_hopper_bot.gd")

## Web-Goldwerte: simulateHopperAutoplay(seed, mode).score für Seeds 1..5.
const GOLD := {
	"easy": [176, 183, 164, 191, 158],
	"normal": [173, 177, 164, 188, 158],
	"hard": [213, 138, 199, 214, 113],
	"endless": [305, 211, 315, 357, 189],
}

## Web: generateRow(mk(7), i*6, rows) — Blockmaske + Reihenabstand. Prüft, dass
## der GDScript-Stream GENAU so viele rng-Züge verbraucht wie V8s Array.sort.
const GOLD_ROWS := [
	["001", 27.014647],
	["100", 27.179028],
	["001", 23.346880],
	["011", 21.937536],
	["010", 23.068802],
	["100", 22.975608],
]


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.HOPPER
	assert_eq(int(t["LANES"]), 3)
	assert_eq(t["LANE_X"], [-1.15, 0.0, 1.15])
	assert_almost(float(t["DURATION_SEC"]), 75.0)
	assert_almost(float(t["BASE_SPEED"]), 11.0)
	assert_almost(float(t["SPEED_RAMP_PCT"]), 0.05)
	assert_almost(float(t["SPEED_RAMP_EVERY_SEC"]), 10.0)
	assert_almost(float(t["MAX_SPEED"]), 19.0)
	assert_almost(float(t["HITBOX_SCALE"]), 0.7)
	assert_almost(float(t["PLAYER_HALF_M"]), 3.2)
	assert_almost(float(t["METEOR_HALF_M"]), 3.4)
	assert_eq(int(t["STAR_POINTS"]), 3)
	assert_eq(int(t["GOLD_POINTS"]), 10)
	assert_eq(int(t["SHIELD_SCORE"]), 60)
	assert_almost(float(t["DISTANCE_PER_POINT_M"]), 10.0)
	assert_almost(float(t["LANE_CHANGE_SEC"]), 0.16)
	assert_almost(float(t["ROW_GAP_M"]["start"]), 27.0)
	assert_almost(float(t["ROW_GAP_M"]["end"]), 18.0)
	assert_almost(float(t["DIFFICULTY_FULL_SEC"]), 60.0)
	assert_almost(float(t["DOUBLE_BLOCK_CHANCE"]["start"]), 0.2)
	assert_almost(float(t["DOUBLE_BLOCK_CHANCE"]["end"]), 0.55)
	assert_almost(float(t["GOLD_CHANCE"]), 0.05)
	assert_almost(float(t["STAR_CHANCE"]), 0.38)
	assert_almost(float(t["SHOWER_EVERY_SEC"]), 14.0)
	assert_almost(float(t["SHOWER_TELEGRAPH_SEC"]), 1.3)
	assert_almost(float(t["SHOWER_DURATION_SEC"]), 2.2)
	assert_almost(float(t["SHOWER_DROP_EVERY_SEC"]), 0.35)
	assert_almost(float(t["SHOWER_METEOR_SPEED"]), 38.0)
	assert_almost(float(t["BOT_WINDOW_SEC"]), 0.4)
	assert_almost(float(t["MAX_SWEEP_STEP_M"]), 2.0)
	assert_almost(float(t["SHIELD_POP_INVULN_SEC"]), 1.2)
	assert_almost(float(t["WORMHOLE_FIRST_SEC"]), 18.0)
	assert_almost(float(t["WORMHOLE_CHANCE"]), 0.08)
	assert_almost(float(t["WORMHOLE_SEC"]), 2.0)
	assert_almost(float(t["WORMHOLE_TICK_SEC"]), 0.2)
	assert_eq(int(t["WORMHOLE_TICK_POINTS"]), 1)
	assert_almost(float(Logic.HOPPER_JUICE["BARREL_ROLL_SEC"]), 0.55)
	assert_almost(float(Logic.HOPPER_JUICE["POP_SEC"]), 0.28)
	assert_almost(float(Logic.HOPPER_JUICE["POP_SCALE"]), 1.13)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])
	# Detailwerte eines Laufs (Web: 67 Aufsammlerpunkte, 972.9564530898484 m).
	var run: Dictionary = Logic.simulate_autoplay(3, "normal")
	assert_eq(int(run["pickups"]), 67)
	assert_almost(float(run["distance"]), 972.9564530898484, 1e-9)


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(8, mode), Logic.simulate_autoplay(8, mode), mode)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 41):
			sum += int(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = float(sum) / 40.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)
	var easy: Dictionary = Logic.apply_difficulty(Logic.HOPPER, "easy")
	assert_almost(float(easy["SHOWER_EVERY_SEC"]), 16.47058823529412, 1e-12)
	assert_almost(float(easy["SHOWER_TELEGRAPH_SEC"]), 1.625)
	assert_almost(float(easy["BOT_WINDOW_SEC"]), 0.5)
	assert_eq(int(easy["RAMP_STEP_OFFSET"]), 0)
	assert_almost(float(easy["GOLD_CHANCE"]), 0.05)
	assert_almost(float(easy["MAX_SPEED"]), 19.0)
	var hard: Dictionary = Logic.apply_difficulty(Logic.HOPPER, "hard")
	assert_almost(float(hard["SHOWER_EVERY_SEC"]), 12.173913043478262, 1e-12)
	assert_almost(float(hard["SHOWER_TELEGRAPH_SEC"]), 1.04)
	assert_almost(float(hard["BOT_WINDOW_SEC"]), 0.35, 1e-12, "Boden 0.35 s")
	assert_eq(int(hard["RAMP_STEP_OFFSET"]), 1)
	assert_almost(float(hard["GOLD_CHANCE"]), 0.1, 1e-12, "§G5.4-Relax ×2")
	assert_eq(Logic.apply_difficulty(Logic.HOPPER, "unsinn"), Logic.HOPPER)


func test_hard_bot_reaches_target() -> void:
	# §G5.4-Ziel für starHopper ist 190 — der Schwer-Bot muss es packen können.
	var best := 0
	for seed_value in range(1, 21):
		best = maxi(best, int(Logic.simulate_autoplay(seed_value, "hard")["score"]))
	assert_true(best >= 190, "bester Schwer-Score %d < Ziel 190" % best)


func test_endless_uncaps_speed_and_terminates() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.HOPPER, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(is_finite(float(tune["MAX_SPEED"])), "Endlos hebt die Tempogrenze auf")
	assert_almost(float(tune["WORMHOLE_CHANCE"]), 0.04, 1e-12, "Wurmlöcher halb so oft")
	assert_true(Logic.speed_at(300.0, tune) > 19.0, "Rampe läuft weiter")
	assert_almost(Logic.speed_at(300.0, Logic.HOPPER), 19.0, 1e-9, "sonst gedeckelt")
	# Sternenhüpfer läuft bis zum Crash: der ungeschützte Treffer beendet.
	assert_true(Logic.endless_ended(Logic.resolve_hit(false)))
	assert_false(Logic.endless_ended(Logic.resolve_hit(true)), "Schild rettet einmal")
	for seed_value in range(1, 11):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "endless")
		assert_true(float(run["distance"]) > 0.0, "Endlos-Lauf terminiert (seed %d)" % seed_value)


func test_speed_gap_and_score_edges() -> void:
	assert_almost(Logic.speed_at(0.0), 11.0)
	assert_almost(Logic.speed_at(10.0), 11.55)
	assert_almost(Logic.speed_at(35.0), 12.733875000000001, 1e-12)
	assert_almost(Logic.speed_at(-9.0), 11.0, 1e-9, "unten gedeckelt")
	assert_almost(Logic.difficulty_at(0.0), 0.0)
	assert_almost(Logic.difficulty_at(30.0), 0.5)
	assert_almost(Logic.difficulty_at(90.0), 1.0, 1e-9, "gedeckelt")
	assert_almost(Logic.row_gap_at(0.0), 27.0)
	assert_almost(Logic.row_gap_at(0.5), 22.5)
	assert_almost(Logic.row_gap_at(1.0), 18.0)
	assert_eq(Logic.hopper_score(0.0, 0), 0)
	assert_eq(Logic.hopper_score(95.0, 0), 9, "Meter/10 wird abgerundet")
	assert_eq(Logic.hopper_score(1234.5, 17), 140)
	assert_eq(Logic.hopper_score(-50.0, 0), 0, "nie negativ")
	# Wurmloch-Ticks sind framerate-unabhängig.
	assert_eq(Logic.wormhole_awards(0.0, 0.2), 1)
	assert_eq(Logic.wormhole_awards(0.0, 2.0), 10)
	assert_eq(Logic.wormhole_awards(1.9, 5.0), 1, "über die Tunnellänge hinaus gedeckelt")
	assert_eq(Logic.wormhole_awards(0.05, 0.15), 0)


func test_lane_gestures_and_hitboxes() -> void:
	assert_eq(Logic.lane_after_tap(1, "left"), 0)
	assert_eq(Logic.lane_after_tap(0, "left"), 0, "Rand hält")
	assert_eq(Logic.lane_after_swipe(0, "right"), 2)
	assert_eq(Logic.lane_after_swipe(1, "right"), 2, "gedeckelt")
	assert_eq(Logic.lane_after_gesture(1, {"kind": "tap", "side": "right"}, true), 1)
	assert_eq(Logic.lane_after_gesture(1, {"kind": "tap", "side": "right"}, false), 2)
	assert_eq(Logic.lane_after_gesture(2, {"kind": "swipe", "dir": "left"}, true), 0)
	# Reichweite 0.7 × (3.2 + 3.4) = 4.62 m.
	assert_true(Logic.hits_meteor({"lane": 1, "m": 100.0}, {"lane": 1, "m": 104.6}))
	assert_false(Logic.hits_meteor({"lane": 1, "m": 100.0}, {"lane": 1, "m": 104.62}))
	assert_false(Logic.hits_meteor({"lane": 0, "m": 100.0}, {"lane": 1, "m": 100.0}))
	# Anti-Tunneling: 10 m Sprung darf den Meteor nicht überspringen.
	assert_true(Logic.sweep_hits_meteor({"lane": 1, "m": 90.0}, {"lane": 1, "m": 100.0}, 20.0))
	assert_false(Logic.hits_meteor({"lane": 1, "m": 90.0}, {"lane": 1, "m": 100.0}))


func test_pickup_shield_and_shower_streams() -> void:
	var r3 := GoobyRng.new(4)
	var stream3 := func() -> float: return r3.next()
	var kinds := PackedStringArray()
	for i in 6:
		var roll: Dictionary = Logic.roll_pickup(stream3, Logic.HOPPER)
		kinds.append("-" if roll.is_empty() else str(roll["kind"]))
	assert_eq(kinds, PackedStringArray(["star", "-", "star", "star", "-", "-"]))
	assert_eq(int(Logic.roll_pickup(func() -> float: return 0.01)["points"]), 10)
	assert_eq(int(Logic.roll_pickup(func() -> float: return 0.4)["points"]), 3)
	assert_true(Logic.roll_pickup(func() -> float: return 0.9).is_empty())
	# Das EINE Schild spawnt ab Score 60.
	assert_false(Logic.should_spawn_shield(59, false))
	assert_true(Logic.should_spawn_shield(60, false))
	assert_false(Logic.should_spawn_shield(99, true), "nur einmal pro Lauf")
	# Meteorschauer: immer 1 sichere + 2 gefährliche Bahnen.
	var r2 := GoobyRng.new(11)
	var stream2 := func() -> float: return r2.next()
	var safes := PackedInt32Array()
	for i in 4:
		var lanes: Dictionary = Logic.pick_shower_lanes(stream2)
		safes.append(int(lanes["safe"]))
		assert_eq((lanes["danger"] as Array).size(), 2)
		assert_false((lanes["danger"] as Array).has(lanes["safe"]))
	assert_eq(safes, PackedInt32Array([0, 0, 0, 1]))


func test_wormhole_gate() -> void:
	var always := func() -> float: return 0.0
	assert_false(Logic.should_spawn_wormhole(always, 17.9, false, false), "frühestens 18 s")
	assert_true(Logic.should_spawn_wormhole(always, 18.0, false, false))
	assert_false(Logic.should_spawn_wormhole(always, 40.0, true, false), "nur einmal")
	assert_false(Logic.should_spawn_wormhole(always, 40.0, false, true), "nicht doppelt")
	assert_false(Logic.should_spawn_wormhole(func() -> float: return 0.5, 40.0, false, false))


func test_row_generation_matches_web_stream() -> void:
	# Beweist die V8-Array.sort-Emulation in Bot.shuffled_lane_order: nur bei
	# gleicher rng-Zugzahl stimmen Maske UND Abstand mit dem Web überein.
	var rng := GoobyRng.new(7)
	var stream := func() -> float: return rng.next()
	var rows: Array[Dictionary] = []
	for i in GOLD_ROWS.size():
		var row: Dictionary = Bot.generate_row(stream, i * 6.0, rows)
		rows.append(row)
		var mask := ""
		for b: bool in row["blocked"]:
			mask += "1" if b else "0"
		assert_eq(mask, str((GOLD_ROWS[i] as Array)[0]), "Reihe %d Maske" % i)
		assert_almost(float(row["gap"]), float((GOLD_ROWS[i] as Array)[1]), 1e-6, "Reihe %d" % i)


func test_every_generated_row_is_survivable() -> void:
	# §C1.5: keine Reihe darf alle drei Bahnen sperren, und die Kette bleibt
	# über den 4-Reihen-Ausblick erreichbar.
	for seed_value in range(1, 13):
		var rng := GoobyRng.new(seed_value)
		var stream := func() -> float: return rng.next()
		var rows: Array[Dictionary] = []
		for i in 40:
			var elapsed := i * 1.7
			var row: Dictionary = Bot.generate_row(stream, elapsed, rows)
			rows.append(row)
			if rows.size() > 4:
				rows.pop_front()
			var open := 0
			for b: bool in row["blocked"]:
				if not b:
					open += 1
			assert_true(open >= 1, "Reihe %d/seed %d ohne Lücke" % [i, seed_value])
			assert_true(
				Bot.is_chain_survivable(rows, Logic.speed_at(elapsed)),
				"Kette bei seed %d nicht überlebbar" % seed_value
			)


func test_bot_lane_choice_matches_web() -> void:
	assert_eq(Bot.max_lane_shift(27.0, 11.0), 2)
	assert_eq(Bot.max_lane_shift(18.0, 19.0), 2)
	assert_eq(Bot.max_lane_shift(5.0, 19.0), 0)
	assert_eq(Bot.max_lane_shift(100.0, 11.0), 2, "auf LANES-1 gedeckelt")
	var lanes := [
		{"safe": true, "value": 1.0, "transitSafe": false, "enter": 1.0},
		{"safe": false, "value": 5.0, "transitSafe": false, "enter": 0.2},
		{"safe": true, "value": 9.0, "transitSafe": true, "enter": 9.0},
	]
	assert_eq(Bot.choose_lane(0, lanes), 2)
	assert_eq(Bot.plan_move(0, lanes), 0, "sichere Bahn halten statt schmutzig kreuzen")
	var blocked := [
		{"safe": false, "value": 1.0, "transitSafe": false, "enter": 1.0},
		{"safe": false, "value": 5.0, "transitSafe": false, "enter": 2.0},
		{"safe": true, "value": 9.0, "transitSafe": false, "enter": 9.0},
	]
	assert_eq(Bot.choose_lane(0, blocked), 2)
	assert_eq(Bot.plan_move(0, blocked), 1, "Panik: in die Bahn mit mehr Restzeit")
	var none := [
		{"safe": false, "value": 0.0},
		{"safe": false, "value": 0.0},
		{"safe": false, "value": 0.0},
	]
	assert_eq(Bot.choose_lane(1, none), 1, "keine sichere Bahn = Bahn halten")
	# Gleichstand bevorzugt die aktuelle Bahn.
	var tie := [
		{"safe": true, "value": 4.0, "transitSafe": true, "enter": 9.0},
		{"safe": true, "value": 4.0, "transitSafe": true, "enter": 9.0},
		{"safe": true, "value": 4.0, "transitSafe": true, "enter": 9.0},
	]
	assert_eq(Bot.choose_lane(1, tie), 1)


func test_lane_outlook_matches_web() -> void:
	var threats := [
		{"lane": 0, "m": 120.0, "approach": 11.0},
		{"lane": 2, "m": 200.0, "approach": 11.0},
	]
	var out: Dictionary = Bot.lane_outlook(threats, 100.0, 3.0, 1.0)
	assert_eq(out["safe"], [false, true, true])
	assert_eq(out["transit"], [true, true, true])
	assert_almost(float((out["enter"] as Array)[0]), 1.3981818181818182, 1e-12)
	assert_almost(float((out["enter"] as Array)[2]), 8.67090909090909, 1e-12)
	assert_false(is_finite(float((out["enter"] as Array)[1])), "freie Bahn = unendlich")


func test_runtime_modifiers_clamp() -> void:
	var boosted: Dictionary = Logic.with_runtime(Logic.HOPPER, {"coinRate": 4.0})
	assert_almost(float(boosted["STAR_CHANCE"]), 0.95, 1e-12, "Deckel 0.95")
	assert_almost(float(boosted["GOLD_CHANCE"]), 0.2, 1e-12, "Deckel 0.2")
	var junk: Dictionary = Logic.with_runtime(Logic.HOPPER, {"speedMult": -3.0, "scoreMult": 0.0})
	assert_almost(float(junk["SPEED_MULT"]), 1.0)
	assert_almost(float(junk["SCORE_MULT"]), 1.0)
	var big: Dictionary = Logic.with_runtime(Logic.HOPPER, {"hitboxMult": 1.5, "goobyScale": 1.6})
	assert_almost(float(big["HITBOX_SCALE"]), 1.05, 1e-12)
	assert_almost(float(big["GOOBY_SCALE"]), 1.6)
	assert_eq(
		Logic.hopper_score(1000.0, 0, Logic.with_runtime(Logic.HOPPER, {"scoreMult": 2.0})), 200
	)
