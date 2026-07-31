extends TestCase
## W13B/DRIVE — City Drive als Arcade-Runde + ctx.strike()/3-Strikes-Pfad +
## Pregame-Auto-Zeile. Beweise: Manifest-Registrierung, Difficulty-Opt-in
## (Web-Parität bleibt Default), Web-verbatim ARCADE-Zahlen, Bot-Monotonie
## easy < normal < hard PRO Seed, Strike-Pfad (3 Strikes → Runde endet,
## Award trotzdem korrekt, kein Sieg-Moment), Auto-Multiplikatoren im
## Fahrmodell und die Auto-Zeile NUR bei Fahr-Spielen.

const Logic := preload("res://scripts/minigames/games/city_drive/city_drive_logic.gd")
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"


func test_manifest_registrierung() -> void:
	var meta := MinigameRegistry.get_game("cityDrive")
	assert_false(meta.is_empty(), "cityDrive ist über game.json registriert")
	assert_eq(str(meta.get("title_key")), "mg.cityDrive.title")
	assert_eq(str(meta.get("scene")), "res://scripts/minigames/games/city_drive/city_drive.tscn")
	var row: Dictionary = meta.get("coin_table", {})
	assert_eq(int(row.get("max")), 35, "Coin-Deckel = Web COIN_TABLE.cityDrive.max")
	assert_eq(int(row.get("divisor")), 10, "Punkte-Skala ×10 ⇒ /10 = Web-Münzen")
	assert_eq(int(meta.get("energy_cost")), 6, "DRIVE_ENERGY_COST")
	assert_eq(int(meta.get("target")), 280, "§G5.4-Regel: ≈ 80 % vom Cap 350")
	assert_true(bool(meta.get("supports_endless")), "Endlos wird unterstützt")
	assert_true(bool(meta.get("difficulty_opt_in")), "Arcade-Runde hat echte Modi")
	assert_true(
		ResourceLoader.exists(MinigameRegistry.cover_path("cityDrive")), "Cover liegt bereit"
	)


func test_difficulty_opt_in_web_default_bleibt() -> void:
	var meta := MinigameRegistry.get_game("cityDrive")
	# Web-Parität ohne Meta (Golden-Fixtures): cityDrive bleibt exkludiert.
	assert_false(MinigameFrameworkLogic.difficulty_enabled("cityDrive"), "Default = Web")
	assert_true(
		MinigameFrameworkLogic.difficulty_enabled("cityDrive", meta), "Manifest-Opt-in greift"
	)
	assert_eq(
		MinigameFrameworkLogic.effective_difficulty("cityDrive", {"difficulty": "hard"}, meta),
		"hard",
		"Arcade-Launch fährt echte Modi"
	)
	assert_eq(
		MinigameFrameworkLogic.effective_difficulty(
			"cityDrive", {"difficulty": "hard", "mode": "shopTrip"}, meta
		),
		"normal",
		"Trip-Launches (params.mode) bleiben normal"
	)
	assert_eq(
		MinigameFrameworkLogic.effective_difficulty("cityDrive", {"difficulty": "hard"}),
		"normal",
		"ohne Meta bleibt die Web-Semantik"
	)


func test_arcade_zahlen_web_verbatim() -> void:
	var t: Dictionary = Logic.ARCADE
	assert_almost(float(t["DURATION_SEC"]), 90.0, 1e-9, "DRIVE.ARCADE_DURATION_SEC")
	assert_eq(int(t["COINS_ACTIVE"]), 26, "DRIVE_TUNING.ARCADE_COINS_ACTIVE")
	assert_almost(float(t["PICKUP_RADIUS_M"]), 3.0, 1e-9, "DRIVE_TUNING.PICKUP_RADIUS_M")
	assert_almost(float(t["CHECKPOINT_RADIUS_M"]), 4.0, 1e-9, "DRIVE.PARKING_RADIUS")
	assert_almost(float(t["CRASH_SPEED_MULT"]), 0.3, 1e-9, "DRIVE.CRASH_SPEED_MULT")
	assert_almost(float(t["CRASH_INVULN_SEC"]), 2.0, 1e-9, "DRIVE_TUNING.CRASH_INVULN_SEC")
	assert_almost(float(t["BASE_SPEED"]), 9.0, 1e-9, "DRIVE.BASE_SPEED")
	assert_almost(float(t["MAX_SPEED"]), 15.0, 1e-9, "ARCADE_SPEED.MAX_SPEED_MS")
	assert_almost(float(t["RAMP_DELAY_SEC"]), 20.0, 1e-9, "ARCADE_SPEED.RAMP_DELAY_SEC")
	assert_eq(int(t["PICKUP_POINTS"]), 10, "1 Web-Münze × Punkte-Skala 10")
	assert_eq(int(t["ZERO_CRASH_BONUS"]), 50, "DRIVE.ZERO_CRASH_BONUS × 10")
	assert_eq(
		int(t["STRIKE_LIMIT"]),
		MinigameFrameworkLogic.STRIKES_FOR_TELEPORT,
		"DRIVE.CRASHES_FOR_TOW == Strike-Limit des Hosts"
	)


func test_difficulty_hebel() -> void:
	var normal := Logic.apply_difficulty(Logic.ARCADE, "normal")
	assert_almost(float(normal["SPEED_MULT"]), 1.0, 1e-9, "normal = Web-Arcade-Semantik")
	var easy := Logic.apply_difficulty(Logic.ARCADE, "easy")
	assert_almost(float(easy["SPEED_MULT"]), 0.85, 1e-9)
	assert_almost(float(easy["TRAFFIC_DENSITY_MULT"]), 0.85, 1e-9)
	var hard := Logic.apply_difficulty(Logic.ARCADE, "hard")
	assert_almost(float(hard["SPEED_MULT"]), 1.2, 1e-9)
	assert_almost(float(hard["TRAFFIC_DENSITY_MULT"]), 1.15, 1e-9)
	assert_false(bool(hard["ENDLESS"]))
	var endless := Logic.apply_difficulty(Logic.ARCADE, "endless")
	assert_true(bool(endless["ENDLESS"]), "Endlos kappt den Timer")
	assert_false(Logic.round_over(9999.0, endless), "Endlos endet nie über die Uhr")


func test_bot_monoton_und_deterministisch() -> void:
	var target := int(MinigameRegistry.get_game("cityDrive").get("target", 0))
	for seed_value in range(1, 13):
		var easy: Dictionary = Logic.simulate_autoplay(seed_value, "easy")
		var normal: Dictionary = Logic.simulate_autoplay(seed_value, "normal")
		var hard: Dictionary = Logic.simulate_autoplay(seed_value, "hard")
		assert_true(
			int(easy["score"]) < int(normal["score"]),
			"Seed %d: easy < normal (%d/%d)" % [seed_value, easy["score"], normal["score"]]
		)
		assert_true(
			int(normal["score"]) < int(hard["score"]),
			"Seed %d: normal < hard (%d/%d)" % [seed_value, normal["score"], hard["score"]]
		)
		assert_eq(
			Logic.simulate_autoplay(seed_value, "hard"),
			hard,
			"Bot ist deterministisch (Seed %d)" % seed_value
		)
		assert_true(
			int(hard["score"]) >= target,
			(
				"Schwer-Bot schafft das §G5.4-Ziel (Seed %d: %d >= %d)"
				% [seed_value, hard["score"], target]
			)
		)
	assert_eq(int(Logic.simulate_autoplay(3, "easy")["crashes"]), 0, "easy fährt crashfrei")


func test_fahrmodell_und_auto_multiplikatoren() -> void:
	var neutral := Logic.apply_difficulty(Logic.ARCADE, "normal")
	assert_almost(Logic.target_speed(0.0, neutral), 9.0, 1e-9, "Start = BASE_SPEED")
	assert_almost(Logic.target_speed(20.0, neutral), 9.0, 1e-9, "Rampe ruht bis 20 s")
	assert_almost(Logic.target_speed(42.0, neutral), 15.0, 1e-9, "20 + 22 s → MAX 15")
	# Autohaus-Multiplikatoren wirken auf Tempo/Lenkung/Boost — geklemmt.
	var mit_auto := Logic.with_car(neutral, {"speed": 1.09, "handling": 1.05, "boost": 1.09})
	assert_almost(Logic.target_speed(42.0, mit_auto), 15.0 * 1.09, 1e-9, "Tempo × 1.09")
	assert_almost(Logic.steer_rate(mit_auto), 1.9 * 1.05, 1e-9, "Lenkrate × 1.05")
	var v_neutral := Logic.step_speed(0.0, 10.0, 0.5, neutral)
	var v_boost := Logic.step_speed(0.0, 10.0, 0.5, mit_auto)
	assert_true(v_boost > v_neutral, "Boost beschleunigt schneller")
	assert_almost(
		Logic.step_speed(12.0, 6.0, 0.1, mit_auto),
		Logic.step_speed(12.0, 6.0, 0.1, neutral),
		1e-9,
		"Boost wirkt NICHT beim Bremsen"
	)
	var hostile := Logic.with_car(neutral, {"speed": 99.0})
	assert_almost(float(hostile["CAR_SPEED_MULT"]), 1.5, 1e-9, "hostile Multiplikator geklemmt")
	assert_eq(Logic.with_car(neutral, null), neutral, "ohne Auto bleibt alles neutral")


func test_streuung_und_checkpoint_deterministisch() -> void:
	var a := Logic.scatter_coins(GoobyRng.new(7), int(Logic.ARCADE["COINS_ACTIVE"]))
	var b := Logic.scatter_coins(GoobyRng.new(7), int(Logic.ARCADE["COINS_ACTIVE"]))
	assert_eq(a.size(), 26, "26 aktive Münzen")
	assert_eq(a, b, "gleicher Seed ⇒ identische Streuung")
	for coin in a:
		var tile := Logic.world_to_tile(coin.x, coin.y)
		assert_true(Logic.is_road(tile.x, tile.y), "Münze liegt auf der Straße (%s)" % coin)
	for seed_value in range(1, 9):
		var from := Vector2(0.0, 40.0)
		var cp := Logic.next_checkpoint(GoobyRng.new(seed_value), from)
		assert_true(
			from.distance_to(cp) >= Logic.CHECKPOINT_MIN_DIST_M,
			"Checkpoint weit genug weg (Seed %d)" % seed_value
		)
		var tile2 := Logic.world_to_tile(cp.x, cp.y)
		assert_true(Logic.is_road(tile2.x, tile2.y), "Checkpoint liegt auf der Straße")


func test_ctx_strike_fallback_ohne_host() -> void:
	var ctx := MinigameCtx.new()
	var s1 := ctx.strike()
	assert_eq(int(s1["strikes"]), 1)
	assert_false(bool(s1["teleport"]))
	var s2 := ctx.strike()
	assert_eq(int(s2["strikes"]), 2)
	assert_false(bool(s2["teleport"]))
	var s3 := ctx.strike()
	assert_eq(int(s3["strikes"]), 3, "dritter Strike")
	assert_true(bool(s3["teleport"]), "AB dem 3. Strike wird teleportiert")


func test_host_drei_strikes_beenden_runde_mit_award() -> void:
	var host := _mount_host("carrotCatch")
	host.countdown_step_sec = 0.0
	host.quick_go_sec = 0.05
	var aktiv := await _wait_active(host)
	assert_true(aktiv, "Runde läuft")
	var game: MinigameBase = host.get("_game")
	var breakdowns: Array = []
	var momente: Array = []
	host.round_finished.connect(func(b: Dictionary) -> void: breakdowns.append(b))
	host.end_moment_fired.connect(func(kind: String) -> void: momente.append(kind))
	game.ctx.report_score(120, 120)
	var s1 := game.ctx.strike()
	assert_false(bool(s1["teleport"]), "Strike 1 läuft weiter")
	assert_false(bool(host.get("_round_over")), "nach Strike 1 läuft die Runde")
	game.ctx.strike()
	var s3 := game.ctx.strike()
	assert_true(bool(s3["teleport"]), "Strike 3 teleportiert")
	assert_true(bool(host.get("_strike_out")), "Host ist im Cutscene-Zustand")
	var veil: Control = host.get("_strike_veil")
	assert_true(veil != null and veil.visible, "Teleport-Veil steht über dem Spiel")
	assert_true(
		(host.get("_viewport_container") as Node).process_mode == Node.PROCESS_MODE_DISABLED,
		"Spielzeit ist eingefroren (Emotion bleibt im Bild stehen)"
	)
	var vorbei := await wait_until(func() -> bool: return bool(host.get("_round_over")), 6000)
	assert_true(vorbei, "die Runde endet nach der Cutscene")
	assert_eq(breakdowns.size(), 1, "genau ein Award")
	var breakdown: Dictionary = breakdowns[0]
	assert_eq(int(breakdown.get("score", -1)), 120, "Award läuft über den aktuellen Score")
	assert_true(int(breakdown.get("coins", 0)) > 0, "Münzen werden trotz Teleport gebucht")
	await wait_frames(20)
	assert_eq(momente.size(), 0, "KEIN Sieg-/Trost-Moment über dem Teleport-Veil")
	# „Nochmal“ räumt den Strike-Zustand vollständig auf.
	_refill_energy()
	host._on_again_pressed()
	assert_eq(int(host.get("_strikes")), 0, "Strikes sind zurückgesetzt")
	assert_false(bool(host.get("_strike_out")), "Cutscene-Flag ist zurückgesetzt")
	assert_false((host.get("_strike_veil") as Control).visible, "Veil ist wieder weg")
	assert_true(
		(host.get("_viewport_container") as Node).process_mode == Node.PROCESS_MODE_INHERIT,
		"Spielzeit läuft wieder"
	)
	await _unmount(host)


func test_city_drive_szene_smoke() -> void:
	var meta := MinigameRegistry.get_game("cityDrive")
	var game: Node = (load(str(meta["scene"])) as PackedScene).instantiate()
	var ctx := MinigameCtx.new()
	ctx.game_id = "cityDrive"
	ctx.difficulty = "normal"
	ctx.run_seed = 4242
	ctx.car = {
		"id": "suv",
		"glb": "suv.glb",
		"farbe": "#4FBF8B",
		"stats": {"speed": 4, "handling": 7, "boost": 5},
		"mults": CarStatsLogic.multipliers({"speed": 4, "handling": 7, "boost": 5}),
	}
	var ergebnisse: Array = []
	ctx.on_end = func(result: Dictionary) -> void: ergebnisse.append(result)
	tree.root.add_child(game)
	game.call("setup", ctx)
	await wait_frames(1)
	game.call("start")
	# Sofort pausieren: die Regel-Aufrufe unten bleiben deterministisch,
	# ohne dass _process-Ticks (Verkehr!) dazwischenfunken.
	game.call("pause")
	await wait_frames(2)
	assert_eq((game.get("_coins") as Array).size(), 26, "26 aktive Münzen in der Szene")
	assert_almost(
		float((game.get("tune") as Dictionary)["CAR_SPEED_MULT"]),
		CarStatsLogic.speed_mult({"speed": 4}),
		1e-9,
		"ctx.car-Multiplikator steckt im Fahr-Tuning"
	)
	# Münze einsammeln: +10, Respawn hält die aktive Zahl konstant.
	var coins: Array = game.get("_coins")
	coins[0] = game.get("van_pos")
	game.call("_check_pickups")
	assert_eq(int(game.get("score")), 10, "Pickup = +10 Punkte (1 Web-Münze)")
	assert_eq(int(game.get("pickups")), 1)
	assert_eq((game.get("_coins") as Array).size(), 26, "Respawn hält 26 aktiv")
	# Checkpoint: +30 und ein frisches Ziel.
	game.set("_checkpoint", game.get("van_pos"))
	game.call("_check_checkpoint")
	assert_eq(int(game.get("score")), 40, "Checkpoint = +30")
	var neues_ziel: Vector2 = game.get("_checkpoint")
	assert_true(
		(game.get("van_pos") as Vector2).distance_to(neues_ziel) > 1.0, "frischer Checkpoint"
	)
	# Crash = Strike (ctx-Fallback ohne Host): der 3. meldet Teleport.
	for i in 3:
		game.set("_crash_cool", 0.0)
		game.call("_crash")
	assert_eq(int(game.get("crashes")), 3, "drei Crashes gezählt")
	assert_true(bool(ctx._local_strikes >= 3), "jeder Crash war ein Strike")
	# Zeit abgelaufen: report_end mit dem Score (Crashes ⇒ kein Bonus).
	game.set("elapsed", 90.5)
	game.call("_finish_time_up")
	assert_eq(ergebnisse.size(), 1, "genau ein report_end")
	assert_eq(int((ergebnisse[0] as Dictionary).get("score")), 40, "Score ohne Null-Crash-Bonus")
	game.queue_free()
	await wait_frames(1)


func test_pregame_auto_zeile_nur_bei_fahr_spielen() -> void:
	var stub := StubState.new()
	stub.data = {
		"city": {"autos": {"hatchback-sports": "#F2C14E"}, "aktivesAuto": "hatchback-sports"}
	}
	var pre := MinigamePregame.new()
	pre.auto_navigate = false
	pre.state_node = stub
	pre.receive_params({"game_id": "cityDrive"})
	tree.root.add_child(pre)
	await wait_frames(1)
	var line: Label = pre.find_child("CarLine", true, false)
	assert_true(line != null, "Fahr-Spiel zeigt die Auto-Zeile")
	assert_true(line.text.contains("Flitzgooby GT"), "GEWÄHLTES Auto steht in der Zeile")
	assert_true(line.text.contains("▮"), "Tempo-Balken stehen in der Zeile")
	pre.queue_free()
	await wait_frames(1)
	var pre2 := MinigamePregame.new()
	pre2.auto_navigate = false
	pre2.state_node = stub
	pre2.receive_params({"game_id": "teaParty"})
	tree.root.add_child(pre2)
	await wait_frames(1)
	assert_true(
		pre2.find_child("CarLine", true, false) == null, "Nicht-Fahr-Spiel bleibt ohne Zeile"
	)
	pre2.queue_free()
	await wait_frames(1)
	stub.free()


## ── Helfer (Muster test_ef3_quick_retry) ────────────────────────────────


func _mount_host(game_id: String) -> MinigameHost:
	_refill_energy()
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.receive_params({"game_id": game_id, "difficulty": "normal", "seed": 777})
	tree.root.add_child(host)
	return host


func _unmount(host: MinigameHost) -> void:
	host.queue_free()
	await wait_frames(2)


func _wait_active(host: MinigameHost) -> bool:
	return await wait_until(
		func() -> bool:
			var game: MinigameBase = host.get("_game")
			return game != null and is_instance_valid(game) and game.is_active(),
		8000
	)


func _refill_energy() -> void:
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("update"):
		return
	gs.update(
		func(state: Dictionary) -> void:
			var gooby: Variant = state.get("gooby")
			if gooby is Dictionary and (gooby as Dictionary).get("stats") is Dictionary:
				((gooby as Dictionary)["stats"] as Dictionary)["energy"] = 100.0
	)


## Minimaler GameState-Stub (get_value-Pfadleser wie das Original).
class StubState:
	extends Node
	var data: Dictionary = {}

	func state() -> Dictionary:
		return data

	func update(mutator: Callable) -> void:
		mutator.call(data)

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var cur: Variant = data
		for part in path.split("."):
			if cur is Dictionary and (cur as Dictionary).has(part):
				cur = cur[part]
			else:
				return fallback
		return cur
