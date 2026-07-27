extends TestCase
## EF-3 F3 (EVAL-1: „0,9 s toter Standbild-Moment am Rundenende — nur 5/37
## Spiele rufen win_moment()“): der HOST inszeniert das Rundenende jetzt
## zentral. Sieg → win_moment (Zeitlupe/Goldblitz/Konfetti), 0 Punkte →
## weicher Trost-Moment; Spiele, die selbst feiern, feuern NICHT doppelt.
## Damit profitieren alle Spiele, ohne dass Spieldateien angefasst werden.

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const GAME_ID := "carrotCatch"


func test_sieg_fuellt_die_atempause_automatisch() -> void:
	var host := await _mount_and_start()
	var momente: Array = []
	var results_sichtbar_beim_moment: Array = []
	host.end_moment_fired.connect(
		func(kind: String) -> void:
			momente.append(kind)
			results_sichtbar_beim_moment.append((host.get("_results") as Control).visible)
	)
	var game: MinigameBase = host.get("_game")
	game.ctx.report_end({"score": 42})
	var kam := await wait_until(func() -> bool: return momente.size() == 1, 3000)
	assert_true(kam, "End-Moment feuert automatisch (Spiel ruft selbst nichts).")
	assert_eq(momente, ["win"] as Array, "Score > 0 = Sieg-Moment.")
	assert_eq(
		results_sichtbar_beim_moment,
		[false] as Array,
		"Der Moment füllt die LÜCKE (vor dem Results-Screen)."
	)
	assert_true(Engine.time_scale < 1.0, "Sieg-Zeitlupe läuft direkt nach dem Moment.")
	var results_da := await wait_until(
		func() -> bool: return (host.get("_results") as Control).visible, 4000
	)
	assert_true(results_da, "Results kommen nach der (gefüllten) Atempause.")
	assert_almost(Engine.time_scale, 1.0, 1e-4, "Zeitlupe ist bis Results wieder vorbei.")
	await _unmount(host)


func test_null_punkte_bekommen_trost_statt_konfetti() -> void:
	var host := await _mount_and_start()
	var momente: Array = []
	host.end_moment_fired.connect(func(kind: String) -> void: momente.append(kind))
	var game: MinigameBase = host.get("_game")
	game.ctx.report_end({"score": 0})
	var kam := await wait_until(func() -> bool: return momente.size() == 1, 3000)
	assert_true(kam, "Auch die Niederlage bekommt einen Moment.")
	assert_eq(momente, ["lose"] as Array, "0 Punkte = Trost-Moment.")
	await wait_until(func() -> bool: return (host.get("_results") as Control).visible, 4000)
	await _unmount(host)


func test_selbst_feiernde_spiele_feuern_nicht_doppelt() -> void:
	var host := await _mount_and_start()
	var momente: Array = []
	host.end_moment_fired.connect(func(kind: String) -> void: momente.append(kind))
	# Wie die 5 Selbst-Feierer (delivery_rush & Co.): win_moment direkt am Ende.
	host.juice.win_moment()
	var game: MinigameBase = host.get("_game")
	game.ctx.report_end({"score": 99})
	await wait_until(func() -> bool: return (host.get("_results") as Control).visible, 4000)
	assert_eq(momente, [] as Array, "Spieleigener win_moment unterdrückt den Auto-Moment.")
	await _unmount(host)


func test_reduced_motion_zeigt_results_sofort_ohne_moment() -> void:
	var war_reduziert := _set_reduced_motion(true)
	var host := await _mount_and_start()
	var momente: Array = []
	host.end_moment_fired.connect(func(kind: String) -> void: momente.append(kind))
	var game: MinigameBase = host.get("_game")
	game.ctx.report_end({"score": 12})
	await wait_frames(3)
	assert_true((host.get("_results") as Control).visible, "Reduced Motion: Results sofort da.")
	await wait_until(func() -> bool: return false, 400)
	assert_eq(momente, [] as Array, "Reduced Motion: kein nachgeschobener Effekt-Moment.")
	await _unmount(host)
	_set_reduced_motion(war_reduziert)
	await wait_frames(1)


func test_juicekit_merkt_sich_den_letzten_moment() -> void:
	var kit := JuiceKit.new()
	tree.root.add_child(kit)
	await wait_frames(1)
	assert_true(
		Time.get_ticks_msec() - kit.win_moment_msec > 100_000, "Frisches Kit: lange kein Moment."
	)
	kit.win_moment()
	assert_true(Time.get_ticks_msec() - kit.win_moment_msec <= 50, "win_moment stempelt die Zeit.")
	var zurueck := await wait_until(
		func() -> bool: return is_equal_approx(Engine.time_scale, 1.0), 2000
	)
	assert_true(zurueck, "time_scale kehrt nach win_moment zurück.")
	kit.lose_moment()
	assert_true(
		Time.get_ticks_msec() - kit.win_moment_msec <= 50, "lose_moment stempelt ebenfalls."
	)
	zurueck = await wait_until(func() -> bool: return is_equal_approx(Engine.time_scale, 1.0), 2000)
	assert_true(zurueck, "time_scale kehrt nach lose_moment zurück.")
	kit.queue_free()
	Engine.time_scale = 1.0
	await wait_frames(1)


## ── Helfer ──────────────────────────────────────────────────────────────


func _mount_and_start() -> MinigameHost:
	_refill_energy()
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.quick_go_sec = 0.0
	host.receive_params({"game_id": GAME_ID, "difficulty": "normal", "seed": 4711})
	tree.root.add_child(host)
	await wait_until(
		func() -> bool:
			var game: MinigameBase = host.get("_game")
			return game != null and is_instance_valid(game) and game.is_active(),
		8000
	)
	return host


func _unmount(host: MinigameHost) -> void:
	host.queue_free()
	Engine.time_scale = 1.0
	await wait_frames(2)


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


func _set_reduced_motion(enabled: bool) -> bool:
	var settings := tree.root.get_node_or_null("AppSettings")
	if settings == null:
		return false
	var vorher := bool(settings.is_reduced_motion())
	settings.set_setting("reduced_motion", enabled)
	return vorher
