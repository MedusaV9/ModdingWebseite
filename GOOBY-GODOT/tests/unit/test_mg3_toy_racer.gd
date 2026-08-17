extends TestCase
## Spielzeug-Rennen — Logik-Parität zum Web (MG-3, Batch 3).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/toyRacer.logic.js.

const Logic := preload("res://scripts/minigames/games/toy_racer/toy_racer_logic.gd")
const Track := preload("res://scripts/minigames/games/toy_racer/toy_racer_track.gd")

## Web: simulateRacerAutoplay(mode, seed) für Seeds 1..5.
const GOLD_SCORE := {
	"easy": [170, 170, 158, 170, 158],
	"normal": [170, 170, 158, 170, 158],
	"hard": [167, 166, 154, 166, 155],
	"endless": [970, 1220, 826, 890, 1089],
}
const GOLD_RANK := {
	"easy": [1, 1, 1, 1, 1],
	"normal": [1, 1, 1, 1, 1],
	"hard": [1, 1, 1, 1, 1],
	"endless": [3, 3, 3, 4, 3],
}
const GOLD_RACES := {
	"easy": [1, 1, 1, 1, 1],
	"normal": [1, 1, 1, 1, 1],
	"hard": [1, 1, 1, 1, 1],
	"endless": [6, 8, 6, 6, 8],
}
const GOLD_WINS := {
	"easy": [1, 1, 1, 1, 1],
	"normal": [1, 1, 1, 1, 1],
	"hard": [1, 1, 1, 1, 1],
	"endless": [5, 5, 4, 4, 4],
}
const GOLD_OVERTAKES := {
	"easy": [3, 3, 3, 3, 3],
	"normal": [3, 3, 3, 3, 3],
	"hard": [3, 3, 3, 3, 3],
	"endless": [16, 4, 5, 8, 3],
}
const GOLD_DRIFT := {
	"easy": [442.804140383, 444.117779934, 323.141811378, 444.07513131, 323.143889265],
	"normal": [444.10189904, 441.635563618, 323.145896288, 444.044139076, 323.005729769],
	"hard": [412.383298185, 401.220271341, 285.767746849, 408.92019576, 292.469674329],
	"endless": [412.913496583, 407.551573422, 286.534122294, 397.701111687, 284.934614599],
}
const GOLD_TIME := {
	"easy": [152.066666667, 149.733333333, 146.8, 149.5, 144.833333333],
	"normal": [126.866666667, 129.0, 122.3, 126.5, 122.633333333],
	"hard": [106.0, 106.766666667, 103.966666667, 105.866666667, 103.033333333],
	"endless": [642.2, 857.033333333, 628.033333333, 643.4, 843.2],
}
## Web: Mittelwert über Seeds 1..30.
const GOLD_MEAN := {
	"easy": 162.53333333333333,
	"normal": 162.46666666666667,
	"hard": 159.63333333333333,
}


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.RACER
	assert_eq(int(t["LAPS"]), 3)
	assert_eq(int(t["KARTS"]), 4)
	assert_eq(int(t["PIECES_PER_LOOP"]), 8)
	assert_almost(float(t["TRACK_HALF_W"]), 0.5)
	assert_almost(float(t["LAT_MAX"]), 0.36)
	assert_almost(float(t["LAT_HARD_MAX"]), 0.78)
	assert_almost(float(t["TARGET_LAP_SEC"]), 47.0)
	assert_almost(float(t["MAX_RACE_SEC"]), 240.0)
	assert_almost(float(t["WORLD_SCALE"]), 2.6)
	assert_almost(float(t["STEER_RATE"]), 1.1)
	assert_almost(float(t["DRIFT_STEER_MULT"]), 1.6)
	assert_almost(float(t["SLIP_GAIN"]), 0.5)
	assert_almost(float(t["DRIFT_SLIP_MULT"]), 0.25)
	assert_almost(float(t["DRIFT_BOOST_SEC"]), 1.2)
	assert_almost(float(t["DRIFT_BOOST_MULT"]), 1.45)
	assert_almost(float(t["DRIFT_MIN_CHARGE"]), 0.35)
	assert_almost(float(t["DRIFT_CHARGE_RATE_CURVE"]), 0.55)
	assert_almost(float(t["DRIFT_CHARGE_RATE_STRAIGHT"]), 0.12)
	assert_almost(float(t["DRIFT_MIN_KAPPA"]), 0.12)
	assert_almost(float(t["OFFTRACK_MULT"]), 0.6)
	assert_eq(int(t["ITEM_ROWS_PER_LAP"]), 3)
	assert_true(t["ITEM_ROW_FRACTIONS"] == [0.18, 0.5, 0.82])
	assert_true(t["ITEM_BOX_LATS"] == [-0.3, 0.0, 0.3])
	assert_almost(float(t["ITEM_RESPAWN_SEC"]), 2.5)
	assert_almost(float(t["PICKUP_S_WINDOW"]), 0.35)
	assert_almost(float(t["PICKUP_LAT_WINDOW"]), 0.24)
	assert_true(t["ITEM_KINDS"] == ["turbo", "shield", "block"])
	assert_true(t["ITEM_WEIGHTS"] == [0.4, 0.3, 0.3])
	assert_almost(float(t["TURBO_SEC"]), 2.0)
	assert_almost(float(t["TURBO_MULT"]), 1.5)
	assert_almost(float(t["BLOCK_DROP_BEHIND"]), 0.8)
	assert_almost(float(t["BLOCK_STUN_SEC"]), 0.9)
	assert_almost(float(t["BLOCK_STUN_MULT"]), 0.25)
	assert_almost(float(t["BLOCK_HIT_S"]), 0.28)
	assert_almost(float(t["BLOCK_HIT_LAT"]), 0.22)
	assert_eq(int(t["MAX_BLOCKS"]), 6)
	assert_almost(float(t["RUBBER_DIST"]), 6.0)
	assert_almost(float(t["RUBBER_GAIN"]), 0.1)
	assert_almost(float(t["RUBBER_MIN"]), 0.88)
	assert_almost(float(t["RUBBER_MAX"]), 1.12)
	assert_almost(float(t["AI_SPREAD"]), 0.04)
	assert_almost(float(t["ACCEL_RATE"]), 2.0)
	assert_almost(float(t["BRAKE_RATE"]), 5.0)
	assert_true(t["POSITION_BONUS"] == [120, 80, 50, 30])
	assert_eq(int(t["OVERTAKE_POINTS"]), 2)
	assert_almost(float(t["DRIFT_METERS_DIV"]), 10.0)
	assert_almost(float(t["OVERTAKE_COOLDOWN_SEC"]), 1.5)
	assert_almost(float(t["BOT_DRIFT_MIN_DEG"]), 45.0)
	assert_almost(float(t["BOT_CORNER_LOOKAHEAD"]), 1.0)
	assert_almost(float(t["SAMPLE_STEP"]), 0.25)
	assert_almost(float(t["GRID_GAP"]), 0.85)
	assert_almost(float(t["MAX_SUBSTEP"]), 1.0 / 30.0)
	assert_eq(int(t["ENDLESS_CHAIN_MAX_RANK"]), 2)
	assert_almost(float(t["ENDLESS_CHAIN_EDGE_STEP"]), 0.02)
	assert_almost(float(t["BOT_LAPSE_SEC"]), 1.6)
	assert_almost(float(Logic.RACER_JUICE["BOOST_FLASH_SEC"]), 0.4)
	# Genau zwei Layout-Vorlagen mit je 8 Teilen.
	assert_eq(Track.TEMPLATES.size(), 2)
	for tpl: Dictionary in Track.TEMPLATES:
		assert_eq((tpl["pieces"] as Array).size(), int(t["PIECES_PER_LOOP"]))


func test_difficulty_rows_match_web() -> void:
	assert_true(Logic.apply_difficulty(Logic.RACER, "normal") == Logic.RACER)
	assert_true(Logic.apply_difficulty(Logic.RACER, "quatsch") == Logic.RACER)
	var easy := Logic.apply_difficulty(Logic.RACER, "easy")
	assert_almost(float(easy["TARGET_LAP_SEC"]), 47.0 / 0.85)
	assert_almost(float(easy["AI_SPREAD"]), 0.08)
	assert_almost(float(easy["AI_EDGE"]), -0.02)
	assert_almost(float(easy["RUBBER_MIN"]), 0.85)
	assert_almost(float(easy["RUBBER_MAX"]), 1.08)
	assert_almost(float(easy["SPEED_MULT"]), 0.85)
	assert_false(bool(easy["ENDLESS"]))
	var hard := Logic.apply_difficulty(Logic.RACER, "hard")
	assert_almost(float(hard["TARGET_LAP_SEC"]), 47.0 / 1.2)
	assert_almost(float(hard["AI_SPREAD"]), 0.022)
	assert_almost(float(hard["AI_EDGE"]), 0.015)
	assert_almost(float(hard["BOT_LAPSE_EVERY_SEC"]), 18.0)
	assert_false(bool(hard["ENDLESS"]))
	var endless := Logic.apply_difficulty(Logic.RACER, "endless")
	assert_true(bool(endless["ENDLESS"]))
	# Schwer ist schneller als Leicht — kürzere Zielrundenzeit.
	assert_true(float(hard["TARGET_LAP_SEC"]) < float(easy["TARGET_LAP_SEC"]))


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD_SCORE:
		var scores: Array = GOLD_SCORE[mode]
		for i in scores.size():
			var run: Dictionary = Logic.simulate_autoplay(mode, i + 1)
			var tag := "%s seed %d" % [mode, i + 1]
			assert_eq(int(run["score"]), int(scores[i]), tag + " score")
			assert_eq(int(run["rank"]), int(GOLD_RANK[mode][i]), tag + " rank")
			assert_eq(int(run["races"]), int(GOLD_RACES[mode][i]), tag + " races")
			assert_eq(int(run["wins"]), int(GOLD_WINS[mode][i]), tag + " wins")
			assert_eq(int(run["overtakes"]), int(GOLD_OVERTAKES[mode][i]), tag + " overtakes")
			assert_almost(
				float(run["driftMeters"]), float(GOLD_DRIFT[mode][i]), 1e-6, tag + " drift"
			)
			assert_almost(float(run["time"]), float(GOLD_TIME[mode][i]), 1e-6, tag + " time")


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(mode, 12), Logic.simulate_autoplay(mode, 12), mode)


func test_difficulty_means_match_web() -> void:
	# Zahlengleichheit ist die Messlatte. Schwer liegt niedriger, weil das
	# schnellere Feld weniger Driftmeter zulässt — exakt wie im Web.
	for mode: String in GOLD_MEAN:
		var sum := 0
		for seed_value in range(1, 31):
			sum += int(Logic.simulate_autoplay(mode, seed_value)["score"])
		assert_almost(float(sum) / 30.0, float(GOLD_MEAN[mode]), 1e-9, mode)
	assert_true(float(GOLD_MEAN["easy"]) >= float(GOLD_MEAN["hard"]))


func test_bot_reaches_target() -> void:
	# Coin-Ziel 150: der Bot muss es im Mittel schaffen.
	var sum := 0
	for seed_value in range(1, 21):
		sum += int(Logic.simulate_autoplay("normal", seed_value)["score"])
	var mean := float(sum) / 20.0
	assert_true(mean >= 150.0, "Bot-Mittel %f" % mean)
	# Und der Bot fährt sauber genug für Platz 1.
	assert_eq(int(Logic.simulate_autoplay("normal", 3)["rank"]), 1)


func test_endless_chains_and_terminates() -> void:
	for seed_value in range(1, 7):
		var run := Logic.simulate_autoplay("endless", seed_value)
		assert_true(int(run["races"]) > 1, "seed %d kettet" % seed_value)
		assert_true(int(run["rank"]) > 2, "seed %d endet bei Platz > 2" % seed_value)
		assert_true(float(run["time"]) < 3600.0, "seed %d beendet" % seed_value)
	# Harte Zeitschranke greift ebenfalls.
	var capped := Logic.simulate_autoplay("endless", 2, 40.0)
	assert_true(float(capped["time"]) <= 40.0 + 1e-9)
	assert_eq(int(capped["races"]), 1)


func test_track_generation_matches_web() -> void:
	var gold := {
		1: ["loopBoulevard", false, 56.851674873, 228, 4, 2],
		2: ["loopBoulevard", false, 56.851674873, 228, 4, 2],
		3: ["rugRing", true, 41.206998146, 165, 4, 0],
		4: ["loopBoulevard", false, 56.851674873, 228, 4, 2],
		5: ["rugRing", true, 41.206998146, 165, 4, 0],
		7: ["rugRing", true, 41.206998146, 165, 4, 0],
	}
	for seed_value: int in gold:
		var row: Array = gold[seed_value]
		var track := Logic.build_track(seed_value)
		var tag := "seed %d" % seed_value
		assert_eq(str(track["templateId"]), str(row[0]), tag + " tpl")
		assert_eq(bool(track["hasBumps"]), bool(row[1]), tag + " bumps")
		assert_almost(float(track["lapLen"]), float(row[2]), 1e-8, tag + " lapLen")
		assert_eq((track["samples"] as Array).size(), int(row[3]), tag + " samples")
		assert_eq((track["cornerZones"] as Array).size(), int(row[4]), tag + " corners")
		assert_eq((track["loopZones"] as Array).size(), int(row[5]), tag + " loops")
	# Item-Reihen: der Looping-Kurs schiebt zwei Reihen hinter den Looping.
	var loop_rows: Array = Logic.build_track(1)["itemRows"]
	assert_almost(float(loop_rows[0]["s"]), 30.25515441, 1e-8)
	assert_almost(float(loop_rows[1]["s"]), 30.25515441, 1e-8)
	assert_almost(float(loop_rows[2]["s"]), 46.618373396, 1e-8)
	var ring_rows: Array = Logic.build_track(3)["itemRows"]
	assert_almost(float(ring_rows[0]["s"]), 7.417259666, 1e-8)
	assert_almost(float(ring_rows[1]["s"]), 20.603499073, 1e-8)
	assert_almost(float(ring_rows[2]["s"]), 33.78973848, 1e-8)


func test_point_at_matches_web() -> void:
	var pt := Logic.point_at(Logic.build_track(1), 5.5)
	var p: Array = pt["p"]
	assert_almost(float(p[0]), -0.326261926, 1e-8, "px")
	assert_almost(float(p[1]), 2.483652995, 1e-8, "py")
	assert_almost(float(p[2]), 3.5083212, 1e-8, "pz")
	var tan: Array = pt["t"]
	assert_almost(float(tan[0]), -0.0935557, 1e-8, "tx")
	assert_almost(float(tan[1]), 0.883421799, 1e-8, "ty")
	assert_almost(float(tan[2]), -0.459144048, 1e-8, "tz")
	assert_almost(float(pt["kappa"]), 0.0, 1e-9, "kappa")
	# s läuft rundenweise um.
	var track := Logic.build_track(3)
	var a := Logic.point_at(track, 1.0)
	var b := Logic.point_at(track, 1.0 + float(track["lapLen"]))
	assert_almost(float((a["p"] as Array)[0]), float((b["p"] as Array)[0]), 1e-9)


func test_rubber_band_matches_web() -> void:
	var gold := [0.88, 0.9, 1.0, 1.1, 1.12]
	var gaps := [-20.0, -6.0, 0.0, 6.0, 20.0]
	for i in gaps.size():
		assert_almost(Logic.compute_rubber(float(gaps[i])), float(gold[i]), 1e-9, "gap %d" % i)
	# Gedeckelt in beide Richtungen.
	assert_almost(Logic.compute_rubber(1e9), float(Logic.RACER["RUBBER_MAX"]))
	assert_almost(Logic.compute_rubber(-1e9), float(Logic.RACER["RUBBER_MIN"]))


func test_scoring_edges() -> void:
	assert_eq(Logic.race_score(1, 0, 0.0), 120)
	assert_eq(Logic.race_score(2, 3, 125.0), 98)
	assert_eq(Logic.race_score(4, 10, 999.0), 149)
	# Platz außerhalb der Tabelle klemmt auf die Ränder.
	assert_eq(Logic.race_score(0, 0, 0.0), 120)
	assert_eq(Logic.race_score(9, 0, 0.0), 30)
	# Driftmeter werden abgerundet.
	assert_eq(Logic.race_score(1, 0, 19.9), 121)
	# Turbo-Modifikator skaliert die Endpunktzahl.
	var turbo := Logic.apply_modifier(
		Logic.RACER, {"type": "turbo", "speedMult": 1.25, "scoreMult": 1.5}
	)
	assert_almost(float(turbo["TARGET_LAP_SEC"]), 47.0 / 1.25)
	assert_almost(float(turbo["SCORE_MULT"]), 1.5)
	var race := Logic.create_race(3, turbo)
	race["ended"] = true
	race["finishRank"] = 1
	assert_eq(Logic.run_score(race), 180)


func test_modifier_hooks() -> void:
	assert_true(Logic.apply_modifier(Logic.RACER, {}) == Logic.RACER)
	var rain := Logic.apply_modifier(Logic.RACER, {"type": "muenzregen", "coinRate": 2.0})
	assert_almost(float(rain["ITEM_RESPAWN_SEC"]), 1.25)
	assert_almost(float(rain["ITEM_RATE"]), 2.0)
	assert_true(Logic.apply_modifier(Logic.RACER, {"type": "unbekannt"}) == Logic.RACER)


func test_race_state_and_helpers() -> void:
	var race := Logic.create_race(3)
	var karts: Array = race["karts"]
	assert_eq(karts.size(), 4)
	assert_true(bool(karts[0]["isPlayer"]))
	# Der Spieler startet hinten im Feld.
	assert_eq(Logic.player_rank(race), 4)
	assert_eq(Logic.player_lap(race), 1)
	for i in range(1, 4):
		assert_true(float(karts[i]["progress"]) > float(karts[0]["progress"]))
	# Ringdifferenz nimmt den kurzen Weg.
	var lap_len := float(race["track"]["lapLen"])
	assert_almost(Logic.s_delta(1.0, lap_len - 1.0, lap_len), 2.0, 1e-9)
	assert_almost(Logic.s_delta(lap_len - 1.0, 1.0, lap_len), -2.0, 1e-9)
	# Item-Wurf folgt den Gewichten 0.4/0.3/0.3.
	var counts := {"turbo": 0, "shield": 0, "block": 0}
	var rng := GoobyRng.new(4)
	for _i in 3000:
		counts[Logic.roll_item(rng)] += 1
	assert_true(int(counts["turbo"]) > int(counts["shield"]))
	assert_true(int(counts["block"]) > 700)


func test_step_race_drift_boost_and_finish() -> void:
	var race := Logic.create_race(3)
	# In der Kurve driften lädt schneller als auf der Geraden.
	for _i in 90:
		Logic.step_race(race, 1.0 / 30.0, {"steer": 0.0, "drifting": true})
	var player: Dictionary = race["karts"][0]
	assert_true(float(player["driftMeters"]) > 0.0, "Driftmeter zählen")
	assert_true(float(player["speed"]) > 0.0)
	# Loslassen mit genug Ladung gibt Schub.
	player["driftCharge"] = 1.0
	Logic.step_race(race, 1.0 / 30.0, {"steer": 0.0, "drifting": false})
	assert_almost(float(player["boostMult"]), float(Logic.RACER["DRIFT_BOOST_MULT"]))
	assert_true(float(player["boostT"]) > 0.0)
	# Neben der Strecke wird gebremst.
	assert_false(bool(player["offTrack"]))
	player["lateral"] = 0.7
	player["targetLateral"] = 0.7
	Logic.step_race(race, 1.0 / 30.0, {"steer": 0.7, "drifting": false})
	assert_true(bool(player["offTrack"]))
	# Zeitlimit beendet das Rennen fail-closed.
	var timeout := Logic.create_race(3)
	for _i in 40:
		Logic.step_race(timeout, 0.25, {"steer": 0.0, "drifting": false})
		if bool(timeout["ended"]):
			break
	# 10 s reichen nicht für 3 Runden — das Rennen läuft noch.
	assert_false(bool(timeout["ended"]))
	assert_true(Logic.player_rank(timeout) >= 1 and Logic.player_rank(timeout) <= 4)


func test_block_stun_and_shield() -> void:
	var race := Logic.create_race(3)
	var player: Dictionary = race["karts"][0]
	player["item"] = "block"
	Logic.step_race(race, 1.0 / 30.0, {"steer": 0.0, "drifting": false, "useItem": true})
	assert_eq((race["blocks"] as Array).size(), 1)
	assert_true(str(player["item"]).is_empty())
	# Direkt auf einen Block fahren betäubt.
	var blocks: Array = race["blocks"]
	blocks[0]["s"] = float(player["s"])
	blocks[0]["lat"] = float(player["lateral"])
	blocks[0]["by"] = 99
	Logic.step_race(race, 1.0 / 30.0, {"steer": 0.0, "drifting": false})
	assert_true(float(player["stunT"]) > 0.0, "Bauklotz betäubt")
	# Mit Schild platzt stattdessen das Schild.
	player["stunT"] = 0.0
	player["shield"] = true
	blocks = race["blocks"]
	blocks.append({"s": float(player["s"]), "lat": float(player["lateral"]), "by": 99})
	Logic.step_race(race, 1.0 / 30.0, {"steer": 0.0, "drifting": false})
	assert_false(bool(player["shield"]), "Schild verbraucht")
	assert_almost(float(player["stunT"]), 0.0, 1e-9)
