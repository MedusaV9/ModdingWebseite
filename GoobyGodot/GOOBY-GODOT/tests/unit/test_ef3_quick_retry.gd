extends TestCase
## EF-3 F2 (EVAL-1: „Nochmal durchläuft jedes Mal den vollen 3-2-1“):
## Der Neustart aus Results/Pause überspringt den 3-2-1 und zeigt nur ein
## kurzes „GO!“ — der Erststart behält den vollen Countdown, und die faire
## Startbedingung bleibt (frische Spielinstanz, Reset, Energie-Abbuchung).

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const GAME_ID := "carrotCatch"


func test_default_quick_go_ist_etwa_eine_halbe_sekunde() -> void:
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	assert_almost(host.quick_go_sec, 0.5, 0.11, "Quick-GO liegt bei ~0,5 s.")
	assert_almost(host.countdown_step_sec, 0.6, 1e-6, "F4: Countdown-Schritt = 0,6 s.")
	host.free()


func test_erststart_zaehlt_drei_zwei_eins_retry_nicht() -> void:
	var host := _mount_host()
	host.countdown_step_sec = 0.05
	host.quick_go_sec = 0.1
	var erststart_texte := await _collect_countdown_until_active(host)
	assert_true(erststart_texte.has("3"), "Erststart zeigt die 3 (voller Countdown).")
	assert_true(erststart_texte.has(I18nService.t("mg.host.go")), "Erststart endet mit GO.")
	# Runde beenden und „Nochmal“ drücken.
	var game: MinigameBase = host.get("_game")
	game.ctx.report_end({"score": 5})
	await wait_frames(2)
	_refill_energy()
	host._on_again_pressed()
	var retry_texte := await _collect_countdown_until_active(host)
	assert_false(retry_texte.has("3"), "Retry überspringt den 3-2-1 (keine 3).")
	assert_false(retry_texte.has("2"), "Retry überspringt den 3-2-1 (keine 2).")
	assert_true(retry_texte.has(I18nService.t("mg.host.go")), "Retry zeigt das kurze GO.")
	await _unmount(host)


func test_retry_setzt_den_zustand_fair_zurueck() -> void:
	var host := _mount_host()
	host.countdown_step_sec = 0.0
	host.quick_go_sec = 0.05
	var go := await _wait_active(host)
	assert_true(go, "Erststart erreicht GO.")
	var erstes_spiel: MinigameBase = host.get("_game")
	var erster_seed: int = host.run_seed
	host._on_game_score(37, 37)
	var game: MinigameBase = host.get("_game")
	game.ctx.report_end({"score": 37})
	await wait_frames(2)
	assert_true(bool(host.get("_round_over")), "Runde ist vorbei.")
	_refill_energy()
	var energie_vorher := _energy()
	host._on_again_pressed()
	var wieder := await _wait_active(host)
	assert_true(wieder, "Retry erreicht das Spiel.")
	var zweites_spiel: MinigameBase = host.get("_game")
	assert_true(
		zweites_spiel != null and zweites_spiel != erstes_spiel,
		"Frische Spielinstanz (kein Weiterspielen alter Zustände)."
	)
	assert_eq(host.score, 0, "Score ist zurückgesetzt.")
	assert_false(bool(host.get("_round_over")), "Neue Runde läuft.")
	assert_ne(host.run_seed, erster_seed, "Frischer Seed pro Runde.")
	assert_eq((host.get("_coin_chunks") as Array).size(), 0, "Coin-Chunks sind zurückgesetzt.")
	var results: Control = host.get("_results")
	assert_false(results.visible, "Results-Screen ist wieder zu.")
	assert_true(
		_energy() < energie_vorher - 0.5,
		(
			"§C6 bleibt fair: auch die Quick-Runde kostet Energie (%s → %s)."
			% [energie_vorher, _energy()]
		)
	)
	await _unmount(host)


func test_retry_ist_deutlich_schneller_als_erststart() -> void:
	var host := _mount_host()
	# Produktionswerte: 3×0,6 s Countdown vs. 0,5 s Quick-GO.
	var t_erst := Time.get_ticks_msec()
	var go := await _wait_active(host)
	var erststart_ms := Time.get_ticks_msec() - t_erst
	assert_true(go, "Erststart erreicht GO.")
	var game: MinigameBase = host.get("_game")
	game.ctx.report_end({"score": 3})
	await wait_frames(2)
	_refill_energy()
	var t_retry := Time.get_ticks_msec()
	host._on_again_pressed()
	var wieder := await _wait_active(host)
	var retry_ms := Time.get_ticks_msec() - t_retry
	assert_true(wieder, "Retry erreicht das Spiel.")
	assert_true(retry_ms < 1200, "Retry→spielbar unter 1,2 s (war: %d ms)." % retry_ms)
	assert_true(
		retry_ms < erststart_ms - 500,
		"Retry (%d ms) klar schneller als Erststart (%d ms)." % [retry_ms, erststart_ms]
	)
	await _unmount(host)


## ── Helfer (Muster test_fb3_pause_modal) ────────────────────────────────


func _mount_host() -> MinigameHost:
	_refill_energy()
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.receive_params({"game_id": GAME_ID, "difficulty": "normal", "seed": 777})
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


## Sammelt alle Countdown-Label-Texte, bis das Spiel aktiv ist.
func _collect_countdown_until_active(host: MinigameHost) -> Array:
	var texte: Array = []
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var label: Label = host.get("_countdown_label")
		if label != null and label.visible and not texte.has(label.text):
			texte.append(label.text)
		var game: MinigameBase = host.get("_game")
		if game != null and is_instance_valid(game) and game.is_active():
			break
		await tree.process_frame
	return texte


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


func _energy() -> float:
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs == null:
		return 0.0
	return float(gs.get_value("gooby.stats.energy", 0.0))
