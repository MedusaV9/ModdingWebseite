extends TestCase
## Gooby Einkaufs-Surf — Logik-Parität zum Web (MG-3, Batch 3).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/shoppingSurf.logic.js
## (Erzeuger: /tmp/gooby-godot/mg3/gold_surf.mjs).

const Logic := preload("res://scripts/minigames/games/shopping_surf/shopping_surf_logic.gd")
const Run := preload("res://scripts/minigames/games/shopping_surf/shopping_surf_run.gd")

## Web: simulateSurfAutoplay(mode, seed, 90).score für Seeds 1..5.
const GOLD_SCORE := {
	"easy": [975, 1035, 1057, 965, 977],
	"normal": [706, 1126, 1176, 1083, 819],
	"hard": [1095, 708, 1383, 784, 632],
	"endless": [1328, 716, 1206, 1405, 612],
}
## Dieselben Läufe: Crashes und ob der Lauf vorzeitig endete.
const GOLD_CRASHES := {
	"easy": [1, 0, 0, 2, 1],
	"normal": [3, 1, 1, 2, 3],
	"hard": [3, 3, 2, 3, 3],
	"endless": [2, 3, 3, 1, 3],
}
## Web: pickNextChunk mit mulberry32(7), Start 0 m, Schritt 30 m.
const GOLD_CHUNKS := [0, 1, 3, 2, 0, 1, 3, 4, 7, 6, 5, 0, 8, 3, 4, 0, 1, 0, 8, 0, 8, 3, 6, 2]
## Web: planPowerupKind-Kette mit mulberry32(11).
const GOLD_POWERUPS := [
	"x2",
	"magnet",
	"shield",
	"turbo",
	"shield",
	"magnet",
	"shield",
	"turbo",
	"x2",
	"shield",
	"x2",
	"turbo",
]


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.SURF
	assert_eq(int(t["LANES"]), 3)
	assert_eq(t["LANE_X"], [-1.6, 0.0, 1.6])
	assert_almost(float(t["LANE_W"]), 1.6)
	assert_almost(float(t["BASE_SPEED"]), 8.0)
	assert_almost(float(t["SPEED_STEP"]), 0.25)
	assert_almost(float(t["SPEED_EVERY_SEC"]), 5.0)
	assert_almost(float(t["MAX_SPEED"]), 16.0)
	assert_almost(float(t["LANE_CHANGE_SEC"]), 0.12)
	assert_almost(float(t["JUMP_SEC"]), 0.55)
	assert_almost(float(t["JUMP_HEIGHT"]), 1.35)
	assert_almost(float(t["SLIDE_SEC"]), 0.5)
	assert_almost(float(t["SLIDE_HEIGHT"]), 0.5)
	assert_almost(float(t["FAST_DROP_SPEED"]), 10.0)
	assert_almost(float(t["BUFFER_SEC"]), 0.25)
	assert_almost(float(t["PLAYER_HALF_W"]), 0.42)
	assert_almost(float(t["PLAYER_HALF_DEPTH"]), 0.3)
	assert_almost(float(t["STUMBLE_SEC"]), 0.8)
	assert_almost(float(t["INVULN_SEC"]), 1.5)
	assert_eq(int(t["ARCADE_MAX_CRASHES"]), 3)
	assert_almost(float(t["NEAR_MISS_M"]), 0.35)
	assert_almost(float(t["CHUNK_LEN_M"]), 30.0)
	assert_almost(float(t["SPAWN_AHEAD_M"]), 70.0)
	assert_almost(float(t["DESPAWN_Z"]), 8.0)
	assert_almost(float(t["GAP_MIN_DISTANCE_M"]), 800.0)
	assert_almost(float(t["POWERUP_GAP_MIN_M"]), 180.0)
	assert_almost(float(t["POWERUP_GAP_MAX_M"]), 260.0)
	assert_almost(float(t["MAX_SWEEP_STEP_M"]), 0.32)
	assert_eq(Logic.CHUNKS.size(), 12)

	var obs: Dictionary = Logic.SURF["OBSTACLES"]
	assert_eq(obs.keys(), ["cart", "crate", "npc", "awning", "puddle", "gap"])
	assert_almost(float(obs["cart"]["clearY"]), 0.55)
	assert_almost(float(obs["cart"]["ownSpeed"]), 2.0)
	assert_almost(float(obs["cart"]["telegraphSec"]), 0.9)
	assert_almost(float(obs["npc"]["crossSpeed"]), 1.2)
	assert_almost(float(obs["awning"]["gapY"]), 0.88)
	assert_almost(float(obs["puddle"]["slowMult"]), 0.9)
	assert_almost(float(obs["puddle"]["slowSec"]), 2.0)
	assert_almost(float(obs["gap"]["halfDepth"]), 1.1)
	var pu: Dictionary = Logic.SURF["POWERUPS"]
	assert_almost(float(pu["magnet"]["sec"]), 6.0)
	assert_almost(float(pu["magnet"]["radius"]), 3.0)
	assert_almost(float(pu["x2"]["sec"]), 8.0)
	assert_almost(float(pu["turbo"]["sec"]), 2.5)
	assert_almost(float(pu["turbo"]["speedMult"]), 1.4)
	assert_almost(float(pu["turbo"]["minGapM"]), 400.0)
	var travel: Dictionary = Logic.SURF["TRAVEL"]
	assert_almost(float(travel["DISTANCE_M"]), 700.0)
	assert_almost(float(travel["JOG_SPEED"]), 7.0)
	assert_eq(int(travel["COIN_CAP"]), 30)
	assert_eq(int(travel["CLEAN_BONUS"]), 5)


func test_speed_ramp_matches_web() -> void:
	var gold := [8.0, 8.0, 8.25, 8.5, 10.0, 16.0]
	var at := [0.0, 4.9, 5.0, 12.0, 40.0, 200.0]
	for i in at.size():
		assert_almost(Logic.speed_ramp_at(at[i]), gold[i])


func test_score_and_travel_reward_edges() -> void:
	assert_eq(Logic.surf_score(123.9, 10, 3), 149)
	assert_eq(Logic.surf_score(0.0, 0, 0), 0)
	# floor(-5) = -5, +2×2 → 1 (nie negativ, aber hier positiv).
	assert_eq(Logic.surf_score(-5.0, 2, 1), 1)
	# Wertung klemmt bei 0.
	assert_eq(Logic.surf_score(-500.0, 0, 0), 0)
	assert_eq(Logic.travel_reward(12, 0), {"coins": 17, "clean": true})
	assert_eq(Logic.travel_reward(60, 0), {"coins": 35, "clean": true})
	assert_eq(Logic.travel_reward(60, 2), {"coins": 30, "clean": false})
	assert_eq(Logic.travel_reward(0, 1), {"coins": 0, "clean": false})
	assert_true(Logic.is_travel_mode("travel"))
	assert_true(Logic.is_travel_mode("surfTravel"))
	assert_false(Logic.is_travel_mode("arcade"))


func test_chunk_stream_matches_web() -> void:
	var rng := GoobyRng.new(7)
	var picks: Array[int] = []
	var last := -1
	var at := 0.0
	for _i in GOLD_CHUNKS.size():
		var idx := Logic.pick_next_chunk(rng, at, last)
		picks.append(idx)
		last = idx
		at += 30.0
	assert_eq(picks, GOLD_CHUNKS)


func test_chunk_gating_rules() -> void:
	# Der Aufwärmabschnitt eröffnet JEDEN Lauf.
	assert_eq(Logic.pick_next_chunk(GoobyRng.new(3), 0.0, -1), 0)
	# Lücken-Abschnitte (curbBreak = 10) erst ab 800 m.
	for seed_value in 200:
		var idx := Logic.pick_next_chunk(GoobyRng.new(seed_value), 700.0, -1)
		assert_ne(idx, 10, "Lücke vor 800 m gezogen")
	# Kistenreihen sperren nie alle drei Spuren.
	for def: Dictionary in Logic.CHUNKS:
		var blocked := {}
		for h: Dictionary in def["hazards"]:
			if str(h["kind"]) == "crate":
				blocked[int(h["atM"])] = int(blocked.get(int(h["atM"]), 0)) + 1
		for count in blocked.values():
			assert_true(int(count) < 3, "Kistenwand in %s" % def["name"])
		# Hindernisse liegen im Reaktionsfenster [8, 24] m.
		for h: Dictionary in def["hazards"]:
			assert_true(float(h["atM"]) >= 8.0 and float(h["atM"]) <= 24.0, str(def["name"]))

	var parts := Logic.expand_chunk(Logic.CHUNKS[0], 120.0)
	assert_almost(float(parts["hazards"][0]["atM"]), 135.0)
	assert_almost(float(parts["coins"][0]["atM"]), 135.0)
	assert_almost(float(parts["coins"][1]["atM"]), 142.0)
	# Die Vorlage bleibt unangetastet.
	assert_almost(float(Logic.CHUNKS[0]["hazards"][0]["atM"]), 15.0)


func test_validator_rows_and_survivability() -> void:
	var hz: Array = Logic.expand_chunk(Logic.CHUNKS[6], 200.0)["hazards"]
	var rows := Logic.hazard_rows(hz, 12.0)
	assert_eq(rows.size(), 2)
	assert_almost(float(rows[0]["t"]), 16.916667, 1e-5)
	assert_eq(rows[0]["lanes"], ["jump", "jump", null])
	assert_almost(float(rows[1]["t"]), 17.75, 1e-5)
	assert_eq(rows[1]["lanes"], [null, null, "slide"])
	for v in [8.0, 12.0, 16.0]:
		assert_true(Logic.is_sequence_survivable(hz, v), "actionWall bei %s" % v)
	# Drei Kisten nebeneinander sind unmöglich — das MUSS der Validator sehen.
	var wall: Array = []
	for lane in 3:
		wall.append({"atM": 50.0, "kind": "crate", "lane": lane})
	assert_false(Logic.is_sequence_survivable(wall, 10.0))
	# Pfützen sind weich und erzeugen gar keine Zeile.
	assert_eq(Logic.hazard_rows([{"atM": 20.0, "kind": "puddle", "lane": 1}], 10.0).size(), 0)


func test_every_chunk_survivable_at_all_ramp_speeds() -> void:
	for mode in ["easy", "normal", "hard", "endless"]:
		var tune := Logic.apply_difficulty(Logic.SURF, mode)
		var speeds := Logic.validator_probe_speeds(tune)
		assert_true(speeds.size() >= 2)
		for def: Dictionary in Logic.CHUNKS:
			var hz: Array = Logic.expand_chunk(def, maxf(800.0, float(def["minM"])))["hazards"]
			for v in speeds:
				assert_true(
					Logic.is_sequence_survivable(hz, v, tune),
					"%s in %s bei %s m/s" % [def["name"], mode, v]
				)


func test_powerup_planning_matches_web() -> void:
	var rng := GoobyRng.new(11)
	var kinds: Array[String] = []
	var last: Variant = null
	var since_turbo := INF
	var at := 0.0
	for _i in GOLD_POWERUPS.size():
		var k := Logic.plan_powerup_kind(rng, last, since_turbo)
		kinds.append(k)
		since_turbo = 0.0 if k == "turbo" else since_turbo + 200.0
		last = k
		at += Logic.plan_powerup_gap(rng)
	assert_eq(kinds, GOLD_POWERUPS)
	assert_almost(at, 2584.926969, 1e-4)
	# Nie zweimal dieselbe Art hintereinander.
	for i in range(1, kinds.size()):
		assert_ne(kinds[i], kinds[i - 1])

	var band := GoobyRng.new(4242)
	for _i in 400:
		var gap := Logic.plan_powerup_gap(band)
		assert_true(gap >= 180.0 and gap < 260.0, "Abstand %s" % gap)


func test_difficulty_monotonicity() -> void:
	var easy := Logic.apply_difficulty(Logic.SURF, "easy")
	var normal := Logic.apply_difficulty(Logic.SURF, "normal")
	var hard := Logic.apply_difficulty(Logic.SURF, "hard")
	var endless := Logic.apply_difficulty(Logic.SURF, "endless")
	# `normal` liefert die Basis-Tabelle IDENTISCH zurück (bit-gleicher Strom).
	assert_true(normal == Logic.SURF)
	# Tempo, Deckel und Dichte steigen streng monoton.
	assert_true(float(easy["BASE_SPEED"]) < float(normal["BASE_SPEED"]))
	assert_true(float(normal["BASE_SPEED"]) < float(hard["BASE_SPEED"]))
	assert_true(float(easy["MAX_SPEED"]) < float(normal["MAX_SPEED"]))
	assert_true(float(normal["MAX_SPEED"]) < float(hard["MAX_SPEED"]))
	assert_true(float(hard["MAX_SPEED"]) < float(endless["MAX_SPEED"]))
	assert_almost(float(hard["MAX_SPEED"]), 18.0)
	assert_almost(float(endless["MAX_SPEED"]), 20.0)
	assert_true(float(easy["DENSITY_MULT"]) < float(normal["DENSITY_MULT"]))
	assert_true(float(normal["DENSITY_MULT"]) < float(hard["DENSITY_MULT"]))
	# Nur leicht schenkt ein Extra-Leben; Endlos endet wie Arcade beim 3.
	assert_eq(int(easy["ARCADE_MAX_CRASHES"]), 4)
	assert_eq(int(hard["ARCADE_MAX_CRASHES"]), 3)
	assert_eq(int(endless["ARCADE_MAX_CRASHES"]), 3)
	assert_true(bool(endless["ENDLESS"]))
	assert_false(bool(hard["ENDLESS"]))
	# Bot-Aussetzer werden mit der Schwierigkeit häufiger.
	assert_true(float(easy["BOT_MISS_CHANCE"]) < float(normal["BOT_MISS_CHANCE"]))
	assert_true(float(normal["BOT_MISS_CHANCE"]) < float(hard["BOT_MISS_CHANCE"]))

	# Dichte-Rampe: nur Endlos zieht bis zum Deckel ×1,5 an.
	for d in [0.0, 750.0, 1500.0, 3000.0]:
		assert_almost(Logic.density_mult_at(d, normal), 1.0)
	assert_almost(Logic.density_mult_at(0.0, endless), 1.15)
	assert_almost(Logic.density_mult_at(750.0, endless), 1.325)
	assert_almost(Logic.density_mult_at(1500.0, endless), 1.5)
	assert_almost(Logic.density_mult_at(3000.0, endless), 1.5)


func test_modifiers_are_payload_only() -> void:
	var base: Dictionary = Logic.SURF
	assert_true(Logic.apply_modifier(base, {}) == base)
	var rain := Logic.apply_modifier(base, {"type": "muenzregen", "coinRate": 1.5})
	assert_almost(float(rain["COIN_RATE"]), 1.5)
	var turbo := Logic.apply_modifier(base, {"type": "turbo", "speedMult": 1.25, "scoreMult": 1.5})
	assert_almost(float(turbo["BASE_SPEED"]), 10.0)
	assert_almost(float(turbo["MAX_SPEED"]), 20.0)
	assert_almost(float(turbo["SCORE_MULT"]), 1.5)
	assert_true(bool(turbo["GATED_SPAWNS"]))
	var giant := Logic.apply_modifier(
		base, {"type": "riesenGooby", "hitboxMult": 1.3, "scale": 1.4}
	)
	assert_almost(float(giant["PLAYER_HALF_W"]), 0.546)
	assert_almost(float(giant["RENDER_SCALE_MULT"]), 1.4)
	# Münzregen ×1.5 liefert im Schnitt +50 % Münzen einer 4er-Reihe.
	var rng := GoobyRng.new(9)
	var total := 0
	for _i in 2000:
		total += Logic.coin_row_count(rng, 4, rain)
	assert_true(absf(total / 2000.0 - 6.0) < 0.15, "Schnitt %s" % (total / 2000.0))
	# COIN_RATE 1 zieht KEINE Zufallszahl (bit-identischer Mittel-Strom).
	var probe := GoobyRng.new(9)
	assert_eq(Logic.coin_row_count(probe, 4), 4)
	assert_almost(probe.next(), GoobyRng.new(9).next())


func test_scripted_run_matches_web() -> void:
	var run := Run.create_run(GoobyRng.new(99))
	var script := {
		20: {"right": true}, 60: {"jump": true}, 95: {"left": true}, 140: {"slide": true}
	}
	var trace: Array = []
	for i in 400:
		var evs := Run.step_run(run, 1.0 / 30.0, script.get(i, {}))
		if i % 50 == 0:
			var types: Array[String] = []
			for e: Dictionary in evs:
				types.append(str(e["type"]))
			(
				trace
				. append(
					{
						"i": i,
						"d": MinigameFrameworkLogic.js_round(float(run["distanceM"]) * 1e4),
						"lane": int(run["lane"]),
						"coins": int(run["coins"]),
						"crashes": int(run["crashes"]),
						"obs": (run["obstacles"] as Array).size(),
						"ev": "|".join(types),
					}
				)
			)
		if bool(run["ended"]):
			break
	# `d` sind Zehntelmillimeter (Meter × 1e4), damit der Vergleich exakt
	# ganzzahlig bleibt — Dictionary-Gleichheit kennt keine Float-Toleranz.
	var gold := [
		{
			"i": 0,
			"d": 2667,
			"lane": 1,
			"coins": 0,
			"crashes": 0,
			"obs": 4,
			"ev": "spawn|spawn|spawn|spawn"
		},
		{"i": 50, "d": 136000, "lane": 2, "coins": 0, "crashes": 0, "obs": 5, "ev": ""},
		{"i": 100, "d": 269333, "lane": 1, "coins": 4, "crashes": 0, "obs": 4, "ev": ""},
		{"i": 150, "d": 397333, "lane": 1, "coins": 4, "crashes": 1, "obs": 6, "ev": ""},
		{"i": 200, "d": 504000, "lane": 1, "coins": 4, "crashes": 1, "obs": 5, "ev": ""},
		{"i": 250, "d": 605333, "lane": 1, "coins": 4, "crashes": 2, "obs": 5, "ev": ""},
		{"i": 300, "d": 738667, "lane": 1, "coins": 6, "crashes": 2, "obs": 6, "ev": ""},
		{"i": 350, "d": 872000, "lane": 1, "coins": 8, "crashes": 2, "obs": 6, "ev": ""},
	]
	assert_eq(trace.size(), gold.size())
	for k in gold.size():
		assert_eq(trace[k], gold[k], "Schritt %d" % int(gold[k]["i"]))
	assert_eq(Run.run_score(run), 115)
	assert_eq(
		Run.run_meta(run),
		{
			"distanceM": 99,
			"coins": 8,
			"coinsCollected": 8,
			"nearMisses": 0,
			"powerups": 0,
			"crashes": 3,
			"surfRun": true,
		}
	)


func test_travel_run_matches_web() -> void:
	var result := Run.simulate_run(GoobyRng.new(5), "travel", 300.0)
	var run: Dictionary = result["run"]
	assert_true(bool(run["finished"]))
	assert_almost(float(run["distanceM"]), 700.040833, 1e-4)
	assert_eq(int(run["coins"]), 145)
	assert_eq(int(run["crashes"]), 1)
	assert_eq(
		Logic.travel_reward(int(run["coins"]), int(run["crashes"])), {"coins": 30, "clean": false}
	)


func test_autoplay_matches_web_gold() -> void:
	for mode in GOLD_SCORE:
		for i in 5:
			var out := Run.simulate_autoplay(str(mode), i + 1, 90.0)
			assert_eq(
				int(out["score"]), int(GOLD_SCORE[mode][i]), "%s Saat %d Punkte" % [mode, i + 1]
			)
			assert_eq(
				int(out["crashes"]),
				int(GOLD_CRASHES[mode][i]),
				"%s Saat %d Crashes" % [mode, i + 1]
			)


func test_determinism_same_seed_same_run() -> void:
	var a := Run.simulate_run(GoobyRng.new(31), "arcade", 60.0)
	var b := Run.simulate_run(GoobyRng.new(31), "arcade", 60.0)
	assert_eq(int(a["score"]), int(b["score"]))
	assert_eq(int(a["events"]), int(b["events"]))
	assert_almost(float(a["run"]["distanceM"]), float(b["run"]["distanceM"]))
	var c := Run.simulate_run(GoobyRng.new(32), "arcade", 60.0)
	assert_ne(int(a["score"]), int(c["score"]))


func test_bot_is_plausible_and_beats_the_target() -> void:
	# Ziel der Kachel ist 420 Punkte — der Bot muss es überall schlagen.
	# ABWEICHUNG ZUR ERWARTUNG: die PUNKTE fallen NICHT mit der Schwierigkeit,
	# weil Punkte = Meter sind und die harten Modi schneller laufen. Die §G10
	# Monotonie hängt an Überlebenszeit und Crashes — die prüfen wir hier.
	var survival := {}
	var crashes := {}
	for mode in ["easy", "normal", "hard"]:
		var score_sum := 0
		var elapsed_sum := 0.0
		var crash_sum := 0
		for seed_value in range(1, 13):
			var out := Run.simulate_autoplay(mode, seed_value, 90.0)
			assert_true(float(out["distanceM"]) > 150.0, "%s zu kurz" % mode)
			assert_true(int(out["crashes"]) <= 4, "%s zu viele Crashes" % mode)
			score_sum += int(out["score"])
			elapsed_sum += float(out["elapsed"])
			crash_sum += int(out["crashes"])
		assert_true(score_sum / 12.0 > 420.0, "%s Schnitt %s" % [mode, score_sum / 12.0])
		survival[mode] = elapsed_sum / 12.0
		crashes[mode] = crash_sum / 12.0
	assert_true(float(survival["easy"]) >= float(survival["normal"]), "%s" % survival)
	assert_true(float(survival["normal"]) > float(survival["hard"]), "%s" % survival)
	assert_true(float(crashes["easy"]) < float(crashes["normal"]), "%s" % crashes)
	assert_true(float(crashes["normal"]) < float(crashes["hard"]), "%s" % crashes)


func test_endless_terminates_on_third_crash() -> void:
	# Endlos hat keinen Zeitdeckel in der Logik — nur der 3. Crash beendet.
	var ended := 0
	for seed_value in range(1, 13):
		var out := Run.simulate_autoplay("endless", seed_value, 400.0)
		if bool(out["ended"]):
			ended += 1
			assert_eq(int(out["crashes"]), 3)
	assert_true(ended >= 10, "nur %d von 12 Endlos-Läufen endeten" % ended)


func test_crash_rules_and_shield() -> void:
	var run := Run.create_run(GoobyRng.new(1))
	var tune: Dictionary = run["tune"]
	var obstacles: Array = run["obstacles"]
	obstacles.clear()
	var crate := {
		"id": 1,
		"kind": "crate",
		"def": (tune["OBSTACLES"] as Dictionary)["crate"],
		"lane": 1,
		"lanes": null,
		"z": -0.2,
		"x": 0.0,
		"halfW": 0.6,
		"telegraphed": false,
		"hit": false,
		"minClear": INF,
		"passed": false,
	}
	obstacles.append(crate)
	# Mit Schild: kein Crash, dafür Unverwundbarkeit.
	run["pu"]["shield"] = true
	var evs := Run.step_run(run, 1.0 / 30.0)
	assert_eq(int(run["crashes"]), 0)
	assert_false(bool(run["pu"]["shield"]))
	assert_true(float(run["invulnT"]) > 0.0)
	assert_true(_has_event(evs, "shieldPop"))
	# Beim echten Crash fällt die Temporampe auf die Basis zurück; der Crash
	# wird NACH dem Zeitgeber-Abbau gebucht, Stolpern startet also voll.
	run["invulnT"] = 0.0
	run["rampSec"] = 60.0
	crate["hit"] = false
	crate["z"] = -0.2
	evs = Run.step_run(run, 1.0 / 30.0)
	assert_eq(int(run["crashes"]), 1)
	assert_almost(float(run["rampSec"]), 0.0)
	assert_almost(Logic.speed_ramp_at(float(run["rampSec"])), float(tune["BASE_SPEED"]))
	assert_true(_has_event(evs, "crash"))
	assert_almost(float(run["stumbleT"]), float(tune["STUMBLE_SEC"]))
	# Im Stolpern torkelt Gooby im halben Tempo.
	assert_almost(Run.current_speed(run), float(tune["BASE_SPEED"]) * 0.5)


func test_jump_slide_buffer_and_fast_drop() -> void:
	var run := Run.create_run(GoobyRng.new(2))
	Run.step_run(run, 1.0 / 60.0, {"jump": true})
	assert_true(float(run["jumpT"]) >= 0.0, "Sprung nicht gestartet")
	assert_true(Run.player_y(run) > 0.0, "Gooby klebt am Boden")
	# Bis kurz vor den Scheitel steigen (0,25 s von 0,55 s).
	for _i in 14:
		Run.step_run(run, 1.0 / 60.0)
	var apex := Run.player_y(run)
	assert_true(apex > 1.2, "Scheitelhöhe %s" % apex)
	# Ein Rutscher in der Luft wird zum Schnellfall.
	var evs := Run.step_run(run, 1.0 / 60.0, {"slide": true})
	assert_true(bool(run["fastDrop"]), "kein Schnellfall")
	assert_true(_has_event(evs, "fastDrop"), "kein fastDrop-Ereignis")
	# Der Schnellfall sinkt mit exakt 10 m/s — schneller als die Sprungkurve.
	var before := Run.player_y(run)
	Run.step_run(run, 1.0 / 60.0)
	assert_almost(before - Run.player_y(run), 10.0 / 60.0, 1e-5)
	for _i in 20:
		Run.step_run(run, 1.0 / 60.0)
	assert_almost(Run.player_y(run), 0.0)
	assert_true(float(run["jumpT"]) < 0.0, "Sprung nicht beendet")
	# Springen während des Rutschens ist gesperrt und landet im Puffer.
	var slider := Run.create_run(GoobyRng.new(3))
	Run.step_run(slider, 1.0 / 60.0, {"slide": true})
	Run.step_run(slider, 1.0 / 60.0, {"jump": true})
	assert_true(float(slider["jumpT"]) < 0.0, "Sprung im Rutschen gestartet")
	assert_eq(str(slider["buffered"]["type"]), "jump")
	# Zu früh gepuffert = verfallen: das Fenster ist nur 250 ms, der Rutscher
	# dauert 500 ms. Am Rutsch-Ende ist der Puffer längst leer.
	for _i in 30:
		Run.step_run(slider, 1.0 / 60.0)
	assert_true((slider["buffered"] as Dictionary).is_empty(), "Puffer nicht verfallen")
	assert_true(float(slider["jumpT"]) < 0.0, "verfallener Puffer hat gefeuert")
	# Rechtzeitig gepuffert (0,1 s vor Rutsch-Ende) feuert der Sprung sofort.
	var late := Run.create_run(GoobyRng.new(3))
	Run.step_run(late, 0.4, {"slide": true})
	Run.step_run(late, 1.0 / 60.0, {"jump": true})
	assert_eq(str(late["buffered"]["type"]), "jump")
	Run.step_run(late, 0.1)
	assert_true(float(late["slideT"]) < 0.0, "Rutscher nicht beendet")
	assert_true(float(late["jumpT"]) >= 0.0, "gepufferter Sprung blieb liegen")
	assert_true((late["buffered"] as Dictionary).is_empty())


func test_lane_tween_and_clamping() -> void:
	var run := Run.create_run(GoobyRng.new(4))
	assert_eq(int(run["lane"]), 1)
	assert_almost(Run.player_x(run), 0.0)
	Run.step_run(run, 1.0 / 60.0, {"left": true})
	assert_eq(int(run["lane"]), 0)
	# Der Tween läuft geglättet, nicht sprunghaft.
	assert_true(Run.player_x(run) > -1.6 and Run.player_x(run) < 0.0)
	for _i in 12:
		Run.step_run(run, 1.0 / 60.0)
	assert_almost(Run.player_x(run), -1.6)
	# Am Rand bleibt Gooby stehen, statt aus der Straße zu fallen.
	Run.step_run(run, 1.0 / 60.0, {"left": true})
	assert_eq(int(run["lane"]), 0)


func test_travel_third_crash_switches_to_jog() -> void:
	var run := Run.create_run(GoobyRng.new(6), "travel")
	run["crashes"] = 2
	var tune: Dictionary = run["tune"]
	(
		(run["obstacles"] as Array)
		. append(
			{
				"id": 1,
				"kind": "crate",
				"def": (tune["OBSTACLES"] as Dictionary)["crate"],
				"lane": 1,
				"lanes": null,
				"z": -0.2,
				"x": 0.0,
				"halfW": 0.6,
				"telegraphed": false,
				"hit": false,
				"minClear": INF,
				"passed": false,
			}
		)
	)
	var evs := Run.step_run(run, 1.0 / 30.0)
	assert_true(_has_event(evs, "jogStart"))
	assert_true(bool(run["jog"]))
	assert_false(bool(run["ended"]))
	assert_eq((run["obstacles"] as Array).size(), 0)
	assert_almost(Run.current_speed(run), 7.0)


func _has_event(events: Array, type: String) -> bool:
	for e: Dictionary in events:
		if str(e["type"]) == type:
			return true
	return false
